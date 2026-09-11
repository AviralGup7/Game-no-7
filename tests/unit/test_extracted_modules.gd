extends RefCounted

## Headless unit tests for modules extracted during the large-file split:
## SpawnLedger, SaveSchema, UiText, DamagePayload.with_amount, PlayerCombat,
## and the player-component bind/cooldown seams. All are autoload-independent.


static func suite() -> Array:
	var results: Array = []
	_spawn_ledger(results)
	_save_schema(results)
	_ui_text(results)
	_payload_copy(results)
	_player_modules(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


# --- SpawnLedger ---

static func _spawn_ledger(results: Array) -> void:
	var ledger := SpawnLedger.new()
	var queue: Array[StringName] = [&"a", &"b", &"c"]
	ledger.reset(queue)
	_check(results, "reset plans the queue", ledger.planned_count() == 3 and ledger.pending_count() == 3)
	_check(results, "peek does not consume", ledger.peek() == &"a" and ledger.pending_count() == 3)
	ledger.note_head(&"a")
	ledger.pop_on_success()
	_check(results, "pop_on_success consumes + counts", ledger.peek() == &"b" and ledger.spawned_count() == 1 and ledger.pending_count() == 2)
	# Retry bound: MAX-1 attempts keep retrying, the MAXth drops the head as failed.
	ledger.note_head(&"b")
	var dropped := false
	for i in range(SpawnLedger.MAX_FAILED_ATTEMPTS - 1):
		dropped = ledger.note_attempt()
	_check(results, "attempts under bound retry", not dropped and ledger.peek() == &"b" and ledger.failed_count() == 0)
	dropped = ledger.note_attempt()
	_check(results, "bound exhausted drops head as failed", dropped and ledger.peek() == &"c" and ledger.failed_count() == 1 and ledger.pending_count() == 1)
	# New head resets the attempt clock.
	ledger.note_head(&"c")
	_check(results, "new head resets attempts", ledger.attempt_count() == 0)
	ledger.extend_one(&"mite")
	_check(results, "extend_one grows plan + pending", ledger.planned_count() == 4 and ledger.pending_count() == 2)
	ledger.record_defeat()
	_check(results, "record_defeat counts", ledger.defeated_count() == 1)
	var snap := ledger.snapshot()
	_check(results, "snapshot carries all counters",
		int(snap.get("planned", 0)) == 4 and int(snap.get("pending", 0)) == 2
		and int(snap.get("spawned", 0)) == 1 and int(snap.get("defeated", 0)) == 1
		and int(snap.get("failed", 0)) == 0 + 1)
	ledger.clear()
	_check(results, "clear zeroes everything",
		ledger.planned_count() == 0 and ledger.pending_count() == 0 and ledger.spawned_count() == 0
		and ledger.defeated_count() == 0 and ledger.failed_count() == 0 and ledger.is_empty())


# --- SaveSchema ---

static func _save_schema(results: Array) -> void:
	var fresh := SaveSchema.normalize_save(null)
	_check(results, "schema null -> defaults", fresh is Dictionary and int(fresh.get("schema_version", 0)) == SaveSchema.SCHEMA_VERSION)
	_check(results, "schema defaults carry v3 keys",
		fresh.has("tutorial_completed") and fresh.has("achievements") and fresh.has("meta_wallet") and fresh.has("meta_ranks"))
	var migrated := SaveSchema.normalize_save({"schema_version": 1, "best_score": 9, "meta_wallet": -4})
	_check(results, "schema migrates + clamps",
		int(migrated.get("schema_version", 0)) == SaveSchema.SCHEMA_VERSION
		and int(migrated.get("best_score", 0)) == 9 and int(migrated.get("meta_wallet", -1)) == 0)
	var ranks := SaveSchema.normalize_save({"schema_version": 3, "meta_ranks": {"vitality": 2, "bad": "x"}})
	var rank_map: Dictionary = ranks.get("meta_ranks", {})
	_check(results, "schema sanitizes rank map", int(rank_map.get("vitality", 0)) == 2 and not rank_map.has("bad"))


# --- UiText ---

static func _ui_text(results: Array) -> void:
	_check(results, "known key resolves", UiText.lookup(&"play") == "PLAY")
	_check(results, "unknown key echoes", UiText.lookup(&"missing_key_xyz") == "missing_key_xyz")


# --- DamagePayload.with_amount ---

static func _payload_copy(results: Array) -> void:
	var src := DamagePayload.new()
	src.amount = 10.0
	src.source_id = &"melee"
	src.knockback = Vector3(1, 0, 0)
	src.status_effects = [&"burn"] as Array[StringName]
	src.metadata = {"k": 1}
	var copy := src.with_amount(4.0)
	_check(results, "with_amount replaces amount", is_equal_approx(copy.amount, 4.0) and is_equal_approx(src.amount, 10.0))
	_check(results, "with_amount keeps other fields",
		copy.source_id == &"melee" and copy.knockback == Vector3(1, 0, 0) and copy.status_effects == [&"burn"])
	copy.status_effects.append(&"slow")
	copy.metadata["k"] = 2
	_check(results, "with_amount duplicates containers",
		src.status_effects == [&"burn"] and int(src.metadata.get("k", 0)) == 1)
	_check(results, "with_amount floors at zero", is_equal_approx(src.with_amount(-5.0).amount, 0.0))


# --- PlayerCombat / Dodge cooldown / Stamina delta ---

static func _player_modules(results: Array) -> void:
	var combat := PlayerCombat.new()
	var fired := [0]
	var accepted := combat.request_attack(func() -> bool:
		fired[0] += 1
		return true
	)
	_check(results, "unbound combat refuses attack", not accepted and fired[0] == 0)
	_check(results, "unbound combat refuses dodge", not combat.request_dodge())
	_check(results, "unbound combat is not busy", not combat.is_busy())
	combat.cancel()
	_check(results, "unbound cancel is safe", combat.buffer.remaining == 0.0)

	var dodge := DodgeController.new()
	dodge.cooldown = 0.8
	_check(results, "unbound dodge cooldown is authored seconds", is_equal_approx(dodge._effective_cooldown(), 0.8))
	var prog := ProgressionComponent.new()
	prog.add_permanent_bonus(&"dodge_cooldown_multiplier", -0.1)
	dodge.bind_motion(null, prog)
	var one_stack := dodge._effective_cooldown()
	_check(results, "dodge cooldown multiplies authored duration", is_equal_approx(one_stack, 0.72),
		"got %.4f" % one_stack)
	# The multiplier (0.9) must never replace the authored 0.8s window.
	_check(results, "multiplier is not used as the cooldown itself", not is_equal_approx(one_stack, 0.9),
		"got %.4f" % one_stack)
	prog.add_permanent_bonus(&"dodge_cooldown_multiplier", -0.1)
	_check(results, "stacked dodge reduction stays a product", is_equal_approx(dodge._effective_cooldown(), 0.64),
		"got %.4f" % dodge._effective_cooldown())

	var stamina := StaminaComponent.new()
	stamina._current = 50.0
	stamina._max = 100.0
	stamina._since_spend = 10.0
	stamina._physics_process(NAN)
	_check(results, "NaN stamina delta does not poison regen clock",
		is_finite(stamina._since_spend) and is_equal_approx(stamina._since_spend, 10.0),
		"got %.4f" % stamina._since_spend)
	stamina._physics_process(-1.0)
	_check(results, "negative stamina delta is ignored", is_equal_approx(stamina._since_spend, 10.0))
	stamina.free()
	dodge.free()
	prog.free()
