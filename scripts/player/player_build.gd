class_name PlayerBuild
extends RefCounted

## Player build/derived-stats application, extracted from Player. Applies upgrades
## through the runtime ProgressionComponent, rebuilds derived stats (move speed,
## max HP, stamina, weapons, skill cooldowns) from the same source, and tops HP up
## to a raised maximum when the player was already full. Player re-emits
## `upgrade_applied` so its public signal contract is unchanged.

signal upgrade_applied(upgrade_id: StringName)

var _health: Node = null
var _progression: Node = null
var _controller: Node = null
var _stamina: Node = null
var _weapons: Node = null
var _skills: Node = null
var _base_move_speed := 6.0
var _base_max_health := 100.0


func bind(health: Node, progression: Node, controller: Node, stamina: Node, weapons: Node, skills: Node, base_move_speed: float, base_max_health: float) -> void:
	_health = health
	_progression = progression
	_controller = controller
	_stamina = stamina
	_weapons = weapons
	_skills = skills
	_base_move_speed = base_move_speed
	_base_max_health = base_max_health


func has_progression() -> bool:
	return _progression != null and _progression.has_method("apply_upgrade_by_id")


## Apply an upgrade through the runtime ProgressionComponent. Returns true when it
## was applied and reflected into derived stats. A max-health upgrade also tops the
## player up to the new maximum when they were already at full health.
func apply_upgrade(upgrade_id: StringName) -> bool:
	if not has_progression():
		return false
	var was_full := _at_full_health()
	if not bool(_progression.call("apply_upgrade_by_id", upgrade_id)):
		return false
	upgrade_applied.emit(upgrade_id)
	AudioManager.play_sfx(&"upgrade_select")
	rebuild_derived_stats()
	if was_full:
		_top_up_health_to_max()
	return true


func rebuild_derived_stats() -> void:
	if _progression == null:
		return
	# Move speed feeds the CharacterController.
	if _controller != null and _progression.has_method("get_stat"):
		var speed := float(_progression.call("get_stat", &"move_speed_multiplier", _base_move_speed))
		if _controller.has_method("set_move_speed"):
			_controller.call("set_move_speed", speed)
	# Max HP feeds the generic HealthComponent (max_health_add). Only raise when the
	# entity is alive; on a fresh run the health reset uses the derived max.
	if _health != null and _progression.has_method("get_stat"):
		var new_max := derived_max_health()
		if _health.has_method("set_max_health"):
			_health.call("set_max_health", new_max)
	# Stamina + weapons + skills refresh from the same progression source.
	if _stamina != null and _stamina.has_method("refresh_from_stats"):
		_stamina.call("refresh_from_stats")
	if _weapons != null and _weapons.has_method("refresh_derived_stats"):
		_weapons.call("refresh_derived_stats")
	if _skills != null and _skills.has_method("set_cooldown_multiplier") and _progression.has_method("get_stat"):
		_skills.call("set_cooldown_multiplier", float(_progression.call("get_stat", &"skill_cooldown_multiplier", 1.0)))


func derived_max_health() -> float:
	if _progression != null and _progression.has_method("get_stat"):
		return maxf(float(_progression.call("get_stat", &"max_health_add", _base_max_health)), 1.0)
	return maxf(_base_max_health, 1.0)


func _at_full_health() -> bool:
	if _health == null:
		return false
	if _health.has_method("is_dead") and bool(_health.call("is_dead")):
		return false
	if _health.has_method("get_health_ratio"):
		return float(_health.call("get_health_ratio")) >= 0.9999
	return false


## After a successful max-health upgrade from full health, raise current to the new max.
func _top_up_health_to_max() -> void:
	if _health == null or not _health.has_method("heal"):
		return
	var new_max := derived_max_health()
	# Compute the gap between current and the new max and heal exactly that (heal caps
	# at max and never revives, so this is safe).
	var current := new_max
	if _health.has_method("get_current"):
		current = float(_health.call("get_current"))
	var gap := maxf(new_max - current, 0.0)
	if gap > 0.0:
		_health.call("heal", gap)
