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
		"passed": DamageResult.IGNORE_INVALID_PAYLOAD == &"invalid_payload" and DamageResult.IGNORE_DEAD == &"dead"
			and DamageResult.IGNORE_BLOCKED == &"blocked",
		"why": "",
	})

	# Fully absorbed / zero-amount hits must not stagger or emit damaged.
	var hp := HealthComponent.new()
	hp.current_health = 50.0
	hp.max_health = 50.0
	var zero := DamagePayload.new()
	zero.amount = 0.0
	var zr := hp.take_damage(zero)
	results.append({
		"name": "zero-amount hit is blocked not accepted",
		"passed": not zr.accepted and zr.ignored_reason == DamageResult.IGNORE_BLOCKED
			and is_equal_approx(hp.current_health, 50.0),
		"why": "reason=%s hp=%f" % [String(zr.ignored_reason), hp.current_health],
	})
	hp.set_mitigation_source(func(_amount: float, _payload: DamagePayload) -> float: return 0.0)
	var absorbed := DamagePayload.new()
	absorbed.amount = 25.0
	var ar := hp.take_damage(absorbed)
	results.append({
		"name": "fully mitigated hit is blocked not accepted",
		"passed": not ar.accepted and ar.ignored_reason == DamageResult.IGNORE_BLOCKED
			and is_equal_approx(hp.current_health, 50.0),
		"why": "reason=%s hp=%f" % [String(ar.ignored_reason), hp.current_health],
	})
	hp.free()
	return results
