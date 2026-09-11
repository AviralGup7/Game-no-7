extends Node
## Autoload: AudioManager
## Owns SFX voice management, buses, volumes, mute, and audio fallback.
##
## v2 (playback-engine rebuild — see docs/AUDIO_ENGINE.md):
##   * The AudioConfig contract is now LIVE: per-cue cooldown spam guard and
##     per-cue voice cap (SfxPolicy), per-play volume/pitch rolls, and bus
##     routing (including the previously phantom "UI" bus) all come from
##     config, defaulting to AudioConfig.for_cue() tuning.
##   * Click-safe voices: every start ramps in (~12 ms); a stolen or
##     recycled voice fades out over ~30 ms with a 1-t^2 shape before the
##     player is reused (a hard stop is a step function = broadband pop).
##     Steals that need a still-playing victim go through a pending-claim
##     queue so the old sound always gets its fade.
##   * Stealing follows middleware "oldest" semantics: per-cue first (the
##     longest-running instance of a frequent cue is the one to drop), then
##     global oldest as the last resort at the 16-voice ceiling.
##   * The dead parallel music path (hard-switch _music_player / play_music)
##     is gone — MusicManager is the only music owner.
##
## Audio is never required for gameplay correctness: every lookup/play is
## failure-safe and missing cues produce a diagnostic, not a crash.

const MAX_SFX_VOICES := 16
const MAX_UI_VOICES := 4
const UI_TOKEN_BASE := 100
## Click-safe onset for every voice start.
const FADE_IN_SECONDS := 0.012
## Click-safe release; 1-t^2 gain shape so the tail has no high-frequency
## step (research: 30 ms still reads as an abrupt stop, with no pop).
const FADE_OUT_SECONDS := 0.030

var _sfx_pool: Array[AudioStreamPlayer] = []
var _voice_cue: Array[StringName] = []
var _voice_fade: Array[Dictionary] = []
## Pending claims: {player_idx, cue, volume_db, pitch_scale} — fired when the
## stolen victim's fade-out completes so the old sound is never hard-cut.
var _pending: Array[Dictionary] = []
var _configs: Dictionary = {}       # cue -> AudioConfig (explicit registration)
var _default_configs: Dictionary = {}  # cue -> AudioConfig.for_cue() cache
var _policy := SfxPolicy.new()
var _rng := RandomNumberGenerator.new()
var _settings := SettingsData.new()
var _buses_ready := false
## True while the OS has backgrounded the app (Android home/recents). Combines
## with the player's mute setting so audio never plays behind other apps.
var _background_muted := false
var _duck_left := 0.0
var _duck_db := 0.0
## Isolated UI bank: menu clicks never steal a combat SFX voice (and the
## reverse). Tokens are namespaced so SfxPolicy steal stays inside this bank.
var _ui_bank := VoiceBank.new()
var _ui_players: Array[AudioStreamPlayer] = []
var _spatial: SpatialVoicePool = null
var _listener: AudioListener3D = null
var _listener_anchor: Node3D = null
var _mix_id: StringName = MixSnapshot.ID_MENU
var _mix_from: Dictionary = {}
var _mix_to: Dictionary = {}
var _mix_t := 1.0
var _boss_active := false

## cue_id -> AudioStream (registered content; may be empty while audio is added).
var _cues: Dictionary = {}


func _ready() -> void:
	# Mixer policy must survive pause: settings change from the pause menu and
	# background/foreground transitions arrive while the tree may be paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_rng.randomize()
	for i in MAX_SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
		_voice_cue.append(&"")
		_voice_fade.append({})
	_setup_ui_bank()
	_setup_spatial()
	_setup_listener()
	EventBus.settings_changed.connect(apply_settings)
	if not EventBus.pause_changed.is_connected(_on_pause_changed):
		EventBus.pause_changed.connect(_on_pause_changed)
	if not EventBus.game_state_changed.is_connected(_on_game_state_changed):
		EventBus.game_state_changed.connect(_on_game_state_changed)
	if not EventBus.boss_spawned.is_connected(_on_boss_spawned):
		EventBus.boss_spawned.connect(_on_boss_spawned)
	if not EventBus.boss_slain.is_connected(_on_boss_slain):
		EventBus.boss_slain.connect(_on_boss_slain)
	apply_settings(SaveManager.get_settings())
	_apply_mix(MixSnapshot.ID_MENU, true)


