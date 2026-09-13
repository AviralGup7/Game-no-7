extends Node
## Headless runtime harness for the shipping Station Zero campaign (audit work
## item #7, docs/CODE_QUALITY_AUDIT_2026-09-12.md): instantiate the real world,
## assert imported meshes (not fallback boxes), traverse every objective,
## simulate a save-write failure, and repeat pause/map/back/checkpoint
## transitions. It drives the shipping scene and the real controllers — no
## Python copy of the campaign rules.
##
## Determinism contract: the engine never ticks the mission logic. The
## director's _physics_process is driven with fixed-delta calls (or frozen)
## and encounter streaming stays off, so frame order is explicit and every
## assertion measures a value (diagnostic count, state, node count, save
## bytes) instead of hoping.
##
## Loaded at runtime by tests/run_tests.gd (deferred phase, embedded) or by
## tests/run_campaign_runtime.gd (standalone headless entry, isolated profile).
## This file must never terminate the process: the embedding SceneTree owns
## process exit, so both entries can stop or keep driving other work.

const CYCLE_COUNT := 20
const KILL_DAMAGE := 100000.0
## Fixed-delta driving of CampaignDirector._physics_process: the partial tick
## is below the update interval, the resume tick lands exactly on it.
const PARTIAL_TICK := 0.1
const RESUME_TICK := CampaignDirector.UPDATE_INTERVAL - PARTIAL_TICK
## Authored rest pads used to alternate the checkpoint drill.
const CHECKPOINT_ALT := "transit"
const CHECKPOINT_HOME := "docks"
## First mission whose console is guarded by live authored enemies.
const GUARDED_MISSION_INDEX := 2
## Distinct authored defeats before the checkpoint-retry persistence drill.
const PERSISTENCE_KILL_COUNT := 5
## Authored station grid: 864 m / 4 m x 672 m / 4 m (data/campaign/station_zero.json).
const NAV_CELL_COUNT := 36288
## Authored content: 17 story objectives plus the extraction shuttle.
const STORY_OBJECTIVE_TARGETS := 17
const EXTRACTION_TARGETS := 1

var _checks := 0
var _failed_count := 0
var _cases: Array[Dictionary] = []
var _error_diags: Array[String] = []
var _window_warnings: Array[String] = []
var _window_messages: Array[String] = []
var _diagnostic_window := false
var _finished := false
var _aborted := false
var _game: CampaignGame = null
var _session: CampaignDirector = null


func _ready() -> void:
	_run.call_deferred()


## ---------- entry-owned surface (runner + standalone entry poll these) ----------

func is_finished() -> bool:
	return _finished


func get_cases() -> Array:
	return _cases


func get_report_line() -> String:
	return "CAMPAIGN RUNTIME: %d checks, %d failed" % [_checks, _failed_count]


## ---------- case plumbing ----------

func _case(title: String, ok: bool, why: String = "") -> void:
	_checks += 1
	if ok:
		_cases.append({"name": title, "passed": true, "why": ""})
		return
	_failed_count += 1
	_cases.append({"name": title, "passed": false, "why": why if why != "" else title})
	push_error("CAMPAIGN RUNTIME FAIL: %s" % title)


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _on_diagnostic(message: String, severity: StringName) -> void:
	if severity == &"error":
		_error_diags.append(message)
	elif _diagnostic_window and severity == &"warning":
		_window_warnings.append(message)


func _on_director_message(text: String) -> void:
	if _diagnostic_window:
		_window_messages.append(text)


## ---------- run ----------

func _run() -> void:
	EventBus.diagnostic.connect(_on_diagnostic)
	await _stage_boot()
	if not _aborted:
		await _stage_save_failure()
	if not _aborted:
		await _stage_transition_cycles()
	if not _aborted:
		await _stage_defeat_persistence()
	if not _aborted:
		await _stage_story()
	_case("no campaign error diagnostics", _error_diags.is_empty(), str(_error_diags))
	_finished = true


