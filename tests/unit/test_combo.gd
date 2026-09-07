extends RefCounted

## Headless unit tests for the combo lifecycle state held by RunState (pure) plus the
## deterministic decay helper in Scoring. No tree/autoloads.

static func suite() -> Array:
	var results: Array = []
	var run := RunState.new()
	run.reset()

	results.append({"name": "fresh run combo == 0 / best_combo == 0",
		"passed": run.combo == 0 and run.best_combo == 0, "why": ""})

	run.set_combo(1)
	run.set_combo(5)
	results.append({"name": "combo tracks best_combo", "passed": run.best_combo == 5, "why": ""})
	run.set_combo(0)
	results.append({"name": "combo reset to 0 keeps best", "passed": run.combo == 0 and run.best_combo == 5, "why": ""})
	run.set_combo(-3)
	results.append({"name": "negative combo never stored", "passed": run.combo == 0, "why": ""})

	# reset clears everything (restart hygiene)
	run.score = 99
	run.currency = 7
	run.kills = 12
	run.combo = 5
	run.selected_upgrades = {&"power": 2}
	run.upgrade_choices = [&"power", &"swift"]
	run.reset()
	results.append({"name": "reset fully clears combo/score/currency/kills/choices",
		"passed": run.combo == 0 and run.best_combo == 0 and run.score == 0 and run.currency == 0 \
			and run.kills == 0 and run.upgrade_choices.is_empty() and run.selected_upgrades.is_empty(),
		"why": ""})

	# decay helper stays deterministic
	var decayed := Scoring.update_combo_over_time(8, 0.0, 10.0, 4.0)
	var alive := Scoring.update_combo_over_time(8, 0.0, 2.0, 4.0)
	results.append({"name": "combo decays after window; persists within window",
		"passed": decayed == 0 and alive == 8, "why": ""})

	# negative base decays to 0
	results.append({"name": "combo decay handles stale/negative input",
		"passed": Scoring.update_combo_over_time(-1, 0.0, 10.0, 4.0) == 0, "why": ""})
	return results
