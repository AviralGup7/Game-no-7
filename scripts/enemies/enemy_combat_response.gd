class_name EnemyCombatResponse
extends RefCounted

## Damage intake, damage response and the death sequence of EnemyBase, extracted so
## the exactly-once guarantees live in one auditable place (composition pattern:
## EnemyLocomotion / EnemyNavigator / EnemyStriker / EnemyPack / EnemyMotion).
##
## Owns:
##   * the poise guard budget — a guarded windup is not interrupted by chip damage
##     until the configured poise budget breaks;
##   * status mitigation/shields as an INTAKE stage (a malformed or invulnerable hit
##     is rejected by HealthComponent without consuming a shield), and the payload's
##     status riders as a POST-ACCEPT stage (only accepted damage procs a build);
##   * the accepted-hit response: resistance-aware knockback, pain-as-stimulus
##     perception noise, feedback/audio, crit hitstop and the Hurt transition;
##   * death: the idempotent state transition, the exactly-once EventBus score
##     payload, despawn, feedback/audio, hitstop and the fade-and-free.
##
## The host keeps the Damageable entry points (apply_damage/is_alive) and the
## lifecycle flags — `_alive`/`_death_handled` are read by tests and by the AI — so
## this module only ever reads the host through its public typed accessors and asks
## `mark_dead()` to win the one-shot transition.

## Poise damage decays per second while the guard is up.
const POISE_DECAY_PER_SECOND := 25.0

## Crit/death punch: micro-freeze seconds and trauma handed to the HitstopManager.
const CRIT_HITSTOP := 0.04
const CRIT_TRAUMA := 0.16
const DEATH_HITSTOP := 0.05
const DEATH_TRAUMA := 0.2
## Runaway knockback guard (see _on_accepted): lengths above this are normalized.
const MAX_KNOCKBACK_LENGTH_SQ := 10000.0
const MAX_KNOCKBACK_LENGTH := 100.0
## Seconds the corpse stays before the tween frees it — slightly longer than the
## feedback sink so death animations get to land.
const CORPSE_LIFETIME := 0.8
## Self-destruct overkill: enough to kill through any max health/shield.
const DETONATE_OVERKILL := 999.0

var _poise_guard := false
var _poise_damage := 0.0


## Arm/disarm the windup interruption budget; disarming clears the accumulated damage.
func set_poise_guard(active: bool) -> void:
	_poise_guard = active
	if not active:
		_poise_damage = 0.0


func is_poise_guarding() -> bool:
	return _poise_guard


func decay_poise(delta: float) -> void:
	if _poise_guard and _poise_damage > 0.0:
		_poise_damage = maxf(_poise_damage - POISE_DECAY_PER_SECOND * delta, 0.0)


