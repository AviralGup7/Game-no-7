class_name GameMode
extends RefCounted

## Data-driven run mode definitions. Standard survival remains the default; Boss Rush,
## Survival (timed endurance), Challenge (fixed loadout + mutators), and Campaign
## (scripted encounter beats + narrative) share the same WaveManager / RunState loop
## with mode-specific wave queues, win conditions, and scoring multipliers.
##
## Pure static API — no tree access. GameRoot stores the active mode id on RunState;
## WaveManager / Main / UI query helpers here.

const MODE_STANDARD := &"standard"
const MODE_BOSS_RUSH := &"boss_rush"
const MODE_SURVIVAL := &"survival"
const MODE_CHALLENGE := &"challenge"
const MODE_CAMPAIGN := &"campaign"
const MODE_DEFEND := &"defend"
const MODE_COLLECT := &"collect"

const OBJECTIVE_CLEAR_WAVES := &"clear_waves"
const OBJECTIVE_SURVIVE_TIME := &"survive_time"
const OBJECTIVE_SLAY_BOSSES := &"slay_bosses"
const OBJECTIVE_DEFEND_POINT := &"defend_point"
const OBJECTIVE_COLLECT := &"collect"

## Catalogue of playable modes. Adding a mode is data-only (plus optional wave helpers).
const CATALOG := {
	MODE_STANDARD: {
		"display_name": "Standard",
		"blurb": "Endless waves. Kill everything. Climb the scoreboard.",
		"objective": OBJECTIVE_CLEAR_WAVES,
		"score_mult": 1.0,
		"currency_mult": 1.0,
		"max_waves": 0,  # 0 = endless
		"target_seconds": 0.0,
		"boss_interval": 10,
		"upgrade_every": 2,
		"forced_mutators": [],
		"fixed_weapon": &"",
		"narrator_id": &"standard",
		"unlock_prestige": 0,
	},
	MODE_BOSS_RUSH: {
		"display_name": "Boss Rush",
		"blurb": "Five Warlord duels. Short rests. No filler packs.",
		"objective": OBJECTIVE_SLAY_BOSSES,
		"score_mult": 1.35,
		"currency_mult": 1.25,
		"max_waves": 5,
		"target_seconds": 0.0,
		"boss_interval": 1,
		"upgrade_every": 1,
		"forced_mutators": [&"elite_surge"],
		"fixed_weapon": &"",
		"narrator_id": &"boss_rush",
		"unlock_prestige": 0,
	},
	MODE_SURVIVAL: {
		"display_name": "Survival",
		"blurb": "Endure five minutes of mounting pressure. Score ticks with time lived.",
		"objective": OBJECTIVE_SURVIVE_TIME,
		"score_mult": 1.15,
		"currency_mult": 1.1,
		"max_waves": 0,
		"target_seconds": 300.0,
		"boss_interval": 8,
		"upgrade_every": 3,
		"forced_mutators": [],
		"fixed_weapon": &"",
		"narrator_id": &"survival",
		"unlock_prestige": 0,
	},
	MODE_CHALLENGE: {
		"display_name": "Challenge Run",
		"blurb": "Fixed Gladius loadout, harsh mutators, clear the tier or die trying.",
		"objective": OBJECTIVE_CLEAR_WAVES,
		"score_mult": 1.5,
		"currency_mult": 1.4,
		"max_waves": 12,
		"target_seconds": 0.0,
		"boss_interval": 6,
		"upgrade_every": 2,
		# Base-tier signature; the live set is chosen by prestige tier via
		# challenge_mutators() (this list is the tier-0 pair, see below).
		"forced_mutators": [&"glass_cannon", &"ember_winds"],
		"fixed_weapon": &"gladius",
		"narrator_id": &"challenge",
		"unlock_prestige": 0,
	},
	MODE_CAMPAIGN: {
		"display_name": "Campaign: The Last Stand",
		"blurb": "Scripted encounters, lore beats, and a final Warlord reckoning.",
		"objective": OBJECTIVE_CLEAR_WAVES,
		"score_mult": 1.2,
		"currency_mult": 1.3,
		"max_waves": 15,
		"target_seconds": 0.0,
		"boss_interval": 5,
		"upgrade_every": 1,
		"forced_mutators": [],
		"fixed_weapon": &"",
		"narrator_id": &"campaign",
		"unlock_prestige": 0,
	},
	MODE_DEFEND: {
		"display_name": "Hold the Line",
		"blurb": "Guard the beacon at the arena's heart. If it falls, the run ends — survive the timer to win.",
		"objective": OBJECTIVE_DEFEND_POINT,
		"score_mult": 1.4,
		"currency_mult": 1.3,
		"max_waves": 0,  # ends on the clock / beacon death, not a wave cap
		"target_seconds": 240.0,
		"boss_interval": 8,
		"upgrade_every": 3,
		"forced_mutators": [],
		"fixed_weapon": &"",
		"narrator_id": &"standard",
		"unlock_prestige": 0,
		"collect_target": 0,
	},
	MODE_COLLECT: {
		"display_name": "Relic Hunt",
		"blurb": "Slain foes drop relics. Bank enough before the horde overruns you.",
		"objective": OBJECTIVE_COLLECT,
		"score_mult": 1.3,
		"currency_mult": 1.35,
		"max_waves": 0,  # ends when the relic quota is met, not a wave cap
		"target_seconds": 0.0,
		"boss_interval": 8,
		"upgrade_every": 3,
		"forced_mutators": [&"bounty_hunt"],
		"fixed_weapon": &"",
		"narrator_id": &"standard",
		"unlock_prestige": 0,
		"collect_target": 20,
	},
}