func _stage_boot() -> void:
	var main_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	_case("project boots the campaign scene",
		main_scene == "res://scenes/campaign/station_zero.tscn", main_scene)
	get_tree().change_scene_to_file(main_scene)
	await _frames(5)
	_game = get_tree().current_scene as CampaignGame
	_case("shipping controller instantiated", _game != null)
	if _game == null:
		_aborted = true
		return
	_case("campaign menu is the initial screen",
		_game.get_campaign_ui().get_debug_snapshot().get("screen", "") == "menu")
	_case("GameRoot starts at the main menu",
		GameRoot.get_current_state() == GameRoot.State.MAIN_MENU,
		String(GameRoot.get_current_state()))
	GameRoot.start_campaign(true)
	await _frames(5)
	_capture_session()
	_case("new campaign reaches PLAYING",
		GameRoot.get_current_state() == GameRoot.State.PLAYING)
	if _session == null:
		_aborted = true
		return
	_case("campaign has no Arena or WaveManager",
		get_tree().get_nodes_in_group("arena").is_empty()
		and _game.find_children("WaveManager", "", true, false).is_empty())
	_case("checkpoint spawns player on an authored deck",
		_session.world.point_is_on_floor(_session.player.global_position))
	await _stage_world_meshes()


func _capture_session() -> void:
	# request_restart() rebuilds the whole scene: re-capture the controller
	# from the live tree so this never touches a freed instance.
	var scene := get_tree().current_scene
	if scene is CampaignGame:
		_game = scene
	_session = _game.get_campaign_director()
	_case("campaign director exists", _session != null)
	if _session == null:
		return
	# The harness owns mission ticks explicitly (fixed-delta calls) while real
	# player physics, UI and audio keep running. Encounter streaming and the
	# automatic quality governor are frozen with it so node counts stay
	# deterministic across the transition-cycle drill.
	_session.set_physics_process(false)
	_session.encounters.set_process(false)
	if is_instance_valid(_game._monitor):
		_game._monitor.set_process(false)
	_session.message.connect(_on_director_message)


## ---------- (a) world + imported meshes, counted fallback diagnostics ----------

