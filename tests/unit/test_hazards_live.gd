extends RefCounted

## Live-harness tests for ArenaHazards: real nodes in the tree, real Damageable victims,
## the physics tick driven by hand so timing assertions are exact.
##
## Registered in run_tests.gd's NODE_SUITES — these fixtures must be inside the tree,
## because a parentless Node3D reports an identity global_position and every spatial
## assertion would then be meaningless (test_area_combat.gd documents the same rule).
##
## What is pinned here is the behaviour the rebuild was FOR: bursts fire on accumulated
## game time (so hitstop stretches a hazard instead of fast-forwarding it), a field hurts
## on a per-victim cooldown instead of every frame, a plate is armed by the player and
## lands on enemies, the marker is optional, and a hazard never touches a victim its own
## query refused to report.
##
## Each case builds its own ArenaHazards, clears the fallback layout and authors exactly the
## hazards it is about, so the only timing variable is the delta the test feeds.

const DELTA := 0.05


class DummyTarget extends Damageable:
	var hp: float = 100.0
	var hits: int = 0
	var last_source_id: StringName = &""
	var last_amount: float = 0.0
	var status: StatusManager = null
	var probe_health: HealthComponent = null

	func is_alive() -> bool:
		return hp > 0.0

	func apply_damage(payload: DamagePayload) -> DamageResult:
		var result := DamageResult.new()
		hits += 1
		last_source_id = payload.source_id
		last_amount = payload.amount
		hp = maxf(hp - payload.amount, 0.0)
		result.accepted = true
		result.final_amount = payload.amount
		return result

	func get_status_manager() -> StatusManager:
		return status

	func get_health_component() -> HealthComponent:
		return probe_health


## A HealthComponent that records instead of clamps, so a healing assertion measures what
## the hazard asked for rather than the vitals bookkeeping underneath it.
class ProbeHealth extends HealthComponent:
	var healed: float = 0.0

	func heal(amount: float) -> float:
		healed += amount
		return amount


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _dummy(team: String, at: Vector3) -> DummyTarget:
	var dummy := DummyTarget.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(dummy)
	dummy.global_position = at
	if team != "":
		dummy.add_to_group(team)
	return dummy


static func _hazards() -> ArenaHazards:
	var node := ArenaHazards.new()
	node.name = "HazardProbe"
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(node)
	# An unknown arena id gets the documented safe default; clear it so each case starts
	# from an empty layout it fills itself.
	node.configure(&"probe_no_such_arena", 12.0, 4242)
	node.clear_hazards()
	# Driven by hand: a real physics frame during the suite would tick hazards twice.
	node.set_physics_process(false)
	return node


static func _place(hazards: ArenaHazards, hazard_id: StringName, at: Vector3) -> HazardInstance:
	var placement := HazardPlacement.new()
	placement.config = HazardConfig.resolve(hazard_id)
	placement.position = at
	placement.mirror = HazardPlacement.MIRROR_NONE
	placement.phase_jitter = 0.0
	return hazards.add_placement(placement)


## Runs `ticks` physics steps of `delta`. Call counts are explicit because the whole point
## of several of these checks is that the hazard follows accumulated time, not frames.
static func _run(hazards: ArenaHazards, ticks: int, delta: float = DELTA) -> void:
	for _i in ticks:
		hazards._physics_process(delta)


