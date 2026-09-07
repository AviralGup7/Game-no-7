class_name FakeClock
extends RefCounted
## Deterministic clock for tests. Injectable wherever a system asks for a time
## source (see HealthComponent.set_time_source). Advances explicitly, never by wall
## clock, so timing-sensitive tests are reproducible.

var _now_seconds: float = 0.0


func set_time(value: float) -> void:
	_now_seconds = maxf(value, 0.0)


func advance(seconds: float) -> void:
	_now_seconds += maxf(seconds, 0.0)


func now() -> float:
	return _now_seconds
