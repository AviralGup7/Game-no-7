extends SceneTree
## Headless test runner.
##   godot --headless --path . --import          (first run only)
##   godot --headless --path . --script res://tests/run_tests.gd
## Returns exit code 0 only when every unit test passes.

const UNIT_SUITES := [
	"res://tests/unit/test_save.gd",
	"res://tests/unit/test_combat.gd",
	"res://tests/unit/test_configs.gd",
	"res://tests/unit/test_scoring.gd",
]


func _initialize() -> void:
	var total := 0
	var failed := 0
	var failures: Array[String] = []
	for path in UNIT_SUITES:
		var script: GDScript = load(path)
		if script == null:
			failed += 1
			failures.append("Could not load suite: %s" % path)
			continue
		var cases: Array = script.call("suite")
		for c in cases:
			total += 1
			if not bool(c.get("passed", false)):
				failed += 1
				failures.append("%s :: %s — %s" % [path.get_file(), str(c.get("name", "")), str(c.get("why", ""))])
			else:
				pass

	print("========================================")
	print("GDScript unit tests: %d total, %d failed" % [total, failed])
	for f in failures:
		print("  FAIL  " + f)
	print("========================================")
	if failed == 0 and failures.is_empty():
		quit(0)
	else:
		quit(1)
