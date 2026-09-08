class_name BossController
extends Node

## Multi-phase boss brain attached beside EnemyBase on boss archetypes.
## Watches the boss's health fraction and advances phases at thresholds; each
## phase applies stat modifiers, fires telegraphed slams / charges / summons and
## opens recovery windows, and drives the BossHealthBar + announcement UI via
## EventBus (boss_spawned / boss_phase_changed / boss_slain) — the UI binds the
## same events, so this controller never touches UI nodes directly. Phases are
## data-driven: author BossPhaseConfig entries on the node (phase_plan) or fall
## back to the built-in three-phase plan.
##
## Determinism: ability selection uses a RandomNumberGenerator seeded from the run
## seed passed to begin_fight(), so replays reproduce the same fight.
##
## Expected host layout: parent = boss EnemyBase with HealthComponent child.

signal phase_advanced(phase: int, max_phases: int)
signal telegraph_started(kind: StringName, duration: float)
signal summon_requested(archetype_id: StringName, count: int)

const BOSS_GROUP := "boss"
const TELEGRAPH_SLAM := &"slam"
const TELEGRAPH_CHARGE := &"charge"
const TELEGRAPH_SUMMON := &"summon"
const TELEGRAPH_RECOVER := &"recover"

const SLAM_RADIUS := 3.5
const SLAM_TELEGRAPH := 0.8
const SLAM_RECOVERY := 0.7
const CHARGE_TELEGRAPH := 0.6
const CHARGE_TIME := 0.55
const CHARGE_SPEED_MULT := 4.2
const CHARGE_LENGTH := 9.0
const CHARGE_HALF_WIDTH := 1.7
const CHARGE_RECOVERY := 0.9
const SUMMON_TELEGRAPH := 1.0
const SUMMON_RECOVERY := 0.5
const DEFAULT_ABILITY_INTERVAL := 4.0
const ENRAGED_ABILITY_INTERVAL := 2.6
const PHASE_STAGGER := 0.8

var _host: EnemyBase = null
var _health: Node = null
var _phases: Array = []        # [{threshold, name, damage_mult, speed_mult, abilities, interval}]
var _phase := 0                # 0-based index of the CURRENT phase
var _enraged := false
var _ability_cooldown := 0.0
var _telegraph_left := 0.0
var _telegraph_kind := &""
var _telegraph_target := Vector3.ZERO
var _charge_left := 0.0
var _charge_dir := Vector3.FORWARD
var _charge_origin := Vector3.ZERO
var _announced_intro := false
var _rng := RandomNumberGenerator.new()

## Authored phase plan. Empty = use _default_phases().
@export var phase_plan: Array[BossPhaseConfig] = []


func _ready() -> void:
	_host = get_parent() as EnemyBase
	if _host != null:
		_host.add_to_group(BOSS_GROUP)
		_health = _host.get_node_or_null("HealthComponent")
		if _health != null and _health.has_signal("health_changed"):
			_health.health_changed.connect(_on_health_changed)
		if _host.has_signal("died"):
			_host.died.connect(_on_boss_died)
	if _phases.is_empty():
		if not phase_plan.is_empty():
			var authored: Array = []
			for entry in phase_plan:
				if entry != null:
					authored.append(entry.to_dict())
			configure_phases(authored if not authored.is_empty() else _default_phases())
		else:
			configure_phases(_default_phases())


func _eb() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")


## Phases sorted by descending threshold; phase 0 is the intro phase (1.0).
func configure_phases(phases: Array) -> void:
	_phases = phases.duplicate()
	_phases.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("threshold", 0.0)) > float(b.get("threshold", 0.0)))
	_phase = 0


func _default_phases() -> Array:
	return [
		{"threshold": 1.0, "name": "Awakening", "damage_mult": 1.0, "speed_mult": 1.0, "abilities": [&"slam"], "interval": 0.0},
		{"threshold": 0.66, "name": "Fury", "damage_mult": 1.25, "speed_mult": 1.1, "abilities": [&"slam", &"summon"], "interval": 0.0},
		{"threshold": 0.33, "name": "Enrage", "damage_mult": 1.5, "speed_mult": 1.25, "abilities": [&"slam", &"summon", &"charge"], "interval": 0.0},
	]


