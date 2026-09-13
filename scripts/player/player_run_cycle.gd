class_name PlayerRunCycle
extends RefCounted

## Run (re)start for Player: the component resets and the starter kit. Player keeps
## the teleport and the state clears (they touch its own private state and the
## interpolation snapshots); this module owns "which component resets in which
## order", which is the part with a documented ordering contract.

var _build: PlayerBuild = null
var _health: HealthComponent = null
var _progression: ProgressionComponent = null
var _dodge: DodgeController = null
var _stamina: StaminaComponent = null
var _experience: ExperienceComponent = null
var _weapons: WeaponManager = null
var _status: StatusManager = null
var _skills: SkillController = null


func bind(
	build: PlayerBuild,
	health: HealthComponent,
	progression: ProgressionComponent,
	dodge: DodgeController,
	stamina: StaminaComponent,
	experience: ExperienceComponent,
	weapons: WeaponManager,
	status: StatusManager,
	skills: SkillController
) -> void:
	_build = build
	_health = health
	_progression = progression
	_dodge = dodge
	_stamina = stamina
	_experience = experience
	_weapons = weapons
	_status = status
	_skills = skills


## Reset every run-scoped component. Order is the contract: progression first so
## health derives from the fresh (empty run) modifiers, and the build rebuild last
## so the derived stats reflect the emptied modifiers.
func reset_components() -> void:
	_progression.reset()
	_health.reset(_build.derived_max_health())
	_dodge.reset()
	_stamina.reset_for_new_run()
	_experience.reset_for_new_run()
	if _skills != null:
		_skills.reset_for_new_run()
	_weapons.reset_for_new_run()
	_status.clear_all()
	_build.rebuild_derived_stats()


## Starter kit: daily loadout (or Gladius) in slot 0 + the first skill unlocked
## (all tolerant when the ContentRegistry is unavailable, e.g. headless direct use).
## Slot 1 + locked skills are filled by Main from owned meta unlocks after reset.
func equip_starter_kit() -> void:
	_weapons.equip_by_id(_starter_weapon_id(), 0, true)
	if _skills != null:
		_skills.assign_skill_by_id(&"seismic_slam", 0, true)
		_skills.assign_skill_by_id(&"bladestorm", 1, false)
		_skills.assign_skill_by_id(&"phantom_rush", 2, false)


func _starter_weapon_id() -> StringName:
	if GameRoot != null:
		return GameRoot.get_daily_weapon()
	return &"gladius"
