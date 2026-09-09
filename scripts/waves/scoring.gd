class_name Scoring
## Pure, deterministic scoring helpers. Kept free of scene/node state so unit tests
## can exercise them headlessly and so scoring never depends on the frame loop.

## Base score for killing one enemy, including optional combo and a global
## multiplier (e.g. from upgrades / run modifiers). Clamped non-negative.
static func calculate_kill_score(enemy_score_value: int, combo: int, multiplier: float) -> int:
	if enemy_score_value <= 0:
		return 0
	var combo_bonus := maxi(combo, 0)
	var raw := float(enemy_score_value + combo_bonus) * maxf(multiplier, 0.0)
	return maxi(int(round(raw)), 0)


## Combo decay/time handling helper: returns the combo after `delta_seconds`
## elapsed with the given combo window and starting value.
static func update_combo_over_time(current_combo: int, last_kill_time: float, now: float, combo_window: float) -> int:
	if current_combo <= 0:
		return 0
	if now - last_kill_time > maxf(combo_window, 0.1):
		return 0
	return current_combo


## Wave completion bonus with difficulty scaling.
static func calculate_wave_bonus(wave_number: int, base: int, multiplier: float) -> int:
	var w := maxi(wave_number, 1)
	var raw := float(maxi(base, 0)) * maxf(multiplier, 1.0) * (0.5 + float(w) * 0.25)
	return maxi(int(round(raw)), 0)
