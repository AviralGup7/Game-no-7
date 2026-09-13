class_name CampaignContract
extends RefCounted

## THE AUTHORED-STATION CONTRACT — one typed home for the campaign's module
## dimensions, district ids, style ids and the interaction/mission/archetype kind
## lists that the Station Zero loader, world builder, map and HUD all read.
##
## Before this file the same values were retyped as bare literals across five
## campaign scripts: the 8 m gameplay module existed as `8.0` in
## `CampaignGeometry.MODULE`, again as `!= 8` and again as the alignment step
## `roundf(n / 8.0) * 8.0` in `CampaignDefinition`; the authored wall-module height
## `0.27` sat inline in the wall batcher; `&"hazard"` / `&"tech"` / `&"rusted"` /
## `&"military"` were written twice (once in `CampaignGeometry`, once in
## `CampaignWorld`); `"cache"` was written in four files and the district ids in
## three. Data validation could not see any of it — `tool/validate_campaign.py`
## only proves the JSON is internally consistent, so a renamed district or kind
## left some call sites matching while others silently kept the default.
##
## ---------------------------------------------------------------------------
## THE DELIBERATE DECISIONS (change one, and you must change the pinned test):
##
##   * `tests/python/test_regress_audit_cleanup.py` fails when a literal from any
##     family below reappears anywhere in `scripts/campaign/`, so this file is the
##     only place those values can be written. The same test pins every id and
##     kind here against `data/campaign/station_zero.json`, so the contract cannot
##     drift from the authored data in either direction.
##   * Style ids are authored-data keys, not a Godot enum: nothing serializes
##     them and the two district→style tables below are the whole policy, so they
##     stay StringNames and the lookup is a dictionary read. They are deliberately
##     not written as `match` arms at the use sites: an identifier in a GDScript
##     `match` pattern binds instead of comparing, which would make the constant a
##     catch-all.
##   * Interaction/mission/archetype kinds stay Strings because the loader compares
##     `row.kind` — a Variant read out of the parsed JSON — against a list.
##   * `WALL_MODULE_THICKNESS_M` has no GDScript reader. Audit finding 17 removed
##     the stretch that used it, so only `scenes/environment/wall*.tscn` still
##     carries the authored thickness; the pinned test asserts the constant equals
##     the shipped `BoxShape3D`, which keeps the two in step without inventing a
##     use for the value.
##   * Budgets deliberately do NOT live here. `max_active_enemies`,
##     `max_visible_sectors`, the 105 m visual cull and the streaming/flow-field
##     radii are performance budgets: each is authored in the JSON or named in the
##     system that enforces it, and the streaming owner is still moving them.
## ---------------------------------------------------------------------------

# ---- Authored module dimensions (mirrors data/campaign/station_zero.json) ----

## Gameplay module edge in metres. The JSON authors the same number as
## `module_size`, and every authored floor coordinate is a multiple of it.
const MODULE_SIZE_M := 8.0
## Navigation cell edge in metres, authored as `navigation_cell`; half a module.
const NAV_CELL_SIZE_M := 4.0
## Authored wall module height in metres (`wall.glb` plus its collision shape).
## `wall_batch()` divides a merged collision box's height by it to size the row.
const WALL_MODULE_HEIGHT_M := 0.27
## Authored wall module thickness in metres. See the decision note above.
const WALL_MODULE_THICKNESS_M := 0.05

# ---- District ids (data/campaign/station_zero.json `sectors[].id`) ----

const DISTRICT_DOCKS := &"docks"
const DISTRICT_TRANSIT := &"transit"
const DISTRICT_HYDROPONICS := &"hydroponics"
const DISTRICT_FOUNDRY := &"foundry"
const DISTRICT_CARGO := &"cargo"
const DISTRICT_REACTOR := &"reactor"
const DISTRICT_MEDBAY := &"medbay"
const DISTRICT_HABITAT := &"habitat"
const DISTRICT_SALVAGE := &"salvage"
const DISTRICT_ARCHIVE := &"archive"
const DISTRICT_COMMS := &"comms"
const DISTRICT_COMMAND := &"command"
## The district a campaign starts in, the one a sector lookup returns when an
## authored id is unknown, and the origin the world builder and its navigation
## check seed the first flow field from.
const DISTRICT_HOME := DISTRICT_DOCKS

