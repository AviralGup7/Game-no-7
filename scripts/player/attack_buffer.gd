class_name AttackBuffer
extends RefCounted

## One pending press, never an auto-attack queue. Tick only in active gameplay.
var remaining := 0.0


func push(window: float) -> void:
	remaining = maxf(window, 0.0)


func clear() -> void:
	remaining = 0.0


func tick(delta: float, attempt: Callable) -> void:
	if remaining <= 0.0:
		return
	remaining = maxf(remaining - maxf(delta, 0.0), 0.0)
	if remaining > 0.0 and bool(attempt.call()):
		clear()
