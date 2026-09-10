class_name SpawnPatterns
extends RefCounted

## Deterministic spawn-position patterns for the SpawnManager: rings, arcs,
## clusters, flanks, cross ambushes and boss gates. Every pattern is a pure
## function of (count, arena_half, seed, salt) so replays and tests reproduce
## exact positions. All points are clamped inside the arena with a wall margin.

const PATTERN_RING := &"ring"
const PATTERN_ARC := &"arc"
const PATTERN_CLUSTER := &"cluster"
const PATTERN_FLANK := &"flank"
const PATTERN_CROSS := &"cross"
const PATTERN_SCATTER := &"scatter"
const PATTERN_GATE := &"gate"       # single boss slot at the far edge
const ALL := [PATTERN_RING, PATTERN_ARC, PATTERN_CLUSTER, PATTERN_FLANK, PATTERN_CROSS, PATTERN_SCATTER]

const WALL_MARGIN := 1.5
const PLAYER_SAFE_RADIUS := 6.0  # spawns are pushed out of this radius


## Dispatch: positions for `count` spawns of a pattern.
static func positions_for(pattern: StringName, count: int, arena_half: float, player_pos: Vector3, rng_seed: int, salt: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	match pattern:
		PATTERN_RING:
			pts = ring(count, arena_half, rng_seed, salt)
		PATTERN_ARC:
			pts = arc(count, arena_half, player_pos, rng_seed, salt)
		PATTERN_CLUSTER:
			pts = cluster(count, arena_half, player_pos, rng_seed, salt)
		PATTERN_FLANK:
			pts = flank(count, arena_half, player_pos)
		PATTERN_CROSS:
			pts = cross(count, arena_half)
		PATTERN_GATE:
			pts = gate(arena_half, player_pos)
		_:
			pts = scatter(count, arena_half, rng_seed, salt)
	enforce_player_distance(pts, player_pos, arena_half)
	return pts


## Even ring around the arena centre.
static func ring(count: int, arena_half: float, rng_seed: int, salt: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var rng := RngService.make_generator(rng_seed, salt)
	var radius := (arena_half - WALL_MARGIN) * rng.randf_range(0.65, 0.95)
	var offset := rng.randf_range(-PI, PI)
	for i in range(count):
		var a := offset + TAU * float(i) / float(count)
		out.append(_clamp(Vector3(cos(a) * radius, 0, sin(a) * radius), arena_half))
	return out


## Arc facing the player (spawns converge from one side).
static func arc(count: int, arena_half: float, player_pos: Vector3, rng_seed: int, salt: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var rng := RngService.make_generator(rng_seed, salt)
	var away := -player_pos
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()
	var base_angle := atan2(away.x, away.z)
	var spread := deg_to_rad(rng.randf_range(90.0, 160.0))
	var radius := (arena_half - WALL_MARGIN) * rng.randf_range(0.8, 1.0)
	for i in range(count):
		var t := 0.0
		if count > 1:
			t = float(i) / float(count - 1) * 2.0 - 1.0
		var a := base_angle + t * spread * 0.5
		out.append(_clamp(Vector3(sin(a) * radius, 0, cos(a) * radius), arena_half))
	return out


## Tight cluster at a random edge point (ambush packs, splitters).
static func cluster(count: int, arena_half: float, player_pos: Vector3, rng_seed: int, salt: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var rng := RngService.make_generator(rng_seed, salt)
	var edge := ring(1, arena_half, rng_seed, salt + 999)[0]
	# Prefer the far side from the player.
	if edge.distance_to(player_pos) < arena_half:
		edge = -edge
	for i in range(count):
		var jitter := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
		out.append(_clamp(edge + jitter, arena_half))
	return out


## Two flank groups on opposite sides of the player.
static func flank(count: int, arena_half: float, player_pos: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var side := Vector3(-player_pos.z, 0, player_pos.x)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized() * (arena_half - WALL_MARGIN)
	for i in range(count):
		var s := 1.0 if i % 2 == 0 else -1.0
		# Truncated division is deliberate: enemies spawn in pairs sharing a lane.
		var along := (float(int(i / 2.0)) - float(int(count / 4.0))) * 1.6
		var p := side * s + Vector3(player_pos.x * 0.3, 0, along)
		out.append(_clamp(p, arena_half))
	return out


## Four-way cross through the centre (late-wave pressure).
static func cross(count: int, arena_half: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 0:
		return out
	var arms := [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
	var r := arena_half - WALL_MARGIN
	for i in range(count):
		var arm: Vector3 = arms[i % 4]
		var step := float(int(i / 4.0)) * 1.8  # 4 spawn arms; truncation groups them
		out.append(_clamp(arm * maxf(r - step, 2.0), arena_half))
	return out


## Uniform scatter (fallback / mixed waves).
static func scatter(count: int, arena_half: float, rng_seed: int, salt: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var rng := RngService.make_generator(rng_seed, salt)
	var r := arena_half - WALL_MARGIN
	for i in range(count):
		out.append(Vector3(rng.randf_range(-r, r), 0, rng.randf_range(-r, r)))
	return out


## Boss gate: far edge from the player, single slot.
static func gate(arena_half: float, player_pos: Vector3) -> Array[Vector3]:
	var away := -player_pos
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized() * (arena_half - WALL_MARGIN)
	return [_clamp(away, arena_half)]


## Push any point inside PLAYER_SAFE_RADIUS of the player out to the rim.
static func enforce_player_distance(pts: Array[Vector3], player_pos: Vector3, arena_half: float) -> void:
	for i in range(pts.size()):
		var flat := Vector2(pts[i].x - player_pos.x, pts[i].z - player_pos.z)
		if flat.length() < PLAYER_SAFE_RADIUS:
			var dir := flat.normalized() if flat.length() > 0.01 else Vector2.RIGHT
			var pushed := Vector3(player_pos.x + dir.x * PLAYER_SAFE_RADIUS, 0, player_pos.z + dir.y * PLAYER_SAFE_RADIUS)
			pts[i] = _clamp(pushed, arena_half)


static func _clamp(p: Vector3, arena_half: float) -> Vector3:
	var r := arena_half - WALL_MARGIN
	return Vector3(clampf(p.x, -r, r), 0.0, clampf(p.z, -r, r))


## Pick a pattern id deterministically for a wave (variety without repetition:
## avoids the previous pattern).
static func pattern_for_wave(wave: int, rng_seed: int, previous: StringName) -> StringName:
	var rng := RngService.make_generator(rng_seed, RngService.STREAM_WAVES + wave)
	var pool: Array = ALL.duplicate()
	pool.erase(previous)
	if pool.is_empty():
		return PATTERN_SCATTER
	return pool[rng.randi_range(0, pool.size() - 1)]
