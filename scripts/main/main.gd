extends Node
## Main scene controller: pure composition + lifecycle coordination. It builds the
## gameplay world (arena + player + camera + spawn/wave systems) under WorldRoot when a
## run starts, starts/tears down the wave director with GameRoot state changes, and
## clears the world cleanly on menu/game-over. It contains no combat/AI/save/UI logic.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CAMERA_SCENE := preload("res://scenes/main/camera_rig.tscn")
const SPAWN_SCENE := preload("res://scenes/enemies/spawn_manager.tscn")
const WAVE_MANAGER_SCRIPT := preload("res://scripts/waves/wave_manager.gd")

var _world_root: Node3D = null
var _ui_root: Node = null
var _spawn_manager: SpawnManager = null
var _wave_manager: WaveManager = null
var _run_started := false
## Persistent (run-independent) directors live outside WorldRoot.
var _music: MusicManager = null
var _achievements: Achievements = null
var _meta: MetaProgression = null
var _tutorial: TutorialManager = null


func _ready() -> void:
	_world_root = get_node_or_null("WorldRoot") as Node3D
	_ui_root = get_node_or_null("UIRoot/UI")
	if _ui_root == null:
		_ui_root = get_node_or_null("UIRoot")
	GameRoot.game_state_changed.connect(_on_state_changed)
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


func _on_state_changed(_previous: StringName, current: StringName) -> void:
	match current:
		GameRoot.State.MAIN_MENU:
			_clear_world()
		GameRoot.State.PLAYING:
			if not _run_started:
				_start_run_waves()
		GameRoot.State.GAME_OVER:
			_stop_run_waves()


func _start_run_waves() -> void:
	if _wave_manager == null or _spawn_manager == null:
		return
	_run_started = true
	_wave_manager.start_run(GameRoot.get_run().seed)


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
		return
	var arena_cfg := ContentRegistry.get_arena(arena_id)
	var arena_scene: PackedScene = null
	if arena_cfg != null and arena_cfg.scene != null:
		arena_scene = arena_cfg.scene
	else:
		EventBus.report_error("Arena config/scene missing for %s" % String(arena_id))
		return
	var arena := arena_scene.instantiate()
	arena.name = "Arena"
	_world_root.add_child(arena)
	var player := _spawn_player(arena)
	_create_systems(arena, player)


func _spawn_player(arena: Node) -> Node:
	var start_marker := arena.get_node_or_null("PlayerStart") as Marker3D
	var spawn := Transform3D.IDENTITY
	if start_marker != null:
		spawn = start_marker.global_transform
	var player := PLAYER_SCENE.instantiate()
	player.name = "Player"
	_world_root.add_child(player)
	if player.has_method("reset_for_new_run"):
		player.call("reset_for_new_run", spawn)
	GameRoot.set_active_player(player)
	# Keep the player inside the arena interior.
	if player.has_method("set_bounds") and arena.has_method("get_interior_half"):
		player.call("set_bounds", float(arena.call("get_interior_half")))
	if player.has_method("set_control_enabled"):
		player.call("set_control_enabled", true)
	_setup_camera(player)
	return player


func _setup_camera(player: Node) -> void:
	var cam := CAMERA_SCENE.instantiate()
	cam.name = "CameraRig"
	_world_root.add_child(cam)
	if cam.has_method("set_target") and player is Node3D:
		cam.call("set_target", player)


func _create_systems(arena: Node, player: Node) -> void:
	# EnemyContainer holds spawned enemies.
	var container := Node3D.new()
	container.name = "EnemyContainer"
	_world_root.add_child(container)

	var spawn := SPAWN_SCENE.instantiate()
	spawn.name = "SpawnManager"
	_world_root.add_child(spawn)
	_spawn_manager = spawn as SpawnManager
	_spawn_manager.configure(arena, player, container, GameRoot.get_run().seed)

	var wave := WAVE_MANAGER_SCRIPT.new()
	wave.name = "WaveManager"
	_world_root.add_child(wave)
	_wave_manager = wave as WaveManager
	_wave_manager.setup(_spawn_manager)

	_create_run_systems(arena, player)


## Per-run support systems: projectiles, pickups, juice, perf scaling, arena
## dressing + hazards. All passive until used; freed with the world on rebuild.
func _create_run_systems(arena: Node, player: Node) -> void:
	var seed := GameRoot.get_run().seed
	var arena_id := GameRoot.get_run().arena_id
	var half := 12.0
	if arena.has_method("get_interior_half"):
		half = float(arena.call("get_interior_half"))

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
	_world_root.add_child(perf)

	var decorator := ArenaDecorator.new()
	decorator.name = "ArenaDecorator"
	(arena as Node).add_child(decorator)
	decorator.decorate(arena_id, half, seed)

	var hazards := ArenaHazards.new()
	hazards.name = "ArenaHazards"
	(arena as Node).add_child(hazards)
	hazards.configure(arena_id, half, seed)

	# Seed the player's deterministic streams + owned meta bonuses for this run.
	if player is Node:
		var skills := (player as Node).get_node_or_null("SkillController")
		if skills != null and skills.has_method("configure"):
			skills.call("configure", seed)
		var weapons := (player as Node).get_node_or_null("WeaponManager")
		if weapons != null and weapons.has_method("configure"):
			weapons.call("configure", seed)
		# Tutorial coach follows real player actions.
		if _tutorial != null:
			if (player as Node).has_signal("attack_started"):
				(player as Node).attack_started.connect(_tutorial.notify_player_attacked)
			if (player as Node).has_signal("dodged"):
				(player as Node).dodged.connect(_tutorial.notify_player_dodged)
	if _meta != null:
		_meta.apply_all_to_run()


func _clear_world() -> void:
	_stop_run_waves()
	if _world_root == null:
		return
	for child in _world_root.get_children():
		child.queue_free()
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
