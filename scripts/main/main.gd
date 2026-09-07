extends Node
## Main scene controller: pure composition + lifecycle coordination. It builds the
## gameplay world (arena + player + camera) under WorldRoot when a run starts and
## tears it down cleanly between runs / on returning to the menu. It contains no
## combat, AI, save, or detailed UI logic.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CAMERA_SCENE := preload("res://scenes/main/camera_rig.tscn")

var _world_root: Node3D = null
var _ui_root: Node = null


func _ready() -> void:
	_world_root = get_node_or_null("WorldRoot") as Node3D
	_ui_root = get_node_or_null("UIRoot/UI")
	if _ui_root == null:
		_ui_root = get_node_or_null("UIRoot")
	GameRoot.game_state_changed.connect(_on_state_changed)


func _on_state_changed(_previous: StringName, current: StringName) -> void:
	match current:
		GameRoot.State.MAIN_MENU:
			_clear_world()
		GameRoot.State.GAME_OVER:
			# Keep the world visible behind the game-over panel for a moment.
			pass


## Called by GameRoot when a new run is being prepared.
func build_world(arena_id: StringName) -> void:
	_clear_world()
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
	_spawn_player(arena)


func _spawn_player(arena: Node) -> void:
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
	if player.has_method("set_control_enabled"):
		player.call("set_control_enabled", true)
	_setup_camera(player)


func _setup_camera(player: Node) -> void:
	var cam := CAMERA_SCENE.instantiate()
	cam.name = "CameraRig"
	_world_root.add_child(cam)
	if cam.has_method("set_target") and player is Node3D:
		cam.call("set_target", player)


func _clear_world() -> void:
	if _world_root == null:
		return
	for child in _world_root.get_children():
		if child.name in ["Arena", "Player", "CameraRig"]:
			child.queue_free()
	# Release the player reference in GameRoot.
	GameRoot.set_active_player(null)


func get_debug_snapshot() -> Dictionary:
	return {
		"world_root_children": _world_root.get_child_count() if _world_root else 0,
		"ui_root_present": _ui_root != null,
	}
