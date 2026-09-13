class_name EffectEventHandlers
extends RefCounted

## EventBus -> VFX translation for EffectDirector, extracted so the director owns the
## pool/wiring contract and this module owns "what each event looks like".
##
## Bound once with `bind(host)` (the EnemyPack idiom): the module keeps the typed
## director reference and every handler keeps the signal's own arity, so the wiring
## can hand EventBus these callables directly. Priorities come from EffectPriorities
## and status ink from the director, so this file never reads EffectDirector's
## constants (that would close a compile-time constants cycle).
##
## `boss_slain` carries no position (the body is already gone), so this module also
## remembers the last spawned boss origin and replays the slain tell there instead of
## at world zero (which is often outside the pit).
##
## The skill-cast handler deliberately stays on the director: it paints pooled ring and
## burst materials directly, so it needs the pool, not just the public burst/ring API.

## Last boss spawn origin, replayed by boss_slain so the death tell lands in the pit.
var _last_boss_at := Vector3.ZERO
var _has_boss_at := false
var _host: EffectDirector = null


func bind(host: EffectDirector) -> void:
	_host = host


## Connect every translated signal. `host` is the node EventBus auto-unbinds on
## tree_exiting; `bind` (is_connected-guarded) makes repeated wiring a no-op.
func connect_all(bus: EventBusService, host: Node) -> void:
	if bus == null:
		return
	bus.bind(host, bus.enemy_spawned, on_enemy_spawned)
	bus.bind(host, bus.enemy_killed, on_enemy_killed)
	bus.bind(host, bus.enemy_damaged, on_enemy_damaged)
	bus.bind(host, bus.wave_started, on_wave_started)
	bus.bind(host, bus.wave_completed, on_wave_completed)
	bus.bind(host, bus.pickup_collected, on_pickup_collected)
	bus.bind(host, bus.pickup_spawned, on_pickup_spawned)
	bus.bind(host, bus.status_applied, on_status_applied)
	bus.bind(host, bus.boss_spawned, on_boss_spawned)
	bus.bind(host, bus.boss_slain, on_boss_slain)
	bus.bind(host, bus.projectile_fired, on_projectile_fired)
	bus.bind(host, bus.player_leveled_up, on_player_leveled_up)
	bus.bind(host, bus.weapon_equipped, on_weapon_equipped)


func disconnect_all(bus: EventBusService) -> void:
	if bus == null:
		return
	bus.unbind(bus.enemy_spawned, on_enemy_spawned)
	bus.unbind(bus.enemy_killed, on_enemy_killed)
	bus.unbind(bus.enemy_damaged, on_enemy_damaged)
	bus.unbind(bus.wave_started, on_wave_started)
	bus.unbind(bus.wave_completed, on_wave_completed)
	bus.unbind(bus.pickup_collected, on_pickup_collected)
	bus.unbind(bus.pickup_spawned, on_pickup_spawned)
	bus.unbind(bus.status_applied, on_status_applied)
	bus.unbind(bus.boss_spawned, on_boss_spawned)
	bus.unbind(bus.boss_slain, on_boss_slain)
	bus.unbind(bus.projectile_fired, on_projectile_fired)
	bus.unbind(bus.player_leveled_up, on_player_leveled_up)
	bus.unbind(bus.weapon_equipped, on_weapon_equipped)


func on_boss_spawned(boss: Node, _boss_id: StringName) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(boss) and boss is Node3D:
		at = (boss as Node3D).global_position
	_last_boss_at = at
	_has_boss_at = true
	# Inner danger disc + outer contrast ring so the telegraph reads on sand arenas
	# and under high-contrast / reduced-motion settings.
	_host.ring_at(at, Color(1.0, 0.95, 0.15), 6.4, EffectPriorities.BOSS)
	_host.ring_at(at, Color(0.95, 0.08, 0.08), 4.4, EffectPriorities.BOSS)
	if not EffectReadability.reduced_motion():
		_host.burst_at(at + Vector3(0, 0.6, 0), Color(1.0, 0.32, 0.18), 2.0, EffectPriorities.BOSS)


func on_boss_slain(_boss_id: StringName) -> void:
	var at := _last_boss_at if _has_boss_at else EffectPlacement.arena_origin(_host)
	_has_boss_at = false
	_host.ring_at(at, Color(1.0, 0.85, 0.32), 9.5, EffectPriorities.BOSS)
	_host.burst_at(at + Vector3(0, 0.5, 0), Color(1.0, 0.88, 0.4), 2.2, EffectPriorities.BOSS)


func on_enemy_spawned(enemy: Node, _archetype: StringName) -> void:
	if is_instance_valid(enemy) and enemy is Node3D:
		_host.ring_at((enemy as Node3D).global_position, Color(0.9, 0.55, 0.3), 1.25, EffectPriorities.SPAWN)


