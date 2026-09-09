class_name StatusEffect
extends RefCounted

## Runtime instance of one status effect on one entity. Tracks stacks, remaining
## duration and tick accrual; the owning StatusManager advances it via tick()
## and reads the aggregated modifiers. Headless-testable (no tree access).
##
## Config resources are never changed at runtime. Caster-side status power is
## copied into these instance fields when the manager creates/reapplies an effect.

var config: StatusEffectConfig = null
var stacks: int = 1
var remaining: float = 0.0
var source: Node = null
var source_id: StringName = &"unknown"
var duration_multiplier: float = 1.0
var dot_multiplier: float = 1.0
var hot_multiplier: float = 1.0

var _tick_accrual: float = 0.0


func _init(cfg: StatusEffectConfig = null, applied_stacks: int = 1, from: Node = null) -> void:
	config = cfg
	source = from
	var archetype_source := from as EnemyBase
	if archetype_source != null:
		source_id = archetype_source.get_archetype_id()
	elif from != null:
		source_id = StringName(from.name)
	stacks = maxi(applied_stacks, 1)
	if cfg != null:
		stacks = mini(stacks, cfg.max_stacks)
		remaining = cfg.duration


## Copy build modifiers onto this runtime object. The shared .tres stays immutable.
func set_power_modifiers(duration_mult: float = 1.0, dot_mult: float = 1.0, hot_mult: float = 1.0) -> void:
	duration_multiplier = clampf(duration_mult, 0.05, 10.0) if is_finite(duration_mult) else 1.0
	dot_multiplier = clampf(dot_mult, 0.0, 10.0) if is_finite(dot_mult) else 1.0
	hot_multiplier = clampf(hot_mult, 0.0, 10.0) if is_finite(hot_mult) else 1.0
	if config != null and not config.is_permanent():
		var base := config.duration * duration_multiplier
		# Hard stop: status-physics soft-locks (stun/root) never outlast a short window
		# even if a future save carries an inflated duration multiplier.
		if config.stuns or config.roots:
			base = minf(base, 3.0)
		remaining = maxf(remaining, base)


func effect_id() -> StringName:
	return config.effect_id if config != null else &""


func is_permanent() -> bool:
	return config == null or config.is_permanent()


func is_expired() -> bool:
	return not is_permanent() and remaining <= 0.0


## Merge a re-application according to the config's stack mode. Reapplying a
## stack-mode ADD effect refreshes its duration; REFRESH preserves stacks; RESET
## replaces the stack count. All modes clamp at the authored max.
func reapply(extra_stacks: int = 1, from: Node = null, duration_mult: float = 1.0, dot_mult: float = 1.0, hot_mult: float = 1.0) -> void:
	if config == null:
		return
	if from != null:
		source = from
	var archetype_source := from as EnemyBase
	if archetype_source != null:
		source_id = archetype_source.get_archetype_id()
	elif from != null:
		source_id = StringName(from.name)
	set_power_modifiers(duration_mult, dot_mult, hot_mult)
	var full_duration := config.duration * duration_multiplier
	match config.stack_mode:
		StatusEffectConfig.STACK_ADD:
			stacks = mini(stacks + maxi(extra_stacks, 1), config.max_stacks)
			remaining = full_duration
		StatusEffectConfig.STACK_RESET:
			stacks = mini(maxi(extra_stacks, 1), config.max_stacks)
			remaining = full_duration
		_:  # STACK_REFRESH (default)
			remaining = full_duration


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
	if config == null:
		return 1.0
	var base := config.move_speed_factor
	if not is_finite(base) or base < 0.0:
		return 1.0
	# Never stall the game on malformed/NaN saves — a finite factor is guaranteed.
	var v := pow(base, float(maxi(stacks, 1)))
	return clampf(v, 0.0, 10.0) if is_finite(v) else 1.0


func damage_factor() -> float:
	if config == null:
		return 1.0
	var base := config.damage_factor
	if not is_finite(base) or base < 0.0:
		return 1.0
	var v := pow(base, float(maxi(stacks, 1)))
	return clampf(v, 0.0, 10.0) if is_finite(v) else 1.0


func received_damage_factor() -> float:
	if config == null:
		return 1.0
	var base := config.received_damage_factor
	if not is_finite(base) or base < 0.0:
		return 1.0
	var v := pow(base, float(maxi(stacks, 1)))
	return clampf(v, 0.0, 10.0) if is_finite(v) else 1.0


func shield_total() -> float:
	if config == null:
		return 0.0
	return config.shield_amount * float(stacks)


func get_debug_snapshot() -> Dictionary:
	return {
		"effect": String(effect_id()),
		"stacks": stacks,
		"remaining": remaining,
		"duration_multiplier": duration_multiplier,
		"dot_multiplier": dot_multiplier,
	}
