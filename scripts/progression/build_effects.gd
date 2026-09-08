class_name BuildEffects
extends Node

## Runtime owner of *transformative* upgrade effects — the ones that change how
## the player plays rather than only stacking stats. Attached as a child of the
## Player by Main (or created lazily). Listens to dodge / kill / attack signals
## and fires area damage, status trails, and temporary allies.
##
## Effect keys are plain StringNames recorded on UpgradeConfig.effect_tags (and
## mirrored into ProgressionComponent via has_upgrade). Adding a new effect is:
##   1. author the upgrade .tres with the tag
##   2. handle the tag in the match below
## No core combat rewrite required.

const EFFECT_CHAIN_MELEE := &"chain_melee"
const EFFECT_FIRE_TRAIL := &"fire_trail"
const EFFECT_KILL_SUMMON := &"kill_summon"
const EFFECT_THORN_NOVA := &"thorn_nova"
const EFFECT_FROST_DODGE := &"frost_dodge"
const EFFECT_EXECUTE := &"execute_threshold"
const EFFECT_LIFESTEAL_BURST := &"lifesteal_burst"
const EFFECT_STATIC_FIELD := &"static_field"

const FIRE_TRAIL_DAMAGE := 8.0
const FIRE_TRAIL_RADIUS := 1.6
const FIRE_TRAIL_DURATION := 1.8
const CHAIN_JUMPS := 3
const CHAIN_RADIUS := 4.5
const CHAIN_DAMAGE_RATIO := 0.45
const SUMMON_DURATION := 8.0
const SUMMON_DAMAGE := 12.0
const THORN_RADIUS := 3.0
const THORN_DAMAGE := 18.0
const EXECUTE_THRESHOLD := 0.18  # % max HP
const STATIC_FIELD_RADIUS := 3.5
const STATIC_FIELD_DAMAGE := 6.0

var _player: Node = null
var _progression: Node = null
var _trails: Array = []  # [{pos, ttl, kind}]
var _summons: Array = []  # [{node, ttl}]
var _seed := 1
var _kill_counter := 0
var _enabled := true
var _handling_hit := false  # re-entry guard for chain/execute cascades


func bind(player: Node, progression: Node, run_seed: int = 1) -> void:
	_player = player
	_progression = progression
	_seed = run_seed if run_seed != 0 else 1
	_wire_signals()


func configure(run_seed: int) -> void:
	_seed = run_seed if run_seed != 0 else 1
	_trails.clear()
	_clear_summons()
	_kill_counter = 0


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func _wire_signals() -> void:
	if _player == null:
		return
	if _player.has_signal("dodged") and not _player.dodged.is_connected(_on_player_dodged):
		_player.dodged.connect(_on_player_dodged)
	if _player.has_signal("attack_hit") and not _player.attack_hit.is_connected(_on_attack_hit):
		_player.attack_hit.connect(_on_attack_hit)
	if _player.has_signal("damaged") and not _player.damaged.is_connected(_on_player_damaged):
		_player.damaged.connect(_on_player_damaged)
	if EventBus != null:
		if not EventBus.enemy_killed.is_connected(_on_enemy_killed):
			EventBus.enemy_killed.connect(_on_enemy_killed)
		# WeaponManager path does not emit Player.attack_hit; enemy_damaged covers both.
		if not EventBus.enemy_damaged.is_connected(_on_enemy_damaged):
			EventBus.enemy_damaged.connect(_on_enemy_damaged)


