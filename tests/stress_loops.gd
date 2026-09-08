extends SceneTree
## Launcher for the extended-loop stress pass (release verification).
## The main --script compiles before autoloads register, so this file
## references nothing and defers to stress_loops_inner.gd once live.
##   godot --headless --path . --script res://tests/stress_loops.gd

var _launched := false


func _initialize() -> void:
	print("STRESS LOOPS: booting real game")


func _process(_delta: float) -> bool:
	if not _launched:
		_launched = true
		var inner: GDScript = load("res://tests/stress_loops_inner.gd")
		if inner == null or not inner.can_instantiate():
			push_error("STRESS LOOPS: could not load inner harness")
			quit(2)
		else:
			root.add_child(inner.new())
	return false
