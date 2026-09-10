extends Node
class_name Main
## Main scene controller: pure composition + lifecycle coordination. It builds the
## gameplay world (arena + player + camera + spawn/wave systems) under WorldRoot when a
## run starts, starts/tears down the wave director with GameRoot state changes, and
## clears the world cleanly on menu/game-over. It contains no combat/AI/save/UI logic.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CAMERA_SCENE := preload("res://scenes/main/camera_rig.tscn")
const SPAWN_SCENE := preload("res://scenes/enemies/spawn_manager.tscn")
const WAVE_MANAGER_SCRIPT := preload("res://scripts/waves/wave_manager.gd")

var _world_root: Node3D = null
var _ui_root: UiRoot = null
var _spawn_manager: SpawnManager = null
var _wave_manager: WaveManager = null
var _run_started := false
## Persistent (run-independent) directors live outside WorldRoot.
var _music: MusicManager = null
var _achievements: Achievements = null
var _meta: MetaProgression = null
var _tutorial: TutorialManager = null
var _soak: RuntimeSoak = null


func _ready() -> void:
	# Composition anchor: GameRoot delegates run-world assembly here.
	GameRoot.set_world_builder(build_world)
	_world_root = get_node_or_null("WorldRoot") as Node3D
	_ui_root = get_node_or_null("UIRoot/UI") as UiRoot
	if _ui_root == null:
		_ui_root = get_node_or_null("UIRoot") as UiRoot
	EventBus.game_state_changed.connect(_on_state_changed)
	_create_persistent_directors()


## Run-independent observers: music, achievements, meta wallet, tutorial coach.
## Created once; they self-wire to EventBus and survive world rebuilds.
func _create_persistent_directors() -> void:
	_music = MusicManager.new()
	_music.name = "MusicManager"
	add_child(_music)
	_music.begin_tracking()
	_achievements = Achievements.new()
	_achievements.name = "Achievements"
	add_child(_achievements)
	_meta = MetaProgression.new()
	_meta.name = "MetaProgression"
	add_child(_meta)
	_tutorial = TutorialManager.new()
	_tutorial.name = "TutorialManager"
	add_child(_tutorial)
	# The coach speaks through the HUD announcement banner (UI children are ready
	# before Main, so the banner already exists).
	if _ui_root != null:
		_tutorial.bind_banner(_ui_root.get_announcement_banner())
	_soak = RuntimeSoak.new()
	_soak.name = "RuntimeSoak"
	add_child(_soak)


func _on_state_changed(_previous: StringName, current: StringName) -> void:
	match current:
		GameRoot.State.MAIN_MENU:
			_clear_world()
		GameRoot.State.PLAYING:
			if not _run_started:
				_start_run_waves()
		GameRoot.State.GAME_OVER:
			_stop_run_waves()


## GameRoot.get_run() is typed (RunState): the old Dictionary/"seed" in run theater
## branches existed only for a guard sweep and could never occur in practice.
func _safe_run() -> RunState:
	return GameRoot.get_run()

func _safe_seed(default: int = 0) -> int:
	var run := _safe_run()
	if run == null:
		return default
	return run.seed

func _safe_arena_id(default: StringName = &"default_arena") -> StringName:
	var run := _safe_run()
	if run == null:
		return default
	return run.arena_id

func _start_run_waves() -> void:
	if _wave_manager == null or _spawn_manager == null:
		EventBus.report_error("Waves cannot start: spawn/wave systems missing (world build was incomplete)")
		return
	_run_started = true
	_wave_manager.start_run(_safe_seed())


func _stop_run_waves() -> void:
	if _wave_manager != null:
		_wave_manager.stop()
	if _spawn_manager != null:
		_spawn_manager.deactivate_all()


