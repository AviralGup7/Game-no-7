class_name VoiceBank
extends RefCounted

## Click-safe voice bank for a *single* bus family (UI 2D, or spatial 3D).
##
## The combat `_sfx_pool` on AudioManager stays inline so soak/stress scripts
## and the v2 `play_sfx` shape guards keep reading the original path. This
## bank is the isolated sibling: UI clicks never steal an SFX voice, and
## spatial Foley never occupies the 2D ceiling.
##
## Fade contract matches AudioManager: 12 ms linear in, 30 ms 1-t^2 out,
## pending-claim on steal, never a hard stop.

const FADE_IN_SECONDS := 0.012
const FADE_OUT_SECONDS := 0.030

var token_base: int = 0
var bus_name: StringName = &"SFX"
var players: Array = []
var cues: Array[StringName] = []
var fades: Array[Dictionary] = []
var pending: Array[Dictionary] = []
var policy: SfxPolicy = null
var clock: Callable = Callable()
## Index of the most recently started voice, or -1.
var last_claimed: int = -1


func setup(owned_players: Array, p_policy: SfxPolicy, p_token_base: int, p_bus: StringName) -> void:
	players = owned_players
	policy = p_policy
	token_base = p_token_base
	bus_name = p_bus
	cues.clear()
	fades.clear()
	pending.clear()
	last_claimed = -1
	for _i in players.size():
		cues.append(&"")
		fades.append({})


func size() -> int:
	return players.size()


func token_of(idx: int) -> int:
	return token_base + idx


func index_of_token(token: int) -> int:
	var idx := token - token_base
	if idx < 0 or idx >= players.size():
		return -1
	return idx


func owns_token(token: int) -> bool:
	return index_of_token(token) >= 0


func active_count() -> int:
	var n := 0
	for p in players:
		if p != null and bool(p.playing):
			n += 1
	return n


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return float(Time.get_ticks_msec()) / 1000.0


func _player_at(idx: int) -> Node:
	if idx < 0 or idx >= players.size():
		return null
	return players[idx]


func is_idle(idx: int) -> bool:
	var p := _player_at(idx)
	if p == null:
		return false
	return (not bool(p.playing)) and fades[idx].is_empty() and not _is_pending_target(idx)


func _is_pending_target(idx: int) -> bool:
	for entry in pending:
		if int((entry as Dictionary)["player_idx"]) == idx:
			return true
	return false


## Claim a voice for `cue` after SfxPolicy has already decided. `steal_token`
## is the policy token (token_base + idx) or -1. Returns true when a voice
## started or was queued on a fade.
func claim(
		cue_id: StringName,
		vol: float,
		pitch: float,
		stream: AudioStream,
		action: StringName,
		steal_token: int
) -> bool:
	if stream == null:
		return false
	if action == SfxPolicy.STEAL and owns_token(steal_token):
		var victim := index_of_token(steal_token)
		var p := _player_at(victim)
		if p != null and bool(p.playing):
			return _defer_on_fade(victim, cue_id, vol, pitch, stream)
	for i in players.size():
		if is_idle(i):
			_start_voice(i, cue_id, vol, pitch, stream)
			return true
	var oldest := _oldest_idx()
	if oldest >= 0:
		return _defer_on_fade(oldest, cue_id, vol, pitch, stream)
	return false


func _oldest_idx() -> int:
	var oldest := -1
	var oldest_pos := -1.0
	for i in players.size():
		var p := _player_at(i)
		if p == null:
			continue
		if fades[i].is_empty() and not _is_pending_target(i) and bool(p.playing):
			var pos: float = p.get_playback_position()
			if oldest < 0 or pos > oldest_pos:
				oldest = i
				oldest_pos = pos
	return oldest


func _defer_on_fade(idx: int, cue_id: StringName, vol: float, pitch: float, stream: AudioStream) -> bool:
	if not _begin_fade_out(idx):
		_start_voice(idx, cue_id, vol, pitch, stream)
		return true
	pending.append({
		"player_idx": idx,
		"cue": cue_id,
		"volume_db": vol,
		"pitch_scale": pitch,
		"stream": stream,
	})
	return true


