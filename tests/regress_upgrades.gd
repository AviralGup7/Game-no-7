extends SceneTree
## Launcher for the upgrade/scorekeeper regression probe.
##   godot --headless --path . --script res://tests/regress_upgrades.gd

var _launched := false


func _initialize() -> void:
	print("REGRESS: booting real game")


func _process(_delta: float) -> bool:
	if not _launched:
		_launched = true
		var inner: GDScript = load("res://tests/regress_upgrades_inner.gd")
		if inner == null or not inner.can_instantiate():
			push_error("REGRESS: could not load inner harness")
			quit(2)
		else:
			root.add_child(inner.new())
	return false
