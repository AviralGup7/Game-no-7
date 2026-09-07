class_name SkillController
extends Node

## Player-side active-skill loadout (3 slots bound to skill_1..3 actions).
## Owns slots, cooldown timers, unlocks, stamina costs, and cast gating; behavior
## execution (damage, scheduled whirl hits, dash movement) lives in SkillExecutor.
## The SkillBar UI reads state through the getters below. Headless-safe: every
## engine/autoload touch is guarded.

signal skill_cast_local(skill_id: StringName, slot: int)
signal skill_cooldown_started(skill_id: StringName, duration: float)
signal skill_became_ready(skill_id: StringName)
signal skill_unlock_changed(skill_id: StringName, unlocked: bool)

const SKILL_SLOTS := 3
const ENEMY_GROUP := "enemies"

var _slots: Array = []          # SkillConfig or null
var _cooldowns: Array[float] = []
var _unlocked: Dictionary = {}  # StringName -> bool
var _enabled := true
var _cooldown_multiplier := 1.0
var _owner_body: Node3D = null
var _rng := RngService.new()
var _executor := SkillExecutor.new()


func _ready() -> void:
	_slots.resize(SKILL_SLOTS)
	_slots.fill(null)
	_cooldowns.resize(SKILL_SLOTS)
	_cooldowns.fill(0.0)
	_owner_body = get_parent() as Node3D
	_executor.bind(_owner_body, _rng)


func configure(run_seed: int) -> void:
	_rng.reseed(run_seed)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func set_cooldown_multiplier(mult: float) -> void:
	_cooldown_multiplier = clampf(mult, 0.05, 4.0)


## Bind a config to a slot (locked until unlock_skill unless `unlocked`).
func assign_skill(config: SkillConfig, slot: int, unlocked: bool = false) -> bool:
	if config == null:
		return false
	slot = clampi(slot, 0, SKILL_SLOTS - 1)
	_slots[slot] = config
	_cooldowns[slot] = 0.0
	_unlocked[config.skill_id] = unlocked
	skill_unlock_changed.emit(config.skill_id, unlocked)
	return true


func assign_skill_by_id(skill_id: StringName, slot: int, unlocked: bool = false) -> bool:
	if ContentRegistry == null:
		return false
	var cfg: SkillConfig = ContentRegistry.get_skill(skill_id)
	if cfg == null:
		return false
	return assign_skill(cfg, slot, unlocked)


func unlock_skill(skill_id: StringName) -> bool:
	if _unlocked.get(skill_id, false):
		return false
	_unlocked[skill_id] = true
	skill_unlock_changed.emit(skill_id, true)
	if EventBus != null:
		EventBus.skill_unlocked.emit(skill_id)
	return true


func is_unlocked(skill_id: StringName) -> bool:
	return bool(_unlocked.get(skill_id, false))


func slot_skill(slot: int) -> SkillConfig:
	if slot < 0 or slot >= _slots.size():
		return null
	return _slots[slot] as SkillConfig


func slot_cooldown(slot: int) -> float:
	if slot < 0 or slot >= _cooldowns.size():
		return 0.0
	return maxf(_cooldowns[slot], 0.0)


func slot_cooldown_fraction(slot: int) -> float:
	var cfg := slot_skill(slot)
	if cfg == null or cfg.cooldown <= 0.0:
		return 0.0
	return clampf(slot_cooldown(slot) / (cfg.cooldown * _cooldown_multiplier), 0.0, 1.0)


func is_slot_ready(slot: int) -> bool:
	var cfg := slot_skill(slot)
	if cfg == null or not is_unlocked(cfg.skill_id):
		return false
	return slot_cooldown(slot) <= 0.0


func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_executor.tick(delta, _enemies())
	if not _enabled:
		return
	_poll_inputs()


func _poll_inputs() -> void:
	for slot in range(SKILL_SLOTS):
		var cfg := slot_skill(slot)
		if cfg == null:
			continue
		var action := String(cfg.input_action)
		if action.is_empty():
			continue
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			try_cast_slot(slot)


func _tick_cooldowns(delta: float) -> void:
	for slot in range(_cooldowns.size()):
		if _cooldowns[slot] > 0.0:
			_cooldowns[slot] = maxf(_cooldowns[slot] - delta, 0.0)
			if _cooldowns[slot] <= 0.0:
				var cfg := slot_skill(slot)
				if cfg != null:
					skill_became_ready.emit(cfg.skill_id)
					if EventBus != null:
						EventBus.skill_ready.emit(cfg.skill_id)


## Attempt to cast the skill in `slot`. Returns false with no side effects when
## locked, on cooldown, unaffordable, stunned, or misconfigured.
func try_cast_slot(slot: int) -> bool:
	if not _enabled:
		return false
	var cfg := slot_skill(slot)
	if cfg == null or not is_unlocked(cfg.skill_id):
		return false
	if slot_cooldown(slot) > 0.0:
		return false
	if _is_caster_stunned():
		return false
	if not _pay_stamina(cfg):
		return false
	_cooldowns[slot] = cfg.cooldown * _cooldown_multiplier
	skill_cooldown_started.emit(cfg.skill_id, _cooldowns[slot])
	_executor.execute(cfg, _enemies())
	skill_cast_local.emit(cfg.skill_id, slot)
	if EventBus != null:
		EventBus.skill_cast.emit(cfg.skill_id, _owner_body)
	return true


func _is_caster_stunned() -> bool:
	if _owner_body == null:
		return false
	var sm := _owner_body.get_node_or_null("StatusManager")
	return sm != null and sm.has_method("is_stunned") and bool(sm.call("is_stunned"))


func _pay_stamina(cfg: SkillConfig) -> bool:
	if cfg.stamina_cost <= 0.0:
		return true
	if _owner_body == null or not _owner_body.has_method("try_spend_stamina"):
		return true  # no stamina system wired: skills are free
	return bool(_owner_body.call("try_spend_stamina", cfg.stamina_cost))


func _enemies() -> Array:
	if not is_inside_tree():
		return []
	return get_tree().get_nodes_in_group(ENEMY_GROUP)


func reset_for_new_run() -> void:
	_cooldowns.fill(0.0)
	_executor.reset_scheduled()


func get_debug_snapshot() -> Dictionary:
	var slots: Array = []
	for i in range(SKILL_SLOTS):
		var cfg := slot_skill(i)
		slots.append({
			"skill": String(cfg.skill_id) if cfg != null else "empty",
			"cooldown": slot_cooldown(i),
			"ready": is_slot_ready(i),
		})
	return {"slots": slots, "pending_hits": _executor.pending_hits_count(), "dashing": _executor.is_dashing()}
