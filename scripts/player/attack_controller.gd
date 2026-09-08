extends Node
class_name AttackController

## Owns attack timing and hit resolution for the player's melee weapon. Uses an
## explicit phase machine advanced by `advance(delta)` (called from the owner's physics
## loop) instead of scene Tweens, so a paused/disabled owner freezes the attack exactly
## like the rest of gameplay and `reset_attack_state()` leaves nothing pending behind.
##
## Lifecycle per swing:
##   READY -> request -> WINDUP -> (windup passes) -> RESOLVE hit -> RECOVERY/cooldown
##        -> READY (+ attack_finished)
##
## Light-melee combo: a press during a landed hit's recovery (within `combo_chain_window`)
## chains straight into the next escalating swing (step 2, then 3 by default), skipping
## the cooldown; otherwise the recovery winds down and the combo resets to step 1. Each
## step applies its own damage/knockback multipliers (step 1 = 1.0, so a plain single
## swing is unchanged). Combo state lives in ComboChain; this controller owns timing.
##
## Hit resolution is exactly once per swing; the recovery/cooldown window blocks
## re-fire ("attack spam"). Duplicate target application is prevented because each
## swing resolves a deduped arc result set once.

signal attack_started()
signal attack_finished()
signal attack_hit(target: Node, result: DamageResult)

const PHASE_READY := &"ready"
const PHASE_WINDUP := &"windup"
const PHASE_RECOVERY := &"recovery"

## Attack tuning (derived stats may override range/damage/cooldown via progression).
@export var attack_cooldown: float = 0.55
@export var attack_windup: float = 0.12
@export var attack_range: float = 2.6
@export var attack_damage: float = 12.0
@export var knockback_strength: float = 6.0
@export var can_crit: bool = true
@export var critical_multiplier: float = 1.6
@export var crit_chance: float = 0.15
## Melee arc (degrees). 360 => full circle around the player.
@export var arc_degrees: float = 360.0

## Light-melee combo chain: a second press while a hit's recovery is still inside
## `combo_chain_window` advances into the next escalating swing (higher damage /
## knockback) instead of waiting out the full cooldown. Letting the window lapse or
## reaching `combo_steps` returns to READY and resets the combo to step 1.
@export var combo_steps: int = 3
@export var combo_chain_window: float = 0.35
@export var combo_damage_multipliers: Array[float] = [1.0, 1.2, 1.6]
@export var combo_knockback_multipliers: Array[float] = [1.0, 1.1, 1.4]

const TARGET_GROUP := "enemies"

var _phase: StringName = PHASE_READY
var _elapsed := 0.0
var _crit_roll_source: Callable = Callable()
var _owner_body: CharacterBody3D = null
var _disabled := false
var _chain := ComboChain.new()


func _ready() -> void:
	_owner_body = get_parent() as CharacterBody3D


## Injectable random source: Callable() -> float in [0,1). Defaults to randf().
func set_crit_roll_source(source: Callable) -> void:
	_crit_roll_source = source


func is_attacking() -> bool:
	return _phase != PHASE_READY


func is_on_cooldown() -> bool:
	return _phase == PHASE_RECOVERY


func is_attack_ready() -> bool:
	return _phase == PHASE_READY and not _disabled


func get_phase() -> StringName:
	return _phase


## Disable attacks (e.g. death / modal states). Idempotent.
func set_attacks_enabled(enabled: bool) -> void:
	_disabled = not enabled
	if _disabled:
		reset_attack_state()


## Advance the attack state machine by `delta` (game time, only advanced while the
## owner is active/playing so pausing freezes attacks).
func advance(delta: float) -> void:
	if _disabled:
		return
	if _phase == PHASE_WINDUP:
		_elapsed += delta
		if _elapsed >= maxf(attack_windup, 0.0):
			_elapsed = 0.0
			_resolve_hit()
			_phase = PHASE_RECOVERY
			_chain.open_chain()
	elif _phase == PHASE_RECOVERY:
		_elapsed += delta
		if _elapsed > combo_chain_window:
			# Timing window elapsed without a chained input -> combo can no longer chain;
			# the recovery still has to wind down before the next swing is READY.
			_chain.expire()
		if _elapsed >= _effective_cooldown():
			_finish_attack()


## Request an attack. Returns true when a swing begins:
##   * READY     -> start a fresh combo at step 1.
##   * RECOVERY  -> chain into the next escalating step, but ONLY while the hit is still
##                  inside the chain window and the combo has steps remaining.
## Requests during WINDUP, or during RECOVERY outside the chain window, are rejected.
func request_attack() -> bool:
	if _disabled:
		return false
	var owner := _owner_body
	if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree():
		return false
	if owner.has_method("is_alive") and not bool(owner.call("is_alive")):
		return false
	if _phase == PHASE_READY:
		_begin_swing(1)
		return true
	if _phase == PHASE_RECOVERY:
		# Chain immediately (skip the full cooldown) into the next escalating swing.
		var next := _chain.try_chain(combo_steps)
		if next > 0:
			_begin_swing(next)
			return true
	return false


func _begin_swing(step: int) -> void:
	_chain.begin(step)
	_phase = PHASE_WINDUP
	_elapsed = 0.0
	attack_started.emit()


func _finish_attack() -> void:
	_phase = PHASE_READY
	_elapsed = 0.0
	_chain.finish()
	attack_finished.emit()


