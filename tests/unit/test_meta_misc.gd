extends RefCounted

## Headless unit tests for DailyChallenge, the XP curve statics,
## Minimap projection, JsonHelpers and AudioConfig validation.

static func suite() -> Array:
	var results: Array = []

	# --- DailyChallenge: deterministic per stamp ---
	var s1 := DailyChallenge.seed_for_stamp(20260907)
	var s2 := DailyChallenge.seed_for_stamp(20260907)
	var s3 := DailyChallenge.seed_for_stamp(20260908)
	results.append({
		"name": "DailyChallenge seeds stable per day, differ across days",
		"passed": s1 == s2 and s1 != s3 and s1 > 0,
		"why": "",
	})
	var m1 := DailyChallenge.mutators_for_stamp(20260907)
	var m2 := DailyChallenge.mutators_for_stamp(20260907)
	results.append({
		"name": "DailyChallenge mutators deterministic + distinct",
		"passed": m1 == m2 and m1.size() == 2 and m1[0] != m1[1]
			and WaveMutators.is_known(m1[0]) and WaveMutators.is_known(m1[1]),
		"why": str(m1),
	})
	var w := DailyChallenge.weapon_for_stamp(20260907)
	results.append({
		"name": "DailyChallenge weapon rotates among starters",
		"passed": w in [&"gladius", &"warreaxe", &"sentinel_spear"],
		"why": String(w),
	})
	var sub_a := DailyChallenge.submission_record({"stamp": 1, "seed": 2}, 500, 6, "Ada")
	var sub_b := DailyChallenge.submission_record({"stamp": 1, "seed": 2}, 400, 9, "Bob")
	results.append({
		"name": "DailyChallenge score beats wave in compare",
		"passed": DailyChallenge.compare_submissions(sub_a, sub_b) == 1
			and DailyChallenge.compare_submissions(sub_b, sub_a) == -1
			and DailyChallenge.compare_submissions(sub_a, sub_a) == 0,
		"why": "",
	})

	# --- XP curve: monotonic, invertible ---
	var l2 := ExperienceComponent.xp_for_level(1)
	var l3 := ExperienceComponent.xp_for_level(2)
	var total5 := ExperienceComponent.total_xp_for_level(5)
	results.append({
		"name": "XP curve grows; totals invert to levels",
		"passed": l3 > l2 and ExperienceComponent.level_for_total_xp(0) == 1
			and ExperienceComponent.level_for_total_xp(total5) == 5
			and ExperienceComponent.level_for_total_xp(total5 - 1) == 4,
		"why": "l2=%d l3=%d total5=%d" % [l2, l3, total5],
	})

	# --- Minimap projection: centre + clamp-to-rim ---
	var center := Vector2(70, 70)
	var p_center := Minimap.project_to_map(Vector2.ZERO, center, 60.0, 12.0)
	var p_rim := Minimap.project_to_map(Vector2(100, 0), center, 60.0, 12.0)
	results.append({
		"name": "Minimap projects centre + clamps to rim",
		"passed": p_center.distance_to(center) < 0.01 and p_rim.distance_to(center) <= 60.01,
		"why": str(p_rim),
	})

	# --- JsonHelpers: total functions never throw ---
	results.append({
		"name": "JsonHelpers parse/stringify/deep_merge safe",
		"passed": JsonHelpers.parse_safe("not json", {"fb": 1}) == {"fb": 1}
			and JsonHelpers.parse_safe("", 7) == 7
			and JsonHelpers.deep_merge({"a": {"x": 1}}, {"a": {"y": 2}}) == {"a": {"x": 1, "y": 2}}
			and is_equal_approx(JsonHelpers.clamped_number({"v": 99}, "v", 0.0, 1.0, 0.5), 1.0)
			and is_equal_approx(JsonHelpers.clamped_number({}, "v", 0.0, 1.0, 0.5), 0.5),
		"why": "",
	})

	# --- AudioConfig validation + rolls ---
	var cue := AudioConfig.new()
	cue.cue_id = &"hit"
	cue.bus = &"SFX"
	cue.volume_var_db = 2.0
	cue.pitch_var = 0.1
	var arng := RandomNumberGenerator.new()
	arng.seed = 3
	results.append({
		"name": "AudioConfig valid passes, rolls vary in range",
		"passed": cue.validate().is_empty()
			and cue.roll_volume_db(arng) >= -2.0 and cue.roll_volume_db(arng) <= 2.0
			and cue.roll_pitch(arng) > 0.5,
		"why": "",
	})
	var bad_cue := AudioConfig.new()
	bad_cue.bus = &"Nope"
	bad_cue.max_voices = 0
	results.append({"name": "AudioConfig flags bad bus/voices", "passed": bad_cue.validate().size() >= 2, "why": ""})

	# --- InputRemapper: labels + safe serialize ---
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	var label := InputRemapper.binding_label(key)
	var ser := InputRemapper.serialize_actions([&"attack"])
	results.append({
		"name": "InputRemapper labels keys, serializes attack binds",
		"passed": label == "Space" and ser.has("attack") and (ser["attack"] as Array).size() >= 1,
		"why": label,
	})
	results.append({
		"name": "InputRemapper rejects junk deserializes",
		"passed": InputRemapper.deserialize_actions({"attack": [{"kind": "nope"}]}) == 0
			and InputRemapper.deserialize_event({}) == null,
		"why": "",
	})

	return results
