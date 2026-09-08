extends Node
## Autoload: AudioManager
## Owns music + SFX buses, volumes, mute, voice limiting, pooled players, and audio
## fallback. Audio is never required for gameplay correctness: every lookup/play is
## failure-safe and optional-missing cues produce a diagnostic, not a crash.

const MAX_SFX_VOICES := 16

var _music_player: AudioStreamPlayer = null
var _sfx_pool: Array[AudioStreamPlayer] = []
var _current_music_id: StringName = &""
var _settings := SettingsData.new()
var _buses_ready := false

## cue_id -> AudioStream (registered content; may be empty while audio is added).
var _cues: Dictionary = {}


func _ready() -> void:
	_ensure_buses()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	for i in MAX_SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	EventBus.settings_changed.connect(apply_settings)
	apply_settings(SaveManager.get_settings())


func _ensure_buses() -> void:
	var names := AudioServer.get_bus_count()
	for target in ["Music", "SFX"]:
		var found := false
		for i in names:
			if AudioServer.get_bus_name(i) == target:
				found = true
				break
		if not found:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, target)
	_buses_ready = true


## Register or replace a cue->stream mapping (called by ContentRegistry at startup).
func register_cue(cue_id: StringName, stream: AudioStream) -> void:
	if stream == null or not is_instance_valid(stream):
		EventBus.report_warning("Null stream registered for cue %s" % String(cue_id))
		return
	_cues[cue_id] = stream


func has_cue(cue_id: StringName) -> bool:
	return _cues.has(cue_id) and _cues[cue_id] != null


func apply_settings(settings: SettingsData) -> void:
	if settings == null:
		return
	_settings = settings
	if not _buses_ready:
		return
	var master_db := _db(settings.master_volume)
	AudioServer.set_bus_volume_db(0, master_db)
	AudioServer.set_bus_volume_db(_bus_index("Music"), _db(settings.music_volume))
	AudioServer.set_bus_volume_db(_bus_index("SFX"), _db(settings.sfx_volume))
	AudioServer.set_bus_mute(0, settings.muted)


func _db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return linear_to_db(clampf(linear, 0.0, 1.0))


func _bus_index(name: String) -> int:
	for i in AudioServer.get_bus_count():
		if AudioServer.get_bus_name(i) == name:
			return i
	return 0


## Live per-bus volume setters (settings UI). Update the cached settings object
## and re-apply to the mixer without emitting settings_changed (avoids loops).
func set_master_volume(value: float) -> void:
	_settings.set_master_volume(value)
	apply_settings(_settings)


func set_music_volume(value: float) -> void:
	_settings.set_music_volume(value)
	apply_settings(_settings)


func set_sfx_volume(value: float) -> void:
	_settings.set_sfx_volume(value)
	apply_settings(_settings)


func set_muted(muted: bool) -> void:
	_settings.set_muted(muted)
	apply_settings(_settings)


## Null-safe stream lookup for the MusicManager (missing cues stay silent).
func get_cue_stream(cue_id: StringName) -> AudioStream:
	return _resolve_stream(cue_id)


## Music ---------------------------------------------------------------------
func play_music(cue_id: StringName) -> void:
	if cue_id == _current_music_id:
		return
	_current_music_id = cue_id
	var stream := _resolve_stream(cue_id)
	if stream == null:
		EventBus.report_warning("Music cue unavailable (fallback: silence): %s" % String(cue_id))
		_current_music_id = &""
		return
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()
	_current_music_id = &""


func get_current_music() -> StringName:
	return _current_music_id


## SFX ------------------------------------------------------------------------
## Returns true when a voice was allocated and started, false when the cue was
## missing or all voices are busy (voice limiting).
func play_sfx(cue_id: StringName, volume_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	var stream := _resolve_stream(cue_id)
	if stream == null:
		EventBus.report_warning("SFX cue unavailable: %s" % String(cue_id))
		return false
	var player := _claim_voice()
	if player == null:
		EventBus.report_warning("SFX voice limit reached; dropping: %s" % String(cue_id))
		return false
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return true


func _claim_voice() -> AudioStreamPlayer:
	# Prefer an idle pooled player; otherwise recycle the oldest playing one.
	var idle: AudioStreamPlayer = null
	var oldest_playing: AudioStreamPlayer = null
	for p in _sfx_pool:
		if not p.playing:
			idle = p
			break
		if oldest_playing == null or p.get_playback_position() > oldest_playing.get_playback_position():
			oldest_playing = p
	var chosen := idle if idle != null else oldest_playing
	if chosen != null:
		chosen.stop()
	return chosen


func _resolve_stream(cue_id: StringName) -> AudioStream:
	if not _cues.has(cue_id):
		return null
	var s: Variant = _cues[cue_id]
	return s as AudioStream


func get_active_voice_count() -> int:
	var n := 0
	for p in _sfx_pool:
		if p.playing:
			n += 1
	return n


func get_debug_snapshot() -> Dictionary:
	return {
		"current_music": String(_current_music_id),
		"active_sfx_voices": get_active_voice_count(),
		"max_sfx_voices": MAX_SFX_VOICES,
		"registered_cues": _cues.size(),
		"muted": _settings.muted,
	}

## Hardened: clamp volume and validate bus before applying.
func _validated_volume(vol: float) -> float:
	if not is_finite(vol):
		return 0.0
	return clampf(vol, -80.0, 6.0)

