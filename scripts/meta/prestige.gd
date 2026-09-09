class_name Prestige
extends RefCounted

## Endgame prestige ladder: the questions the UI asks and the arithmetic over the ladder's rows.
## The ladder itself — costs, per-rank bonuses, titles, challenge tiers, cosmetic unlock ranks, the
## armory-completion soft gate — is authored data in `res://data/prestige/ladder.tres`
## (`PrestigeLadderConfig`).
##
## It used to be four tables that did not know about each other: `MAX_PRESTIGE` said 10 while
## `TITLES` was an int-keyed Dictionary that could stop anywhere (rank 9 then answered the
## `.get(rank, "Unproven")` default — "Unproven" for a player who had prestiged nine times);
## `CHALLENGE_TIERS` was indexed by `min(floor(rank / 2), CHALLENGE_TIERS.size() - 1)`, so deleting
## a rung made the *top* rung unreachable and a gap in the keys handed a Mythic player the easiest
## run in the game; and the cosmetic unlocks were a six-branch `if rank >= n` staircase whose ids
## nothing checked against the catalogue that wears them. The data files now validate that the titles
## cover every rank, that the rungs get harder rather than merely longer, and that each cosmetic id
## resolves.
##
## Pure helpers + SaveManager integration via the MetaProgression owner (this class never touches
## disk itself, beyond loading its one content file when there is no registry).

const LADDER_PATH := "res://data/prestige/ladder.tres"

## Resolved once, then kept. `run_scorekeeper` asks for the currency multiplier on every kill, so a
## per-call `load()` would be a disk hit inside the scoring path; a live game answers from the
## registry and only the headless harness reaches the file.
static var _ladder: PrestigeLadderConfig
static var _ladder_resolved := false


static func ladder() -> PrestigeLadderConfig:
	if _ladder_resolved:
		return _ladder
	_ladder_resolved = true
	if ContentRegistry != null:
		_ladder = ContentRegistry.get_prestige_ladder()
	if _ladder == null and ResourceLoader.exists(LADDER_PATH):
		_ladder = load(LADDER_PATH) as PrestigeLadderConfig
	return _ladder


## Test/tooling hook: content refreshes (or a suite that swaps the ladder) re-resolve on next ask.
static func forget_ladder() -> void:
	_ladder = null
	_ladder_resolved = false


static func max_rank() -> int:
	var cfg := ladder()
	return cfg.max_rank if cfg != null else 0


static func cost_base() -> int:
	var cfg := ladder()
	return cfg.cost_base if cfg != null else 0


## Per-rank bonuses, exposed for the armory panel's copy. The panel used to print the constant, which
## is the same claim one step further from the truth than a stale comment.
static func score_bonus_per_rank() -> float:
	var cfg := ladder()
	return cfg.score_bonus_per_rank if cfg != null else 0.0


static func currency_bonus_per_rank() -> float:
	var cfg := ladder()
	return cfg.currency_bonus_per_rank if cfg != null else 0.0


static func armory_completion_required() -> float:
	var cfg := ladder()
	return cfg.armory_completion_required if cfg != null else 1.0


## Ranks come off disk, so they are clamped to the ladder before anything multiplies with them. With
## no ladder to check against, a rank is kept as written (zeroing it would burn the save over a
## content-load failure) — and every consumer above answers 0/neutral, so it buys nothing.
static func clamp_rank(rank: int) -> int:
	if rank < 0:
		return 0
	var cfg := ladder()
	return mini(rank, cfg.max_rank) if cfg != null else rank


static func cost_for_rank(current_rank: int) -> int:
	# Escalating cost: base * (rank+1). The curve is the ladder's formula, so it stays here; only the
	# base is authored.
	return cost_base() * (clamp_rank(current_rank) + 1)


## `&"unavailable"` is new and deliberate: with the ladder missing there is nothing to buy, and the
## old code would have answered `ok` at cost 0 because its numbers were consts that could not be
## absent. The armory panel disables the button on that verdict.
static func can_prestige(rank: int, wallet: int, armory_completion: float) -> StringName:
	var cfg := ladder()
	if cfg == null:
		return &"unavailable"
	if rank >= cfg.max_rank:
		return &"maxed"
	# Soft gate: encourage finishing most of the armory first.
	if armory_completion < cfg.armory_completion_required:
		return &"armory_incomplete"
	if wallet < cost_for_rank(rank):
		return &"insufficient_funds"
	return &"ok"


static func score_multiplier(rank: int) -> float:
	var cfg := ladder()
	if cfg == null:
		return 1.0
	return 1.0 + cfg.score_bonus_per_rank * float(clamp_rank(rank))


static func currency_multiplier(rank: int) -> float:
	var cfg := ladder()
	if cfg == null:
		return 1.0
	return 1.0 + cfg.currency_bonus_per_rank * float(clamp_rank(rank))


static func title_for(rank: int) -> String:
	var cfg := ladder()
	return cfg.title_for(rank) if cfg != null else ""


## Index of the challenge rung a player at `rank` plays under. -1 = no ladder authored.
static func challenge_tier(rank: int) -> int:
	var cfg := ladder()
	return cfg.tier_index_for_rank(rank) if cfg != null else -1


## The rung itself, typed. This used to hand out a Dictionary that every caller read with
## `.get(key, <that caller's own default>)`.
static func challenge_tier_def(rank: int) -> ChallengeTier:
	var cfg := ladder()
	return cfg.tier_for_rank(rank) if cfg != null else null


static func challenge_tier_label(rank: int) -> String:
	var tier := challenge_tier_def(rank)
	return tier.label if tier != null else ""


static func challenge_tier_score_mult(rank: int) -> float:
	var tier := challenge_tier_def(rank)
	return tier.score_mult if tier != null else 1.0


static func challenge_tier_currency_mult(rank: int) -> float:
	var tier := challenge_tier_def(rank)
	return tier.currency_mult if tier != null else 1.0


static func challenge_tier_mutator_count(rank: int) -> int:
	var tier := challenge_tier_def(rank)
	return maxi(tier.mutator_count, 0) if tier != null else 0


static func challenge_tier_waves(rank: int) -> int:
	var tier := challenge_tier_def(rank)
	return maxi(tier.max_waves, 1) if tier != null else 1


## Cosmetics the ladder has handed out by `rank`, in authored order. The staircase this replaces had
## to stay sorted by rank for `all_cosmetics_up_to()` to work; the rows are now validated for order
## and for naming a real cosmetic.
static func cosmetics_for_rank(rank: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var cfg := ladder()
	if cfg == null:
		return out
	for row in cfg.cosmetic_unlocks:
		if row != null and rank >= row.unlock_rank:
			out.append(row.cosmetic_id)
	return out


static func all_cosmetics_up_to(rank: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var cfg := ladder()
	if cfg == null:
		return out
	for row in cfg.cosmetic_unlocks:
		if row != null and row.unlock_rank <= clamp_rank(rank) and row.cosmetic_id not in out:
			out.append(row.cosmetic_id)
	return out
