class_name BossController
extends Node

## Multi-phase boss brain attached beside EnemyBase on boss archetypes.
## Watches the boss's health fraction and advances phases at thresholds; each
## phase applies stat modifiers, swaps the AI state bias (melee <-> ranged),
## fires telegraphed slams / summons / enrage, and drives the BossHealthBar +
## announcement UI via EventBus. Fully data-driven through BossPhase entries
## configured here or by content (see configure_phases).
##
## Expected host layout: parent = boss EnemyBase with HealthComponent child.

signal phase_advanced(phase: int, max_phases: int)
signal telegraph_started(kind: StringName, duration: float)
signal summon_requested(archetype_id: StringName, count: int)

const BOSS_GROUP := "boss"
const TELEGRAPH_SLAM := &"slam"
const TELEGRAPH_CHARGE := &"charge"
const TELEGRAPH_SUMMON := &"summon"

var _host: EnemyBase = null
var _health: Node = null
var _phases: Array = []        # [{threshold, name, hp_mult, damage_mult, speed_mult, abilities:[]}]
var _phase := 0                # 0-based index of the CURRENT phase
var _enraged := false
var _ability_cooldown := 0.0
var _telegraph_left := 0.0
var _telegraph_kind := &""
var _telegraph_target := Vector3.ZERO
var _announced_intro := false


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
		configure_phases(_default_phases())


## Phases sorted by descending threshold; phase 0 is the intro phase (1.0).
func configure_phases(phases: Array) -> void:
	_phases = phases.duplicate()
	_phases.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("threshold", 0.0)) > float(b.get("threshold", 0.0)))
	_phase = 0


func _default_phases() -> Array:
	return [
		{"threshold": 1.0, "name": "Awakening", "hp_mult": 1.0, "damage_mult": 1.0, "speed_mult": 1.0, "abilities": [&"slam"]},
		{"threshold": 0.66, "name": "Fury", "hp_mult": 1.0, "damage_mult": 1.25, "speed_mult": 1.1, "abilities": [&"slam", &"summon"]},
		{"threshold": 0.33, "name": "Enrage", "hp_mult": 1.0, "damage_mult": 1.5, "speed_mult": 1.25, "abilities": [&"slam", &"summon", &"charge"]},
	]


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


## Called by the spawner once the boss is initialized + in the tree.
func begin_fight() -> void:
	if _announced_intro or _host == null:
		return
	_announced_intro = true
	_ability_cooldown = 2.0
	if EventBus != null:
		EventBus.boss_spawned.emit(_host, _host.get_archetype_id())
		EventBus.announcement.emit(&"boss_spawned", "%s has entered the arena!" % _display_name(), &"danger")


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
	_ability_cooldown -= delta
	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		if _telegraph_left <= 0.0:
			_resolve_telegraph()
		return
	if _ability_cooldown <= 0.0:
		_trigger_ability()


func _on_health_changed(current: float, maximum: float) -> void:
	if _host == null or maximum <= 0.0:
		return
	var frac := clampf(current / maximum, 0.0, 1.0)
	var target := _phase
	for i in range(_phases.size()):
		if frac <= float(_phases[i].get("threshold", 0.0)):
			target = i
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
	phase_advanced.emit(_phase, _phases.size())
	if EventBus != null:
		EventBus.boss_phase_changed.emit(_host, _phase, _phases.size())
		EventBus.announcement.emit(&"boss_phase", "%s: %s!" % [_display_name(), phase_name()], &"warning")
	# Immediate ability so the phase change is felt.
	_ability_cooldown = 0.5


func _trigger_ability() -> void:
	var data: Dictionary = _phases[clampi(_phase, 0, _phases.size() - 1)] if not _phases.is_empty() else {}
	var abilities: Array = data.get("abilities", [&"slam"])
	_ability_cooldown = 4.0 if not _enraged else 2.6
	var pick: String = String(abilities[randi() % abilities.size()]) if not abilities.is_empty() else "slam"
	var target := _host.get_move_target()
	var aim := target.global_position if target != null else _host.global_position + Vector3.FORWARD * 4.0
	match pick:
		"slam":
			_begin_telegraph(TELEGRAPH_SLAM, 0.8, aim)
		"charge":
			_begin_telegraph(TELEGRAPH_CHARGE, 0.6, aim)
		"summon":
			_begin_telegraph(TELEGRAPH_SUMMON, 1.0, _host.global_position)
		_:
			_begin_telegraph(TELEGRAPH_SLAM, 0.8, aim)


func _begin_telegraph(kind: StringName, duration: float, at: Vector3) -> void:
	_telegraph_kind = kind
	_telegraph_left = duration
	_telegraph_target = at
	_host.set_desired_move(Vector3.ZERO, 0.0)
	telegraph_started.emit(kind, duration)


func _resolve_telegraph() -> void:
	match _telegraph_kind:
		TELEGRAPH_SLAM:
			_resolve_slam()
		TELEGRAPH_CHARGE:
			_resolve_charge()
		TELEGRAPH_SUMMON:
			_resolve_summon()
	_telegraph_kind = &""


func _resolve_slam() -> void:
	var dmg := _host.get_effective_attack_damage() * 2.0
	var victims: Array = []
	if _host.get_move_target() != null:
		victims = [_host.get_move_target()]
	AreaDamage.apply_radial(victims, _telegraph_target, 3.5, dmg, _host, _host.get_archetype_id(), 14.0, true, AreaDamage.FALLOFF_LINEAR)


func _resolve_charge() -> void:
	var dir: Vector3 = _telegraph_target - _host.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	_host.set_desired_move(dir.normalized(), _host.get_effective_speed() * 4.0)
	# The charge impact itself is resolved as a short line blast along the path.
	var victims: Array = []
	if _host.get_move_target() != null:
		victims = [_host.get_move_target()]
	AreaDamage.apply_line(victims, _host.global_position, dir.normalized(), 8.0, 1.6, _host.get_effective_attack_damage() * 1.5, _host, _host.get_archetype_id(), 16.0)


func _resolve_summon() -> void:
	summon_requested.emit(&"basic", 2 if not _enraged else 3)


func _on_boss_died() -> void:
	if EventBus != null:
		EventBus.announcement.emit(&"boss_slain", "%s defeated!" % _display_name(), &"victory")


func get_debug_snapshot() -> Dictionary:
	return {
		"phase": _phase,
		"max_phases": _phases.size(),
		"phase_name": phase_name(),
		"enraged": _enraged,
		"telegraph": String(_telegraph_kind),
	}
