extends RefCounted

## Contract test for the EventBus signal registry.
##
## `EventBusService.owned_signals()` is the machine-readable list of every signal
## the bus declares. This suite pins it against what the engine itself reports
## from `Script.get_script_signal_list()`, which returns only the signals defined
## by that script (not the ones inherited from Node). So:
##
##   * a signal added to res://scripts/core/event_bus.gd without being added to
##     the registry fails here, and
##   * a registry entry pointing at a signal that was deleted fails here,
##
## instead of the two lists drifting apart silently. Order is deliberately NOT
## asserted: `get_script_signal_list()` is backed by an unordered map, so its
## iteration order is not contractual.
##
## Registered in run_tests.gd's UNIT_SUITES. It needs no scene tree: it
## instantiates EventBusService directly (that script references no autoload, so
## the runner's load-order contract still holds) and frees the node before
## returning.

const BUS_SCRIPT := "res://scripts/core/event_bus.gd"


static func suite() -> Array:
	var results: Array = []
	var script: GDScript = load(BUS_SCRIPT) as GDScript
	if script == null or not script.can_instantiate():
		results.append({
			"name": "event_bus.gd compiles and instantiates",
			"passed": false,
			"why": "could not load or instantiate %s" % BUS_SCRIPT,
		})
		return results

	var bus: Node = script.new() as Node
	if bus == null:
		results.append({
			"name": "event_bus.gd compiles and instantiates",
			"passed": false,
			"why": "script.new() returned null",
		})
		return results

	var registry: Array = bus.call("owned_signals")
	var engine: Array = script.get_script_signal_list()

	var registered := PackedStringArray()
	var nameless := 0
	for entry in registry:
		if entry is Signal:
			var n: String = (entry as Signal).get_name()
			if n.is_empty():
				nameless += 1
			else:
				registered.append(n)
		else:
			nameless += 1

	var declared := PackedStringArray()
	for entry in engine:
		declared.append(String((entry as Dictionary).get("name", "")))

	var missing := PackedStringArray()
	for n in declared:
		if not registered.has(n):
			missing.append(n)
	var extra := PackedStringArray()
	for n in registered:
		if not declared.has(n):
			extra.append(n)

	results.append({
		"name": "EventBus registry is populated (guards against a vacuous pass)",
		"passed": not registered.is_empty() and not declared.is_empty(),
		"why": "registry=%d engine=%d" % [registered.size(), declared.size()],
	})
	results.append({
		"name": "every registry entry is a live Signal with a name",
		"passed": nameless == 0,
		"why": "%d entries were not a named Signal" % nameless,
	})
	results.append({
		"name": "every declared signal is registered",
		"passed": missing.is_empty(),
		"why": "declared but missing from owned_signals(): %s" % (
			", ".join(missing) if not missing.is_empty() else "none"),
	})
	results.append({
		"name": "registry declares no signal that does not exist",
		"passed": extra.is_empty(),
		"why": "registered but not declared: %s" % (
			", ".join(extra) if not extra.is_empty() else "none"),
	})
	results.append({
		"name": "registry and engine report the same signal count",
		"passed": registered.size() == declared.size(),
		"why": "registry=%d engine=%d" % [registered.size(), declared.size()],
	})

	bus.free()
	return results
