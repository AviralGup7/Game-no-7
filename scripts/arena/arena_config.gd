class_name ArenaConfig
extends ValidatedConfig

## Data-driven identity + configuration for an arena scene. Lives under
## res://data/arenas/. GameRoot / SpawnManager consume this, never scene-specific
## hardcoding, so a new arena is "drop in a scene + a .tres + register it".
##
## `hazard_layout` is why this file extends ValidatedConfig: the arena — not
## ArenaHazards — is the authority on which hazards exist and where. Extending
## ValidatedConfig is what makes ContentLoader run validate() on it at load, so an
## authored layout with a missing config or a bad mirror is a startup error instead of
## an arena that quietly loses its hazards.

@export var arena_id: StringName = &"default_arena"
@export var display_name: String = ""
@export var scene: PackedScene = null
@export_range(0.0, 100.0, 0.1) var enemy_spawn_min_player_distance: float = 6.0
@export var default_camera_profile: StringName = &"default"
@export var background_music_cue: StringName = &""
@export var allowed_archetypes: Array[StringName] = []
@export var tags: Array[StringName] = []
@export_range(1, 1000) var unlock_wave: int = 1
## The arena's hazard layout, authored here so ArenaHazards never needs a per-arena
## branch. Each placement expands its own radial symmetry (HazardPlacement.mirror), so
## the number of live hazards is usually a multiple of the number of lines here.
@export var hazard_layout: Array[HazardPlacement] = []


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(arena_id).is_empty():
		problems.append("arena_id is empty")
	if scene == null:
		problems.append("scene is null for %s" % String(arena_id))
	if enemy_spawn_min_player_distance < 0.0:
		problems.append("enemy_spawn_min_player_distance cannot be negative")
	if hazard_layout.size() > 64:
		problems.append("hazard_layout has %d placements; expand mirrors instead of hand-listing" % hazard_layout.size())
	for placement in hazard_layout:
		if placement == null:
			problems.append("null HazardPlacement in hazard_layout")
			continue
		problems.append_array(placement.validate())
	return problems