static func is_known(mode_id: StringName) -> bool:
	return CATALOG.has(mode_id)


static func def(mode_id: StringName) -> Dictionary:
	if CATALOG.has(mode_id):
		return CATALOG[mode_id]
	return CATALOG[MODE_STANDARD]


static func display_name(mode_id: StringName) -> String:
	return String(def(mode_id).get("display_name", "Standard"))


static func blurb(mode_id: StringName) -> String:
	return String(def(mode_id).get("blurb", ""))


static func all_mode_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in CATALOG.keys():
		out.append(StringName(String(id)))
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


static func score_multiplier(mode_id: StringName) -> float:
	return float(def(mode_id).get("score_mult", 1.0))


static func currency_multiplier(mode_id: StringName) -> float:
	return float(def(mode_id).get("currency_mult", 1.0))


static func max_waves(mode_id: StringName) -> int:
	return int(def(mode_id).get("max_waves", 0))


static func target_seconds(mode_id: StringName) -> float:
	return float(def(mode_id).get("target_seconds", 0.0))


## Relic quota for OBJECTIVE_COLLECT modes (0 for every other mode).
static func collect_target(mode_id: StringName) -> int:
	return maxi(int(def(mode_id).get("collect_target", 0)), 0)


static func upgrade_every(mode_id: StringName) -> int:
	return maxi(int(def(mode_id).get("upgrade_every", 2)), 1)


static func boss_interval(mode_id: StringName) -> int:
	return maxi(int(def(mode_id).get("boss_interval", 10)), 1)


