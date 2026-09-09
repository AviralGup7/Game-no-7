extends RefCounted

## Deterministic governor tests for the PerformanceMonitor rebuild.
##
## The monitor is driven with synthetic frame times (push_frame_time) and a
## pinned internal clock (set_test_time), so every warmup / cooldown /
## stability decision is exact — no real-time waits, no wall-clock flakiness.
## No tree required: engine writes are headless-safe and render knobs are
## guarded; this is the "pure/deterministic function exercised headlessly"
## contract from the README.
##
## Tick convention: each loop iteration is one 30 Hz frame —
##   m.process_tick(1.0 / 30.0) with the test clock advanced 33 ms.

const TICK := 1.0 / 30.0
const TICK_MS := 33
const BAD_MS := 50.0        # 3x the 60 fps budget: unambiguous degradation
const GOOD_MS := 16.667     # a flat 60 fps stream: exactly the 60 fps budget


static func suite() -> Array:
	var results: Array = []
	var saved_max_fps := Engine.max_fps

	var monitor_script: GDScript = load("res://scripts/utilities/performance_monitor.gd")
	results.append(_case(
		"monitor loads",
		monitor_script != null,
		"load() returned null (parse error)"))
	results.append(_parse_smoke())

	# -- case 1: warmup holds, sustained degradation walks to the floor, -----
	#            every auto step persists the settled tier.
	var m := PerformanceMonitor.new()
	var tiers_seen: Array = []
	var persists: Array = []
	m.set_persist_tier_callable(func(name: String) -> void: persists.append(name))
	m.quality_tier_changed.connect(func(_old_t: int, new_t: int) -> void: tiers_seen.append(new_t))
	m.set_test_time(0)
	m.arm(0)
	_drive(m, 80, BAD_MS)  # t = 2640 ms, still inside the 3000 ms warmup
	results.append(_case(
		"warmup holds: no auto step in the first 3s",
		m.get_tier() == PerformanceMonitor.TIER_HIGH and tiers_seen.is_empty(),
		"tier=%d signals=%d" % [m.get_tier(), tiers_seen.size()]))
	# Through t ~= 11220 ms: the first step clears warmup + 2 bad ticks (~t=5.3s);
	# the second must also wait out the 5 s step cooldown (~t=10.3s).
	_drive(m, 260, BAD_MS)
	results.append(_case(
		"sustained over-budget frames walk HIGH->MEDIUM->LOW and stop at the floor",
		m.get_tier() == PerformanceMonitor.TIER_LOW and tiers_seen == [PerformanceMonitor.TIER_MEDIUM, PerformanceMonitor.TIER_LOW],
		"tier=%d signals=%s" % [m.get_tier(), str(tiers_seen)]))
	results.append(_case(
		"auto steps persist the settled tier, in order",
		persists == ["medium", "low"],
		"persisted=%s" % str(persists)))
	_drive(m, 60, BAD_MS)
	results.append(_case(
		"at the floor the governor stops churning",
		m.get_tier() == PerformanceMonitor.TIER_LOW and tiers_seen.size() == 2,
		"tier=%d signals=%d" % [m.get_tier(), tiers_seen.size()]))

	# -- case 2: upgrades need a long clean stretch, one tier per window. ----
	_drive(m, 600, GOOD_MS)  # 20 s of a flat 60 fps
	results.append(_case(
		"step up #1 only after 15s stability (LOW->MEDIUM)",
		m.get_tier() == PerformanceMonitor.TIER_MEDIUM and tiers_seen.size() == 3,
		"tier=%d signals=%d" % [m.get_tier(), tiers_seen.size()]))
	_drive(m, 600, GOOD_MS)
	results.append(_case(
		"step up #2 (MEDIUM->HIGH) after another clean window",
		m.get_tier() == PerformanceMonitor.TIER_HIGH and tiers_seen.size() == 4,
		"tier=%d signals=%d" % [m.get_tier(), tiers_seen.size()]))
	_drive(m, 600, GOOD_MS)
	results.append(_case(
		"step up #3 (HIGH->ULTRA) caps at the ceiling",
		m.get_tier() == PerformanceMonitor.TIER_ULTRA and tiers_seen.size() == 5,
		"tier=%d signals=%d" % [m.get_tier(), tiers_seen.size()]))
	_drive(m, 600, GOOD_MS)
	results.append(_case(
		"ULTRA is the ceiling: no further churn",
		m.get_tier() == PerformanceMonitor.TIER_ULTRA and tiers_seen.size() == 5,
		"tier=%d signals=%d" % [m.get_tier(), tiers_seen.size()]))
	results.append(_case(
		"upgrade path persisted medium->high->ultra",
		persists == ["medium", "low", "medium", "high", "ultra"],
		"persisted=%s" % str(persists)))
	m.free()

	# -- case 3: manual tier changes emit once, are silent when repeated, and
	#            never persist (the save belongs to the auto governor / user UI).
	var m2 := PerformanceMonitor.new()
	var manual_signals: Array = []
	var manual_persists: Array = []
	m2.set_persist_tier_callable(func(name: String) -> void: manual_persists.append(name))
	m2.quality_tier_changed.connect(func(_o: int, n: int) -> void: manual_signals.append(n))
	m2.set_test_time(0)
	m2.arm(0)
	m2.set_tier(PerformanceMonitor.TIER_LOW)
	m2.set_tier(PerformanceMonitor.TIER_LOW)
	results.append(_case(
		"manual set_tier: one signal on change, silent on repeat, no persist",
		manual_signals == [PerformanceMonitor.TIER_LOW] and manual_persists.is_empty(),
		"signals=%s persists=%s" % [str(manual_signals), str(manual_persists)]))
	m2.free()

	# -- case 4: the 5 s cooldown gates manual steps in both directions. -----
	var m3 := PerformanceMonitor.new()
	m3.set_test_time(0)
	m3.arm(0)
	m3.set_tier(PerformanceMonitor.TIER_MEDIUM)
	m3.set_test_time(1000)
	var early: bool = m3.request_step_down()
	m3.set_test_time(5000)
	var after: bool = m3.request_step_down()
	var rearmed: bool = m3.request_step_up()
	m3.set_test_time(10000)
	var up: bool = m3.request_step_up()
	results.append(_case(
		"cooldown: decline inside 5s, accept after, re-arm on each step",
		early == false and after == true and rearmed == false and up == true and m3.get_tier() == PerformanceMonitor.TIER_MEDIUM,
		"early=%s after=%s rearmed=%s up=%s tier=%d" % [str(early), str(after), str(rearmed), str(up), m3.get_tier()]))
	m3.free()

	# -- case 5: the player's session FPS cap survives tier changes. ---------
	var m4 := PerformanceMonitor.new()
	m4.configure(PerformanceMonitor.TIER_MEDIUM, 30)
	var cap_medium: int = Engine.max_fps
	m4.set_tier(PerformanceMonitor.TIER_ULTRA)
	var cap_ultra: int = Engine.max_fps
	m4.set_tier(PerformanceMonitor.TIER_LOW)
	var cap_low: int = Engine.max_fps
	var budget := m4.frame_budget_ms()
	results.append(_case(
		"session cap (30 fps) is never raised above by tier changes",
		cap_medium == 30 and cap_ultra == 30 and cap_low == 30,
		"caps medium/ultra/low = %d/%d/%d" % [cap_medium, cap_ultra, cap_low]))
	results.append(_case(
		"frame budget tightens to the session cap",
		absf(budget - 1000.0 / 30.0) < 0.01,
		"budget=%.3f" % budget))
	m4.free()

	# -- case 6: percentile math + ring cap (nearest-rank p95). --------------
	var m5 := PerformanceMonitor.new()
	for i in range(1, 101):
		m5.push_frame_time(float(i))
	var p95_a: float = m5.get_p95_frame_ms()
	for i in range(101, 201):
		m5.push_frame_time(float(i))
	var stats_b: Dictionary = m5.get_frame_time_stats()
	for i in range(201, 601):
		m5.push_frame_time(float(i))
	var stats_c: Dictionary = m5.get_frame_time_stats()
	results.append(_case(
		"p95 of 1..100 is 95 (nearest rank)",
		absf(p95_a - 95.0) < 0.001,
		"p95=%.3f" % p95_a))
	results.append(_case(
		"average of 1..200 is 100.5",
		absf(float(stats_b["avg_ms"]) - 100.5) < 0.001,
		"avg=%.3f" % float(stats_b["avg_ms"])))
	results.append(_case(
		"ring caps at 240 samples holding the newest frames (361..600 avg 480.5)",
		int(stats_c["samples"]) == PerformanceMonitor.RING_SIZE and absf(float(stats_c["avg_ms"]) - 480.5) < 0.001,
		"samples=%d avg=%.3f" % [int(stats_c["samples"]), float(stats_c["avg_ms"])]))
	m5.free()

	# -- case 7: clock/pause artifacts never enter the window. ---------------
	var m6 := PerformanceMonitor.new()
	m6.push_frame_time(NAN)
	m6.push_frame_time(-5.0)
	m6.push_frame_time(0.0)
	m6.push_frame_time(5000.0)
	var dropped: Dictionary = m6.get_frame_time_stats()
	m6.push_frame_time(20.0)
	m6.push_frame_time(20.0)
	var kept: Dictionary = m6.get_frame_time_stats()
	results.append(_case(
		"non-finite / out-of-range samples are dropped",
		int(dropped["samples"]) == 0 and int(kept["samples"]) == 2 and absf(float(kept["avg_ms"]) - 20.0) < 0.001,
		"dropped=%d kept=%d avg=%.3f" % [int(dropped["samples"]), int(kept["samples"]), float(kept["avg_ms"])]))
	m6.free()

	# -- case 8: a flat 60 fps at a 60 fps tier is healthy, not a step signal.
	var m7 := PerformanceMonitor.new()
	m7.configure(PerformanceMonitor.TIER_MEDIUM, 0)
	var m7_signals: Array = []
	m7.quality_tier_changed.connect(func(_o: int, _n: int) -> void: m7_signals.append(1))
	m7.set_test_time(0)
	m7.arm(0)
	_drive(m7, 240, GOOD_MS)  # 8 s: clean but inside the 15 s upgrade gate
	results.append(_case(
		"healthy at-cap pacing does not trigger a step (8s < 15s stability)",
		m7.get_tier() == PerformanceMonitor.TIER_MEDIUM and m7_signals.is_empty(),
		"tier=%d signals=%d" % [m7.get_tier(), m7_signals.size()]))
	m7.free()

	# -- case 9: spiky workload (ok average, recurring stalls) steps down. ---
	var m8 := PerformanceMonitor.new()
	m8.configure(PerformanceMonitor.TIER_MEDIUM, 0)
	var m8_signals: Array = []
	m8.quality_tier_changed.connect(func(_o: int, n: int) -> void: m8_signals.append(n))
	m8.set_test_time(0)
	m8.arm(0)
	var frame_idx := 0
	for _t in range(240):
		# 70% fast frames, 30% 35 ms stalls: avg 17.5 ms (barely over budget),
		# p95 35 ms (2.1x), many hitches -> the "spiky" gate must fire.
		m8.push_frame_time(35.0 if frame_idx % 10 < 3 else 10.0)
		frame_idx += 1
		m8.process_tick(TICK)
		m8.set_test_time(m8._test_now_msec + TICK_MS)
	results.append(_case(
		"spiky workload (recurring hitches) steps down despite ok average",
		m8.get_tier() == PerformanceMonitor.TIER_LOW and m8_signals == [PerformanceMonitor.TIER_LOW],
		"tier=%d signals=%s" % [m8.get_tier(), str(m8_signals)]))
	m8.free()

	# -- case 10: one hitch in the window blocks an upgrade, then recovery. --
	var m9 := PerformanceMonitor.new()
	m9.configure(PerformanceMonitor.TIER_LOW, 0)
	var m9_signals: Array = []
	m9.quality_tier_changed.connect(func(_o: int, n: int) -> void: m9_signals.append(n))
	m9.set_test_time(0)
	m9.arm(0)
	_drive(m9, 480, GOOD_MS)  # 16 s -> LOW->MEDIUM around the 15 s mark
	results.append(_case(
		"upgrade LOW->MEDIUM happens once the 15s gate elapses",
		m9.get_tier() == PerformanceMonitor.TIER_MEDIUM and m9_signals == [PerformanceMonitor.TIER_MEDIUM],
		"tier=%d signals=%s" % [m9.get_tier(), str(m9_signals)]))
	_drive(m9, 150, GOOD_MS)
	m9.push_frame_time(100.0)  # a single stall inside the live window
	_drive(m9, 150, GOOD_MS)  # t ~= 21 s: the hitch is still inside the ring
	results.append(_case(
		"a live hitch blocks the next upgrade",
		m9.get_tier() == PerformanceMonitor.TIER_MEDIUM and m9_signals.size() == 1,
		"tier=%d signals=%s" % [m9.get_tier(), str(m9_signals)]))
	_drive(m9, 300, GOOD_MS)  # the hitch ages out of the 4s window
	results.append(_case(
		"after the hitch ages out, the upgrade resumes (MEDIUM->HIGH)",
		m9.get_tier() == PerformanceMonitor.TIER_HIGH and m9_signals == [PerformanceMonitor.TIER_MEDIUM, PerformanceMonitor.TIER_HIGH],
		"tier=%d signals=%s" % [m9.get_tier(), str(m9_signals)]))
	m9.free()

	Engine.max_fps = saved_max_fps
	return results


## Parse smoke for the five files the governor rebuild touches (CI runs the
## full suites elsewhere; this keeps a regression visible in the unit tier).
static func _parse_smoke() -> Dictionary:
	var paths := [
		"res://scripts/utilities/performance_monitor.gd",
		"res://scripts/main/main.gd",
		"res://scripts/ui/ui_root.gd",
		"res://scripts/save/settings_data.gd",
		"res://scripts/ui/settings_panel.gd",
	]
	var broken: Array = []
	for path in paths:
		if load(path) == null:
			broken.append(path)
	return _case(
		"governor-rebuild scripts parse (%d files)" % paths.size(),
		broken.is_empty(),
		"failed: %s" % str(broken))


static func _drive(m: PerformanceMonitor, ticks: int, frame_ms: float) -> void:
	for _t in range(ticks):
		m.push_frame_time(frame_ms)
		m.process_tick(TICK)
		m.set_test_time(m._test_now_msec + TICK_MS)


static func _case(name: String, passed: bool, why: String = "") -> Dictionary:
	return {"name": name, "passed": passed, "why": why}
