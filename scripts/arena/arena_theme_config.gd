class_name ArenaThemeConfig
extends ValidatedConfig

## The look of one arena: sky, sun, fog, tone map and surface tints. Authored under
## res://data/arena_themes/ and referenced from ArenaConfig.theme.
##
## This used to be `const THEMES := { "ember_crucible": { "sun_color": Color(…), … }, … }`
## inside arena.gd, read as `preset.get("sun_energy", sun.light_energy)`. Three ways to fail,
## all silent: an arena id missing from the table got the scene's daylight look and nobody
## said so (`docs/EXTENDING.md` §3 promised "a new scene + a .tres"); a misspelt key fell back
## to a default colour; and the numbers that every arena shared — ambient energy, glow,
## fog-sky-affect, tone map — were welded into `_apply_sky_and_light`, so a "darker" arena was
## a code edit. Now: one typed resource per arena, validated at load, with every look number
## authored and none of them defaulted.
##
## Referenced by hard resource reference (not by id), so there is no table to keep in sync and
## a renamed theme is a load error in the editor rather than a missing entry at runtime.

@export var theme_id: StringName = &""
@export var display_name: String = ""

## Real-sky panorama (Poly Haven CC0 .hdr, see THIRD_PARTY_ASSETS.md). Empty, or a path that
## has not been imported on this device, falls back to the procedural colours below — that
## fallback is the reason the colours are authored even when a panorama is.
@export_file("*.hdr") var panorama_path: String = ""
@export var sky_top: Color = Color(0.36, 0.6, 0.85)
@export var sky_horizon: Color = Color(0.72, 0.8, 0.9)
@export var ground_horizon: Color = Color(0.55, 0.6, 0.66)

## Sun. `sun_energy` multiplies the DirectionalLight3D the scene authors; 0 disables it
## (a panorama-lit arena can run on IBL alone).
@export var sun_color: Color = Color(1.0, 0.92, 0.78)
@export_range(0.0, 5.0, 0.05) var sun_energy: float = 1.2

## Ambient push from the sky. PanoramaSkyMaterial has no energy knob in 4.4 (its one
## meaningful property is the panorama), so `ambient_energy` is the exposure handle for an
## HDRI-lit arena, together with `brightness`. Note that the scene keeps
## `ambient_light_sky_contribution` at its default 1.0, so with AMBIENT_SOURCE_SKY the sky
## drives the ambient term and `ambient_color` tints rather than replaces it — which is why
## the shipped themes lean on energy and tone map for their mood, not on this colour.
@export var ambient_color: Color = Color(0.62, 0.68, 0.75)
@export_range(0.0, 4.0, 0.05) var ambient_energy: float = 0.85

## Distance fog: the arena's mood *and* its mobile fill-cost limiter (fog is per-pixel, cheap,
## and hides the short draw distance a phone wants).
@export var fog_color: Color = Color(0.7, 0.7, 0.7)
@export_range(0.0, 0.2, 0.001) var fog_density: float = 0.011
@export_range(0.0, 1.0, 0.01) var fog_sky_affect: float = 0.25

## Cinematic adjustment + emissive glow. Kept mobile-renderer-safe by range: no volumetrics,
## no SSR, and glow_bloom stays small enough to not wash out the readability palette
## (docs/ART_STYLE.md).
@export_range(0.2, 3.0, 0.01) var brightness: float = 1.02
@export_range(0.2, 3.0, 0.01) var contrast: float = 1.06
@export_range(0.0, 2.0, 0.01) var glow_intensity: float = 0.55
@export_range(0.0, 1.0, 0.01) var glow_bloom: float = 0.05
@export_range(0.05, 10.0, 0.05) var glow_hdr_threshold: float = 1.1

## Floor / wall tint. Applied through material_override, so the shared scene material is
## never mutated. The node identity is authored because the old code matched node *names*
## (`name == &"Floor"`, `String(name).begins_with("Wall")`): renaming a mesh in the editor
## silently stopped the tint from applying.
@export var tint_floor_and_walls: bool = true
@export var floor_node_path: NodePath = &"Geometry/Floor"
@export var wall_node_prefix: String = "Wall"
@export var floor_tint: Color = Color(0.66, 0.64, 0.6)
@export var wall_tint: Color = Color(0.72, 0.7, 0.68)

const COLOR_FIELDS := ["sky_top", "sky_horizon", "ground_horizon", "sun_color",
	"ambient_color", "fog_color", "floor_tint", "wall_tint"]


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(theme_id).is_empty():
		problems.append("theme_id is empty")
	elif not String(resource_path).is_empty() and String(theme_id) != resource_path.get_file().get_basename():
		problems.append("theme_id '%s' does not match the file name" % String(theme_id))
	for field in COLOR_FIELDS:
		var problems_for_color := _color_problems(get(field), field)
		if not problems_for_color.is_empty():
			problems.append_array(problems_for_color)
	if not panorama_path.is_empty() and not panorama_path.begins_with("res://"):
		problems.append("panorama_path must be a res:// path (a user:// or absolute path will not load in an export): %s" % panorama_path)
	if not panorama_path.is_empty() and not panorama_path.get_extension().to_lower() == "hdr":
		problems.append("panorama_path must name an .hdr: %s" % panorama_path)
	if fog_density > 0.12:
		# Readability rule, not a rendering one: past this the opposite side of a 24 m
		# arena disappears, and an arena you cannot see enemies cross is not playable.
		problems.append("fog_density %s would hide the far half of the arena (cap 0.12)" % str(fog_density))
	if sun_energy < 0.0:
		problems.append("sun_energy cannot be negative")
	if ambient_energy < 0.0:
		problems.append("ambient_energy cannot be negative")
	if tint_floor_and_walls and String(floor_node_path).is_empty():
		problems.append("tint_floor_and_walls is on but floor_node_path is empty (nothing to tint)")
	if tint_floor_and_walls and wall_node_prefix.is_empty():
		problems.append("tint_floor_and_walls is on but wall_node_prefix is empty; use tint_floor_and_walls = false to opt out")
	return problems


## A non-finite Color is not a look bug, it is a black-screen bug: it propagates into
## Environment and every material that reads it.
static func _color_problems(c: Color, field: String) -> Array[String]:
	var out: Array[String] = []
	if not (is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and is_finite(c.a)):
		out.append("%s has a non-finite channel" % field)
	elif c.r < 0.0 or c.g < 0.0 or c.b < 0.0 or c.a < 0.0:
		out.append("%s has a negative channel" % field)
	return out
