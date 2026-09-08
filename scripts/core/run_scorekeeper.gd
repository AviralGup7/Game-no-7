class_name RunScorekeeper
extends RefCounted

## Run scoring, extracted from GameRoot. Owns exactly-once kill scoring (combo,
## multipliers, currency), combo expiry, and wave-completion bonuses for one
## RunState. GameRoot feeds it enemy_killed / process ticks / bonus calls and
## supplies the player-stat provider; all EventBus score/currency/combo signals
## are emitted from here.

## Combo lifecycle tuning. Combos decay to 0 after this many seconds without a kill.
const COMBO_WINDOW_SECONDS: float = 4.0

var _run: RunState = null
var _stat_provider: Callable = Callable()
var _last_kill_time: float = 0.0
var _combat_log := CombatLog.new()


## Recent kill feed (debug views / post-run summary).
func get_combat_log() -> CombatLog:
	return _combat_log


## Bind to a run + a (key, base) -> float derived-stat provider (GameRoot's
## player progression lookup). The same RunState object is re-bound every run.
func bind(run: RunState, stat_provider: Callable) -> void:
	_run = run
	_stat_provider = stat_provider
	_last_kill_time = 0.0


func reset_run(run: RunState) -> void:
	_run = run
	_last_kill_time = 0.0
	_combat_log.clear()
	_combat_log.record(CombatLog.KIND_SYSTEM, "Run started")


## Exactly-once per enemy_killed: bump combo, award multiplied score + currency.
func record_kill(score_value: int, currency_value: int, archetype_id: StringName = &"") -> void:
	if _run == null or not _run.player_alive:
		return
	_run.add_kill()
	var multiplier := _score_multiplier()
	# Raise combo by one then award score including the streak bonus; record the kill
	# time so the combo can expire after the window.
	_run.set_combo(_run.combo + 1)
	_last_kill_time = _run.elapsed_seconds
	var gained := Scoring.calculate_kill_score(score_value, _run.combo, multiplier)
	_run.add_score(gained)
	_combat_log.log_kill(archetype_id, gained)
	EventBus.score_changed.emit(_run.score, gained)
	var currency_reward := maxi(int(round(float(currency_value) * _currency_multiplier())), 0)
	_run.add_currency(currency_reward)
	EventBus.currency_changed.emit(_run.currency, currency_reward)
	EventBus.combo_changed.emit(_run.combo, _run.best_combo)


## Reset the combo to 0 when the kill window elapses without another kill. Emits
## only on an actual value change, and only while the run is still live.
func tick_combo() -> void:
	if _run == null or _run.combo <= 0:
		return
	if _run.elapsed_seconds - _last_kill_time > COMBO_WINDOW_SECONDS:
		_run.set_combo(0)
		EventBus.combo_changed.emit(0, _run.best_combo)


func award_bonus(bonus: int) -> void:
	if _run == null or not _run.player_alive or bonus <= 0:
		return
	_run.add_score(bonus)
	_combat_log.log(CombatLog.KIND_SYSTEM, "Wave bonus +%d" % bonus)
	EventBus.score_changed.emit(_run.score, bonus)


func _score_multiplier() -> float:
	return 1.0 + _derived_stat(&"score_multiplier_add", 0.0)


func _currency_multiplier() -> float:
	return 1.0 + _derived_stat(&"currency_multiplier_add", 0.0)


func _derived_stat(key: StringName, base: float) -> float:
	if _stat_provider.is_valid():
		return float(_stat_provider.call(key, base))
	return base

## Hardened: clamp score delta.
func _validated_score_delta(d: int) -> int:
	if d < 0:
		return 0
	return mini(d, 1000000)

