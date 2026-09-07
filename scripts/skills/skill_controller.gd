class_name SkillController
extends Node

## Player-side active-skill loadout (3 slots bound to skill_1..3 actions).
## Owns cooldown timers, stamina costs, multi-hit scheduling (whirl), dash
## movement (dash_strike) and all damage/effect application via the shared
## AreaDamage + StatusManager seams. Skills unlock by player level/wave; the
## SkillBar UI reads state through the getters below. Headless-safe: every
## engine/autoload touch is guarded.

signal skill_cast_local(skill_id: StringName, slot: int)
signal skill_cooldown_started(skill_id: StringName, duration: float)
signal skill_became_ready(skill_id: StringName)
signal skill_unlock_changed(skill_id: StringName, unlocked: bool)

const SKILL_SLOTS := 3
const ENEMY_GROUP := "enemies"

var _slots: Array = []          # SkillConfig or null
var _cooldowns: Array[float] = []
var _unlocked: Dictionary = {}  # StringName -> bool
var _pending_hits: Array = []   # [{config, hits_left, timer, origin, caster}]
var _dashing: Dictionary = {}   # active dash state or {}
var _enabled := true
var _cooldown_multiplier := 1.0
var _owner_body: Node3D = null
var _rng := RngService.new()


func _ready() -> void:
	_slots.resize(SKILL_SLOTS)
	_slots.fill(null)
	_cooldowns.resize(SKILL_SLOTS)
	_cooldowns.fill(0.0)
	_owner_body = get_parent() as Node3D


func configure(run_seed: int) -> void:
	_rng.reseed(run_seed)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func set_cooldown_multiplier(mult: float) -> void:
	_cooldown_multiplier = clampf(mult, 0.05, 4.0)


## Bind a config to a slot (locked until unlock_skill unless `unlocked`).
func assign_skill(config: SkillConfig, slot: int, unlocked: bool = false) -> bool:
	if config == null:
		return false
	slot = clampi(slot, 0, SKILL_SLOTS - 1)
	_slots[slot] = config
	_cooldowns[slot] = 0.0
	_unlocked[config.skill_id] = unlocked
	skill_unlock_changed.emit(config.skill_id, unlocked)
	return true


func assign_skill_by_id(skill_id: StringName, slot: int, unlocked: bool = false) -> bool:
	if ContentRegistry == null:
		return false
	var cfg: SkillConfig = ContentRegistry.get_skill(skill_id)
	if cfg == null:
		return false
	return assign_skill(cfg, slot, unlocked)


func unlock_skill(skill_id: StringName) -> bool:
	if _unlocked.get(skill_id, false):
		return false
	_unlocked[skill_id] = true
	skill_unlock_changed.emit(skill_id, true)
	if EventBus != null:
		EventBus.skill_unlocked.emit(skill_id)
	return true


func is_unlocked(skill_id: StringName) -> bool:
	return bool(_unlocked.get(skill_id, false))


func slot_skill(slot: int) -> SkillConfig:
	if slot < 0 or slot >= _slots.size():
		return null
	return _slots[slot] as SkillConfig


func slot_cooldown(slot: int) -> float:
	if slot < 0 or slot >= _cooldowns.size():
		return 0.0
	return maxf(_cooldowns[slot], 0.0)


func slot_cooldown_fraction(slot: int) -> float:
	var cfg := slot_skill(slot)
	if cfg == null or cfg.cooldown <= 0.0:
		return 0.0
	return clampf(slot_cooldown(slot) / (cfg.cooldown * _cooldown_multiplier), 0.0, 1.0)


func is_slot_ready(slot: int) -> bool:
	var cfg := slot_skill(slot)
	if cfg == null or not is_unlocked(cfg.skill_id):
		return false
	return slot_cooldown(slot) <= 0.0


func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_pending_hits(delta)
	_tick_dash(delta)
	if not _enabled:
		return
	_poll_inputs()


func _poll_inputs() -> void:
	for slot in range(SKILL_SLOTS):
		var cfg := slot_skill(slot)
		if cfg == null:
			continue
		var action := String(cfg.input_action)
		if action.is_empty():
			continue
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			try_cast_slot(slot)


func _tick_cooldowns(delta: float) -> void:
	for slot in range(_cooldowns.size()):
		if _cooldowns[slot] > 0.0:
			_cooldowns[slot] = maxf(_cooldowns[slot] - delta, 0.0)
			if _cooldowns[slot] <= 0.0:
				var cfg := slot_skill(slot)
				if cfg != null:
					skill_became_ready.emit(cfg.skill_id)
					if EventBus != null:
						EventBus.skill_ready.emit(cfg.skill_id)


## Attempt to cast the skill in `slot`. Returns false with no side effects when
## locked, on cooldown, unaffordable, stunned, or misconfigured.
func try_cast_slot(slot: int) -> bool:
	if not _enabled:
		return false
	var cfg := slot_skill(slot)
	if cfg == null or not is_unlocked(cfg.skill_id):
		return false
	if slot_cooldown(slot) > 0.0:
		return false
	if _is_caster_stunned():
		return false
	if not _pay_stamina(cfg):
		return false
	_cooldowns[slot] = cfg.cooldown * _cooldown_multiplier
	skill_cooldown_started.emit(cfg.skill_id, _cooldowns[slot])
	_execute(cfg)
	skill_cast_local.emit(cfg.skill_id, slot)
	if EventBus != null:
		EventBus.skill_cast.emit(cfg.skill_id, _owner_body)
	return true


