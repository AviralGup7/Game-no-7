class_name PlayerIntake
extends RefCounted

## Damage intake for Player: the Damageable entry point plus the two intake stages
## (status mitigation/shields on the way in, payload riders on the way out).
##
## Extracted from Player so the root keeps the death latch and the command surface.
## Everything here reaches the components through the host's typed accessors, so a
## headless fixture that never calls apply_damage is unaffected — and the mitigation
## provider stays a Player method, because HealthComponent holds it as a Callable.

## Damageable protocol entry point. A corpse keeps DamageResult.IGNORE_DEAD; a
## malformed or invulnerable payload is handed to HealthComponent untouched so it
## can answer with its own ignore reason.
func apply_damage(host: Player, payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	if not host.is_alive():
		result.ignored_reason = DamageResult.IGNORE_DEAD
		return result
	var health := host.get_health_component()
	# Do not consume a shield for payloads HealthComponent will reject before
	# intake (malformed, invulnerable, or already-dead). Accepted hits are then
	# reduced by status mitigation/shields exactly once.
	if payload == null or not payload.is_valid() or health.is_invulnerable():
		return health.take_damage(payload)
	var final_payload := apply_status_intake(host, payload)
	var taken := health.take_damage(final_payload)
	if taken.accepted and taken.final_amount > 0.0:
		apply_payload_status(host, payload, taken)
	return taken


## Incoming weapon/projectile riders: apply payload effects after an accepted hit.
func apply_payload_status(host: Player, payload: DamagePayload, result: DamageResult = null) -> void:
	if payload == null or payload.status_effects.is_empty():
		return
	var applied := host.get_status_manager().apply_effects(payload.status_effects, payload.source)
	if result != null:
		for raw_id in applied:
			if int(applied[raw_id]) > 0:
				result.status_effects_applied.append(StringName(String(raw_id)))


## Scale + shield an incoming payload through the StatusManager (guard shields,
## shock vulnerability...). Returns the original payload when nothing reduced it.
func apply_status_intake(host: Player, payload: DamagePayload) -> DamagePayload:
	if payload == null:
		return payload
	var status := host.get_status_manager()
	var factor := status.incoming_damage_factor()
	var amount := payload.amount * factor
	amount = status.absorb_direct(amount)
	if is_equal_approx(amount, payload.amount):
		return payload
	return payload.with_amount(amount)


## Mitigation provider for the generic HealthComponent: computes post-resistance
## damage from the player's progression-derived damage_resistance_add.
func mitigation(host: Player, amount: float) -> float:
	var resistance := clampf(host.get_progression_component().get_stat(&"damage_resistance_add", 0.0), 0.0, 1.0)
	return maxf(amount * (1.0 - resistance), 0.0)