func _stage_world_meshes() -> void:
	var modules: Array = [
		CampaignGeometry.GROUND_MILITARY, CampaignGeometry.GROUND_HAZARD, CampaignGeometry.GROUND_TECH,
		CampaignGeometry.WALL_MILITARY, CampaignGeometry.WALL_HAZARD, CampaignGeometry.WALL_TECH,
		CampaignGeometry.WALL_RUSTED,
	]
	var module_failures: Array[String] = []
	for module in modules:
		var name := String((module as PackedScene).resource_path).get_file()
		var root := (module as PackedScene).instantiate()
		var instance := _find_mesh_instance(root)
		var imported := instance != null and instance.mesh != null and instance.mesh is not BoxMesh \
			and instance.mesh.get_surface_count() > 0 and instance.mesh.get_aabb().get_volume() > 0.0
		if not imported:
			module_failures.append(name)
		root.free()
	_case("every environment module ships an imported mesh", module_failures.is_empty(),
		str(module_failures))
	var world := _session.world
	var batches := world.find_children("*", "MultiMeshInstance3D", true, false)
	var rails := _child_named(world, "PerimeterRails")
	var rail_batches := 0
	var wall_fallback_boxes := 0
	if rails != null:
		rail_batches = rails.find_children("*", "MultiMeshInstance3D", true, false).size()
		for box in rails.find_children("*", "MeshInstance3D", true, false):
			if (box as MeshInstance3D).mesh is BoxMesh:
				wall_fallback_boxes += 1
	var floor_batches := int(batches.size()) - rail_batches
	var expected_floor_batches := int(_session.definition.floors.size())
	var fallback_batches := 0
	for batch in batches:
		var instance := batch as MultiMeshInstance3D
		var mesh: Mesh = instance.multimesh.mesh if instance.multimesh != null else null
		if mesh == null or mesh is BoxMesh:
			fallback_batches += 1
	_case("every module batch uses an imported mesh", fallback_batches == 0,
		"%d of %d batches fell back to boxes" % [fallback_batches, int(batches.size())])
	_case("floor batch count matches the authored regions",
		floor_batches == expected_floor_batches,
		"%d floor batches for %d regions" % [floor_batches, expected_floor_batches])
	_case("perimeter rails render as batched walls", rail_batches >= 4,
		"%d wall batches" % rail_batches)
	# The geometry fallback path's observable output is a box where an imported
	# module should be; counting both signatures is the diagnostic count.
	_case("zero geometry fallback diagnostics",
		fallback_batches == 0 and wall_fallback_boxes == 0,
		"measured %d fallback batches + %d fallback wall boxes" % [fallback_batches, wall_fallback_boxes])
	var authored_solids := expected_floor_batches + int(_session.definition.props.size())
	var colliders := 0
	var collision := _child_named(world, "StaticCollision")
	if collision != null:
		colliders = collision.find_children("*", "StaticBody3D", true, false).size()
	_case("static collision covers every authored region, prop and rail",
		colliders == authored_solids + rail_batches + wall_fallback_boxes,
		"%d colliders vs %d authored + %d rail segments" % [colliders, authored_solids, rail_batches])
	var snapshot := world.get_debug_snapshot()
	var navigation: Dictionary = snapshot.get("navigation", {})
	_case("navigation grid is built", bool(navigation.get("built", false)))
	_case("navigation grid covers the authored station",
		int(navigation.get("cells", 0)) == NAV_CELL_COUNT,
		"%d cells" % int(navigation.get("cells", 0)))
	var visible: Array = snapshot.get("visible_districts", [])
	_case("streaming starts within the visible-sector budget",
		visible.size() >= 1 and visible.size() <= int(_session.definition.max_visible_sectors),
		str(visible))


## ---------- (c) save-write failure: rollback, retryability, no corruption ----------

