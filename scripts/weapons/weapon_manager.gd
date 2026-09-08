class_name WeaponManager
extends Node

## Player-side weapon loadout: owns up to LOADOUT_SLOTS WeaponInstances, the
## active slot, equip/switch rules, per-frame cooldown ticking and the melee +
## volley dispatch that connects WeaponInstance timing to MeleeResolver /
## RangedResolver / ProjectilePool. UI and skills talk to THIS node; the
## AttackController remains the legacy single-weapon path and stays untouched.
##
## Wiring (optional, all tolerant): parent Player, sibling ProgressionComponent
## (derived stats), ProjectilePool (found via group "projectile_pool").

signal weapon_equipped_local(weapon_id: StringName, slot: int)
signal weapon_switched_local(old_id: StringName, new_id: StringName)
signal attack_resolved(weapon_id: StringName, hit_count: int, was_crit: bool)
signal reload_started(weapon_id: StringName)
signal reload_finished(weapon_id: StringName)

const LOADOUT_SLOTS := 2
const ENEMY_GROUP := "enemies"

var _slots: Array = [null, null] # WeaponInstance or null per slot
var _active_slot := 0
var _run_seed := 0
var _current_wave := 1
var _attacks_enabled := true
var _projectile_pool: ProjectilePool = null
var _owner_body: Node3D = null


func _ready() -> void:
	_slots.resize(LOADOUT_SLOTS)
	_slots.fill(null)
	_owner_body = get_parent() as Node3D
	_locate_projectile_pool()
	_bind_status_refresh()


func _bind_status_refresh() -> void:
	if _owner_body == null:
		return
	var status := _owner_body.get_node_or_null("StatusManager") as StatusManager
	if status == null:
		return
	if not status.effect_applied.is_connected(_on_status_applied):
		status.effect_applied.connect(_on_status_applied)
	if not status.effect_expired.is_connected(_on_status_removed):
		status.effect_expired.connect(_on_status_removed)
	if not status.effect_cleansed.is_connected(_on_status_removed):
		status.effect_cleansed.connect(_on_status_removed)


func _on_status_applied(_effect_id: StringName, _stacks: int) -> void:
	refresh_derived_stats()


func _on_status_removed(_effect_id: StringName) -> void:
	refresh_derived_stats()


func _locate_projectile_pool() -> void:
	if _projectile_pool != null and is_instance_valid(_projectile_pool):
		return
	var pools := get_tree().get_nodes_in_group("projectile_pool") if is_inside_tree() else []
	if not pools.is_empty():
		_projectile_pool = pools[0] as ProjectilePool


func configure(run_seed: int) -> void:
	_run_seed = run_seed
	for inst in _slots:
		if inst is WeaponInstance:
			(inst as WeaponInstance).reseed(run_seed)


func set_attacks_enabled(enabled: bool) -> void:
	_attacks_enabled = enabled
	if not enabled:
		cancel_in_progress()


func cancel_in_progress() -> void:
	for inst in _slots:
		if inst is WeaponInstance:
			(inst as WeaponInstance).cancel_attack()


## Equip a weapon config into a slot (replaces whatever was there). Returns the
## replaced weapon id, or &"" when the slot was empty.
func equip(config: WeaponConfig, slot: int = 0) -> StringName:
	if config == null or not config.validate().is_empty() or config.disabled:
		return &""
	slot = clampi(slot, 0, LOADOUT_SLOTS - 1)
	var replaced := &""
	if _slots[slot] is WeaponInstance:
		replaced = (_slots[slot] as WeaponInstance).config.weapon_id
	var inst := WeaponInstance.new(config, _run_seed)
	_apply_derived_stats(inst)
	# Forward per-instance reload completion so HUD/audio can observe it.
	if not inst.reloaded.is_connected(_on_instance_reloaded):
		inst.reloaded.connect(_on_instance_reloaded.bind(config.weapon_id))
	_slots[slot] = inst
	weapon_equipped_local.emit(config.weapon_id, slot)
	if EventBus != null:
		EventBus.weapon_equipped.emit(config.weapon_id, slot)
	return replaced


## Equip by registry id (looks the config up via ContentRegistry). False when
## unknown/disabled/future-wave or the registry is unavailable. Setup flows may
## explicitly bypass the wave gate for a starter/daily loadout.
func equip_by_id(weapon_id: StringName, slot: int = 0, bypass_wave_gate: bool = false) -> bool:
	if ContentRegistry == null:
		return false
	var cfg: WeaponConfig = ContentRegistry.get_weapon(weapon_id)
	if cfg == null or not cfg.validate().is_empty() or cfg.disabled:
		return false
	if not bypass_wave_gate and _current_wave < cfg.unlock_wave:
		return false
	equip(cfg, slot)
	return true


