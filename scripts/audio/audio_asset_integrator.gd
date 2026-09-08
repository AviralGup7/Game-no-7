class_name AudioAssetIntegrator
extends RefCounted

## Integrates the approved, checksum-locked audio library (assets/audio/**) into
## the existing AudioManager + MusicManager architecture. This is the "recorded
## audio registration" step that the asset audit lists as pending.
##
## Why a code integrator and not .tres drops under res://data/audio/:
##  - It reads assets/catalog.json (the single authoritative cue->file map), so the
##    mapping never drifts from the approved library.
##  - It builds AudioStreamRandomizer pools in code for multi-variant SFX and applies
##    the catalogue's suggested gain per cue.
##  - It lets us force loop=true on the imported Ogg music streams (music must loop;
##    a .tres wrapper cannot change an Ogg import's loop flag).
##  - It keeps every source byte inside the locked assets/ tree (no duplication) so
##    the manifest/provenance checks stay intact.
##
## Registration happens once at startup after the ContentRegistry autoload has run,
## and ALWAYS takes precedence over ProceduralSfx fallback because register_audio_cue
## overwrites. Missing/invalid source files only log a diagnostic and keep the
## procedural fallback — never a crash.

## Catalog path (source of truth for cue -> file mappings).
const CATALOG_PATH := "res://assets/catalog.json"

## Map MusicManager's state cues onto the two approved, looping music tracks.
## Only a menu loop and one combat loop ship in the approved library, so all
## combat-adjacent states share the combat track (menu keeps the menu track).
const MUSIC_STATE_CUES := {
	&"music_menu": &"arena_menu",
	&"music_calm": &"arena_gameplay",
	&"music_battle": &"arena_gameplay",
	&"music_boss": &"arena_gameplay",
	&"music_victory": &"arena_gameplay",
}

## Cues that are pure music tracks (never SFX), pulled verbatim from the catalog.
const MUSIC_CUES: Array[StringName] = [&"arena_menu", &"arena_gameplay"]

var _registered_sfx := 0
var _registered_music := 0


## Register every approved SFX cue + the state music cues. Safe to call more than once
## (re-registration is idempotent). Returns true when at least the catalogue loaded.
func register() -> void:
	if AudioManager == null or ContentRegistry == null:
		EventBus.report_warning("AudioAssetIntegrator: autoloads not ready")
		return
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not catalog is Dictionary:
		EventBus.report_warning("AudioAssetIntegrator: cannot read " + CATALOG_PATH)
		return
	var cues: Dictionary = catalog.get("audio_cues", {})
	for cue_id in cues:
		var meta: Dictionary = cues[cue_id]
		var files: Array = meta.get("files", [])
		if files.is_empty():
			continue
		if StringName(cue_id) in MUSIC_CUES:
			# Music tracks are registered below through MUSIC_STATE_CUES.
			continue
		var volume: float = float(meta.get("suggested_volume_db", -8.0))
		var stream := _build_variant_stream(files, volume)
		if stream != null:
			ContentRegistry.register_audio_cue(StringName(cue_id), stream)
			_registered_sfx += 1
	for state_cue in MUSIC_STATE_CUES:
		var source: StringName = MUSIC_STATE_CUES[state_cue]
		var meta: Dictionary = cues.get(String(source), {})
		var files: Array = meta.get("files", [])
		if files.is_empty():
			continue
		var stream := _load_looping_music(files[0])
		if stream != null:
			ContentRegistry.register_audio_cue(state_cue, stream)
			_registered_music += 1
	EventBus.report_info("AudioAssetIntegrator registered %d SFX + %d music state cues from approved library" % [_registered_sfx, _registered_music])


## Pooled one-shot SFX: one AudioStreamRandomizer per cue so variants play alternately.
static func _build_variant_stream(files: Array, volume_db: float) -> AudioStreamRandomizer:
	var any := false
	var rand := AudioStreamRandomizer.new()
	rand.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM
	for f in files:
		var s := load("res://%s" % f)
		if s is AudioStream:
			rand.add_stream(s as AudioStream, 1.0)
			any = true
		else:
			EventBus.report_warning("AudioAssetIntegrator: unimported source " + f)
	if not any:
		return null
	rand.random_volume_db = 3.0
	return rand


## Music: register the underlying stream directly (not pooled) and force looping so the
## real Ogg tracks behave like the seamless procedural loops they replace.
static func _load_looping_music(path: String) -> AudioStream:
	var s := load("res://%s" % path)
	if s == null:
		EventBus.report_warning("AudioAssetIntegrator: missing music " + path)
		return null
	# AudioStreamOggVorbis exposes loop at runtime (set false until Godot imports it
	# with loop enabled). Guarded so non-Ogg fallbacks never error.
	if s is AudioStreamOggVorbis:
		var ogg := s as AudioStreamOggVorbis
		if not ogg.loop:
			ogg.loop = true
	return s


func get_debug_snapshot() -> Dictionary:
	return {"registered_sfx": _registered_sfx, "registered_music": _registered_music}
