class_name StatusManager
extends Node

## Component owning all status effects on one entity (player or enemy).
## Siblings: HealthComponent (DoT/HoT sink), CharacterController/EnemyBase
## (speed factors are QUERIED via getters — this node never pokes movement
## directly). Effects tick in _physics_process; expiry emits signals locally
## and on the EventBus. Tolerant when configs or health are missing.

signal effect_applied(effect_id: StringName, stacks: int)
signal effect_expired(effect_id: StringName)
signal effect_cleansed(effect_id: StringName)

var _effects: Dictionary = {}  # StringName -> StatusEffect
var _health: Node = null
var _owner_body: Node = null
var _shield_pool: float = 0.0


func _ready() -> void:
	_owner_body = get_parent()
	_health = get_parent().get_node_or_null("HealthComponent") if get_parent() != null else null


func bind_health(health_node: Node) -> void:
	_health = health_node


## Apply one effect by config. Returns the resulting stack count (0 = rejected).
func apply_effect(config: StatusEffectConfig, stacks: int = 1, source: Node = null) -> int:
	if config == null:
		return 0
	var id := config.effect_id
	if _effects.has(id):
		(_effects[id] as StatusEffect).reapply(stacks, source)
	else:
		_effects[id] = StatusEffect.new(config, stacks, source)
		_shield_pool += config.shield_amount * float(stacks)
	var total := (_effects[id] as StatusEffect).stacks
	effect_applied.emit(id, total)
	if EventBus != null:
		EventBus.status_applied.emit(_owner_body, id, total)
	return total


## Apply several effect ids at once (unknown ids are skipped with a warning).
func apply_effects(effect_ids: Array, source: Node = null) -> Dictionary:
	var applied: Dictionary = {}
	if ContentRegistry == null:
		return applied
	for raw in effect_ids:
		var id := StringName(String(raw))
		var cfg: StatusEffectConfig = ContentRegistry.get_status_effect(id)
		if cfg == null:
			if EventBus != null:
				EventBus.report_warning("Unknown status effect %s" % String(id))
			continue
		applied[id] = apply_effect(cfg, 1, source)
	return applied


func has_effect(effect_id: StringName) -> bool:
	return _effects.has(effect_id)


func stack_count(effect_id: StringName) -> int:
	if not _effects.has(effect_id):
		return 0
	return (_effects[effect_id] as StatusEffect).stacks


func remaining_time(effect_id: StringName) -> float:
	if not _effects.has(effect_id):
		return 0.0
	return (_effects[effect_id] as StatusEffect).remaining


func active_effect_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _effects:
		out.append(id)
	return out


## Remove one effect early (cleanse). Returns true when something was removed.
func cleanse(effect_id: StringName) -> bool:
	if not _effects.has(effect_id):
		return false
	_effects.erase(effect_id)
	effect_cleansed.emit(effect_id)
	return true


## Remove all harmful (or all) effects. Returns the number cleansed.
func cleanse_all(only_harmful: bool = true) -> int:
	var removed := 0
	for id in _effects.keys():
		var fx := _effects[id] as StatusEffect
		if only_harmful and fx.config != null and not fx.config.is_harmful:
			continue
		_effects.erase(id)
		effect_cleansed.emit(id)
		removed += 1
	return removed


func clear_all() -> void:
	_effects.clear()
	_shield_pool = 0.0


func _physics_process(delta: float) -> void:
	if _effects.is_empty():
		return
	var expired: Array = []
	for id in _effects:
		var fx := _effects[id] as StatusEffect
		var ticks := fx.tick(delta)
		if ticks > 0:
			_apply_ticks(fx, ticks)
		if fx.is_expired():
			expired.append(id)
	for id in expired:
		_effects.erase(id)
		effect_expired.emit(id)
		if EventBus != null:
			EventBus.status_expired.emit(_owner_body, id)


func _apply_ticks(fx: StatusEffect, ticks: int) -> void:
	if _health == null or not is_instance_valid(_health):
		return
	var dot := fx.dot_per_tick() * float(ticks)
	if dot > 0.0 and _health.has_method("take_damage"):
		# Shields absorb DoT first.
		var absorbed := minf(dot, _shield_pool)
		_shield_pool -= absorbed
		dot -= absorbed
		if dot > 0.0:
			var payload := DamagePayload.new()
			payload.amount = dot
			payload.source = fx.source
			payload.source_id = fx.source_id
			payload.damage_type = fx.config.dot_type if fx.config != null else &"physical"
			payload.hit_position = (_owner_body as Node3D).global_position if _owner_body is Node3D else Vector3.ZERO
			if payload.is_valid():
				_health.call("take_damage", payload)
	var hot := fx.hot_per_tick() * float(ticks)
	if hot > 0.0 and _health.has_method("heal"):
		_health.call("heal", hot)


# ---------------- Aggregated modifier queries ----------------
# Movers / damage pipelines multiply their base values by these.

func move_speed_factor() -> float:
	var f := 1.0
	for id in _effects:
		f *= (_effects[id] as StatusEffect).move_speed_factor()
	return maxf(f, 0.0)


func outgoing_damage_factor() -> float:
	var f := 1.0
	for id in _effects:
		f *= (_effects[id] as StatusEffect).damage_factor()
	return maxf(f, 0.0)


func incoming_damage_factor() -> float:
	var f := 1.0
	for id in _effects:
		f *= (_effects[id] as StatusEffect).received_damage_factor()
	return maxf(f, 0.0)


func is_stunned() -> bool:
	for id in _effects:
		var fx := _effects[id] as StatusEffect
		if fx.config != null and fx.config.stuns:
			return true
	return false


func is_rooted() -> bool:
	for id in _effects:
		var fx := _effects[id] as StatusEffect
		if fx.config != null and fx.config.roots:
			return true
	return false


func shield_remaining() -> float:
	return maxf(_shield_pool, 0.0)


## Spend shield against a direct hit. Returns the leftover damage.
func absorb_direct(amount: float) -> float:
	var absorbed := minf(maxf(amount, 0.0), _shield_pool)
	_shield_pool -= absorbed
	return maxf(amount, 0.0) - absorbed


func get_debug_snapshot() -> Dictionary:
	var list: Array = []
	for id in _effects:
		list.append((_effects[id] as StatusEffect).get_debug_snapshot())
	return {"effects": list, "shield": _shield_pool}
