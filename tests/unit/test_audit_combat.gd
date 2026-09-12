extends RefCounted
## Real signal/health boundaries and upgrade ownership; no renderer or clock assumptions.

static func suite() -> Array:
	var results: Array = []
	_health_boundaries(results)
	_boss_death_boundary(results)
	_expired_damage_source(results)
	_effect_ownership(results)
	return results


static func _check(results: Array, label: String, passed: bool) -> void:
	results.append({"name": label, "passed": passed, "why": ""})


static func _payload(amount: float, source: Node = null) -> DamagePayload:
	var payload := DamagePayload.new()
	payload.amount = amount
	payload.source = source
	payload.source_id = &"audit_hit"
	return payload


static func _health_boundaries(results: Array) -> void:
	var hp := HealthComponent.new()
	hp.reset(10.0)
	var malformed := _payload(NAN)
	var rejected := hp.take_damage(malformed)
	_check(results, "invalid damage is rejected without mutating caller payload", not rejected.accepted and rejected.ignored_reason == DamageResult.IGNORE_INVALID_PAYLOAD and is_nan(malformed.amount) and hp.current_health == 10.0)
	hp.set_mitigation_source(func(_amount: float, _payload_value: DamagePayload) -> float: return NAN)
	_check(results, "non-finite mitigation cannot poison health", not hp.take_damage(_payload(1.0)).accepted and hp.current_health == 10.0)
	hp.set_mitigation_source(func(_amount: float, _payload_value: DamagePayload) -> float: return INF)
	_check(results, "infinite mitigation cannot become a lethal accepted hit", not hp.take_damage(_payload(1.0)).accepted and not hp.is_dead())
	hp.set_mitigation_source(Callable())
	hp.set_invulnerable(INF)
	hp.set_max_health(NAN)
	_check(results, "non-finite health and invulnerability settings are ignored", hp.max_health == 10.0 and not hp.is_invulnerable())
	var events: Array[String] = []
	var nested: Array = []
	var healing: Array[float] = [-1.0]
	hp.health_changed.connect(func(_current: float, _maximum: float) -> void: events.append("health"))
	hp.damaged.connect(func(_result: DamageResult) -> void:
		events.append("damage")
		if nested.is_empty():
			nested.append(null)  # Bounds the fixture even on a re-entrant implementation.
			nested[0] = hp.take_damage(_payload(1.0))
			healing[0] = hp.heal(5.0)
	)
	hp.died.connect(func() -> void: events.append("death"))
	var lethal := hp.take_damage(_payload(10.0))
	var reentered := nested[0] as DamageResult
	_check(results, "lethal hits commit death before damage observers re-enter", lethal.target_died and hp.is_dead() and hp.current_health == 0.0 and not reentered.accepted and reentered.ignored_reason == DamageResult.IGNORE_DEAD and healing[0] == 0.0)
	_check(results, "death notification stays exactly once and ordered", events == ["health", "damage", "death"])
	hp.free()


