class_name UiCommands
extends RefCounted
## Thin intent adapter, NEVER an alternate game/progression controller.
## GameRoot has no input, arena/loadout or shop commands in the initial baseline.
## Prefer those facades if supplied by the system-owning branch; otherwise retain
## the existing validated player input / MetaProgression APIs. Selection fails
## closed instead of writing ContentRegistry or RunState from presentation.

static func meta(tree: SceneTree) -> MetaProgression:
	return tree.get_first_node_in_group("meta_progression") as MetaProgression

static func purchase(tree: SceneTree, id: StringName) -> bool:
	if GameRoot.has_method("request_armory_purchase"):
		return bool(GameRoot.call("request_armory_purchase", id))
	var service := meta(tree)
	return service.purchase(id) if service != null else false

static func select_arena(id: StringName) -> bool:
	if id == ContentRegistry.get_selected_arena_id():
		return true
	if GameRoot.has_method("request_arena_selection"):
		return bool(GameRoot.call("request_arena_selection", id))
	return false

static func action(method: StringName, args: Array = []) -> bool:
	if GameRoot.get_current_state() not in [GameRoot.State.PLAYING, GameRoot.State.WAVE_TRANSITION]:
		return false
	if GameRoot.has_method(method):
		var accepted: Variant = GameRoot.callv(method, args)
		return accepted != false
	var player := GameRoot.get_active_player()
	if not is_instance_valid(player) or not player.has_method(method):
		return false
	var result: Variant = player.callv(method, args)
	return result != false

static func move(value: Vector2) -> void:
	if GameRoot.has_method("request_move_input"):
		GameRoot.call("request_move_input", value)
		return
	var player := GameRoot.get_active_player()
	if is_instance_valid(player) and player.has_method("set_move_input"):
		player.call("set_move_input", value)

static func binding(action_name: StringName) -> String:
	var bindings := InputRemapper.get_bindings(action_name)
	return InputRemapper.binding_label(bindings[0]) if not bindings.is_empty() else "Unbound"