## Damageable protocol entry point. Returns the HealthComponent's DamageResult, with
## the project's two ignore reasons preserved for a missing component / a corpse.
func apply_damage(host: EnemyBase, payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	var health := host.get_health_component()
	if health == null:
		result.ignored_reason = &"no_health_component"
		return result
	if not host.is_alive():
		result.ignored_reason = DamageResult.IGNORE_DEAD
		return result
	# Status mitigation/shields are an intake stage, but do not consume a shield
	# for malformed or invulnerable hits that HealthComponent will reject.
	var final_payload := payload
	if payload != null and payload.is_valid() and not health.is_invulnerable():
		final_payload = _apply_intake(host, payload)
	var accepted := health.take_damage(final_payload)
	_on_accepted(host, accepted, payload)
	# Invulnerability, shields and dead-state rejection must not grant a
	# status proc. Only an accepted hit is allowed to advance a build synergy.
	if accepted.accepted and accepted.final_amount > 0.0:
		_apply_riders(host, payload, accepted)
	return accepted


## HealthComponent's `damaged` signal path (accepted hits only): feedback, juice,
## poise and the Hurt transition. Exactly-once is the component's contract: it emits
## `damaged` only on the accepted path.
func respond_to_damage(host: EnemyBase, result: DamageResult) -> void:
	host.damaged.emit(result)
	var bus := host.get_event_bus()
	if bus != null:
		bus.enemy_damaged.emit(host, result)
	var feedback := host.get_feedback()
	if result.was_critical and feedback != null:
		feedback.play_crit()
	elif feedback != null:
		feedback.play_damaged()
	var audio := host.get_audio()
	if audio != null:
		audio.play_hit()
	if result.was_critical:
		_juice_hitstop(host, CRIT_HITSTOP, CRIT_TRAUMA)
	if not host.is_alive():
		return
	# Poise: while a windup is guarded, chip damage accumulates instead of
	# interrupting; only breaking the budget (or an over-budget hit) staggers.
	if not _breaks_poise(host, result.final_amount):
		return
	host.force_state(&"hurt")


## Idempotent death. `mark_dead()` is the race guard, so a second `died` emission
## (or a lethal hit landing in the same frame as an explosion) changes nothing.
func handle_death(host: EnemyBase) -> void:
	if not host.mark_dead():
		return
	host.set_desired_move(Vector3.ZERO, 0.0)
	host.clear_move_override()
	set_poise_guard(false)
	host.force_state(&"dead")
	host.died.emit()
	var bus := host.get_event_bus()
	if bus != null:
		bus.report_info("Enemy %s died" % String(host.get_archetype_id()))
		# Exactly-once score payload.
		bus.enemy_killed.emit(host, host.get_archetype_id(), host.get_score_value(), host.get_currency_value())
	host.despawn_requested.emit(host)
	var feedback := host.get_feedback()
	if feedback != null:
		feedback.play_died()
	var audio := host.get_audio()
	if audio != null:
		audio.play_death()
	_juice_hitstop(host, DEATH_HITSTOP, DEATH_TRAUMA)
	_fade_and_free(host)


## Lethal self-damage routed through the HealthComponent so the normal exactly-once
## death path fires (score payload, despawn, death-blast dispatch in SpawnManager).
func detonate_self(host: EnemyBase) -> void:
	if not host.is_alive():
		return
	var health := host.get_health_component()
	if health == null:
		return
	var payload := DamagePayload.new()
	payload.amount = maxf(health.get_current(), 0.0) + DETONATE_OVERKILL
	payload.source = host
	payload.source_id = host.get_archetype_id()
	payload.damage_type = &"explosion"
	health.take_damage(payload)


func health_fraction(host: EnemyBase) -> float:
	var health := host.get_health_component()
	if health != null:
		return clampf(health.get_health_ratio(), 0.0, 1.0)
	return 1.0 if host.is_alive() else 0.0


## True when this hit should interrupt the enemy (Hurt). While a poise guard is armed
## and a positive budget is configured, accepted damage accumulates and only the hit
## that crosses the budget staggers — that hit resets the budget.
func _breaks_poise(host: EnemyBase, amount: float) -> bool:
	if not _poise_guard:
		return true
	var cfg := host.get_config()
	var budget := cfg.poise if cfg != null else 0.0
	if budget <= 0.0:
		return true
	_poise_damage += amount
	if _poise_damage < budget:
		return false
	_poise_damage = 0.0
	return true


func _apply_riders(host: EnemyBase, payload: DamagePayload, result: DamageResult) -> void:
	if payload == null or payload.status_effects.is_empty():
		return
	var status := host.get_status_manager()
	if status == null:
		return
	var applied := status.apply_effects(payload.status_effects, payload.source)
	for raw_id in applied:
		if int(applied[raw_id]) > 0:
			result.status_effects_applied.append(StringName(String(raw_id)))


func _apply_intake(host: EnemyBase, payload: DamagePayload) -> DamagePayload:
	var status := host.get_status_manager()
	if status == null or payload == null:
		return payload
	var amount := payload.amount * status.incoming_damage_factor()
	amount = status.absorb_direct(amount)
	if is_equal_approx(amount, payload.amount):
		return payload
	return payload.with_amount(amount)


func _on_accepted(host: EnemyBase, result: DamageResult, payload: DamagePayload) -> void:
	if not result.accepted:
		return
	# Pain reveals the attacker: even an unaware enemy snaps its attention to
	# whoever hurt it (a stimulus, not a mind read — it still needs its
	# reaction beat before committing).
	var perception := host.get_perception()
	if perception != null and not perception.can_engage() and payload != null:
		var source := payload.source
		if source != null and source != host and source is Node3D:
			perception.note_noise((source as Node3D).global_position, 1.0, host.global_position)
	var cfg := host.get_config()
	var resistance := cfg.knockback_resistance if cfg != null else 0.0
	var resisted := payload.knockback * (1.0 - clampf(resistance, 0.0, 1.0))
	# Runtime guard (replaces the dead _validated_knockback helper): a NaN/inf
	# knockback must never reach the integrator, and runaway magnitudes are capped.
	if not is_finite(resisted.x) or not is_finite(resisted.y) or not is_finite(resisted.z):
		resisted = Vector3.ZERO
	elif resisted.length_squared() > MAX_KNOCKBACK_LENGTH_SQ:
		resisted = resisted.normalized() * MAX_KNOCKBACK_LENGTH
	host.get_motion().add_knockback(resisted)


## Crit/death punch: micro-freeze + trauma through the run's HitstopManager.
func _juice_hitstop(host: EnemyBase, duration: float, trauma: float) -> void:
	if not host.is_inside_tree():
		return
	for node in host.get_tree().get_nodes_in_group("hitstop_manager"):
		if node == null or not is_instance_valid(node):
			continue
		var manager := node as HitstopManager
		if manager == null:
			continue
		manager.request_hitstop(duration)
		manager.add_trauma(trauma)
		break  # Only one manager owns the global time_scale; avoid stacking the freeze


func _fade_and_free(host: EnemyBase) -> void:
	if not host.is_inside_tree():
		host.queue_free()
		return
	var tween := host.create_tween()
	tween.tween_interval(CORPSE_LIFETIME)
	tween.tween_callback(host.queue_free)