func _stage_save_failure() -> void:
	var baseline := _read_file_text(SaveManager.SAVE_PATH)
	_case("baseline campaign save exists on disk", baseline != "",
		"save file missing before the failure drill")
	var checkpoint_before := String(_session.progress.checkpoint)
	_case("checkpoint baseline is the start sector", checkpoint_before == CHECKPOINT_HOME,
		checkpoint_before)
	var progress_before := _progress_fingerprint()
	# Block the commit point: the temp write-open fails before any byte is
	# touched, so the primary save must stay byte-identical.
	var block_target := ProjectSettings.globalize_path(SaveManager.SAVE_PATH) + ".tmp"
	if not _make_tmp_block(block_target):
		_case("save write failure can be simulated", false,
			"could not block the commit path at " + block_target)
		_aborted = true
		return
	var at := _session.definition.sector(CHECKPOINT_ALT).checkpoint
	_teleport(at)
	_diagnostic_window = true
	_session._physics_process(CampaignDirector.UPDATE_INTERVAL)
	_diagnostic_window = false
	_case("failed save emits exactly one actionable diagnostic",
		_window_warnings.size() == 1 and _window_warnings[0].find("temporary save") != -1,
		str(_window_warnings))
	_case("failed checkpoint save does not advance the checkpoint",
		String(_session.progress.checkpoint) == checkpoint_before,
		"checkpoint moved to " + String(_session.progress.checkpoint))
	_case("failed checkpoint save stays immediately retryable", _session._checkpoint_inside.is_empty())
	_case("failed save pauses the run with a save dialog",
		GameRoot.get_current_state() == GameRoot.State.PAUSED
		and _game.get_campaign_ui().get_debug_snapshot().get("modal", false) == true,
		String(GameRoot.get_current_state()))
	_case("failed save reports the retry through the director message",
		"Restored health. Saving failed — checkpoint not advanced; retry here." in _window_messages,
		str(_window_messages))
	_case("rest pad still heals on the failed visit",
		is_equal_approx(_session.player.get_health_component().get_health_ratio(), 1.0))
	_case("failed save leaves the on-disk save byte-identical",
		_read_file_text(SaveManager.SAVE_PATH) == baseline)
	_case("failed save leaves no temporary file behind",
		not FileAccess.file_exists(block_target))
	_case("store keeps the pre-failure checkpoint in memory",
		String(SaveManager.get_campaign().get("checkpoint", "")) == checkpoint_before)
	# The failed commit leaves a retryable pending transaction carrying the
	# rolled-back state; the next tick must recover from it.
	var pending := SaveManager.peek_pending_profile_transaction()
	var pending_doc: Variant = pending.get("campaign", {})
	var pending_checkpoint := ""
	if pending_doc is Dictionary:
		pending_checkpoint = String((pending_doc as Dictionary).get("checkpoint", ""))
	_case("failed commit leaves a retryable pending transaction",
		SaveManager.has_pending_profile_transaction() and pending_checkpoint == checkpoint_before,
		"pending checkpoint " + pending_checkpoint)
	# Immediate retry: close the dialog, resume, unblock the commit.
	_game.get_campaign_ui()._modal.cancel_all()
	GameRoot.request_resume()
	_case("resume from the save dialog",
		GameRoot.get_current_state() == GameRoot.State.PLAYING and not get_tree().paused)
	if DirAccess.dir_exists_absolute(block_target):
		DirAccess.remove_absolute(block_target)
	# The first tick after unblock is consumed by the pending retry: it
	# restores the staged state and persists the rolled-back slice.
	_diagnostic_window = true
	_session._physics_process(CampaignDirector.UPDATE_INTERVAL)
	_diagnostic_window = false
	_case("pending transaction retries on the first tick",
		not SaveManager.has_pending_profile_transaction())
	_case("pending retry announces the recovered save",
		"Progress saved." in _window_messages, str(_window_messages))
	var retry_disk := JsonHelpers.load_dict(SaveManager.SAVE_PATH)
	var retry_doc: Variant = retry_disk.get("campaign", {})
	var retry_checkpoint := ""
	if retry_doc is Dictionary:
		retry_checkpoint = String((retry_doc as Dictionary).get("checkpoint", ""))
	_case("pending retry commits the rolled-back state", retry_checkpoint == checkpoint_before,
		retry_checkpoint)
	# Now the actual rest-visit retry on the same pad.
	_teleport(at)
	_session._physics_process(CampaignDirector.UPDATE_INTERVAL)
	_case("checkpoint advances on the immediate retry",
		String(_session.progress.checkpoint) == CHECKPOINT_ALT
		and _session._checkpoint_inside == CHECKPOINT_ALT,
		"checkpoint " + String(_session.progress.checkpoint)
		+ " / inside " + _session._checkpoint_inside)
	var disk := JsonHelpers.load_dict(SaveManager.SAVE_PATH)
	var campaign_doc: Variant = disk.get("campaign", {})
	var disk_checkpoint := ""
	if campaign_doc is Dictionary:
		disk_checkpoint = String((campaign_doc as Dictionary).get("checkpoint", ""))
	_case("retry persists the new checkpoint to disk", disk_checkpoint == CHECKPOINT_ALT,
		disk_checkpoint)
	_case("failed save corrupted no mission progress", _progress_fingerprint() == progress_before,
		"before " + progress_before + " / after " + _progress_fingerprint())


func _make_tmp_block(block_target: String) -> bool:
	if DirAccess.dir_exists_absolute(block_target):
		return true
	return DirAccess.make_dir_absolute(block_target) == OK


## Mission-progress signature. The checkpoint is intentionally excluded: a
## successful (c) retry is expected to move it, everything else must not.
func _progress_fingerprint() -> String:
	var p := _session.progress
	return "%d|%s|%s|%d|%d" % [
		int(p.mission),
		str(p.defeated),
		str(p.interacted),
		int(p.xp),
		SaveManager.get_meta_wallet(),
	]


