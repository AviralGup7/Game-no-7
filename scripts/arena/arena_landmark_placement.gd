class_name ArenaLandmarkPlacement
extends Resource

## One centrepiece in the merged dungeon's wings: which shared landmark config, and where.
## Lives in `ArenaConfig.extra_landmarks`.
##
## This is the shape `HazardPlacement` / `ArenaObstaclePlacement` already established — a
## nested typed entry with its own validate() — so a wing landmark's *look* (kind, colours,
## light, footprint) has exactly one home (`data/arena_landmarks/*.tres`) while its *position*
## is the arena's to author. Without this split, placing the same forge in two different rooms
## would mean duplicating the whole config resource (and its tuning) once per room.

## The shared landmark definition. Null means "authored nothing here" and is refused at load.
@export var config: ArenaLandmarkConfig = null
## Where the centrepiece stands, in arena-local metres (XZ; Y is ignored — the landmark sits
## on the floor).
@export var position: Vector3 = Vector3.ZERO


func validate() -> Array[String]:
	var problems: Array[String] = []
	if config == null:
		problems.append("ArenaLandmarkPlacement has no config (a placement must reference a res://data/arena_landmarks/*.tres)")
	if not is_finite(position.x) or not is_finite(position.z):
		problems.append("ArenaLandmarkPlacement position must be finite")
	return problems
