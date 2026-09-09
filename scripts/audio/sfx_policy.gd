class_name SfxPolicy
extends RefCounted

## Pure per-cue SFX governance (headless, no tree, no autoloads).
##
## Rebuild of the voice-management contract that AudioConfig declared but the
## v1 playback engine never honored. Mirrors standard middleware semantics:
##   * cooldown  = "minimum time between instances" (the anti-spam safety net
##     FMOD/Wwise ship; the most efficient limiter is code-side rules, not
##     DSP-side tricks).
##   * max_voices = per-cue instance cap; when full, the NEWEST play steals
##     the cue's OLDEST active voice (FMOD "stealing: oldest" — the right
##     policy for very frequent events: the longest-running instance is the
##     one whose tail matters least to the player).
##
## The playback engine asks `try_play()` before claiming a player and reports
## `voice_started()` / `voice_ended()` so per-cue occupancy stays accurate.
## Deterministic for identical input sequences (pinned by unit tests).

const REJECT := &"reject"   # inside the cue's cooldown window
const FRESH := &"fresh"     # a fresh voice may be claimed
const STEAL := &"steal"     # cap reached: steal the returned voice token

const DEFAULT_CAP := 4

var _cooldowns: Dictionary = {}  # cue -> seconds
var _caps: Dictionary = {}       # cue -> int
var _last_play: Dictionary = {}  # cue -> clock seconds
var _active: Dictionary = {}     # cue -> Array[int] voice tokens, oldest first


## Arm a cue with its contract. Idempotent; re-calling retunes the same cue.
func configure(cue: StringName, cooldown_s: float, max_voices: int) -> void:
	_cooldowns[cue] = cooldown_s if (is_finite(cooldown_s) and cooldown_s >= 0.0) else 0.0
	_caps[cue] = maxi(max_voices, 1)


## Drop all state for one cue (run teardown / cue unregistration).
func reset(cue: StringName) -> void:
	_cooldowns.erase(cue)
	_caps.erase(cue)
	_last_play.erase(cue)
	_active.erase(cue)


func get_cooldown(cue: StringName) -> float:
	return float(_cooldowns.get(cue, 0.0))


func get_cap(cue: StringName) -> int:
	return int(_caps.get(cue, DEFAULT_CAP))


## Decision for one requested play at `now_s` (monotonic seconds).
## Returns {"action": StringName, "steal_token": int}.
##   REJECT: inside the cooldown window — drop silently (this is the guard's
##   job; warning-spamming on every suppressed play would defeat the purpose).
##   STEAL:  cap reached — `steal_token` is the OLDEST active voice of the cue.
##   FRESH:  nothing to steal; claim an idle voice.
func try_play(cue: StringName, now_s: float) -> Dictionary:
	if not is_finite(now_s) or now_s < 0.0:
		now_s = 0.0
	var cooldown := get_cooldown(cue)
	if cooldown > 0.0:
		var last := float(_last_play.get(cue, -INF))
		if last > -INF and (now_s - last) < cooldown:
			return {"action": REJECT, "steal_token": -1}
	var actives: Array = _active.get(cue, [])
	if actives.size() >= get_cap(cue):
		return {"action": STEAL, "steal_token": int(actives[0])}
	return {"action": FRESH, "steal_token": -1}


## Record that a play of `cue` actually started (arms the cooldown window).
func note_played(cue: StringName, now_s: float) -> void:
	if is_finite(now_s) and now_s >= 0.0:
		_last_play[cue] = now_s


func voice_started(cue: StringName, token: int) -> void:
	var actives: Array = _active.get(cue, [])
	if not actives.has(token):
		actives.append(token)
		_active[cue] = actives


func voice_ended(cue: StringName, token: int) -> void:
	if not _active.has(cue):
		return
	var actives: Array = _active[cue]
	var at := actives.find(token)
	if at >= 0:
		actives.remove_at(at)


func active_count(cue: StringName) -> int:
	if not _active.has(cue):
		return 0
	return (_active[cue] as Array).size()


func get_debug_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for cue in _cooldowns.keys():
		out[String(cue)] = {
			"cooldown": get_cooldown(cue),
			"cap": get_cap(cue),
			"active": active_count(cue),
		}
	return out