## Pure phase lookup used by the controller and headless tests: the phase whose
## threshold is the lowest one still >= frac, in descending-sorted `phases`.
static func phase_index_for_fraction(frac: float, phases: Array) -> int:
	if phases.is_empty():
		return 0
	var clamped := clampf(frac, 0.0, 1.0)
	var target := 0
	for i in range(phases.size()):
		var th := float(phases[i].get("threshold", 0.0))
		if not is_finite(th):
			continue
		th = clampf(th, 0.0, 1.0)
		if clamped <= th:
			target = i
	return clampi(target, 0, phases.size() - 1)


func current_phase() -> int:
	return _phase


func max_phases() -> int:
	return _phases.size()


func phase_name() -> String:
	if _phases.is_empty():
		return "Boss"
	return String(_phases[clampi(_phase, 0, _phases.size() - 1)].get("name", "Boss"))


func is_enraged() -> bool:
	return _enraged


## Called by the spawner once the boss is initialized + in the tree. Seeds the
## ability RNG from the run seed so the fight is replay-deterministic.
func begin_fight(run_seed: int = 0) -> void:
	if _announced_intro or _host == null:
		return
	_announced_intro = true
	_rng.seed = (run_seed * 31 + hash(String(_host.get_archetype_id()))) & 0x7FFFFFFF
	_ability_cooldown = 2.0
	var bus := _eb()
	if bus != null:
		bus.boss_spawned.emit(_host, _host.get_archetype_id())
		bus.announcement.emit(&"boss_spawned", "%s has entered the arena!" % _display_name(), &"danger")
	if AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx(&"boss_spawned", -6.0)


func _display_name() -> String:
	var cfg := _host.get_config() if _host != null else null
	if cfg != null and not String(cfg.display_name).is_empty():
		return String(cfg.display_name)
	return "Boss"


func _physics_process(delta: float) -> void:
	if _host == null or not _host.is_alive():
		return
	if not _announced_intro:
		return
	# A charge in flight resolves on completion, ignoring the normal cadence.
	if _charge_left > 0.0:
		_charge_left -= delta
		if _charge_left <= 0.0:
			_resolve_charge_impact()
			_begin_recovery(CHARGE_RECOVERY)
		return
	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		if _telegraph_left <= 0.0:
			_resolve_telegraph()
		return
	_ability_cooldown -= delta
	if _ability_cooldown <= 0.0:
		_trigger_ability()


func _on_health_changed(current: float, maximum: float) -> void:
	if _host == null or not is_finite(current) or not is_finite(maximum) or maximum <= 0.0:
		return
	# Phases belong to the fight. Health traffic before begin_fight() is setup
	# noise (spawn, difficulty scaling, max-health resets) and must never burn a
	# phase transition — advancement is one-way, so a spurious early jump would
	# leave the boss permanently enraged.
	if not _announced_intro:
		return
	var frac := clampf(current / maximum, 0.0, 1.0)
	var target := phase_index_for_fraction(frac, _phases)
	if target > _phase:
		_advance_to(target)


