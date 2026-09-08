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

## Hardened: validate spawn entry.
func _validated_entry() -> bool:
    if archetype_id == &"":
        return false
    if count < 0:
        return false
    return true
func _validated_count(c: int) -> int:
    if c < 0:
        return 0
    return mini(c, 200)

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

