class_name Minimap
extends Control

## Circular arena radar (v2, threat-aware).
##
## Rebuilt from the base up (see docs/MINIMAP_RADAR.md for the research log).
## What changed vs v1:
##   * v1 re-sampled groups at 15 Hz and snapped dots to their new spot, so
##     every track stepped ~0.5 m per refresh. v2 keeps a per-entity display
##     position that eases toward the truth with frame-rate-independent
##     exponential smoothing: `pos += (target - pos) * (1 - exp(-rate*dt))`
##     (the same first-order smoothing the camera uses via CameraMath.exp_weight).
##   * Discovery (the only expensive part: group queries) still runs at 15 Hz;
##     the canvas animates every frame, but only issues queue_redraw() when
##     something actually moved (tracks easing, pings, fades, player motion,
##     boss danger pulse) — an idle radar costs nothing.
##   * New enemies spawn a short expanding "spotted" ring (the standard radar
##     ping used by tactical shooters when a target comes into view); killed
##     enemies fade out instead of popping.
##   * The player wedge is drawn instantly (never lagged) with a facing cone
##     showing where you are looking, north-up orientation (stable mental map;
##     pros keep the radar fixed and read orientation from the player icon).
##   * Nearest enemy gets a white emphasis ring; while a boss is alive the rim
##     pulses red (danger state) and the boss dot grows a halo.
##   * Pickups blink during the last quarter of their lifetime so expiring
##     rewards read as urgent.
##
## The projection + tracking core is pure and static (no tree required) and is
## unit-tested headlessly in tests/unit/test_minimap_radar.gd. Rendering stays
## in this Control. Public API v1 pins preserved: `project_to_map` semantics
## (centre + clamp-to-rim), `arena_half`, 140x140 custom minimum size.

const PLAYER_GROUP := "player"

## Easing rate (1/s) for track display positions toward their true position.
const TRACK_RATE := 8.0
## Seconds a removed entity stays visible while fading out.
const TRACK_FADE_SECONDS := 0.35
## Milliseconds a new enemy's spawn ping ring is visible.
const SPAWN_PING_MS := 1200
## Hard cap on tracked slots (bounds memory in pathological waves).
const MAX_TRACKS := 96
## Group re-query cadence (seconds). Smoothing itself runs every frame.
const DISCOVERY_INTERVAL := 1.0 / 15.0
## Player facing cone (half of the total arc, degrees) and its world range.
const FOV_CONE_HALF_DEGREES := 35.0
const FOV_CONE_RANGE := 10.0
## Rim pulse cadence while a boss is alive.
const DANGER_PULSE_HZ := 1.4
## Pickup urgency kicks in during the final quarter of its lifetime.
const PICKUP_BLINK_FRACTION := 0.75
## Redraw epsilon: a track counts as "still moving" until its display position
## is within this many world metres of the truth.
const TRACK_SETTLE_EPSILON := 0.03

@export var arena_half := 12.0

var _cached_arena: Arena = null
var _cached_half := 12.0
var _discovery_acc := DISCOVERY_INTERVAL
var _player: Node3D = null
var _boss_live := false
var _live: Array = []
var _live_xz: Dictionary = {}  # id -> Vector2 (last discovered truth)
var _tracks: Dictionary = {}   # id -> {pos, alpha, born_ms, kind, blink}
var _nearest_id := -1
var _last_player_px := Vector2.ZERO
var _last_facing := Vector2.ZERO
var _dirty := true


func _ready() -> void:
	custom_minimum_size = Vector2(140, 140)
	mouse_filter = MOUSE_FILTER_IGNORE
	_cached_half = _safe_half(arena_half)


# ---------------------------------------------------------------------------
# Pure, headless-testable core
# ---------------------------------------------------------------------------

## Project a world XZ offset (relative to arena centre) onto map pixels,
## clamping out-of-range points to the rim so nothing draws outside the disc.
## NOTE: pinned by tests/unit/test_meta_misc.gd — keep semantics exact.
static func project_to_map(world_xz: Vector2, center_px: Vector2, radius_px: float, half: float) -> Vector2:
	if not is_finite(world_xz.x) or not is_finite(world_xz.y):
		return center_px
	if half <= 0.0 or radius_px <= 0.0:
		return center_px
	var offset := world_xz / half
	var mag := offset.length()
	if mag > 1.0:
		offset /= mag
	return center_px + offset * radius_px

