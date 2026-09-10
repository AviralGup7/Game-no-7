class_name MusicManager
extends Node

## Adaptive music director (v2 — real layered mixing).
##
## Rebuild of the "4-layer intensity mixer" v1 faked with a volume nudge on a
## single bed (see docs/AUDIO_ENGINE.md for the research log):
##
##   * **Vertical layering.** The state bed (menu/calm/battle/boss/victory)
##     keeps v1's pop-free A/B crossfade; on top of it, optional intensity
##     STEMS ride two dedicated players. Stem convention: for a resolved bed
##     cue `music_battle`, stems are `music_battle_l2` / `music_battle_l3`
##     (registered through the normal cue pipeline — code, .tres or the
##     approved asset library). No stems registered -> single-bed behavior,
##     i.e. v1 (graceful degradation; music is never required).
##   * **Asymmetric intensity fades.** Tension snaps UP fast (0.6 s) and
##     releases SLOW (2.0 s) — the standard adaptive-music rule ("tension
##     should snap up fast and release slowly").
##   * **Dwell suppression.** A downward layer move holds for
##     LAYER_DWELL_SECONDS so heat flicker during rapid hits cannot machine-
##     gun the stems; upward moves bypass the dwell entirely.
##   * **Phase sync.** A stem joining mid-track seeks to the active bed's
##     playback position so layered loops stay in step (best-effort).
##   * **No hard cuts, ever.** A stem whose stream changes fades its old
##     audio out, swaps at the fade end, then fades the new stream in.
##   * The pure decisions (layer mapping, stem levels, fade durations) are
##     static and unit-tested headlessly.
##
## Heat model and state machine (menu/calm/battle/boss/victory, calm<->battle
## hysteresis, boss->battle handoff) carry over from v1.

signal music_state_changed(old_state: StringName, new_state: StringName)

const STATE_SILENT := &"silent"
const STATE_MENU := &"menu"
const STATE_CALM := &"calm"
const STATE_BATTLE := &"battle"
const STATE_BOSS := &"boss"
const STATE_VICTORY := &"victory"

const BED_LEVEL_DB := -8.0
const SILENCE_DB := -60.0

## Bed crossfade (state changes): unchanged from v1.
const CROSSFADE_SECONDS := 1.5
## Stem intensity fades: up fast, down slow (asymmetric by design).
const STEM_FADE_UP_SECONDS := 0.6
const STEM_FADE_DOWN_SECONDS := 2.0
## Minimum settle time before a DOWNWARD layer move is allowed to fire.
const LAYER_DWELL_SECONDS := 0.4

## How many stems ride above the bed (l2, l3).
const STEM_COUNT := 2

const HEAT_DECAY_PER_SECOND := 0.25
const HEAT_PER_KILL := 0.12
const HEAT_PER_DAMAGE := 0.02

var _state: StringName = STATE_SILENT
var _heat := 0.0
var _layer := 0
var _players: Array[AudioStreamPlayer] = []  # the two A/B bed players
var _active_index := 0
var _fading := 0.0
## Outgoing player's volume when the current crossfade started. Capturing it
## (instead of assuming full level) keeps rapid state changes pop-free.
var _outgoing_from_db := SILENCE_DB
## Active state's resolved bed cue id (stems are named after it) and the
## stems that state can use.
var _active_bed_cue := &""
var _active_stem_cues: Array[StringName] = []
## Per-stem state: {player, cue, stream, from, to, t, dur,
##                  pending: {stream, db} for fade-out -> swap -> fade-in}
var _stems: Array[Dictionary] = []
var _dwell_left := 0.0
var _wired := false


func _ready() -> void:
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = SILENCE_DB
		add_child(p)
		_players.append(p)
	for i in STEM_COUNT:
		var sp := AudioStreamPlayer.new()
		sp.bus = "Music"
		sp.volume_db = SILENCE_DB
		add_child(sp)
		_stems.append({
			"player": sp,
			"cue": &"",
			"stream": null,
			"from": SILENCE_DB,
			"to": SILENCE_DB,
			"t": 0.0,
			"dur": 0.0,
			"pending": {},
		})


# ---------------------------------------------------------------------------
# Pure, headless-testable core
# ---------------------------------------------------------------------------

## Intensity layer (0..3) for a state + heat value. Boss always peaks;
## battle maps heat across 1..3; everything else sits at the bed.
static func target_layer_for(state: StringName, heat: float) -> int:
	var h := clampf(heat, 0.0, 1.5)
	match state:
		STATE_BATTLE:
			return clampi(1 + int(h * 2.0), 0, 3)
		STATE_BOSS:
			return 3
		_:
			return 0


