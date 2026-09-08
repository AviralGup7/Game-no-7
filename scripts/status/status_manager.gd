class_name StatusManager
extends Node

## Component owning all status effects on one entity (player or enemy).
## Siblings: HealthComponent (DoT/HoT sink), CharacterController/EnemyBase
## (speed factors are QUERIED via getters). Effects tick in _physics_process;
## expiry and cleanse remove their shield contribution as well as their effect.
##
## Caster status power is read from the caster's ProgressionComponent and copied
## into each StatusEffect instance. Shared .tres resources are never mutated.

signal effect_applied(effect_id: StringName, stacks: int)
signal effect_expired(effect_id: StringName)
signal effect_cleansed(effect_id: StringName)

var _effects: Dictionary = {}  # StringName -> StatusEffect
var _health: Node = null
var _owner_body: Node = null
var _shield_layers: Dictionary = {}  # effect id -> remaining shield contribution
var _shield_pool: float = 0.0


func _ready() -> void:
	_owner_body = get_parent()
	_health = get_parent().get_node_or_null("HealthComponent") if get_parent() != null else null


func bind_health(health_node: Node) -> void:
	_health = health_node


## Apply one effect by config. Returns the resulting stack count (0 = rejected).
func apply_effect(config: StatusEffectConfig, stacks: int = 1, source: Node = null) -> int:
	if config == null or not config.validate().is_empty():
		return 0
	var id := config.effect_id
	var power := _power_for(source)
	if _effects.has(id):
		var fx := _effects[id] as StatusEffect
		var before_shield := fx.shield_total()
		fx.reapply(stacks, source, float(power["duration"]), float(power["damage"]), float(power["damage"]))
		var after_shield := fx.shield_total()
		if config.stack_mode == StatusEffectConfig.STACK_ADD:
			# ADD only grants the newly acquired capacity; refreshing at max does
			# not create an infinite shield loop.
			_shield_layers[id] = float(_shield_layers.get(id, 0.0)) + maxf(after_shield - before_shield, 0.0)
		else:
			# REFRESH/RESET replenish this effect's own layer to its authored
			# capacity while leaving other effect layers untouched.
			_shield_layers[id] = after_shield
	else:
		var created := StatusEffect.new(config, stacks, source)
		created.set_power_modifiers(float(power["duration"]), float(power["damage"]), float(power["damage"]))
		_effects[id] = created
		_shield_layers[id] = created.shield_total()
	_sync_shield_pool()
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


## Remove one effect early (cleanse), including its unspent shield. Returns true
## when something was removed.
func cleanse(effect_id: StringName) -> bool:
	if not _effects.has(effect_id):
		return false
	_remove_effect(effect_id)
	effect_cleansed.emit(effect_id)
	return true


## Remove all harmful (or all) effects. Returns the number cleansed.
func cleanse_all(only_harmful: bool = true) -> int:
	var removed := 0
	for id in _effects.keys().duplicate():
		var fx := _effects[id] as StatusEffect
		if only_harmful and fx.config != null and not fx.config.is_harmful:
			continue
		_remove_effect(id)
		effect_cleansed.emit(id)
		removed += 1
	return removed


func clear_all() -> void:
	var removed: Array = _effects.keys().duplicate()
	_effects.clear()
	_shield_layers.clear()
	_shield_pool = 0.0
	for id in removed:
		effect_cleansed.emit(id)


func _physics_process(delta: float) -> void:
	if _effects.is_empty():
		return
	if not is_inside_tree():
		return
	if delta <= 0.0 or not is_finite(delta):
		return
	var expired: Array = []
	for id in _effects.keys().duplicate():
		if not _effects.has(id):
			continue
		var fx := _effects[id] as StatusEffect
		if fx == null or not is_instance_valid(fx):
			expired.append(id)
			continue
		var ticks := fx.tick(delta)
		if ticks > 0:
			_apply_ticks(fx, ticks)
		if fx.is_expired():
			expired.append(id)
	for id in expired:
		_remove_effect(id)
		effect_expired.emit(id)
		if EventBus != null:
			EventBus.status_expired.emit(_owner_body, id)


func _apply_ticks(fx: StatusEffect, ticks: int) -> void:
	if _health == null or not is_instance_valid(_health):
		return
	var dot := fx.dot_per_tick() * float(ticks)
	var damage_allowed := not (_health.has_method("is_dead") and bool(_health.call("is_dead")))
	if damage_allowed and _health.has_method("is_invulnerable"):
		damage_allowed = not bool(_health.call("is_invulnerable"))
	if dot > 0.0 and damage_allowed and _health.has_method("take_damage"):
		dot = absorb_direct(dot)
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


func _remove_effect(effect_id: StringName) -> void:
	_effects.erase(effect_id)
	_shield_layers.erase(effect_id)
	_sync_shield_pool()


func _sync_shield_pool() -> void:
	_shield_pool = 0.0
	for value in _shield_layers.values():
		_shield_pool += maxf(float(value), 0.0)


## Read status-build multipliers without mutating config resources. The source's
## progression wins; self-applied effects fall back to the affected entity.
func _power_for(source: Node) -> Dictionary:
	var provider := source
	if provider == null or not is_instance_valid(provider):
		provider = _owner_body
	var prog := provider.get_node_or_null("ProgressionComponent") if provider is Node else null
	var duration := 1.0
	var damage := 1.0
	if prog != null and prog.has_method("get_stat"):
		duration = float(prog.call("get_stat", &"status_duration_multiplier", 1.0))
		damage = float(prog.call("get_stat", &"status_damage_multiplier", 1.0))
	return {"duration": clampf(duration, 0.05, 10.0), "damage": clampf(damage, 0.0, 10.0)}


# ---------------- Aggregated modifier queries ----------------

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


## Spend shield against a direct hit. Returns the leftover damage. Layers are
## consumed in stable effect insertion order so expiring one shield cannot erase
## another effect's unspent capacity.
func absorb_direct(amount: float) -> float:
	var remaining := maxf(amount, 0.0)
	for id in _shield_layers.keys().duplicate():
		if remaining <= 0.0:
			break
		var layer := maxf(float(_shield_layers[id]), 0.0)
		var absorbed := minf(layer, remaining)
		_shield_layers[id] = layer - absorbed
		remaining -= absorbed
	_sync_shield_pool()
	return remaining


func get_debug_snapshot() -> Dictionary:
	var list: Array = []
	for id in _effects:
		list.append((_effects[id] as StatusEffect).get_debug_snapshot())
	return {"effects": list, "shield": _shield_pool}

## Hardened: validate incoming status effects batch.
func _validated_effects(effects: Array) -> Array:
	var out: Array = []
	for e in effects:
		if e == null or not is_instance_valid(e as Object):
			continue
		if e is Dictionary and e.has("id"):
			var dur:float = float(e.get("duration", 0.0))
			if not is_finite(dur) or dur <= 0.0:
				continue
			out.append(e)
		elif e is StatusEffect and is_finite(e.duration):
			out.append(e)
	return out

