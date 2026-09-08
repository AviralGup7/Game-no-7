class_name DropTable
extends RefCounted

## Deterministic enemy-drop resolution.
## Given the slain enemy's archetype id, the wave number and an RngService, it
## decides HOW MANY drops (pity-protected) and WHICH pickups (weighted, wave
## gated). Pure apart from the injected config list — headless-testable.

const BASE_DROP_CHANCE := 0.22
const ELITE_BONUS_CHANCE := 0.35
const BOSS_GUARANTEED_DROPS := 3
const PITY_KILLS_WITHOUT_DROP := 9   # force a drop after this many dry kills
const MAX_DROPS_PER_KILL := 3

var _configs: Array[PickupConfig] = []
var _dry_streak := 0


func _init(configs: Array = []) -> void:
	for c in configs:
		if c is PickupConfig:
			_configs.append(c)


func configure(configs: Array) -> void:
	_configs.clear()
	for c in configs:
		if c is PickupConfig:
			_configs.append(c)


func dry_streak() -> int:
	return _dry_streak


func reset_pity() -> void:
	_dry_streak = 0


## Resolve drops for one kill. Returns pickup ids (possibly empty).
## `is_elite` / `is_boss` raise quantity; `luck_bonus` adds flat chance.
func roll_drops(_archetype_id: StringName, wave_number: int, is_elite: bool, is_boss: bool, luck_bonus: float, rng: RngService) -> Array[StringName]:
	var out: Array[StringName] = []
	var eligible := _eligible(wave_number)
	if eligible.is_empty():
		return out
	var chance := BASE_DROP_CHANCE + maxf(luck_bonus, 0.0)
	if is_elite:
		chance += ELITE_BONUS_CHANCE
	var guaranteed := 0
	if is_boss:
		guaranteed = BOSS_GUARANTEED_DROPS
	_dry_streak += 1
	var drop_any := guaranteed > 0
	if not drop_any and rng != null and rng.chance(RngService.STREAM_DROPS, chance):
		drop_any = true
	if not drop_any and _dry_streak >= PITY_KILLS_WITHOUT_DROP:
		drop_any = true  # pity drop
	if not drop_any:
		return out
	_dry_streak = 0
	var count := guaranteed
	if count <= 0:
		count = 1
		# Elites and lucky streaks can double-drop.
		if is_elite and rng != null and rng.chance(RngService.STREAM_DROPS, 0.4):
			count = 2
	count = mini(count, MAX_DROPS_PER_KILL)
	var table := WeightedTable.new()
	for cfg in eligible:
		var w := cfg.drop_weight
		# Slight bias: healing drops are kinder when the run is young.
		if cfg.effect == PickupConfig.EFFECT_HEAL and wave_number <= 2:
			w *= 1.5
		table.add(cfg.pickup_id, w)
	for i in range(count):
		var id: Variant = table.roll_with_service(rng, RngService.STREAM_DROPS)
		if id != null:
			out.append(id)
	return out


func _eligible(wave_number: int) -> Array[PickupConfig]:
	var out: Array[PickupConfig] = []
	for cfg in _configs:
		if cfg.disabled:
			continue
		if cfg.drop_weight <= 0.0:
			continue
		if wave_number < cfg.min_wave:
			continue
		out.append(cfg)
	return out


## Wave-clear bonus drops: `count` pity-free weighted picks.
func roll_bonus_drops(count: int, wave_number: int, rng: RngService) -> Array[StringName]:
	var out: Array[StringName] = []
	var eligible := _eligible(wave_number)
	if eligible.is_empty() or count <= 0:
		return out
	var table := WeightedTable.new()
	for cfg in eligible:
		table.add(cfg.pickup_id, cfg.drop_weight)
	for i in range(count):
		var id: Variant = table.roll_with_service(rng, RngService.STREAM_DROPS)
		if id != null:
			out.append(id)
	return out