func _read_file_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## ---------- (d) repeated pause -> map -> back -> checkpoint transitions ----------

func _stage_transition_cycles() -> void:
	await _frames(2)
	var ui := _game.get_campaign_ui()
	var previous := String(_session.progress.checkpoint)
	# Warmup cycle: one-time node creation (music beds, first draws) settles
	# before the leak baseline is taken.
	await _cycle("warmup", _expected_checkpoint(previous), ui)
	await _frames(2)
	var baseline_nodes: int = get_tree().root.get_node_count()
	for cycle in range(CYCLE_COUNT):
		var label := "cycle %d" % (cycle + 1)
		var expect := _expected_checkpoint(previous)
		await _cycle(label, expect, ui)
		await _frames(2)
		var nodes: int = get_tree().root.get_node_count()
		_case(label + " / no node leak (%d nodes)" % nodes, nodes == baseline_nodes,
			"baseline %d" % baseline_nodes)
		previous = expect


func _expected_checkpoint(previous: String) -> String:
	return CHECKPOINT_ALT if previous != CHECKPOINT_ALT else CHECKPOINT_HOME


func _cycle(label: String, expect: String, ui: CampaignUI) -> void:
	# 1. Pause: the tree pauses, the pause screen shows, sim clock freezes.
	GameRoot.request_pause()
	_case(label + " / pause reaches PAUSED",
		GameRoot.get_current_state() == GameRoot.State.PAUSED and get_tree().paused)
	_case(label + " / pause screen shows",
		ui.get_debug_snapshot().get("screen", "") == "pause")
	var clock_frozen := _session._clock
	_session._physics_process(0.0166)
	_session._physics_process(0.0166)
	_case(label + " / paused tick freezes the sim clock",
		is_equal_approx(_session._clock, clock_frozen),
		"clock %s" % _session._clock)
	# 2. Map from the pause screen.
	ui.open_map()
	_case(label + " / map opens while paused",
		ui.get_debug_snapshot().get("screen", "") == "map"
		and GameRoot.get_current_state() == GameRoot.State.PAUSED)
	# 3. Back to pause, 4. back to resume.
	ui._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_case(label + " / back returns to pause",
		ui.get_debug_snapshot().get("screen", "") == "pause"
		and GameRoot.get_current_state() == GameRoot.State.PAUSED)
	ui._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_case(label + " / second back resumes the run",
		GameRoot.get_current_state() == GameRoot.State.PLAYING
		and not get_tree().paused
		and ui.get_debug_snapshot().get("screen", "") == "playing")
	# 5. Checkpoint visit, time-gated by the director's update interval.
	var at := _session.definition.sector(expect).checkpoint
	_teleport(at)
	_session._physics_process(PARTIAL_TICK)
	_case(label + " / checkpoint visit waits for the update interval",
		is_equal_approx(_session._clock, PARTIAL_TICK)
		and String(_session.progress.checkpoint) != expect,
		"clock %s / checkpoint %s" % [_session._clock, String(_session.progress.checkpoint)])
	_session._physics_process(RESUME_TICK)
	_case(label + " / checkpoint saves at %s on the full tick" % expect,
		String(_session.progress.checkpoint) == expect,
		"checkpoint " + String(_session.progress.checkpoint))
	_case(label + " / simulation resumes exactly",
		_session.player.global_position.is_equal_approx(at),
		"player at " + str(_session.player.global_position))
	var root := GameRoot.get_debug_snapshot()
	_case(label + " / transition lock is clear",
		bool(root.get("transition_in_progress", true)) == false
		and String(root.get("pending_state", "")) == "",
		"pending " + String(root.get("pending_state", "")))


## ---------- (e) defeat persistence across a checkpoint retry ----------