## Frame-rate-independent exponential step toward `target` (Lisyarus's
## canonical smoothing; identical family to CameraMath.exp_weight). Returns
## `current` for non-positive delta, `target` when rate <= 0 (hard follow),
## and never propagates NaN.
static func track_position(current: Vector2, target: Vector2, delta: float, rate: float) -> Vector2:
	if not (is_finite(target.x) and is_finite(target.y)):
		return current if (is_finite(current.x) and is_finite(current.y)) else Vector2.ZERO
	if not (is_finite(current.x) and is_finite(current.y)):
		return target
	if delta <= 0.0:
		return current
	if rate <= 0.0:
		return target
	var w := 1.0 - exp(-maxf(rate, 0.0) * delta)
	return current.lerp(target, clampf(w, 0.0, 1.0))

## 0..1 progress of a spawn ping ring; 1.0 (done) for bad durations.
static func ping_progress(elapsed_ms: int, duration_ms: int) -> float:
	if duration_ms <= 0:
		return 1.0
	return clampf(float(elapsed_ms) / float(duration_ms), 0.0, 1.0)

## Pickup urgency pulse: 1.0 when `urgency <= 0`, else oscillates 0.35..1.0
## at 2.5 Hz (deterministic in `phase_ms`, so tests can pin exact values).
static func blink_alpha(urgency: float, phase_ms: int) -> float:
	if urgency <= 0.0 or not is_finite(urgency):
		return 1.0
	var s := sin(TAU * 2.5 * (float(phase_ms) / 1000.0))
	return 0.675 + 0.325 * s

