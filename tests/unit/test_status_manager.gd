extends RefCounted

## Live-harness tests for StatusManager: real component in a real tree, a real
## HealthComponent, and the physics tick driven by hand so every timing assertion is
## exact (DELTA is 1/8, so the DoT cadence lands on binary-exact sums — the phase-3 lesson
## about 0.1 accumulating to 3.9999999).
##
## Registered in run_tests.gd's NODE_SUITES: the manager resolves its health sibling and
## its bus through the tree, and a parentless Node3D has no meaningful global_position for
## the DoT payload.
##
## These cover what the rebuild was for, none of which is visible from the pure config
## suite: that the five derived numbers are a *cached fold* (a read must not rescan), that
## invalidation happens on every mutation that can change them (including an expiry that
## crosses zero mid-tick), that an idle component stops being ticked, that re-entering the
## manager from its own signal does not corrupt the tick, and that shield layers live on
## their effect and die with it.


const DELTA := 0.125


class ProbeHealth extends HealthComponent:
	## Records every payload so a DoT assertion can count quanta instead of inferring them
	## from a health delta that other systems could also be moving.
	var payloads: Array = []
	var healed: float = 0.0

	func take_damage(payload: DamagePayload) -> DamageResult:
		payloads.append(payload)
		return super.take_damage(payload)

	func heal(amount: float) -> float:
		var applied: float = super.heal(amount)
		healed += applied
		return applied


class ProbeHost extends Node3D:
	var health: ProbeHealth = null
	var status: StatusManager = null


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _host() -> ProbeHost:
	var host := ProbeHost.new()
	host.name = "StatusProbe"
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(host)
	var health := ProbeHealth.new()
	health.name = "HealthComponent"
	health.max_health = 100000.0
	host.add_child(health)
	host.health = health
	# The manager binds its health sibling in _ready, so it must be added last.
	var status := StatusManager.new()
	status.name = "StatusManager"
	host.add_child(status)
	host.status = status
	return host


static func _free(host: ProbeHost) -> void:
	if host != null and is_instance_valid(host):
		host.free()


static func _burn() -> StatusEffectConfig:
	var c := StatusEffectConfig.new()
	c.effect_id = &"burn"
	c.display_name = "Burn"
	c.duration = 4.0
	c.max_stacks = 3
	c.stack_mode = StatusEffectConfig.STACK_ADD
	c.dot_per_second = 4.0
	c.dot_type = &"fire"
	c.tick_interval = 0.5
	return c


static func _slow() -> StatusEffectConfig:
	var c := StatusEffectConfig.new()
	c.effect_id = &"slow"
	c.duration = 3.0
	c.max_stacks = 1
	c.move_speed_factor = 0.5
	c.tick_interval = 0.5
	return c


static func _haste() -> StatusEffectConfig:
	var c := StatusEffectConfig.new()
	c.effect_id = &"haste"
	c.is_harmful = false
	c.duration = 3.0
	c.max_stacks = 1
	c.move_speed_factor = 1.4
	c.tick_interval = 0.5
	return c


static func _weaken() -> StatusEffectConfig:
	var c := StatusEffectConfig.new()
	c.effect_id = &"weaken"
	c.duration = 3.0
	c.max_stacks = 3
	c.stack_mode = StatusEffectConfig.STACK_ADD
	c.damage_factor = 0.8
	c.tick_interval = 0.5
	return c


static func _guard(amount: float, mode: StringName, stacks: int) -> StatusEffectConfig:
	var c := StatusEffectConfig.new()
	c.effect_id = &"guard" if mode != StatusEffectConfig.STACK_ADD else &"addguard"
	c.is_harmful = false
	c.duration = 10.0
	c.max_stacks = stacks
	c.stack_mode = mode
	c.shield_amount = amount
	c.tick_interval = 0.5
	return c


static func _regen() -> StatusEffectConfig:
	var c := StatusEffectConfig.new()
	c.effect_id = &"regen"
	c.is_harmful = false
	c.duration = 2.0
	c.max_stacks = 2
	c.hot_per_second = 5.0
	c.tick_interval = 0.5
	return c