## Called by GameRoot when a new run is being prepared.
func build_world(arena_id: StringName) -> void:
	_clear_world()
	_run_started = false
	if _world_root == null:
		EventBus.report_error("World build aborted: WorldRoot missing from main scene")
		return
	var arena_cfg := ContentRegistry.get_arena(arena_id) if ContentRegistry != null else null
	if (arena_cfg == null or arena_cfg.scene == null) and ContentRegistry != null:
		var fallback_id: StringName = ContentRegistry.get_selected_arena_id()
		if fallback_id != arena_id:
			arena_cfg = ContentRegistry.get_arena(fallback_id)
		if arena_cfg == null or arena_cfg.scene == null:
			for a in ContentRegistry.get_all_arenas().values():
				if a is ArenaConfig and a.scene != null:
					arena_cfg = a
					break
	var arena_scene: PackedScene = null
	if arena_cfg != null and arena_cfg.scene != null:
		arena_scene = arena_cfg.scene
	else:
		EventBus.report_error("Arena config/scene missing for %s" % String(arena_id))
		return
	var arena := arena_scene.instantiate() as Arena
	if arena == null:
		EventBus.report_error("Arena scene failed to instantiate: %s" % arena_scene.resource_path)
		return
	arena.name = "Arena"
	_world_root.add_child(arena)
	var player := _spawn_player(arena)
	if player == null:
		EventBus.report_error("World build incomplete: player failed to spawn; run systems not created")
		return
	_create_systems(arena, player)


func _spawn_player(arena: Arena) -> Player:
	var spawn := arena.get_safe_player_spawn() if arena != null else Transform3D.IDENTITY
	if PLAYER_SCENE == null:
		EventBus.report_error("Player scene failed to load: scenes/player/player.tscn (the player will not appear)")
		return null
	var player := PLAYER_SCENE.instantiate() as Player
	if player == null:
		EventBus.report_error("Player scene failed to instantiate: scenes/player/player.tscn (the player will not appear)")
		return null
	player.name = "Player"
	_world_root.add_child(player)
	_validate_player_visual(player)
	player.reset_for_new_run(spawn)
	GameRoot.set_active_player(player)
	# Keep the player inside the arena interior.
	player.set_bounds(arena.get_interior_half())
	player.set_control_enabled(true)
	_setup_camera(player)
	return player


## Verify the player spawned with its full authored visuals. If the scene failed
## to build CharacterModel/Audio/attachments, log a clear diagnostic instead of
## silently running an invisible or partially-assembled hero.
func _validate_player_visual(player: Player) -> void:
	var visual_root := player.get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		EventBus.report_error("Player spawned WITHOUT VisualRoot — the hero will be invisible on device")
		return
	var model_mount := visual_root.get_node_or_null("CharacterModel")
	if model_mount == null:
		EventBus.report_error("Player VisualRoot has no CharacterModel mount — model will not attach")
		return
	var body := (model_mount as Node).get_node_or_null("Body")
	if body == null:
		EventBus.report_diagnostic("Player CharacterModel has no primitive Body; model mount is the only visual", &"warning")


func _setup_camera(player: Player) -> void:
	var cam := CAMERA_SCENE.instantiate() as CameraRig
	cam.name = "CameraRig"
	_world_root.add_child(cam)
	# Arenas declare their lens; fall back to the rig default when absent.
	var cfg: ArenaConfig = ContentRegistry.get_arena(_safe_arena_id())
	if cfg != null:
		var prof: CameraProfile = ContentRegistry.get_camera_profile(cfg.default_camera_profile)
		if prof != null:
			cam.set_camera_profile(prof)
	cam.set_target(player)


func _create_systems(arena: Arena, player: Player) -> void:
	# EnemyContainer holds spawned enemies.
	var container := Node3D.new()
	container.name = "EnemyContainer"
	_world_root.add_child(container)

	var spawn := SPAWN_SCENE.instantiate()
	spawn.name = "SpawnManager"
	_world_root.add_child(spawn)
	_spawn_manager = spawn as SpawnManager
	if _spawn_manager == null:
		EventBus.report_error("SpawnManager scene missing its script — enemies will not spawn (%s)" % SPAWN_SCENE.resource_path)
	else:
		_spawn_manager.configure(arena, player, container, _safe_seed())

	var wave := WAVE_MANAGER_SCRIPT.new()
	wave.name = "WaveManager"
	_world_root.add_child(wave)
	_wave_manager = wave as WaveManager
	if _wave_manager == null:
		EventBus.report_error("WaveManager script failed to instantiate — waves will not run")
	else:
		_wave_manager.setup(_spawn_manager)
		_apply_daily_mutators()

	_create_run_systems(arena, player)