## Stem target levels (dB) for a layer: [l2, l3]. SILENCE_DB = off.
static func stem_targets(layer: int) -> Array[float]:
	match layer:
		0:
			return [SILENCE_DB, SILENCE_DB]
		1:
			return [-14.0, SILENCE_DB]
		2:
			return [-9.0, SILENCE_DB]
		_:
			return [-9.0, -5.0]


## Asymmetric fade duration: rising intensity is immediate, falling is slow.
static func stem_fade_seconds(rising: bool) -> float:
	return STEM_FADE_UP_SECONDS if rising else STEM_FADE_DOWN_SECONDS


# ---------------------------------------------------------------------------
# State machine (carried over from v1)
# ---------------------------------------------------------------------------

func get_state() -> StringName:
	return _state


func get_heat() -> float:
	return _heat


func get_layer() -> int:
	return _layer


## Start tracking run events (idempotent; call from Main on world build).
func begin_tracking() -> void:
	if _wired or EventBus == null:
		return
	_wired = true
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.enemy_killed.connect(_on_kill)
	EventBus.enemy_damaged.connect(_on_damaged)
	EventBus.boss_spawned.connect(_on_boss)
	EventBus.boss_slain.connect(_on_boss_slain)
	EventBus.game_state_changed.connect(_on_state_changed)
	# Fresh launch boots straight into the menu with no transition firing, so
	# seed the menu bed here; every later state arrives via game_state_changed.
	if GameRoot != null and GameRoot.get_current_state() == &"main_menu" and _players.size() == 2:
		request_state(STATE_MENU)


func request_state(state: StringName) -> void:
	if state == _state:
		return
	if _players.is_empty():
		return
	var old := _state
	_state = state
	_fading = CROSSFADE_SECONDS
	_active_index = (_active_index + 1) % _players.size()
	if _players.size() == 2:
		_outgoing_from_db = _players[(_active_index + 1) % 2].volume_db
	# Stems belong to the incoming bed: drop the old ones (fade, never hard
	# cut), then re-derive which stems the new state can use.
	_active_bed_cue = _cue_for_state()
	_active_stem_cues = _stem_cues_for(_active_bed_cue)
	_play_cue_on_active()
	_relayer_for_state_change()
	music_state_changed.emit(old, state)


## State changes re-mean the layer immediately (boss always peaks, calm has
## no stems): bypass the dwell, fade each stem toward its new state's target.
func _relayer_for_state_change() -> void:
	var target := target_layer_for(_state, _heat)
	_layer = clampi(target, 0, 3)
	_dwell_left = LAYER_DWELL_SECONDS
	_apply_stem_levels()


func _cue_for_state() -> StringName:
	match _state:
		STATE_MENU:
			return &"music_menu"
		STATE_CALM:
			return _arena_cue(&"music_calm")
		STATE_BATTLE:
			return _arena_cue(&"music_battle")
		STATE_BOSS:
			return &"music_boss"
		STATE_VICTORY:
			return &"music_victory"
	return &""


## Arena configs may override the calm/battle bed via background_music_cue;
## unknown or missing ids fall back to the default cue for the state.
func _arena_cue(fallback: StringName) -> StringName:
	if GameRoot == null or ContentRegistry == null or AudioManager == null:
		return fallback
	var run := GameRoot.get_run()
	if run != null and run.arena_id != &"":
		var arena: ArenaConfig = ContentRegistry.get_arena(run.arena_id)
		if arena != null and arena.background_music_cue != &"" and AudioManager.has_cue(arena.background_music_cue):
			return arena.background_music_cue
	return fallback