func set_current_wave(wave_number: int) -> void:
	_current_wave = maxi(wave_number, 1)


func get_current_wave() -> int:
	return _current_wave


func switch_to(slot: int) -> bool:
	slot = clampi(slot, 0, LOADOUT_SLOTS - 1)
	if slot == _active_slot:
		return false
	if not (_slots[slot] is WeaponInstance):
		return false
	var old := active_instance()
	if old != null:
		old.cancel_attack()
	var old_id := active_weapon_id()
	_active_slot = slot
	var new_id := active_weapon_id()
	weapon_switched_local.emit(old_id, new_id)
	if EventBus != null:
		EventBus.weapon_switched.emit(old_id, new_id)
	return true


func cycle_weapon() -> bool:
	return switch_to((_active_slot + 1) % LOADOUT_SLOTS)


func active_instance() -> WeaponInstance:
	if _active_slot < 0 or _active_slot >= _slots.size():
		return null
	return _slots[_active_slot] as WeaponInstance


func active_weapon_id() -> StringName:
	var inst := active_instance()
	if inst == null or inst.config == null:
		return &""
	return inst.config.weapon_id


func slot_instance(slot: int) -> WeaponInstance:
	if slot < 0 or slot >= _slots.size():
		return null
	return _slots[slot] as WeaponInstance


## Stable loadout mirror for RunState/save summaries. Empty slots are omitted.
func get_loadout_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for raw in _slots:
		var inst := raw as WeaponInstance
		if inst != null and inst.config != null:
			ids.append(inst.config.weapon_id)
	return ids


## Refresh wielder-derived modifiers on every equipped weapon (call after any
## upgrade / external stat change).
func refresh_derived_stats() -> void:
	for inst in _slots:
		if inst is WeaponInstance:
			_apply_derived_stats(inst)


func _apply_derived_stats(inst: WeaponInstance) -> void:
	var prog := _progression()
	var status_damage := 1.0
	if _owner_body != null:
		var status := _owner_body.get_node_or_null("StatusManager")
		if status != null and status.has_method("outgoing_damage_factor"):
			status_damage = maxf(float(status.call("outgoing_damage_factor")), 0.0)
	inst.damage_multiplier = _stat(prog, &"attack_damage_multiplier", 1.0) * status_damage
	inst.cooldown_multiplier = _stat(prog, &"attack_cooldown_multiplier", 1.0)
	inst.range_bonus = _stat(prog, &"attack_range_add", 0.0)
	inst.knockback_multiplier = _stat(prog, &"knockback_multiplier", 1.0)
	inst.crit_chance_bonus = _stat(prog, &"crit_chance_add", 0.0)
	inst.crit_multiplier_bonus = _stat(prog, &"crit_multiplier_add", 0.0)
	inst.status_chance_bonus = _stat(prog, &"status_chance_add", 0.0)
	inst.projectile_count_bonus = maxi(int(round(_stat(prog, &"projectile_count_add", 0.0))), 0)
	inst.projectile_pierce_bonus = maxi(int(round(_stat(prog, &"projectile_pierce_add", 0.0))), 0)


func _progression() -> Node:
	if _owner_body == null:
		return null
	return _owner_body.get_node_or_null("ProgressionComponent")


func _stat(prog: Node, key: StringName, fallback: float) -> float:
	if prog != null and prog.has_method("get_stat"):
		return float(prog.call("get_stat", key, fallback))
	return fallback


## Attempt an attack with the active weapon. Returns the combo step started, or
## 0 when no attack could start. Resolution happens in tick() when the windup
## elapses (or immediately for zero-windup weapons once tick(0) runs).
func request_attack() -> int:
	if not _attacks_enabled:
		return 0
	var inst := active_instance()
	if inst == null:
		return 0
	var was_reloading := inst.is_reloading()
	var step := inst.try_start_attack()
	if not was_reloading and inst.is_reloading():
		reload_started.emit(inst.config.weapon_id)
	return step


## Advance the active weapon's timers; resolves the swing/shot when its windup
## elapses. Must be called every physics step while the player is live.
func tick(delta: float) -> void:
	# Holstered cooldowns/reloads continue, but cannot fire delayed swings.
	for slot in range(_slots.size()):
		if slot != _active_slot and _slots[slot] is WeaponInstance:
			(_slots[slot] as WeaponInstance).tick(delta)
	var inst := active_instance()
	if inst == null:
		return
	if inst.tick(delta):
		_resolve_active_attack(inst)


