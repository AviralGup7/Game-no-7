extends RefCounted
## Runtime-loaded stage for the campaign runtime harness.
##
## Load-order contract (see tests/run_tests.gd): the runner compiles before the
## project autoloads exist, so it never preloads this file or the harness. It
## loads this stage at _process() time, when autoloads are registered, and this
## stage in turn load()s the harness script, which may reference game classes
## and autoloads.

const HARNESS_PATH := "res://tests/campaign_runtime/campaign_runtime_inner.gd"


func create_harness(host: Node) -> Node:
	var script: GDScript = load(HARNESS_PATH)
	if script == null or not script.can_instantiate():
		return null
	var harness: Node = script.new() as Node
	if harness == null:
		return null
	host.add_child(harness)
	return harness


func is_finished(harness: Node) -> bool:
	return bool(harness.call("is_finished"))


func get_cases(harness: Node) -> Array:
	var raw: Variant = harness.call("get_cases")
	return raw if raw is Array else []