# ---- Environment style ids (which shipped module scene a surface uses) ----

const STYLE_MILITARY := &"military"
const STYLE_HAZARD := &"hazard"
const STYLE_TECH := &"tech"
const STYLE_RUSTED := &"rusted"
## Ground plating: hazard around heat/cargo machinery, powered panels on transit,
## habitation and life support, military tread for every other district — which
## is also the default for a district this table does not name.
const FLOOR_STYLE_BY_DISTRICT := {
	DISTRICT_REACTOR: STYLE_HAZARD,
	DISTRICT_CARGO: STYLE_HAZARD,
	DISTRICT_FOUNDRY: STYLE_HAZARD,
	DISTRICT_SALVAGE: STYLE_HAZARD,
	DISTRICT_TRANSIT: STYLE_TECH,
	DISTRICT_HABITAT: STYLE_TECH,
	DISTRICT_MEDBAY: STYLE_TECH,
	DISTRICT_HYDROPONICS: STYLE_TECH,
}
## Wall theme per nearest district. It differs from the floor table on purpose:
## cargo walls read rusted while its floor stays hazard plating, and command
## shares the rusted wall set without inheriting a non-military floor.
const WALL_STYLE_BY_DISTRICT := {
	DISTRICT_REACTOR: STYLE_HAZARD,
	DISTRICT_FOUNDRY: STYLE_HAZARD,
	DISTRICT_TRANSIT: STYLE_TECH,
	DISTRICT_HABITAT: STYLE_TECH,
	DISTRICT_HYDROPONICS: STYLE_TECH,
	DISTRICT_MEDBAY: STYLE_TECH,
	DISTRICT_CARGO: STYLE_RUSTED,
	DISTRICT_COMMAND: STYLE_RUSTED,
	DISTRICT_SALVAGE: STYLE_RUSTED,
}


static func floor_style(district_id: StringName) -> StringName:
	return FLOOR_STYLE_BY_DISTRICT.get(district_id, STYLE_MILITARY)


static func wall_style(district_id: StringName) -> StringName:
	return WALL_STYLE_BY_DISTRICT.get(district_id, STYLE_MILITARY)


# ---- Authored kind lists (validated by CampaignDefinition, read by world/map/HUD) ----

## Interaction record kinds. `cache` is the only kind that can be resolved
## without a mission pointing at it, which is why the HUD, the station chart and
## the marker visibility rule all test for it.
const INTERACTION_TERMINAL := "terminal"
const INTERACTION_COLLECT := "collect"
const INTERACTION_EXTRACTION := "extraction"
const INTERACTION_CACHE := "cache"
const INTERACTION_KINDS: Array[String] = [
	INTERACTION_TERMINAL, INTERACTION_COLLECT, INTERACTION_EXTRACTION, INTERACTION_CACHE,
]
## Mission record kinds. The runtime dispatches on mission *targets* and
## *requires*, so these are validated in the authored data only.
const MISSION_INTERACT := "interact"
const MISSION_COLLECT := "collect"
const MISSION_CLEAR := "clear"
const MISSION_EXTRACT := "extract"
const MISSION_KINDS: Array[String] = [
	MISSION_INTERACT, MISSION_COLLECT, MISSION_CLEAR, MISSION_EXTRACT,
]
## Enemy archetype ids an encounter member may name. The commander archetype is
## the only one whose scene the campaign overrides (security_commander.tscn).
const ENCOUNTER_ARCHETYPES: Array[String] = [
	"basic", "fast", "heavy", "ranged", "dasher", "warlord",
]
const ENCOUNTER_COMMANDER := "warlord"