## Per-run support systems: projectiles, pickups, juice, perf scaling, arena
## dressing + hazards. All passive until used; freed with the world on rebuild.
func _create_run_systems(arena: Arena, player: Player) -> void:
	var seed := _safe_seed()
	var arena_id := _safe_arena_id()
	var half := arena.get_interior_half()

	var projectiles := ProjectilePool.new()
	projectiles.name = "ProjectilePool"
	_world_root.add_child(projectiles)

	var pickups := PickupManager.new()
	pickups.name = "PickupManager"
	_world_root.add_child(pickups)
	pickups.configure(seed)

	var hitstop := HitstopManager.new()
	hitstop.name = "HitstopManager"
	_world_root.add_child(hitstop)

	var perf := PerformanceMonitor.new()
	perf.name = "PerformanceMonitor"
	# The player's saved graphics quality is the run's opening tier (the
	# governor may still auto-scale from there; a fresh save carries "medium").
	# The session FPS cap (Settings) survives tier changes.
	perf.configure(_initial_quality_tier(), maxi(int(Engine.max_fps), 0))
	perf.set_persist_tier_callable(_persist_quality_tier)
	_world_root.add_child(perf)

	var decorator := ArenaDecorator.new()
	decorator.name = "ArenaDecorator"
	arena.add_child(decorator)
	decorator.decorate(arena_id, half, seed)
	# Prestige banners (unlocked cosmetics) hang on the arena walls in their colours.
	if SaveManager != null:
		decorator.apply_prestige_banners(half, SaveManager.get_unlocked_cosmetics())

	var hazards := ArenaHazards.new()
	hazards.name = "ArenaHazards"
	arena.add_child(hazards)
	# The layout itself is authored: ArenaConfig.hazard_layout for the arena, plus the
	# game mode's own HazardModeLayout. Neither call needs a new code path when a designer
	# adds a hazard or an arena (docs/EXTENDING.md).
	hazards.configure(arena_id, half, seed)
	var mode_id := GameMode.MODE_STANDARD
	if GameRoot != null:
		mode_id = GameRoot.get_run_mode()
	hazards.apply_mode_pressure(mode_id)

	# Agent 4 presentation: pooled VFX director (impact/death/wave/status feedback).
	var effects := EffectDirector.new()
	effects.name = "EffectDirector"
	_world_root.add_child(effects)

	# Objective director: arms Hold the Line / Relic Hunt win-loss logic. A no-op
	# for wave/survival/boss modes, so it is always safe to create.
	var objectives := ObjectiveDirector.new()
	objectives.name = "ObjectiveDirector"
	_world_root.add_child(objectives)
	# The beacon / relic fallback anchor sits at the arena's geometric centre.
	objectives.configure(mode_id, arena.global_position, pickups)

	# Seed the player's deterministic streams + owned meta bonuses for this run.
	var skills := player.get_skill_controller()
	if skills != null:
		skills.configure(seed)
	var weapons := player.get_weapon_manager()
	weapons.configure(seed)
	_apply_owned_unlocks(player, skills, weapons)
	_attach_build_effects(player, seed)
	# Tutorial coach follows real player actions.
	if _tutorial != null:
		player.attack_started.connect(_tutorial.notify_player_attacked)
		player.dodged.connect(_tutorial.notify_player_dodged)
	if _meta != null:
		_meta.apply_all_to_run()
	_apply_player_cosmetics(player)
	player.rebuild_derived_stats()


## Map the saved graphics quality to the governor's opening tier. Unknown or
## legacy values fall back to MEDIUM (the save schema default).
func _initial_quality_tier() -> int:
	if SaveManager == null:
		return PerformanceMonitor.TIER_MEDIUM
	var quality := SaveManager.get_settings().graphics_quality
	var idx := [&"low", &"medium", &"high", &"ultra"].find(quality)
	return idx if idx >= 0 else PerformanceMonitor.TIER_MEDIUM


