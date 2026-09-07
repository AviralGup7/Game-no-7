extends RefCounted

## Headless unit tests for deterministic scoring helpers. Scoring is a registered
## class_name, so its static helpers are typed.

static func suite() -> Array:
	var results: Array = []

	results.append({
		"name": "kill score positive base scales with combo+multiplier",
		"passed": Scoring.calculate_kill_score(10, 0, 1.0) == 10
			and Scoring.calculate_kill_score(10, 5, 2.0) == 30,
		"why": "",
	})

	results.append({
		"name": "kill score never negative",
		"passed": Scoring.calculate_kill_score(10, -3, -1.0) >= 0,
		"why": "",
	})

	results.append({
		"name": "combo decays after window",
		"passed": Scoring.update_combo_over_time(8, 0.0, 5.0, 2.0) == 0
			and Scoring.update_combo_over_time(8, 0.0, 0.5, 2.0) == 8,
		"why": "",
	})

	var a := Scoring.calculate_kill_score(10, 4, 1.5)
	var b := Scoring.calculate_kill_score(10, 4, 1.5)
	results.append({
		"name": "deterministic for identical inputs",
		"passed": a == b,
		"why": "",
	})
	return results
