class_name PlayerDebugView
extends RefCounted

## Read-only snapshots for Player, extracted so the root keeps the command surface.
## Mirrors EnemyDebugView / CameraRigDebug: static functions, no state, called with
## the orchestrator as the argument.

## Runtime debug mirror. `control_enabled` is the raw input gate (the root passes it
## in, because the snapshot reports the flag itself, not the alive-gated view).
static func snapshot(host: Player, control_enabled: bool) -> Dictionary:
	return {
		"position": host.global_position,
		"health": host.get_health_component().get_debug_snapshot(),
		"controller": host.get_character_controller().get_debug_snapshot(),
		"alive": host.is_alive(),
		"control_enabled": control_enabled,
		"progression": host.get_progression_component().get_debug_snapshot(),
		"level": host.get_level(),
		"stamina": host.get_stamina_fraction(),
		"weapons": host.get_weapon_manager().get_debug_snapshot(),
		"skills": {} if host.get_skill_controller() == null else host.get_skill_controller().get_debug_snapshot(),
	}


static func progression_snapshot(host: Player) -> Dictionary:
	return host.get_progression_component().get_debug_snapshot()


## Serializable build mirror consumed by RunState. Live components remain the
## source of truth; this method only reads their stable content ids and tags.
static func build_snapshot(host: Player) -> Dictionary:
	var weapons: Array = host.get_weapon_manager().get_loadout_ids()
	var skills: Array = [] if host.get_skill_controller() == null else host.get_skill_controller().get_assigned_skill_ids()
	var archetypes: Array[StringName] = []
	if ContentRegistry != null:
		for id in weapons:
			var wc := ContentRegistry.get_weapon(StringName(String(id)))
			if wc != null:
				for tag in wc.tags:
					if tag not in archetypes:
						archetypes.append(tag)
		for id in skills:
			var sc := ContentRegistry.get_skill(StringName(String(id)))
			if sc != null:
				for tag in sc.tags:
					if tag not in archetypes:
						archetypes.append(tag)
		var stacks: Dictionary = host.get_progression_component().get_upgrade_stack_snapshot()
		for id in stacks:
			if int(stacks[id]) <= 0:
				continue
			var uc := ContentRegistry.get_upgrade(StringName(String(id)))
			if uc != null:
				if uc.category not in archetypes:
					archetypes.append(uc.category)
				for tag in uc.tags:
					if tag not in archetypes:
						archetypes.append(tag)
	return {"equipped_weapons": weapons, "equipped_skills": skills, "build_archetypes": archetypes}
