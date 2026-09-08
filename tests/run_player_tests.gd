extends SceneTree
## Load the suite after autoload registration; --script compilation happens before it.
## godot --headless --path . --script res://tests/run_player_tests.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var script: GDScript = load("res://tests/integration/test_player.gd")
	if script == null or not script.can_instantiate():
		push_error("Player suite failed to compile")
		quit(1)
		return
	var suite: RefCounted = script.new()
	var result: Dictionary = suite.run(root)
	var failures: Array = result.get("failures", ["Suite returned no results"])
	print("Player tests: %d checks, %d failed" % [result.get("checks", 0), failures.size()])
	for failure in failures:
		print("FAIL: " + String(failure))
	# Drain the pooled audio commands before shutting down the dummy audio driver.
	for child in root.get_node("AudioManager").get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
	await create_timer(0.1).timeout
	quit(0 if failures.is_empty() else 1)
