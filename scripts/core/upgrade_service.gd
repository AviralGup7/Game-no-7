class_name UpgradeService
extends RefCounted

## Deterministic upgrade selection flow, extracted from GameRoot. Chooses the
## offered upgrades for a wave, validates a player's pick, and applies it to the
## runtime ProgressionComponent (mirrored into RunState). GameRoot keeps the state
## gating + transitions + announcements; this service owns the pure-ish decision
## logic. All-static; only called from GameRoot at runtime (uses the
## ContentRegistry/UpgradeSelector/EventBus autoloads).


## Deterministically choose the offered upgrades from run seed + wave + current
## stacks. Returns an empty list when nothing is eligible (caller continues to the
## next wave without touching state).
static func choose_for_wave(run: RunState, player: Node, wave_number: int) -> Array[StringName]:
	var empty: Array[StringName] = []
	if run == null:
		return empty
	var prog := _progression_node_of(player)
	if prog == null:
		return empty
	var counts: Dictionary = prog.call("get_upgrade_stack_snapshot") if prog.has_method("get_upgrade_stack_snapshot") else {}
	var pool: Array[UpgradeConfig] = []
	for raw in ContentRegistry.get_all_upgrades().values():
		pool.append(raw as UpgradeConfig)
	var chosen: Array[UpgradeConfig] = UpgradeSelector.choose_upgrade_choices(pool, 3, run.seed, wave_number, counts)
	if chosen.is_empty():
		EventBus.report_info("No eligible upgrades to present after wave %d; continuing" % wave_number)
		return empty
	return UpgradeSelector.to_id_list(chosen)


## Validate a pick against the offered list + live progression state. Returns ""
## when the selection may proceed, otherwise the human-readable rejection reason
## (already reported as a warning).
static func validate_selection(run: RunState, player: Node, upgrade_id: StringName) -> String:
	var reason: String = ""
	if run == null:
		return "no run"
	if upgrade_id not in run.upgrade_choices:
		reason = "Upgrade %s is not currently offered" % String(upgrade_id)
		EventBus.report_warning(reason)
		return reason
	if player == null or not is_instance_valid(player) or not bool(player.call("is_alive")):
		reason = "request_upgrade_selection: no live player"
		EventBus.report_warning(reason)
		return reason
	var cfg := ContentRegistry.get_upgrade(upgrade_id)
	if cfg == null:
		reason = "request_upgrade_selection: unknown upgrade %s" % String(upgrade_id)
		EventBus.report_warning(reason)
		return reason
	var prog := _progression_node_of(player)
	var counts: Dictionary = prog.call("get_upgrade_stack_snapshot") if prog != null and prog.has_method("get_upgrade_stack_snapshot") else {}
	if not UpgradeSelector.is_eligible(cfg, run.current_wave, counts):
		reason = "Upgrade %s is no longer selectable" % String(upgrade_id)
		EventBus.report_warning(reason)
		return reason
	return ""


## Apply a validated pick to the runtime ProgressionComponent and mirror the
## result into RunState. Returns false (with a warning) when application fails.
static func apply_selection(run: RunState, player: Node, upgrade_id: StringName) -> bool:
	# Keep this method safe when called outside GameRoot as well. GameRoot normally
	# performs the same validation before reaching here, but the service is the
	# authoritative last gate against stale offers, future waves and invalid ids.
	if not validate_selection(run, player, upgrade_id).is_empty():
		return false
	if player == null or not player.has_method("apply_upgrade") or not bool(player.call("apply_upgrade", upgrade_id)):
		EventBus.report_warning("Upgrade %s could not be applied" % String(upgrade_id))
		return false
	_sync_run_from_progression(run, player)
	run.upgrade_choices.clear()
	return true


static func _progression_node_of(player: Node) -> Node:
	if player == null or not is_instance_valid(player):
		return null
	return player.get_node_or_null("ProgressionComponent")


## Mirror the runtime ProgressionComponent (source of truth) into the serializable
## RunState snapshot so game-over summaries/analytics see exactly what is applied.
## `active_modifiers` is owned by the mutator/director path — do not overwrite it
## with stat-modifier keys here; that would erase the wave-mutator record.
static func _sync_run_from_progression(run: RunState, player: Node) -> void:
	if run == null:
		return
	var prog := _progression_node_of(player)
	if prog == null:
		return
	if prog.has_method("get_upgrade_stack_snapshot"):
		run.selected_upgrades = (prog.call("get_upgrade_stack_snapshot") as Dictionary).duplicate()

## Hardened: validate upgrade pool before offering.
func _validated_pool_size(n: int) -> int:
    if n < 0:
        return 0
    return mini(n, 100)

