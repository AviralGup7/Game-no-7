class_name UiCommands
extends RefCounted
## Thin intent adapter, NEVER an alternate game/progression controller.
## Selection fails closed instead of writing ContentRegistry or RunState from
## presentation.
##
## The old generic `action(method, args)` forwarded ARBITRARY method names to
## GameRoot/player via callv() string dispatch — zero compile-time safety, and it
## probed GameRoot for methods that do not exist (request_move_input etc.), so
## the "GameRoot branch" was silently dead. The command surface is small and
## closed (touch buttons + skill bar), so it is now an explicit typed dispatch:
## adding a command means adding a case here, and a typo becomes a parse error
## instead of a silent runtime no-op.

static func meta(tree: SceneTree) -> MetaProgression:
	return tree.get_first_node_in_group("meta_progression") as MetaProgression


## Armory purchases route through the MetaProgression service (wallet + ranks).
static func purchase(tree: SceneTree, id: StringName) -> bool:
	var service := meta(tree)
	return service.purchase(id) if service != null else false


## Arena selection for the next run. GameRoot validates availability and
## ContentRegistry owns the live selection used by world build.
static func select_arena(id: StringName) -> bool:
	return GameRoot.request_arena_selection(id)


## Typed player-command dispatch for the touch buttons and skill bar. Returns
## false when the command is unknown or declined (stamina/cooldown/state gates).
static func action(method: StringName, args: Array = []) -> bool:
	if GameRoot.get_current_state() not in [GameRoot.State.PLAYING, GameRoot.State.WAVE_TRANSITION]:
		return false
	var player := GameRoot.get_active_player()
	if player == null or not is_instance_valid(player):
		return false
	match method:
		&"request_attack":
			return player.request_attack()
		&"request_dodge":
			return player.request_dodge()
		&"request_weapon_switch":
			return player.request_weapon_switch()
		&"request_lock_on":
			return player.request_lock_on()
		&"request_skill":
			# A non-numeric arg would raise inside int() and abort the dispatch;
			# an out-of-range slot is simply declined by the controller.
			var slot := 0
			if not args.is_empty() and (args[0] is int or args[0] is float):
				slot = int(args[0])
			return player.request_skill(slot)
		_:
			push_warning("UiCommands.action: unknown player command %s" % String(method))
			return false


static func move(value: Vector2) -> void:
	var player := GameRoot.get_active_player()
	if player != null and is_instance_valid(player):
		player.set_move_input(value)


static func binding(action_name: StringName) -> String:
	var bindings := InputRemapper.get_bindings(action_name)
	return InputRemapper.binding_label(bindings[0]) if not bindings.is_empty() else "Unbound"
