extends Node
class_name ProgressionComponent

## Owns validated upgrade modifiers and derived stats for a run. Upgrades are applied
## only through apply_upgrade() which validates prerequisites/exclusions/stack limits
## before recording anything. Later systems query derived stats here; the component
## never writes arbitrary node properties. It is the RUNTIME calculation owner; RunState
## keeps only a serializable mirror (see get_progression_snapshot/restore_progression).
##
## MODIFIER SEMANTICS (single documented model — see docs/EXTENDING.md)
##   * stat_modifiers values are authored in DECIMAL domain:
##       - percentage keys carry a fraction  (0.15 == +15%)
##       - absolute/additive keys carry the literal delta (+20 HP, +0.35 range, +5 heal)
##   * Stacking is ADDITIVE in the modifier domain: N copies sum their per-stack value.
##   * Derived reads (single consistent formula family):
##       multiplicative family  {move_speed_multiplier, attack_damage_multiplier,
##                               knockback_multiplier}
##             derived = base * (1 + Σ)          # +15% damage twice => base * 1.30
##       cooldown family       {attack_cooldown_multiplier, dodge_cooldown_multiplier}
##             derived = base * (1 + Σ)          # Σ<0 is a REDUCTION; never increases
##             clamped >= MIN_COOLDOWN so cooldowns never hit 0 or go negative
##       additive family       {max_health_add, attack_range_add, healing_on_kill,
##                              score_multiplier_add, currency_multiplier_add}
##             derived = base + Σ
##       resistance            damage_resistance_add   clamped to [0,1] before returning
##   * Consumers interpret these derived values (e.g. damage *= (1 - resistance)) so a
##     resistance of 1.0 cannot produce negative/zero-damage surprises beyond 0 floor.

const MIN_COOLDOWN := 0.05

# upgrade_id -> stack count for the current run.
var _stacks: Dictionary = {}
# accumulated effective modifier totals (modifier key -> total across stacks).
var _modifiers: Dictionary = {}
# The progression owner is also the authority for wave-gated run upgrades. GameRoot
# updates this mirror as waves start; direct callers cannot apply a future upgrade.
var _current_wave: int = 1

const MULTIPLICATIVE := [
	&"move_speed_multiplier", &"attack_damage_multiplier", &"knockback_multiplier",
	&"skill_damage_multiplier", &"area_radius_multiplier", &"area_damage_multiplier",
	&"status_duration_multiplier", &"status_damage_multiplier",
]
const COOLDOWN := [&"attack_cooldown_multiplier", &"dodge_cooldown_multiplier", &"skill_cooldown_multiplier"]


func reset() -> void:
	_stacks.clear()
	_modifiers.clear()
	_current_wave = 1


## Set the authoritative run wave used by direct application and restore calls.
## UpgradeService still validates the offered-card contract; this check protects
## every other caller of ProgressionComponent as well.
func set_current_wave(wave_number: int) -> void:
	_current_wave = maxi(wave_number, 1)


func get_current_wave() -> int:
	return _current_wave


func apply_upgrade(config: UpgradeConfig) -> bool:
	if config == null or not config.validate().is_empty():
		return false
	if config.disabled or _current_wave < config.unlock_wave:
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
	if ContentRegistry == null:
		return false
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


## Sum this upgrade's per-stack modifier values into the running totals.
func _accumulate(config: UpgradeConfig) -> void:
	for key in config.stat_modifiers:
		var k: StringName = StringName(String(key))
		var raw: Variant = config.stat_modifiers[key]
		var v: float = float(raw) if is_finite(float(raw)) else 0.0
		if not is_finite(float(_modifiers.get(k, 0.0))):
			_modifiers[k] = 0.0
		_modifiers[k] = clampf(float(_modifiers[k]) + v, -1e6, 1e6)


