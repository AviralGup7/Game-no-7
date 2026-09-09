class_name StatusEffect
extends RefCounted

## Runtime instance of one status effect on one entity. Tracks stacks, remaining
## duration and tick accrual; the owning StatusManager advances it via tick() and
## folds its modifiers into cached aggregates. Headless-testable (no tree access).
##
## Config resources are never changed at runtime. Caster-side status power is
## copied into these instance fields when the manager creates/reapplies an effect.
##
## This class is private to scripts/status/: nothing outside the subsystem holds a
## StatusEffect, which is what lets StatusManager cache derived state (speed and
## damage aggregates, shield pool) without an invalidation leak. An effect is
## mutated only by tick(), reapply() and the shield methods below.

var config: StatusEffectConfig = null
var stacks: int = 1
var remaining: float = 0.0
var source: Node = null
var source_id: StringName = &"unknown"
var duration_multiplier: float = 1.0
var dot_multiplier: float = 1.0
var hot_multiplier: float = 1.0

## This effect's own unspent shield capacity. It used to live in a parallel
## Dictionary on the manager keyed by effect id, which meant every application,
## removal and absorbed hit did hash lookups/insertions on a second table that
## could not drift from this one (and did not have to be kept in sync).
var shield_layer: float = 0.0

var _tick_accrual: float = 0.0


func _init(cfg: StatusEffectConfig = null, applied_stacks: int = 1, from: Node = null) -> void:
	config = cfg
	source = from
	_apply_source_id(from)
	stacks = maxi(applied_stacks, 1)
	if cfg != null:
		stacks = mini(stacks, cfg.max_stacks)
		remaining = _clamped_duration(cfg.duration)
		shield_layer = shield_total()


## Copy build modifiers onto this runtime object. The shared .tres stays immutable.
## Ceiling on a status-physics lock. `validate()` refuses a *permanent* stun/root, and this
## refuses a long one: an authoring slip like `duration = 30` next to `stuns = true` used to
## be documented as capped at 3 s while the code only raised `remaining` (maxf), so the cap
## never applied and a player could be frozen for half a minute by one bad .tres.
const SOFT_LOCK_CAP_SECONDS := 3.0


func _clamped_duration(desired: float) -> float:
	var value := maxf(desired, 0.0) if is_finite(desired) else 0.0
	if config != null and (config.stuns or config.roots):
		value = minf(value, SOFT_LOCK_CAP_SECONDS)
	return value


func set_power_modifiers(duration_mult: float = 1.0, dot_mult: float = 1.0, hot_mult: float = 1.0) -> void:
	duration_multiplier = clampf(duration_mult, 0.05, 10.0) if is_finite(duration_mult) else 1.0
	dot_multiplier = clampf(dot_mult, 0.0, 10.0) if is_finite(dot_mult) else 1.0
	hot_multiplier = clampf(hot_mult, 0.0, 10.0) if is_finite(hot_mult) else 1.0
	if config != null and not config.is_permanent():
		var base := config.duration * duration_multiplier
		# A build can stretch a lock; the soft-lock cap still holds, and a small
		# multiplier cannot make it vanish outright either (it is a floor at `base`).
		remaining = _clamped_duration(maxf(remaining, base))


func effect_id() -> StringName:
	return config.effect_id if config != null else &""


func is_permanent() -> bool:
	return config == null or config.is_permanent()


func is_expired() -> bool:
	return not is_permanent() and remaining <= 0.0


## Merge a re-application according to the config's stack mode. Reapplying a
## stack-mode ADD effect refreshes its duration; REFRESH preserves stacks; RESET
## replaces the stack count. All modes clamp at the authored max.
##
## Returns whether the *modifier* state changed (stacks or shield capacity), which is
## exactly what the manager needs to know to invalidate its cached aggregates — a
## duration-only refresh is a read-cheap no-op for them.
func reapply(extra_stacks: int = 1, from: Node = null, duration_mult: float = 1.0, dot_mult: float = 1.0, hot_mult: float = 1.0) -> bool:
	if config == null:
		return false
	var stacks_before := stacks
	var shield_before := shield_layer
	if from != null:
		source = from
		_apply_source_id(from)
	set_power_modifiers(duration_mult, dot_mult, hot_mult)
	var full_duration := config.duration * duration_multiplier
	match config.stack_mode:
		StatusEffectConfig.STACK_ADD:
			stacks = mini(stacks + maxi(extra_stacks, 1), config.max_stacks)
			remaining = _clamped_duration(full_duration)
		StatusEffectConfig.STACK_RESET:
			stacks = mini(maxi(extra_stacks, 1), config.max_stacks)
			remaining = _clamped_duration(full_duration)
		_:  # STACK_REFRESH (default)
			remaining = _clamped_duration(full_duration)
	# Shield capacity follows the new stack count per the manager's stack-mode policy
	# (it decides how much of the increase to grant), so the caller writes shield_layer.
	return stacks != stacks_before or shield_layer != shield_before


