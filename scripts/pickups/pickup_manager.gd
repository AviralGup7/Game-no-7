class_name PickupManager
extends Node

## Scene-tree owner of all live pickups: pooled Pickup nodes, kill-drop wiring
## (via EventBus.enemy_killed + DropTable), collection-effect application, and
## magnet-burst support. Budgets the live count so pathological drop chains
## recycle the oldest pickup instead of flooding the arena.

signal drops_spawned(pickup_ids: Array[StringName], at: Vector3)

const MANAGER_GROUP := "pickup_manager"
const DEFAULT_POOL_SIZE := 32

@export var pool_size: int = DEFAULT_POOL_SIZE
@export var max_live_pickups: int = 24

var _idle: Array[Pickup] = []
var _live: Array[Pickup] = []
var _drop_table := DropTable.new()
var _rng := RngService.new()
var _luck_bonus := 0.0


func _ready() -> void:
	if pool_size < 1:
		pool_size = DEFAULT_POOL_SIZE
	pool_size = clampi(pool_size, 1, 64)
	max_live_pickups = clampi(max_live_pickups, 1, 48)
	add_to_group(MANAGER_GROUP)
	for i in range(maxi(pool_size, 1)):
		_idle.append(_make_pickup())
	_refresh_drop_table()
	if EventBus != null and not EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.connect(_on_enemy_killed)


func configure(run_seed: int, luck_bonus: float = 0.0) -> void:
	_rng.reseed(run_seed)
	_luck_bonus = maxf(luck_bonus, 0.0)
	_drop_table.reset_pity()


func _refresh_drop_table() -> void:
	_drop_table.configure(ContentRegistry.get_all_pickup_configs() if ContentRegistry != null else [])


func _make_pickup() -> Pickup:
	var p := Pickup.new()
	p.collision_layer = 0
	p.collision_mask = 0
	var visual := Node3D.new()
	visual.name = "Visual"
	p.add_child(visual)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var gem := PrismMesh.new()
	gem.size = Vector3(0.4, 0.6, 0.4)
	mesh.mesh = gem
	mesh.position.y = 0.35
	visual.add_child(mesh)
	add_child(p)  # _ready must see Visual/Mesh before caching node references.
	p.pool_reset()
	if not p.release_requested.is_connected(_on_release_requested):
		p.release_requested.connect(_on_release_requested)
	if not p.collected.is_connected(_on_collected):
		p.collected.connect(_on_collected)
	return p


func _obtain() -> Pickup:
	if not _idle.is_empty():
		return _idle.pop_back()
	# Recycle the oldest live pickup (deterministic degradation).
	if not _live.is_empty():
		var oldest: Pickup = _live.pop_front()
		oldest.pool_reset()
		return oldest
	var extra := _make_pickup()
	_idle.append(extra)
	return _idle.pop_back()


## Spawn one pickup by id near `at` (small deterministic scatter). Returns the
## Pickup or null when the id is unknown.
func spawn_pickup(pickup_id: StringName, at: Vector3, level: int = 1) -> Pickup:
	var cfg := _config_of(pickup_id)
	if cfg == null:
		return null
	while _live.size() >= max_live_pickups and not _live.is_empty():
		var oldest: Pickup = _live.pop_front()
		oldest.pool_reset()
		_idle.append(oldest)
	var scatter := _rng.point_in_disc(RngService.STREAM_DROPS, 0.8)
	var p := _obtain()
	p.drop(cfg, at + scatter, _player(), level)
	_live.append(p)
	if EventBus != null:
		EventBus.pickup_spawned.emit(p, pickup_id)
	if AudioManager != null:
		AudioManager.play_sfx(&"item_drop", -10.0)
	return p


func _config_of(pickup_id: StringName) -> PickupConfig:
	if ContentRegistry == null:
		return null
	return ContentRegistry.get_pickup(pickup_id)


func _player() -> Node3D:
	if GameRoot != null:
		var pl: Variant = GameRoot.get_active_player()
		if pl is Node3D:
			return pl
	if is_inside_tree():
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			return players[0] as Node3D
	return null


func _on_enemy_killed(enemy: Node, archetype_id: StringName, _score: int, _currency: int) -> void:
	var wave := 1
	if GameRoot != null and GameRoot.has_method("get_run"):
		var run: Variant = GameRoot.call("get_run")
		if run != null:
			if run is Dictionary:
				wave = maxi(int((run as Dictionary).get("current_wave", 1)), 1)
			elif "current_wave" in run:
				wave = maxi(int((run as Variant).current_wave), 1)
	var is_elite := enemy != null and enemy.has_method("is_elite") and bool(enemy.call("is_elite"))
	var is_boss := enemy != null and enemy.is_in_group("boss")
	var ids := _drop_table.roll_drops(archetype_id, wave, is_elite, is_boss, _luck_bonus, _rng)
	if ids.is_empty():
		return
	var at := Vector3.ZERO
	if enemy is Node3D:
		at = (enemy as Node3D).global_position
	for id in ids:
		spawn_pickup(id, at)
	drops_spawned.emit(ids, at)


