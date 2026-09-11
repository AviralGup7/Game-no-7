class_name MixSnapshot
extends RefCounted

## Named mixer snapshots. Offsets (dB) sit on top of the player's SettingsData
## volumes; they never start/stop music — MusicManager remains the only music
## owner. Combat duck (AudioManager.duck_music) is a separate, shorter path
## that only touches the Music bus.
##
## Snapshots exist so pause/menu/upgrade can silence world SFX without muting
## the UI bus (the v2 UI bus already exists; without a snapshot, pause still
## left every enemy hit playing at full mix under the overlay).

const ID_MENU := &"menu"
const ID_COMBAT := &"combat"
const ID_BOSS := &"boss"
const ID_PAUSED := &"paused"
const ID_SILENT := &"silent"
const ID_UPGRADE := &"upgrade"
const ID_GAME_OVER := &"game_over"

const KEY_SFX := &"sfx"
const KEY_UI := &"ui"
const KEY_MUSIC := &"music"

const SILENCE_DB := -80.0
const OFFSET_MIN := -80.0
const OFFSET_MAX := 6.0

## game_state StringName -> snapshot id. Pause is an overlay and wins.
const STATE_MAP := {
	&"main_menu": ID_MENU,
	&"starting_run": ID_COMBAT,
	&"playing": ID_COMBAT,
	&"wave_transition": ID_COMBAT,
	&"upgrade_selection": ID_UPGRADE,
	&"paused": ID_PAUSED,
	&"game_over": ID_GAME_OVER,
	&"loading": ID_MENU,
	&"error": ID_MENU,
}


static func is_known(id: StringName) -> bool:
	return id in [
		ID_MENU, ID_COMBAT, ID_BOSS, ID_PAUSED, ID_SILENT, ID_UPGRADE, ID_GAME_OVER
	]


static func clamp_offset(db: float) -> float:
	if not is_finite(db):
		return 0.0
	return clampf(db, OFFSET_MIN, OFFSET_MAX)


## Bus offsets in dB for a snapshot. Music is always 0 — beds stay with
## MusicManager (a snapshot must not fight the stem mixer).
static func offsets_for(id: StringName) -> Dictionary:
	match id:
		ID_PAUSED:
			# World Foley out; menu clicks stay at the player's SFX slider.
			return {KEY_SFX: -14.0, KEY_UI: 0.0, KEY_MUSIC: 0.0}
		ID_MENU:
			return {KEY_SFX: -10.0, KEY_UI: 0.0, KEY_MUSIC: 0.0}
		ID_UPGRADE:
			return {KEY_SFX: -8.0, KEY_UI: 0.0, KEY_MUSIC: 0.0}
		ID_GAME_OVER:
			return {KEY_SFX: -6.0, KEY_UI: 0.0, KEY_MUSIC: 0.0}
		ID_SILENT:
			return {KEY_SFX: SILENCE_DB, KEY_UI: -6.0, KEY_MUSIC: 0.0}
		ID_BOSS:
			# Boss stingers stay readable; MusicManager already peaks stems.
			return {KEY_SFX: 0.0, KEY_UI: 0.0, KEY_MUSIC: 0.0}
		_:
			return {KEY_SFX: 0.0, KEY_UI: 0.0, KEY_MUSIC: 0.0}


static func sfx_offset(id: StringName) -> float:
	return float(offsets_for(id).get(KEY_SFX, 0.0))


static func ui_offset(id: StringName) -> float:
	return float(offsets_for(id).get(KEY_UI, 0.0))


static func music_offset(id: StringName) -> float:
	return float(offsets_for(id).get(KEY_MUSIC, 0.0))


## Pause overlay always wins; otherwise the game-state map. An unknown state
## falls back to combat so a missed wire never silences the mix.
static func id_for_game_state(state: StringName, paused: bool) -> StringName:
	if paused:
		return ID_PAUSED
	if STATE_MAP.has(state):
		return STATE_MAP[state]
	return ID_COMBAT


## Boss fights stay on the combat snapshot (SFX readable) unless paused.
static func id_for_run(state: StringName, paused: bool, boss_active: bool) -> StringName:
	if paused:
		return ID_PAUSED
	if boss_active and state in [&"playing", &"wave_transition"]:
		return ID_BOSS
	return id_for_game_state(state, false)


static func compose_bus_db(settings_db: float, offset_db: float, extra_duck_db: float = 0.0) -> float:
	var base := settings_db if is_finite(settings_db) else 0.0
	var off := clamp_offset(offset_db)
	var duck := extra_duck_db if (is_finite(extra_duck_db) and extra_duck_db > 0.0) else 0.0
	return clampf(base + off - duck, SILENCE_DB, OFFSET_MAX)


static func lerp_db(from_db: float, to_db: float, t: float) -> float:
	var a := from_db if is_finite(from_db) else SILENCE_DB
	var b := to_db if is_finite(to_db) else SILENCE_DB
	var k := clampf(t, 0.0, 1.0) if is_finite(t) else 1.0
	return lerpf(a, b, k)


## Smoothstep for snapshot fades (gentle at both ends; musical for ~120 ms).
static func shaped_t(t: float) -> float:
	var k := clampf(t, 0.0, 1.0) if is_finite(t) else 1.0
	return k * k * (3.0 - 2.0 * k)


static func snapshot_fade_seconds() -> float:
	return 0.12


## UI bus must never inherit the SFX snapshot cut (pause overlay clicks).
static func ui_follows_sfx(id: StringName) -> bool:
	return sfx_offset(id) == ui_offset(id) and id == ID_COMBAT


static func debug_dict(id: StringName) -> Dictionary:
	var off := offsets_for(id)
	return {
		"id": String(id),
		"sfx": float(off[KEY_SFX]),
		"ui": float(off[KEY_UI]),
		"music": float(off[KEY_MUSIC]),
	}
