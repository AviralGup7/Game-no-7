extends RefCounted

## Headless unit tests for combat payload/result validation.

static func suite() -> Array:
	var results: Array = []
	var Payload = load("res://scripts/combat/damage_payload.gd")
	var Result = load("res://scripts/combat/damage_result.gd")

	var p := Payload.new()
	p.amount = 10.0
	results.append({"name": "valid payload accepted", "passed": p.is_valid(), "why": ""})

	p.amount = -1.0
	results.append({"name": "negative amount rejected", "passed": not p.is_valid(), "why": ""})

	p.amount = INF
	results.append({"name": "infinite amount rejected", "passed": not p.is_valid(), "why": ""})

	p.amount = NAN
	results.append({"name": "NaN amount rejected", "passed": not p.is_valid(), "why": ""})

	var q := Payload.new()
	q.amount = 5.0
	q.critical_multiplier = 0.5
	results.append({"name": "critical_multiplier < 1 rejected", "passed": not q.is_valid(), "why": ""})

	# Defaults per schema
	var d := Payload.new()
	results.append({
		"name": "defaults: physical, no status effects, timestamp set",
		"passed": d.damage_type == &"physical" and d.status_effects.is_empty() and d.timestamp_msec > 0,
		"why": "",
	})

	# DamageResult constants exist
	results.append({
		"name": "DamageResult ignore reasons defined",
		"passed": Result.IGNORE_INVALID_PAYLOAD == &"invalid_payload" and Result.IGNORE_DEAD == &"dead",
		"why": "",
	})
	return results