## Build + apply the melee damage to everything in range (exactly once per swing).
func _resolve_hit() -> void:
	var owner := _owner_body
	if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree():
		return
	if owner.has_method("is_alive") and not bool(owner.call("is_alive")):
		return

	var origin := owner.global_position
	var forward := _facing_forward(owner)
	var candidates := owner.get_tree().get_nodes_in_group(TARGET_GROUP)
	var range_val := _effective_range()
	var targets := CombatQuery.find_targets_in_arc(origin, forward, candidates, range_val, arc_degrees * 0.5)

	for candidate in targets:
		var t: Node3D = candidate as Node3D
		if t == null:
			continue
		var to_target: Vector3 = (t.global_position - origin) * Vector3(1, 0, 1)
		var dir: Vector3 = Vector3.FORWARD if to_target.length_squared() < 0.0001 else to_target.normalized()
		var payload: DamagePayload = _build_payload(dir)
		if not t.has_method("apply_damage"):
			continue
		var result: Variant = t.call("apply_damage", payload)
		if result is DamageResult:
			attack_hit.emit(t, result)
	# All targets resolved exactly once per swing (CombatQuery dedupes by list order).


func _facing_forward(owner: CharacterBody3D) -> Vector3:
	# Visual forward is -Z of the character; keep Y flat.
	var f := -owner.global_transform.basis.z
	f.y = 0.0
	return f if f.length_squared() > 0.001 else Vector3.FORWARD


## Effective recovery/cooldown after progression (attack_cooldown_multiplier). A
## negative modifier is a REDUCTION; clamped so it never increases or goes below floor.
func _effective_cooldown() -> float:
	if _owner_body == null or not is_instance_valid(_owner_body):
		return maxf(attack_cooldown, 0.05)
	var prog := _owner_body.get_node_or_null("ProgressionComponent")
	if prog != null and prog.has_method("get_stat"):
		return float(prog.call("get_stat", &"attack_cooldown_multiplier", attack_cooldown))
	return maxf(attack_cooldown, 0.05)


func _effective_range() -> float:
	if _owner_body == null or not is_instance_valid(_owner_body):
		return attack_range
	var prog := _owner_body.get_node_or_null("ProgressionComponent")
	if prog != null and prog.has_method("get_stat"):
		return float(prog.call("get_stat", &"attack_range_add", attack_range))
	return attack_range


func _effective_damage() -> float:
	var dmg := attack_damage
	if _owner_body != null and is_instance_valid(_owner_body):
		var prog := _owner_body.get_node_or_null("ProgressionComponent")
		if prog != null and prog.has_method("get_stat"):
			dmg = float(prog.call("get_stat", &"attack_damage_multiplier", attack_damage))
	return dmg


func _roll_crit() -> bool:
	if not can_crit:
		return false
	var chance := clampf(crit_chance, 0.0, 1.0)
	if chance <= 0.0:
		return false
	if _crit_roll_source.is_valid():
		return float(_crit_roll_source.call()) < chance
	return randf() < chance


func _build_payload(direction: Vector3) -> DamagePayload:
	var payload := DamagePayload.new()
	var dmg := _effective_damage()
	var crit := _roll_crit()
	if crit:
		dmg *= maxf(critical_multiplier, 1.0)
		payload.was_critical = true
	# Escalate damage/knockback with the combo step (step 1 multiplier is 1.0, so a
	# plain single swing is unchanged).
	dmg *= _chain.damage_factor(combo_damage_multipliers)
	payload.amount = dmg
	payload.source = _owner_body
	payload.source_id = &"melee"
	payload.damage_type = &"physical"
	payload.can_crit = can_crit
	payload.critical_multiplier = critical_multiplier
	var k := knockback_strength
	if _owner_body != null and is_instance_valid(_owner_body):
		var prog := _owner_body.get_node_or_null("ProgressionComponent")
		if prog != null and prog.has_method("get_stat"):
			k = float(prog.call("get_stat", &"knockback_multiplier", knockback_strength))
	payload.knockback = direction * maxf(k * _chain.knockback_factor(combo_knockback_multipliers), 0.0)
	payload.hit_position = _owner_body.global_position
	return payload


func set_attack_cooldown(value: float) -> void:
	attack_cooldown = maxf(value, 0.05)


func set_attack_damage(value: float) -> void:
	attack_damage = maxf(value, 0.0)


func set_attack_range(value: float) -> void:
	attack_range = maxf(value, 0.5)


## Fully reset the attack state (used on new run / respawn / disable). Because timing
## is internal accumulation (no tweens), nothing lingers after this call.
func reset_attack_state() -> void:
	_phase = PHASE_READY
	_elapsed = 0.0
	_chain.reset()


## Current combo step: 0 when no combo is in progress, else 1..combo_steps.
func get_combo_step() -> int:
	return _chain.step()


## True while the last landed hit can still chain into the next combo step.
func is_chain_ready() -> bool:
	return _chain.is_chain_ready()


func get_debug_snapshot() -> Dictionary:
	return {
		"phase": String(_phase),
		"attacking": is_attacking(),
		"on_cooldown": is_on_cooldown(),
		"attack_cooldown": attack_cooldown,
		"attack_range": attack_range,
		"attack_damage": attack_damage,
		"disabled": _disabled,
		"combo_step": _chain.step(),
		"chain_allowed": _chain.is_chain_ready(),
	}