func _is_caster_stunned() -> bool:
	if _owner_body == null:
		return false
	var sm := _owner_body.get_node_or_null("StatusManager")
	return sm != null and sm.has_method("is_stunned") and bool(sm.call("is_stunned"))


func _pay_stamina(cfg: SkillConfig) -> bool:
	if cfg.stamina_cost <= 0.0:
		return true
	if _owner_body == null or not _owner_body.has_method("try_spend_stamina"):
		return true  # no stamina system wired: skills are free
	return bool(_owner_body.call("try_spend_stamina", cfg.stamina_cost))


func _execute(cfg: SkillConfig) -> void:
	match cfg.behavior:
		SkillConfig.BEHAVIOR_SLAM:
			_do_slam(cfg)
		SkillConfig.BEHAVIOR_WHIRL:
			_do_whirl(cfg)
		SkillConfig.BEHAVIOR_DASH_STRIKE:
			_do_dash_strike(cfg)
		SkillConfig.BEHAVIOR_SHOCKWAVE:
			_do_shockwave(cfg)
		SkillConfig.BEHAVIOR_WARCRY:
			_do_self_effects(cfg)
		SkillConfig.BEHAVIOR_HEAL_SURGE:
			_do_heal_surge(cfg)
		SkillConfig.BEHAVIOR_FROST_NOVA:
			_do_frost_nova(cfg)
		_:
			if EventBus != null:
				EventBus.report_warning("Unknown skill behavior %s" % String(cfg.behavior))


func _caster_damage() -> float:
	# Skills scale off the active weapon so weapon progression feeds them.
	if _owner_body != null:
		var wm := _owner_body.get_node_or_null("WeaponManager")
		if wm != null and wm.has_method("active_instance"):
			var inst: WeaponInstance = wm.call("active_instance")
			if inst != null:
				return inst.effective_damage()
	return 10.0


func _skill_damage(cfg: SkillConfig) -> float:
	return maxf(_caster_damage() * cfg.damage_multiplier + cfg.flat_damage, 0.0)


func _enemies() -> Array:
	if not is_inside_tree():
		return []
	return get_tree().get_nodes_in_group(ENEMY_GROUP)


func _face() -> Vector3:
	if _owner_body == null:
		return Vector3.FORWARD
	var f := -(_owner_body.global_transform.basis.z)
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func _apply_victim_effects(cfg: SkillConfig, victims: Array) -> void:
	if cfg.victim_effects.is_empty() or victims.is_empty():
		return
	if not _rng.chance(RngService.STREAM_DROPS, cfg.victim_effect_chance):
		return
	for v in victims:
		if v is Node:
			var sm := (v as Node).get_node_or_null("StatusManager")
			if sm != null and sm.has_method("apply_effects"):
				sm.call("apply_effects", cfg.victim_effects, _owner_body)


func _do_slam(cfg: SkillConfig) -> void:
	var origin := _owner_body.global_position if _owner_body != null else Vector3.ZERO
	var hits := AreaDamage.apply_radial(_enemies(), origin, cfg.radius, _skill_damage(cfg), _owner_body, cfg.skill_id, cfg.knockback, true)
	_apply_victim_effects(cfg, hits)


func _do_frost_nova(cfg: SkillConfig) -> void:
	var origin := _owner_body.global_position if _owner_body != null else Vector3.ZERO
	var hits := AreaDamage.apply_radial(_enemies(), origin, cfg.radius, _skill_damage(cfg), _owner_body, cfg.skill_id, cfg.knockback, true)
	if ContentRegistry != null:
		for v in hits:
			if v is Node:
				var sm := (v as Node).get_node_or_null("StatusManager")
				if sm != null and sm.has_method("apply_effects"):
					var ids: Array = cfg.victim_effects.duplicate()
					if &"slow" not in ids:
						ids.append(&"slow")
					sm.call("apply_effects", ids, _owner_body)
	else:
		_apply_victim_effects(cfg, hits)


func _do_whirl(cfg: SkillConfig) -> void:
	# First hit lands instantly; the rest are scheduled so damage + FX read as
	# a spin instead of one burst.
	var origin := _owner_body.global_position if _owner_body != null else Vector3.ZERO
	var per_hit := _skill_damage(cfg) / float(maxi(cfg.hit_count, 1))
	var hits := AreaDamage.apply_radial(_enemies(), origin, cfg.radius, per_hit, _owner_body, cfg.skill_id, cfg.knockback * 0.4, true)
	_apply_victim_effects(cfg, hits)
	if cfg.hit_count > 1:
		_pending_hits.append({
			"config": cfg,
			"hits_left": cfg.hit_count - 1,
			"timer": cfg.hit_interval,
			"per_hit": per_hit,
		})


