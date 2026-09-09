class_name Prestige
extends RefCounted

## Endgame prestige ladder. After the armory is largely complete, players spend
## a full prestige reset for permanent score/currency multipliers, challenge-tier
## unlocks, and cosmetic titles. Pure helpers + SaveManager integration via the
## MetaProgression owner (this class never touches disk itself).

const PRESTIGE_COST_BASE := 2000  # banked coins required to prestige
const MAX_PRESTIGE := 10
const SCORE_BONUS_PER_RANK := 0.08  # +8% run score per prestige
const CURRENCY_BONUS_PER_RANK := 0.06  # +6% banked cut per prestige
const CHALLENGE_TIER_EVERY := 2  # unlock a harder challenge tier every 2 prestiges

## Cosmetic titles unlocked by prestige rank (display only).
const TITLES := {
	0: "Unproven",
	1: "Survivor",
	2: "Veteran",
	3: "Champion",
	4: "Warlord-Slayer",
	5: "Pit Legend",
	6: "Ashen Crown",
	7: "Frostbound",
	8: "Eternal Guard",
	9: "Mythic",
	10: "Last Stand",
}

## Challenge tiers unlocked by prestige (used by GameMode challenge variants).
const CHALLENGE_TIERS := {
	0: {"label": "Standard Challenge", "score_mult": 1.5, "mutators": 2},
	1: {"label": "Hard Challenge", "score_mult": 1.8, "mutators": 3},
	2: {"label": "Nightmare Challenge", "score_mult": 2.2, "mutators": 3},
	3: {"label": "Mythic Challenge", "score_mult": 2.8, "mutators": 4},
	4: {"label": "Last Stand Challenge", "score_mult": 3.5, "mutators": 4},
}


static func cost_for_rank(current_rank: int) -> int:
	# Escalating cost: base * (rank+1).
	return PRESTIGE_COST_BASE * (clampi(current_rank, 0, MAX_PRESTIGE) + 1)


static func can_prestige(rank: int, wallet: int, armory_completion: float) -> StringName:
	if rank >= MAX_PRESTIGE:
		return &"maxed"
	# Soft gate: encourage finishing most of the armory first (60%+).
	if armory_completion < 0.6:
		return &"armory_incomplete"
	if wallet < cost_for_rank(rank):
		return &"insufficient_funds"
	return &"ok"


static func score_multiplier(rank: int) -> float:
	return 1.0 + SCORE_BONUS_PER_RANK * float(clampi(rank, 0, MAX_PRESTIGE))


static func currency_multiplier(rank: int) -> float:
	return 1.0 + CURRENCY_BONUS_PER_RANK * float(clampi(rank, 0, MAX_PRESTIGE))


static func title_for(rank: int) -> String:
	return String(TITLES.get(clampi(rank, 0, MAX_PRESTIGE), "Unproven"))


static func challenge_tier(rank: int) -> int:
	return mini(int(floor(float(rank) / float(CHALLENGE_TIER_EVERY))), CHALLENGE_TIERS.size() - 1)


static func challenge_tier_def(rank: int) -> Dictionary:
	return CHALLENGE_TIERS.get(challenge_tier(rank), CHALLENGE_TIERS[0])


## Cosmetics unlocked at each prestige rank (ids only — visuals are freeform).
static func cosmetics_for_rank(rank: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if rank >= 1:
		out.append(&"banner_survivor")
	if rank >= 2:
		out.append(&"trail_ember")
	if rank >= 3:
		out.append(&"title_champion")
	if rank >= 5:
		out.append(&"aura_legend")
	if rank >= 7:
		out.append(&"trail_frost")
	if rank >= 10:
		out.append(&"banner_last_stand")
	return out


static func all_cosmetics_up_to(rank: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for r in range(1, clampi(rank, 0, MAX_PRESTIGE) + 1):
		for c in cosmetics_for_rank(r):
			if c not in out:
				out.append(c)
	return out
