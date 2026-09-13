class_name EnemyDebugView
extends RefCounted

## One read-only render of an EnemyBase for the debug overlay and the headless suites
## (mirrors Player.get_debug_snapshot / Arena.get_debug_snapshot). Extracted from
## EnemyBase so the diagnostics do not sit in the middle of the AI: adding a field
## here touches no gameplay code.
##
## Every value is read through the host's public typed API; the snapshot is a copy and
## never holds a live reference.


static func snapshot(host: EnemyBase) -> Dictionary:
	var personality := host.get_personality()
	var health := host.get_health_component()
	return {
		"archetype": String(host.get_archetype_id()),
		"state": String(host.get_state()),
		"alive": host.is_alive(),
		"death_handled": host.is_death_handled(),
		"position": host.global_position,
		"health": health.get_debug_snapshot() if health != null else {},
		"desired_dir": host.desired_dir,
		"desired_speed": host.desired_speed,
		"move_override": host.is_move_overridden(),
		"poise_guard": host.is_poise_guarding(),
		"elite": host.is_elite(),
		"perception": host.get_perception().get_status_name(),
		"aggression": roundf(personality.aggression * 100.0) / 100.0 if personality != null else -1.0,
		"caution": roundf(personality.caution * 100.0) / 100.0 if personality != null else -1.0,
		"fear_retreating": host.is_fear_retreating(),
	}
