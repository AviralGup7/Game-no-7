extends RefCounted

## Headless unit tests for status-effect configs/instances and skill configs.
## (StatusManager/SkillController are tree-bound; their pure math lives in
## StatusEffect and is covered here.)

static func _burn() -> StatusEffectConfig:
	var c := StatusEffectConfig.new()
	c.effect_id = &"burn"
	c.duration = 4.0
	c.max_stacks = 3
	c.stack_mode = StatusEffectConfig.STACK_ADD
	c.dot_per_second = 4.0
	c.dot_type = &"fire"
	c.tick_interval = 0.5
	return c


static func suite() -> Array:
	var results: Array = []

	# --- StatusEffectConfig validation ---
	var burn := _burn()
	results.append({"name": "StatusEffectConfig valid passes", "passed": burn.validate().is_empty(), "why": ""})
	var bad := StatusEffectConfig.new()
	bad.stack_mode = &"nope"
	bad.tick_interval = 0.0
	bad.move_speed_factor = -1.0
	results.append({"name": "StatusEffectConfig flags bad mode/tick/speed", "passed": bad.validate().size() >= 3, "why": ""})
	var perm := StatusEffectConfig.new()
	perm.effect_id = &"aura"
	perm.duration = 0.0
	results.append({"name": "StatusEffectConfig zero duration = permanent", "passed": perm.is_permanent(), "why": ""})

	# --- StatusEffect: stacking + expiry ---
	var fx := StatusEffect.new(burn, 1)
	fx.reapply(1)
	fx.reapply(1)
	fx.reapply(1)  # over max: clamped
	results.append({
		"name": "StatusEffect ADD stacks clamp at max",
		"passed": fx.stacks == 3 and is_equal_approx(fx.remaining, 4.0),
		"why": "stacks=%d" % fx.stacks,
	})
	var refresh := StatusEffectConfig.new()
	refresh.effect_id = &"slow"
	refresh.duration = 3.0
	refresh.max_stacks = 1
	var fx2 := StatusEffect.new(refresh, 1)
	fx2.tick(2.0)
	fx2.reapply(1)
	results.append({
		"name": "StatusEffect REFRESH renews duration, keeps 1 stack",
		"passed": fx2.stacks == 1 and fx2.remaining > 2.9 and not fx2.is_expired(),
		"why": "",
	})
	fx2.tick(3.5)
	results.append({"name": "StatusEffect expires past duration", "passed": fx2.is_expired(), "why": ""})

	# --- StatusEffect: tick quanta + per-tick damage ---
	var fx3 := StatusEffect.new(burn, 2)
	var ticks := fx3.tick(1.1)  # 2.2 intervals => 2 ticks
	results.append({
		"name": "StatusEffect tick() returns whole quanta",
		"passed": ticks == 2 and is_equal_approx(fx3.dot_per_tick(), 4.0 * 0.5 * 2.0),
		"why": "ticks=%d" % ticks,
	})

	# --- StatusEffect: multiplicative factors ---
	var slow := StatusEffectConfig.new()
	slow.effect_id = &"slow"
	slow.move_speed_factor = 0.5
	slow.max_stacks = 2
	var fx4 := StatusEffect.new(slow, 2)
	results.append({
		"name": "StatusEffect factors compound per stack",
		"passed": is_equal_approx(fx4.move_speed_factor(), 0.25) and is_equal_approx(fx4.damage_factor(), 1.0),
		"why": "",
	})

	# --- SkillConfig validation ---
	var slam := SkillConfig.new()
	slam.skill_id = &"seismic_slam"
	slam.behavior = SkillConfig.BEHAVIOR_SLAM
	slam.cooldown = 12.0
	slam.damage_multiplier = 2.5
	slam.radius = 4.5
	results.append({"name": "SkillConfig valid passes", "passed": slam.validate().is_empty(), "why": ""})
	var bad_skill := SkillConfig.new()
	bad_skill.behavior = &"nope"
	bad_skill.cooldown = -1.0
	bad_skill.hit_count = 0
	results.append({"name": "SkillConfig flags bad behavior/cooldown/hits", "passed": bad_skill.validate().size() >= 3, "why": ""})
	results.append({
		"name": "SkillConfig behavior classes",
		"passed": slam.is_offensive() and not slam.is_self_buff(),
		"why": "",
	})
	var cry := SkillConfig.new()
	cry.behavior = SkillConfig.BEHAVIOR_WARCRY
	results.append({"name": "SkillConfig warcry is self-buff", "passed": cry.is_self_buff(), "why": ""})

	# --- PickupConfig validation + scaling ---
	var orb := PickupConfig.new()
	orb.pickup_id = &"health_orb"
	orb.effect = PickupConfig.EFFECT_HEAL
	orb.amount = 25.0
	results.append({
		"name": "PickupConfig valid passes, scales with level",
		"passed": orb.validate().is_empty() and is_equal_approx(orb.scaled_amount(1), 25.0)
			and orb.scaled_amount(3) > 25.0,
		"why": "",
	})
	var bad_pick := PickupConfig.new()
	bad_pick.effect = &"nope"
	bad_pick.collect_radius = 0.0
	results.append({"name": "PickupConfig flags bad effect/radius", "passed": bad_pick.validate().size() >= 2, "why": ""})

	return results
