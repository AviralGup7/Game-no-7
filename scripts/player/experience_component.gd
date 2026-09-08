class_name ExperienceComponent
extends Node

## Run-scoped XP + levels: kills and XP gems feed XP, thresholds trigger
## level-ups that unlock skills (via SkillController hooks) and grant small
## Choice-free boons (heal + stamina refill) so levelling feels good even
## before the skill UI is opened. Curve is exponential-but-capped; all tuning
## is consts so tests assert exact thresholds.

signal xp_changed(xp: int, level: int, xp_into_level: int, xp_for_level: int)
signal leveled_up(new_level: int)

const BASE_XP_FOR_LEVEL_2 := 60
const GROWTH := 1.45
const MAX_LEVEL := 20
const LEVEL_HEAL_FRACTION := 0.15

var _xp := 0
var _level := 1
var _xp_multiplier := 1.0
var _owner_body: Node = null


func _ready() -> void:
	_owner_body = get_parent()


## XP required to go from `level` to `level+1` (level >= 1).
static func xp_for_level(level: int) -> int:
	if level < 1:
		return BASE_XP_FOR_LEVEL_2
	var req := float(BASE_XP_FOR_LEVEL_2) * pow(GROWTH, float(level - 1))
	return maxi(int(round(req)), 1)


## Total XP needed to HAVE REACHED `level` from level 1.
static func total_xp_for_level(level: int) -> int:
	var total := 0
	for l in range(1, maxi(level, 1)):
		total += xp_for_level(l)
	return total


## Level implied by a lifetime total (inverse of the curve; pure).
static func level_for_total_xp(total_xp: int) -> int:
	var remaining := maxi(total_xp, 0)
	var level := 1
	while level < MAX_LEVEL:
		var need := xp_for_level(level)
		if remaining < need:
			break
		remaining -= need
		level += 1
	return level


func set_xp_multiplier(mult: float) -> void:
	_xp_multiplier = clampf(mult, 0.0, 10.0)


## Add XP (kills, gems). Returns the number of level-ups triggered.
func add_xp(amount: float) -> int:
	if amount <= 0.0 or _level >= MAX_LEVEL:
		return 0
	_xp += int(round(amount * _xp_multiplier))
	var ups := 0
	while _level < MAX_LEVEL and _xp_into_level() >= xp_for_level(_level):
		_xp -= xp_for_level(_level)
		_level += 1
		ups += 1
		_on_level_up()
	xp_changed.emit(_xp, _level, _xp_into_level(), xp_for_level(_level))
	return ups


func _xp_into_level() -> int:
	return _xp


func get_xp() -> int:
	return total_xp_earned() - total_xp_for_level(_level)


func total_xp_earned() -> int:
	return total_xp_for_level(_level) + _xp


func get_level() -> int:
	return _level


func get_fraction_into_level() -> float:
	if _level >= MAX_LEVEL:
		return 1.0
	return clampf(float(_xp) / float(maxi(xp_for_level(_level), 1)), 0.0, 1.0)


func is_max_level() -> bool:
	return _level >= MAX_LEVEL


func _on_level_up() -> void:
	# Small automatic boon: heal a slice + refill stamina.
	if _owner_body != null:
		var hp := _owner_body.get_node_or_null("HealthComponent") as HealthComponent
		if hp != null:
			hp.heal(hp.get_max() * LEVEL_HEAL_FRACTION)
		var st := _owner_body.get_node_or_null("StaminaComponent") as StaminaComponent
		if st != null:
			st.restore_full()
		_unlock_skills_for_level()
	leveled_up.emit(_level)
	if EventBus != null:
		EventBus.player_leveled_up.emit(_level, _xp)
	AudioManager.play_sfx(&"level_up", -8.0)


func _unlock_skills_for_level() -> void:
	var skills := _owner_body.get_node_or_null("SkillController") as SkillController if _owner_body != null and is_instance_valid(_owner_body) else null
	if skills == null:
		return
	for cfg in ContentRegistry.get_all_skill_configs():
		var sc := cfg as SkillConfig
		if sc != null and _level >= sc.unlock_level and not sc.disabled:
			skills.unlock_skill(sc.skill_id)


func reset_for_new_run() -> void:
	_xp = 0
	_level = 1
	_xp_multiplier = 1.0
	xp_changed.emit(_xp, _level, _xp_into_level(), xp_for_level(_level))


func get_debug_snapshot() -> Dictionary:
	return {"level": _level, "xp": _xp, "need": xp_for_level(_level), "total": total_xp_earned()}