func _ensure_buses() -> void:
	var names := AudioServer.get_bus_count()
	for target in ["Music", "SFX", "UI"]:
		var found := false
		for i in names:
			if AudioServer.get_bus_name(i) == target:
				found = true
				break
		if not found:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, target)
	_buses_ready = true


func _setup_ui_bank() -> void:
	_ui_players.clear()
	for i in MAX_UI_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_ui_players.append(p)
	_ui_bank.setup(_ui_players, _policy, UI_TOKEN_BASE, &"UI")
	_ui_bank.clock = Callable(self, "_clock_s")


func _setup_spatial() -> void:
	_spatial = SpatialVoicePool.new()
	_spatial.name = &"SpatialVoices"
	add_child(_spatial)
	_spatial.configure(_policy, Callable(self, "_clock_s"))


func _setup_listener() -> void:
	_listener = AudioListener3D.new()
	_listener.name = &"WorldListener"
	add_child(_listener)
	_listener.current = true


## Register or replace a cue->stream mapping (called by ContentRegistry at
## startup). `config` overrides the built-in AudioConfig.for_cue() contract.
func register_cue(cue_id: StringName, stream: AudioStream, config: AudioConfig = null) -> void:
	if stream == null or not is_instance_valid(stream):
		EventBus.report_warning("Null stream registered for cue %s" % String(cue_id))
		return
	_cues[cue_id] = stream
	if config != null:
		_configs[cue_id] = config
	else:
		_configs.erase(cue_id)
	_default_configs.erase(cue_id)


func has_cue(cue_id: StringName) -> bool:
	return _cues.has(cue_id) and _cues[cue_id] != null


func _config_for(cue_id: StringName) -> AudioConfig:
	if _configs.has(cue_id):
		return _configs[cue_id]
	if not _default_configs.has(cue_id):
		_default_configs[cue_id] = AudioConfig.for_cue(cue_id)
	return _default_configs[cue_id]


func _safe_bus(bus: StringName) -> StringName:
	return bus if (bus in AudioConfig.VALID_BUSES) else &"SFX"


func apply_settings(settings: SettingsData) -> void:
	if settings == null:
		return
	_settings = settings
	if not _buses_ready:
		return
	var master_db := _db(settings.master_volume)
	AudioServer.set_bus_volume_db(0, master_db)
	var mix := _current_mix_offsets()
	# Combat duck never touches SFX or UI — hits must stay readable under a boss tell.
	# Mix snapshots offset SFX/UI independently so pause can silence Foley without
	# muting menu clicks. Music offset is always 0 (MusicManager owns the bed).
	AudioServer.set_bus_volume_db(
		_bus_index("Music"),
		MixSnapshot.compose_bus_db(_db(settings.music_volume), float(mix.get(MixSnapshot.KEY_MUSIC, 0.0)), _duck_db)
	)
	AudioServer.set_bus_volume_db(
		_bus_index("SFX"),
		MixSnapshot.compose_bus_db(_db(settings.sfx_volume), float(mix.get(MixSnapshot.KEY_SFX, 0.0)))
	)
	AudioServer.set_bus_volume_db(
		_bus_index("UI"),
		MixSnapshot.compose_bus_db(_db(settings.sfx_volume), float(mix.get(MixSnapshot.KEY_UI, 0.0)))
	)
	AudioServer.set_bus_mute(0, settings.muted or _background_muted)


## Briefly duck Music under a combat cue so hits/crits/dodges read on a phone speaker.
func duck_music(seconds: float = 0.12, amount_db: float = 4.0) -> void:
	if not is_finite(seconds) or seconds <= 0.0:
		return
	# Combat ducks stay short; a boss tell (>=0.4s) may hold up to 1.1s without
	# letting stacked 0.12s hits extend the mute.
	if seconds >= 0.4:
		_duck_left = minf(maxf(_duck_left, seconds), 1.1)
	elif _duck_left > 0.35:
		# Hit during a boss tell: deepen the duck, keep the tell's remaining time.
		pass
	else:
		_duck_left = minf(maxf(_duck_left, seconds), 0.35)
	_duck_db = maxf(_duck_db, clampf(amount_db, 0.0, 12.0))
	apply_settings(_settings)