static func forced_mutators(mode_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for m in Array(def(mode_id).get("forced_mutators", [])):
		out.append(StringName(String(m)))
	return out


static func fixed_weapon(mode_id: StringName) -> StringName:
	return StringName(String(def(mode_id).get("fixed_weapon", "")))


## ---------- Challenge prestige tiers ----------
## The Challenge run reads the player's prestige tier (Prestige.challenge_tier)
## so a higher rank is a harsher, better-paying, longer run — not the same fixed
## Gladius + 2 mutators every time. The mutator SET is drawn deterministically
## from this ordered pool (first N by tier count), so tier 0 reproduces the
## historical [glass_cannon, ember_winds] pair and each step adds pressure.
const CHALLENGE_MUTATOR_POOL: Array[StringName] = [
	&"glass_cannon", &"ember_winds", &"iron_hide", &"volatile_mix", &"elite_surge",
]


## Whether this mode's run parameters scale with prestige tier.
static func scales_with_prestige(mode_id: StringName) -> bool:
	return validated(mode_id) == MODE_CHALLENGE


## Deterministic mutator set for the Challenge run at `prestige_rank`. Non-challenge
## modes keep their authored forced_mutators regardless of rank.
static func challenge_mutators(mode_id: StringName, prestige_rank: int) -> Array[StringName]:
	if not scales_with_prestige(mode_id):
		return forced_mutators(mode_id)
	var count := Prestige.challenge_tier_mutator_count(prestige_rank)
	var out: Array[StringName] = []
	for i in range(mini(count, CHALLENGE_MUTATOR_POOL.size())):
		out.append(CHALLENGE_MUTATOR_POOL[i])
	return out


## Prestige-aware wrappers. Callers with a live run pass GameRoot.get_prestige_rank();
## the rank is only consulted for modes that scale (Challenge today).
static func score_multiplier_for(mode_id: StringName, prestige_rank: int) -> float:
	if scales_with_prestige(mode_id):
		return Prestige.challenge_tier_score_mult(prestige_rank)
	return score_multiplier(mode_id)


static func currency_multiplier_for(mode_id: StringName, prestige_rank: int) -> float:
	if scales_with_prestige(mode_id):
		return Prestige.challenge_tier_currency_mult(prestige_rank)
	return currency_multiplier(mode_id)


static func max_waves_for(mode_id: StringName, prestige_rank: int) -> int:
	if scales_with_prestige(mode_id):
		return Prestige.challenge_tier_waves(prestige_rank)
	return max_waves(mode_id)


static func is_victory_wave_for(mode_id: StringName, wave_number: int, prestige_rank: int) -> bool:
	var cap := max_waves_for(mode_id, prestige_rank)
	if cap <= 0:
		return false
	return wave_number >= cap


## Label shown in the run-setup preview / announcements for the active tier.
static func challenge_tier_label(mode_id: StringName, prestige_rank: int) -> String:
	if scales_with_prestige(mode_id):
		return Prestige.challenge_tier_label(prestige_rank)
	return display_name(mode_id)


static func objective(mode_id: StringName) -> StringName:
	return StringName(String(def(mode_id).get("objective", OBJECTIVE_CLEAR_WAVES)))


static func narrator_id(mode_id: StringName) -> StringName:
	return StringName(String(def(mode_id).get("narrator_id", "standard")))


## Whether the run should end in victory after completing `wave_number`.
static func is_victory_wave(mode_id: StringName, wave_number: int) -> bool:
	var cap := max_waves(mode_id)
	if cap <= 0:
		return false
	return wave_number >= cap


## Survival mode: victory when elapsed time reaches the target.
static func is_survival_victory(mode_id: StringName, elapsed: float) -> bool:
	if objective(mode_id) != OBJECTIVE_SURVIVE_TIME:
		return false
	var target := target_seconds(mode_id)
	return target > 0.0 and elapsed >= target


## Deterministic spawn queue override for modes that don't use the standard planner.
## Returns empty when the mode should fall through to WavePlanner.
static func spawn_queue(mode_id: StringName, wave_number: int, seed: int) -> Array[StringName]:
	var w := maxi(wave_number, 1)
	match mode_id:
		MODE_BOSS_RUSH:
			return _boss_rush_queue(w)
		MODE_SURVIVAL:
			return _survival_queue(w, seed)
		MODE_CAMPAIGN:
			return _campaign_queue(w, seed)
		MODE_CHALLENGE:
			# Challenge uses the extended planner but is capped by max_waves.
			return []
		MODE_DEFEND:
			return _defend_queue(w, seed)
		MODE_COLLECT:
			return _collect_queue(w, seed)
		_:
			return []


static func _boss_rush_queue(wave_number: int) -> Array[StringName]:
	var out: Array[StringName] = [&"warlord"]
	# Escalating add packs between phases of the duel.
	var adds := mini(2 + wave_number, 6)
	for i in range(adds):
		out.append(&"basic" if i % 2 == 0 else &"fast")
	if wave_number >= 3:
		out.append(&"heavy")
	if wave_number >= 5:
		out.append(&"ranged")
		out.append(&"dasher")
	return out


## Hold the Line: steady pressure that ramps with time; the run ends on the clock
## or when the beacon dies, so waves keep coming (no early soft start).
static func _defend_queue(wave_number: int, seed: int) -> Array[StringName]:
	var base := WavePlanner.extended_queue_for_wave(maxi(wave_number + 1, 2), seed)
	# Enemies converge on the beacon; a heavy every third wave threatens it directly.
	if wave_number % 3 == 0:
		base.append(&"heavy")
	return base


## Relic Hunt: dense, drop-rich packs so relics fall steadily; endless until quota.
static func _collect_queue(wave_number: int, seed: int) -> Array[StringName]:
	var base := WavePlanner.extended_queue_for_wave(maxi(wave_number + 2, 3), seed)
	if wave_number % 4 == 0:
		base.append(&"ranged")
	return base


static func _survival_queue(wave_number: int, seed: int) -> Array[StringName]:
	# Dense, escalating packs without early-game soft start.
	var base := WavePlanner.extended_queue_for_wave(maxi(wave_number + 2, 3), seed)
	# Inject an extra heavy every 4th wave to keep pressure high.
	if wave_number % 4 == 0:
		base.append(&"heavy")
	return base


static func _campaign_queue(wave_number: int, seed: int) -> Array[StringName]:
	# Scripted encounter beats for the short campaign arc.
	match wave_number:
		1:
			return [&"basic", &"basic", &"basic", &"basic", &"basic"]
		2:
			return [&"basic", &"basic", &"fast", &"basic", &"fast", &"basic"]
		3:
			return [&"basic", &"fast", &"ranged", &"basic", &"fast", &"ranged"]
		4:
			return [&"basic", &"heavy", &"fast", &"basic", &"dasher", &"basic"]
		5:
			return [&"warlord", &"basic", &"basic", &"fast"]
		6:
			return [&"fast", &"fast", &"ranged", &"exploder", &"basic", &"basic", &"dasher"]
		7:
			return [&"heavy", &"ranged", &"basic", &"splitter", &"fast", &"basic", &"ranged"]
		8:
			return [&"dasher", &"exploder", &"fast", &"heavy", &"basic", &"ranged", &"dasher"]
		9:
			return [&"splitter", &"heavy", &"ranged", &"fast", &"exploder", &"basic", &"dasher", &"basic"]
		10:
			return [&"warlord", &"fast", &"fast", &"ranged", &"basic"]
		11, 12, 13:
			return WavePlanner.extended_queue_for_wave(wave_number + 2, seed)
		14:
			return [&"heavy", &"heavy", &"ranged", &"dasher", &"exploder", &"splitter", &"fast", &"fast"]
		15:
			return [&"warlord", &"warlord", &"heavy", &"ranged", &"dasher", &"basic", &"basic"]
		_:
			return WavePlanner.extended_queue_for_wave(wave_number, seed)


## Whether this wave should offer an upgrade under the mode's cadence.
static func wants_upgrade(mode_id: StringName, wave_number: int) -> bool:
	var every := upgrade_every(mode_id)
	if every <= 0:
		return false
	return wave_number % every == 0


## Objective progress string for HUD / summary. `progress` carries mode-specific
## live state (relics collected, beacon fraction) so this stays pure and typed.
static func objective_label(mode_id: StringName, wave: int, elapsed: float, bosses_slain: int, progress: int = 0) -> String:
	match objective(mode_id):
		OBJECTIVE_SURVIVE_TIME:
			var target := target_seconds(mode_id)
			var left := maxf(target - elapsed, 0.0)
			return "Survive  %d:%02d remaining" % [int(left) / 60, int(left) % 60]
		OBJECTIVE_SLAY_BOSSES:
			var cap := max_waves(mode_id)
			return "Bosses  %d / %d" % [bosses_slain, cap]
		OBJECTIVE_DEFEND_POINT:
			var target_d := target_seconds(mode_id)
			var left_d := maxf(target_d - elapsed, 0.0)
			return "Hold  %d:%02d  •  Beacon %d%%" % [int(left_d) / 60, int(left_d) % 60, clampi(progress, 0, 100)]
		OBJECTIVE_COLLECT:
			return "Relics  %d / %d" % [progress, collect_target(mode_id)]
		OBJECTIVE_CLEAR_WAVES:
			var cap2 := max_waves(mode_id)
			if cap2 > 0:
				return "Wave  %d / %d" % [wave, cap2]
			return "Wave  %d" % wave
		_:
			return "Wave  %d" % wave


## Hardened: clamp unknown mode ids to standard.
static func validated(mode_id: StringName) -> StringName:
	if is_known(mode_id):
		return mode_id
	return MODE_STANDARD
