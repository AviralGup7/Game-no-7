class_name ProceduralSfx
extends RefCounted

## Deterministic procedural audio: every SFX + music cue the game references,
## synthesized as 8-bit mono loops/one-shots so the game is never silent, even
## with zero shipped sound files. Real audio drops in data/audio/ always win —
## ensure_registered() only fills cues still missing from AudioManager.
## Generation is pure/static (seeded noise) so unit tests can assert byte-level
## determinism; only ensure_registered() touches autoloads.
## Music loops are seamless by construction: every partial completes an integer
## number of cycles per loop (no clicks at the wrap point).

const MIX_RATE := 22050

## Audio mapping (M4 — updated M7):
##  LIVE — every catalog cue has a real file + procedural fallback and a gameplay caller (player_step distance-based, equip via player_switch alias, item_drop via pickup spawn, plus weapons/skills/boss/waves/pickups/UI);
##  FALLBACK — procedural synthesis guarantees silence-free fallback; real file in assets/audio/* wins when AudioManager.has_cue;
##  RESERVED — none currently (footstep/equip/item_drop migrated to LIVE in M7);
##  UNUSED — none. All cues documented in assets/catalog.json audio_cues + here. Catalog 34 cues + SFX_CUES 29 + MUSIC 5 all LIVE via has_cue seam (the five music beds each ship a recorded loop; procedural pads remain the silent-free fallback).
const SFX_CUES: Array[StringName] = [
	&"player_attack", &"player_hurt", &"player_death", &"player_dodge",
	&"player_step", &"player_switch", &"player_shot", &"player_reload", &"player_low_health",
	&"enemy_hit", &"enemy_death", &"enemy_attack", &"enemy_spawn", &"enemy_windup", &"enemy_dash", &"enemy_explosion",
	&"pickup", &"upgrade_select", &"ui_confirm", &"ui_back",
	&"skill_cast", &"skill_ready", &"level_up",
	&"wave_started", &"wave_completed", &"boss_spawned", &"boss_phase_changed", &"boss_slain", &"game_over",
]
const MUSIC_CUES: Array[StringName] = [
	&"music_menu", &"music_calm", &"music_battle", &"music_boss", &"music_victory",
]
## Intensity stems (MusicManager convention: `<bed>_l2` / `<bed>_l3`). Missing
## stems degrade to the single-bed v1 path; registering these makes the layer
## mixer actually have something to fade.
const STEM_CUES: Array[StringName] = [
	&"music_battle_l2", &"music_battle_l3",
	&"music_boss_l2", &"music_boss_l3",
	&"music_calm_l2",
]
const MUSIC_LOOP_SECONDS := 6.0


## Register synthesized streams for every cue AudioManager still lacks.
static func ensure_registered() -> void:
	if AudioManager == null or ContentRegistry == null:
		return
	for cue_id in SFX_CUES:
		if not AudioManager.has_cue(cue_id):
			ContentRegistry.register_audio_cue(cue_id, make_sfx(cue_id))
	for cue_id in MUSIC_CUES:
		if not AudioManager.has_cue(cue_id):
			ContentRegistry.register_audio_cue(cue_id, make_music(cue_id))
	for cue_id in STEM_CUES:
		if not AudioManager.has_cue(cue_id):
			ContentRegistry.register_audio_cue(cue_id, make_music(cue_id))