func _do_dash_strike(cfg: SkillConfig) -> void:
	var origin := _owner_body.global_position if _owner_body != null else Vector3.ZERO
	_dashing = {
		"config": cfg,
		"from": origin,
		"dir": _face(),
		"timer": maxf(cfg.dash_duration, 0.05),
		"total": maxf(cfg.dash_duration, 0.05),
		"struck": [],
	}


func _do_shockwave(cfg: SkillConfig) -> void:
	var origin := _owner_body.global_position if _owner_body != null else Vector3.ZERO
	var muzzle := RangedResolver.muzzle_position(origin, _face(), 0.4, 0.4)
	var dirs: Array[Vector3] = [_face()]
	var pool := _projectile_pool()
	if pool != null:
		pool.fire_volley({
			"team": Projectile.TEAM_PLAYER,
			"origin": muzzle,
			"speed": 16.0,
			"damage": _skill_damage(cfg),
			"knockback": cfg.knockback,
			"pierce": 99,
			"max_distance": cfg.length,
			"lifetime": cfg.length / 16.0,
			"source": _owner_body,
			"source_id": cfg.skill_id,
			"status_effects": cfg.victim_effects,
		}, dirs)
	else:
		# Fallback: instant line damage when no pool is wired (tests, minimal scenes).
		var hits := AreaDamage.apply_line(_enemies(), origin, _face(), cfg.length, cfg.radius, _skill_damage(cfg), _owner_body, cfg.skill_id, cfg.knockback)
		_apply_victim_effects(cfg, hits)


func _do_self_effects(cfg: SkillConfig) -> void:
	if _owner_body == null:
		return
	var sm := _owner_body.get_node_or_null("StatusManager")
	if sm != null and sm.has_method("apply_effects") and not cfg.caster_effects.is_empty():
		sm.call("apply_effects", cfg.caster_effects, _owner_body)


func _do_heal_surge(cfg: SkillConfig) -> void:
	if _owner_body == null:
		return
	var hp := _owner_body.get_node_or_null("HealthComponent")
	if hp != null and hp.has_method("heal") and cfg.heal_amount > 0.0:
		hp.call("heal", cfg.heal_amount)
	_do_self_effects(cfg)


func _projectile_pool() -> ProjectilePool:
	if not is_inside_tree():
		return null
	var pools := get_tree().get_nodes_in_group("projectile_pool")
	return pools[0] as ProjectilePool if not pools.is_empty() else null


func _tick_pending_hits(delta: float) -> void:
	if _pending_hits.is_empty():
		return
	var origin := _owner_body.global_position if _owner_body != null else Vector3.ZERO
	for entry in _pending_hits.duplicate():
		entry["timer"] = float(entry["timer"]) - delta
		if float(entry["timer"]) > 0.0:
			continue
		var cfg: SkillConfig = entry["config"]
		var hits := AreaDamage.apply_radial(_enemies(), origin, cfg.radius, float(entry["per_hit"]), _owner_body, cfg.skill_id, cfg.knockback * 0.4, true)
		_apply_victim_effects(cfg, hits)
		entry["hits_left"] = int(entry["hits_left"]) - 1
		if int(entry["hits_left"]) <= 0:
			_pending_hits.erase(entry)
		else:
			entry["timer"] = cfg.hit_interval


func _tick_dash(delta: float) -> void:
	if _dashing.is_empty() or _owner_body == null:
		return
	var cfg: SkillConfig = _dashing["config"]
	var dir: Vector3 = _dashing["dir"]
	var total: float = _dashing["total"]
	var timer: float = float(_dashing["timer"]) - delta
	_dashing["timer"] = timer
	var step_speed := cfg.length / maxf(total, 0.01)
	if _owner_body is CharacterBody3D:
		(_owner_body as CharacterBody3D).velocity = Vector3(dir.x * step_speed, (_owner_body as CharacterBody3D).velocity.y, dir.z * step_speed)
		(_owner_body as CharacterBody3D).move_and_slide()
	# Strike enemies passed through (each once per dash).
	var struck: Array = _dashing["struck"]
	var fresh := AreaDamage.apply_line(_enemies(), (_dashing["from"] as Vector3).lerp(_owner_body.global_position, 0.5), dir, cfg.length, cfg.radius, _skill_damage(cfg), _owner_body, cfg.skill_id, cfg.knockback, struck)
	for v in fresh:
		struck.append(v)
	_apply_victim_effects(cfg, fresh)
	if timer <= 0.0:
		_dashing.clear()


func reset_for_new_run() -> void:
	_cooldowns.fill(0.0)
	_pending_hits.clear()
	_dashing.clear()


func get_debug_snapshot() -> Dictionary:
	var slots: Array = []
	for i in range(SKILL_SLOTS):
		var cfg := slot_skill(i)
		slots.append({
			"skill": String(cfg.skill_id) if cfg != null else "empty",
			"cooldown": slot_cooldown(i),
			"ready": is_slot_ready(i),
		})
	return {"slots": slots, "pending_hits": _pending_hits.size(), "dashing": not _dashing.is_empty()}
