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
##
## The arena's *world* is authored here too — `theme`, `landmark`, `obstacle_layout` —
## because those three used to be code that branched on the arena id (`Arena.THEMES`,
## `PANORAMA_SKIES`, `ArenaObstacles.layout_for`), which made "drop in a scene + a .tres"
## a lie: the .tres decided gameplay and the code decided how the arena looked and what
## stood in it. They are hard resource references, not ids, so there is no table to keep
## in sync with the folder and a renamed theme is an editor load error. `theme == null` is
## the one deliberate case: the scene keeps its authored look (greybox and preview scenes).

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
## Sky, sun, fog, tone map and surface tints. Null keeps the scene's own look; a theme with
## a bad colour or an unreadable panorama is refused at load rather than rendering black.
@export var theme: ArenaThemeConfig = null
## What stands in the middle of the floor. Null means nothing stands there — no body, no
## blocker, no silently-built obelisk.
@export var landmark: ArenaLandmarkConfig = null
## Pillars and rubble, authored in this arena's metres (not scaled from another arena's
## pattern). Each placement expands its own mirror, like the hazards above; the expanded set
## is what becomes collision, mesh and nav blockers together. Absence is a choice, and the
## choice is documented on ArenaObstacles.fallback_layout.
@export var obstacle_layout: Array[ArenaObstaclePlacement] = []


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
	if obstacle_layout.size() > 64:
		problems.append("obstacle_layout has %d placements; expand mirrors instead of hand-listing" % obstacle_layout.size())
	for ob in obstacle_layout:
		if ob == null:
			problems.append("null ArenaObstaclePlacement in obstacle_layout")
			continue
		problems.append_array(ob.validate())
	if theme != null:
		problems.append_array(theme.validate())
	if landmark != null:
		problems.append_array(landmark.validate())
		problems.append_array(_obstacle_landmark_overlap(landmark))
	return problems


## The cross-check neither half can make alone: an obstacle authored inside the landmark's
## footprint is invisible (it is inside the centrepiece), still solid, and double-blocks the
## nav grid — so the AI routes around a wall that is not drawn. Shipped layouts keep clear of
## it; a designer copying a coordinate from the middle outward gets told at load.
func _obstacle_landmark_overlap(cfg: ArenaLandmarkConfig) -> Array[String]:
	var problems: Array[String] = []
	var half := cfg.footprint_half * cfg.scale
	for ob in obstacle_layout:
		if ob == null:
			continue
		for at in ob.mirrored_positions():
			if absf(at.x - cfg.position.x) < half.x + 0.25 \
					and absf(at.z - cfg.position.z) < half.z + 0.25:
				problems.append("obstacle at (%s, %s) is buried in the landmark footprint" % [str(at.x), str(at.z)])
	return problems