func _stage_defeat_persistence() -> void:
	var members: Array[CampaignMember] = []
	for member in _session.definition.encounter("transit_guards").members:
		members.append(member)
	for member in _session.definition.encounter("dock_patrol").members:
		members.append(member)
	members = members.slice(0, PERSISTENCE_KILL_COUNT)
	var expected: Array[String] = []
	for member in members:
		expected.append(member.id)
		_kill(member)
	# Kill rewards (XP + enemy credits) are banked in-memory; the restart must
	# load exactly that state, granting nothing a second time.
	var xp_after_kills := _session.player.get_experience_component().total_xp_earned()
	var wallet_after_kills := SaveManager.get_meta_wallet()
	GameRoot.request_restart()
	await _frames(5)
	_capture_session()
	_case("retry reboots the session at PLAYING",
		_session != null and GameRoot.get_current_state() == GameRoot.State.PLAYING)
	if _session == null:
		_aborted = true
		return
	var preserved := true
	for id in expected:
		preserved = preserved and (id in _session.progress.defeated)
	_case("defeated set survives checkpoint retry", preserved,
		"expected %s / live %s" % [str(expected), str(_session.progress.defeated)])
	var checkpoint := _session.definition.sector(String(_session.progress.checkpoint)).checkpoint
	var spawn := _session.player.global_position
	_case("retry spawns at the saved checkpoint",
		absf(spawn.x - checkpoint.x) < 0.5 and absf(spawn.z - checkpoint.z) < 0.5
		and _session.world.point_is_on_floor(spawn),
		"spawn %s / checkpoint %s" % [str(spawn), str(checkpoint)])
	for member in members:
		_case("cleared actor cannot respawn / " + member.id,
			not _session.encounters._spawn(member))
	_case("retry does not re-grant XP",
		_session.player.get_experience_component().total_xp_earned() == xp_after_kills,
		"before %s / after %s" % [xp_after_kills, _session.player.get_experience_component().total_xp_earned()])
	_case("retry does not re-bank enemy credits",
		SaveManager.get_meta_wallet() == wallet_after_kills,
		"before %s / after %s" % [wallet_after_kills, SaveManager.get_meta_wallet()])
	await _frames(3)


## ---------- (b) traverse all 13 missions, 17 story objectives + extraction ----------

