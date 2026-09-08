class_name ComboChain
extends RefCounted

## Light-melee combo state, extracted from AttackController. Tracks the current
## combo step plus the chain window (a press during a landed hit's recovery, while
## the window is open and steps remain, chains into the next escalating swing and
## skips the cooldown). Step multipliers escalate damage/knockback per swing.
## Pure (no tree/autoload access): fully headless-testable.


var _step := 0          # 0 = no combo in progress, else 1..max_steps
var _chain_allowed := false


func reset() -> void:
	_step = 0
	_chain_allowed = false


## Begin a swing at `step` (fresh combos start at 1).
func begin(step: int) -> void:
	_step = maxi(step, 1)
	_chain_allowed = false


## The recovery just resolved a hit: chaining is allowed until the window lapses.
func open_chain() -> void:
	_chain_allowed = true


## The chain window lapsed without a chained input: no more chaining this recovery.
func expire() -> void:
	_chain_allowed = false


## Finish the attack: back to neutral, combo over.
func finish() -> void:
	reset()


## Request a chained swing. Returns the next step (2, 3, ...) when chaining is
## legal, or 0 when the window lapsed / the combo is at max steps.
func try_chain(max_steps: int) -> int:
	if not _chain_allowed or _step >= max_steps:
		return 0
	return _step + 1


## Current combo step: 0 when no combo is in progress, else 1..max_steps.
func step() -> int:
	return _step


## True while the last landed hit can still chain into the next combo step.
func is_chain_ready() -> bool:
	return _chain_allowed


## Multiplier applied to damage for the current combo step (falls back to 1.0).
func damage_factor(multipliers: Array[float]) -> float:
	return _step_multiplier(multipliers, _step)


## Multiplier applied to knockback for the current combo step (falls back to 1.0).
func knockback_factor(multipliers: Array[float]) -> float:
	return _step_multiplier(multipliers, _step)


func _step_multiplier(multipliers: Array[float], step: int) -> float:
	if step <= 0:
		return 1.0
	if step <= multipliers.size():
		return multipliers[step - 1]
	return 1.0

## Hardened: clamp combo window.
func _validated_combo_window(w: float) -> float:
	if not is_finite(w) or w <= 0.0:
		return 0.4
	return clampf(w, 0.05, 2.0)

