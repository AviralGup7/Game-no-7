class_name WavePlanner
## Deterministic wave generation. Pure static functions take (wave_number, seed) and
## return the same WaveConfig every time for the same inputs, so headless tests can
## assert composition/counts exactly. Difficulty grows across bounded dimensions
## (count, composition, spawn interval, simultaneous cap, stat scalars) without ever
## becoming unplayable — counts/speeds are capped.

const BASIC := &"basic"
const FAST := &"fast"
const HEAVY := &"heavy"


## Returns the flat ordered spawn queue (archetype ids) for the wave.
static func spawn_queue_for_wave(wave_number: int) -> Array[StringName]:
	var counts := _counts_for_wave(wave_number)
	var out: Array[StringName] = []
	for i in counts.basic:
		out.append(BASIC)
	for i in counts.fast:
		out.append(FAST)
	for i in counts.heavy:
		out.append(HEAVY)
	return out


## Build a fully-typed WaveConfig for the wave. Used by WaveManager at runtime.
static func generate_wave(wave_number: int, _seed: int) -> WaveConfig:
	wave_number = maxi(wave_number, 1)
	var cfg := WaveConfig.new()
	cfg.wave_number = wave_number
	var counts := _counts_for_wave(wave_number)
	var entries: Array[WaveSpawnEntry] = []
	if counts.basic > 0:
		entries.append(_entry(BASIC, counts.basic))
	if counts.fast > 0:
		entries.append(_entry(FAST, counts.fast))
	if counts.heavy > 0:
		entries.append(_entry(HEAVY, counts.heavy))
	cfg.spawn_entries = entries
	cfg.spawn_interval = clampf(0.9 - wave_number * 0.05, 0.35, 0.9)
	cfg.maximum_simultaneous_enemies = mini(6 + wave_number * 2, 22)
	cfg.transition_delay = 2.5
	cfg.completion_bonus = wave_number * 20
	cfg.upgrade_after_completion = wave_number % 2 == 0
	cfg.announcement_text_key = &"wave_started"
	cfg.difficulty_rating = clampf(1.0 + (wave_number - 1) * 0.15, 1.0, 6.0)
	return cfg


static func _entry(archetype_id: StringName, count: int) -> WaveSpawnEntry:
	var e := WaveSpawnEntry.new()
	e.archetype_id = archetype_id
	e.count = count
	e.spawn_weight = 1.0
	return e


static func _counts_for_wave(wave_number: int) -> Dictionary:
	var w := maxi(wave_number, 1)
	var basic := 5
	var fast := 0
	var heavy := 0
	match w:
		1:
			basic = 5
		2:
			basic = 7
		3:
			basic = 8
			fast = 1
		4:
			basic = 10
			fast = 2
		5:
			basic = 8
			fast = 2
			heavy = 1
		_:
			# Late waves scale gradually but stay capped.
			var extra := w - 5
			basic = mini(8 + extra, 18)
			fast = mini(2 + extra, 10)
			# heavy was the only tier missing its cap, so total planned count kept
			# climbing past the documented ceiling (46 by wave 40). 12 keeps the
			# existing curve untouched until wave 27 and holds the total at <= 40.
			heavy = mini(1 + int(floor(extra / 2.0)), 12)
	return {"basic": basic, "fast": fast, "heavy": heavy}


## Extended queue: the classic composition plus new-archetype injections from wave 6
## (ranged backlines, dasher flanks, exploders, splitters, periodic heavies). Waves 1-5
## are byte-identical to spawn_queue_for_wave so early-game tests stay pinned.
static func extended_queue_for_wave(wave_number: int, seed: int) -> Array[StringName]:
	var out := spawn_queue_for_wave(wave_number)
	var w := maxi(wave_number, 1)
	if w < 6:
		return out
	var rng := RngService.make_generator(seed, RngService.STREAM_WAVES + w * 13)
	var extra := w - 5
	var ranged := mini(1 + int(extra / 2), 5) # extra // 2, mini(1 + extra // 2, 5)
	var dasher := mini(int(extra / 2), 4)
	var exploder := mini(int(maxi(extra - 2, 0) / 2), 3)
	var splitter := mini(int(maxi(extra - 3, 0) / 3), 2)
	var adds: Array[StringName] = []
	for i in range(ranged):
		adds.append(&"ranged")
	for i in range(dasher):
		adds.append(&"dasher")
	for i in range(exploder):
		adds.append(&"exploder")
	for i in range(splitter):
		adds.append(&"splitter")
	# Boss waves (every 10th): the warlord leads, adds trail behind.
	if w % 10 == 0:
		out.push_front(&"warlord")
	# Deterministic interleave: shuffle the NEW adds, then weave them through the
	# classic queue so the wave reads as mixed packs instead of sorted blocks.
	for i in range(adds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := adds[i]
		adds[i] = adds[j]
		adds[j] = tmp
	var woven: Array[StringName] = []
	var ai := 0
	for i in range(out.size()):
		woven.append(out[i])
		if ai < adds.size() and (i % 3 == 2 or i == out.size() - 1):
			woven.append(adds[ai])
			ai += 1
	while ai < adds.size():
		woven.append(adds[ai])
		ai += 1
	return woven


## Expand an authored WaveConfig's entries into a flat queue with deterministic
## weight-biased interleaving (no long same-archetype runs).
static func expand_authored_entries(cfg: WaveConfig, seed: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if cfg == null:
		return out
	var buckets: Array = []
	for entry in cfg.spawn_entries:
		if entry.count > 0:
			buckets.append({"id": entry.archetype_id, "left": entry.count, "weight": maxf(entry.spawn_weight, 0.01)})
	if buckets.is_empty():
		return out
	var rng := RngService.make_generator(seed, RngService.STREAM_WAVES + cfg.wave_number * 29)
	var total := 0
	for b in buckets:
		total += int(b["left"])
	var guard := 0
	while total > 0 and guard < 4096:
		guard += 1
		var sum := 0.0
		for b in buckets:
			if int(b["left"]) > 0:
				sum += float(b["weight"])
		if sum <= 0.0:
			break
		var roll := rng.randf() * sum
		var acc := 0.0
		var chosen := 0
		for i in range(buckets.size()):
			if int(buckets[i]["left"]) <= 0:
				continue
			acc += float(buckets[i]["weight"])
			if roll < acc:
				chosen = i
				break
		out.append(buckets[chosen]["id"])
		buckets[chosen]["left"] = int(buckets[chosen]["left"]) - 1
		total -= 1
	return out


## Difficulty scalars for enemy hp / damage / speed at a given wave (>= 1.0). Applied
## per spawned enemy via EnemyBase.apply_difficulty() so shared configs are not mutated.
static func calculate_difficulty_scalars(wave_number: int) -> Dictionary:
	var w := maxi(wave_number, 1)
	return {
		"hp": clampf(1.0 + (w - 1) * 0.12, 1.0, 3.0),
		"damage": clampf(1.0 + (w - 1) * 0.05, 1.0, 2.5),
		"speed": clampf(1.0 + (w - 1) * 0.015, 1.0, 1.3),
	}
