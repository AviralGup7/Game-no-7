class_name UpgradeSelector
extends RefCounted

## Deterministic, data-driven upgrade selection. Pure/static: given a candidate pool and
## the full selection context (run seed, wave number, current stack counts) it returns the
## same choices for the same inputs, using a local RandomNumberGenerator seeded from
## (run_seed, wave_number) so the global RNG state is never touched. It never returns
## null or invalid choices, never duplicates, and falls back gracefully when fewer than
## `count` valid upgrades exist.
##
## The engine only filters on data (unlock wave, disabled, prerequisites, exclusions,
## max stacks) plus the provided stack counts. Pool assembly (which content the run can
## see) is the caller's responsibility (GameRoot pulls from ContentRegistry).

const DEFAULT_CHOICE_COUNT := 3


## Weighted deterministic sample WITHOUT replacement. Returns a typed list of chosen
## UpgradeConfigs, size <= min(count, eligible). Empty when no valid upgrades exist.
static func choose_upgrade_choices(
	pool: Array,
	count: int,
	run_seed: int,
	wave_number: int,
	stack_counts: Dictionary
) -> Array[UpgradeConfig]:
	var want := maxi(count, 1)
	var eligible := eligible_upgrades(pool, wave_number, stack_counts)
	if eligible.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_seed(run_seed, wave_number)  # deterministic; never touches global RNG

	var out: Array[UpgradeConfig] = []
	var remaining: Array[UpgradeConfig] = []
	for e in eligible:
		remaining.append(e)
	var chosen_ids := {}
	while out.size() < want and not remaining.is_empty():
		var next := _weighted_pick(remaining, rng)
		if chosen_ids.has(next.upgrade_id):
			remaining.erase(next)
			continue
		chosen_ids[next.upgrade_id] = true
		out.append(next)
		remaining.erase(next)
	return out


## Which of `pool` are currently selectable for `wave_number` given stack counts.
static func eligible_upgrades(pool: Array, wave_number: int, stack_counts: Dictionary) -> Array[UpgradeConfig]:
	var out: Array[UpgradeConfig] = []
	for raw in pool:
		var cfg := raw as UpgradeConfig
		if cfg == null:
			continue
		if not is_eligible(cfg, wave_number, stack_counts):
			continue
		out.append(cfg)
	return out


static func is_eligible(cfg: UpgradeConfig, wave_number: int, stack_counts: Dictionary) -> bool:
	if cfg == null:
		return false
	if cfg.disabled:
		return false
	if wave_number < cfg.unlock_wave:
		return false
	if int(stack_counts.get(cfg.upgrade_id, 0)) >= cfg.max_stacks:
		return false
	# Prerequisites: every prerequisite must already have >= 1 stack.
	for prereq in cfg.prerequisites:
		if int(stack_counts.get(prereq, 0)) <= 0:
			return false
	# Exclusions: if any exclusion already has >= 1 stack, this is not selectable.
	for excl in cfg.exclusions:
		if int(stack_counts.get(excl, 0)) > 0:
			return false
	return true


## Weighted deterministic pick. Candidates with non-positive weight are skipped.
static func _weighted_pick(candidates: Array[UpgradeConfig], rng: RandomNumberGenerator) -> UpgradeConfig:
	var total := 0.0
	for c in candidates:
		total += maxf(c.weight, 0.0)
	if total <= 0.0:
		return candidates[0]
	var roll := rng.randf_range(0.0, total)
	var acc := 0.0
	for c in candidates:
		acc += maxf(c.weight, 0.0)
		if roll <= acc:
			return c
	return candidates[candidates.size() - 1]


## Deterministic seed mixing run_seed + wave_number.
static func hash_seed(run_seed: int, wave_number: int) -> int:
	return int(run_seed) * 73856093 ^ int(wave_number) * 19349663


## Convenience: map chosen configs to their ids.
static func to_id_list(choices: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for raw in choices:
		var cfg := raw as UpgradeConfig
		if cfg != null:
			out.append(cfg.upgrade_id)
	return out