func _advance_to(index: int) -> void:
	_phase = clampi(index, 0, _phases.size() - 1)
	var data: Dictionary = _phases[_phase]
	# Phase stat bump via difficulty scaling (multiplies on top of wave scaling).
	if _host.has_method("apply_phase_modifiers"):
		_host.call("apply_phase_modifiers", float(data.get("damage_mult", 1.0)), float(data.get("speed_mult", 1.0)))
	# Enrage on the final phase: cleanse control effects + roar.
	if _phase >= _phases.size() - 1 and not _enraged:
		_enraged = true
		var sm := _host.get_node_or_null("StatusManager")
		if sm != null and sm.has_method("cleanse_all"):
			sm.call("cleanse_all", true)
	# Phase transition stagger: the boss reels, giving a short breathing room.
	if _host != null:
		_host.set_move_override(Vector3.ZERO, 0.0, PHASE_STAGGER)
		# Cosmetics must never gate the phase transition itself. _apply_phase_visuals
		# creates tweens, which fail on a node that is not inside the tree (and
		# during teardown); letting that abort _advance_to would apply the stat
		# bumps but never emit phase_advanced, desyncing every listener (UI, audio,
		# analytics) from the boss's actual phase.
		if _host.is_inside_tree():
			_apply_phase_visuals(_phase)
	phase_advanced.emit(_phase, _phases.size())
	var bus := _eb()
	if bus != null:
		bus.boss_phase_changed.emit(_host, _phase, _phases.size())
		bus.announcement.emit(&"boss_phase", "%s: %s!" % [_display_name(), phase_name()], &"warning")
	if AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx(&"boss_phase_changed", -7.0, 1.0 + 0.08 * _phase)
	# A short pause before the phase's first ability so the change is felt.
	_ability_cooldown = 0.8