static func _lock(duration: float, roots: bool = false) -> StatusEffectConfig:
	var c := StatusEffectConfig.new()
	c.effect_id = &"stun"
	c.duration = duration
	c.max_stacks = 1
	c.stack_mode = StatusEffectConfig.STACK_RESET
	c.stuns = not roots
	c.roots = roots
	c.tick_interval = 0.5
	return c


# --------------------------------------------------------------------------- cases


## The fold is the only place that walks the table; a read is a field fetch.
static func _recomputes(mgr: StatusManager) -> int:
	return int(mgr.get_debug_snapshot()["recomputes"])


static func _reads(mgr: StatusManager) -> int:
	return int(mgr.get_debug_snapshot()["aggregate_reads"])


static func _reads_are_cached(results: Array) -> void:
	var host := _host()
	var mgr := host.status
	var folds_before := _recomputes(mgr)
	mgr.apply_effect(_slow(), 1, host)
	_check(results, "applying an effect does not refold eagerly",
		_recomputes(mgr) == folds_before, "recomputes=%d" % _recomputes(mgr))
	mgr.move_speed_factor()
	_check(results, "the first read after an application folds exactly once",
		_recomputes(mgr) == folds_before + 1, "recomputes=%d" % _recomputes(mgr))
	var reads_before := _reads(mgr)
	for i in 30:
		mgr.move_speed_factor()
		mgr.incoming_damage_factor()
		mgr.is_stunned()
	_check(results, "90 further reads add no folds",
		_recomputes(mgr) == folds_before + 1, "recomputes=%d" % _recomputes(mgr))
	_check(results, "and are counted as reads, so the cache is observable",
		_reads(mgr) - reads_before == 90, "reads=%d" % (_reads(mgr) - reads_before))
	var stale := bool(mgr.get_debug_snapshot()["stale"])
	_check(results, "a clean cache reports itself as fresh", not stale, "stale=%s" % str(stale))
	mgr.apply_effect(_haste(), 1, host)
	_check(results, "an application marks the cache stale for the next read",
		bool(mgr.get_debug_snapshot()["stale"]), "")
	_free(host)


## An independent re-implementation of the fold, so the cache cannot be wrong in a way that
## agrees with itself.
static func _fold_matches_brute_force(results: Array) -> void:
	var host := _host()
	var slow := _slow()
	var haste := _haste()
	var weaken := _weaken()
	host.status.apply_effect(slow, 1, host)
	host.status.apply_effect(haste, 1, host)
	host.status.apply_effect(weaken, 1, host)
	host.status.apply_effect(weaken, 1, host)
	# Fields, not calls: `slow`/`haste` are `StatusEffectConfig`s, where `move_speed_factor` is the
	# authored float; the *method* of that name lives on `StatusEffect`/`StatusManager` (it is the
	# stacked, resolved value). Calling the field is a parse error, and `:=` on it inferred nothing.
	var expected_move: float = slow.move_speed_factor * haste.move_speed_factor
	var expected_outgoing := pow(weaken.damage_factor, 2.0)
	_check(results, "the cached move factor equals an independent product over the effects",
		is_equal_approx(host.status.move_speed_factor(), expected_move),
		"got=%s want=%s" % [str(host.status.move_speed_factor()), str(expected_move)])
	_check(results, "stacks compound the outgoing factor the same way",
		is_equal_approx(host.status.outgoing_damage_factor(), expected_outgoing),
		"got=%s want=%s" % [str(host.status.outgoing_damage_factor()), str(expected_outgoing)])
	var cleanse_count := host.status.cleanse_all(true)
	_check(results, "cleansing harmful effects leaves only the friendly fold",
		# `haste` is the config: the authored float is the answer for a single stack, and reading it
		# as a method is what made this file fail to parse.
		cleanse_count == 2 and is_equal_approx(host.status.move_speed_factor(), haste.move_speed_factor),
		"cleansed=%d move=%s" % [cleanse_count, str(host.status.move_speed_factor())])
	_free(host)