static func _free(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()


static func suite() -> Array:
	var results: Array = []
	_burst_hits_both_sides_once_per_period(results)
	_burst_count_follows_accumulated_time(results)
	_field_throttles_per_victim(results)
	_heal_integrates_the_clock(results)
	_plate_is_a_player_tool(results)
	_visuals_are_optional(results)
	_status_lands_with_the_burst(results)
	_gather_filters(results)
	_disabled_and_debug_hooks(results)
	_non_finite_centre_is_skipped(results)
	return results


static func _burst_hits_both_sides_once_per_period(results: Array) -> void:
	var hazards := _hazards()
	var config := HazardConfig.resolve(&"fire_vent")
	var vent := _place(hazards, &"fire_vent", Vector3(0, 0.05, 0))
	var enemy := _dummy("enemies", Vector3(0, 0.0, 0.5))
	var player := _dummy("player", Vector3(0, 0.0, -1.0))
	# Period 4, telegraph 1: the warning window must not hurt anybody.
	_run(hazards, 70)
	var early_ok := is_equal_approx(enemy.hp, 100.0) and is_equal_approx(player.hp, 100.0)
	_run(hazards, 12)
	var struck_ok := enemy.hits == 1 and player.hits == 1
	var amount_ok := is_equal_approx(enemy.last_amount, config.damage) and is_equal_approx(player.last_amount, config.damage)
	var attribution_ok := enemy.last_source_id == config.source_id and String(vent.label()).begins_with("fire_vent")
	_run(hazards, 60)
	var once_ok := enemy.hits == 1 and player.hits == 1
	# A victim outside the radius is not merely undamaged: it is never a candidate.
	var far := _dummy("enemies", Vector3(9.0, 0.0, 0.0))
	_run(hazards, 61)
	var far_ok := far.hits == 0
	_check(results, "a vent ignores a victim outside its authored radius", far_ok, "hits=%d" % far.hits)
	_check(results, "a burst damages the player and an enemy once per period",
		early_ok and struck_ok and amount_ok and attribution_ok and once_ok,
		"early=%s struck=%s amount=%s attribution=%s once=%s" % [
			str(early_ok), str(struck_ok), str(amount_ok), str(attribution_ok), str(once_ok),
		])
	_free([hazards, enemy, player, far])


## The clock bug this rebuild fixed: hazard timers compared Time.get_ticks_msec() against
## gameplay intervals, so real frames — not game time — drove them while Engine.time_scale
## decided what each frame was worth.
static func _burst_count_follows_accumulated_time(results: Array) -> void:
	var hazards := _hazards()
	_place(hazards, &"fire_vent", Vector3(-6, 0.05, 0))
	var victim := _dummy("enemies", Vector3(-6, 0.0, 0))
	_run(hazards, 81)
	var coarse_hits := victim.hits
	# The same four seconds of GAME time delivered in 3210 tiny frames is what a hitstop of
	# 1/20th speed looks like from the hazard's side: one more burst, not twenty.
	_run(hazards, 3210, 0.00125)
	_check(results, "burst count follows game time, not frames elapsed",
		coarse_hits == 1 and victim.hits == 2, "coarse=%d total=%d" % [coarse_hits, victim.hits])
	_free([hazards, victim])


static func _field_throttles_per_victim(results: Array) -> void:
	var hazards := _hazards()
	var config := HazardConfig.resolve(&"spike_bed")
	_place(hazards, &"spike_bed", Vector3(6, 0.05, 6))
	var victim := _dummy("enemies", Vector3(6, 0.0, 6))
	_run(hazards, 60)
	# 3 s of standing on spikes costs three hits at one per second, not sixty.
	_check(results, "a spike bed costs one hit per victim cooldown, not per tick",
		victim.hits == 3, "hits=%d over 3s (cooldown %ss, damage %ss)" % [
			victim.hits, str(config.victim_cooldown), str(config.damage)])
	_check(results, "throttled field damage is the authored number at the authored cadence",
		is_equal_approx(victim.hp, 100.0 - 3.0 * config.damage), "hp=%s" % str(victim.hp))
	_run(hazards, 28)
	_check(results, "a victim that stays in the field keeps bleeding on cadence",
		victim.hits == 5, "hits=%d" % victim.hits)
	_free([hazards, victim])


static func _heal_integrates_the_clock(results: Array) -> void:
	var hazards := _hazards()
	var config := HazardConfig.resolve(&"heal_ward")
	_place(hazards, &"heal_ward", Vector3(-6, 0.05, -6))
	var player := _dummy("player", Vector3(-6, 0.0, -6))
	player.probe_health = ProbeHealth.new()
	player.add_child(player.probe_health)
	var crouching := _dummy("enemies", Vector3(-6, 0.0, -6))
	_run(hazards, 40)
	var first: ProbeHealth = player.probe_health
	_check(results, "a healing ward regenerates at its authored rate in hp per second",
		first != null and first.healed > config.heal_per_second * 1.9 and first.healed < config.heal_per_second * 2.1,
		"healed=%s want~%s" % [str(first.healed) if first != null else "null", str(config.heal_per_second * 2.0)])
	_check(results, "a ward is not a weapon: enemies are not even candidates",
		crouching.hits == 0, "hits=%d" % crouching.hits)
	# Same field, a fifth of the scan rate, five times the frames: the integrated total is
	# what must not change.
	var fast := _hazards()
	_place(fast, &"heal_ward", Vector3(-10, 0.05, 10))
	var crouch := _dummy("player", Vector3(-10, 0.0, 10))
	crouch.probe_health = ProbeHealth.new()
	crouch.add_child(crouch.probe_health)
	_run(fast, 200, 0.01)
	var second: ProbeHealth = crouch.probe_health
	var fine := second.healed if second != null else 0.0
	_check(results, "the same ward heals the same total at 100 Hz",
		first != null and absf(fine - first.healed) < 0.05, "fine=%s coarse=%s" % [str(fine), str(first.healed) if first != null else "null"])
	_free([hazards, fast, player, crouching, crouch])


static func _plate_is_a_player_tool(results: Array) -> void:
	var hazards := _hazards()
	_place(hazards, &"pressure_plate", Vector3(0, 0.05, -8))
	var enemy_on_it := _dummy("enemies", Vector3(0, 0.0, -8))
	var enemy_near := _dummy("enemies", Vector3(1.6, 0.0, -8))
	_run(hazards, 20)
	_check(results, "enemies walking over a plate do not set it off",
		enemy_on_it.hits == 0 and enemy_near.hits == 0, "on=%d near=%d" % [enemy_on_it.hits, enemy_near.hits])
	var player := _dummy("player", Vector3(0, 0.0, -8))
	_run(hazards, 4)
	var blast_ok := enemy_on_it.hits == 1 and enemy_near.hits == 1
	# The blast (3.5 m) is wider than the tread (2.0 m): the far enemy is inside one and
	# outside the other, which is the entire design of the plate.
	var beyond := _dummy("enemies", Vector3(5.5, 0.0, -8))
	_run(hazards, 4)
	_check(results, "the player arms it and only enemies eat the blast",
		blast_ok and player.hits == 0, "blast=%s player_immune=%s" % [str(blast_ok), str(player.hits == 0)])
	_check(results, "a detonated plate re-arms on its own cooldown",
		beyond.hits == 0 and enemy_on_it.hits == 1, "beyond=%d on_it=%d" % [beyond.hits, enemy_on_it.hits])
	_run(hazards, 130)
	_check(results, "a player still standing on a re-armed plate sets it off again",
		enemy_on_it.hits == 2, "hits=%d" % enemy_on_it.hits)
	_free([hazards, enemy_on_it, enemy_near, player, beyond])


static func _visuals_are_optional(results: Array) -> void:
	var hazards := _hazards()
	var config := HazardConfig.resolve(&"fire_vent")
	var instance := _place(hazards, &"fire_vent", Vector3(-9, 0.05, 9))
	var marker := instance.visual()
	_check(results, "an authored hazard gets a typed marker child", marker != null and marker is HazardMarker)
	var victim := _dummy("enemies", Vector3(-9, 0.0, 9))
	_run(hazards, 81)
	var damage_with_visuals := victim.hp
	# Free the marker and KEEP the dangling reference: that is the state a world rebuild
	# actually leaves behind, and gameplay must be unaffected by it.
	if marker != null:
		marker.free()
	_run(hazards, 81)
	_check(results, "gameplay keeps running with the visual gone",
		is_equal_approx(damage_with_visuals, 100.0 - config.damage)
			and is_equal_approx(victim.hp, damage_with_visuals - config.damage),
		"with=%s without=%s want=%s" % [str(damage_with_visuals), str(victim.hp), str(100.0 - 2.0 * config.damage)])
	var mover := _place(hazards, &"ember_mover", Vector3(0, 0.05, 0))
	var mover_marker := mover.visual()
	if mover_marker != null:
		mover_marker.free()
	_run(hazards, 10)
	_check(results, "an orbiting hazard advances its own position even with no marker",
		not is_equal_approx(mover.position.distance_to(mover.origin), 0.0), str(mover.position))
	_free([hazards, victim])


static func _status_lands_with_the_burst(results: Array) -> void:
	var hazards := _hazards()
	var burn: StatusEffectConfig = null
	if ResourceLoader.exists("res://data/status/burn.tres"):
		burn = load("res://data/status/burn.tres") as StatusEffectConfig
	_check(results, "the burn status vents stamp is authored data that validates",
		burn != null and burn.validate().is_empty())
	var inside := _dummy("enemies", Vector3(4, 0.0, 4))
	inside.status = StatusManager.new()
	inside.add_child(inside.status)
	var outside := _dummy("enemies", Vector3(4, 0.0, 9))
	outside.status = StatusManager.new()
	outside.add_child(outside.status)
	_place(hazards, &"fire_vent", Vector3(4, 0.05, 4))
	_run(hazards, 85)
	_check(results, "a burst stamps its status on the victims inside it",
		inside.status != null and inside.status.has_effect(&"burn"),
		"effects=%s" % str(inside.status.active_effect_ids()) if inside.status != null else "no manager")
	_check(results, "a victim outside the burst is not burned by the same vent",
		outside.status != null and not outside.status.has_effect(&"burn"),
		"effects=%s" % str(outside.status.active_effect_ids()) if outside.status != null else "no manager")
	_free([hazards, inside, outside])


static func _gather_filters(results: Array) -> void:
	var hazards := _hazards()
	_place(hazards, &"spike_bed", Vector3(-4, 0.05, -4))
	var unaffiliated := DummyTarget.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(unaffiliated)
	unaffiliated.global_position = Vector3(-4, 0.0, -4)
	var corpse := _dummy("enemies", Vector3(-3.9, 0.0, -4))
	corpse.hp = 0.0
	# A bystander well outside the field, so "the snapshot reports the gather it did"
	# measures a real candidate and not whatever stale fixtures are still in the tree.
	var bystander := _dummy("enemies", Vector3(-9.5, 0.0, -9.5))
	_run(hazards, 60)
	_check(results, "a victim in no team group and a dead body are never candidates",
		unaffiliated.hits == 0 and corpse.hits == 0, "stray=%d corpse=%d" % [unaffiliated.hits, corpse.hits])
	var snapshot := hazards.get_debug_snapshot()
	_check(results, "the tick reports how much gathering it did",
		snapshot.has("victims_last_tick") and snapshot.has("queries_last_tick")
			and int(snapshot["victims_last_tick"]) > 0, str(snapshot.get("victims_last_tick")))
	_free([hazards, unaffiliated, corpse, bystander])


static func _disabled_and_debug_hooks(results: Array) -> void:
	var hazards := _hazards()
	# GDScript lambdas copy local captures, so the counter travels in a shared Array.
	var counter: Array = [0]
	hazards.hazard_triggered.connect(func(hazard_id: StringName, _at: Vector3) -> void:
		if hazard_id == &"fire_vent":
			counter[0] += 1)
	var victim := _dummy("enemies", Vector3(8, 0.0, 8))
	_place(hazards, &"fire_vent", Vector3(8, 0.05, 8))
	hazards.ignite_pulses()
	_run(hazards, 22)
	var ignited_ok := victim.hits == 1 and int(counter[0]) == 1
	hazards.set_enabled(false)
	_run(hazards, 160)
	var disabled_ok := victim.hits == 1
	_check(results, "ignite_pulses skips the wait and the trigger signal carries the hazard id",
		ignited_ok, "hits=%d signals=%d" % [victim.hits, int(counter[0])])
	_check(results, "set_enabled(false) stops hazard gameplay entirely", disabled_ok, "hits=%d" % victim.hits)
	hazards.set_enabled(true)
	_run(hazards, 80)
	_check(results, "re-enabling resumes bursts on the same clock",
		victim.hits == 2, "hits=%d" % victim.hits)
	_free([hazards, victim])


static func _non_finite_centre_is_skipped(results: Array) -> void:
	var hazards := _hazards()
	var instance := _place(hazards, &"fire_vent", Vector3(-8, 0.05, -8))
	var victim := _dummy("enemies", Vector3(-8, 0.0, -8))
	instance.position = Vector3(NAN, 0.0, -8.0)
	_run(hazards, 160)
	_check(results, "a non-finite epicentre damages nobody instead of spraying NaN knockback",
		victim.hits == 0 and is_equal_approx(victim.hp, 100.0), "hits=%d" % victim.hits)
	_free([hazards, victim])
