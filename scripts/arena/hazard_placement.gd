class_name HazardPlacement
extends Resource

## One hazard in an arena layout: which shared config, where, and (optionally) how it
## repeats. Lives in ArenaConfig.hazard_layout / HazardModeLayout.extra_placements.
##
## This is the shape WaveSpawnEntry established — a nested typed entry resource with its
## own validate() and duplicate_entry() — so authored layouts and any future procedural
## generator produce the same type and are validated identically. A placement carries ONE
## optional geometry tweak (radius) rather than a re-declaration of the config: gameplay
## numbers have exactly one home (docs/ARCHITECTURE.md, "Single source of tuning").

const MIRROR_NONE := &"none"
const MIRROR_X := &"x"              ## plus the copy at (-x, z)
const MIRROR_Z := &"z"              ## plus the copy at (x, -z)
const MIRROR_BOTH := &"both"        ## all four quadrants
const MIRROR_ROT180 := &"rot180"    ## plus the point-symmetric copy at (-x, -z)
const VALID_MIRRORS := [MIRROR_NONE, MIRROR_X, MIRROR_Z, MIRROR_BOTH, MIRROR_ROT180]

@export var config: HazardConfig = null
## Authored centre in arena-local metres (XZ only — hazard math ignores Y).
@export var position: Vector3 = Vector3.ZERO
## Radial symmetry to apply while building the layout. The authored arenas are 4-fold
## symmetric, so this turns eleven lines of coordinates into six readable placements.
@export var mirror: StringName = MIRROR_NONE
## 0 = inherit the config radius; > 0 overrides it for this placement (visual included).
@export_range(0.0, 12.0, 0.05) var radius_override: float = 0.0
## Fraction of the period the burst timer starts part-way through, so a row of vents
## does not fire in lockstep. 0 = every placement of this kind fires together.
@export_range(0.0, 1.0, 0.01) var phase_jitter: float = 1.0


func effective_radius() -> float:
	return radius_override if radius_override > 0.0 else (config.radius if config != null else 0.0)


func jittered_period() -> float:
	return config.period if config != null else 0.0


## Positions this single authored line expands to, in a stable order.
func mirrored_positions() -> Array[Vector3]:
	var out: Array[Vector3] = [position]
	var flipped_x := Vector3(-position.x, position.y, position.z)
	var flipped_z := Vector3(position.x, position.y, -position.z)
	match mirror:
		MIRROR_X:
			out.append(flipped_x)
		MIRROR_Z:
			out.append(flipped_z)
		MIRROR_ROT180:
			out.append(Vector3(-position.x, position.y, -position.z))
		MIRROR_BOTH:
			out.append(flipped_x)
			out.append(flipped_z)
			out.append(Vector3(-position.x, position.y, -position.z))
	return out


func validate() -> Array[String]:
	var problems: Array[String] = []
	if config == null:
		problems.append("HazardPlacement has no config (a placement must reference a res://data/hazards/*.tres)")
	if mirror not in VALID_MIRRORS:
		problems.append("HazardPlacement mirror must be none, x, z, both or rot180")
	if radius_override > 0.0 and config != null and radius_override > config.radius * 3.0:
		problems.append("HazardPlacement radius_override is more than triple the authored radius")
	if not is_finite(position.x) or not is_finite(position.z):
		problems.append("HazardPlacement position must be finite")
	if config != null and config.moves() and mirror == MIRROR_X:
		problems.append("HazardPlacement: an orbiting hazard mirrors onto its own orbit path (use none)")
	return problems


func duplicate_entry() -> HazardPlacement:
	var copy := HazardPlacement.new()
	copy.config = config
	copy.position = position
	copy.mirror = mirror
	copy.radius_override = radius_override
	copy.phase_jitter = phase_jitter
	return copy