func _resolve_active_attack(inst: WeaponInstance) -> void:
	if _owner_body == null or not is_instance_valid(_owner_body):
		return
	if inst == null or inst.config == null or not is_instance_valid(inst):
		return
	if not is_inside_tree():
		return
	var cfg := inst.config
	var was_crit := inst.roll_crit()
	var origin := _owner_body.global_position
	var facing := -(_owner_body.global_transform.basis.z)
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var total_hits := 0
	if cfg.is_melee():
		total_hits += _resolve_melee(inst, origin, facing, was_crit)
	if cfg.is_ranged():
		_fire_volley(inst, origin, facing, was_crit)
	attack_resolved.emit(cfg.weapon_id, total_hits, was_crit)


func _resolve_melee(inst: WeaponInstance, origin: Vector3, facing: Vector3, was_crit: bool) -> int:
	var candidates := get_tree().get_nodes_in_group(ENEMY_GROUP) if is_inside_tree() else []
	var applied := MeleeResolver.resolve_and_apply(origin, facing, candidates, inst, _owner_body, was_crit)
	_maybe_apply_status(inst, applied)
	return applied.size()


func _maybe_apply_status(inst: WeaponInstance, applied: Array) -> void:
	if applied.is_empty() or not inst.roll_on_hit_effects():
		return
	for entry in applied:
		var target: Variant = entry["target"]
		if target == null or not is_instance_valid(target):
			continue
		var sm := (target as Node).get_node_or_null("StatusManager") if target is Node else null
		if sm != null and sm.has_method("apply_effects"):
			var status_result: Variant = sm.call("apply_effects", inst.config.on_hit_effects, _owner_body)
			var result: Variant = entry.get("result")
			if result is DamageResult and status_result is Dictionary:
				for raw_id in status_result:
					if int((status_result as Dictionary)[raw_id]) > 0:
						(result as DamageResult).status_effects_applied.append(StringName(String(raw_id)))


func _fire_volley(inst: WeaponInstance, origin: Vector3, facing: Vector3, was_crit: bool) -> void:
	_locate_projectile_pool()
	if _projectile_pool == null:
		return
	var cfg := inst.config
	var dirs := RangedResolver.spread_directions(facing, inst.effective_projectile_count(), cfg.projectile_spread_degrees)
	var muzzle := RangedResolver.muzzle_position(origin, facing)
	var damage := inst.effective_damage()
	if was_crit:
		damage *= inst.effective_crit_multiplier()
	var cfg_dict := {
		"team": Projectile.TEAM_PLAYER,
		"origin": muzzle,
		"speed": cfg.projectile_speed,
		"damage": damage,
		"knockback": inst.effective_knockback(),
		"pierce": inst.effective_projectile_pierce(),
		"damage_type": cfg.damage_type,
		"max_distance": cfg.projectile_speed * cfg.projectile_lifetime,
		"lifetime": cfg.projectile_lifetime,
		"source": _owner_body,
		"source_id": cfg.weapon_id,
		"was_critical": was_crit,
		"critical_multiplier": inst.effective_crit_multiplier(),
		"status_effects": cfg.on_hit_effects if inst.roll_on_hit_effects() else [],
	}
	_projectile_pool.fire_volley(cfg_dict, dirs)
	if EventBus != null:
		EventBus.projectile_fired.emit(_owner_body, cfg.weapon_id)


func request_reload() -> bool:
	var inst := active_instance()
	if inst == null:
		return false
	var started := inst.start_reload()
	if started:
		reload_started.emit(inst.config.weapon_id)
	return started


func _on_instance_reloaded(weapon_id: StringName) -> void:
	reload_finished.emit(weapon_id)


func reset_for_new_run() -> void:
	for inst in _slots:
		if inst is WeaponInstance:
			(inst as WeaponInstance).reset()
	_active_slot = 0


func get_debug_snapshot() -> Dictionary:
	var inst := active_instance()
	return {
		"active_slot": _active_slot,
		"active_weapon": String(active_weapon_id()),
		"weapon": inst.get_debug_snapshot() if inst != null else {},
	}

## Hardened: validate weapon switch to prevent null config.
func _validated_weapon_id(id: StringName) -> bool:
	if id == &"":
		return false
	if ContentRegistry == null or not ContentRegistry.has_method("get_weapon"):
		return false
	return ContentRegistry.get_weapon(id) != null

