extends RefCounted

## Headless unit tests for ProceduralSfx: every referenced cue synthesizes a
## valid stream, generation is byte-deterministic, SFX are one-shots and music
## cues are seamless integer-cycle loops. Pure/static only (ensure_registered
## touches autoloads, so it stays out of the headless suites).


static func suite() -> Array:
	var results: Array = []
	_sfx_shapes(results)
	_music_shapes(results)
	_determinism(results)
	_seamless_loops(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _sfx_shapes(results: Array) -> void:
	for cue_id in ProceduralSfx.SFX_CUES:
		var stream := ProceduralSfx.make_sfx(cue_id)
		_check(results, "sfx %s synthesizes" % cue_id, stream is AudioStreamWAV and stream.data.size() > 100)
		_check(results, "sfx %s is 8-bit mono" % cue_id,
			stream.format == AudioStreamWAV.FORMAT_8_BITS and not stream.stereo and stream.mix_rate == ProceduralSfx.MIX_RATE)
		_check(results, "sfx %s is a one-shot" % cue_id, stream.loop_mode == AudioStreamWAV.LOOP_DISABLED)
		_check(results, "sfx %s has audible content" % cue_id, _peak(stream) > 0.05,
			"peak %f" % _peak(stream))


static func _music_shapes(results: Array) -> void:
	for cue_id in ProceduralSfx.MUSIC_CUES:
		var stream := ProceduralSfx.make_music(cue_id)
		var want := int(ProceduralSfx.MUSIC_LOOP_SECONDS * ProceduralSfx.MIX_RATE)
		_check(results, "music %s synthesizes at loop length" % cue_id, stream.data.size() == want,
			"got %d want %d" % [stream.data.size(), want])
		_check(results, "music %s loops forward" % cue_id,
			stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == want)
		_check(results, "music %s has audible content" % cue_id, _peak(stream) > 0.05)


static func _determinism(results: Array) -> void:
	for cue_id in [&"player_attack", &"enemy_spawn", &"pickup", &"music_battle"]:
		var a := ProceduralSfx.make_sfx(cue_id) if cue_id != &"music_battle" else ProceduralSfx.make_music(cue_id)
		var b := ProceduralSfx.make_sfx(cue_id) if cue_id != &"music_battle" else ProceduralSfx.make_music(cue_id)
		_check(results, "%s is byte-deterministic" % cue_id, a.data == b.data)


static func _seamless_loops(results: Array) -> void:
	# Integer-cycle partials: loop wrap must be near-continuous (no click).
	for cue_id in ProceduralSfx.MUSIC_CUES:
		var stream := ProceduralSfx.make_music(cue_id)
		var first := float(stream.data[0]) - 128.0
		var last := float(stream.data[stream.data.size() - 1]) - 128.0
		_check(results, "music %s wraps seamlessly" % cue_id, absf(first - last) < 24.0,
			"edge delta %f" % absf(first - last))


## Peak |amplitude| in [0, 1] sampled across the stream.
static func _peak(stream: AudioStreamWAV) -> float:
	var peak := 0.0
	var n := stream.data.size()
	var step := maxi(int(n / 2000.0), 1)  # sample stride, must stay an int count
	var i := 0
	while i < n:
		peak = maxf(peak, absf(float(stream.data[i]) - 128.0) / 128.0)
		i += step
	return peak