func _stage_story() -> void:
	var missions: Array[CampaignMission] = _session.definition.missions
	var total_targets := 0
	for mission in missions:
		total_targets += int(mission.targets.size())
	for index in range(int(missions.size())):
		var mission: CampaignMission = missions[index]
		var targets: Array[String] = mission.targets
		if index == GUARDED_MISSION_INDEX:
			# Prove the requirement gate before clearing it.
			var first := _session.definition.interaction(String(targets[0]))
			_teleport(first.at)
			_case("guarded console refuses early interaction", not _session.try_interact())
		for encounter_id in mission.requires:
			for member in _session.definition.encounter(String(encounter_id)).members:
				if member.id not in _session.progress.defeated:
					_kill(member)
		for raw_id in targets:
			var id := String(raw_id)
			var item := _session.definition.interaction(id)
			_teleport(item.at)
			var is_final := id == String(targets[targets.size() - 1])
			if is_final:
				var reward: CampaignReward = mission.reward
				var wallet_before := SaveManager.get_meta_wallet()
				var xp_before := _session.player.get_experience_component().total_xp_earned()
				_case("story interaction / " + id, _session.try_interact())
				_case("mission advances once / " + String(mission.id),
					int(_session.progress.mission) == index + 1,
					"cursor at " + str(_session.progress.mission))
				_case("mission grants the authored checkpoint / " + String(mission.id),
					String(_session.progress.checkpoint) == String(mission.sector),
					"checkpoint " + String(_session.progress.checkpoint))
				_case("mission credits bank exactly once / " + String(mission.id),
					SaveManager.get_meta_wallet() == wallet_before + int(reward.credits))
				_case("mission xp granted exactly once / " + String(mission.id),
					_session.player.get_experience_component().total_xp_earned()
					== xp_before + int(reward.xp))
				var upgrade := String(reward.upgrade)
				if upgrade != "":
					var stacks := _session.player.get_progression_component().get_progression_snapshot()
					_case("upgrade reward applied / " + upgrade, int(stacks.get(upgrade, 0)) > 0,
						str(stacks))
				var weapon := String(reward.weapon)
				if weapon != "":
					_case("weapon reward available / " + weapon,
						StringName(weapon) in _session.available_weapons())
			else:
				_case("story interaction / " + id, _session.try_interact())
				_case("multi-target mission stays pending / " + id,
					int(_session.progress.mission) == index,
					"cursor at " + str(_session.progress.mission))
		# One supply cache per visited sector, once.
		var cache := _session.definition.interaction("supply_" + String(mission.sector))
		if cache != null and String(cache.id) not in _session.progress.interacted:
			_teleport(cache.at)
			var cache_before := SaveManager.get_meta_wallet()
			_case("supply cache pays once / " + String(cache.id), _session.try_interact())
			_case("supply cache cannot be farmed / " + String(cache.id),
				not _session.try_interact())
			_case("supply cache credits banked / " + String(cache.id),
				SaveManager.get_meta_wallet() == cache_before + int(cache.credits))
	var missing: Array[String] = []
	var extraction_targets := 0
	for mission in missions:
		for raw_id in mission.targets:
			var id := String(raw_id)
			if String(_session.definition.interaction(id).kind) == "extraction":
				extraction_targets += 1
			if id not in _session.progress.interacted:
				missing.append(id)
	_case("%d story objectives plus the extraction are all complete" \
		% (STORY_OBJECTIVE_TARGETS + EXTRACTION_TARGETS),
		missing.is_empty() and total_targets == STORY_OBJECTIVE_TARGETS + EXTRACTION_TARGETS \
		and extraction_targets == EXTRACTION_TARGETS,
		"missing %s / %d targets / %d extraction" % [str(missing), total_targets, extraction_targets])
	_case("extraction reaches campaign victory",
		GameRoot.get_current_state() == GameRoot.State.GAME_OVER and GameRoot.get_run().victory)
	_case("completion persists", bool(SaveManager.get_campaign().get("completed", false)))
	var final_wallet := SaveManager.get_meta_wallet()
	GameRoot.request_restart()
	await _frames(5)
	_capture_session()
	_case("completed campaign can be explored",
		GameRoot.get_current_state() == GameRoot.State.PLAYING
		and _session.current_mission() == null)
	_case("completed campaign pays no reward again",
		SaveManager.get_meta_wallet() == final_wallet)
	var evac := _session.definition.interaction("evac_shuttle")
	_teleport(evac.at)
	_case("completed targets cannot pay again", not _session.try_interact())
	var damage := DamagePayload.new()
	damage.amount = KILL_DAMAGE
	_session.player.get_health_component().take_damage(damage)
	_case("death opens the retry screen",
		GameRoot.get_current_state() == GameRoot.State.GAME_OVER
		and _game.get_campaign_ui().get_debug_snapshot().get("screen", "") == "result")


## ---------- helpers ----------

func _kill(member: CampaignMember) -> void:
	var id := member.id
	_session.encounters._spawn(member)
	var actor := _session.encounters._active.get(id) as EnemyBase
	_case("authored actor can be defeated / " + id, actor != null)
	if actor == null:
		return
	actor.set_ai_enabled(false)
	var payload := DamagePayload.new()
	payload.amount = KILL_DAMAGE
	payload.source = _session.player
	payload.source_id = &"campaign_runtime"
	var before: int = _session.progress.defeated.size()
	actor.apply_damage(payload)
	actor.apply_damage(payload)
	_case("death counted exactly once / " + id, _session.progress.defeated.size() == before + 1)


func _teleport(at: Vector3) -> void:
	_session.player.global_position = at
	_session.player.velocity = Vector3.ZERO
	_session.player.reset_physics_interpolation()
	_session.world.update_visibility(at)


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _child_named(parent: Node, name: String) -> Node:
	for child in parent.get_children():
		if child.name == name:
			return child
	return null