static func make_sfx(cue_id: StringName) -> AudioStreamWAV:
	match cue_id:
		&"player_attack":
			return _to_stream(_sweep(0.16, 900.0, 200.0, 0.5, 0.35), false)
		&"player_hurt":
			return _to_stream(_thud(0.25, 160.0, 60.0, 0.6), false)
		&"player_death":
			return _to_stream(_sweep(0.6, 400.0, 50.0, 0.6, 0.2), false)
		&"player_dodge":
			return _to_stream(_whoosh(0.12, 0.35), false)
		&"player_step":
			return _to_stream(_click(0.07, 180.0, 0.25), false)
		&"player_switch":
			return _to_stream(_sweep(0.12, 400.0, 800.0, 0.45, 0.1), false)
		&"player_shot":
			return _to_stream(_sweep(0.14, 700.0, 300.0, 0.5, 0.2), false)
		&"player_reload":
			return _to_stream(_click(0.15, 220.0, 0.4), false)
		&"player_low_health":
			return _to_stream(_sweep(0.35, 200.0, 80.0, 0.55, 0.15), false)
		&"enemy_hit":
			return _to_stream(_click(0.1, 300.0, 0.55), false)
		&"enemy_death":
			return _to_stream(_sweep(0.3, 500.0, 100.0, 0.55, 0.4), false)
		&"enemy_attack":
			return _to_stream(_growl(0.2, 0.5), false)
		&"enemy_spawn":
			return _to_stream(_sweep(0.25, 100.0, 600.0, 0.4, 0.0), false)
		&"enemy_windup":
			return _to_stream(_sweep(0.35, 120.0, 480.0, 0.42, 0.25), false)
		&"enemy_dash":
			return _to_stream(_whoosh(0.18, 0.45), false)
		&"enemy_explosion":
			return _to_stream(_thud(0.4, 90.0, 30.0, 0.7), false)
		&"pickup":
			return _to_stream(_blip(0.18, [880.0, 1320.0], 0.5), false)
		&"upgrade_select":
			return _to_stream(_blip(0.4, [523.25, 659.25, 783.99], 0.5), false)
		&"ui_confirm":
			return _to_stream(_blip(0.12, [660.0, 880.0], 0.45), false)
		&"ui_back":
			return _to_stream(_blip(0.12, [440.0, 330.0], 0.4), false)
		&"skill_cast":
			return _to_stream(_sweep(0.22, 500.0, 900.0, 0.55, 0.15), false)
		&"skill_ready":
			return _to_stream(_blip(0.2, [523.25, 1046.5], 0.45), false)
		&"level_up":
			return _to_stream(_blip(0.5, [440.0, 554.0, 659.0, 880.0], 0.6), false)
		&"wave_started":
			return _to_stream(_sweep(0.4, 200.0, 600.0, 0.6, 0.05), false)
		&"wave_completed":
			return _to_stream(_blip(0.6, [392.0, 523.25, 659.25, 783.99], 0.6), false)
		&"boss_spawned":
			return _to_stream(_sweep(0.7, 80.0, 180.0, 0.65, 0.2), false)
		&"boss_phase_changed":
			return _to_stream(_sweep(0.5, 150.0, 320.0, 0.6, 0.25), false)
		&"boss_slain":
			return _to_stream(_blip(0.8, [260.0, 329.0, 392.0, 523.25], 0.65), false)
		&"game_over":
			return _to_stream(_sweep(0.8, 400.0, 60.0, 0.55, 0.1), false)
	return _to_stream(_click(0.1, 440.0, 0.4), false)


static func make_music(cue_id: StringName) -> AudioStreamWAV:
	match cue_id:
		&"music_menu":
			return _to_stream(_pad([108.0, 162.0, 216.0], 1, 0.30), true)
		&"music_calm":
			return _to_stream(_pad([132.0, 198.0, 264.0], 3, 0.32), true)
		&"music_battle":
			return _to_stream(_pad([96.0, 144.0, 192.0, 999.0], 12, 0.42), true)
		&"music_boss":
			return _to_stream(_pad([72.0, 108.0, 144.0], 6, 0.46), true)
		&"music_victory":
			return _to_stream(_arpeggio([216.0, 270.0, 324.0, 432.0], 0.36), true)
	return _to_stream(_pad([108.0, 162.0, 216.0], 1, 0.3), true)


# ---------------------------- primitives ----------------------------

static func _to_stream(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size())
	for i in range(samples.size()):
		data[i] = clampi(int(128.0 + samples[i] * 120.0), 0, 255)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


