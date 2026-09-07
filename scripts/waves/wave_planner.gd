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
			heavy = 1 + int(floor(extra / 2.0))
	return {"basic": basic, "fast": fast, "heavy": heavy}


## Difficulty scalars for enemy hp / damage / speed at a given wave (>= 1.0). Applied
## per spawned enemy via EnemyBase.apply_difficulty() so shared configs are not mutated.
static func calculate_difficulty_scalars(wave_number: int) -> Dictionary:
	var w := maxi(wave_number, 1)
	return {
		"hp": clampf(1.0 + (w - 1) * 0.12, 1.0, 3.0),
		"damage": clampf(1.0 + (w - 1) * 0.05, 1.0, 2.5),
		"speed": clampf(1.0 + (w - 1) * 0.015, 1.0, 1.3),
	}
