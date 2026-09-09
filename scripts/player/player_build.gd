class_name PlayerBuild
extends RefCounted

## Player build/derived-stats application, extracted from Player. Applies upgrades
## through the runtime ProgressionComponent, rebuilds derived stats (move speed,
## max HP, stamina, weapons, skill cooldowns) from the same source, and tops HP up
## to a raised maximum when the player was already full. Player re-emits
## `upgrade_applied` so its public signal contract is unchanged.
##
## All component references are typed and required (Player guarantees them before
## binding); only the SkillController is optional and may be null.

signal upgrade_applied(upgrade_id: StringName)

var _health: HealthComponent = null
var _progression: ProgressionComponent = null
var _controller: CharacterController = null
var _stamina: StaminaComponent = null
var _weapons: WeaponManager = null
var _skills: SkillController = null
var _base_move_speed := 6.0
var _base_max_health := 100.0


func bind(
	health: HealthComponent,
	progression: ProgressionComponent,
	controller: CharacterController,
	stamina: StaminaComponent,
	weapons: WeaponManager,
	skills: SkillController,
	base_move_speed: float,
	base_max_health: float
) -> void:
	_health = health
	_progression = progression
	_controller = controller
	_stamina = stamina
	_weapons = weapons
	_skills = skills
	_base_move_speed = base_move_speed
	_base_max_health = base_max_health


func has_progression() -> bool:
	return _progression != null


## Apply an upgrade through the runtime ProgressionComponent. Returns true when it
## was applied and reflected into derived stats. A max-health upgrade also tops the
## player up to the new maximum when they were already at full health.
func apply_upgrade(upgrade_id: StringName) -> bool:
	if not has_progression():
		return false
	var was_full := _at_full_health()
	if not _progression.apply_upgrade_by_id(upgrade_id):
		return false
	upgrade_applied.emit(upgrade_id)
	AudioManager.play_sfx(&"upgrade_select", -8.0)
	rebuild_derived_stats()
	if was_full:
		_top_up_health_to_max()
	return true


func rebuild_derived_stats() -> void:
	if _progression == null:
		return
	# Move speed feeds the CharacterController.
	_controller.set_move_speed(_progression.get_stat(&"move_speed_multiplier", _base_move_speed))
	# Max HP feeds the generic HealthComponent (max_health_add). Only raise when the
	# entity is alive; on a fresh run the health reset uses the derived max.
	_health.set_max_health(derived_max_health())
	# Stamina + weapons + skills refresh from the same progression source.
	_stamina.refresh_from_stats()
	_weapons.refresh_derived_stats()
	if _skills != null:
		_skills.set_cooldown_multiplier(_progression.get_stat(&"skill_cooldown_multiplier", 1.0))
		_skills.set_combat_modifiers(
			_progression.get_stat(&"skill_damage_multiplier", 1.0),
			_progression.get_stat(&"area_radius_multiplier", 1.0),
			_progression.get_stat(&"area_damage_multiplier", 1.0),
			_progression.get_stat(&"status_chance_add", 0.0)
		)


func derived_max_health() -> float:
	if _progression == null:
		return maxf(_base_max_health, 1.0)
	return maxf(_progression.get_stat(&"max_health_add", _base_max_health), 1.0)


func _at_full_health() -> bool:
	if _health == null:
		return false
	if _health.is_dead():
		return false
	return _health.get_health_ratio() >= 0.9999


## After a successful max-health upgrade from full health, raise current to the new max.
func _top_up_health_to_max() -> void:
	if _health == null:
		return
	var new_max := derived_max_health()
	# Compute the gap between current and the new max and heal exactly that (heal caps
	# at max and never revives, so this is safe).
	var current := _health.get_current()
	var gap := maxf(new_max - current, 0.0)
	if gap > 0.0:
		_health.heal(gap)