## A factor axis nobody touches must not pay a pow() per effect per read.
static func _neutral_factors_skip_pow(results: Array) -> void:
	var effect := StatusEffect.new(_slow(), 1)
	_check(results, "an effect with a neutral factor reads 1.0 on the untouched axes",
		is_equal_approx(effect.damage_factor(), 1.0) and is_equal_approx(effect.received_damage_factor(), 1.0),
		"")
	_check(results, "and the axis it does set is per-stack multiplicative",
		is_equal_approx(StatusEffect.new(_slow_with(0.5), 2).move_speed_factor(), 0.25),
		"")
	var nan_host := _host()
	var broken := _slow_with(1.0)
	broken.move_speed_factor = NAN
	broken.received_damage_factor = INF
	nan_host.status.apply_effect(broken, 1, nan_host)
	_check(results, "a NaN or Inf authored factor cannot reach movement: the fold stays finite",
		is_finite(nan_host.status.move_speed_factor()) and is_finite(nan_host.status.incoming_damage_factor()),
		"move=%s incoming=%s" % [str(nan_host.status.move_speed_factor()),
			str(nan_host.status.incoming_damage_factor())])
	_check(results, "and the neutral axis is what a non-finite factor folds to",
		is_equal_approx(nan_host.status.move_speed_factor(), 1.0),
		str(nan_host.status.move_speed_factor()))
	_free(nan_host)


static func _slow_with(factor: float) -> StatusEffectConfig:
	var c := _slow()
	c.move_speed_factor = factor
	c.max_stacks = 2
	return c


## Duration is the one thing that advances every tick, so it is the one thing that can
## silently invalidate a cached fold. Crossing zero must.
static func _expiry_invalidates(results: Array) -> void:
	var host := _host()
	host.health.current_health = 100000.0
	host.status.apply_effect(_slow(), 1, host)
	_check(results, "a locked enemy is slowed while the lock runs",
		is_equal_approx(host.status.move_speed_factor(), 0.5), str(host.status.move_speed_factor()))
	# slow.duration = 3.0 -> 24 ticks of 0.125
	for i in 23:
		host.status._physics_process(DELTA)
	_check(results, "one tick before expiry the fold is unchanged",
		is_equal_approx(host.status.move_speed_factor(), 0.5),
		"remaining=%s" % str(host.status.remaining_time(&"slow")))
	host.status._physics_process(DELTA)
	_check(results, "the tick that expires the effect also un-slows the entity",
		is_equal_approx(host.status.move_speed_factor(), 1.0) and host.status.effect_count() == 0,
		"move=%s count=%d" % [str(host.status.move_speed_factor()), host.status.effect_count()])
	_check(results, "an emptied component parks its own tick instead of idling in it",
		not host.status.is_physics_processing(), "still processing")
	_check(results, "and the tick scratch is left empty, not growing per frame",
		host.status._tick_keys.size() == 0 and host.status._expiring.size() == 0,
		"keys=%d expiring=%d" % [host.status._tick_keys.size(), host.status._expiring.size()])
	_free(host)


static func _idle_and_wake(results: Array) -> void:
	var host := _host()
	_check(results, "a fresh manager is not ticked at all", not host.status.is_physics_processing(), "")
	host.status.apply_effect(_burn(), 1, host)
	_check(results, "an application wakes it", host.status.is_physics_processing(), "")
	var removed := host.status.cleanse(&"burn")
	_check(results, "the last removal parks it again", removed and not host.status.is_physics_processing(), "")
	# A tick while parked must be a no-op rather than a crash on an empty table.
	host.status._physics_process(DELTA)
	_check(results, "ticking an empty component reports a neutral fold",
		is_equal_approx(host.status.move_speed_factor(), 1.0) and host.status.shield_remaining() == 0.0, "")
	_free(host)


static func _dot_quanta(results: Array) -> void:
	var host := _host()
	var expired_ids: Array = []
	host.status.effect_expired.connect(func(id: StringName) -> void: expired_ids.append(id))
	host.status.apply_effect(_burn(), 1, host)
	# burn: dot 4.0/s * interval 0.5 * 1 stack = 2.0 per quanta; duration 4.0 -> 8 quanta.
	for i in 32:
		host.status._physics_process(DELTA)
	var total := 0.0
	for payload in host.health.payloads:
		total += payload.amount
	_check(results, "32 ticks of 1/8 s deliver exactly the authored DoT",
		host.health.payloads.size() == 8 and is_equal_approx(total, 16.0),
		"quanta=%d total=%s" % [host.health.payloads.size(), str(total)])
	_check(results, "the DoT keeps its authored damage type (fire burns, physical does not)",
		not host.health.payloads.is_empty() and host.health.payloads[0].damage_type == &"fire",
		str(host.health.payloads[0].damage_type) if not host.health.payloads.is_empty() else "no payload")
	_check(results, "the DoT is attributed to the caster's id",
		not host.health.payloads.is_empty() and host.health.payloads[0].source_id == &"StatusProbe",
		str(host.health.payloads[0].source_id) if not host.health.payloads.is_empty() else "no payload")
	_check(results, "expiry emits exactly once, with the effect id",
		expired_ids.size() == 1 and String(expired_ids[0]) == "burn", str(expired_ids))
	_free(host)