## Wave-clear bonus: sprinkle `count` pickups around the arena centre-ish.
func spawn_wave_clear_bonus(count: int, around: Vector3, wave_number: int) -> Array[Pickup]:
	var out: Array[Pickup] = []
	for id in _drop_table.roll_bonus_drops(count, wave_number, _rng):
		var p := spawn_pickup(id, around + _rng.point_in_disc(RngService.STREAM_DROPS, 4.0))
		if p != null:
			out.append(p)
	return out


## Magnet burst: teleport every live pickup into collection range of the player.
func magnet_burst() -> int:
	var player := _player()
	if player == null:
		return 0
	var moved := 0
	for p in _live:
		if p.config != null:
			p.global_position = player.global_position + _rng.point_in_disc(RngService.STREAM_DROPS, p.config.collect_radius * 0.5)
			moved += 1
	return moved


func _on_collected(pickup: Pickup, collector: Node) -> void:
	if pickup.config != null:
		_apply_effect(pickup.config, pickup.level, collector)


func _apply_effect(cfg: PickupConfig, level: int, collector: Node) -> void:
	if AudioManager != null:
		AudioManager.play_sfx(&"pickup")
	var amount := cfg.scaled_amount(level)
	match cfg.effect:
		PickupConfig.EFFECT_HEAL:
			var hp := (collector as Node).get_node_or_null("HealthComponent") if collector is Node else null
			if hp != null and hp.has_method("heal"):
				hp.call("heal", amount)
		PickupConfig.EFFECT_CURRENCY:
			if GameRoot != null and GameRoot.has_method("get_run"):
				var run_c: Variant = GameRoot.call("get_run")
				if run_c != null:
					if run_c is Dictionary:
						(run_c as Dictionary)["currency"] = maxi(int((run_c as Dictionary).get("currency", 0)) + int(round(amount)), 0)
						if EventBus != null:
							EventBus.currency_changed.emit(int((run_c as Dictionary).get("currency", 0)), int(round(amount)))
					elif run_c is Object and (run_c as Object).has_method("add_currency"):
						run_c.call("add_currency", int(round(amount)))
						if EventBus != null and "currency" in run_c:
							EventBus.currency_changed.emit(int((run_c as Object).get("currency")), int(round(amount)))
		PickupConfig.EFFECT_SCORE:
			if GameRoot != null and GameRoot.has_method("get_run"):
				var run_s: Variant = GameRoot.call("get_run")
				if run_s != null:
					if run_s is Dictionary:
						(run_s as Dictionary)["score"] = maxi(int((run_s as Dictionary).get("score", 0)) + int(round(amount)), 0)
						if EventBus != null:
							EventBus.score_changed.emit(int((run_s as Dictionary).get("score", 0)), int(round(amount)))
					elif run_s is Object and (run_s as Object).has_method("add_score"):
						run_s.call("add_score", int(round(amount)))
						if EventBus != null and "score" in run_s:
							EventBus.score_changed.emit(int((run_s as Object).get("score")), int(round(amount)))
		PickupConfig.EFFECT_STAMINA:
			if collector != null and collector.has_method("restore_stamina"):
				collector.call("restore_stamina", amount)
		PickupConfig.EFFECT_XP:
			if collector != null and collector.has_method("add_xp"):
				collector.call("add_xp", amount)
		PickupConfig.EFFECT_SHIELD:
			var sm := (collector as Node).get_node_or_null("StatusManager") if collector is Node else null
			if sm == null and ContentRegistry != null:
				pass  # shield without a StatusManager is a no-op (tolerant)
			elif sm != null and sm.has_method("apply_effects") and ContentRegistry != null:
				var shield_cfg: StatusEffectConfig = ContentRegistry.get_status_effect(&"guard")
				if shield_cfg != null and sm.has_method("apply_effect"):
					sm.call("apply_effect", shield_cfg, 1, collector)
		PickupConfig.EFFECT_MAGNET:
			magnet_burst()
		PickupConfig.EFFECT_CLEANSE:
			var sm2 := (collector as Node).get_node_or_null("StatusManager") if collector is Node else null
			if sm2 != null and sm2.has_method("cleanse_all"):
				sm2.call("cleanse_all", true)


func _on_release_requested(p: Pickup) -> void:
	_live.erase(p)
	p.pool_reset()
	_idle.append(p)


func purge_all() -> void:
	for p in _live.duplicate():
		_on_release_requested(p)


func live_count() -> int:
	return _live.size()


func get_debug_snapshot() -> Dictionary:
	return {"live": _live.size(), "idle": _idle.size(), "dry_streak": _drop_table.dry_streak()}

## Hardened: clamp drop position to arena bounds.
func _validated_drop_pos(pos: Vector3, half: float) -> Vector3:
	if not is_finite(pos.x) or not is_finite(pos.z):
		return Vector3.ZERO
	half = clampf(half, 4.0, 100.0)
	return Vector3(clampf(pos.x, -half, half), pos.y, clampf(pos.z, -half, half))