func _apply_phase_visuals(phase: int) -> void:
	# Guarded: create_tween() requires a node inside the tree. Bail out rather than
	# let a cosmetic failure propagate back into the phase-transition path.
	if _host == null or not _host.is_inside_tree():
		return
	var feedback := _host.get_node_or_null("EnemyFeedback")
	var tint := Color.WHITE
	match phase:
		0:
			tint = Color(1, 1, 1) # Awakening — keep authored tint
			# No recolour; just a pulse
		1:
			tint = Color(1.0, 0.55, 0.22) # Fury — warm orange
		2:
			tint = Color(1.0, 0.28, 0.12) # Enrage — hot red with emissive in feedback
		_:
			tint = Color(1.0, 0.62, 0.18)
	if phase > 0 and feedback != null and feedback.has_method("recolor"):
		feedback.call("recolor", tint)
	# Scale bump for readability on mobile
	var vr := _host.get_node_or_null("VisualRoot") as Node3D
	if vr != null:
		var target := 1.0 + 0.12 * float(phase)
		var tw := vr.create_tween()
		tw.tween_property(vr, "scale", Vector3.ONE * target, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Burst via EffectDirector (handled through bus) — also add local light pulse
	var light := _host.get_node_or_null("BossPhaseLight") as OmniLight3D
	if light == null:
		light = OmniLight3D.new()
		light.name = "BossPhaseLight"
		_host.add_child(light)
	light.light_color = tint if phase > 0 else Color(1.0, 0.82, 0.35)
	light.omni_range = 5.0 + 1.5 * float(phase)
	light.light_energy = 1.2 + 0.5 * float(phase)
	light.position.y = 1.8
	light.visible = true
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", light.light_energy * 1.6, 0.18)
	lt.tween_property(light, "light_energy", light.light_energy, 0.45)


func _trigger_ability() -> void:
	var data: Dictionary = _phases[clampi(_phase, 0, _phases.size() - 1)] if not _phases.is_empty() else {}
	var abilities: Array = data.get("abilities", [&"slam"])
	_ability_cooldown = _ability_interval(data)
	var pick := String(abilities[_rng.randi_range(0, abilities.size() - 1)]) if not abilities.is_empty() else "slam"
	var target := _host.get_move_target()
	var aim := target.global_position if target != null else _host.global_position + Vector3.FORWARD * 4.0
	match pick:
		"slam":
			_begin_telegraph(TELEGRAPH_SLAM, SLAM_TELEGRAPH, aim)
		"charge":
			_begin_telegraph(TELEGRAPH_CHARGE, CHARGE_TELEGRAPH, aim)
		"summon":
			_begin_telegraph(TELEGRAPH_SUMMON, SUMMON_TELEGRAPH, _host.global_position)
		_:
			_begin_telegraph(TELEGRAPH_SLAM, SLAM_TELEGRAPH, aim)


func _ability_interval(data: Dictionary) -> float:
	var authored := float(data.get("interval", 0.0))
	if authored > 0.0:
		return authored
	return ENRAGED_ABILITY_INTERVAL if _enraged else DEFAULT_ABILITY_INTERVAL


## Telegraph: root the boss in place for the tell's duration (movement override),
## then resolve. The locked target position is what makes slams dodgeable.
func _begin_telegraph(kind: StringName, duration: float, at: Vector3) -> void:
	_telegraph_kind = kind
	_telegraph_left = duration
	_telegraph_target = at
	if _host != null:
		_host.set_move_override(Vector3.ZERO, 0.0, duration)
	telegraph_started.emit(kind, duration)


## Recovery window: rooted + no abilities for `duration` (the punish window).
func _begin_recovery(duration: float) -> void:
	if _host != null:
		_host.set_move_override(Vector3.ZERO, 0.0, duration)
	telegraph_started.emit(TELEGRAPH_RECOVER, duration)
	_ability_cooldown = maxf(_ability_cooldown, duration)


func _resolve_telegraph() -> void:
	match _telegraph_kind:
		TELEGRAPH_SLAM:
			_resolve_slam()
			_begin_recovery(SLAM_RECOVERY)
		TELEGRAPH_CHARGE:
			_resolve_charge()
		TELEGRAPH_SUMMON:
			_resolve_summon()
			_begin_recovery(SUMMON_RECOVERY)
	_telegraph_kind = &""


func _resolve_slam() -> void:
	var dmg := _host.get_effective_attack_damage() * 2.0
	var victims: Array = []
	if _host.get_move_target() != null:
		victims = [_host.get_move_target()]
	AreaDamage.apply_radial(victims, _telegraph_target, SLAM_RADIUS, dmg, _host, _host.get_archetype_id(), 14.0, true, AreaDamage.FALLOFF_LINEAR)


## Charge: lock the direction at release, then travel for CHARGE_TIME at high
## speed (movement override drives the body); impact resolves when it ends.
func _resolve_charge() -> void:
	var dir: Vector3 = _telegraph_target - _host.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	_charge_dir = dir.normalized()
	_charge_origin = _host.global_position
	_charge_left = CHARGE_TIME
	_host.set_move_override(_charge_dir, _host.get_effective_speed() * CHARGE_SPEED_MULT, CHARGE_TIME)
	_host.face_direction(_charge_dir)


func _resolve_charge_impact() -> void:
	var victims: Array = []
	if _host.get_move_target() != null:
		victims = [_host.get_move_target()]
	var travelled := _charge_origin.distance_to(_host.global_position)
	var length := maxf(travelled, CHARGE_LENGTH * 0.5)
	AreaDamage.apply_line(victims, _charge_origin, _charge_dir, length, CHARGE_HALF_WIDTH,
		_host.get_effective_attack_damage() * 1.5, _host, _host.get_archetype_id(), 16.0)


func _resolve_summon() -> void:
	summon_requested.emit(&"basic", 2 if not _enraged else 3)


func _exit_tree() -> void:
	# Prevent stale boss health_changed/died connections after despawn/reuse.
	if _health != null and _health.has_signal("health_changed") and _health.health_changed.is_connected(_on_health_changed):
		_health.health_changed.disconnect(_on_health_changed)
	if _host != null and _host.has_signal("died") and _host.died.is_connected(_on_boss_died):
		_host.died.disconnect(_on_boss_died)


func _on_boss_died() -> void:
	_telegraph_left = 0.0
	_telegraph_kind = &""
	_charge_left = 0.0
	if _host != null:
		_host.clear_move_override()
	var bus := _eb()
	if bus != null:
		bus.boss_slain.emit(_host.get_archetype_id() if _host != null else &"boss")
		bus.announcement.emit(&"boss_slain", "%s defeated!" % _display_name(), &"victory")
	if AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx(&"boss_slain", -6.0)


func get_debug_snapshot() -> Dictionary:
	return {
		"phase": _phase,
		"max_phases": _phases.size(),
		"phase_name": phase_name(),
		"enraged": _enraged,
		"telegraph": String(_telegraph_kind),
	}

## Hardened: clamp boss threshold to prevent phase skip.
func _validated_threshold(t: float) -> float:
	if not is_finite(t):
		return 0.0
	return clampf(t, 0.0, 1.0)

