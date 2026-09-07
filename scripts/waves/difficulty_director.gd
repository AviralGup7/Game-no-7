class_name DifficultyDirector
extends RefCounted

## Adaptive difficulty: watches run performance (damage taken rate, kill pace,
## deaths avoided, heal reliance) and outputs gentle scalar nudges so skilled
## play is rewarded with richer, spicier waves while struggling runs ease off.
## Pure accumulator + pure queries: the WaveManager feeds events and reads
## multipliers before generating each wave. Never exceeds ±25%.

const WINDOW_SECONDS := 30.0
const MAX_SAMPLES := 64
const MAX_NUDGE := 0.25

var _damage_samples: Array = []  # [{t, amount}]
var _kill_samples: Array = []    # [{t}]
var _now := 0.0
var _player_max_hp := 100.0


func _init(player_max_hp: float = 100.0) -> void:
	_player_max_hp = maxf(player_max_hp, 1.0)


func reset(player_max_hp: float = 100.0) -> void:
	_damage_samples.clear()
	_kill_samples.clear()
	_now = 0.0
	_player_max_hp = maxf(player_max_hp, 1.0)


## Advance the clock (call with the run's elapsed seconds each wave boundary).
func set_time(now: float) -> void:
	_now = maxf(now, 0.0)
	_prune()


func record_damage_taken(amount: float) -> void:
	if amount <= 0.0:
		return
	_damage_samples.append({"t": _now, "amount": amount})
	_prune()


func record_kill() -> void:
	_kill_samples.append({"t": _now})
	_prune()


func _prune() -> void:
	var cutoff := _now - WINDOW_SECONDS
	while not _damage_samples.is_empty() and float(_damage_samples[0]["t"]) < cutoff:
		_damage_samples.pop_front()
	while not _kill_samples.is_empty() and float(_kill_samples[0]["t"]) < cutoff:
		_kill_samples.pop_front()
	while _damage_samples.size() > MAX_SAMPLES:
		_damage_samples.pop_front()
	while _kill_samples.size() > MAX_SAMPLES:
		_kill_samples.pop_front()


## Damage taken per second across the window, normalized by max HP.
func recent_dps_taken() -> float:
	var total := 0.0
	for s in _damage_samples:
		total += float(s["amount"])
	return total / WINDOW_SECONDS / _player_max_hp


## Kills per second across the window.
func recent_kill_rate() -> float:
	return float(_kill_samples.size()) / WINDOW_SECONDS


## Performance score in [-1, 1]: +1 = dominating (fast kills, no damage),
## -1 = struggling (heavy damage, slow kills).
func performance_score() -> float:
	# Fast clean kills push up; damage taken pushes down. Tuned so an average
	# run hovers near 0.
	var kill_term := clampf((recent_kill_rate() - 0.35) * 2.5, -1.0, 1.0)
	var dps_term := clampf((recent_dps_taken() - 0.04) * 12.0, 0.0, 1.5)
	return clampf(kill_term - dps_term, -1.0, 1.0)


## Full multiplier set for the NEXT wave. Dominating players get slightly
## stronger, richer waves; struggling players get a gentler mix.
func next_wave_multipliers() -> Dictionary:
	var p := performance_score()
	var nudge := p * MAX_NUDGE
	return {
		"hp_mult": 1.0 + nudge,
		"damage_mult": 1.0 + nudge * 0.6,
		"speed_mult": 1.0 + nudge * 0.3,
		"count_bonus": _count_bonus(p),
		"score_mult": 1.0 + maxf(nudge, 0.0),
		"elite_bonus": maxf(nudge, 0.0) * 0.4,
	}


func _count_bonus(performance: float) -> int:
	if performance > 0.55:
		return 2
	if performance > 0.25:
		return 1
	if performance < -0.55:
		return -2
	if performance < -0.25:
		return -1
	return 0


## Should the director suggest a breather (skip mutators this wave)?
func suggest_breather() -> bool:
	return performance_score() < -0.6


## Should the director spice things up (force an extra mutator)?
func suggest_spice() -> bool:
	return performance_score() > 0.6


func get_debug_snapshot() -> Dictionary:
	return {
		"dps_taken": recent_dps_taken(),
		"kill_rate": recent_kill_rate(),
		"performance": performance_score(),
		"samples": _damage_samples.size() + _kill_samples.size(),
	}
