class_name Narrator
extends RefCounted

## The voice that reads authored copy aloud: short arena lines, per-wave beats, and mode intros
## delivered through EventBus.announcement. No tables of its own any more.
##
## `scripts/meta/narrator.gd` used to be four hand-written Dictionaries: `ARENA_LORE` (keyed by
## arena id, with a `name` key nobody read and a fall-through that gave **The Pit's** lines to any
## arena not in the table), `MODE_INTRO` (keyed by a second `narrator_id` on each mode, which no
## caller followed, so the two modes that meant to borrow Standard's intro got their own anyway),
## `CAMPAIGN_BEATS` (keyed by wave number, duplicating the arc the campaign's spawn `match` already
## scripted), and `ENEMY_BLURBS` (five of eight archetypes, read by nobody — deleted, not migrated).
## Every line now lives on the thing it describes: the arena config, the mode config, and the mode's
## own wave-plan rows, so the encounter and the sentence about it cannot disagree.
##
## Pure static API — no tree access.

const ARENA_CONFIG_DIR := "res://data/arenas/"


static func arena_intro(arena_id: StringName) -> String:
	var cfg := _arena(arena_id)
	return cfg.lore_intro if cfg != null else ""


static func arena_mid(arena_id: StringName) -> String:
	var cfg := _arena(arena_id)
	return cfg.lore_mid if cfg != null else ""


static func arena_late(arena_id: StringName) -> String:
	var cfg := _arena(arena_id)
	return cfg.lore_late if cfg != null else ""


## What the mode says as its run begins. `ArenaConfig.lore_intro` is the fallback the table used to
## offer; it is kept as an explicit choice by the caller, not a Dictionary default.
static func mode_intro(mode_id: StringName) -> String:
	return GameMode.intro_line(mode_id)


static func victory_line(mode_id: StringName) -> String:
	return GameMode.victory_line(mode_id)


## The announcer's line for one scripted wave of a mode, or "" when the wave has no beat. Replaces
## `campaign_beat()`, which returned a Dictionary out of a table the mode's spawn queue already
## had its own copy of.
static func beat_text(mode_id: StringName, wave_number: int) -> String:
	var plan := GameMode.beat_for_wave(mode_id, wave_number)
	if plan == null or not plan.has_beat():
		return ""
	if plan.beat_title.is_empty():
		return plan.beat_line
	if plan.beat_line.is_empty():
		return plan.beat_title
	return "%s — %s" % [plan.beat_title, plan.beat_line]


## Emit the right announcement for a wave start given mode + arena context. Which modes have beats is
## not a question this function answers any more — it asks the mode — so a new scripted mode is
## announced without touching this file. The severity cadence stays here: every fifth wave reads as a
## milestone, which is how the announcer works, not what the author wrote.
static func announce_wave(mode_id: StringName, arena_id: StringName, wave_number: int) -> void:
	if EventBus == null:
		return
	var beat := beat_text(mode_id, wave_number)
	if not beat.is_empty():
		_emit(&"campaign_beat", beat, &"warning" if wave_number % 5 == 0 else &"info")
		return
	# Light flavour on milestone waves for other modes. Wave 1 is the mode's own line and the arena's
	# is its fallback; 5 and every tenth after that belong to the arena.
	if wave_number == 1:
		var intro := mode_intro(mode_id)
		_emit(&"narrator", intro if not intro.is_empty() else arena_intro(arena_id), &"info")
	elif wave_number == 5:
		_emit(&"narrator", arena_mid(arena_id), &"info")
	elif wave_number >= 10 and wave_number % 10 == 0:
		_emit(&"narrator", arena_late(arena_id), &"warning")


static func announce_run_start(mode_id: StringName, arena_id: StringName) -> void:
	if EventBus == null:
		return
	var line := mode_intro(mode_id)
	_emit(&"narrator", line if not line.is_empty() else arena_intro(arena_id), &"info")


static func announce_victory(mode_id: StringName) -> void:
	if EventBus == null:
		return
	_emit(&"victory", victory_line(mode_id), &"victory")


## One wire for every line this class produces. A mode with an empty intro_line, or an arena with no
## lore_mid, used to put a banner on screen with no text in it: silence is the correct reading of
## authored nothing, and it belongs here rather than in each caller.
static func _emit(text_key: StringName, text: String, severity: StringName) -> void:
	if text.is_empty():
		return
	EventBus.announcement.emit(text_key, text, severity)


## Registry first, then the file: `ArenaConfig` is the arena's authored identity, and the announcer
## is handed only an id by WaveManager. Same path ArenaHazards takes, and it is reached at most a few
## times per run (run start, wave 5, wave 10) — the headless harness never gets here, because every
## announce_* above returns as soon as EventBus is missing. A missing arena is answered with no
## line, never with another arena's.
static func _arena(arena_id: StringName) -> ArenaConfig:
	if arena_id == &"":
		return null
	if ContentRegistry != null:
		var registered: ArenaConfig = ContentRegistry.get_arena(arena_id)
		if registered != null:
			return registered
	var path := "%s%s.tres" % [ARENA_CONFIG_DIR, String(arena_id)]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ArenaConfig
