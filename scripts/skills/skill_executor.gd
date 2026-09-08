class_name SkillExecutor
extends RefCounted

## Skill behavior execution, extracted from SkillController. Applies a cast config
## through the shared AreaDamage + StatusManager seams and ticks scheduled
## follow-ups (whirl multi-hits, dash movement + strikes). The controller keeps
## slots/cooldowns/unlock/input and passes the live enemy list each call.

var _owner_body: Node3D = null
var _rng: RngService = null
var _pending_hits: Array = []   # [{config, hits_left, timer, per_hit}]
var _dashing: Dictionary = {}   # active dash state or {}
# Wielder progression modifiers, copied as values rather than mutating resources.
var _skill_damage_multiplier := 1.0
var _area_radius_multiplier := 1.0
var _area_damage_multiplier := 1.0
var _status_chance_bonus := 0.0


func bind(owner_body: Node3D, rng: RngService) -> void:
	_owner_body = owner_body
	_rng = rng


func set_combat_modifiers(skill_damage: float = 1.0, area_radius: float = 1.0, area_damage: float = 1.0, status_chance: float = 0.0) -> void:
	_skill_damage_multiplier = clampf(skill_damage, 0.0, 10.0)
	_area_radius_multiplier = clampf(area_radius, 0.05, 10.0)
	_area_damage_multiplier = clampf(area_damage, 0.0, 10.0)
	_status_chance_bonus = clampf(status_chance, -1.0, 1.0)


func reset_scheduled() -> void:
	_pending_hits.clear()
	_dashing.clear()


func pending_hits_count() -> int:
	return _pending_hits.size()


func is_dashing() -> bool:
	return not _dashing.is_empty()


func execute(cfg: SkillConfig, enemies: Array) -> void:
	if cfg == null or cfg.disabled:
		return
	match cfg.behavior:
		SkillConfig.BEHAVIOR_SLAM:
			_do_slam(cfg, enemies)
		SkillConfig.BEHAVIOR_WHIRL:
			_do_whirl(cfg, enemies)
		SkillConfig.BEHAVIOR_DASH_STRIKE:
			_do_dash_strike(cfg)
		SkillConfig.BEHAVIOR_SHOCKWAVE:
			_do_shockwave(cfg, enemies)
		SkillConfig.BEHAVIOR_CHAIN_LIGHTNING:
			_do_chain_lightning(cfg, enemies)
		SkillConfig.BEHAVIOR_WARCRY:
			_do_self_effects(cfg)
		SkillConfig.BEHAVIOR_HEAL_SURGE:
			_do_heal_surge(cfg)
		SkillConfig.BEHAVIOR_FROST_NOVA:
			_do_frost_nova(cfg, enemies)
		_:
			if EventBus != null:
				EventBus.report_warning("Unknown skill behavior %s" % String(cfg.behavior))


## Advance whirl follow-ups + the active dash. Called every physics step even when
## input is disabled so in-flight skills always resolve.
func tick(delta: float, enemies: Array) -> void:
	_tick_pending_hits(delta, enemies)
	_tick_dash(delta, enemies)


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
	return maxf((_caster_damage() * cfg.damage_multiplier + cfg.flat_damage) * _skill_damage_multiplier * _area_damage_multiplier, 0.0)


func _radius(cfg: SkillConfig) -> float:
	return maxf(cfg.radius * _area_radius_multiplier, 0.1)


func _length(cfg: SkillConfig) -> float:
	return maxf(cfg.length * _area_radius_multiplier, 0.1)


func _origin() -> Vector3:
	return _owner_body.global_position if _owner_body != null else Vector3.ZERO


