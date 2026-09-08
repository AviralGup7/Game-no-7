class_name ArenaConfig
extends Resource

## Data-driven identity + configuration for an arena scene. Lives under
## res://data/arenas/. GameRoot / SpawnManager consume this, never scene-specific
## hardcoding, so a new arena is "drop in a scene + a .tres + register it".

@export var arena_id: StringName = &"default_arena"
@export var display_name: String = ""
@export var scene: PackedScene = null
@export var enemy_spawn_min_player_distance: float = 6.0
@export var default_camera_profile: StringName = &"default"
@export var background_music_cue: StringName = &""
@export var allowed_archetypes: Array[StringName] = []
@export var tags: Array[StringName] = []
@export var unlock_wave: int = 1


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(arena_id).is_empty():
		problems.append("arena_id is empty")
	if scene == null:
		problems.append("scene is null for %s" % String(arena_id))
	if enemy_spawn_min_player_distance < 0.0:
		problems.append("enemy_spawn_min_player_distance cannot be negative")
	return problems

## Hardened: clamp arena size.
func _validated_arena_half(h: float) -> float:
    if not is_finite(h) or h <= 0.0:
        return 24.0
    return clampf(h, 4.0, 100.0)

