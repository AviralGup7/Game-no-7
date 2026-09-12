extends SceneTree
## Load the suite after autoload registration; --script compilation happens before it.
## godot --headless --path . --script res://tests/run_player_tests.gd


var _launched := false


func _process(_delta: float) -> bool:
	if not _launched:
		_launched = true
		# Like run_tests.gd, start on the first live frame: deferred calls from
		# _initialize can flush before autoloads and Node3D transforms are ready.
		_run()
	return false


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
	# Player Foley lives in a nested spatial bank, not only direct 2D children.
	# Drain both banks before driver teardown so playback resources can retire.
	var audio := root.get_node_or_null("AudioManager")
	if audio != null:
		audio.call("isolate_run")
		_stop_audio(audio)
	await create_timer(0.1).timeout
	quit(0 if failures.is_empty() else 1)


func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()
	elif node is AudioStreamPlayer2D:
		(node as AudioStreamPlayer2D).stop()
	for child in node.get_children():
		_stop_audio(child)