## Linear attack, power-curve release envelope in [0, 1].
static func _env(t: float, dur: float, attack: float) -> float:
	if t <= 0.0:
		return 0.0
	if t < attack:
		return t / maxf(attack, 0.0001)
	var k := 1.0 - (t - attack) / maxf(dur - attack, 0.0001)
	return k * k


## Frequency sweep with optional noise grit. start_f > end_f falls, else rises.
static func _sweep(dur: float, start_f: float, end_f: float, vol: float, grit: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var phase := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var k := t / dur
		phase += TAU * lerpf(start_f, end_f, k) / MIX_RATE
		var tone := sin(phase) * 0.7 + sin(phase * 2.0) * 0.2
		var noise := (rng.randf() * 2.0 - 1.0) * grit
		out[i] = (tone + noise) * _env(t, dur, 0.005) * vol
	return out


static func _thud(dur: float, start_f: float, end_f: float, vol: float) -> PackedFloat32Array:
	var out := _sweep(dur, start_f, end_f, vol, 0.25)
	# Extra click transient at the head.
	for i in range(mini(int(0.008 * MIX_RATE), out.size())):
		out[i] += 0.3 * (1.0 - float(i) / (0.008 * MIX_RATE))
	return out


static func _whoosh(dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var prev := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var noise := rng.randf() * 2.0 - 1.0
		# Cheap highpass: air without rumble.
		var hp := noise - prev
		prev = noise
		out[i] = hp * _env(t, dur, dur * 0.4) * vol
	return out


static func _click(dur: float, freq: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(n):
		var t := float(i) / MIX_RATE
		var sq := 1.0 if sin(TAU * freq * t) > 0.0 else -1.0
		var noise := (rng.randf() * 2.0 - 1.0) * 0.3
		out[i] = (sq * 0.5 + noise) * _env(t, dur, 0.002) * vol
	return out


static func _growl(dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(n):
		var t := float(i) / MIX_RATE
		var saw := fmod(90.0 * t, 1.0) * 2.0 - 1.0
		var sub := sin(TAU * 55.0 * t)
		var noise := (rng.randf() * 2.0 - 1.0) * 0.35
		out[i] = (saw * 0.4 + sub * 0.5 + noise) * _env(t, dur, 0.01) * vol
	return out


static func _blip(dur: float, freqs: Array[float], vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var step := dur / float(freqs.size())
	for i in range(n):
		var t := float(i) / MIX_RATE
		var idx := mini(int(t / step), freqs.size() - 1)
		var local := t - float(idx) * step
		out[i] = sin(TAU * float(freqs[idx]) * t) * _env(local, step, 0.005) * vol
	return out


## Seamless looping pad: partials at integer cycles/loop + integer-cycle tremolo.
static func _pad(freqs: Array[float], pulses: int, vol: float) -> PackedFloat32Array:
	var dur := MUSIC_LOOP_SECONDS
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var s := 0.0
		for f in freqs:
			var c: float = float(f) * dur
			var whole: float = round(c)
			# Snap to an integer cycle count so the loop wraps seamlessly.
			s += sin(TAU * whole * t / dur) / float(freqs.size())
			s += sin(TAU * (whole + 1.0) * t / dur) * 0.15 / float(freqs.size())
		var trem := 0.7 + 0.3 * sin(TAU * float(pulses) * t / dur)
		out[i] = s * trem * vol
	return out


## Seamless looping arpeggio: eighth-note steps dividing the loop evenly.
static func _arpeggio(freqs: Array[float], vol: float) -> PackedFloat32Array:
	var dur := MUSIC_LOOP_SECONDS
	var steps := 12
	var step := dur / float(steps)
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var idx := int(t / step) % freqs.size()
		var local := fmod(t, step)
		var c: float = round(float(freqs[idx]) * dur)
		var tone := sin(TAU * c * t / dur) * _env(local, step, 0.005)
		var root := sin(TAU * round(108.0 * dur) * t / dur) * 0.25
		out[i] = (tone * 0.7 + root) * vol
	return out
