class_name SpatialAttenuation
extends RefCounted

## Pure distance / rolloff math for world SFX. Godot's AudioStreamPlayer3D still
## performs the DSP attenuation; this module is the *pre-claim* gate so far-away
## enemy hits never occupy a spatial voice, plus a headless-testable model of
## the same curves used to size unit_size / max_distance.
##
## Models follow the common middleware set (inverse, inverse-square, linear,
## logarithmic). Gains are linear [0, 1]; dB conversion is 20*log10.

const MODEL_INVERSE := 0
const MODEL_INVERSE_SQUARE := 1
const MODEL_LINEAR := 2
const MODEL_LOG := 3

const DEFAULT_UNIT_SIZE := 8.0
const DEFAULT_MAX_DISTANCE := 42.0
## Slightly past max_distance so a voice that is *just* inside still plays;
## past this the claim is dropped before a player is taken.
const CULL_DISTANCE := 48.0
const MIN_GAIN := 0.0001
const SILENCE_DB := -80.0
const OCCLUSION_MAX_DB := 12.0

const MODEL_NAMES := {
	MODEL_INVERSE: &"inverse",
	MODEL_INVERSE_SQUARE: &"inverse_square",
	MODEL_LINEAR: &"linear",
	MODEL_LOG: &"log",
}


static func clamp_unit_size(unit_size: float) -> float:
	if not is_finite(unit_size) or unit_size <= 0.0:
		return DEFAULT_UNIT_SIZE
	return clampf(unit_size, 0.5, 64.0)


static func clamp_max_distance(max_distance: float) -> float:
	if not is_finite(max_distance) or max_distance <= 0.0:
		return DEFAULT_MAX_DISTANCE
	return clampf(max_distance, 2.0, 256.0)


static func clamp_distance(distance: float) -> float:
	if not is_finite(distance) or distance < 0.0:
		return 0.0
	return distance


static func is_valid_model(model: int) -> bool:
	return model >= MODEL_INVERSE and model <= MODEL_LOG


static func model_name(model: int) -> StringName:
	return MODEL_NAMES.get(model, &"inverse")


static func model_from_name(name: StringName) -> int:
	match name:
		&"inverse_square":
			return MODEL_INVERSE_SQUARE
		&"linear":
			return MODEL_LINEAR
		&"log":
			return MODEL_LOG
		_:
			return MODEL_INVERSE


## Flat (XZ) distance — vertical difference is ignored so a flying tell and a
## grounded grunt at the same arena cell share a voice budget.
static func distance_flat(from: Vector3, to: Vector3) -> float:
	var dx := to.x - from.x
	var dz := to.z - from.z
	if not is_finite(dx) or not is_finite(dz):
		return INF
	return sqrt(dx * dx + dz * dz)


static func should_cull(distance: float, max_distance: float = DEFAULT_MAX_DISTANCE) -> bool:
	var d := clamp_distance(distance)
	var cap := clamp_max_distance(max_distance)
	var cull_at := maxf(cap, CULL_DISTANCE)
	return d >= cull_at


## Linear gain in [MIN_GAIN, 1] for `distance` metres.
static func gain(
		distance: float,
		unit_size: float = DEFAULT_UNIT_SIZE,
		max_distance: float = DEFAULT_MAX_DISTANCE,
		model: int = MODEL_INVERSE
) -> float:
	var d := clamp_distance(distance)
	var unit := clamp_unit_size(unit_size)
	var cap := clamp_max_distance(max_distance)
	if d >= cap:
		return 0.0
	if d <= 0.0001:
		return 1.0
	if not is_valid_model(model):
		model = MODEL_INVERSE
	var raw := 1.0
	match model:
		MODEL_INVERSE:
			raw = unit / (unit + d)
		MODEL_INVERSE_SQUARE:
			var denom := unit + d
			raw = (unit * unit) / (denom * denom)
		MODEL_LINEAR:
			raw = 1.0 - d / cap
		MODEL_LOG:
			# log2(1 + d/unit) grows slowly; invert and floor at the cap.
			var at_cap := log(1.0 + cap / unit) / log(2.0)
			var at_d := log(1.0 + d / unit) / log(2.0)
			raw = 1.0 - at_d / maxf(at_cap, 0.0001)
	return clampf(raw, 0.0, 1.0)


static func db_from_gain(linear_gain: float) -> float:
	if not is_finite(linear_gain) or linear_gain <= MIN_GAIN:
		return SILENCE_DB
	return clampf(linear_to_db(linear_gain), SILENCE_DB, 0.0)


static func gain_from_db(db: float) -> float:
	if not is_finite(db) or db <= SILENCE_DB:
		return 0.0
	return clampf(db_to_linear(db), 0.0, 1.0)


## Extra muffling for an occluded emitter. `occlusion_01` 0 = clear, 1 = fully
## blocked. Applied as a dB cut (not a hard mute) so the player still hears
## that *something* happened on the other side of a pillar.
static func occluded_db(base_db: float, occlusion_01: float) -> float:
	var occ := clampf(occlusion_01, 0.0, 1.0) if is_finite(occlusion_01) else 0.0
	var db := base_db if is_finite(base_db) else 0.0
	return clampf(db - occ * OCCLUSION_MAX_DB, SILENCE_DB, 6.0)


static func occluded_gain(linear_gain: float, occlusion_01: float) -> float:
	return gain_from_db(occluded_db(db_from_gain(linear_gain), occlusion_01))


## Combined pre-claim: cull, then inverse-distance gain, then optional occlusion.
static func hearable_gain(
		listener: Vector3,
		emitter: Vector3,
		occlusion_01: float = 0.0,
		unit_size: float = DEFAULT_UNIT_SIZE,
		max_distance: float = DEFAULT_MAX_DISTANCE,
		model: int = MODEL_INVERSE
) -> float:
	var d := distance_flat(listener, emitter)
	if should_cull(d, max_distance):
		return 0.0
	return occluded_gain(gain(d, unit_size, max_distance, model), occlusion_01)


static func hearable_db(
		listener: Vector3,
		emitter: Vector3,
		occlusion_01: float = 0.0,
		unit_size: float = DEFAULT_UNIT_SIZE,
		max_distance: float = DEFAULT_MAX_DISTANCE,
		model: int = MODEL_INVERSE
) -> float:
	return db_from_gain(hearable_gain(listener, emitter, occlusion_01, unit_size, max_distance, model))


## True when the emitter is close enough to spend a voice.
static func is_hearable(
		listener: Vector3,
		emitter: Vector3,
		max_distance: float = DEFAULT_MAX_DISTANCE
) -> bool:
	return not should_cull(distance_flat(listener, emitter), max_distance)
