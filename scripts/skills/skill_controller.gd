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

var _slots: Array = [null, null, null] # SkillConfig or null
var _cooldowns: Array[float] = [0.0, 0.0, 0.0]
var _current_wave := 1
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


## Copy build modifiers into the executor without giving it ownership of
## ProgressionComponent or mutating any shared SkillConfig resource.
func set_combat_modifiers(skill_damage: float = 1.0, area_radius: float = 1.0, area_damage: float = 1.0, status_chance: float = 0.0) -> void:
	_executor.set_combat_modifiers(skill_damage, area_radius, area_damage, status_chance)


## Bind a config to a slot (locked until unlock_skill unless `unlocked`).
func assign_skill(config: SkillConfig, slot: int, unlocked: bool = false) -> bool:
	if config == null or not config.validate().is_empty() or config.disabled:
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
	if ContentRegistry == null:
		return false
	var cfg: SkillConfig = ContentRegistry.get_skill(skill_id)
	if cfg == null or not cfg.validate().is_empty() or cfg.disabled or _current_wave < cfg.unlock_wave:
		return false
	var level := _current_level()
	# _current_level returns -1 when no ExperienceComponent is present (headless
	# tests). Treat unknown level as blocked for any non-trivial level gate so
	# skills do not unlock for free outside the intended progression.
	if level < cfg.unlock_level:
		return false
	_unlocked[skill_id] = true
	skill_unlock_changed.emit(skill_id, true)
	if EventBus != null:
		EventBus.skill_unlocked.emit(skill_id)
	return true


func is_unlocked(skill_id: StringName) -> bool:
	return bool(_unlocked.get(skill_id, false))


func set_current_wave(wave_number: int) -> void:
	_current_wave = maxi(wave_number, 1)


## Unlock every registry skill whose level and wave gates are now satisfied. This
## catches a level-up before its wave as well as a wave-up after its level-up.
func unlock_available() -> int:
	if ContentRegistry == null:
		return 0
	var unlocked_count := 0
	for raw in ContentRegistry.get_all_skill_configs():
		var cfg := raw as SkillConfig
		if cfg != null and _current_wave >= cfg.unlock_wave and _current_level() >= cfg.unlock_level:
			if unlock_skill(cfg.skill_id):
				unlocked_count += 1
	return unlocked_count


func _current_level() -> int:
	if _owner_body == null:
		return -1
	var experience := _owner_body.get_node_or_null("ExperienceComponent") as ExperienceComponent
	if experience != null:
		return experience.get_level()
	return -1


## Stable assigned-skill mirror for RunState save summaries. Locked skills remain
## part of the loadout; unlock state stays in this controller.
func get_assigned_skill_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for raw in _slots:
		var cfg := raw as SkillConfig
		if cfg != null:
			ids.append(cfg.skill_id)
	return ids


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
					if AudioManager != null:
						AudioManager.play_sfx(&"skill_ready", -12.0)


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
	if AudioManager != null:
		AudioManager.play_sfx(&"skill_cast", -8.0, 1.0 + 0.05 * slot)
	return true


func _is_caster_stunned() -> bool:
	if _owner_body == null:
		return false
	var sm := _owner_body.get_node_or_null("StatusManager") as StatusManager
	return sm != null and sm.is_stunned()


func _pay_stamina(cfg: SkillConfig) -> bool:
	if cfg.stamina_cost <= 0.0:
		return true
	if _owner_body == null:
		return true  # no owner bound: skills are free
	if _owner_body is Player:
		return (_owner_body as Player).try_spend_stamina(cfg.stamina_cost)
	return true  # non-Player owners (tests) have no stamina: skills are free


func _enemies() -> Array:
	if not is_inside_tree():
		return []
	return get_tree().get_nodes_in_group(ENEMY_GROUP)


func reset_for_new_run() -> void:
	_cooldowns.fill(0.0)
	_executor.reset_scheduled()
	# A new run starts from neutral skill tuning; PlayerBuild reapplies any
	# permanent/run modifiers immediately after this reset.


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

