class_name ChallengeTier
extends Resource

## One rung of the Challenge run's prestige escalation: what the run becomes once the player has
## the rank that unlocks it.
##
## A row, not a config file: it lives inside `res://data/prestige/ladder.tres` and has no path of its
## own, so it extends Resource (like `WaveSpawnEntry` and `HazardPlacement`) instead of
## `ValidatedConfig` — ContentLoader only runs validate() on files it registers. Its `validate()` is
## still real: the ladder's own validate() folds every row's problems into its list, which is what the
## loader reports, and `tests/unit/test_game_modes.gd` exercises the row rules directly.
##
## The rung used to be `CHALLENGE_TIERS[rank]` — a Dictionary of Dictionaries keyed by an *int*,
## indexed by `min(floor(rank / 2), CHALLENGE_TIERS.size() - 1)`. That pair of facts is a trap:
## delete or renumber one key and the size no longer matches the top index, so the lookup falls
## through `.get(idx, CHALLENGE_TIERS[0])` to **tier 0**, and a Mythic player is quietly handed the
## easiest run in the game at full price. A dense array with an authored `unlock_rank` cannot skip a
## rank, and `PrestigeLadderConfig.validate()` requires the rungs to get harder, not merely longer.


@export var label: String = ""
## Prestige rank at which this rung replaces the one below it. The ladder's rows are ordered by
## this and must start at 0, so every player — including an unprestiged one — resolves exactly one
## rung.
@export_range(0, 40, 1) var unlock_rank: int = 0
@export_range(0.05, 20.0, 0.01) var score_mult: float = 1.5
@export_range(0.05, 20.0, 0.01) var currency_mult: float = 1.4
## How many ids the mode's `prestige_mutator_pool` hands this rung, in the pool's authored order.
## A count rather than a list so escalating stays one number per rung — and so tier 0 reproduces
## the historical [glass_cannon, ember_winds] opening instead of re-declaring it.
@export_range(0, 12, 1) var mutator_count: int = 2
## Waves the run must clear to win. The cap is authored per rung because the run's length is the
## ladder's main lever: 12 waves at tier 0, 20 at Last Stand.
@export_range(1, 200, 1) var max_waves: int = 12


func validate() -> Array[String]:
	var problems: Array[String] = []
	if label.is_empty():
		problems.append("a challenge tier with no label cannot be shown on the run-setup card")
	if not is_finite(score_mult) or not is_finite(currency_mult):
		problems.append("%s: multipliers must be finite" % label)
	if score_mult <= 0.0 or currency_mult <= 0.0:
		problems.append("%s: multipliers must be > 0 (a run that pays nothing is deleted, not tuned)" % label)
	if mutator_count < 0:
		problems.append("%s: mutator_count cannot be negative" % label)
	if max_waves < 1:
		problems.append("%s: max_waves must be >= 1 or the rung can never be won" % label)
	return problems
