class_name StatusEffect
extends RefCounted

## Runtime instance of one status effect on one entity. Tracks stacks, remaining
## duration and tick accrual; the owning StatusManager advances it via tick()
## and reads the aggregated modifiers. Headless-testable (no tree access).

var config: StatusEffectConfig = null
var stacks: int = 1
var remaining: float = 0.0
var source: Node = null
var source_id: StringName = &"unknown"

var _tick_accrual: float = 0.0


func _init(cfg: StatusEffectConfig = null, applied_stacks: int = 1, from: Node = null) -> void:
	config = cfg
	source = from
	if from != null and from.has_method("get_archetype_id"):
		source_id = from.call("get_archetype_id")
	elif from != null:
		source_id = StringName(from.name)
	stacks = maxi(applied_stacks, 1)
	if cfg != null:
		stacks = mini(stacks, cfg.max_stacks)
		remaining = cfg.duration


func effect_id() -> StringName:
	return config.effect_id if config != null else &""


func is_permanent() -> bool:
	return config == null or config.is_permanent()


func is_expired() -> bool:
	return not is_permanent() and remaining <= 0.0


## Merge a re-application according to the config's stack mode.
func reapply(extra_stacks: int = 1, from: Node = null) -> void:
	if config == null:
		return
	if from != null:
		source = from
	match config.stack_mode:
		StatusEffectConfig.STACK_ADD:
			stacks = mini(stacks + maxi(extra_stacks, 1), config.max_stacks)
			remaining = config.duration
		StatusEffectConfig.STACK_RESET:
			stacks = mini(maxi(extra_stacks, 1), config.max_stacks)
			remaining = config.duration
		_:  # STACK_REFRESH (default)
			remaining = config.duration


## Advance time. Returns the number of full ticks that elapsed this step so the
## manager can apply that many DoT/HoT quanta. Duration only decreases for
## non-permanent effects.
func tick(delta: float) -> int:
	if config == null:
		return 0
	if not is_permanent():
		remaining -= delta
	_tick_accrual += delta
	var ticks := 0
	while _tick_accrual >= config.tick_interval:
		_tick_accrual -= config.tick_interval
		ticks += 1
	return ticks


func dot_per_tick() -> float:
	if config == null:
		return 0.0
	return config.dot_per_second * config.tick_interval * float(stacks)


func hot_per_tick() -> float:
	if config == null:
		return 0.0
	return config.hot_per_second * config.tick_interval * float(stacks)


func move_speed_factor() -> float:
	if config == null:
		return 1.0
	return pow(config.move_speed_factor, float(stacks))


func damage_factor() -> float:
	if config == null:
		return 1.0
	return pow(config.damage_factor, float(stacks))


func received_damage_factor() -> float:
	if config == null:
		return 1.0
	return pow(config.received_damage_factor, float(stacks))


func shield_total() -> float:
	if config == null:
		return 0.0
	return config.shield_amount * float(stacks)


func get_debug_snapshot() -> Dictionary:
	return {
		"effect": String(effect_id()),
		"stacks": stacks,
		"remaining": remaining,
	}