func _face() -> Vector3:
	if _owner_body == null:
		return Vector3.FORWARD
	var f := -(_owner_body.global_transform.basis.z)
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func _apply_victim_effects(cfg: SkillConfig, victims: Array) -> void:
	if cfg.victim_effects.is_empty() or victims.is_empty():
		return
	if not _roll_victim_effects(cfg):
		return
	for v in victims:
		if v is Node:
			var sm := (v as Node).get_node_or_null("StatusManager")
			if sm != null and sm.has_method("apply_effects"):
				sm.call("apply_effects", cfg.victim_effects, _owner_body)


func _roll_victim_effects(cfg: SkillConfig) -> bool:
	var chance := clampf(cfg.victim_effect_chance + _status_chance_bonus, 0.0, 1.0)
	return _rng == null or _rng.chance(RngService.STREAM_DROPS, chance)


func _projectile_victim_effects(cfg: SkillConfig) -> Array[StringName]:
	var out: Array[StringName] = []
	if cfg.victim_effects.is_empty() or not _roll_victim_effects(cfg):
		return out
	for effect_id in cfg.victim_effects:
		out.append(effect_id)
	return out



func _do_slam(cfg: SkillConfig, enemies: Array) -> void:
	var hits := AreaDamage.apply_radial(enemies, _origin(), _radius(cfg), _skill_damage(cfg), _owner_body, cfg.skill_id, cfg.knockback, true, AreaDamage.FALLOFF_LINEAR, [], cfg.damage_type)
	_apply_victim_effects(cfg, hits)


func _do_frost_nova(cfg: SkillConfig, enemies: Array) -> void:
	var hits := AreaDamage.apply_radial(enemies, _origin(), _radius(cfg), _skill_damage(cfg), _owner_body, cfg.skill_id, cfg.knockback, true, AreaDamage.FALLOFF_LINEAR, [], cfg.damage_type)
	# Frost Nova guarantees its defining slow; any extra configured effects still
	# respect the authored proc chance and status-build bonus.
	_apply_victim_effects(cfg, hits)
	if ContentRegistry != null:
		var slow_ids: Array[StringName] = [&"slow"]
		for v in hits:
			if v is Node:
				var sm := (v as Node).get_node_or_null("StatusManager")
				if sm != null and sm.has_method("apply_effects"):
					sm.call("apply_effects", slow_ids, _owner_body)


func _do_whirl(cfg: SkillConfig, enemies: Array) -> void:
	# First hit lands instantly; the rest are scheduled so damage + FX read as
	# a spin instead of one burst.
	var per_hit := _skill_damage(cfg) / float(maxi(cfg.hit_count, 1))
	var hits := AreaDamage.apply_radial(enemies, _origin(), _radius(cfg), per_hit, _owner_body, cfg.skill_id, cfg.knockback * 0.4, true, AreaDamage.FALLOFF_NONE, [], cfg.damage_type)
	_apply_victim_effects(cfg, hits)
	if cfg.hit_count > 1:
		_pending_hits.append({
			"config": cfg,
			"hits_left": cfg.hit_count - 1,
			"timer": cfg.hit_interval,
			"per_hit": per_hit,
		})


func _do_dash_strike(cfg: SkillConfig) -> void:
	_dashing = {
		"config": cfg,
		"from": _origin(),
		"dir": _face(),
		"timer": maxf(cfg.dash_duration, 0.05),
		"total": maxf(cfg.dash_duration, 0.05),
		"struck": [],
	}


func _do_shockwave(cfg: SkillConfig, enemies: Array) -> void:
	var muzzle := RangedResolver.muzzle_position(_origin(), _face(), 0.4, 0.4)
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
			"max_distance": _length(cfg),
			"lifetime": _length(cfg) / 16.0,
			"source": _owner_body,
			"source_id": cfg.skill_id,
			"damage_type": cfg.damage_type,
			"status_effects": _projectile_victim_effects(cfg),
		}, dirs)
	else:
		# Fallback: instant line damage when no pool is wired (tests, minimal scenes).
		var hits := AreaDamage.apply_line(enemies, _origin(), _face(), _length(cfg), _radius(cfg), _skill_damage(cfg), _owner_body, cfg.skill_id, cfg.knockback, [], cfg.damage_type)
		_apply_victim_effects(cfg, hits)