## A 5-second frame (a tab returning to the foreground) must not be paid as 40 DoT ticks.
static func _hitch_is_clamped(results: Array) -> void:
	var host := _host()
	host.status.apply_effect(_burn(), 1, host)
	host.status._physics_process(5.0)
	var total := 0.0
	for payload in host.health.payloads:
		total += payload.amount
	_check(results, "one huge frame is clamped to 0.5 s of DoT, not the whole gap",
		host.health.payloads.size() == 1 and is_equal_approx(total, 2.0),
		"quanta=%d total=%s" % [host.health.payloads.size(), str(total)])
	_free(host)


static func _hot_is_integrated(results: Array) -> void:
	var host := _host()
	host.health.current_health = 40.0
	host.status.apply_effect(_regen(), 1, host)
	for i in 16:
		host.status._physics_process(DELTA)
	# regen: 5.0/s * 0.5 * 1 stack = 2.5 per quanta, 2.0 s / 0.5 = 4 quanta = 10.0.
	_check(results, "HoT heals the authored total over its duration",
		is_equal_approx(host.health.healed, 10.0), "healed=%s" % str(host.health.healed))
	# Same effect, four times the tick rate (1/32 s): the total is a property of the
	# duration and rate, not of how often the manager happens to look.
	var host2 := _host()
	host2.health.current_health = 40.0
	host2.status.apply_effect(_regen(), 1, host2)
	for i in 64:
		host2.status._physics_process(0.03125)
	_check(results, "the same effect at 4x the tick rate heals the same total",
		is_equal_approx(host2.health.healed, 10.0), "healed=%s" % str(host2.health.healed))
	_free(host)
	_free(host2)


static func _shield_layers(results: Array) -> void:
	var host := _host()
	var refresh_shield := _guard(30.0, StatusEffectConfig.STACK_REFRESH, 1)
	host.status.apply_effect(refresh_shield, 1, host)
	_check(results, "a shield effect publishes its full capacity as the pool",
		is_equal_approx(host.status.shield_remaining(), 30.0), str(host.status.shield_remaining()))
	var leftover := host.status.absorb_direct(12.0)
	_check(results, "absorbing spends the layer and reports the remainder",
		is_equal_approx(leftover, 0.0) and is_equal_approx(host.status.shield_remaining(), 18.0),
		"left=%s pool=%s" % [str(leftover), str(host.status.shield_remaining())])
	var over := host.status.absorb_direct(100.0)
	_check(results, "the excess passes through once the layer is spent",
		is_equal_approx(over, 82.0) and host.status.shield_remaining() == 0.0,
		"left=%s pool=%s" % [str(over), str(host.status.shield_remaining())])
	_check(results, "a spent shield does not delete its effect",
		host.status.has_effect(refresh_shield.effect_id) and host.status.effect_count() == 1, "")
	host.status.apply_effect(refresh_shield, 1, host)
	_check(results, "re-applying a REFRESH shield replenishes it to capacity",
		is_equal_approx(host.status.shield_remaining(), 30.0), str(host.status.shield_remaining()))
	_free(host)


