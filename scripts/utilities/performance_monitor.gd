class_name PerformanceMonitor
extends Node

## Runtime performance sampling + automatic quality scaling for low-end Android.
##
## Governor rebuild (v2) — full algorithm write-up and sources in
## docs/PERFORMANCE_GOVERNOR.md. Design properties, grounded in industry
## practice for adaptive quality scaling:
##
## - Decisions run on FRAME TIME, not FPS. FPS is the nonlinear inverse of
##   frame time, so an FPS average flatters mixed workloads (alternating
##   30/90 fps reads as "60 fps"). Frame time is linear: budget vs actual.
## - Thresholds are RELATIVE to the current tier's own frame budget. A 30 fps
##   tier is *designed* to run at 33.3 ms; an absolute "degrade past 18 ms"
##   rule reads that healthy capped tier as failing and cascades to the floor
##   with no way back up (recovery needs frame times the cap itself forbids).
## - The 95th-percentile frame time is the primary statistic (it captures the
##   stutters players actually notice; the average hides them), with a hitch
##   count (frames beyond 2x budget) catching spiky workloads a flat average
##   would miss.
## - Hysteresis: a downgrade needs two consecutive sustained-bad decision
##   ticks; an upgrade needs a long clean stretch (15 s) since the last tier
##   change. Downgrade fast, upgrade cautiously — without hysteresis the
##   system oscillates and ends up worse than a fixed low preset.
## - The sample window clears on every tier change so no decision is ever made
##   on stale samples from the previous tier.
## - A rate-capped tier hides headroom (frames pin to the cap even on fast
##   hardware), so the upgrade gate for "at the cap" tiers tests flat pacing
##   (low p95, zero hitches) instead of average headroom.
## - An auto-scaled tier is persisted through an injected Callable seam (this
##   script stays free of autoload identifiers so headless suites can load it
##   under --script); main.gd wires the seam to SaveManager, so a slow device
##   reboots at the tier that already proved sustainable instead of re-lagging.
##
## Headless-safe: every rendering query is guarded; the governor core is pure
## and driven by push_frame_time()/process_tick()/set_test_time() in tests.

signal fps_sampled(fps: float, average: float)
signal quality_tier_changed(old_tier: int, new_tier: int)

const TIER_ULTRA := 3
const TIER_HIGH := 2
const TIER_MEDIUM := 1
const TIER_LOW := 0

## Ring depth: ~4 s of frames at 60 fps. Fixed head index => O(1) push, no
## per-frame FIFO pop and no per-frame full-window re-sum.
const RING_SIZE := 240
## Decision cadence: window stats are computed here, not per frame.
const DECISION_INTERVAL_SECONDS := 0.5
## A fresh run absorbs load spikes (scene build, first shader compile).
## Samples still accumulate; auto-steps are withheld during this window.
const WARMUP_SECONDS := 3.0
## Cooldown between any two tier changes (seconds).
const MIN_SECONDS_BETWEEN_STEPS := 5.0
## Upgrade gate: seconds of sustained stability at the current tier required
## before a single step up.
const UP_STABILITY_SECONDS := 15.0
## Downgrade gate (sustained): avg and p95 both over budget by these ratios.
const DOWN_AVG_RATIO := 1.15
const DOWN_P95_RATIO := 1.35
## Downgrade gate (spiky): recurring stalls (hitches) plus a badly stretched
## tail, even when the average still looks acceptable.
const DOWN_HITCH_MIN := 2
const DOWN_SPIKE_P95_RATIO := 1.5
## Upgrade gate (uncapped tiers): the tier must sit comfortably inside budget.
const UP_AVG_RATIO := 0.8
const UP_P95_RATIO := 0.9
## Upgrade gate (rate-capped tiers): pacing must be flat at the cap.
const AT_CAP_AVG_RATIO := 0.95
const UP_P95_AT_CAP_RATIO := 1.1
## A frame beyond 2x budget counts as a hitch/stall.
const HITCH_BUDGET_MULT := 2.0
## Samples outside [MIN_SAMPLE_MS, MAX_SAMPLE_MS] are clock/pause artifacts.
const MIN_SAMPLE_MS := 0.1
const MAX_SAMPLE_MS := 1000.0
## Minimum ring fill before a window is trusted for a decision.
const MIN_SAMPLES_FOR_DECISION := 30
## Budget reference when a tier carries no fps cap (desktop, unlimited): the
## game's design frame budget.
const UNCAPPED_BUDGET_FPS := 60.0