func _do_chain_lightning(cfg: SkillConfig, enemies: Array) -> void:
	var hits := AreaDamage.apply_chain(enemies, _origin(), _radius(cfg), cfg.chain_radius * _area_radius_multiplier, cfg.chain_jumps, _skill_damage(cfg), cfg.chain_decay, _owner_body, cfg.skill_id, cfg.damage_type)
	_apply_victim_effects(cfg, hits)


func _do_self_effects(cfg: SkillConfig) -> void:
	if _owner_body == null:
		return
	var sm := _owner_body.get_node_or_null("StatusManager")
	if sm != null and sm.has_method("apply_effects") and not cfg.caster_effects.is_empty():
		sm.call("apply_effects", cfg.caster_effects, _owner_body)
	var wm := _owner_body.get_node_or_null("WeaponManager")
	if wm != null and wm.has_method("refresh_derived_stats"):
		wm.call("refresh_derived_stats")


func _do_heal_surge(cfg: SkillConfig) -> void:
	if _owner_body == null:
		return
	var hp := _owner_body.get_node_or_null("HealthComponent")
	if hp != null and hp.has_method("heal") and cfg.heal_amount > 0.0:
		hp.call("heal", cfg.heal_amount)
	_do_self_effects(cfg)


func _projectile_pool() -> ProjectilePool:
	if _owner_body == null or not _owner_body.is_inside_tree():
		return null
	var pools := _owner_body.get_tree().get_nodes_in_group("projectile_pool")
	return pools[0] as ProjectilePool if not pools.is_empty() else null


func _tick_pending_hits(delta: float, enemies: Array) -> void:
	if _pending_hits.is_empty():
		return
	var origin := _origin()
	for entry in _pending_hits.duplicate():
		entry["timer"] = float(entry["timer"]) - delta
		if float(entry["timer"]) > 0.0:
			continue
		var cfg: SkillConfig = entry["config"]
		var hits := AreaDamage.apply_radial(enemies, origin, _radius(cfg), float(entry["per_hit"]), _owner_body, cfg.skill_id, cfg.knockback * 0.4, true, AreaDamage.FALLOFF_NONE, [], cfg.damage_type)
		_apply_victim_effects(cfg, hits)
		entry["hits_left"] = int(entry["hits_left"]) - 1
		if int(entry["hits_left"]) <= 0:
			_pending_hits.erase(entry)
		else:
			entry["timer"] = cfg.hit_interval


func _tick_dash(delta: float, enemies: Array) -> void:
	if _dashing.is_empty() or _owner_body == null:
		return
	var cfg: SkillConfig = _dashing["config"]
	var dir: Vector3 = _dashing["dir"]
	var total: float = _dashing["total"]
	var timer: float = float(_dashing["timer"]) - delta
	_dashing["timer"] = timer
	var step_speed := _length(cfg) / maxf(total, 0.01)
	if _owner_body is CharacterBody3D:
		(_owner_body as CharacterBody3D).velocity = Vector3(dir.x * step_speed, (_owner_body as CharacterBody3D).velocity.y, dir.z * step_speed)
		(_owner_body as CharacterBody3D).move_and_slide()
	# Strike enemies passed through (each once per dash).
	var struck: Array = _dashing["struck"]
	var fresh := AreaDamage.apply_line(enemies, (_dashing["from"] as Vector3).lerp(_owner_body.global_position, 0.5), dir, _length(cfg), _radius(cfg), _skill_damage(cfg), _owner_body, cfg.skill_id, cfg.knockback, struck, cfg.damage_type)
	for v in fresh:
		struck.append(v)
	_apply_victim_effects(cfg, fresh)
	if timer <= 0.0:
		_dashing.clear()
