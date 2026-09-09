extends RefCounted

## Headless unit tests for the human-like AI brain modules:
##   * EnemyPersonality — deterministic per-enemy cast (same run seed + serial
##     always rolls the same individual; values stay in authored ranges);
##   * EnemyPerception — sight/FOV/LOS, stimulus -> reaction -> engagement,
##     hearing, target memory / investigation, and the legacy always-aware mode.
## Pure RefCounted, no nodes, no physics.

static func suite() -> Array:
	var results: Array = []
	_personality_determinism(results)
	_personality_ranges(results)
	_perception_vision_cycle(results)
	_perception_hearing(results)
	_perception_los(results)
	_perception_fov(results)
	_perception_memory_and_investigation(results)
	_perception_spot_while_investigating(results)
	_perception_always_aware(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


# --- EnemyPersonality ------------------------------------------------------

static func _personality_determinism(results: Array) -> void:
	var a := EnemyPersonality.roll(12345, 7)
	var b := EnemyPersonality.roll(12345, 7)
	var c := EnemyPersonality.roll(12345, 8)
	_check(results, "same (seed, serial) rolls the same individual",
			a.aggression == b.aggression and a.caution == b.caution and a.aim_skill == b.aim_skill
			and a.strafe_bias == b.strafe_bias and a.reaction == b.reaction
			and a.dash_willingness == b.dash_willingness and a.cd_spread == b.cd_spread,
			"a=%s b=%s" % [str(a.aggression), str(b.aggression)])
	var differs := a.aggression != c.aggression or a.aim_skill != c.aim_skill \
			or a.strafe_bias != c.strafe_bias or a.reaction != c.reaction
	_check(results, "different serials roll different individuals", differs)


static func _personality_ranges(results: Array) -> void:
	var ok := true
	var why := ""
	for i in range(64):
		var p := EnemyPersonality.roll(999, i)
		if p.aggression < 0.2 or p.aggression > 0.9 \
				or p.caution < 0.1 or p.caution > 0.9 \
				or p.aim_skill < 0.3 or p.aim_skill > 0.85 \
				or p.reaction < 0.5 or p.reaction > 1.6 \
				or p.dash_willingness < 0.35 or p.dash_willingness > 1.0:
			ok = false
			why = "serial=%d" % i
			break
	_check(results, "personality values stay in authored ranges", ok, why)


# --- EnemyPerception -------------------------------------------------------

static func _mk(vision: float, fov: float, hearing: float, reaction: float, memory: float, always: bool) -> EnemyPerception:
	var p := EnemyPerception.new()
	p.configure(vision, fov, hearing, reaction, memory, always)
	return p


## See -> react (beats the reaction timer) -> engage; last_seen tracks.
static func _perception_vision_cycle(results: Array) -> void:
	var p := _mk(10.0, 360.0, 0.0, 0.2, 3.0, false)
	var eye := Vector3.ZERO
	p.update(0.016, eye, Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0), true)
	_check(results, "stimulus inside vision starts the REACTING beat",
			p.status == EnemyPerception.Status.REACTING, p.get_status_name())
	for _i in range(16):  # ~0.26 s > 0.2 s reaction
		p.update(0.016, eye, Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0), true)
	_check(results, "reaction timer elapses into ENGAGED", p.status == EnemyPerception.Status.ENGAGED,
			p.get_status_name())
	_check(results, "last seen tracks the target", p.last_seen_pos == Vector3(5.0, 0.0, 0.0),
			str(p.last_seen_pos))
	# Out of vision range: not visible, no fresh stimulus.
	var far := _mk(10.0, 360.0, 0.0, 0.2, 3.0, false)
	far.update(0.016, eye, Vector3(1.0, 0.0, 0.0), Vector3(30.0, 0.0, 0.0), true)
	_check(results, "target beyond vision range is not seen",
			far.status == EnemyPerception.Status.UNAWARE, far.get_status_name())


## Hearing wakes unaware enemies into investigation (no sight needed).
static func _perception_hearing(results: Array) -> void:
	var p := _mk(0.0, 360.0, 8.0, 0.2, 3.0, false)  # sight disabled for this test
	var eye := Vector3.ZERO
	# Just out of the 0.5-intensity reach (8 * (0.4+0.3) = 5.6): no wake.
	p.note_noise(Vector3(6.0, 0.0, 0.0), 0.5, eye)
	_check(results, "distant noise does not wake the enemy",
			p.status == EnemyPerception.Status.UNAWARE, p.get_status_name())
	p.note_noise(Vector3(4.0, 0.0, 0.0), 0.5, eye)
	_check(results, "nearby noise pulls the enemy into INVESTIGATING",
			p.status == EnemyPerception.Status.INVESTIGATING, p.get_status_name())
	_check(results, "investigation point is the noise source",
			p.investigate_point() == Vector3(4.0, 0.0, 0.0), str(p.investigate_point()))
	_check(results, "investigate_done at the noise point", p.investigate_done(Vector3(4.0, 0.0, 0.0)))
	p.clear_investigation()
	_check(results, "clearing the investigation returns to UNAWARE",
			p.status == EnemyPerception.Status.UNAWARE, p.get_status_name())
	# A loud hit cuts the reaction beat in half.
	var p2 := _mk(10.0, 360.0, 8.0, 0.4, 3.0, false)
	p2.update(0.1, eye, Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0), true)
	_check(results, "precondition: REACTING with 0.4 s reaction",
			p2.status == EnemyPerception.Status.REACTING, p2.get_status_name())
	p2.note_noise(Vector3(3.0, 0.0, 0.0), 1.0, eye)
	p2.update(0.21, eye, Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0), true)
	_check(results, "noise cuts the reaction beat (engaged sooner than 0.4 s)",
			p2.status == EnemyPerception.Status.ENGAGED, p2.get_status_name())


