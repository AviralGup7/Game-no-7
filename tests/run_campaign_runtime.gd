extends SceneTree
## Standalone headless entry point for the campaign runtime suite:
##
##   godot --headless --path . --script res://tests/run_campaign_runtime.gd
##
## Run it through scripts/run_campaign_runtime.sh, which isolates the save
## profile; the environment guard below keeps a bare invocation from writing a
## fresh campaign into a real player save (same contract as tests/verify_campaign.gd).
##
## Load-order contract — do not add game-class references or preloads here:
## Godot compiles the --script main loop BEFORE the project autoloads are
## registered. The harness is runtime-loaded on the first live frame, when the
## autoloads exist. The suite is also embedded in tests/run_tests.gd (deferred
## phase), so the CI godot-tests job and the 4.7.2 diagnostics job run it too.

var _launched := false
var _harness = null


func _process(_delta: float) -> bool:
	if not _launched:
		_launched = true
		if OS.get_environment("STATION_ZERO_TEST_PROFILE") != "1":
			push_error("Use scripts/run_campaign_runtime.sh to isolate player save data")
			quit(2)
			return false
		var script: GDScript = load("res://tests/campaign_runtime/campaign_runtime_inner.gd")
		if script == null or not script.can_instantiate():
			push_error("Campaign runtime harness could not compile")
			quit(2)
			return false
		_harness = script.new()
		root.add_child(_harness)
		return false
	if _harness != null and bool(_harness.call("is_finished")):
		var cases: Array = []
		var raw: Variant = _harness.call("get_cases")
		if raw is Array:
			cases = raw
		var failed := 0
		for c in cases:
			if not (c is Dictionary) or not bool((c as Dictionary).get("passed", false)):
				failed += 1
		print("========================================")
		print(String(_harness.call("get_report_line")))
		for c in cases:
			if c is Dictionary and not bool((c as Dictionary).get("passed", false)):
				print("  FAIL  " + String((c as Dictionary).get("name", "")))
		print("========================================")
		quit(0 if failed == 0 else 1)
		return false
	return false
