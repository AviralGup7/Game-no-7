extends Node
## Real-scene campaign integration, using an isolated profile. Drives the actual
## controllers/health/save/touch APIs, not a Python copy of campaign rules.

var _checks := 0
var _failed: Array[String] = []
var _errors: Array[String] = []
var _game: CampaignGame
var _session: CampaignDirector


func _ready() -> void:
	_run.call_deferred()


func _check(title: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failed.append(title)
		push_error("CAMPAIGN FAIL: " + title)


func _frames(count: int = 3) -> void:
	for i in range(count):
		await get_tree().process_frame


func _run() -> void:
	EventBus.diagnostic.connect(func(text: String, severity: StringName) -> void:
		if severity == &"error":
			_errors.append(text))
	var path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	_check("project boots the campaign scene", path == "res://scenes/campaign/station_zero.tscn")
	get_tree().change_scene_to_file(path)
	await _frames(5)
	_game = get_tree().current_scene as CampaignGame
	_check("shipping controller instantiated", _game != null)
	if _game == null:
		await _finish()
		return
	_check("campaign menu is the initial screen", _game.get_campaign_ui().get_debug_snapshot().screen == "menu")
	GameRoot.start_campaign(true)
	await _frames(5)
	_capture_session()
	_check("new campaign reaches PLAYING", GameRoot.get_current_state() == GameRoot.State.PLAYING)
	if _session == null:
		await _finish()
		return
	_check("campaign has no Arena or WaveManager", get_tree().get_nodes_in_group("arena").is_empty() and _game.find_children("WaveManager", "", true, false).is_empty())
	_check("checkpoint spawns player on an authored deck", _session.world.point_is_on_floor(_session.player.global_position))
	_check("distant scenes start without active NPCs", int(_session.encounters.get_debug_snapshot().active) == 0)
	_check("interaction is distance gated", not _session.try_interact())
	await _layouts()
	await _touch_map_back()
	_budget()
	await _streaming_and_reload()
	await _story()
	await _finish()


func _capture_session() -> void:
	_session = _game.get_campaign_director()
	_check("campaign director exists", _session != null)
	if _session != null:
		# Control mission ticks explicitly, while real player physics/UI/audio
		# still run. This prevents timing-dependent patrol attacks in a harness.
		_session.set_physics_process(false)
		_session.encounters.set_process(false)


func _move_to(at: Vector3) -> void:
	_session.player.global_position = at
	_session.player.velocity = Vector3.ZERO
	_session.player.reset_physics_interpolation()
	_session.world.update_visibility(at)
	_session._update_route()
	var camera := get_tree().get_first_node_in_group("camera_rig") as CameraRig
	if camera != null:
		camera.reset_transform()
	await get_tree().physics_frame
	await _frames(2)
	_check("streaming keeps at most three district batches", _session.world.get_debug_snapshot().visible_districts.size() <= 3)


func _kill(member: Dictionary) -> void:
	_session.encounters._spawn(member)
	var actor := _session.encounters._active.get(String(member.id)) as EnemyBase
	_check("authored actor can be activated / " + String(member.id), actor != null)
	if actor == null:
		return
	actor.set_ai_enabled(false)
	var payload := DamagePayload.new()
	payload.amount = 100000.0
	payload.source = _session.player
	payload.source_id = &"campaign_test"
	var before: int = _session.progress.defeated.size()
	actor.apply_damage(payload)
	actor.apply_damage(payload)
	_check("death counted exactly once / " + String(member.id), _session.progress.defeated.size() == before + 1)


func _budget() -> void:
	for group in _session.definition.encounters:
		for member in group.members:
			_session.encounters._spawn(member)
			var actor := _session.encounters._active.get(String(member.id)) as EnemyBase
			if actor != null:
				actor.set_ai_enabled(false)
	_check("encounter budget actually refuses a nineteenth active NPC", _session.encounters._active.size() == 18)
	# Start the next case cleanly without claiming kills or paying rewards.
	for value in _session.encounters._active.values():
		var actor := value as EnemyBase
		actor.queue_free()
	_session.encounters._active.clear()


func _streaming_and_reload() -> void:
	var member: Dictionary = _session.definition.encounters[0].members[0]
	_check("explicit encounter activation works", _session.encounters._spawn(member))
	var before: int = _session.progress.defeated.size()
	await _move_to(_session.definition.checkpoint("reactor").origin)
	_session.encounters.stream_nearby()
	_check("leaving a district is not a defeat", _session.progress.defeated.size() == before)
	_check("distant authored member is removed", not _session.encounters._active.has(String(member.id)))
	await _frames(2)
	await _move_to(_session.definition.checkpoint("docks").origin)
	_kill(member)
	_check("defeat/checkpoint save succeeds", _session.save_progress(true))
	var total_xp := _session.player.get_experience_component().total_xp_earned()
	var credits := SaveManager.get_meta_wallet()
	GameRoot.request_restart()
	await _frames(5)
	_capture_session()
	_check("defeat survives checkpoint retry", member.id in _session.progress.defeated)
	_check("cleared actor cannot respawn on reload", not _session.encounters._spawn(member))
	_check("retry does not multiply XP", _session.player.get_experience_component().total_xp_earned() == total_xp)
	_check("retry does not bank rewards twice", SaveManager.get_meta_wallet() == credits)


func _story() -> void:
	# One optional supply cache, once, before the story.
	var cache := _session.definition.interaction("supply_docks")
	await _move_to(CampaignDefinition.point(cache.at))
	var wallet := SaveManager.get_meta_wallet()
	_check("supply locker can be opened", _session.try_interact())
	_check("cache credits reach the permanent wallet", SaveManager.get_meta_wallet() == wallet + int(cache.credits))
	_check("cache cannot be farmed", not _session.try_interact())
	for index in range(_session.definition.missions.size()):
		var mission: Dictionary = _session.definition.missions[index]
		for id in mission.targets:
			var target := _session.definition.interaction(String(id))
			await _move_to(CampaignDefinition.point(target.at))
			if _session.remaining_guards() > 0:
				_check("guarded console refuses early interaction", not _session.try_interact())
				for encounter_id in mission.requires:
					for member in _session.definition.encounter(String(encounter_id)).members:
						if member.id not in _session.progress.defeated:
							_kill(member)
			_check("story interaction / " + String(id), _session.try_interact())
		_check("mission advances once / " + String(mission.id), int(_session.progress.mission) == index + 1)
		_check("story grants an authored checkpoint", String(_session.progress.checkpoint) == String(mission.sector))
		if index == 2:
			_check("rail rifle is earned as campaign inventory", &"sentinel_spear" in _session.available_weapons())
			GameRoot._notification(NOTIFICATION_APPLICATION_PAUSED)
			_check("Android backgrounding pauses campaign", GameRoot.get_current_state() == GameRoot.State.PAUSED and get_tree().paused)
			var disk := JsonHelpers.load_dict(SaveManager.SAVE_PATH)
			_check("backgrounding flushes current campaign cursor", int(disk.get("campaign", {}).get("mission", -1)) == index + 1)
			_game.get_campaign_ui()._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
			_check("Android Back resumes from pause", GameRoot.get_current_state() == GameRoot.State.PLAYING)
	_check("extraction reaches campaign victory", GameRoot.get_current_state() == GameRoot.State.GAME_OVER and GameRoot.get_run().victory)
	_check("completion persists", SaveManager.get_campaign().completed)
	wallet = SaveManager.get_meta_wallet()
	GameRoot.request_restart()
	await _frames(5)
	_capture_session()
	_check("completed campaign can be explored", GameRoot.get_current_state() == GameRoot.State.PLAYING and _session.current_mission().is_empty())
	_check("completed campaign has no repeated reward", SaveManager.get_meta_wallet() == wallet)
	_check("completed targets cannot pay again", not _session.try_interact())
	# Real player death -> checkpoint retry, not a new run/world roll.
	var damage := DamagePayload.new()
	damage.amount = 100000.0
	_session.player.get_health_component().take_damage(damage)
	_check("death opens retry screen", GameRoot.get_current_state() == GameRoot.State.GAME_OVER and _game.get_campaign_ui().get_debug_snapshot().screen == "result")


func _touch_map_back() -> void:
	var ui := _game.get_campaign_ui()
	var hud := ui._hud
	var stick := hud._touch.joystick
	var finger := InputEventScreenTouch.new()
	finger.index = 21
	finger.pressed = true
	finger.position = stick.size * 0.5
	stick._gui_input(finger)
	_check("movement finger is held", stick.is_active())
	var chart: Button = null
	for node in hud.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == "MAP":
			chart = button
	_check("native MAP button exists", chart != null)
	if chart != null:
		var input := chart.get_node("TouchButtonInput") as TouchButtonInput
		var map_finger := InputEventScreenTouch.new()
		map_finger.index = 22
		map_finger.pressed = true
		map_finger.position = Vector2(10, 10)
		input._on_gui_input(map_finger)
		_check("second finger opens station map while moving", ui.get_debug_snapshot().screen == "map")
		_check("map cancels movement ownership", not stick.is_active())
		ui._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
		_check("Back from chart remains paused", ui.get_debug_snapshot().screen == "pause" and get_tree().paused)
		ui._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
		_check("Back from pause resumes", not get_tree().paused)
	await _frames()


func _layouts() -> void:
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var hud := CampaignHud.new()
	viewport.add_child(hud)
	hud.bind(_session)
	var previous := SaveManager.get_settings().to_dict()
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(1920, 1080), Vector2i(1280, 800)]:
		viewport.size = resolution
		for scale in [1.0, 1.5, 2.0]:
			var settings := SettingsData.new()
			settings.from_dict(previous)
			settings.set_text_scale(scale)
			SaveManager.save_settings(settings)
			hud.theme = UiTheme.create(settings)
			UiTheme.apply_text_scale(hud, scale)
			hud.apply_layout()
			await _frames(3)
			var screen := Rect2(Vector2.ZERO, Vector2(resolution))
			for node in hud.find_children("*", "Button", true, false):
				var button := node as Button
				if not button.is_visible_in_tree():
					continue
				_check("campaign touch target fits %s @ %.1f" % [str(resolution), scale], screen.encloses(button.get_global_rect()) and button.size.y >= 88 and button.size.x >= 88)
	var restored := SettingsData.new()
	restored.from_dict(previous)
	SaveManager.save_settings(restored)
	viewport.queue_free()
	await _frames(3)


func _finish() -> void:
	_check("no campaign error diagnostics", _errors.is_empty())
	GameRoot.request_main_menu()
	await _frames(3)
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	await _frames(3)
	print("CAMPAIGN TESTS: %d checks, %d failed" % [_checks, _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)