## Read an effective derived stat. `base` is the unmodified, pre-upgrade value.
func get_stat(key: StringName, base: float) -> float:
	if not is_finite(base):
		base = 0.0
	if not _modifiers.has(key):
		return base
	if not is_finite(float(_modifiers[key])):
		return base
	var total := float(_modifiers[key])
	if key in MULTIPLICATIVE:
		return base * (1.0 + total)
	if key in COOLDOWN:
		# Cooldown reduction is expressed as a NEGATIVE total; clamp so we never go
		# below a small floor (i.e. -10% cooldown cannot become +10% cooldown).
		return maxf(base * (1.0 + total), MIN_COOLDOWN)
	if key == &"damage_resistance_add":
		return clampf(base + total, 0.0, 1.0)
	# Additive family: max_health_add, attack_range_add, healing_on_kill,
	# score/currency/xp multipliers, crit values, projectile counts/pierce and
	# stamina/pickup bonuses. Percentage-like additive values are authored in
	# decimal form and consumers choose the neutral base they need.
	return base + total


func get_stack_count(upgrade_id: StringName) -> int:
	return int(_stacks.get(upgrade_id, 0))


func has_upgrade(upgrade_id: StringName) -> bool:
	return int(_stacks.get(upgrade_id, 0)) > 0


func get_upgrade_stack_snapshot() -> Dictionary:
	return _stacks.duplicate()


func get_modifier_snapshot() -> Dictionary:
	return _modifiers.duplicate()


func get_selected_upgrade_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _stacks:
		out.append(StringName(String(key)))
	return out


## Serializable snapshot: upgrade_id -> stack count (single source of truth for the
## run mirror). Mirrors exactly what is applied in this runtime component.
func get_progression_snapshot() -> Dictionary:
	return _stacks.duplicate()


## Restore a serialized run progression snapshot. Only recognized upgrade ids with a
## positive stack count up to their max are applied; invalid ids are ignored (and a
## diagnostic emitted). Returns the number of upgrades successfully restored.
func restore_progression(snapshot: Dictionary, wave_number: int = -1) -> int:
	var restored := 0
	_stacks.clear()
	_modifiers.clear()
	if wave_number > 0:
		_current_wave = maxi(wave_number, 1)
	if snapshot == null or snapshot.is_empty() or ContentRegistry == null:
		return 0
	# Apply in stable id order and make repeated passes so a child upgrade is not
	# lost merely because a JSON dictionary serialized its prerequisite later.
	var ids: Array[String] = []
	for raw_id in snapshot:
		ids.append(String(raw_id))
	ids.sort()
	var pending: Dictionary = {}
	for id in ids:
		pending[id] = mini(maxi(int(snapshot[id]), 0), 999999)
	var made_progress := true
	while made_progress and not pending.is_empty():
		made_progress = false
		for id in ids:
			if not pending.has(id) or int(pending[id]) <= 0:
				continue
			var config: UpgradeConfig = ContentRegistry.get_upgrade(StringName(id))
			if config == null:
				EventBus.report_warning("restore_progression: ignoring unknown upgrade %s" % id)
				pending.erase(id)
				continue
			if apply_upgrade(config):
				pending[id] = int(pending[id]) - 1
				restored += 1
				made_progress = true
			else:
				# A blocked prerequisite may become valid on a later pass. A hard
				# wave/exclusion/max-stack failure is naturally exhausted below.
				continue
		for id in ids:
			if pending.has(id) and int(pending[id]) <= 0:
				pending.erase(id)
	# Any remaining positive entries were invalid for this run (future wave,
	# exclusion cycle, or malformed data); never partially invent their stats.
	return restored


## Add a run-scoped flat bonus to one modifier total (meta-progression armory,
## debug tooling). Participates in the same derived formulas as upgrade totals
## and is cleared by reset() like everything else.
func add_permanent_bonus(key: StringName, delta: float) -> void:
	if key not in UpgradeConfig.MODIFIER_KEYS or not is_finite(delta):
		return
	_modifiers[key] = float(_modifiers.get(key, 0.0)) + delta


func get_debug_snapshot() -> Dictionary:
	return {"upgrade_stacks": _stacks.duplicate(), "modifiers": _modifiers.duplicate()}