func _process(delta: float) -> void:
	if _duck_left > 0.0 and is_finite(delta) and delta > 0.0:
		_duck_left -= delta
		if _duck_left <= 0.0:
			_duck_left = 0.0
			_duck_db = 0.0
			apply_settings(_settings)
	if is_finite(delta) and delta > 0.0:
		_tick_fades(delta)
		_reap_finished()
		_ui_bank.tick(delta)
		_tick_mix(delta)
		_snap_listener()


func _clock_s() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------

## Returns true when a voice was allocated and started, false when the cue was
## missing, the cooldown guard suppressed the play, or the voice ceiling was
## reached (voice limiting).
func play_sfx(cue_id: StringName, volume_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	var stream := _resolve_stream(cue_id)
	if stream == null:
		EventBus.report_warning("SFX cue unavailable: %s" % String(cue_id))
		return false
	var cfg := _config_for(cue_id)
	var now := _clock_s()
	_policy.configure(cue_id, cfg.cooldown, cfg.max_voices)
	var decision := _policy.try_play(cue_id, now)
	var action: StringName = decision["action"]
	if action == SfxPolicy.REJECT:
		# By-design spam guard: suppressing must stay silent or the guard
		# would just move the spam into the report channel.
		return false
	var base_vol := clampf(volume_db, -80.0, 6.0) if is_finite(volume_db) else 0.0
	var base_pitch := clampf(pitch_scale, 0.1, 4.0) if (is_finite(pitch_scale) and pitch_scale > 0.0) else 1.0
	var vol := base_vol + cfg.roll_volume_db(_rng)
	var pitch := base_pitch * cfg.roll_pitch(_rng)
	# UI bus is a dedicated bank: skill/wave/boss SFX never share a voice with
	# a menu click, and a full combat pool cannot steal the pause-overlay tick.
	if AudioConfig.is_ui_bus(cfg.bus):
		return _ui_bank.claim(cue_id, vol, pitch, stream, action, int(decision["steal_token"]))
	# 1) Per-cue steal (policy picked the cue's oldest voice).
	if action == SfxPolicy.STEAL:
		var victim_idx := int(decision["steal_token"])
		if victim_idx >= 0 and victim_idx < _sfx_pool.size() and _sfx_pool[victim_idx].playing:
			return _defer_on_fade(victim_idx, cue_id, vol, pitch, stream)
		# Token already drained (ended between decision and claim): fall
		# through to a normal claim.
	# 2) Any idle player: start immediately.
	for i in _sfx_pool.size():
		if not _sfx_pool[i].playing and _voice_fade[i].is_empty() and not _is_pending_target(i):
			_start_voice(i, cue_id, vol, pitch, stream)
			return true
	# 3) Ceiling reached: globally oldest playing voice (v1 fallback),
	# fade-protected like every other steal.
	var oldest := -1
	var oldest_pos := -1.0
	for i in _sfx_pool.size():
		if _voice_fade[i].is_empty() and not _is_pending_target(i) and _sfx_pool[i].playing:
			var pos: float = _sfx_pool[i].get_playback_position()
			if oldest < 0 or pos > oldest_pos:
				oldest = i
				oldest_pos = pos
	if oldest >= 0:
		return _defer_on_fade(oldest, cue_id, vol, pitch, stream)
	EventBus.report_warning("SFX voice limit reached; dropping: %s" % String(cue_id))
	return false


## World Foley at a point. UI cues refuse spatialization (they stay 2D on the
## UI bank). Far emitters are culled before a voice is claimed.
func play_sfx_at(cue_id: StringName, at: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	return _play_world(cue_id, at, null, volume_db, pitch_scale)


## World Foley that follows `emitter` until the voice ends.
func play_sfx_on(cue_id: StringName, emitter: Node3D, volume_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	if emitter == null or not is_instance_valid(emitter):
		return false
	return _play_world(cue_id, emitter.global_position, emitter, volume_db, pitch_scale)


func _play_world(
		cue_id: StringName,
		at: Vector3,
		emitter: Node3D,
		volume_db: float,
		pitch_scale: float
) -> bool:
	var cfg := _config_for(cue_id)
	if AudioConfig.is_ui_bus(cfg.bus):
		return play_sfx(cue_id, volume_db, pitch_scale)
	if AudioConfig.is_music_bus(cfg.bus):
		return false
	var stream := _resolve_stream(cue_id)
	if stream == null:
		EventBus.report_warning("SFX cue unavailable: %s" % String(cue_id))
		return false
	if _spatial == null:
		return play_sfx(cue_id, volume_db, pitch_scale)
	var listen_at: Vector3 = _spatial.get_listener_position()
	if not SpatialAttenuation.is_hearable(listen_at, at, SpatialVoicePool.MAX_DISTANCE):
		return false
	var now := _clock_s()
	_policy.configure(cue_id, cfg.cooldown, cfg.max_voices)
	var decision := _policy.try_play(cue_id, now)
	var action: StringName = decision["action"]
	if action == SfxPolicy.REJECT:
		return false
	var base_vol := clampf(volume_db, -80.0, 6.0) if is_finite(volume_db) else 0.0
	var base_pitch := clampf(pitch_scale, 0.1, 4.0) if (is_finite(pitch_scale) and pitch_scale > 0.0) else 1.0
	var vol := base_vol + cfg.roll_volume_db(_rng)
	var pitch := base_pitch * cfg.roll_pitch(_rng)
	var steal := int(decision["steal_token"])
	if emitter != null:
		return _spatial.play_on(cue_id, emitter, vol, pitch, stream, action, steal)
	return _spatial.play_at(cue_id, at, vol, pitch, stream, action, steal)


## Bind the 3D listener to a world node (the active player). Passing null parks
## the listener at the last pose; it is never parented onto the player so the
## player scene stays untouched.
func bind_listener(anchor: Node3D) -> void:
	_listener_anchor = anchor if (anchor != null and is_instance_valid(anchor)) else null
	if _spatial != null:
		_spatial.set_listener(_listener_anchor)
	_snap_listener()


## GAME_OVER freeze: park the 3D listener and stop world Foley. The UI bank
## stays alive so summary buttons still click. Combat 2D SFX are not stolen
## from the menu; spatial is the leak under the overlay.
func isolate_run() -> void:
	bind_listener(null)
	if _spatial != null:
		_spatial.isolate_run()


func set_spatial_budget(cap: int) -> void:
	if _spatial != null:
		_spatial.apply_budget(cap)


func _snap_listener() -> void:
	if _listener == null:
		return
	if _listener_anchor == null or not is_instance_valid(_listener_anchor):
		return
	_listener.global_transform = _listener_anchor.global_transform


func _on_pause_changed(is_paused: bool) -> void:
	var state := GameRoot.get_current_state() if GameRoot != null else &"playing"
	_apply_mix(MixSnapshot.id_for_run(state, is_paused, _boss_active), false)


func _on_game_state_changed(_previous: StringName, current: StringName) -> void:
	var paused := GameRoot.is_paused() if GameRoot != null else false
	_apply_mix(MixSnapshot.id_for_run(current, paused, _boss_active), false)


func _on_boss_spawned(_boss: Node, _boss_id: StringName) -> void:
	_boss_active = true
	var state := GameRoot.get_current_state() if GameRoot != null else &"playing"
	var paused := GameRoot.is_paused() if GameRoot != null else false
	_apply_mix(MixSnapshot.id_for_run(state, paused, true), false)


func _on_boss_slain(_boss_id: StringName) -> void:
	_boss_active = false
	var state := GameRoot.get_current_state() if GameRoot != null else &"playing"
	var paused := GameRoot.is_paused() if GameRoot != null else false
	_apply_mix(MixSnapshot.id_for_run(state, paused, false), false)


func _apply_mix(id: StringName, instant: bool) -> void:
	if id == _mix_id and _mix_t >= 1.0 and not instant:
		return
	_mix_from = _current_mix_offsets()
	_mix_id = id
	_mix_to = MixSnapshot.offsets_for(id)
	_mix_t = 1.0 if instant else 0.0
	if instant:
		apply_settings(_settings)


func _current_mix_offsets() -> Dictionary:
	if _mix_t >= 1.0 or _mix_to.is_empty():
		return MixSnapshot.offsets_for(_mix_id)
	if _mix_from.is_empty():
		return _mix_to
	var k := MixSnapshot.shaped_t(_mix_t)
	return {
		MixSnapshot.KEY_SFX: MixSnapshot.lerp_db(
			float(_mix_from.get(MixSnapshot.KEY_SFX, 0.0)),
			float(_mix_to.get(MixSnapshot.KEY_SFX, 0.0)),
			k
		),
		MixSnapshot.KEY_UI: MixSnapshot.lerp_db(
			float(_mix_from.get(MixSnapshot.KEY_UI, 0.0)),
			float(_mix_to.get(MixSnapshot.KEY_UI, 0.0)),
			k
		),
		MixSnapshot.KEY_MUSIC: MixSnapshot.lerp_db(
			float(_mix_from.get(MixSnapshot.KEY_MUSIC, 0.0)),
			float(_mix_to.get(MixSnapshot.KEY_MUSIC, 0.0)),
			k
		),
	}


func _tick_mix(delta: float) -> void:
	if _mix_t >= 1.0:
		return
	_mix_t = clampf(_mix_t + delta / MixSnapshot.snapshot_fade_seconds(), 0.0, 1.0)
	apply_settings(_settings)


## The victim still has audio in the air: give it its fade-out and queue this
## play to fire the moment the player is truly free (never a hard cut).
func _defer_on_fade(idx: int, cue_id: StringName, vol: float, pitch: float, stream: AudioStream) -> bool:
	if not _begin_fade_out(idx):
		# No audio left to protect (ended between check and fade): claim now.
		_start_voice(idx, cue_id, vol, pitch, stream)
		return true
	_pending.append({"player_idx": idx, "cue": cue_id, "volume_db": vol, "pitch_scale": pitch, "stream": stream})
	return true


func _is_pending_target(idx: int) -> bool:
	for entry in _pending:
		if int((entry as Dictionary)["player_idx"]) == idx:
			return true
	return false


func _start_voice(idx: int, cue_id: StringName, vol: float, pitch: float, stream: AudioStream) -> void:
	var player := _sfx_pool[idx]
	var cfg := _config_for(cue_id)
	player.bus = _safe_bus(cfg.bus)
	player.stream = stream
	# Defensive sanity clamps: authored values are trusted, but a bad tween or
	# lerp must never blast the mix or produce a negative-pitch voice.
	player.pitch_scale = clampf(pitch, 0.1, 4.0) if (is_finite(pitch) and pitch > 0.0) else 1.0
	player.volume_db = -80.0
	player.play()
	_voice_cue[idx] = cue_id
	_policy.voice_started(cue_id, idx)
	_policy.note_played(cue_id, _clock_s())
	_begin_fade_in(idx, clampf(vol, -80.0, 6.0))


# --- Click-safe fades --------------------------------------------------------

func _begin_fade_in(idx: int, to_db: float) -> void:
	_voice_fade[idx] = {
		"kind": "in",
		"t": 0.0,
		"dur": FADE_IN_SECONDS,
		"from": -80.0,
		"to": to_db,
	}
	_sfx_pool[idx].volume_db = -80.0


## Starts the release fade unless the voice is already silent or a fade is in
## flight. Returns true when a fade is now owning the player.
func _begin_fade_out(idx: int) -> bool:
	var player := _sfx_pool[idx]
	if not player.playing:
		return false
	if not _voice_fade[idx].is_empty():
		return true  # a fade is already in flight for this voice
	_voice_fade[idx] = {
		"kind": "out",
		"t": 0.0,
		"dur": FADE_OUT_SECONDS,
		"from": player.volume_db,
		"to": -80.0,
	}
	return true


func _tick_fades(delta: float) -> void:
	for i in _sfx_pool.size():
		var fade: Dictionary = _voice_fade[i]
		if fade.is_empty():
			continue
		var f: Dictionary = fade
		var k := clampf(float(f["t"]) + delta / maxf(float(f["dur"]), 0.001), 0.0, 1.0)
		var from := float(f["from"])
		var to := float(f["to"])
		var player := _sfx_pool[i]
		if String(f["kind"]) == "out":
			# 1-t^2 gain shape: no high-frequency step at the tail.
			player.volume_db = to + (from - to) * (1.0 - k * k)
		else:
			player.volume_db = from + (to - from) * k
		if k >= 1.0:
			_finish_fade(i)


func _finish_fade(idx: int) -> void:
	var fade: Dictionary = _voice_fade[idx]
	var kind := String(fade.get("kind", ""))
	_voice_fade[idx] = {}
	var player := _sfx_pool[idx]
	if kind == "out":
		player.stop()
		var cue: StringName = _voice_cue[idx]
		if cue != &"":
			_policy.voice_ended(cue, idx)
			_voice_cue[idx] = &""
		_fire_pending(idx)


func _fire_pending(idx: int) -> void:
	var keep: Array[Dictionary] = []
	for entry in _pending:
		if int((entry as Dictionary)["player_idx"]) != idx:
			keep.append(entry)
			continue
		# If the slot was reused meanwhile (pathological double-claim), drop
		# the stale request rather than clobber the live voice.
		if _voice_cue[idx] != &"" or _sfx_pool[idx].playing:
			continue
		var e: Dictionary = entry
		_start_voice(idx, StringName(e["cue"]), float(e["volume_db"]), float(e["pitch_scale"]), e["stream"])
	_pending = keep


## Natural end of a voice (played out, no fade in flight) releases its
## per-cue policy slot.
func _reap_finished() -> void:
	for i in _sfx_pool.size():
		if _voice_fade[i].is_empty() and _voice_cue[i] != &"" and not _sfx_pool[i].playing:
			_policy.voice_ended(_voice_cue[i], i)
			_voice_cue[i] = &""


func _resolve_stream(cue_id: StringName) -> AudioStream:
	if not _cues.has(cue_id):
		return null
	var s: Variant = _cues[cue_id]
	return s as AudioStream


## Null-safe stream lookup for the MusicManager (missing cues stay silent).
func get_cue_stream(cue_id: StringName) -> AudioStream:
	return _resolve_stream(cue_id)


func get_active_voice_count() -> int:
	var n := 0
	for p in _sfx_pool:
		if p.playing:
			n += 1
	return n


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


## Live bus preview for the settings sliders: writes straight to the mixer
## without touching SettingsData, so Back still discards unapplied edits while
## the player hears the mix immediately. Callers restore via apply_settings().
func preview_bus_volume(bus_key: String, linear: float) -> void:
	if not _buses_ready:
		return
	match bus_key:
		"master":
			AudioServer.set_bus_volume_db(0, _db(linear))
		"music":
			AudioServer.set_bus_volume_db(_bus_index("Music"), _db(linear) - _duck_db)
		"sfx":
			AudioServer.set_bus_volume_db(_bus_index("SFX"), _db(linear))
		"ui":
			AudioServer.set_bus_volume_db(_bus_index("UI"), _db(linear))


func _db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return linear_to_db(clampf(linear, 0.0, 1.0))


## (`bus_name`, not `name`: that shadows the Node.name property the analyzer
## checks against.)
func _bus_index(bus_name: String) -> int:
	for i in AudioServer.get_bus_count():
		if AudioServer.get_bus_name(i) == bus_name:
			return i
	return 0


func _notification(what: int) -> void:
	# Android backgrounds the app without pausing the tree: mute the master bus
	# so music/SFX never play behind other apps, then restore on return. The
	# mute combines with (never overwrites) the player's own mute setting.
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, \
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_set_background_muted(true)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_set_background_muted(false)


func _set_background_muted(muted: bool) -> void:
	if _background_muted == muted:
		return
	_background_muted = muted
	apply_settings(_settings)


func is_background_muted() -> bool:
	return _background_muted


func get_debug_snapshot() -> Dictionary:
	return {
		"active_sfx_voices": get_active_voice_count(),
		"max_sfx_voices": MAX_SFX_VOICES,
		"registered_cues": _cues.size(),
		"pending_claims": _pending.size(),
		"muted": _settings.muted,
		"background_muted": _background_muted,
		"voice_policy": _policy.get_debug_snapshot(),
		"ui_voices": _ui_bank.active_count(),
		"spatial": _spatial.get_debug_snapshot() if _spatial != null else {},
		"mix": MixSnapshot.debug_dict(_mix_id),
	}