static func _additive_shield_has_no_infinite_loop(results: Array) -> void:
	var host := _host()
	var additive := _guard(10.0, StatusEffectConfig.STACK_ADD, 3)
	host.status.apply_effect(additive, 1, host)
	host.status.apply_effect(additive, 1, host)
	host.status.apply_effect(additive, 1, host)
	_check(results, "ADD grows the layer one granted capacity per stack",
		is_equal_approx(host.status.shield_remaining(), 30.0) and host.status.stack_count(additive.effect_id) == 3,
		"pool=%s stacks=%d" % [str(host.status.shield_remaining()), host.status.stack_count(additive.effect_id)])
	host.status.apply_effect(additive, 1, host)
	host.status.apply_effect(additive, 1, host)
	_check(results, "re-applying at max stacks cannot farm shield",
		is_equal_approx(host.status.shield_remaining(), 30.0), str(host.status.shield_remaining()))
	# Two shield effects, consumed in insertion order, so one expiring cannot eat the other's
	# unspent capacity.
	var second := _guard(45.0, StatusEffectConfig.STACK_REFRESH, 1)
	second.effect_id = &"overguard"
	host.status.apply_effect(second, 1, host)
	var spent_first := host.status.absorb_direct(40.0)
	_check(results, "layers drain oldest-first and the newer layer is untouched by the surplus",
		is_equal_approx(spent_first, 0.0) and is_equal_approx(host.status.shield_remaining(), 35.0),
		"left=%s pool=%s" % [str(spent_first), str(host.status.shield_remaining())])
	host.status.clear_all()
	_check(results, "clear_all() takes the pool with the effects, and reports the removals",
		host.status.effect_count() == 0 and host.status.shield_remaining() == 0.0
		and host.status.shield_remaining() > -0.001,
		"pool=%s" % str(host.status.shield_remaining()))
	_free(host)


static func _absorb_edge_cases(results: Array) -> void:
	var host := _host()
	_check(results, "absorbing a non-positive or non-finite amount is a no-op",
		host.status.absorb_direct(0.0) == 0.0 and host.status.absorb_direct(-5.0) == 0.0
		and host.status.absorb_direct(NAN) == 0.0, "")
	var big := host.status.absorb_direct(1.0e9)
	_check(results, "an absurd hit is still clamped to the documented 10k ceiling",
		is_equal_approx(big, 10000.0), str(big))
	host.health.current_health = 100000.0
	# A DoT on a shielded host is absorbed before health, on the tick that fires.
	var guarded := _guard(25.0, StatusEffectConfig.STACK_REFRESH, 1)
	host.status.apply_effect(guarded, 1, host)
	var burned := _burn()
	host.status.apply_effect(burned, 1, host)
	for i in 16:
		host.status._physics_process(DELTA)
	# 1.0 s at interval 0.5 = 4 quanta x 2.0 = 8.0 of DoT, all inside the 25.0 layer.
	_check(results, "DoT is spent against the layer before health",
		host.health.payloads.is_empty() and is_equal_approx(host.status.shield_remaining(), 17.0),
		"payloads=%d pool=%s" % [host.health.payloads.size(), str(host.status.shield_remaining())])
	_free(host)


## The manager's own signals fire back into it (a pickup cleanses on apply in the real game),
## and the tick must survive re-entering it mid-loop.
static func _reentrancy(results: Array) -> void:
	var host := _host()
	var cleansed_from_signal: Array = []
	host.health.damaged.connect(func(_result: DamageResult) -> void:
		cleansed_from_signal.append(host.status.cleanse_all(true)))
	host.status.apply_effect(_burn(), 1, host)
	host.status.apply_effect(_slow(), 1, host)
	for i in 16:
		host.status._physics_process(DELTA)
	_check(results, "cleanse_all() from a damage signal during the tick does not corrupt it",
		not cleansed_from_signal.is_empty() and int(cleansed_from_signal[0]) >= 1
		and host.status.effect_count() == 0,
		"cleansed=%s count=%d" % [str(cleansed_from_signal), host.status.effect_count()])
	_check(results, "and the fold is still finite and neutral afterwards",
		is_finite(host.status.move_speed_factor()) and is_equal_approx(host.status.move_speed_factor(), 1.0),
		str(host.status.move_speed_factor()))
	# Remove-during-removal: an effect the handler already erased must not be double-emitted.
	var double: Array = []
	var host2 := _host()
	host2.status.effect_expired.connect(func(id: StringName) -> void:
		double.append(host2.status.cleanse(id)))
	host2.status.apply_effect(_slow(), 1, host2)
	for i in 32:
		host2.status._physics_process(DELTA)
	_check(results, "a removal racing the expiry pass is idempotent",
		double.size() == 1 and bool(double[0]) == false, str(double))
	_free(host)
	_free(host2)


