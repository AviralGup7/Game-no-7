class_name WeightedTable
extends RefCounted

## Deterministic weighted-random picker.
## Entries pair an opaque value with a positive weight; `roll()` maps a uniform
## [0,1) sample to an entry so planners can drive selection from any RNG stream
## (or from fixed test values). Headless-testable, no tree access.

var _values: Array = []
var _weights: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0


func _init(entries: Array = []) -> void:
	for e in entries:
		if e is Array and e.size() >= 2:
			add(e[0], float(e[1]))


## Add one entry. Non-positive weights are clamped to a tiny epsilon so the
## entry stays selectable-but-rare instead of silently vanishing.
const MIN_WEIGHT := 0.0001
const MAX_WEIGHT := 1000000.0
const MAX_TOTAL_WEIGHT := 1e9


func add(value: Variant, weight: float) -> void:
	_values.append(value)
	var w := _sanitize_weight(weight)
	_weights.append(w)
	_recalculate_total()


func remove_at(index: int) -> void:
	if index < 0 or index >= _values.size():
		return
	_values.remove_at(index)
	_weights.remove_at(index)
	# Rebuild instead of subtracting a PackedFloat32 value repeatedly. This
	# avoids accumulated drift and repairs the aggregate if old content was bad.
	_recalculate_total()


func set_weight(index: int, weight: float) -> void:
	if index < 0 or index >= _values.size():
		return
	_weights[index] = _sanitize_weight(weight)
	_recalculate_total()


func _sanitize_weight(weight: float) -> float:
	if not is_finite(weight):
		return MIN_WEIGHT
	return clampf(weight, MIN_WEIGHT, MAX_WEIGHT)


func _recalculate_total() -> void:
	_total = 0.0
	for weight in _weights:
		_total += float(weight)
	if not is_finite(_total) or _total <= 0.0:
		_total = 0.0
	elif _total > MAX_TOTAL_WEIGHT:
		# Preserve relative probabilities while keeping the cumulative range
		# representable and stable for very large generated tables.
		var scale := MAX_TOTAL_WEIGHT / _total
		for i in range(_weights.size()):
			_weights[i] *= scale
		_total = MAX_TOTAL_WEIGHT


func size() -> int:
	return _values.size()


func is_empty() -> bool:
	return _values.is_empty()


func total_weight() -> float:
	return _total


func value_at(index: int) -> Variant:
	return _values[index]


func weight_at(index: int) -> float:
	return _weights[index]


func clear() -> void:
	_values.clear()
	_weights.clear()
	_total = 0.0


## Map a uniform sample in [0,1) to an entry index. Returns -1 when empty.
func roll_index(sample: float) -> int:
	if _values.is_empty() or not is_finite(_total) or _total <= 0.0:
		return -1
	# A malformed external sample must be deterministic, not turn the target
	# into NaN and silently select the final entry.
	if not is_finite(sample):
		sample = 0.0
	var target := clampf(sample, 0.0, 0.9999999) * _total
	var acc := 0.0
	for i in range(_values.size()):
		acc += _weights[i]
		if target < acc:
			return i
	return _values.size() - 1


## Map a uniform sample to a value; returns `fallback` when empty.
func roll(sample: float, fallback: Variant = null) -> Variant:
	var idx := roll_index(sample)
	if idx < 0:
		return fallback
	return _values[idx]


## Roll using a RandomNumberGenerator directly.
func roll_with_rng(rng: RandomNumberGenerator, fallback: Variant = null) -> Variant:
	if rng == null:
		return fallback
	return roll(rng.randf(), fallback)


## Roll using an RngService stream salt.
func roll_with_service(svc: RngService, salt: int, fallback: Variant = null) -> Variant:
	if svc == null:
		return fallback
	return roll(svc.stream(salt).randf(), fallback)


## Probability of entry `index` being picked (0 when empty/invalid).
func probability_of(index: int) -> float:
	if index < 0 or index >= _values.size() or _total <= 0.0:
		return 0.0
	return _weights[index] / _total


## Return up to `count` DISTINCT values (no replacement). Fewer when the table
## holds fewer entries. Driven by the provided samples array (extra samples
## ignored, missing samples treated as 0).
func roll_unique(samples: Array, count: int) -> Array:
	var out: Array = []
	if _values.is_empty() or count <= 0:
		return out
	var remaining_values := _values.duplicate()
	var remaining_weights := Array(_weights)
	var remaining_total := _total
	var n := mini(count, remaining_values.size())
	for k in range(n):
		var sample := 0.0
		if k < samples.size():
			var raw_sample := float(samples[k])
			sample = clampf(raw_sample, 0.0, 0.9999999) if is_finite(raw_sample) else 0.0
		if not is_finite(remaining_total) or remaining_total <= 0.0:
			break
		var target := sample * remaining_total
		var acc := 0.0
		var chosen := remaining_values.size() - 1
		for i in range(remaining_values.size()):
			acc += float(remaining_weights[i])
			if target < acc:
				chosen = i
				break
		out.append(remaining_values[chosen])
		remaining_total -= float(remaining_weights[chosen])
		remaining_values.remove_at(chosen)
		remaining_weights.remove_at(chosen)
	return out


func to_debug_string() -> String:
	var parts: PackedStringArray = []
	for i in range(_values.size()):
		parts.append("%s:%.2f" % [str(_values[i]), _weights[i]])
	return "WeightedTable[%s]" % ", ".join(parts)
