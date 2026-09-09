class_name ArenaLandmarkConfig
extends ValidatedConfig

## What stands in the middle of an arena, how big it is, what it is made of, and how it is
## lit. Authored under res://data/arena_landmarks/ and referenced from ArenaConfig.landmark.
##
## The identity of a landmark (a forge has a basin and a lava disc, a crystal cluster has
## three prisms, an obelisk has a shaft and a cap) is code — `ArenaLandmark` builds those
## silhouettes. Everything else about it used to be code too: which kind an arena got came
## from the `THEMES` dictionary, the shape was hard-coded per kind, and the `_:` arm of two
## `match` statements meant an unrecognised kind quietly built *an obelisk*. Now the kind is
## a validated id and the geometry, placement, colour and light are authored numbers.
##
## `footprint_half` is the one number with two jobs, which is the point: the collision body
## and the nav-grid blocker are derived from the same vector, so the AI's intent and the
## physics body cannot disagree — the same rule `HazardConfig.radius` follows for hazards.

## Which silhouette ArenaLandmark builds. Adding a kind means one arm in that builder *and*
## this list; the validator and the python suite require the two to agree, and an id outside
## the list is a startup error rather than a silent obelisk.
const KIND_OBELISK := &"obelisk"
const KIND_FORGE := &"forge"
const KIND_CRYSTAL := &"crystal"
const VALID_KINDS := [KIND_OBELISK, KIND_FORGE, KIND_CRYSTAL]

## Box (a shaft, a wall) or cylinder (a basin, a prism cluster). Both are built from
## footprint_half: box uses it as the half size, cylinder uses x/z as the radius and y as the
## half height. Two shapes cover the shipped silhouettes exactly, with no third convention to
## misread.
const SHAPE_BOX := &"box"
const SHAPE_CYLINDER := &"cylinder"
const VALID_SHAPES := [SHAPE_BOX, SHAPE_CYLINDER]

@export var landmark_id: StringName = &""
@export var kind: StringName = KIND_OBELISK
@export var shape: StringName = SHAPE_BOX
## XZ half-extent + half height. This is what the collision body is made from and what the
## nav grid blocks; the mesh silhouette is scaled to fit it (`ArenaLandmark` multiplies the
## authored proportions by it), so art and physics stay one number apart.
@export var footprint_half: Vector3 = Vector3(0.55, 2.3, 0.55)
## Authored centre in arena-local metres. Y is fixed at 0: a landmark stands on the floor,
## and a non-zero Y would make the footprint (which assumes the floor) lie about the body.
@export var position: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3.ZERO
## Multiplies the silhouette's proportions. Kept separate from footprint_half so a designer
## can nudge the visible bulk without moving the blocker the AI routes around — but the
## collision body follows the footprint, never the scale, so the two can be visually mismatched
## only inside the range this field allows.
@export_range(0.25, 4.0, 0.05) var scale: float = 1.0
## Photo-material tint for the body geometry (tint multiplies the photo albedo) and its
## roughness. Authored per landmark: a forge wants dark scorched rock, an obelisk pale stone.
@export var material_tint: Color = Color(0.6, 0.56, 0.5)
@export_range(0.0, 1.0, 0.01) var material_roughness: float = 0.78
@export var accent_color: Color = Color(0.85, 0.75, 0.45)
@export_range(0.0, 20.0, 0.05) var emissive_energy: float = 1.2
## Fill light carried by the landmark (the arena's one moving light besides the sun).
@export var light_color: Color = Color(1.0, 0.8, 0.5)
@export_range(0.0, 10.0, 0.05) var light_energy: float = 1.1
@export_range(0.0, 40.0, 0.1) var light_range: float = 6.0
## Height of the light above the landmark's footprint centre.
@export_range(0.0, 12.0, 0.05) var light_offset_y: float = 2.0


## Every Color export must be swept by validate(): one NaN channel in a material tint
## propagates into every mesh that reads it, which is a black landmark, not a wrong one.
const COLOR_FIELDS := ["material_tint", "accent_color", "light_color"]


## The blocker handed to ArenaNavGrid, in the same AABB form as the obstacles, grown from the
## authored footprint so the grid and the body describe one object.
func footprint() -> AABB:
	# Scaled, because ArenaLandmark puts `scale` on the holder, which scales the meshes AND
	# the body: a blocker that ignored it would leave the AI walking through a grown landmark.
	var half := footprint_half * scale
	return AABB(position - half, half * 2.0)


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(landmark_id).is_empty():
		problems.append("landmark_id is empty")
	elif not String(resource_path).is_empty() and String(landmark_id) != resource_path.get_file().get_basename():
		problems.append("landmark_id '%s' does not match the file name" % String(landmark_id))
	if kind not in VALID_KINDS:
		problems.append("unknown landmark kind '%s' — ArenaLandmark builds no silhouette for it" % String(kind))
	if shape not in VALID_SHAPES:
		problems.append("unknown landmark collision shape '%s'" % String(shape))
	if shape == SHAPE_CYLINDER and kind == KIND_OBELISK:
		problems.append("an obelisk is a box: a cylinder body would leave its corners walkable")
	if footprint_half.x <= 0.1 or footprint_half.z <= 0.1:
		problems.append("footprint_half.x/z must exceed 0.1 or the landmark is not an obstacle, it is scenery")
	if footprint_half.y <= 0.1 or footprint_half.y > 12.0:
		problems.append("footprint_half.y must be in (0.1, 12] (it is also the collision half-height)")
	if not (is_finite(footprint_half.x) and is_finite(footprint_half.y) and is_finite(footprint_half.z)):
		problems.append("footprint_half is not finite")
	if not is_finite(position.x) or not is_finite(position.z) or absf(position.y) > 0.01:
		problems.append("a landmark must sit on the floor (position.y 0) with finite x/z")
	for field in COLOR_FIELDS:
		var color_problems := _color_problems(get(field), field)
		if not color_problems.is_empty():
			problems.append_array(color_problems)
	if light_energy > 0.0 and light_range <= 0.5:
		problems.append("a light with energy needs a range above 0.5 m (energy with range 0 is invisible, not dim)")
	return problems


static func _color_problems(c: Color, field: String) -> Array[String]:
	var out: Array[String] = []
	if not (is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and is_finite(c.a)):
		out.append("%s has a non-finite channel" % field)
	elif c.r < 0.0 or c.g < 0.0 or c.b < 0.0 or c.a < 0.0:
		out.append("%s has a negative channel" % field)
	return out
