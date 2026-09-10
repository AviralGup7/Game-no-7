class_name PrestigeUnlock
extends Resource

## A cosmetic the prestige ladder hands out at a rank. Inline sub-resource of `PrestigeLadderConfig`.
##
## `Prestige.cosmetics_for_rank()` was six `if rank >= n` lines appending six ids. The staircase is
## where the ordering bug lived: the list had to stay sorted by rank because `all_cosmetics_up_to()`
## walked ranks 1..n and de-duplicated, so an author who inserted `if rank >= 4` between the 3 and 5
## arms got the right set at every rank and never noticed. Here the rows are validated to be in
## non-decreasing rank order, and each id has to resolve in the cosmetics catalogue — which the
## staircase could not check, because the ids were strings in the middle of an expression.


@export_range(1, 40, 1) var unlock_rank: int = 1
## Must name an entry in `Cosmetics`. A typo used to mean "this rank unlocks nothing you can see".
@export var cosmetic_id: StringName = &""


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(cosmetic_id).is_empty():
		problems.append("PrestigeUnlock at rank %d has no cosmetic_id" % unlock_rank)
	elif not Cosmetics.is_known(cosmetic_id):
		problems.append("PrestigeUnlock at rank %d awards '%s', which is not a Cosmetics id"
				% [unlock_rank, String(cosmetic_id)])
	if unlock_rank < 1:
		problems.append("PrestigeUnlock rank %d is below the first prestige" % unlock_rank)
	return problems
