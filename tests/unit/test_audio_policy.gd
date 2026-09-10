extends RefCounted

## Headless unit tests for the audio playback-engine rebuild (v2):
## the SfxPolicy voice governor (cooldown / per-cue cap / oldest-steal),
## the AudioConfig built-in contracts, and the MusicManager's pure layering
## decisions (layer mapping, stem levels, asymmetric fades). No tree, no
## autoloads, no nodes — deterministic.

static func suite() -> Array:
	var results: Array = []

	# --- SfxPolicy: cooldown spam guard ---
	var pol := SfxPolicy.new()
	pol.configure(&"step", 0.10, 4)
	var d0: Dictionary = pol.try_play(&"step", 1.0)
	results.append({
		"name": "SfxPolicy first play is FRESH",
		"passed": d0["action"] == SfxPolicy.FRESH,
		"why": str(d0),
	})
	pol.note_played(&"step", 1.0)
	var d1: Dictionary = pol.try_play(&"step", 1.05)
	results.append({
		"name": "SfxPolicy rejects inside the cooldown window",
		"passed": d1["action"] == SfxPolicy.REJECT,
		"why": str(d1),
	})
	var d2: Dictionary = pol.try_play(&"step", 1.11)
	results.append({
		"name": "SfxPolicy allows again after the cooldown elapses",
		"passed": d2["action"] == SfxPolicy.FRESH,
		"why": str(d2),
	})

	# --- SfxPolicy: per-cue cap + oldest steal ---
	var p2 := SfxPolicy.new()
	p2.configure(&"shot", 0.0, 2)
	var r1: Dictionary = p2.try_play(&"shot", 0.0)
	p2.voice_started(&"shot", 10)
	var r2: Dictionary = p2.try_play(&"shot", 0.1)
	p2.voice_started(&"shot", 11)
	var r3: Dictionary = p2.try_play(&"shot", 0.2)
	results.append({
		"name": "SfxPolicy caps voices per cue and steals the OLDEST",
		"passed": r1["action"] == SfxPolicy.FRESH and r2["action"] == SfxPolicy.FRESH
			and r3["action"] == SfxPolicy.STEAL and int(r3["steal_token"]) == 10,
		"why": str([r1, r2, r3]),
	})
	p2.voice_ended(&"shot", 10)
	var r4: Dictionary = p2.try_play(&"shot", 0.3)
	results.append({
		"name": "SfxPolicy voice_ended frees a slot (FRESH again)",
		"passed": r4["action"] == SfxPolicy.FRESH,
		"why": str(r4),
	})
	# Cooldown outranks the cap: a suppressed play must not steal.
	var p3 := SfxPolicy.new()
	p3.configure(&"hurt", 0.5, 1)
	p3.voice_started(&"hurt", 5)
	p3.note_played(&"hurt", 1.0)
	var r5: Dictionary = p3.try_play(&"hurt", 1.1)
	results.append({
		"name": "SfxPolicy cooldown outranks cap (reject, no steal)",
		"passed": r5["action"] == SfxPolicy.REJECT and int(r5["steal_token"]) == -1,
		"why": str(r5),
	})

	# --- SfxPolicy: cue isolation + unknown cue defaults ---
	var p4 := SfxPolicy.new()
	p4.configure(&"a", 0.5, 1)
	p4.note_played(&"a", 0.0)
	var iso: Dictionary = p4.try_play(&"b", 0.0)
	results.append({
		"name": "SfxPolicy state is per-cue (isolation)",
		"passed": iso["action"] == SfxPolicy.FRESH and p4.active_count(&"a") == 0,
		"why": str(iso),
	})
	var p5 := SfxPolicy.new()  # never configured
	var def0: Dictionary = p5.try_play(&"mystery", 0.0)
	for i in range(SfxPolicy.DEFAULT_CAP):
		p5.voice_started(&"mystery", i)
	var def1: Dictionary = p5.try_play(&"mystery", 1.0)
	results.append({
		"name": "SfxPolicy unconfigured cues use the default cap",
		"passed": def0["action"] == SfxPolicy.FRESH
			and def1["action"] == SfxPolicy.STEAL and int(def1["steal_token"]) == 0,
		"why": str([def0, def1]),
	})
	# Determinism: identical input sequences -> identical decisions.
	var a := SfxPolicy.new()
	var b := SfxPolicy.new()
	a.configure(&"x", 0.2, 3)
	b.configure(&"x", 0.2, 3)
	var same := true
	for i in range(12):
		var da: Dictionary = a.try_play(&"x", float(i) * 0.05)
		var db: Dictionary = b.try_play(&"x", float(i) * 0.05)
		if da != db:
			same = false
			break
		if da["action"] == SfxPolicy.FRESH:
			a.note_played(&"x", float(i) * 0.05)
			b.note_played(&"x", float(i) * 0.05)
			a.voice_started(&"x", i)
			b.voice_started(&"x", i)
		if da["action"] == SfxPolicy.STEAL:
			a.voice_ended(&"x", int(da["steal_token"]))
			b.voice_ended(&"x", int(da["steal_token"]))
	results.append({
		"name": "SfxPolicy is deterministic for identical input",
		"passed": same,
		"why": "",
	})

	# --- AudioConfig.for_cue: the built-in contract is live ---
	var step := AudioConfig.for_cue(&"player_step")
	results.append({
		"name": "for_cue: spam sources get cooldown + raised cap",
		"passed": step.cooldown > 0.0 and step.max_voices >= 4 and step.bus == &"SFX",
		"why": "cd=%f cap=%d bus=%s" % [step.cooldown, step.max_voices, String(step.bus)],
	})
	var ui := AudioConfig.for_cue(&"ui_confirm")
	results.append({
		"name": "for_cue: UI cues route to the UI bus",
		"passed": ui.bus == &"UI" and ui.max_voices == 2,
		"why": "bus=%s cap=%d" % [String(ui.bus), ui.max_voices],
	})
	var hurt := AudioConfig.for_cue(&"player_hurt")
	results.append({
		"name": "for_cue: one-shot feedback never layers (cap 1)",
		"passed": hurt.max_voices == 1 and hurt.cooldown > 0.0,
		"why": "cap=%d cd=%f" % [hurt.max_voices, hurt.cooldown],
	})
	var generic := AudioConfig.for_cue(&"totally_unknown_cue")
	results.append({
		"name": "for_cue: generic default is conservative (no variance, SFX bus)",
		"passed": generic.bus == &"SFX" and generic.max_voices == AudioConfig.DEFAULT_MAX_VOICES
			and generic.cooldown == 0.0 and generic.volume_var_db == 0.0
			and generic.pitch_var == 0.0,
		"why": "bus=%s cap=%d" % [String(generic.bus), generic.max_voices],
	})
	var all_valid := true
	for key in AudioConfig._TUNED.keys():
		var cfg := AudioConfig.for_cue(StringName(String(key)))
		if not cfg.validate().is_empty():
			all_valid = false
	results.append({
		"name": "for_cue: every tuned contract validates clean",
		"passed": all_valid,
		"why": "",
	})

	# --- MusicManager: pure layering decisions ---
	results.append({
		"name": "target_layer_for: non-combat states sit at the bed",
		"passed": MusicManager.target_layer_for(MusicManager.STATE_MENU, 1.5) == 0
			and MusicManager.target_layer_for(MusicManager.STATE_CALM, 1.5) == 0
			and MusicManager.target_layer_for(MusicManager.STATE_VICTORY, 1.5) == 0
			and MusicManager.target_layer_for(MusicManager.STATE_SILENT, 0.0) == 0,
		"why": "",
	})
	results.append({
		"name": "target_layer_for: battle maps heat 0..1.5 across 1..3, boss peaks",
		"passed": MusicManager.target_layer_for(MusicManager.STATE_BATTLE, 0.0) == 1
			and MusicManager.target_layer_for(MusicManager.STATE_BATTLE, 0.5) == 2
			and MusicManager.target_layer_for(MusicManager.STATE_BATTLE, 1.0) == 3
			and MusicManager.target_layer_for(MusicManager.STATE_BATTLE, 1.5) == 3
			and MusicManager.target_layer_for(MusicManager.STATE_BOSS, 0.0) == 3,
		"why": "",
	})
	var l0 := MusicManager.stem_targets(0)
	var l1 := MusicManager.stem_targets(1)
	var l2 := MusicManager.stem_targets(2)
	var l3 := MusicManager.stem_targets(3)
	var monotone := l0[0] <= l1[0] and l1[0] <= l2[0] and l2[0] <= l3[0] \
		and l0[1] <= l1[1] and l1[1] <= l2[1] and l2[1] <= l3[1]
	results.append({
		"name": "stem_targets: layers are monotone-louder; layer 0 is silence",
		"passed": l0 == [MusicManager.SILENCE_DB, MusicManager.SILENCE_DB]
			and l3[0] > l1[0] and l3[1] > MusicManager.SILENCE_DB and monotone,
		"why": str([l0, l1, l2, l3]),
	})
	results.append({
		"name": "stem fades are asymmetric (up fast, down slow)",
		"passed": MusicManager.stem_fade_seconds(true) < MusicManager.stem_fade_seconds(false)
			and MusicManager.STEM_FADE_UP_SECONDS <= 1.0
			and MusicManager.STEM_FADE_DOWN_SECONDS >= 1.0
			and MusicManager.LAYER_DWELL_SECONDS > 0.0,
		"why": "up=%f down=%f dwell=%f" % [
			MusicManager.STEM_FADE_UP_SECONDS,
			MusicManager.STEM_FADE_DOWN_SECONDS,
			MusicManager.LAYER_DWELL_SECONDS],
	})
	# Boss (layer 3) must be the hottest combination.
	var boss_hot := l3[0] >= MusicManager.stem_targets(2)[0] and l3[1] > MusicManager.stem_targets(2)[1]
	results.append({
		"name": "stem_targets: boss layer (3) is strictly hotter than layer 2",
		"passed": boss_hot,
		"why": str([l3, MusicManager.stem_targets(2)]),
	})

	return results
