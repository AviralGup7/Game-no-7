extends Node
## Autoload: SceneRouter
## One scene change at a time. GameRoot decides *which* scene/state; SceneRouter
## decides *how* the tree change happens. What is proven here: a second request
## made while a transition holds the lock is refused with a warning, the engine's
## Error from `change_scene_to_file()` is checked and reported, and the lock is
## held until `current_scene` actually differs from the scene that was replaced
## (bounded at 120 frames, and a timeout is reported through the same channel).
## Nothing is re-routed or rolled back on failure: the caller keeps the tree it
## already has and reads `get_last_error()`. The main game scene is persistent and
## composes world + UI, so most transitions are state changes rather than scene
## swaps; this autoload exists to keep scene-loading policy in one place and to be
## a clean seam for future full-scene routing (e.g. dedicated menu scenes).

var _transitioning := false
var _last_error := ""

const MAIN_SCENE := "res://scenes/campaign/station_zero.tscn"


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
	var previous := tree.current_scene
	var error := tree.change_scene_to_file(path)
	if error != OK:
		_transitioning = false
		_last_error = "Could not load scene %s (error %d)" % [path, error]
		EventBus.report_error(_last_error)
		return false
	_last_error = ""
	_reset_when_changed(previous)
	return true


func _reset_when_changed(previous: Node) -> void:
	# The engine defers replacement. Keep the lock until current_scene actually
	# changes rather than guessing that one frame is enough.
	if is_inside_tree() and get_tree() != null:
		var frames := 0
		while get_tree() != null and get_tree().current_scene == previous and frames < 120:
			await get_tree().process_frame
			frames += 1
		if get_tree() != null and get_tree().current_scene == previous:
			_last_error = "Scene transition did not complete within 120 frames"
			EventBus.report_error(_last_error)
	_transitioning = false


func is_transitioning() -> bool:
	return _transitioning


func get_last_error() -> String:
	return _last_error