## Zeroed RING_SIZE sample ring. Godot 4.4 has no PackedFloat32Array(int)
## constructor, so make_ring() resizes an empty array. The member starts
## empty on purpose (constructor-time expressions stay trivially safe); the
## first push_frame_time() lazily sizes it via _clear_ring().
static func make_ring() -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.resize(RING_SIZE)
	return r


var _ring: PackedFloat32Array = PackedFloat32Array()
var _head := 0
var _filled := 0
var _sum := 0.0
var _tier: int = TIER_HIGH
var _enabled := true
var _auto_scale := true
var _last_step_msec: int = 0
var _stable_since_msec: int = 0
var _warmup_until_msec: int = 0
var _down_streak := 0
var _decision_accum := 0.0
var _last_sample_usec: int = 0
var _session_cap_fps := 0
var _persist_tier: Callable = Callable()
var _root_viewport: Viewport = null
## Test seam: when >= 0, _now_ms() reads this instead of wall time, which makes
## warmup/cooldown/stability decisions exactly reproducible in headless suites.
var _test_now_msec := -1


func _ready() -> void:
	add_to_group("performance_monitor")
	var tree := get_tree()
	if tree != null:
		_root_viewport = tree.root as Viewport
	arm()


func _process(delta: float) -> void:
	if not _enabled:
		return
	_sample_frame()
	process_tick(delta)


func _exit_tree() -> void:
	# A low-tier run must not leave the persistent menus capped at the run's
	# degraded level: the global fps cap returns to the project-configured
	# value. MSAA (a viewport-level knob) is restored the same way, from the
	# project setting, so the menu never inherits the run's AA level.
	Engine.max_fps = _configured_max_fps()
	_restore_msaa()


## Pin the internal clock (headless tests). -1 restores wall time.
func set_test_time(ms: int) -> void:
	_test_now_msec = ms


## Start the governor from `initial_tier`: record the time base, begin warmup,
## apply the tier's engine knobs. _ready() calls this; headless tests call it
## directly with a pinned clock.
func arm(now_ms: int = -1) -> void:
	var now := _clock(now_ms)
	_last_step_msec = now
	_stable_since_msec = now
	_warmup_until_msec = now + int(WARMUP_SECONDS * 1000.0)
	_down_streak = 0
	_decision_accum = 0.0
	_last_sample_usec = 0
	_clear_ring()
	_apply_tier_to_engine()


## Set the starting tier (from the player's saved graphics quality) and the
## session FPS cap chosen in Settings. Call before add_child().
func configure(initial_tier: int, session_cap_fps: int = 0) -> void:
	_session_cap_fps = maxi(int(session_cap_fps), 0)
	set_tier(initial_tier)


## Provider seam: main.gd wires this to SaveManager so an auto-scaled tier
## persists across launches. Manual tier changes never call it.
func set_persist_tier_callable(callable: Callable) -> void:
	_persist_tier = callable


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func set_auto_scale(auto: bool) -> void:
	_auto_scale = auto


func get_tier() -> int:
	return _tier


func get_tier_name(idx: int = -1) -> String:
	var i := _tier if idx < 0 else clampi(idx, 0, TIER_ULTRA)
	match i:
		TIER_ULTRA:
			return "ultra"
		TIER_HIGH:
			return "high"
		TIER_MEDIUM:
			return "medium"
		_:
			return "low"


