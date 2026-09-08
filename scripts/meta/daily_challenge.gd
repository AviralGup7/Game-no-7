class_name DailyChallenge
extends RefCounted

## Seeded daily challenge: one shared seed per calendar day (derived from the
## date, identical for every player), plus deterministic mutators and a fixed
## loadout so leaderboards compare skill, not luck. Pure/static — the Main menu
## queries today's config and GameRoot starts it like any run with overrides.

const CHALLENGE_VERSION := 1


## YYYYMMDD integer for "today" in UTC (stable across timezones for fairness).
static func today_stamp() -> int:
	var dt := Time.get_date_dict_from_system(true)
	return int(dt["year"]) * 10000 + int(dt["month"]) * 100 + int(dt["day"])


## Deterministic seed for a date stamp (versioned so rebalances rotate).
static func seed_for_stamp(stamp: int) -> int:
	var h := stamp * 2654435761 + CHALLENGE_VERSION * 40503
	h = ((h >> 16) ^ h) * 0x45d9f3b
	h = ((h >> 16) ^ h) * 0x45d9f3b
	h = (h >> 16) ^ h
	var s: int = absi(h)
	return s if s != 0 else 1


static func seed_for_today() -> int:
	return seed_for_stamp(today_stamp())


## Two fixed mutators for the day's run (deterministic, distinct).
static func mutators_for_stamp(stamp: int) -> Array[StringName]:
	var rng := RngService.make_generator(seed_for_stamp(stamp), RngService.STREAM_WAVES)
	var pool: Array = WaveMutators.ALL.duplicate()
	var out: Array[StringName] = []
	for i in range(2):
		if pool.is_empty():
			break
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


## Fixed starting weapon rotation (one of the three early weapons).
static func weapon_for_stamp(stamp: int) -> StringName:
	var options: Array[StringName] = [&"gladius", &"warreaxe", &"sentinel_spear"]
	return options[seed_for_stamp(stamp) % options.size()]


## Full challenge card for a stamp: everything the menu + GameRoot need.
static func challenge_for_stamp(stamp: int) -> Dictionary:
	return {
		"stamp": stamp,
		"seed": seed_for_stamp(stamp),
		"mutators": mutators_for_stamp(stamp),
		"weapon": weapon_for_stamp(stamp),
		"label": "Daily %d" % stamp,
	}


static func challenge_for_today() -> Dictionary:
	return challenge_for_stamp(today_stamp())


## Score submission record (local best-per-day; network boards are out of scope).
static func submission_record(challenge: Dictionary, score: int, wave: int, player_name: String) -> Dictionary:
	return {
		"stamp": int(challenge.get("stamp", 0)),
		"seed": int(challenge.get("seed", 0)),
		"score": maxi(score, 0),
		"wave": maxi(wave, 0),
		"player": player_name.left(16),
		"version": CHALLENGE_VERSION,
	}


## Compare two submissions: higher score wins, then higher wave.
static func compare_submissions(a: Dictionary, b: Dictionary) -> int:
	if int(a.get("score", 0)) != int(b.get("score", 0)):
		return signi(int(a.get("score", 0)) - int(b.get("score", 0)))
	return signi(int(a.get("wave", 0)) - int(b.get("wave", 0)))


static func signi(v: int) -> int:
	return 1 if v > 0 else (-1 if v < 0 else 0)

## Hardened: validate daily seed and clamp wave.
func _validated_daily_seed(s: int) -> int:
	if s == 0:
		return 1
	return s
func _validated_wave(w: int) -> int:
	if w < 1:
		return 1
	return mini(w, 99)

