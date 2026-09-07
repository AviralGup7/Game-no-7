class_name WaveSpawnEntry
extends Resource

## One line item in a wave plan: how many of an archetype to spawn, with optional
## weighting/elite/tag metadata. Both authored wave resources and procedurally
## generated plans use this type so they are inspected and validated identically.

@export var archetype_id: StringName = &""
@export var count: int = 1
@export var spawn_weight: float = 1.0
@export var elite_chance: float = 0.0
@export var spawn_tags: Array[StringName] = []


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(archetype_id).is_empty():
		problems.append("WaveSpawnEntry archetype_id is empty")
	if count < 0:
		problems.append("WaveSpawnEntry count cannot be negative")
	if spawn_weight <= 0.0:
		problems.append("WaveSpawnEntry spawn_weight must be > 0")
	if not is_finite(spawn_weight):
		problems.append("WaveSpawnEntry spawn_weight must be finite")
	if elite_chance < 0.0 or elite_chance > 1.0:
		problems.append("WaveSpawnEntry elite_chance must be in [0,1]")
	return problems


func duplicate_entry() -> WaveSpawnEntry:
	var copy := WaveSpawnEntry.new()
	copy.archetype_id = archetype_id
	copy.count = count
	copy.spawn_weight = spawn_weight
	copy.elite_chance = elite_chance
	copy.spawn_tags = spawn_tags.duplicate()
	return copy