static func _soft_lock_cap(results: Array) -> void:
	var brief := StatusEffect.new(_lock(1.5), 1)
	_check(results, "a normal stun keeps its authored duration",
		is_equal_approx(brief.remaining, 1.5), str(brief.remaining))
	var forever := StatusEffect.new(_lock(30.0), 1)
	_check(results, "a mis-authored 30 s stun is capped at the documented 3 s",
		is_equal_approx(forever.remaining, 3.0), str(forever.remaining))
	forever.reapply(1, null, 10.0, 1.0, 1.0)
	_check(results, "and a duration multiplier on a re-apply cannot inflate it past the cap",
		is_equal_approx(forever.remaining, 3.0), str(forever.remaining))
	var rooted := StatusEffect.new(_lock(30.0, true), 1)
	_check(results, "roots are capped the same way", is_equal_approx(rooted.remaining, 3.0), "")
	var host := _host()
	host.status.apply_effect(_lock(30.0), 1, host)
	_check(results, "the lock is live for reads while it runs", host.status.is_stunned(), "")
	for i in 24:
		host.status._physics_process(DELTA)
	_check(results, "the capped lock releases within 3 s of game time",
		not host.status.is_stunned() and host.status.effect_count() == 0,
		"stunned=%s count=%d" % [str(host.status.is_stunned()), host.status.effect_count()])
	_free(host)


static func _rejected_authoring(results: Array) -> void:
	var host := _host()
	var anonymous := _slow()
	anonymous.effect_id = &""
	_check(results, "a config with no effect_id is refused, not applied",
		host.status.apply_effect(anonymous, 1, host) == 0 and host.status.effect_count() == 0, "")
	var no_ticks := _slow()
	no_ticks.tick_interval = 0.0
	_check(results, "a DoT cadence of zero is refused",
		host.status.apply_effect(no_ticks, 1, host) == 0, "")
	var permanent_stun := _lock(0.0)
	_check(results, "a permanent stun is refused (it would freeze the player forever)",
		host.status.apply_effect(permanent_stun, 1, host) == 0, "")
	var permanent_shield := _guard(30.0, StatusEffectConfig.STACK_REFRESH, 1)
	permanent_shield.duration = 0.0
	_check(results, "a permanent shield is refused (it would stall damage)",
		host.status.apply_effect(permanent_shield, 1, host) == 0, "")
	_check(results, "and rejection leaves the component parked, not half-applied",
		host.status.effect_count() == 0 and not host.status.is_physics_processing(), "")
	_check(results, "a null config is refused without a crash", host.status.apply_effect(null, 1, host) == 0, "")
	_free(host)


static func _signal_and_debug_surface(results: Array) -> void:
	var host := _host()
	var applied: Array = []
	host.status.effect_applied.connect(func(id: StringName, stacks: int) -> void: applied.append([id, stacks]))
	var burn := _burn()
	host.status.apply_effect(burn, 2, host)
	host.status.apply_effect(burn, 1, host)
	_check(results, "effect_applied reports the id and the resulting stacks both times",
		applied.size() == 2 and int(applied[0][1]) == 2 and int(applied[1][1]) == 3, str(applied))
	var snapshot: Dictionary = host.status.get_debug_snapshot()
	var effects: Array = snapshot["effects"]
	_check(results, "the debug snapshot lists one entry per effect with its shield",
		effects.size() == 1 and snapshot.has("recomputes") and snapshot.has("stale"),
		str(snapshot.keys()))
	_check(results, "active_effect_ids stays available for the HUD and matches the table",
		host.status.active_effect_ids().size() == 1 and host.status.has_effect(&"burn"), "")
	_check(results, "cleanse_all(false) also removes the beneficial ones",
		host.status.cleanse_all(false) == 1 and host.status.effect_count() == 0, "")
	_free(host)


static func suite() -> Array:
	var results: Array = []
	_reads_are_cached(results)
	_fold_matches_brute_force(results)
	_neutral_factors_skip_pow(results)
	_expiry_invalidates(results)
	_idle_and_wake(results)
	_dot_quanta(results)
	_hitch_is_clamped(results)
	_hot_is_integrated(results)
	_shield_layers(results)
	_additive_shield_has_no_infinite_loop(results)
	_absorb_edge_cases(results)
	_reentrancy(results)
	_soft_lock_cap(results)
	_rejected_authoring(results)
	_signal_and_debug_surface(results)
	return results