## Advance the governor. Called from _process; headless tests drive it
## directly with synthetic deltas and a pinned clock.
func process_tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var avg_fps := get_average_fps()
	var inst_fps := 0.0
	if _filled > 0:
		var last := float(_ring[(_head - 1 + RING_SIZE) % RING_SIZE])
		if last > 0.0:
			inst_fps = 1000.0 / last
	fps_sampled.emit(inst_fps, avg_fps)
	if not _auto_scale:
		return
	_decision_accum += delta
	if _decision_accum < DECISION_INTERVAL_SECONDS:
		return
	_decision_accum = 0.0
	var now := _now_ms()
	if now < _warmup_until_msec:
		return
	if _filled < MIN_SAMPLES_FOR_DECISION:
		return
	_tick_auto_scale(now)


## Record one frame time (ms). Non-finite and out-of-range values (pause
## resume spikes, clock glitches) are dropped instead of poisoning the window.
func push_frame_time(ms: float) -> void:
	if not is_finite(ms) or ms < MIN_SAMPLE_MS or ms > MAX_SAMPLE_MS:
		return
	if _ring.size() != RING_SIZE:
		_clear_ring()
	if _filled < RING_SIZE:
		_ring[_head] = ms
		_filled += 1
	else:
		_sum -= _ring[_head]
		_ring[_head] = ms
	_head = (_head + 1) % RING_SIZE
	_sum += ms


## Measure this frame's wall-clock interval and record it.
func _sample_frame() -> void:
	var now_usec := Time.get_ticks_usec()
	if _last_sample_usec > 0:
		push_frame_time(float(now_usec - _last_sample_usec) / 1000.0)
	_last_sample_usec = now_usec


## Frame budget for a tier: 1000 ms / effective target fps. Always relative to
## the tier's own cap, so a tier holding its designed rate reads as healthy.
## The player's session FPS cap (Settings) can only tighten the budget, never
## loosen it.
func frame_budget_ms(tier: int = -1) -> float:
	var t := _tier if tier < 0 else tier
	var fps := float(tier_target_fps(t))
	if not is_finite(fps) or fps <= 0.0:
		fps = UNCAPPED_BUDGET_FPS
	if _session_cap_fps > 0:
		fps = minf(fps, float(_session_cap_fps))
	if fps <= 0.0:
		fps = UNCAPPED_BUDGET_FPS
	return 1000.0 / fps


func tier_target_fps(tier: int) -> int:
	match clampi(tier, TIER_LOW, TIER_ULTRA):
		TIER_LOW:
			return 30
		TIER_MEDIUM:
			return 60
		_:
			return _configured_max_fps()


## Engine cap written for a tier. The player's session cap survives tier
## changes: the governor may lower the cap, never raise it above the choice.
func _tier_fps_cap(tier: int) -> int:
	var base := tier_target_fps(tier)
	if _session_cap_fps > 0:
		if base <= 0:
			return _session_cap_fps
		return mini(base, _session_cap_fps)
	return base


func _cooldown_elapsed() -> bool:
	return _now_ms() - _last_step_msec >= int(MIN_SECONDS_BETWEEN_STEPS * 1000.0)


func request_step_down() -> bool:
	if _tier <= TIER_LOW or not _cooldown_elapsed():
		return false
	set_tier(_tier - 1)
	return true


func request_step_up() -> bool:
	if _tier >= TIER_ULTRA or not _cooldown_elapsed():
		return false
	set_tier(_tier + 1)
	return true


## User / settings-UI path: explicit choice, never persisted, window cleared.
func set_tier(tier: int) -> void:
	_change_tier(clampi(tier, TIER_LOW, TIER_ULTRA))


## Auto-scale path: applies the tier and persists it for the next launch.
func _auto_step(new_tier: int, reason: String) -> void:
	_change_tier(clampi(new_tier, TIER_LOW, TIER_ULTRA), reason, true)


func _change_tier(target: int, reason: String = "", persist: bool = false) -> void:
	if target == _tier:
		return
	var old := _tier
	_tier = target
	_last_step_msec = _now_ms()
	_stable_since_msec = _last_step_msec
	_down_streak = 0
	# Decisions never run on samples collected under the previous tier.
	_clear_ring()
	_apply_tier_to_engine()
	quality_tier_changed.emit(old, _tier)
	if persist:
		if _persist_tier.is_valid():
			_persist_tier.call(get_tier_name())
		if reason != "":
			_report_info("Quality auto-scaled %s -> %s (%s)" % [get_tier_name(old), get_tier_name(_tier), reason])


