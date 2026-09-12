class_name CampaignGame
extends Node
## Default app composition. Legacy arena scenes remain as regression fixtures,
## but this entry point never constructs an Arena, WaveManager or run selector.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CAMERA_SCENE := preload("res://scenes/main/camera_rig.tscn")
var definition := CampaignDefinition.new()
var _world_root: Node3D
var _world: CampaignWorld
var _director: CampaignDirector
var _ui: CampaignUI
var _meta: MetaProgression
var _music: MusicManager
var _monitor: PerformanceMonitor


func _ready() -> void:
	_world_root = get_node("WorldRoot") as Node3D
	GameRoot.set_world_builder(build_world)
	_meta = MetaProgression.new()
	_meta.name = "MetaProgression"
	add_child(_meta)
	_music = MusicManager.new()
	_music.name = "MusicManager"
	add_child(_music)
	_music.begin_tracking()
	var loaded := definition.load_authored()
	_ui = CampaignUI.new()
	_ui.name = "CampaignUI"
	_ui.definition = definition
	(get_node("UIRoot") as CanvasLayer).add_child(_ui)
	EventBus.game_state_changed.connect(_on_state)
	if not loaded:
		EventBus.report_error("The authored Station Zero campaign could not be loaded")
		GameRoot.transition_to(GameRoot.State.LOADING)
		GameRoot.transition_to(GameRoot.State.ERROR)


func build_world(world_id: StringName) -> void:
	_clear_world()
	if world_id != &"station_zero" or not definition.valid:
		return
	_world = CampaignWorld.new()
	_world.name = "StationWorld"
	_world_root.add_child(_world)
	if not _world.build(definition):
		EventBus.report_error("Station Zero geometry or navigation failed to build")
		_clear_world()
		return
	# Pools precede actors so their first shot/effect resolves a live pool.
	_support_systems()
	var player := PLAYER_SCENE.instantiate() as Player
	if player == null:
		EventBus.report_error("Station Zero player scene did not instantiate as Player")
		_clear_world()
		return
	player.name = "Player"
	_world_root.add_child(player)
	var progress := SaveManager.get_campaign()
	player.reset_for_new_run(definition.checkpoint(String(progress.checkpoint)))
	player.set_bounds(176.0)
	GameRoot.set_active_player(player)
	var camera := CAMERA_SCENE.instantiate() as CameraRig
	camera.name = "CameraRig"
	_world_root.add_child(camera)
	var view := camera.get_node("Camera3D") as Camera3D
	view.far = 110.0
	camera.set_target(player)
	camera.reset_transform()
	_director = CampaignDirector.new()
	_director.name = "CampaignDirector"
	_world_root.add_child(_director)
	_director.configure(_world, player, _meta)
	var effects := BuildEffects.new()
	effects.name = "BuildEffects"
	player.add_child(effects)
	effects.bind(player, player.get_progression_component(), 0)
	_ui.bind_session(_director)
	_ui.theme = UiTheme.create(SaveManager.get_settings())
	_on_tier_changed(0, _monitor.get_tier())


func _support_systems() -> void:
	var projectiles := ProjectilePool.new()
	projectiles.name = "ProjectilePool"
	_world_root.add_child(projectiles)
	var pickups := PickupManager.new()
	pickups.name = "PickupManager"
	_world_root.add_child(pickups)
	pickups.configure(0)
	var effects := EffectDirector.new()
	effects.name = "EffectDirector"
	_world_root.add_child(effects)
	var hitstop := HitstopManager.new()
	hitstop.name = "HitstopManager"
	_world_root.add_child(hitstop)
	hitstop.set_reduced_motion(SaveManager.get_settings().reduced_motion)
	_monitor = PerformanceMonitor.new()
	_monitor.name = "PerformanceMonitor"
	var tier := [&"low", &"medium", &"high", &"ultra"].find(SaveManager.get_settings().graphics_quality)
	_monitor.configure(maxi(tier, 0), maxi(Engine.max_fps, 0))
	_monitor.set_persist_tier_callable(_persist_quality)
	_world_root.add_child(_monitor)
	_monitor.quality_tier_changed.connect(_on_tier_changed)


func _on_tier_changed(_old: int, _new: int) -> void:
	if is_instance_valid(_monitor):
		PoolGovernor.apply(_monitor, self)


func _persist_quality(quality: String) -> void:
	var current := SaveManager.get_settings()
	if String(current.graphics_quality) == quality:
		return
	var settings := SettingsData.new()
	settings.from_dict(current.to_dict())
	settings.set_graphics_quality(StringName(quality))
	SaveManager.save_settings(settings)


func _on_state(_old: StringName, state: StringName) -> void:
	# Menus are opaque; do not render an invisible station or let cheap paused
	# frames teach the automatic quality governor an unrealistic headroom budget.
	_world_root.visible = state == GameRoot.State.PLAYING
	if is_instance_valid(_monitor):
		_monitor.set_process(state == GameRoot.State.PLAYING)
	if state == GameRoot.State.MAIN_MENU:
		if is_instance_valid(_director):
			_director.save_progress(true)
		_clear_world()  # Also tears down a partially failed build with no director.
		return
	if not is_instance_valid(_director):
		return
	match state:
		GameRoot.State.PAUSED:
			_director.save_progress(true)
		GameRoot.State.GAME_OVER:
			_director.save_progress(true)
			_director.stop()
			RunIsolation.isolate_from(self)
			AudioManager.isolate_run()
		GameRoot.State.PLAYING:
			_director.changed.emit()


func _clear_world() -> void:
	if is_instance_valid(_director):
		_director.stop()
	if is_instance_valid(_ui):
		_ui.bind_session(null)
	RunIsolation.isolate_from(self)
	AudioManager.isolate_run()
	GameRoot.set_active_player(null)
	for child in _world_root.get_children():
		_world_root.remove_child(child)
		child.free()
	_director = null
	_world = null
	_monitor = null


func get_campaign_director() -> CampaignDirector:
	return _director


func get_campaign_ui() -> CampaignUI:
	return _ui


func _exit_tree() -> void:
	GameRoot.set_world_builder(Callable())
	GameRoot.set_active_player(null)