## Triangle for the player wedge: a tip `length` px along `facing` and two
## base corners swept back by `spread` radians (radians). Degenerate-safe.
static func wedge_points(center: Vector2, facing: Vector2, length: float, spread: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var dir := facing if facing.length_squared() > 0.001 else Vector2.UP
	dir = dir.normalized()
	if not (is_finite(dir.x) and is_finite(dir.y)):
		dir = Vector2.UP
	length = clampf(length, 0.0, 96.0)
	spread = clampf(spread, 0.02, 1.2)
	pts.append(center + dir * length)
	pts.append(center + dir.rotated(spread) * length * 0.42)
	pts.append(center + dir.rotated(-spread) * length * 0.42)
	return pts

## Pure track state machine: advance previous tracks one step against the
## freshly discovered `live` list and return the next table.
##
## `live` entries: {"id": int, "xz": Vector2, "kind": StringName, "blink": float}
## Returned table: id -> {"pos": Vector2 (world XZ display pos), "alpha": float,
##   "born_ms": int, "kind": StringName, "blink": float}
## Rules (all deterministic):
##   * live entity with a track  -> pos eases toward truth, alpha restores to 1
##   * live entity without track -> spawns at truth instantly, born_ms = now
##   * stale track (entity gone) -> alpha -= dt/fade_seconds, holds last pos
##   * non-finite truth, bad id  -> entity ignored
##   * more than `cap` slots     -> evict stalest (alpha<1) first, then oldest
static func advance_tracks(
	previous: Dictionary,
	live: Array,
	delta: float,
	now_ms: int,
	tr_rate: float = TRACK_RATE,
	fade_seconds: float = TRACK_FADE_SECONDS,
	cap: int = MAX_TRACKS
) -> Dictionary:
	var next: Dictionary = {}
	var seen: Dictionary = {}
	for entry in live:
		if not (entry is Dictionary):
			continue
		var id := int((entry as Dictionary).get("id", -1))
		if id <= 0:
			continue
		var xz := Vector2((entry as Dictionary).get("xz", Vector2(INF, INF)))
		if not (is_finite(xz.x) and is_finite(xz.y)):
			continue
		var kind := StringName(String((entry as Dictionary).get("kind", "enemy")))
		var blink := clampf(float((entry as Dictionary).get("blink", 0.0)), 0.0, 1.0)
		if seen.has(id):
			continue
		seen[id] = true
		if previous.has(id):
			var prev: Dictionary = (previous as Dictionary)[id]
			next[id] = {
				"pos": track_position(Vector2(prev.get("pos", xz)), xz, delta, tr_rate),
				"alpha": 1.0,
				"born_ms": int(prev.get("born_ms", now_ms)),
				"kind": kind,
				"blink": blink,
			}
		else:
			next[id] = {"pos": xz, "alpha": 1.0, "born_ms": now_ms, "kind": kind, "blink": blink}
	# Fade out tracks whose entity vanished; they hold their last seen spot.
	for id in (previous as Dictionary).keys():
		if seen.has(id):
			continue
		var prev: Dictionary = (previous as Dictionary)[id]
		var a := float(prev.get("alpha", 1.0)) - delta / maxf(fade_seconds, 0.0001)
		if a <= 0.0:
			continue
		next[id] = {
			"pos": Vector2(prev.get("pos", Vector2.ZERO)),
			"alpha": a,
			"born_ms": int(prev.get("born_ms", now_ms)),
			"kind": StringName(String(prev.get("kind", "enemy"))),
			"blink": 0.0,
		}
	while (next as Dictionary).size() > cap:
		var victim := -1
		var victim_score := INF
		for id in (next as Dictionary).keys():
			var t: Dictionary = (next as Dictionary)[id]
			var stale_bonus := 0.0 if float(t.get("alpha", 1.0)) < 1.0 else 1.0e9
			var score := float(int(t.get("born_ms", 0))) + stale_bonus
			if score < victim_score:
				victim_score = score
				victim = id
		if victim < 0:
			break
		(next as Dictionary).erase(victim)
	return next


# ---------------------------------------------------------------------------
# Node behaviour
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not is_finite(delta) or delta < 0.0:
		delta = 0.016
	var discovered := false
	_discovery_acc += delta
	if _discovery_acc >= DISCOVERY_INTERVAL:
		_discovery_acc = 0.0
		_discover()
		discovered = true

	var now_ms := Time.get_ticks_msec()
	_tracks = advance_tracks(_tracks, _live, delta, now_ms)

	if _dirty or _animating(now_ms):
		queue_redraw()
		_dirty = false
		_cache_player()  # remembers painted player pos/facing for next frame's motion test


func _cache_player() -> void:
	var c := size * 0.5
	var r := _map_radius()
	if _player == null or not is_instance_valid(_player):
		_last_player_px = Vector2.ZERO
		_last_facing = Vector2.ZERO
		return
	var xz := _finite_xz(_player.global_position.xz)
	_last_player_px = project_to_map(xz, c, r, _cached_half)
	_last_facing = _facing_2d()


## True while the canvas would paint something different than the last frame.
func _animating(now_ms: int) -> bool:
	if _boss_live:
		return true  # danger pulse runs continuously
	if _player != null and is_instance_valid(_player):
		var c := size * 0.5
		var r := _map_radius()
		var xz := _finite_xz(_player.global_position.xz)
		var px := project_to_map(xz, c, r, _cached_half)
		if px.distance_squared_to(_last_player_px) > 0.25:
			return true
		if _facing_2d().angle_to(_last_facing) > 0.02:
			return true
	for id in _tracks.keys():
		var t: Dictionary = _tracks[id]
		if float(t.get("alpha", 1.0)) < 1.0:
			return true  # fading out
		if ping_progress(now_ms - int(t.get("born_ms", now_ms)), SPAWN_PING_MS) < 1.0:
			return true  # spawn ping still expanding
		if _live_xz.has(id):
			var truth: Vector2 = _live_xz[id]
			if Vector2(t.get("pos", truth)).distance_squared_to(truth) > TRACK_SETTLE_EPSILON * TRACK_SETTLE_EPSILON:
				return true  # still easing
	return false


func _discover() -> void:
	if _cached_arena == null or not is_instance_valid(_cached_arena):
		_cached_arena = _find_arena()
	if _cached_arena != null and is_instance_valid(_cached_arena):
		_cached_half = _safe_half(_cached_arena.get_interior_half())
	else:
		_cached_half = _safe_half(arena_half)
	var tree := get_tree()
	var pn := tree.get_first_node_in_group(PLAYER_GROUP)
	_player = pn if (pn is Node3D and is_instance_valid(pn)) else null
	_boss_live = tree.has_any_node_in_group(BossController.BOSS_GROUP)

	var fresh: Array = []
	var fresh_xz: Dictionary = {}
	for e in tree.get_nodes_in_group(EnemyBase.TARGET_GROUP):
		if not (e is EnemyBase) or not is_instance_valid(e):
			continue
		var xz := (e as EnemyBase).global_position.xz
		if not (is_finite(xz.x) and is_finite(xz.y)):
			continue
		var kind := &"enemy"
		if e.is_in_group(BossController.BOSS_GROUP):
			kind = &"boss"
		elif (e as EnemyBase).is_elite():
			kind = &"elite"
		fresh.append({"id": e.get_instance_id(), "xz": xz, "kind": kind, "blink": 0.0})
		fresh_xz[e.get_instance_id()] = xz
	for p in tree.get_nodes_in_group(Pickup.PICKUP_GROUP):
		if not (p is Pickup) or not is_instance_valid(p) or not (p as Pickup).is_active():
			continue
		var xz := (p as Pickup).global_position.xz
		if not (is_finite(xz.x) and is_finite(xz.y)):
			continue
		var urgency := 0.0
		var cfg := (p as Pickup).config
		if cfg != null and cfg.lifetime > 0.0:
			urgency = 1.0 if (p as Pickup).age() >= cfg.lifetime * PICKUP_BLINK_FRACTION else 0.0
		fresh.append({"id": p.get_instance_id(), "xz": xz, "kind": &"pickup", "blink": urgency})
		fresh_xz[p.get_instance_id()] = xz

	# Deep value compare: only repaint at discovery cadence if the roster
	# actually changed (a fully idle arena stays idle on the canvas too).
	var changed := fresh != _live
	_live = fresh
	_live_xz = fresh_xz
	if changed:
		_dirty = true


## Resolve the live arena layout-independently (audit "fragile hardcoded path"):
## the Arena joins `Arena.ARENA_GROUP` in its _ready, so the group lookup works
## no matter which scene roots the UI or what the arena node is named. The
## legacy "WorldRoot/Arena" path off current_scene stays as a fallback for
## authored scenes whose arena predates the group contract; no arena (UI tests)
## keeps the default arena_half.
func _find_arena() -> Arena:
	var arena := get_tree().get_first_node_in_group(Arena.ARENA_GROUP) as Arena
	if arena != null:
		return arena
	var cs := get_tree().current_scene
	return cs.get_node_or_null("WorldRoot/Arena") as Arena if cs != null else null


func _safe_half(v: float) -> float:
	return v if (is_finite(v) and v > 0.0) else 12.0


func _map_radius() -> float:
	return maxf(minf(size.x, size.y) * 0.48, 8.0)


## Map-space facing: world forward is -Z (Godot convention), and the projection
## keeps +X/+Z axis-aligned, so screen facing = (-basis.z.x, -basis.z.z).
func _facing_2d() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return Vector2.UP
	var f := _player.global_transform.basis.z
	var v := Vector2(-f.x, -f.z)
	return v if v.length_squared() > 0.001 else Vector2.UP


func _finite_xz(v: Vector2) -> Vector2:
	return v if (is_finite(v.x) and is_finite(v.y)) else Vector2.ZERO


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _draw() -> void:
	var c := size * 0.5
	var r := _map_radius()
	var now_ms := Time.get_ticks_msec()

	# Disc + rim (cyan; red pulse while a boss is alive).
	draw_circle(c, r, Color(0.02, 0.05, 0.09, 0.92))
	var rim := Color(0.4, 0.75, 0.9, 0.9)
	if _boss_live:
		var pulse := 0.5 + 0.5 * sin(TAU * DANGER_PULSE_HZ * (float(now_ms) / 1000.0))
		rim = rim.lerp(Color(0.9, 0.25, 0.2, 1.0), 0.35 + 0.4 * pulse)
	draw_arc(c, r, 0.0, TAU, 48, rim, 2.0)
	# Range rings (quarter + 80% of arena radius).
	draw_arc(c, r * 0.45, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.07), 1.0)
	draw_arc(c, r * 0.8, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.10), 1.0)

	if _player == null or not is_instance_valid(_player):
		return
	var xz := _finite_xz(_player.global_position.xz)
	var pc := project_to_map(xz, c, r, _cached_half)
	var facing := _facing_2d()

	# Facing cone: where you are looking (north-up, so map angle = facing.angle()).
	var cone_r := minf(FOV_CONE_RANGE / _cached_half, 1.0) * r
	var half_a := FOV_CONE_HALF_DEGREES * DEG2RAD
	var a0 := facing.angle() - half_a
	var fan := PackedVector2Array([pc])
	for i in range(9):
		var a := a0 + (2.0 * half_a) * (float(i) / 8.0)
		fan.append(pc + Vector2(cos(a), sin(a)) * cone_r)
	draw_colored_polygon(fan, Color(0.5, 0.85, 1.0, 0.10))
	draw_arc(pc, cone_r, a0, a0 + 2.0 * half_a, 16, Color(0.5, 0.85, 1.0, 0.25), 1.0)

	# Player wedge: instant (never lagged), brighter than the cone.
	var wpts := wedge_points(pc, facing, 12.0, 0.45)
	draw_colored_polygon(wpts, Color(0.55, 0.9, 1.0, 0.95))
	draw_polyline(wpts, Color(0.9, 1.0, 1.0, 0.5), 1.0, true)

	# Nearest-enemy emphasis (world distance from player).
	_nearest_id = _nearest_threat_id(xz)

	# Tracks, ordered pickups -> enemies -> elites -> bosses so big dots win.
	var order := [&"pickup", &"enemy", &"elite", &"boss"]
	for kind_name in order:
		var kind := StringName(String(kind_name))
		for id in _tracks.keys():
			var t: Dictionary = _tracks[id]
			if StringName(String(t.get("kind", "enemy"))) != kind:
				continue
			var tpos := project_to_map(Vector2(t.get("pos", Vector2.ZERO)), c, r, _cached_half)
			var alpha := float(t.get("alpha", 1.0)) * blink_alpha(float(t.get("blink", 0.0)), now_ms)
			if alpha <= 0.01:
				continue
			match kind:
				&"pickup":
					draw_circle(tpos, 3.5, Color(0.5, 0.85, 1.0, 0.95 * alpha))
				&"elite":
					draw_circle(tpos, 6.0, Color(1.0, 0.7, 0.25, 0.95 * alpha))
					draw_arc(tpos, 8.5, 0.0, TAU, 24, Color(1.0, 0.8, 0.4, 0.5 * alpha), 1.5)
				&"boss":
					var halo := 0.25 + 0.3 * (0.5 + 0.5 * sin(TAU * DANGER_PULSE_HZ * (float(now_ms) / 1000.0)))
					draw_arc(tpos, 12.0, 0.0, TAU, 32, Color(0.8, 0.55, 1.0, halo), 2.0)
					draw_circle(tpos, 8.0, Color(0.8, 0.55, 1.0, 0.95 * alpha))
				_:
					var hot := int(id) == _nearest_id
					var dot := Color(1.0, 0.32, 0.25, 0.95 * alpha)
					draw_circle(tpos, 4.5, dot)
					if hot:
						draw_arc(tpos, 7.5, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.8 * alpha), 1.5)
			# Spawn ping for newly spotted non-pickup entities.
			if kind != &"pickup":
				var p := ping_progress(now_ms - int(t.get("born_ms", now_ms)), SPAWN_PING_MS)
				if p < 1.0:
					var pr := 4.0 + 16.0 * p
					draw_arc(tpos, pr, 0.0, TAU, 24,
						Color(1.0, 0.45, 0.35, 0.55 * (1.0 - p)), 1.5)


func _nearest_threat_id(player_xz: Vector2) -> int:
	var best := -1
	var best_d := INF
	for entry in _live:
		var kind := StringName(String((entry as Dictionary).get("kind", "enemy")))
		if kind == &"pickup":
			continue
		var d: Vector2 = (entry as Dictionary)["xz"]
		var dist := player_xz.distance_squared_to(d)
		if dist < best_d:
			best_d = dist
			best = int((entry as Dictionary)["id"])
	return best
