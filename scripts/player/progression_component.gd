extends Node
class_name ProgressionComponent

## Owns validated upgrade modifiers and derived stats for a run. Upgrades are applied
## only through apply_upgrade() which validates prerequisites/exclusions/stack limits
## before recording anything. Later systems query derived stats here; the component
## never writes arbitrary node properties.

const STACK_BY_DEFAULT := 99

# upgrade_id -> stack count for the current run.
var _stacks: Dictionary = {}
# accumulated effective modifier values (key -> float).
var _modifiers: Dictionary = {}


func reset() -> void:
	_stacks.clear()
	_modifiers.clear()


func apply_upgrade(config: UpgradeConfig) -> bool:
	if config == null:
		return false
	if config.disabled:
		return false
	if not _meets_prerequisites(config):
		return false
	if _is_excluded(config):
		return false
	var current := int(_stacks.get(config.upgrade_id, 0))
	if current >= config.max_stacks:
		return false
	_stacks[config.upgrade_id] = current + 1
	_accumulate(config)
	return true


func apply_upgrade_by_id(upgrade_id: StringName) -> bool:
	var config: UpgradeConfig = ContentRegistry.get_upgrade(upgrade_id)
	if config == null:
		EventBus.report_warning("apply_upgrade_by_id: unknown upgrade %s" % String(upgrade_id))
		return false
	return apply_upgrade(config)


func _meets_prerequisites(config: UpgradeConfig) -> bool:
	for prereq in config.prerequisites:
		if int(_stacks.get(prereq, 0)) <= 0:
			return false
	return true


func _is_excluded(config: UpgradeConfig) -> bool:
	for excl in config.exclusions:
		if int(_stacks.get(excl, 0)) > 0:
			return true
	return false


func _accumulate(config: UpgradeConfig) -> void:
	for key in config.stat_modifiers:
		var k: StringName = StringName(String(key))
		var v: float = float(config.stat_modifiers[key])
		var accum: float = float(_modifiers.get(k, 0.0))
		accum += _resolve_key_mode(k, v)
		_modifiers[k] = accum


## Multiplier keys replace, additive keys accumulate. Kept central so future keys
## are added in one place.
func _resolve_key_mode(key: StringName, value: float) -> float:
	var multiplicative := [
		&"move_speed_multiplier", &"attack_damage_multiplier",
		&"attack_cooldown_multiplier", &"knockback_multiplier",
	]
	if key in multiplicative:
		# Store as accumulated product? For simplicity phase structure treats these
		# additively and consumers read them as (1 + value). This keeps later phases
		# flexible; document in EXTENDING.
		return value
	return value


## Read an effective derived stat. `base` is the unmodified stat.
func get_stat(key: StringName, base: float) -> float:
	if not _modifiers.has(key):
		return base
	var mod := float(_modifiers[key])
	match key:
		&"max_health_add":
			return base + mod
		&"move_speed_multiplier", &"attack_damage_multiplier":
			return base * (1.0 + mod)
		&"attack_cooldown_multiplier":
			return maxf(base * (1.0 + mod), 0.05)
		&"damage_resistance_add", &"score_multiplier_add", &"currency_multiplier_add", &"healing_on_kill":
			return base + mod
		&"attack_range_add":
			return base + mod
		&"knockback_multiplier":
			return base * (1.0 + mod)
		&"dodge_cooldown_multiplier":
			return maxf(base * (1.0 + mod), 0.05)
	return base


func get_stack_count(upgrade_id: StringName) -> int:
	return int(_stacks.get(upgrade_id, 0))


func has_upgrade(upgrade_id: StringName) -> bool:
	return int(_stacks.get(upgrade_id, 0)) > 0


func get_upgrade_stack_snapshot() -> Dictionary:
	return _stacks.duplicate()


func get_selected_upgrade_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _stacks:
		out.append(StringName(String(key)))
	return out


func get_debug_snapshot() -> Dictionary:
	return {"upgrade_stacks": _stacks.duplicate(), "modifiers": _modifiers.duplicate()}
