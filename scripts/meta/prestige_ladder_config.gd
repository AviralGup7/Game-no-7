class_name PrestigeLadderConfig
extends ValidatedConfig

## The whole endgame ladder in one authored file: `res://data/prestige/ladder.tres`.
##
## Why one file instead of `data/prestige/<rank>.tres`: a ladder is a *sequence*, not a set. Rank
## n+1's cost is derived from rank n, the title list is indexed by rank, and the challenge tiers
## must be ordered and gapless or the lookup lands on the wrong rung (see `ChallengeTier`).
## Files in a folder have no order Godot guarantees for us to inherit, so the ordering rules below
## can only be enforced if the sequence is one resource's array.
##
## `Prestige` kept the same content as four independent tables — two consts for the cost curve, an
## int-keyed `TITLES` Dictionary with a `.get(rank, "Unproven")` default, an int-keyed
## `CHALLENGE_TIERS` Dictionary, and a six-branch `if rank >= n` cosmetic staircase — and none of
## them knew about each other. MAX_PRESTIGE could say 10 while TITLES stopped at 8 (title_for(9)
## then answered "Unproven" for a player who had prestiged nine times), and the UI printed the
## per-rank bonus straight from the const with no idea whether the ladder agreed with it.


## Banked coins required to take the next prestige; the cost of rank n+1 is base * (n+1). The
## growth stays in code (`Prestige.cost_for_rank`) because it is the ladder's *formula*, and a
## formula expressed as data is how you end up with a table nobody can read.
@export_range(1, 1000000, 1) var cost_base: int = 2000
## The top of the ladder. Everything else here is sized against it, which is what `validate()`
## enforces — the const used to float free of the title list it indexed.
@export_range(1, 40, 1) var max_rank: int = 10
@export_range(0.0, 1.0, 0.001) var score_bonus_per_rank: float = 0.08
@export_range(0.0, 1.0, 0.001) var currency_bonus_per_rank: float = 0.06
## Soft gate: how much of the armory must be bought before prestiging is offered at all.
@export_range(0.0, 1.0, 0.01) var armory_completion_required: float = 0.6
## Display title for each rank, index 0 = rank 0. Must be `max_rank + 1` long.
@export var titles: PackedStringArray = []
@export var challenge_tiers: Array[ChallengeTier] = []
@export var cosmetic_unlocks: Array[PrestigeUnlock] = []


func holds_rank(rank: int) -> bool:
	return rank >= 0 and rank <= max_rank


func title_for(rank: int) -> String:
	if titles.is_empty():
		return ""
	return titles[clampi(rank, 0, titles.size() - 1)]


## The rung a player at `rank` plays under: the last tier whose `unlock_rank` they have reached.
func tier_index_for_rank(rank: int) -> int:
	if challenge_tiers.is_empty():
		return -1
	var best := 0
	for i in range(challenge_tiers.size()):
		var tier := challenge_tiers[i]
		if tier != null and rank >= tier.unlock_rank:
			best = i
	return best


func tier_for_rank(rank: int) -> ChallengeTier:
	if challenge_tiers.is_empty():
		return null
	return challenge_tiers[tier_index_for_rank(rank)]


func validate() -> Array[String]:
	var problems: Array[String] = []
	if cost_base < 1:
		problems.append("cost_base must be >= 1 or prestige is free")
	problems.append_array(_validate_titles())
	problems.append_array(_validate_tiers())
	problems.append_array(_validate_unlocks())
	return problems


func _validate_titles() -> Array[String]:
	var problems: Array[String] = []
	if titles.size() != max_rank + 1:
		if titles.size() <= max_rank:
			problems.append("ranks 0..%d but %d titles: title_for clamps, so the top ranks all read '%s'"
					% [max_rank, titles.size(), titles[titles.size() - 1] if not titles.is_empty() else ""])
		else:
			problems.append("ranks 0..%d but %d titles: the last %d are unreachable"
					% [max_rank, titles.size(), titles.size() - max_rank - 1])
	for i in range(titles.size()):
		if titles[i].is_empty():
			problems.append("title %d is empty: the summary, armory and HUD all print it" % i)
	return problems


## The escalation contract the UI asserts to the player ("harder, richer, longer") is authored here
## rather than promised by a label, because the run's cap and payout are read from whichever rung
## matches the rank — if the rungs were not monotonic, prestige could make a run *easier*.
func _validate_tiers() -> Array[String]:
	var problems: Array[String] = []
	if challenge_tiers.is_empty():
		problems.append("a prestige ladder with no challenge tiers cannot escalate the Challenge run")
		return problems
	if challenge_tiers[0] == null or challenge_tiers[0].unlock_rank != 0:
		problems.append("the first challenge tier must unlock at rank 0: an unprestiged run still needs a rung")
	var previous_rank := -1
	var previous: ChallengeTier = null
	for tier in challenge_tiers:
		if tier == null:
			problems.append("null ChallengeTier in challenge_tiers")
			continue
		for problem in tier.validate():
			problems.append("tier at rank %d: %s" % [tier.unlock_rank, problem])
		if tier.unlock_rank <= previous_rank:
			problems.append("tier '%s' unlocks at rank %d, not after the previous rung (%d)"
					% [tier.label, tier.unlock_rank, previous_rank])
		elif previous != null:
			if tier.score_mult < previous.score_mult or tier.currency_mult < previous.currency_mult:
				problems.append("tier '%s' pays less than '%s' for a higher rank" % [tier.label, previous.label])
			if tier.max_waves < previous.max_waves or tier.mutator_count < previous.mutator_count:
				problems.append("tier '%s' is shorter or gentler than '%s' (prestige must never weaken a run)"
						% [tier.label, previous.label])
		previous_rank = tier.unlock_rank
		previous = tier
	return problems


func _validate_unlocks() -> Array[String]:
	var problems: Array[String] = []
	var previous_rank := 0
	var seen := {}
	for row in cosmetic_unlocks:
		if row == null:
			problems.append("null PrestigeUnlock in cosmetic_unlocks")
			continue
		for problem in row.validate():
			problems.append(String(problem))
		if row.unlock_rank > max_rank:
			problems.append("cosmetic '%s' unlocks at rank %d, past the ladder's top rank %d — nobody can earn it"
					% [String(row.cosmetic_id), row.unlock_rank, max_rank])
		if row.unlock_rank < previous_rank:
			problems.append("cosmetic '%s' at rank %d is out of rank order (all_cosmetics_up_to walks the rows)"
					% [String(row.cosmetic_id), row.unlock_rank])
		if seen.has(row.cosmetic_id):
			problems.append("cosmetic '%s' is awarded by two ranks" % String(row.cosmetic_id))
		seen[row.cosmetic_id] = true
		previous_rank = row.unlock_rank
	return problems