func _tick_auto_scale(now: int) -> void:
	var budget := frame_budget_ms()
	var stats := _window_stats(budget)
	var sustained := float(stats["avg_ratio"]) >= DOWN_AVG_RATIO and float(stats["p95_ratio"]) >= DOWN_P95_RATIO
	var spiky := int(stats["hitches"]) >= DOWN_HITCH_MIN and float(stats["p95_ratio"]) >= DOWN_SPIKE_P95_RATIO
	if sustained or spiky:
		_down_streak += 1
	else:
		_down_streak = 0
	if _down_streak >= 2 and _cooldown_elapsed():
		# Auto path (the manual step-down API never persists): downgrades must
		# persist like upgrades — the next launch opens at the settled tier.
		_auto_step(_tier - 1, "sustained frame-time deficit")
		return
	var clean := _is_clean(stats, float(stats["avg_ms"]), budget)
	if clean and _tier < TIER_ULTRA and _cooldown_elapsed():
		if now - _stable_since_msec >= int(UP_STABILITY_SECONDS * 1000.0):
			_auto_step(_tier + 1, "sustained headroom for %ds" % int(UP_STABILITY_SECONDS))


## Clean = enough headroom to justify the tier above. Rate-capped tiers hide
## headroom (frames pin to the cap even on fast hardware), so for a tier that
## is AT its cap the gate tests flat pacing instead of average headroom.
func _is_clean(stats: Dictionary, avg_ms: float, budget: float) -> bool:
	var p95_ratio := float(stats["p95_ratio"])
	var hitches := int(stats["hitches"])
	if hitches > 0:
		return false
	if avg_ms >= AT_CAP_AVG_RATIO * budget:
		return p95_ratio <= UP_P95_AT_CAP_RATIO
	return p95_ratio <= UP_P95_RATIO and float(stats["avg_ratio"]) <= UP_AVG_RATIO


## Frame-time window stats relative to `budget_ms`. Percentiles use the
## nearest-rank method on a sorted copy (O(n log n), run at decision cadence
## only — never per frame).
func _window_stats(budget_ms: float) -> Dictionary:
	var avg_ms := get_average_frame_ms()
	var p95_ms := get_p95_frame_ms()
	var hitches := 0
	for i in _filled:
		if float(_ring[i]) > HITCH_BUDGET_MULT * budget_ms:
			hitches += 1
	var safe := budget_ms if budget_ms > 0.0 else 1.0
	return {
		"avg_ms": avg_ms,
		"p95_ms": p95_ms,
		"hitches": hitches,
		"avg_ratio": avg_ms / safe,
		"p95_ratio": p95_ms / safe,
	}


## Public telemetry / test view of the current window.
func get_frame_time_stats() -> Dictionary:
	var stats := _window_stats(frame_budget_ms())
	return {
		"samples": _filled,
		"avg_ms": float(stats["avg_ms"]),
		"p95_ms": float(stats["p95_ms"]),
		"hitches": int(stats["hitches"]),
		"budget_ms": frame_budget_ms(),
	}


func get_average_frame_ms() -> float:
	if _filled == 0:
		return 0.0
	return _sum / float(_filled)


func get_p95_frame_ms() -> float:
	if _filled == 0:
		return 0.0
	var samples: Array = []
	samples.resize(_filled)
	for i in _filled:
		samples[i] = float(_ring[i])
	samples.sort()
	var rank := ceili(0.95 * float(_filled))
	var idx := mini(int(rank) - 1, _filled - 1)
	return float(samples[maxi(idx, 0)])


func get_average_fps() -> float:
	if _filled == 0:
		return 60.0
	var avg := get_average_frame_ms()
	if avg <= 0.0:
		return 60.0
	return 1000.0 / avg


