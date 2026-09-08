extends SceneTree
## Launcher for the soak stability run (release verification).
## The main --script compiles before autoloads register, so this file
## references nothing and defers to soak_runtime_inner.gd once live.
##   godot --headless --path . --script res://tests/soak_runtime.gd

var _launched := false


func _initialize() -> void:
	print("SOAK: booting real game")


func _process(_delta: float) -> bool:
	if not _launched:
		_launched = true
		var inner: GDScript = load("res://tests/soak_runtime_inner.gd")
		if inner == null or not inner.can_instantiate():
			push_error("SOAK: could not load inner harness")
			quit(2)
		else:
			root.add_child(inner.new())
	return false