## Governor seam: persist an auto-scaled tier into the save so the next launch
## opens at the tier this device already proved it can hold. Dedupes against
## the current value; SaveManager owns the debounced atomic write.
func _persist_quality_tier(tier_name: String) -> void:
	if SaveManager == null:
		return
	var current := SaveManager.get_settings()
	if String(current.graphics_quality) == tier_name:
		return
	var next := SettingsData.new()
	next.from_dict(current.to_dict())
	next.set_graphics_quality(StringName(tier_name))
	SaveManager.save_settings(next)


## Attach the prestige-unlocked body cosmetics (trail / aura) to the live hero.
## Reads the persisted unlock list from SaveManager; banners are arena-scoped and
## applied by ArenaDecorator, titles are HUD text.
func _apply_player_cosmetics(player: Player) -> void:
	if player == null:
		return
	var visual_root := player.get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		return
	var unlocked: Array = []
	if SaveManager != null:
		unlocked = SaveManager.get_unlocked_cosmetics()
	var existing := visual_root.get_node_or_null("PlayerCosmetics") as PlayerCosmetics
	if existing == null:
		existing = PlayerCosmetics.new()
		existing.name = "PlayerCosmetics"
		visual_root.add_child(existing)
	existing.apply(unlocked)


## Daily runs share one deterministic mutator pair for every wave.
func _apply_daily_mutators() -> void:
	if _wave_manager == null:
		return
	var daily: Dictionary = GameRoot.get_daily_challenge()
	if daily.is_empty():
		return
	var ids: Array[StringName] = []
	for m in Array(daily.get("mutators", [])):
		ids.append(StringName(String(m)))
	_wave_manager.set_forced_mutators(ids)


## Attach the transformative upgrade runtime (BuildEffects) to the live player.
func _attach_build_effects(player: Player, run_seed: int) -> void:
	if player == null:
		return
	var existing := player.get_node_or_null("BuildEffects") as BuildEffects
	if existing != null:
		existing.configure(run_seed)
		return
	var fx := BuildEffects.new()
	fx.name = "BuildEffects"
	player.add_child(fx)
	fx.bind(player, player.get_progression_component(), run_seed)


## Owned armory unlocks take effect: starter content remains in slot 0 while
## the first owned weapon/skills fill the optional loadout slots. The meta table
## supplies targets, so adding a new unlock does not require another id branch.
func _apply_owned_unlocks(player: Player, skills: SkillController, weapons: WeaponManager) -> void:
	if _meta == null or player == null:
		return
	if skills != null:
		var skill_slot := 1
		for skill_id in _meta.unlocked_targets(&"skill"):
			if skill_slot >= 3:
				break
			if ContentRegistry.get_skill(skill_id) != null:
				skills.assign_skill_by_id(skill_id, skill_slot, true)
				skill_slot += 1
	var weapon_slot := 1
	for weapon_id in _meta.unlocked_targets(&"weapon"):
		if weapon_slot >= 2:
			break
		if ContentRegistry.get_weapon(weapon_id) != null:
			weapons.equip_by_id(weapon_id, weapon_slot, true)
			weapon_slot += 1


func _clear_world() -> void:
	_stop_run_waves()
	if _world_root == null:
		return
	# Immediate (not deferred) teardown: build_world adds the replacement Arena /
	# Player / managers synchronously in the same call, and queue_free'd nodes
	# still in the tree collide with the new names, permanently renaming the new
	# world children to @-style auto-names and breaking WorldRoot path lookups.
	for child in _world_root.get_children():
		# Detach BEFORE freeing: while the old "Arena"/"Player"/... nodes are still
		# attached they occupy their names, and build_world() re-adds the new ones
		# in this same call. Godot would then silently rename the new nodes and
		# hardcoded lookups such as "WorldRoot/Arena" would resolve to the dying
		# node (or null). free() rather than queue_free() because the replacement
		# is built synchronously and must not race a deferred deletion.
		_world_root.remove_child(child)
		child.free()
	_spawn_manager = null
	_wave_manager = null
	# Release the player reference in GameRoot.
	GameRoot.set_active_player(null)


func get_debug_snapshot() -> Dictionary:
	return {
		"world_root_children": _world_root.get_child_count() if _world_root else 0,
		"ui_root_present": _ui_root != null,
		"run_started": _run_started,
		"wave": _wave_manager.get_debug_snapshot() if _wave_manager != null else {},
	}