func get_min_fps() -> float:
	if _filled == 0:
		return 60.0
	# Rare path (debug snapshot): a full scan is fine here.
	var m := INF
	for i in _filled:
		m = minf(m, float(_ring[i]))
	if m <= 0.0:
		return 60.0
	return 1000.0 / m


func _clear_ring() -> void:
	_ring = make_ring()
	_head = 0
	_filled = 0
	_sum = 0.0


## Push engine-level knobs for the current tier. Everything is best-effort and
## guarded so headless/editor runs without a renderer never crash.
func _apply_tier_to_engine() -> void:
	Engine.max_fps = _tier_fps_cap(_tier)
	_apply_msaa()
	_apply_render_tier()


## MSAA is the cheapest high-impact GPU lever on the mobile renderer. 4x is
## this project's ceiling: the engine docs call 8x "unlikely to run smoothly
## on mobile GPUs". Changing the level reconfigures the 3D render buffers, so
## it only happens on tier change (already rate-limited by the step cooldown).
func _apply_msaa() -> void:
	var vp := _resolve_root_viewport()
	if vp == null:
		return
	var level: int
	match _tier:
		TIER_LOW:
			level = Viewport.MSAA_DISABLED
		TIER_MEDIUM:
			level = Viewport.MSAA_2X
		_:
			level = Viewport.MSAA_4X
	if int(vp.msaa_3d) != level:
		vp.msaa_3d = level as Viewport.MSAA


func _restore_msaa() -> void:
	if _root_viewport == null or not is_instance_valid(_root_viewport):
		return
	var configured := int(ProjectSettings.get_setting_with_override("rendering/anti_aliasing/quality/msaa_3d"))
	if int(_root_viewport.msaa_3d) != configured:
		_root_viewport.msaa_3d = configured as Viewport.MSAA


func _resolve_root_viewport() -> Viewport:
	if _root_viewport != null and is_instance_valid(_root_viewport):
		return _root_viewport
	var tree := get_tree()
	if tree == null:
		return null
	_root_viewport = tree.root as Viewport
	return _root_viewport


## Shadows, glow, and sun energy promised by Settings.graphics_quality.
func _apply_render_tier() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var shadow_on := _tier >= TIER_MEDIUM
	var glow_on := _tier >= TIER_HIGH
	var shadow_size := 1024 if _tier <= TIER_MEDIUM else 2048
	RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
	for n in tree.get_nodes_in_group("arena"):
		if n is Node:
			_tune_arena_lights(n as Node, shadow_on, glow_on)


func _tune_arena_lights(arena: Node, shadow_on: bool, glow_on: bool) -> void:
	var sun := arena.get_node_or_null("Lighting/Sun") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = shadow_on
		sun.light_energy = 0.85 if _tier == TIER_LOW else 1.15
	var wenv := arena.get_node_or_null("Environment") as WorldEnvironment
	if wenv != null and wenv.environment != null:
		wenv.environment.glow_enabled = glow_on
		if _tier == TIER_LOW:
			wenv.environment.fog_density = minf(wenv.environment.fog_density, 0.008)


func _configured_max_fps() -> int:
	return int(ProjectSettings.get_setting_with_override("application/run/max_fps"))


