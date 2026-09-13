class_name CameraHitstopLocator
extends RefCounted

## Finds the run's HitstopManager for the camera shake controller, extracted from
## CameraRig so the per-frame rig loop only has to say "bind if needed".
##
## The manager is scene-authored under the run's WorldRoot and also joins the
## "hitstop_manager" group, so the lookup tries the group first, then the authored
## path, then a bounded class walk. It is retried every frame until it resolves: the
## rig can run for a frame or two before the run's world root exists (scene router,
## campaign boot, headless fixtures).

## Group every HitstopManager joins.
const MANAGER_GROUP := &"hitstop_manager"

var _manager: Node = null


## Locate the manager once, then keep handing the same instance to the shake
## controller. Safe to call every frame.
func bind_if_needed(tree: SceneTree, shake: CameraShakeController) -> void:
	if _manager != null and is_instance_valid(_manager):
		shake.set_hitstop_manager(_manager as HitstopManager)
		return
	if tree == null:
		return
	_manager = tree.get_first_node_in_group(String(MANAGER_GROUP))
	if _manager == null:
		var world := tree.current_scene as Node
		if world != null:
			_manager = world.get_node_or_null("WorldRoot/HitstopManager")
			if _manager == null:
				_manager = find_exact_class(world)
	if _manager != null:
		shake.set_hitstop_manager(_manager as HitstopManager)


func get_manager() -> Node:
	return _manager


## Depth-first search for the exact HitstopManager class (last resort when neither the
## group nor the authored path resolves). Typed compare, not a name test.
func find_exact_class(root: Node) -> Node:
	if root == null:
		return null
	if root is HitstopManager:
		return root
	for child in root.get_children():
		var found := find_exact_class(child as Node)
		if found != null:
			return found
	return null
