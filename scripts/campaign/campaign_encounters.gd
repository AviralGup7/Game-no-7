class_name CampaignEncounters
extends Node
## Finite authored populations, not waves. Streaming is NOT a defeat: leaving
## and returning restores only living spawn IDs, with no additional rewards.

signal member_defeated(spawn_id: String, credits: int)
const COMMANDER_SCENE := preload("res://scenes/campaign/security_commander.tscn")
const TICK := 0.3
const DESPAWN_DISTANCE := 90.0
const SPAWN_DISTANCE := 70.0
const SPAWNS_PER_TICK := 2
var _definition: CampaignDefinition
var _world: CampaignWorld
var _player: Player
var _progress: Dictionary
var _actors: Node3D
var _active: Dictionary = {}  # authored member id -> EnemyBase
var _enabled := true
var _clock := 0.0
var _flow_cell := Vector2i(-2147483648, -2147483648)


func configure(world: CampaignWorld, player: Player, progress: Dictionary) -> void:
	_world = world
	_definition = world.definition
	_player = player
	_progress = progress
	_actors = Node3D.new()
	_actors.name = "ActiveEncounterActors"
	add_child(_actors)
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _process(delta: float) -> void:
	if not _enabled or not is_instance_valid(_player) or GameRoot.get_current_state() != GameRoot.State.PLAYING:
		return
	_clock += delta
	if _clock < TICK:
		return
	_clock = 0.0
	stream_nearby()


func stream_nearby() -> void:
	if not _enabled or not is_instance_valid(_player):
		return
	var at := _player.global_position
	for id in _active.keys():
		var actor := _active[id] as EnemyBase
		if not is_instance_valid(actor):
			_active.erase(id)
		elif actor.global_position.distance_to(at) > DESPAWN_DISTANCE:
			# No despawn_requested or enemy_killed emission on this path.
			actor.set_ai_enabled(false)
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			actor.queue_free()
			_active.erase(id)
	var player_cell := _world.nav.to_cell(at)
	if not _active.is_empty() and player_cell != _flow_cell:
		_world.nav.rebuild_flow_field(at)
		_flow_cell = player_cell
	var spawned := 0
	for group in _definition.encounters:
		var center_data: Array = group.get("center", [])
		var center := Vector3(float(center_data[0]), 0.2, float(center_data[1]))
		if center.distance_to(at) > float(group.activate_radius):
			continue
		for member in group.members:
			if _active.size() >= _definition.max_active_enemies or spawned >= SPAWNS_PER_TICK:
				return
			var id := String(member.id)
			if id in _progress.defeated or _active.has(id):
				continue
			var distance := CampaignDefinition.point(member.at).distance_to(at)
			if distance > SPAWN_DISTANCE:
				continue
			if _spawn(member):
				spawned += 1


func _spawn(member: Dictionary) -> bool:
	if _active.size() >= _definition.max_active_enemies or _active.has(String(member.id)) or String(member.id) in _progress.defeated:
		return false
	var config := ContentRegistry.get_enemy(StringName(String(member.type)))
	if config == null or config.scene == null:
		EventBus.report_error("Campaign enemy resource is missing: %s" % String(member.type))
		return false
	var scene := COMMANDER_SCENE if String(member.type) == "warlord" else config.scene
	var root := scene.instantiate()
	if not root is EnemyBase:
		root.free()
		EventBus.report_error("Campaign encounter scene is not an EnemyBase")
		return false
	var actor := root as EnemyBase
	actor.name = String(member.id)
	_actors.add_child(actor)
	actor.global_position = _safe_spawn_position(CampaignDefinition.point(member.at))
	actor.reset_physics_interpolation()
	actor.set_bounds(176.0)
	actor.initialize(config, _player, 0)
	actor.set_spawn_serial(_definition.spawn_ids().find(String(member.id)))
	actor.set_nav_grid(_world.nav)
	_active[String(member.id)] = actor
	_world.nav.rebuild_flow_field(_player.global_position)
	EventBus.enemy_spawned.emit(actor, config.archetype_id)
	var boss := actor.get_boss_controller()
	if boss != null:
		# The inherited commander scene authors three finite phases, no summons.
		boss.begin_fight(0, "command deck")
	return true


func _safe_spawn_position(authored: Vector3) -> Vector3:
	if authored.distance_to(_player.global_position) >= 8.0 and _world.nav.is_walkable(authored):
		return authored
	for radius in [8.0, 12.0, 16.0]:
		for step in range(8):
			var angle := TAU * float(step) / 8.0
			var candidate := authored + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			if candidate.distance_to(_player.global_position) >= 8.0 and _world.nav.is_walkable(candidate):
				return candidate
	return authored


func _on_enemy_killed(enemy: Node, _type: StringName, _score: int, credits: int) -> void:
	if not _enabled or enemy == null:
		return
	for raw_id in _active.keys():
		if _active[raw_id] != enemy:
			continue
		var id := String(raw_id)
		_active.erase(id)
		if id not in _progress.defeated:
			_progress.defeated.append(id)
			member_defeated.emit(id, credits)
		return


func member_position(member: Dictionary) -> Vector3:
	var actor := _active.get(String(member.id)) as EnemyBase
	if is_instance_valid(actor) and actor.is_alive():
		return actor.global_position
	return CampaignDefinition.point(member.at)


func remaining(encounter_id: String) -> int:
	var group := _definition.encounter(encounter_id)
	var count := 0
	for member in group.get("members", []):
		if String(member.id) not in _progress.defeated:
			count += 1
	return count


func safe_to_rest(at: Vector3) -> bool:
	for value in _active.values():
		var actor := value as EnemyBase
		if is_instance_valid(actor) and actor.is_alive() and actor.global_position.distance_to(at) < 24.0:
			return false
	# A dormant guard close to a rest pad is still a threat (prevents skipping
	# the safety check in the few frames before the next streaming tick).
	for group in _definition.encounters:
		for member in group.members:
			if String(member.id) not in _progress.defeated and CampaignDefinition.point(member.at).distance_to(at) < 20.0:
				return false
	return true


func stop() -> void:
	_enabled = false
	for value in _active.values():
		var actor := value as EnemyBase
		if is_instance_valid(actor):
			actor.set_ai_enabled(false)
			actor.process_mode = Node.PROCESS_MODE_DISABLED  # Includes boss telegraphs.


func get_debug_snapshot() -> Dictionary:
	return {"active": _active.size(), "cap": _definition.max_active_enemies,
		"defeated": _progress.defeated.duplicate(), "enabled": _enabled}
