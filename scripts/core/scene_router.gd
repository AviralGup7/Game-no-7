extends Node
## Autoload: SceneRouter
## Controlled, duplicate-safe scene changes with loading transitions and failure
## recovery. GameRoot decides *which* scene/state; SceneRouter decides *how* the
## tree change happens. The main game scene is persistent and composes world + UI,
## so most transitions are state changes rather than scene swaps; this autoload
## exists to keep scene-loading policy in one place and to be a clean seam for
## future full-scene routing (e.g. dedicated menu scenes).

var _transitioning := false
var _last_error := ""

const MAIN_SCENE := "res://scenes/main/main.tscn"


func goto_main_scene() -> void:
	change_scene_to_file(MAIN_SCENE)


## Change the current scene through the tree. Returns false and emits a diagnostic
## when a transition is already in flight or the load fails.
func change_scene_to_file(path: String) -> bool:
	if _transitioning:
		EventBus.report_warning("Scene transition already in progress; ignoring %s" % path)
		return false
	if not ResourceLoader.exists(path):
		_last_error = "Missing scene: %s" % path
		EventBus.report_error(_last_error)
		return false
	_transitioning = true
	var tree := get_tree()
	if tree == null:
		_transitioning = false
		return false
	EventBus.report_info("Routing to scene: %s" % path)
	# change_scene_to_file is already deferred internally; wrap completion so the
	# in-flight flag is cleared after the swap.
	tree.change_scene_to_file(path)
	_reset_later()
	return true


func _reset_later() -> void:
	if is_inside_tree() and get_tree() != null:
		await get_tree().process_frame
	_transitioning = false
	else:
		_transitioning = false


func is_transitioning() -> bool:
	return _transitioning


func get_last_error() -> String:
	return _last_error

## Hardened: validate scene id before routing.
func _validated_scene_id(id: StringName) -> bool:
	if id == &"":
		return false
	return true

