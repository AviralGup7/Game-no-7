class_name RngService
extends RefCounted

## Deterministic random-number streams for gameplay systems.
## Each gameplay concern (waves, drops, crits, cosmetics, AI jitter) owns an
## independent RandomNumberGenerator seeded from the run seed plus a stream salt,
## so rebalancing one system never perturbs another system's sequence.
## Pure and headless-testable: no autoload or tree access.

const STREAM_WAVES := 11
const STREAM_DROPS := 101
const STREAM_CRITS := 211
const STREAM_AI := 317
const STREAM_COSMETIC := 401
const STREAM_UPGRADES := 503
const STREAM_ARENA := 607
const STREAM_AUDIO := 701

var _streams: Dictionary = {}  # int salt -> RandomNumberGenerator
var _base_seed: int = 0


func _init(base_seed: int = 0) -> void:
	_base_seed = base_seed


## Seed (or re-seed) every known stream from the run seed. Idempotent.
func reseed(base_seed: int) -> void:
	_base_seed = base_seed
	for salt in _streams:
		(_streams[salt] as RandomNumberGenerator).seed = _mix(base_seed, int(salt))


func get_base_seed() -> int:
	return _base_seed


## Fetch (lazily creating) the generator for one stream salt.
func stream(salt: int) -> RandomNumberGenerator:
	if not _streams.has(salt):
		var rng := RandomNumberGenerator.new()
		rng.seed = _mix(_base_seed, salt)
		_streams[salt] = rng
	return _streams[salt]


func _mix(base_seed: int, salt: int) -> int:
	# SplitMix-style avalanche so adjacent salts produce unrelated sequences.
	var z: int = base_seed + (-7046029254386353131) + salt * (-4658895280553007687)
	z = (z ^ (z >> 30)) * (-4658895280553007687)
	z = (z ^ (z >> 27)) * (-7723594293327613461)
	z = z ^ (z >> 31)
	return z


# ---------------- Convenience rolls ----------------

func randf_range(salt: int, low: float, high: float) -> float:
	return stream(salt).randf_range(low, high)


func randi_range(salt: int, low: int, high: int) -> int:
	return stream(salt).randi_range(low, high)


## True with probability `probability` in [0,1]. The parameter is `probability`,
## not `chance`, because `chance()` is this class' own method.
func chance(salt: int, probability: float) -> bool:
	if probability <= 0.0:
		return false
	if probability >= 1.0:
		return true
	return stream(salt).randf() < probability


## Uniform pick from a non-empty array; returns null for an empty array.
func pick(salt: int, items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[stream(salt).randi_range(0, items.size() - 1)]


## Deterministic Fisher-Yates shuffle; returns a NEW array, input untouched.
func shuffled(salt: int, items: Array) -> Array:
	var out := items.duplicate()
	var rng := stream(salt)
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


## Random unit vector on the XZ plane.
func dir_xz(salt: int) -> Vector3:
	var a := stream(salt).randf_range(-PI, PI)
	return Vector3(cos(a), 0.0, sin(a))


## Random point inside a disc of radius `r` on the XZ plane (uniform density).
func point_in_disc(salt: int, r: float) -> Vector3:
	var a := stream(salt).randf_range(-PI, PI)
	var d := sqrt(stream(salt).randf()) * r
	return Vector3(cos(a) * d, 0.0, sin(a) * d)


## Gaussian-ish roll in [0,1] via averaged uniforms (n=3), for natural spread.
func bell(salt: int) -> float:
	var rng := stream(salt)
	return (rng.randf() + rng.randf() + rng.randf()) / 3.0


# ---------------- Static one-shot helpers ----------------

## Build a throwaway generator for pure static contexts (tests, planners).
static func make_generator(base_seed: int, salt: int) -> RandomNumberGenerator:
	if salt < 0:
		salt = 0
	if salt > 16384:
		salt = salt % 16384
	var svc := RngService.new(base_seed)
	return svc.stream(salt)


## Deterministic int in [low, high] without keeping a service around.
static func roll_range(base_seed: int, salt: int, low: int, high: int) -> int:
	return make_generator(base_seed, salt).randi_range(low, high)
