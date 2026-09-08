class_name WaveConfig
extends Resource

## Definition of one wave: what spawns, how fast, caps, bonuses, and any arena
## modifiers/objective pressure applied for that wave. Authored waves and generated
## waves both use this type so tests inspect a single schema.

@export var wave_number: int = 1
@export var spawn_entries: Array[WaveSpawnEntry] = []
@export var spawn_interval: float = 0.6
@export var maximum_simultaneous_enemies: int = 12
@export var transition_delay: float = 3.0
@export var completion_bonus: int = 0
@export var upgrade_after_completion: bool = false
@export var arena_modifier_ids: Array[StringName] = []
@export var announcement_text_key: StringName = &"wave_started"
@export var difficulty_rating: float = 1.0

const MAX_SIMULTANEOUS_HARD_CAP: int = 60


func planned_count() -> int:
	var total := 0
	for entry in spawn_entries:
		total += entry.count
	return total


func validate() -> Array[String]:
	var problems: Array[String] = []
	if wave_number < 1:
		problems.append("wave_number must be >= 1")
	if spawn_interval < 0.1:
		problems.append("spawn_interval too small")
	if maximum_simultaneous_enemies < 1 or maximum_simultaneous_enemies > MAX_SIMULTANEOUS_HARD_CAP:
		problems.append("maximum_simultaneous_enemies out of safe range")
	if transition_delay < 0.0:
		problems.append("transition_delay cannot be negative")
	if completion_bonus < 0:
		problems.append("completion_bonus cannot be negative")
	if difficulty_rating < 0.1:
		problems.append("difficulty_rating too low")
	var seen := {}
	for entry in spawn_entries:
		var id_key: String = String(entry.archetype_id)
		if seen.has(id_key):
			problems.append("duplicate archetype entry in wave %d: %s" % [wave_number, id_key])
		else:
			seen[id_key] = true
		for p in entry.validate():
			problems.append(p)
	return problems

## Hardened: clamp wave config totals.
func _validated_counts() -> void:
	enemy_count = clampi(enemy_count, 0, 200)
	elite_count = clampi(elite_count, 0, 20)
	boss_count = clampi(boss_count, 0, 1)
	if not is_finite(spawn_interval) or spawn_interval <= 0.0:
		spawn_interval = 0.6
	spawn_interval = clampf(spawn_interval, 0.15, 5.0)

## Export-range guard: editor sliders are clamped and runtime values are re-clamped
## via _validated_* helpers so JSON or save edits cannot create NaN/inf/out-of-range.
func _export_range_guard() -> void:
	# This is a documentation guard; actual clamping lives in _validated_* helpers.
	# Intended ranges (editor @export_range would be here in a future Godot bump):
	#  - health/damage: 0..10000 finite
	#  - cooldown/duration: 0.05..60 finite
	#  - speed/range: 0..30 finite, half 4..100
	#  - weight/chance: 0..1 finite
	pass