## Autoload lookup by path + typed cast: bare identifiers are not injected
## into scripts compiled by the --script test harness (see tests/run_tests.gd
## header); the Node is the real EventBus script when autoloads ran.
func _report_info(text: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var bus := tree.root.get_node_or_null("/root/EventBus") as EventBusService
	if bus != null:
		bus.report_info(text)


## Effect-budget multipliers queried by particle/text layers.
func particle_budget_scale() -> float:
	match _tier:
		TIER_ULTRA:
			return 1.0
		TIER_HIGH:
			return 0.8
		TIER_MEDIUM:
			return 0.5
		_:
			return 0.25


func max_damage_numbers() -> int:
	match _tier:
		TIER_ULTRA:
			return 48
		TIER_HIGH:
			return 32
		TIER_MEDIUM:
			return 20
		_:
			return 10


## Live-enemy budget used by WaveManager so high waves cannot spawn unbounded
## crowds on a LOW/MEDIUM phone. Independent of authored wave caps (takes min).
func max_simultaneous_enemies() -> int:
	match _tier:
		TIER_ULTRA:
			return 28
		TIER_HIGH:
			return 22
		TIER_MEDIUM:
			return 16
		_:
			return 10


## Live projectile budget. Independent of ProjectilePool.pool_size (the
## physical idle list); fire() never lets more than this stay in the air.
func max_projectiles() -> int:
	match _tier:
		TIER_ULTRA:
			return 48
		TIER_HIGH:
			return 32
		TIER_MEDIUM:
			return 20
		_:
			return 12


## Live pickup budget. PickupManager.max_live_pickups is mins against this.
func max_pickups() -> int:
	match _tier:
		TIER_ULTRA:
			return 24
		TIER_HIGH:
			return 18
		TIER_MEDIUM:
			return 12
		_:
			return 8


## Concurrent GPU particle bursts. Never exceeds EffectDirector.MAX_BURSTS.
func max_vfx_bursts() -> int:
	match _tier:
		TIER_ULTRA:
			return 10
		TIER_HIGH:
			return 8
		TIER_MEDIUM:
			return 6
		_:
			return 4


## Concurrent telegraph/impact rings. Never exceeds EffectDirector.MAX_RINGS.
func max_vfx_rings() -> int:
	match _tier:
		TIER_ULTRA:
			return 14
		TIER_HIGH:
			return 10
		TIER_MEDIUM:
			return 8
		_:
			return 5


## Concurrent world Foley voices. Never exceeds SpatialVoicePool.MAX_VOICES.
func max_spatial_voices() -> int:
	match _tier:
		TIER_ULTRA:
			return 16
		TIER_HIGH:
			return 12
		TIER_MEDIUM:
			return 8
		_:
			return 4


## One dictionary the PoolGovernor and debug overlay both read so a new cap
## cannot be added to one path and forgotten on the other.
func pool_budgets() -> Dictionary:
	return {
		"projectiles": max_projectiles(),
		"pickups": max_pickups(),
		"vfx_bursts": max_vfx_bursts(),
		"vfx_rings": max_vfx_rings(),
		"spatial_voices": max_spatial_voices(),
		"damage_numbers": max_damage_numbers(),
		"enemies": max_simultaneous_enemies(),
	}


func get_debug_snapshot() -> Dictionary:
	var stats := get_frame_time_stats()
	var budgets := pool_budgets()
	return {
		"tier": get_tier_name(),
		"avg_fps": get_average_fps(),
		"min_fps": get_min_fps(),
		"samples": int(stats["samples"]),
		"p95_ms": float(stats["p95_ms"]),
		"budget_ms": float(stats["budget_ms"]),
		"hitches": int(stats["hitches"]),
		"warmup": _now_ms() < _warmup_until_msec,
		"auto_scale": _auto_scale,
		"static_memory_mb": _static_memory_mb(),
		"max_projectiles": int(budgets["projectiles"]),
		"max_pickups": int(budgets["pickups"]),
		"max_vfx_bursts": int(budgets["vfx_bursts"]),
		"max_vfx_rings": int(budgets["vfx_rings"]),
		"max_spatial_voices": int(budgets["spatial_voices"]),
		"max_damage_numbers": int(budgets["damage_numbers"]),
		"max_simultaneous_enemies": int(budgets["enemies"]),
	}


## Debug telemetry: engine static memory, in MB. Typed call on purpose — 4.4
## has no system-total-RAM getter, and string dispatch is banned by the
## typed-architecture gate.
static func _static_memory_mb() -> int:
	return int(float(OS.get_static_memory_usage()) / 1048576.0)


func _now_ms() -> int:
	if _test_now_msec >= 0:
		return _test_now_msec
	return Time.get_ticks_msec()


func _clock(now_ms: int) -> int:
	if now_ms >= 0:
		return now_ms
	return _now_ms()
