class_name StaminaComponent
extends Node

## Dodge/skill resource: dodges and skills spend stamina, it regenerates after a
## short delay, and exhaustion blocks spending until a threshold refill.
## The Player exposes try_spend_stamina()/restore_stamina() facades over this.
## Tolerant: works standalone (defaults) or driven by ProgressionComponent stats.

signal stamina_changed(current: float, maximum: float)
signal exhausted()
signal recovered()

const DEFAULT_MAX := 100.0
const DEFAULT_REGEN_PER_SECOND := 22.0
const DEFAULT_REGEN_DELAY := 0.6
const EXHAUST_REFILL_FRACTION := 0.3

var _max := DEFAULT_MAX
var _current := DEFAULT_MAX
var _regen_rate := DEFAULT_REGEN_PER_SECOND
var _regen_delay := DEFAULT_REGEN_DELAY
var _since_spend := 999.0
var _exhausted := false
var _progression: ProgressionComponent = null


func _ready() -> void:
	if _progression == null:
		_progression = get_parent().get_node_or_null("ProgressionComponent") as ProgressionComponent if get_parent() != null else null
	_rebuild_from_stats()
	_current = _max


## Player wires progression once. Safe to call before or after _ready.
func bind_progression(prog: ProgressionComponent) -> void:
	_progression = prog


func _rebuild_from_stats() -> void:
	_max = maxf(_stat(&"stamina_max_add", DEFAULT_MAX), 10.0)
	_regen_rate = maxf(_stat(&"stamina_regen_add", DEFAULT_REGEN_PER_SECOND), 0.0)
	_regen_delay = clampf(_stat(&"stamina_delay_add", DEFAULT_REGEN_DELAY), 0.0, 3.0)


func _stat(key: StringName, fallback: float) -> float:
	if _progression != null:
		return _progression.get_stat(key, fallback)
	return fallback


## Re-read progression stats (call after upgrades). Keeps the current fraction.
func refresh_from_stats() -> void:
	var frac := get_fraction()
	_rebuild_from_stats()
	_current = clampf(_max * frac, 0.0, _max)
	_emit_stamina()


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_since_spend += delta
	if _since_spend < _regen_delay or _regen_rate <= 0.0:
		return
	if _current >= _max:
		return
	_current = minf(_current + _regen_rate * delta, _max)
	if _exhausted and _current >= _max * EXHAUST_REFILL_FRACTION:
		_exhausted = false
		recovered.emit()
	_emit_stamina()


func _emit_stamina() -> void:
	stamina_changed.emit(_current, _max)
	if EventBus != null:
		EventBus.stamina_changed.emit(_current, _max)


## Spend `amount`; fails (returns false, no partial spend) when exhausted or
## when the balance is insufficient.
func try_spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if _exhausted:
		return false
	if _current < amount:
		_exhausted = true
		exhausted.emit()
		stamina_changed.emit(_current, _max)
		if EventBus != null:
			EventBus.stamina_changed.emit(_current, _max)
		return false
	_current -= amount
	_since_spend = 0.0
	if _current <= 0.0:
		_current = 0.0
		_exhausted = true
		exhausted.emit()
	_emit_stamina()
	return true


func restore(amount: float) -> void:
	if amount <= 0.0:
		return
	_current = minf(_current + amount, _max)
	if _exhausted and _current >= _max * EXHAUST_REFILL_FRACTION:
		_exhausted = false
		recovered.emit()
	_emit_stamina()


func restore_full() -> void:
	_current = _max
	_exhausted = false
	_emit_stamina()


func can_spend(amount: float) -> bool:
	return not _exhausted and _current >= amount


func is_exhausted() -> bool:
	return _exhausted


func get_current() -> float:
	return _current


func get_max() -> float:
	return _max


func get_fraction() -> float:
	if _max <= 0.0:
		return 0.0
	return clampf(_current / _max, 0.0, 1.0)


func reset_for_new_run() -> void:
	_rebuild_from_stats()
	_current = _max
	_since_spend = 999.0
	_exhausted = false


func get_debug_snapshot() -> Dictionary:
	return {"current": _current, "max": _max, "exhausted": _exhausted, "regen": _regen_rate}