func _start_voice(idx: int, cue_id: StringName, vol: float, pitch: float, stream: AudioStream) -> void:
	var player := _player_at(idx)
	if player == null:
		return
	player.bus = String(bus_name)
	player.stream = stream
	player.pitch_scale = clampf(pitch, 0.1, 4.0) if (is_finite(pitch) and pitch > 0.0) else 1.0
	player.volume_db = -80.0
	player.play()
	cues[idx] = cue_id
	last_claimed = idx
	if policy != null:
		policy.voice_started(cue_id, token_of(idx))
		policy.note_played(cue_id, _now())
	_begin_fade_in(idx, clampf(vol, -80.0, 6.0) if is_finite(vol) else 0.0)


func _begin_fade_in(idx: int, to_db: float) -> void:
	fades[idx] = {
		"kind": "in",
		"t": 0.0,
		"dur": FADE_IN_SECONDS,
		"from": -80.0,
		"to": to_db,
	}
	var p := _player_at(idx)
	if p != null:
		p.volume_db = -80.0


func _begin_fade_out(idx: int) -> bool:
	var player := _player_at(idx)
	if player == null or not bool(player.playing):
		return false
	if not fades[idx].is_empty():
		return true
	fades[idx] = {
		"kind": "out",
		"t": 0.0,
		"dur": FADE_OUT_SECONDS,
		"from": player.volume_db,
		"to": -80.0,
	}
	return true


func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	for i in players.size():
		var fade: Dictionary = fades[i]
		if fade.is_empty():
			continue
		var k := clampf(float(fade["t"]) + delta / maxf(float(fade["dur"]), 0.001), 0.0, 1.0)
		var from := float(fade["from"])
		var to := float(fade["to"])
		var player := _player_at(i)
		if player == null:
			fades[i] = {}
			continue
		if String(fade["kind"]) == "out":
			player.volume_db = to + (from - to) * (1.0 - k * k)
		else:
			player.volume_db = from + (to - from) * k
		fade["t"] = k
		fades[i] = fade
		if k >= 1.0:
			_finish_fade(i)
	_reap_finished()


func _finish_fade(idx: int) -> void:
	var fade: Dictionary = fades[idx]
	var kind := String(fade.get("kind", ""))
	fades[idx] = {}
	var player := _player_at(idx)
	if kind == "out" and player != null:
		player.stop()
		var cue: StringName = cues[idx]
		if cue != &"" and policy != null:
			policy.voice_ended(cue, token_of(idx))
		cues[idx] = &""
		_fire_pending(idx)


func _fire_pending(idx: int) -> void:
	var keep: Array[Dictionary] = []
	for entry in pending:
		if int((entry as Dictionary)["player_idx"]) != idx:
			keep.append(entry)
			continue
		if cues[idx] != &"":
			continue
		var p := _player_at(idx)
		if p != null and bool(p.playing):
			continue
		var e: Dictionary = entry
		_start_voice(idx, StringName(e["cue"]), float(e["volume_db"]), float(e["pitch_scale"]), e["stream"])
	pending = keep


func _reap_finished() -> void:
	for i in players.size():
		var p := _player_at(i)
		if p == null:
			continue
		if fades[i].is_empty() and cues[i] != &"" and not bool(p.playing):
			if policy != null:
				policy.voice_ended(cues[i], token_of(i))
			cues[i] = &""


func stop_all() -> void:
	for i in players.size():
		var p := _player_at(i)
		if p != null and bool(p.playing):
			_begin_fade_out(i)
	pending.clear()


func get_debug_snapshot() -> Dictionary:
	return {
		"bus": String(bus_name),
		"size": players.size(),
		"active": active_count(),
		"pending": pending.size(),
		"token_base": token_base,
	}