func _exit_tree() -> void:
	if _player != null and is_instance_valid(_player):
		if _player.has_signal("dodged") and _player.dodged.is_connected(_on_player_dodged):
			_player.dodged.disconnect(_on_player_dodged)
		if _player.has_signal("attack_hit") and _player.attack_hit.is_connected(_on_attack_hit):
			_player.attack_hit.disconnect(_on_attack_hit)
		if _player.has_signal("damaged") and _player.damaged.is_connected(_on_player_damaged):
			_player.damaged.disconnect(_on_player_damaged)
	if EventBus != null:
		if EventBus.enemy_killed.is_connected(_on_enemy_killed):
			EventBus.enemy_killed.disconnect(_on_enemy_killed)
		if EventBus.enemy_damaged.is_connected(_on_enemy_damaged):
			EventBus.enemy_damaged.disconnect(_on_enemy_damaged)
	_clear_summons()


func _physics_process(delta: float) -> void:
	if not _enabled or not is_finite(delta) or delta <= 0.0:
		return
	_tick_trails(delta)
	_tick_summons(delta)
	if _has(EFFECT_STATIC_FIELD):
		_tick_static_field(delta)


func has_effect(effect_id: StringName) -> bool:
	return _has(effect_id)


func _has(effect_id: StringName) -> bool:
	if _progression == null or not is_instance_valid(_progression):
		return false
	# Prefer dedicated effect query; fall back to upgrade id == effect id.
	if _progression.has_method("has_effect") and bool(_progression.call("has_effect", effect_id)):
		return true
	if _progression.has_method("has_upgrade") and bool(_progression.call("has_upgrade", effect_id)):
		return true
	return false


func _stacks(effect_id: StringName) -> int:
	if _progression != null and _progression.has_method("get_effect_stacks"):
		return maxi(int(_progression.call("get_effect_stacks", effect_id)), 1)
	if _progression != null and _progression.has_method("get_stack_count"):
		return maxi(int(_progression.call("get_stack_count", effect_id)), 1)
	return 1


# ---------------------- Signal handlers ----------------------

func _on_player_dodged() -> void:
	if not _enabled or _player == null or not is_instance_valid(_player):
		return
	var pos := (_player as Node3D).global_position if _player is Node3D else Vector3.ZERO
	if _has(EFFECT_FIRE_TRAIL):
		_spawn_trail(pos, &"fire", FIRE_TRAIL_DURATION * float(_stacks(EFFECT_FIRE_TRAIL)))
	if _has(EFFECT_FROST_DODGE):
		_apply_frost_nova(pos)


func _on_attack_hit(target: Node, result: DamageResult) -> void:
	_handle_offensive_hit(target, result)


func _on_enemy_damaged(enemy: Node, result: DamageResult) -> void:
	_handle_offensive_hit(enemy, result)


func _handle_offensive_hit(target: Node, result: DamageResult) -> void:
	if not _enabled or result == null or not result.accepted:
		return
	# Guard against re-entry from chain/execute damage we ourselves deal.
	if _handling_hit:
		return
	_handling_hit = true
	if _has(EFFECT_CHAIN_MELEE) and target is Node3D:
		_chain_from(target as Node3D, float(result.final_amount))
	if _has(EFFECT_EXECUTE) and target != null and target.has_method("get_health_fraction"):
		var frac := float(target.call("get_health_fraction"))
		if frac > 0.0 and frac <= EXECUTE_THRESHOLD and target.has_method("apply_damage"):
			var payload := DamagePayload.new()
			payload.amount = 9999.0
			payload.source = _player
			payload.source_id = &"execute"
			payload.damage_type = &"true"
			if payload.is_valid():
				target.call("apply_damage", payload)
	_handling_hit = false


func _on_player_damaged(result: DamageResult) -> void:
	if not _enabled or result == null or not result.accepted:
		return
	if _has(EFFECT_THORN_NOVA) and _player is Node3D:
		_thorn_nova((_player as Node3D).global_position)


