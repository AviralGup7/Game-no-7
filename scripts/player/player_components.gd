class_name PlayerComponents
extends RefCounted

## Scene contract for Player: which child nodes are REQUIRED and what happens when a
## scene variant omits one.
##
## The typed field resolution itself stays on Player (it assigns the private fields
## the whole class reads), the same way EnemyBase keeps its own resolver. This module
## owns the check that the resolver's result satisfies the REQUIRED set.

## Fail fast when a REQUIRED component is missing from the scene variant. Debug/test
## builds assert immediately (the bug is caught the moment the scene loads); release
## builds log once and disable processing rather than silently degrading into a
## half-functional player.
static func check_required(
	host: Player,
	health: HealthComponent,
	controller: CharacterController,
	progression: ProgressionComponent,
	targeting: TargetingComponent,
	dodge: DodgeController,
	stamina: StaminaComponent,
	experience: ExperienceComponent,
	weapons: WeaponManager,
	status: StatusManager
) -> bool:
	var missing := PackedStringArray()
	if health == null:
		missing.append("HealthComponent")
	if controller == null:
		missing.append("CharacterController")
	if progression == null:
		missing.append("ProgressionComponent")
	if targeting == null:
		missing.append("TargetingComponent")
	if dodge == null:
		missing.append("DodgeController")
	if stamina == null:
		missing.append("StaminaComponent")
	if experience == null:
		missing.append("ExperienceComponent")
	if weapons == null:
		missing.append("WeaponManager")
	if status == null:
		missing.append("StatusManager")
	if missing.is_empty():
		return true
	push_error("Player requires components missing from its scene: %s — these are not optional; fix the scene variant of player.tscn." % ", ".join(missing))
	assert(false, "Player missing required components: %s" % ", ".join(missing))
	host.set_physics_process(false)
	return false