## A line-of-sight gate blocks sight even inside range + FOV.
static func _perception_los(results: Array) -> void:
	var p := _mk(10.0, 360.0, 0.0, 0.2, 3.0, false)
	var blocked := func(_a: Vector3, _b: Vector3) -> bool: return false
	p.set_los_check(blocked)
	var eye := Vector3.ZERO
	var visible := p.visible_now(eye, Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0))
	_check(results, "LOS callable blocks sight through cover", not visible)
	p.set_los_check(Callable())
	var visible2 := p.visible_now(eye, Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0))
	_check(results, "with no LOS gate the same point is visible", visible2)


## FOV cone: only what is in front of the facing direction is seen.
static func _perception_fov(results: Array) -> void:
	var p := _mk(10.0, 90.0, 0.0, 0.2, 3.0, false)
	var eye := Vector3.ZERO
	var facing := Vector3(1.0, 0.0, 0.0)
	_check(results, "target in front of the FOV is seen",
			p.visible_now(eye, facing, Vector3(5.0, 0.0, 0.0)))
	_check(results, "target beside the FOV edge is seen (>=45 deg)",
			p.visible_now(eye, facing, Vector3(4.0, 0.0, 3.0)))
	_check(results, "target behind is NOT seen",
			not p.visible_now(eye, facing, Vector3(-5.0, 0.0, 0.0)))
	_check(results, "target at 90 deg is NOT seen",
			not p.visible_now(eye, facing, Vector3(0.0, 0.0, 5.0)))


## Engaged -> sight lost -> investigation at the last seen point -> forget.
static func _perception_memory_and_investigation(results: Array) -> void:
	var p := _mk(10.0, 360.0, 0.0, 0.2, 3.0, false)
	var eye := Vector3.ZERO
	var facing := Vector3(1.0, 0.0, 0.0)
	for _i in range(16):
		p.update(0.016, eye, facing, Vector3(5.0, 0.0, 0.0), true)
	_check(results, "precondition: ENGAGED", p.status == EnemyPerception.Status.ENGAGED)
	# Target breaks cover (beyond the 10 m vision range).
	p.update(0.016, eye, facing, Vector3(100.0, 0.0, 0.0), true)
	_check(results, "losing sight starts INVESTIGATING", p.status == EnemyPerception.Status.INVESTIGATING,
			p.get_status_name())
	_check(results, "investigates the LAST SEEN position",
			p.investigate_point() == Vector3(5.0, 0.0, 0.0), str(p.investigate_point()))
	for _i in range(220):  # ~3.5 s > 3.0 s memory
		p.update(0.016, eye, facing, Vector3(100.0, 0.0, 0.0), true)
	_check(results, "memory expires back to UNAWARE", p.status == EnemyPerception.Status.UNAWARE,
			p.get_status_name())


## Spotting the target while investigating commits instantly (no reaction beat).
static func _perception_spot_while_investigating(results: Array) -> void:
	# Hearing must be enabled for the noise stimulus to wake this enemy.
	var p := _mk(10.0, 360.0, 8.0, 0.2, 3.0, false)
	var eye := Vector3.ZERO
	var facing := Vector3(1.0, 0.0, 0.0)
	p.note_noise(Vector3(5.0, 0.0, 0.0), 1.0, eye)
	_check(results, "noise starts investigation", p.status == EnemyPerception.Status.INVESTIGATING,
			p.get_status_name())
	p.update(0.016, eye, facing, Vector3(5.0, 0.0, 0.0), true)  # spot it there
	_check(results, "spotting while investigating engages instantly",
			p.status == EnemyPerception.Status.ENGAGED, p.get_status_name())


## Legacy detect_range == 0 behavior: always aware, engages on the first frame.
static func _perception_always_aware(results: Array) -> void:
	var p := _mk(0.0, 360.0, 0.0, 0.2, 3.0, true)
	p.update(0.016, Vector3.ZERO, Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0), true)
	_check(results, "always-aware archetype engages on first frame",
			p.status == EnemyPerception.Status.ENGAGED, p.get_status_name())
	# A dead/vanished target resets the brain.
	p.update(0.016, Vector3.ZERO, Vector3(1.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0), false)
	_check(results, "missing target resets to UNAWARE", p.status == EnemyPerception.Status.UNAWARE)