func on_enemy_killed(enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	if is_instance_valid(enemy) and enemy is Node3D:
		var at := (enemy as Node3D).global_position + Vector3(0, 0.35, 0)
		_host.burst_at(at, Color(0.95, 0.55, 0.25), 1.15, EffectPriorities.ENEMY_DEATH)
		_host.ring_at((enemy as Node3D).global_position, Color(1.0, 0.62, 0.35), 1.85, EffectPriorities.ENEMY_DEATH)


func on_enemy_damaged(enemy: Node, result: DamageResult) -> void:
	if not is_instance_valid(enemy) or not enemy is Node3D or result == null or not result.accepted:
		return
	var at := (enemy as Node3D).global_position + Vector3(0, 1.1, 0)
	if result.was_critical:
		# Gold crit: larger, brighter, with shock ring for readability — CRITICAL so it never drops.
		_host.burst_at(at, Color(1.0, 0.88, 0.22), 0.82, EffectPriorities.CRITICAL)
		_host.ring_at((enemy as Node3D).global_position, Color(1.0, 0.92, 0.45), 1.05, EffectPriorities.CRITICAL)
	else:
		_host.burst_at(at, Color(0.9, 0.72, 0.55), 0.42, EffectPriorities.ENEMY_HIT)


func on_wave_started(_wave_number: int, _planned: int) -> void:
	var origin := EffectPlacement.arena_origin(_host)
	_host.ring_at(origin, Color(0.85, 0.45, 0.22), 6.5, EffectPriorities.SPAWN)
	_host.burst_at(origin + Vector3(0, 0.2, 0), Color(1.0, 0.65, 0.3), 1.2, EffectPriorities.SPAWN)


func on_wave_completed(_wave_number: int, _bonus: int) -> void:
	var origin := EffectPlacement.arena_origin(_host)
	_host.ring_at(origin, Color(1.0, 0.88, 0.38), 8.0, EffectPriorities.SPAWN)
	_host.burst_at(origin + Vector3(0, 0.4, 0), Color(1.0, 0.92, 0.5), 1.45, EffectPriorities.SPAWN)


func on_pickup_collected(_pickup_id: StringName, _amount: int, collector: Node) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(collector) and collector is Node3D:
		at = (collector as Node3D).global_position
	_host.ring_at(at, Color(1.0, 0.88, 0.38), 1.0, EffectPriorities.PICKUP)
	_host.burst_at(at + Vector3(0, 0.6, 0), Color(1.0, 0.92, 0.55), 0.55, EffectPriorities.PICKUP)


func on_pickup_spawned(pickup: Node, _pickup_id: StringName) -> void:
	if not is_instance_valid(pickup) or not pickup is Node3D:
		return
	_host.ring_at((pickup as Node3D).global_position, Color(0.45, 0.85, 1.0), 0.7, EffectPriorities.PICKUP)


func on_status_applied(target: Node, effect_id: StringName, _stacks: int) -> void:
	if not is_instance_valid(target) or not target is Node3D:
		return
	var color := _host.status_color(effect_id)
	var at := (target as Node3D).global_position
	_host.ring_at(at, color, 0.85, EffectPriorities.STATUS)
	at += Vector3(0, 1.6, 0)
	if effect_id == &"burn" or effect_id == &"shock" or effect_id == &"poison" or effect_id == &"bleed":
		_host.burst_at(at, color, 0.5, EffectPriorities.STATUS)


func on_projectile_fired(shooter: Node, _weapon_id: StringName) -> void:
	if not is_instance_valid(shooter) or not shooter is Node3D:
		return
	var at := (shooter as Node3D).global_position + Vector3(0, 1.0, 0)
	_host.burst_at(at, Color(1.0, 0.82, 0.45), 0.48, EffectPriorities.HIT)


func on_player_leveled_up(_new_level: int, _xp: int) -> void:
	# Celebratory burst — called from player; the position comes from the player group.
	var at := _player_position()
	_host.ring_at(at, Color(1.0, 0.88, 0.32), 2.2, EffectPriorities.PLAYER)
	_host.burst_at(at + Vector3(0, 1.2, 0), Color(1.0, 0.95, 0.55), 1.6, EffectPriorities.PLAYER)
	_host.burst_at(at + Vector3(0, 0.4, 0), Color(0.45, 0.85, 1.0), 1.1, EffectPriorities.PLAYER)


func on_weapon_equipped(_weapon_id: StringName, _slot: int) -> void:
	# Brief equip flash at the player, rising from chest height.
	var at := Vector3.ZERO
	var players := _players()
	if players.size() > 0:
		at = (players[0] as Node3D).global_position + Vector3(0, 1.0, 0)
	_host.burst_at(at, Color(0.72, 0.82, 1.0), 0.62, EffectPriorities.PLAYER)


## Valid player-group bodies (there is normally exactly one), so the two player-tell
## handlers share one lookup and stay no-ops outside a live run.
func _players() -> Array:
	var tree := _host.get_tree() if _host != null else null
	if tree == null:
		return []
	var out: Array = []
	for p in tree.get_nodes_in_group(&"player"):
		if is_instance_valid(p) and p is Node3D:
			out.append(p)
	return out


func _player_position() -> Vector3:
	var players := _players()
	return (players[0] as Node3D).global_position if players.size() > 0 else Vector3.ZERO