static func _effect_ownership(results: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var fixture := Node3D.new()
	tree.root.add_child(fixture)
	fixture.position = Vector3(20, 0, 30)
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player := player_scene.instantiate() as Player
	fixture.add_child(player)
	var progression := player.get_progression_component()
	progression.set_current_wave(10)
	_check(results, "audit proc upgrades validate and equip", progression.apply_upgrade(ContentRegistry.get_upgrade(&"storm_edge")) and progression.apply_upgrade(ContentRegistry.get_upgrade(&"reaper_mark")))
	var effects := BuildEffects.new()
	effects.name = "BuildEffects"
	player.add_child(effects)
	effects.bind(player, progression, 17)
	var origin := AuditDamageVictim.new()
	var neighbor := AuditDamageVictim.new()
	fixture.add_child(origin)
	fixture.add_child(neighbor)
	origin.global_position = Vector3(100, 0, 100)
	neighbor.global_position = Vector3(102, 0, 100)
	origin.apply_damage(_payload(10.0))
	_check(results, "environmental damage cannot trigger player offensive upgrades", origin.health.current_health == 90.0 and neighbor.health.current_health == 100.0)
	origin.health.reset(100.0)
	var direct := origin.apply_damage(_payload(10.0, player))
	_check(results, "accepted health results preserve the attacker and source id", direct.source == player and direct.source_id == &"audit_hit")
	_check(results, "chain lightning skips its original victim and cannot recursively proc itself", origin.health.current_health == 90.0 and is_equal_approx(neighbor.health.current_health, 95.5))
	origin.health.current_health = 15.0
	origin.apply_damage(_payload(1.0))
	_check(results, "environmental chip damage cannot receive a free execute", origin.is_alive() and origin.health.current_health == 14.0)
	origin.apply_damage(_payload(1.0, player))
	_check(results, "player hits still execute low-health enemies", not origin.is_alive())
	effects._spawn_trail(Vector3.ZERO, &"fire", 1.0)
	effects._spawn_summon(Vector3(100, 0, 100))
	var ally := effects._summons[0]["node"] as Node3D
	_check(results, "summon placement is world-space under a translated parent", ally.global_position.is_equal_approx(Vector3(100, 0.1, 100)))
	player.isolate_run()
	_check(results, "game-over isolation stops and drains transformative effects", not effects._enabled and effects._trails.is_empty() and effects._summons.is_empty() and ally.is_queued_for_deletion() and not EventBus.enemy_damaged.is_connected(effects._on_enemy_damaged) and not EventBus.enemy_killed.is_connected(effects._on_enemy_killed) and not player.dodged.is_connected(effects._on_player_dodged))
	effects.bind(player, progression, 18)
	_check(results, "a new run rebinds one clean effect subscription", effects._enabled and EventBus.enemy_damaged.is_connected(effects._on_enemy_damaged) and player.dodged.is_connected(effects._on_player_dodged) and effects._kill_counter == 0)
	var replacement := Player.new()  # Signal owner only; never enters the live scene.
	effects.bind(replacement, progression, 19)
	_check(results, "rebinding effects disconnects the previous player", not player.dodged.is_connected(effects._on_player_dodged) and replacement.dodged.is_connected(effects._on_player_dodged))
	effects.isolate_run()
	replacement.free()
	tree.root.remove_child(fixture)
	fixture.free()


static func _boss_death_boundary(results: Array) -> void:
	var boss := EnemyBase.new()
	var controller := BossController.new()
	controller._host = boss
	controller.configure_phases(controller._default_phases())
	controller._announced_intro = true
	var changes: Array[int] = [0]
	controller.phase_advanced.connect(func(_phase: int, _count: int) -> void: changes[0] += 1)
	controller._on_health_changed(0.0, 100.0)
	controller._on_health_changed(-1.0, 100.0)
	_check(results, "zero-health boss does not enrage, buff itself or emit a phase", changes[0] == 0 and controller.current_phase() == 0 and not controller._enraged and boss._damage_scale == 1.0)
	controller.free()
	boss.free()


static func _expired_damage_source(results: Array) -> void:
	var root := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var owner_node := Node3D.new()
	root.add_child(owner_node)
	var victim := AuditDamageVictim.new()
	root.add_child(victim)
	var projectile := Projectile.new()
	root.add_child(projectile)
	projectile.source = owner_node
	projectile.source_id = &"expired_source_test"
	projectile.team = Projectile.TEAM_PLAYER
	projectile.damage = 5.0
	projectile._active = true
	var payload := _payload(5.0, owner_node)
	owner_node.free()
	var copy := payload.with_amount(3.0)
	_check(results, "damage clones drop expired node references without losing source ids", copy.source == null and copy.source_id == payload.source_id)
	projectile._resolve_hit(victim)
	_check(results, "projectiles still resolve damage after their shooter is freed", victim.health.current_health == 95.0 and not projectile._active)
	root.free()