## Spend from this effect's shield layer. Returns the damage left over.
func absorb(amount: float) -> float:
	var remaining_damage := maxf(amount, 0.0)
	if shield_layer <= 0.0 or not is_finite(shield_layer):
		return remaining_damage
	var absorbed := minf(shield_layer, remaining_damage)
	shield_layer = maxf(shield_layer - absorbed, 0.0)
	return maxf(remaining_damage - absorbed, 0.0)


func _apply_source_id(from: Node) -> void:
	var archetype_source := from as EnemyBase
	if archetype_source != null:
		source_id = archetype_source.get_archetype_id()
	elif from != null:
		source_id = StringName(from.name)


## Advance time. Returns the number of full ticks that elapsed this step. Tick
## accrual is capped to the portion of this frame during which the effect was
## active, preventing a large frame from dealing damage after expiry.
func tick(delta: float) -> int:
	if config == null or delta <= 0.0 or not is_finite(delta) or is_expired():
		return 0
	var active_delta := delta
	if not is_permanent():
		active_delta = minf(delta, remaining)
		remaining = maxf(remaining - delta, 0.0)
	if not is_finite(config.tick_interval) or config.tick_interval <= 0.0:
		return 0
	_tick_accrual += clampf(active_delta, 0.0, 60.0)
	# Guard huge hitches: one frame can only yield a bounded number of ticks.
	var ticks := 0
	var budget := 64
	while _tick_accrual >= config.tick_interval and budget > 0:
		_tick_accrual -= config.tick_interval
		ticks += 1
		budget -= 1
	if budget == 0:
		_tick_accrual = 0.0
	return ticks


func dot_per_tick() -> float:
	if config == null:
		return 0.0
	var v := config.dot_per_second * dot_multiplier * config.tick_interval * float(maxi(stacks, 1))
	return clampf(v, 0.0, 10000.0) if is_finite(v) else 0.0


func hot_per_tick() -> float:
	if config == null:
		return 0.0
	var v := config.hot_per_second * hot_multiplier * config.tick_interval * float(maxi(stacks, 1))
	return clampf(v, 0.0, 10000.0) if is_finite(v) else 0.0


func move_speed_factor() -> float:
	return _stacked_factor(config.move_speed_factor if config != null else 1.0)


func damage_factor() -> float:
	return _stacked_factor(config.damage_factor if config != null else 1.0)


func received_damage_factor() -> float:
	return _stacked_factor(config.received_damage_factor if config != null else 1.0)


## A factor is per-stack multiplicative: 0.5 at 2 stacks is 0.25. Never stall the game
## on malformed/NaN saves — a finite, non-negative answer is guaranteed.
func _stacked_factor(base: float) -> float:
	if not is_finite(base) or base < 0.0:
		return 1.0
	if base == 1.0:
		# The overwhelmingly common case (most effects do not touch this axis) skips
		# the transcendental entirely; pow() ran per effect per query per frame before.
		return 1.0
	var v := pow(base, float(maxi(stacks, 1)))
	return clampf(v, 0.0, 10.0) if is_finite(v) else 1.0


func shield_total() -> float:
	if config == null:
		return 0.0
	return config.shield_amount * float(stacks)


func grants_shield() -> bool:
	return config != null and config.shield_amount > 0.0


func get_debug_snapshot() -> Dictionary:
	return {
		"effect": String(effect_id()),
		"stacks": stacks,
		"remaining": remaining,
		"duration_multiplier": duration_multiplier,
		"dot_multiplier": dot_multiplier,
		"shield": shield_layer,
	}
