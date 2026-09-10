extends RefCounted

## Headless unit tests for the minimap radar v2 pure core (projection,
## exponential track smoothing, spawn ping, blink pulse, wedge geometry and
## the advance_tracks state machine). No tree, no nodes — deterministic.

static func suite() -> Array:
	var results: Array = []

	# --- project_to_map: centre, rim clamp, degenerate + NaN safety (pinned
	# semantics shared with test_meta_misc.gd) ---
	var center := Vector2(70, 70)
	var p0 := Minimap.project_to_map(Vector2.ZERO, center, 60.0, 12.0)
	results.append({
		"name": "Minimap v2 projects centre to disc centre",
		"passed": p0.distance_squared_to(center) < 0.001,
		"why": str(p0),
	})
	var p_rim := Minimap.project_to_map(Vector2(100.0, 30.0), center, 60.0, 12.0)
	var rim_len := p_rim.distance_to(center)
	results.append({
		"name": "Minimap v2 clamps out-of-range points onto the rim",
		"passed": absf(rim_len - 60.0) < 0.001,
		"why": "dist=%f" % rim_len,
	})
	var p_nan := Minimap.project_to_map(Vector2(INF, 0.0), center, 60.0, 12.0)
	results.append({
		"name": "Minimap v2 NaN world point falls back to centre",
		"passed": p_nan.distance_squared_to(center) < 0.001,
		"why": str(p_nan),
	})
	var p_deg := Minimap.project_to_map(Vector2(1.0, 1.0), center, 0.0, 12.0)
	results.append({
		"name": "Minimap v2 degenerate radius/half falls back to centre",
		"passed": Minimap.project_to_map(Vector2(1, 1), center, 60.0, 0.0).distance_squared_to(center) < 0.001
			and p_deg.distance_squared_to(center) < 0.001,
		"why": "",
	})

	# --- track_position: frame-rate-independent exponential smoothing ---
	var a := Vector2(0.0, 0.0)
	var b := Vector2(10.0, 4.0)
	results.append({
		"name": "track_position zero delta is a no-op",
		"passed": Minimap.track_position(a, b, 0.0, 8.0) == a,
		"why": "",
	})
	results.append({
		"name": "track_position non-positive rate hard-follows target",
		"passed": Minimap.track_position(a, b, 0.1, 0.0) == b,
		"why": "",
	})
	var two_steps := Minimap.track_position(a, b, 0.1, 8.0)
	two_steps = Minimap.track_position(two_steps, b, 0.1, 8.0)
	var one_step := Minimap.track_position(a, b, 0.2, 8.0)
	results.append({
		"name": "track_position is frame-rate independent (2x0.1s == 1x0.2s)",
		"passed": two_steps.distance_squared_to(one_step) < 1.0e-6,
		"why": "two=%s one=%s" % [str(two_steps), str(one_step)],
	})
	var far := Minimap.track_position(a, b, 5.0, 8.0)
	results.append({
		"name": "track_position converges without overshoot",
		"passed": far.distance_squared_to(b) < 0.01 and far.length() <= b.length() + 1.0e-4,
		"why": str(far),
	})
	var nan_t := Minimap.track_position(Vector2(1.0, 1.0), Vector2(INF, 0.0), 0.1, 8.0)
	var nan_c := Minimap.track_position(Vector2(INF, 0.0), b, 0.1, 8.0)
	results.append({
		"name": "track_position never propagates NaN",
		"passed": is_finite(nan_t.x) and is_finite(nan_t.y)
			and is_finite(nan_c.x) and is_finite(nan_c.y),
		"why": "t=%s c=%s" % [str(nan_t), str(nan_c)],
	})
	# Midpoint sanity: half of the way in time should land between start/end.
	var mid := Minimap.track_position(a, b, 0.05, 8.0)
	results.append({
		"name": "track_position monotone toward target",
		"passed": mid.length() > a.length() and mid.distance_squared_to(b) > 0.0,
		"why": str(mid),
	})

	# --- ping_progress ---
	results.append({
		"name": "ping_progress 0 -> 0, half -> 0.5, over -> 1",
		"passed": Minimap.ping_progress(0, 1200) == 0.0
			and absf(Minimap.ping_progress(600, 1200) - 0.5) < 1.0e-6
			and Minimap.ping_progress(5000, 1200) == 1.0,
		"why": "",
	})
	results.append({
		"name": "ping_progress bad duration is done",
		"passed": Minimap.ping_progress(10, 0) == 1.0 and Minimap.ping_progress(10, -5) == 1.0,
		"why": "",
	})

	# --- blink_alpha ---
	results.append({
		"name": "blink_alpha idle pickups are steady at 1.0",
		"passed": Minimap.blink_alpha(0.0, 12345) == 1.0 and Minimap.blink_alpha(-1.0, 0) == 1.0,
		"why": "",
	})
	# phase 100ms -> sin(TAU*2.5*0.1) = sin(pi/2) = 1 -> 0.675+0.325 = 1.0
	var peak := Minimap.blink_alpha(1.0, 100)
	var trough := Minimap.blink_alpha(1.0, 300)
	results.append({
		"name": "blink_alpha pulses between 0.35 and 1.0 (deterministic phase)",
		"passed": absf(peak - 1.0) < 1.0e-4 and absf(trough - 0.35) < 1.0e-4,
		"why": "peak=%f trough=%f" % [peak, trough],
	})

	# --- wedge_points ---
	var wpts := Minimap.wedge_points(Vector2(50, 50), Vector2(1, 0), 12.0, 0.45)
	var tip_ok := wpts.size() == 3 and is_finite(wpts[0].x) and is_finite(wpts[0].y) \
		and (wpts[0] - Vector2(50, 50)).normalized().is_equal_approx(Vector2(1, 0)) \
		and (wpts[0] - Vector2(50, 50)).length() == 12.0
	var wpts_up := Minimap.wedge_points(Vector2.ZERO, Vector2.ZERO, 10.0, 0.45)
	results.append({
		"name": "wedge_points: 3 finite pts, tip along facing; zero facing -> up",
		"passed": tip_ok and (wpts_up[0] - Vector2.ZERO).normalized().is_equal_approx(Vector2.UP),
		"why": str(wpts) + " up=" + str(wpts_up),
	})

	# --- advance_tracks state machine ---
	var live1: Array = [
		{"id": 1, "xz": Vector2(2.0, 0.0), "kind": &"enemy", "blink": 0.0},
		{"id": 2, "xz": Vector2(0.0, 3.0), "kind": &"elite", "blink": 0.0},
		{"id": 3, "xz": Vector2(1.0, 1.0), "kind": &"pickup", "blink": 1.0},
	]
	var t1 := Minimap.advance_tracks({}, live1, 0.016, 1000)
	var spawn_at_truth: bool = t1.size() == 3 \
		and (t1[1] as Dictionary)["pos"] == Vector2(2.0, 0.0) \
		and (t1[1] as Dictionary)["born_ms"] == 1000 \
		and (t1[3] as Dictionary)["kind"] == &"pickup" \
		and (t1[3] as Dictionary)["blink"] == 1.0
	results.append({
		"name": "advance_tracks spawns new tracks at truth with born_ms",
		"passed": spawn_at_truth,
		"why": str(t1),
	})
	# Entity 1 moved: display pos must ease between old and new, closer to new.
	var live2: Array = [
		{"id": 1, "xz": Vector2(4.0, 0.0), "kind": &"enemy", "blink": 0.0},
		{"id": 2, "xz": Vector2(0.0, 3.0), "kind": &"elite", "blink": 0.0},
		{"id": 3, "xz": Vector2(1.0, 1.0), "kind": &"pickup", "blink": 1.0},
	]
	var t2 := Minimap.advance_tracks(t1, live2, 0.1, 1100)
	var p21: Vector2 = (t2[1] as Dictionary)["pos"]
	var eased := p21.x > 2.0 and p21.x < 4.0 and p21.x > 3.0  # well past midpoint at rate 8, dt 0.1
	results.append({
		"name": "advance_tracks eases live tracks toward new truth (no snap)",
		"passed": eased and (t2[1] as Dictionary)["born_ms"] == 1000,
		"why": str(p21),
	})
	# Entity 1 vanished (absent from the live roster): fades at
	# delta/fade_seconds per step and holds its last seen position.
	var live3: Array = [
		{"id": 2, "xz": Vector2(0.0, 3.0), "kind": &"elite", "blink": 0.0},
		{"id": 3, "xz": Vector2(1.0, 1.0), "kind": &"pickup", "blink": 1.0},
	]
	var t3 := Minimap.advance_tracks(t2, live3, 0.175, 1275)
	var a3 := float((t3[1] as Dictionary)["alpha"])
	var hold: bool = (t3[1] as Dictionary)["pos"] == p21
	results.append({
		"name": "advance_tracks stale tracks fade (0.5 after half-fade) and hold position",
		"passed": absf(a3 - 0.5) < 1.0e-3 and hold,
		"why": "alpha=%f pos=%s" % [a3, str((t3[1] as Dictionary)["pos"])],
	})
	var t4 := Minimap.advance_tracks(t3, live3, 0.2, 1475)
	results.append({
		"name": "advance_tracks drops stale tracks once faded out",
		"passed": not t4.has(1) and t4.size() == 2,
		"why": str(t4.keys()),
	})
	# Re-spawn of a just-faded id gets a fresh track (new ping).
	var t5 := Minimap.advance_tracks(t4, live2, 0.016, 1491)
	results.append({
		"name": "advance_tracks respawned entity is a fresh track (new born_ms)",
		"passed": t5.has(1) and int((t5[1] as Dictionary)["born_ms"]) == 1491 \
			and (t5[1] as Dictionary)["pos"] == Vector2(4.0, 0.0),
		"why": str(t5.get(1, {})),
	})
	# Garbage entries are ignored.
	var junk: Array = [
		"nope",
		{"id": -3, "xz": Vector2(1, 1), "kind": &"enemy", "blink": 0.0},
		{"id": 4, "xz": Vector2(INF, 0.0), "kind": &"enemy", "blink": 0.0},
		{"id": 5, "xz": Vector2(1, 1), "kind": &"enemy", "blink": 99.0},
	]
	var t6 := Minimap.advance_tracks({}, junk, 0.016, 2000)
	results.append({
		"name": "advance_tracks ignores non-dicts, bad ids, NaN truth; clamps blink",
		"passed": t6.size() == 1 and t6.has(5) and float((t6[5] as Dictionary)["blink"]) == 1.0,
		"why": str(t6),
	})
	# Duplicate ids in one live list collapse to one track.
	var dup: Array = [
		{"id": 9, "xz": Vector2(1, 1), "kind": &"enemy", "blink": 0.0},
		{"id": 9, "xz": Vector2(2, 2), "kind": &"enemy", "blink": 0.0},
	]
	var t7 := Minimap.advance_tracks({}, dup, 0.016, 3000)
	results.append({
		"name": "advance_tracks dedupes repeated ids",
		"passed": t7.size() == 1 and (t7[9] as Dictionary)["pos"] == Vector2(1, 1),
		"why": str(t7),
	})
	# Cap: 200 fresh entities, cap 96 -> exactly 96 kept, all live (alpha 1).
	var big: Array = []
	for i in range(200):
		big.append({"id": 1000 + i, "xz": Vector2(float(i % 20), float(int(i / 20.0))), "kind": &"enemy", "blink": 0.0})
	var t8 := Minimap.advance_tracks({}, big, 0.016, 4000, 8.0, 0.35, 96)
	results.append({
		"name": "advance_tracks enforces the track cap",
		"passed": t8.size() == 96,
		"why": "size=%d" % t8.size(),
	})
	# Determinism: same inputs -> identical output.
	var d1 := Minimap.advance_tracks(t1, live2, 0.1, 1100)
	var d2 := Minimap.advance_tracks(t1, live2, 0.1, 1100)
	results.append({
		"name": "advance_tracks is deterministic",
		"passed": d1 == d2,
		"why": "",
	})

	return results
