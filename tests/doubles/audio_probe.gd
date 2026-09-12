extends RefCounted
## E2E audio inspection must include all three banks. UI clicks and world Foley
## no longer live in the legacy 2D SFX pool. Reset only between independent test
## interactions; cooldown/cap behavior has its own policy and native unit tests.

static func players() -> Array[Node]:
	var result: Array[Node] = []
	result.append_array(AudioManager._sfx_pool)
	result.append_array(AudioManager._ui_bank.players)
	if AudioManager._spatial != null:
		result.append_array(AudioManager._spatial._bank.players)
	return result


static func cue_for(stream: AudioStream) -> StringName:
	if stream != null:
		for cue in AudioManager._cues:
			if AudioManager._cues[cue] == stream:
				return cue
	return &""


static func snapshot() -> Dictionary:
	var result := {"total": 0, "unknowns": 0, "by_cue": {}}
	for player in players():
		if not bool(player.get("playing")):
			continue
		result.total += 1
		var cue := String(cue_for(player.get("stream") as AudioStream))
		if cue.is_empty():
			result.unknowns += 1
		else:
			result.by_cue[cue] = int(result.by_cue.get(cue, 0)) + 1
	return result


static func stop() -> void:
	for player in players():
		player.call("stop")
	AudioManager._pending.clear()
	for index in AudioManager._voice_fade.size():
		AudioManager._voice_fade[index] = {}
		AudioManager._voice_cue[index] = &""
	var banks: Array[VoiceBank] = [AudioManager._ui_bank]
	if AudioManager._spatial != null:
		AudioManager._spatial._queued_place.clear()
		AudioManager._spatial._emitters.fill(null)
		banks.append(AudioManager._spatial._bank)
	for bank in banks:
		bank.pending.clear()
		for index in bank.size():
			bank.fades[index] = {}
			bank.cues[index] = &""
	for cue in AudioManager._cues:
		AudioManager._policy.reset(cue)
