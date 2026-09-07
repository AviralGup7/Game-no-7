extends RefCounted

## Headless unit tests for combat payload/result validation.
## DamagePayload and DamageResult are registered class_names, so referencing them
## directly keeps `.new()` statically typed (no inference-from-Variant issues).

static func suite() -> Array:
	var results: Array = []

	var p := DamagePayload.new()
	p.amount = 10.0
	results.append({"name": "valid payload accepted", "passed": p.is_valid(), "why": ""})

	p.amount = -1.0
	results.append({"name": "negative amount rejected", "passed": not p.is_valid(), "why": ""})

	p.amount = INF
	results.append({"name": "infinite amount rejected", "passed": not p.is_valid(), "why": ""})

	p.amount = NAN
	results.append({"name": "NaN amount rejected", "passed": not p.is_valid(), "why": ""})

	var q := DamagePayload.new()
	q.amount = 5.0
	q.critical_multiplier = 0.5
	results.append({"name": "critical_multiplier < 1 rejected", "passed": not q.is_valid(), "why": ""})

	# Defaults per schema
	var d := DamagePayload.new()
	results.append({
		"name": "defaults: physical, no status effects, timestamp set",
		"passed": d.damage_type == &"physical" and d.status_effects.is_empty() and d.timestamp_msec > 0,
		"why": "",
	})

	# DamageResult constants exist
	results.append({
		"name": "DamageResult ignore reasons defined",
		"passed": DamageResult.IGNORE_INVALID_PAYLOAD == &"invalid_payload" and DamageResult.IGNORE_DEAD == &"dead",
		"why": "",
	})
	return results
