extends SceneTree
## Runtime-load the campaign harness after autoload registration. Do not add
## project class references/preloads here: --script compiles before autoloads.

var _launched := false


func _process(_delta: float) -> bool:
	if not _launched:
		_launched = true
		if OS.get_environment("STATION_ZERO_TEST_PROFILE") != "1":
			push_error("Use scripts/run_campaign_validation.sh to isolate player save data")
			quit(2)
			return false
		var harness: GDScript = load("res://tests/verify_campaign_inner.gd")
		if harness == null or not harness.can_instantiate():
			push_error("Campaign harness could not compile")
			quit(2)
		else:
			root.add_child(harness.new())
	return false
