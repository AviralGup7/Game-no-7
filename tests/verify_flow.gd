extends SceneTree
## Launcher for the audio & feedback E2E verification.
## The main --script compiles before autoloads register, so this file
## references nothing and defers to verify_flow_inner.gd once the tree is live.
##   godot --headless --path . --script res://tests/verify_flow.gd

var _launched := false


func _initialize() -> void:
	print("VERIFY FLOW: booting real game")


func _process(_delta: float) -> bool:
	if not _launched:
		_launched = true
		var inner: GDScript = load("res://tests/verify_flow_inner.gd")
		if inner == null or not inner.can_instantiate():
			push_error("VERIFY FLOW: could not load inner harness")
			quit(2)
		else:
			root.add_child(inner.new())
	return false