func _on_enemy_killed(enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	if not _enabled or _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("is_alive") and not bool(_player.call("is_alive")):
		return
	_kill_counter += 1
	if _has(EFFECT_KILL_SUMMON):
		# Summon every 3rd kill (stack shortens the interval).
		var every := maxi(4 - _stacks(EFFECT_KILL_SUMMON), 2)
		if _kill_counter % every == 0 and enemy is Node3D:
			_spawn_summon((enemy as Node3D).global_position)
	if _has(EFFECT_LIFESTEAL_BURST) and _kill_counter % 5 == 0:
		var hp := _player.get_node_or_null("HealthComponent")
		if hp != null and hp.has_method("heal"):
			hp.call("heal", 12.0 * float(_stacks(EFFECT_LIFESTEAL_BURST)))


# ---------------------- Effect implementations ----------------------

func _chain_from(origin_target: Node3D, base_damage: float) -> void:
	if not is_inside_tree():
		return
	var candidates := get_tree().get_nodes_in_group("enemies")
	var exclude: Array = [origin_target]
	var dmg := base_damage * CHAIN_DAMAGE_RATIO * float(_stacks(EFFECT_CHAIN_MELEE))
	AreaDamage.apply_chain(
		candidates,
		origin_target.global_position,
		CHAIN_RADIUS,
		CHAIN_RADIUS,
		CHAIN_JUMPS,
		dmg,
		0.7,
		_player,
		&"chain_melee",
		&"shock"
	)
	# apply_chain already damages; exclude unused but kept for clarity.
	exclude.clear()


func _spawn_trail(pos: Vector3, kind: StringName, ttl: float) -> void:
	_trails.append({"pos": pos, "ttl": ttl, "kind": kind, "tick": 0.0})


func _tick_trails(delta: float) -> void:
	if _trails.is_empty() or not is_inside_tree():
		return
	var victims := get_tree().get_nodes_in_group("enemies")
	var kept: Array = []
	for t in _trails:
		t["ttl"] = float(t["ttl"]) - delta
		t["tick"] = float(t.get("tick", 0.0)) + delta
		if float(t["ttl"]) <= 0.0:
			continue
		# Damage pulse ~4 Hz so trails feel hot without melting the CPU.
		if float(t["tick"]) >= 0.25:
			t["tick"] = 0.0
			var dmg := FIRE_TRAIL_DAMAGE * float(_stacks(EFFECT_FIRE_TRAIL))
			AreaDamage.apply_radial(
				victims, t["pos"], FIRE_TRAIL_RADIUS, dmg, _player, &"fire_trail",
				2.0, false, AreaDamage.FALLOFF_NONE, [], &"fire"
			)
			_try_burn_near(victims, t["pos"], FIRE_TRAIL_RADIUS)
		kept.append(t)
	_trails = kept


func _try_burn_near(victims: Array, center: Vector3, radius: float) -> void:
	if ContentRegistry == null:
		return
	var burn: StatusEffectConfig = ContentRegistry.get_status_effect(&"burn")
	if burn == null:
		return
	var r2 := radius * radius
	for v in victims:
		if v is Node3D:
			var d: Vector3 = (v as Node3D).global_position - center
			d.y = 0.0
			if d.length_squared() <= r2:
				var sm := (v as Node).get_node_or_null("StatusManager")
				if sm != null and sm.has_method("apply_effect"):
					sm.call("apply_effect", burn, 1, _player)


func _apply_frost_nova(pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var victims := get_tree().get_nodes_in_group("enemies")
	AreaDamage.apply_radial(
		victims, pos, 3.0, 10.0 * float(_stacks(EFFECT_FROST_DODGE)), _player,
		&"frost_dodge", 4.0, false, AreaDamage.FALLOFF_LINEAR, [], &"frost"
	)
	if ContentRegistry == null:
		return
	var slow: StatusEffectConfig = ContentRegistry.get_status_effect(&"slow")
	if slow == null:
		return
	for v in victims:
		if v is Node3D:
			var d: Vector3 = (v as Node3D).global_position - pos
			d.y = 0.0
			if d.length_squared() <= 9.0:
				var sm := (v as Node).get_node_or_null("StatusManager")
				if sm != null and sm.has_method("apply_effect"):
					sm.call("apply_effect", slow, 1, _player)


func _thorn_nova(pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var victims := get_tree().get_nodes_in_group("enemies")
	AreaDamage.apply_radial(
		victims, pos, THORN_RADIUS, THORN_DAMAGE * float(_stacks(EFFECT_THORN_NOVA)),
		_player, &"thorn_nova", 5.0, false, AreaDamage.FALLOFF_LINEAR
	)


func _spawn_summon(at: Vector3) -> void:
	# Lightweight ally: a short-lived radial aura that damages nearby enemies.
	# Visual is a simple glowing disc so we don't need a full AI ally scene.
	if not is_inside_tree() or _player == null:
		return
	var root := Node3D.new()
	root.name = "TempAlly"
	root.position = Vector3(at.x, 0.1, at.z)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.2
	cyl.height = 0.15
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.85, 1.0, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.2
	disc.material_override = mat
	root.add_child(disc)
	# Parent under the world root (player's parent) so it survives player motion.
	var host: Node = _player.get_parent() if _player.get_parent() != null else self
	host.add_child(root)
	_summons.append({
		"node": root,
		"ttl": SUMMON_DURATION * float(_stacks(EFFECT_KILL_SUMMON)),
		"tick": 0.0,
		"pos": root.global_position,
	})


func _tick_summons(delta: float) -> void:
	if _summons.is_empty() or not is_inside_tree():
		return
	var victims := get_tree().get_nodes_in_group("enemies")
	var kept: Array = []
	for s in _summons:
		s["ttl"] = float(s["ttl"]) - delta
		s["tick"] = float(s.get("tick", 0.0)) + delta
		var node: Node = s.get("node")
		if float(s["ttl"]) <= 0.0 or node == null or not is_instance_valid(node):
			if node != null and is_instance_valid(node):
				node.queue_free()
			continue
		if float(s["tick"]) >= 0.5:
			s["tick"] = 0.0
			var pos: Vector3 = (node as Node3D).global_position if node is Node3D else s["pos"]
			AreaDamage.apply_radial(
				victims, pos, 2.5, SUMMON_DAMAGE, _player, &"kill_summon",
				3.0, false, AreaDamage.FALLOFF_LINEAR
			)
		kept.append(s)
	_summons = kept


func _clear_summons() -> void:
	for s in _summons:
		var node: Node = s.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	_summons.clear()


func _tick_static_field(delta: float) -> void:
	# Accumulate and pulse once per second around the player.
	if _player == null or not (_player is Node3D) or not is_inside_tree():
		return
	if not has_meta("_static_acc"):
		set_meta("_static_acc", 0.0)
	var acc := float(get_meta("_static_acc")) + delta
	if acc < 1.0:
		set_meta("_static_acc", acc)
		return
	set_meta("_static_acc", 0.0)
	var victims := get_tree().get_nodes_in_group("enemies")
	AreaDamage.apply_radial(
		victims, (_player as Node3D).global_position, STATIC_FIELD_RADIUS,
		STATIC_FIELD_DAMAGE * float(_stacks(EFFECT_STATIC_FIELD)), _player,
		&"static_field", 1.0, false, AreaDamage.FALLOFF_LINEAR, [], &"shock"
	)


func get_debug_snapshot() -> Dictionary:
	return {
		"trails": _trails.size(),
		"summons": _summons.size(),
		"kills": _kill_counter,
		"effects": _active_effect_ids(),
	}


func _active_effect_ids() -> Array:
	var ids: Array = []
	for e in [
		EFFECT_CHAIN_MELEE, EFFECT_FIRE_TRAIL, EFFECT_KILL_SUMMON, EFFECT_THORN_NOVA,
		EFFECT_FROST_DODGE, EFFECT_EXECUTE, EFFECT_LIFESTEAL_BURST, EFFECT_STATIC_FIELD,
	]:
		if _has(e):
			ids.append(String(e))
	return ids