## Optional intensity stems for a resolved bed cue. Missing/unknown stems
## degrade to silence (the single-bed v1 behavior).
func _stem_cues_for(bed_cue: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in STEM_COUNT:
		var idn := StringName("%s_l%d" % [String(bed_cue), 2 + i])
		out.append(idn if (AudioManager != null and AudioManager.has_cue(idn)) else &"")
	return out


func _play_cue_on_active() -> void:
	var cue := _active_bed_cue
	var player := _players[_active_index]
	if cue == &"" or AudioManager == null or not AudioManager.has_cue(cue):
		player.stop()
		player.stream = null
		if cue != &"":
			EventBus.report_info("Music cue missing, staying silent: %s" % String(cue))
		return
	player.stream = AudioManager.get_cue_stream(cue)
	player.play()


func _process(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		delta = 0.016
	_heat = maxf(_heat - HEAT_DECAY_PER_SECOND * delta, 0.0)
	_tick_intensity(delta)
	_tick_bed_crossfade(delta)
	_tick_stems(delta)


## Intensity -> layer with the asymmetric dwell rule: up is immediate, down
## waits LAYER_DWELL_SECONDS (heat flicker during rapid hits cannot machine-
## gun the stems, but a real lull releases the layer promptly).
func _tick_intensity(delta: float) -> void:
	var target := target_layer_for(_state, _heat)
	if target == _layer:
		_dwell_left = 0.0
		return
	if target > _layer:
		_set_layer(target)
		return
	_dwell_left = maxf(_dwell_left, LAYER_DWELL_SECONDS)
	_dwell_left -= delta
	if _dwell_left <= 0.0:
		_dwell_left = 0.0
		_set_layer(target)


func _set_layer(new_layer: int) -> void:
	_layer = clampi(new_layer, 0, 3)
	_dwell_left = LAYER_DWELL_SECONDS
	_apply_stem_levels()


func _apply_stem_levels() -> void:
	var targets := stem_targets(_layer)
	for i in _stems.size():
		var st: Dictionary = _stems[i]
		var want_cue: StringName = _active_stem_cues[i] if i < _active_stem_cues.size() else &""
		var want_db := float(targets[i])
		# Asymmetric: a rising level (or a stem coming out of silence) fades
		# in fast; a falling level releases slowly.
		var rising := want_db > float(st["to"]) + 0.5
		_set_stem_target(st, want_db, stem_fade_seconds(rising), want_cue)


# ---------------------------------------------------------------------------
# Stem engine
# ---------------------------------------------------------------------------

## Drive one stem toward (want_cue, want_db). Never hard-cuts: a stream change
## fades the old audio out, swaps at the fade end, then fades the new stream
## in (the swap rides the stem's "pending" slot).
func _set_stem_target(st: Dictionary, want_db: float, dur: float, want_cue: StringName) -> void:
	var player: AudioStreamPlayer = st["player"]
	if String(st["cue"]) != String(want_cue):
		var stream := _resolve_stem_stream(want_cue)
		if player.playing:
			# Audio in the air: fade out; the swap happens at fade end.
			st["pending"] = {"cue": want_cue, "stream": stream, "db": want_db}
			_start_fade(st, SILENCE_DB, dur)
			return
		# Silent: swap immediately (a dead cue/stream is just stale data).
		st["pending"] = {}
		st["cue"] = want_cue
		st["stream"] = stream
	else:
		# Same cue: a queued swap (if any) is now stale — the state flickered
		# back before it fired. Drop it.
		st["pending"] = {}
	if want_db <= SILENCE_DB + 0.5:
		if player.playing:
			_start_fade(st, SILENCE_DB, dur)
		else:
			st["t"] = 0.0
			st["dur"] = 0.0
			st["to"] = SILENCE_DB
		return
	# Above silence: start (phase-synced) if needed, then fade to the level.
	if not player.playing:
		if st["stream"] == null:
			# The cue may have resolved since the silent swap (late asset
			# registration): try once more before staying silent.
			st["stream"] = _resolve_stem_stream(st["cue"])
			if st["stream"] == null:
				return
		player.stream = st["stream"]
		_phase_sync(player)
		player.play()
	_start_fade(st, want_db, dur)


func _resolve_stem_stream(cue_id: StringName) -> AudioStream:
	if cue_id == &"":
		return null
	if AudioManager == null or not AudioManager.has_cue(cue_id):
		return null
	var s := AudioManager.get_cue_stream(cue_id)
	if s == null:
		EventBus.report_info("Music stem missing, layer stays silent: %s" % String(cue_id))
		return null
	return s


func _start_fade(st: Dictionary, to_db: float, dur: float) -> void:
	st["from"] = float((st["player"] as AudioStreamPlayer).volume_db)
	st["to"] = to_db
	st["t"] = 0.0
	st["dur"] = dur if is_finite(dur) and dur > 0.0 else 0.001


## Best-effort phase sync: join at the active bed's position so loops stay
## in step (the stem and the bed share the same authored loop family).
func _phase_sync(stem: AudioStreamPlayer) -> void:
	var bed := _players[_active_index] if _active_index < _players.size() else null
	if bed == null or not bed.playing:
		return
	var pos: float = bed.get_playback_position()
	if is_finite(pos) and pos > 0.0:
		stem.seek(pos)


func _tick_bed_crossfade(delta: float) -> void:
	if _fading <= 0.0 or _players.size() != 2:
		return
	_fading -= delta
	var t := clampf(1.0 - _fading / CROSSFADE_SECONDS, 0.0, 1.0)
	var incoming: AudioStreamPlayer = _players[_active_index]
	var outgoing: AudioStreamPlayer = _players[(_active_index + 1) % 2]
	incoming.volume_db = lerpf(SILENCE_DB, BED_LEVEL_DB, t)
	outgoing.volume_db = lerpf(_outgoing_from_db, SILENCE_DB, t)
	if _fading <= 0.0:
		outgoing.stop()
		incoming.volume_db = BED_LEVEL_DB


func _tick_stems(delta: float) -> void:
	for s in _stems:
		var st: Dictionary = s
		var dur: float = float(st["dur"])
		if dur <= 0.0:
			continue
		var player: AudioStreamPlayer = st["player"]
		var k := clampf(float(st["t"]) + delta / dur, 0.0, 1.0)
		st["t"] = k
		# Smoothstep: gentle at both ends, musical for slow fades.
		var shaped := k * k * (3.0 - 2.0 * k)
		player.volume_db = float(st["from"]) + (float(st["to"]) - float(st["from"])) * shaped
		if k >= 1.0:
			st["dur"] = 0.0
			_stem_fade_done(st)


## Fade completed: either the level settled, or a stream swap is pending
## (fade old out -> swap -> fade new in).
func _stem_fade_done(st: Dictionary) -> void:
	var player: AudioStreamPlayer = st["player"]
	var pending: Dictionary = st["pending"]
	if not pending.is_empty():
		st["pending"] = {}
		player.stop()
		st["cue"] = pending["cue"]
		st["stream"] = pending["stream"]
		var db: float = float(pending["db"])
		if st["stream"] != null and db > SILENCE_DB + 0.5:
			player.stream = st["stream"]
			_phase_sync(player)
			player.play()
			_start_fade(st, db, STEM_FADE_UP_SECONDS)
		else:
			st["to"] = SILENCE_DB
		return
	if float(st["to"]) <= SILENCE_DB + 0.5:
		# Settled at silence: stop the voice (a loop would never end itself).
		player.stop()
		st["to"] = SILENCE_DB
	elif not player.playing:
		# Level above silence but the voice died (non-loop stream end):
		# restart rather than leave the layer hollow.
		if st["stream"] != null:
			player.stream = st["stream"]
			_phase_sync(player)
			player.play()


func add_heat(amount: float) -> void:
	_heat = clampf(_heat + amount, 0.0, 1.5)
	if _state == STATE_CALM and _heat > 0.5:
		request_state(STATE_BATTLE)
	elif _state == STATE_BATTLE and _heat <= 0.05:
		request_state(STATE_CALM)


func _on_run_started(_run_id: int, _seed: int) -> void:
	# A restarted run must open calm even if the previous run ended mid-fight.
	_heat = 0.0
	request_state(STATE_CALM)


func _on_run_ended(_score: int, _wave: int, _best: int) -> void:
	# run_ended always lands after the game_over state hook (it is emitted from
	# _finalize_run), so restating VICTORY here keeps the post-run bed instead
	# of stomping it with silence. Same-state requests are a no-op.
	request_state(STATE_VICTORY)


func _on_kill(_enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	add_heat(HEAT_PER_KILL)


func _on_damaged(_enemy: Node, _result: DamageResult) -> void:
	add_heat(HEAT_PER_DAMAGE)


func _on_boss(_boss: Node, _boss_id: StringName) -> void:
	request_state(STATE_BOSS)


func _on_boss_slain(_boss_id: StringName) -> void:
	# The fight goes on (adds remain); drop back to battle instead of silence.
	if _state == STATE_BOSS:
		request_state(STATE_BATTLE)


func _on_state_changed(_previous: StringName, current: StringName) -> void:
	if current == &"main_menu":
		request_state(STATE_MENU)
	elif current == &"game_over":
		request_state(STATE_VICTORY)


func get_debug_snapshot() -> Dictionary:
	var stems: Array[String] = []
	for s in _stems:
		stems.append(String((s as Dictionary)["cue"]))
	return {
		"state": String(_state),
		"heat": _heat,
		"layer": _layer,
		"stems": stems,
	}
