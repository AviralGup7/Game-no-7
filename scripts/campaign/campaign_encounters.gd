class_name CampaignEncounters
extends Node
## Finite authored populations, not waves. Streaming is NOT a defeat: leaving
## and returning restores only living spawn IDs, with no additional rewards.

signal member_defeated(spawn_id: String, credits: int)
const COMMANDER_SCENE := preload("res://scenes/campaign/security_commander.tscn")
const TICK := CampaignBudgets.STREAM_TICK_SECONDS
const DESPAWN_DISTANCE := CampaignBudgets.DESPAWN_DISTANCE
const SPAWN_DISTANCE := CampaignBudgets.SPAWN_DISTANCE
const SPAWNS_PER_TICK := CampaignBudgets.SPAWNS_PER_TICK
## Distance a required guard must clear before it is placed at its authored spot:
## an actor popping in on top of the hero is a pop-in and an unavoidable ambush.
## `CLEARANCE_RINGS` are the alternate offsets probed when the authored point is
## too close or unwalkable, and `RING_SAMPLES` is how many evenly spaced angles
## each ring tries. The final `return authored` is the proven fallback: a guard
## with no clear ring point spawns at its authored position anyway. These are
## spawn-legality rules, not the CampaignBudgets flow numbers.
const PLAYER_CLEARANCE := 8.0
const CLEARANCE_RINGS: Array = [8.0, 12.0, 16.0]
const RING_SAMPLES := 8
## Flow-field window for combat on the expanded station: it comfortably covers
## every actor that can be live (spawn 70 m / despawn 90 m) while keeping each
## rebuild proportional to the crowd instead of to the whole 864 x 672 m deck.
const FLOW_RADIUS := CampaignBudgets.FLOW_FIELD_RADIUS
var _definition: CampaignDefinition
var _world: CampaignWorld
var _player: Player
var _defeated: Array[String] = []
var _actors: Node3D
var _active: Dictionary = {}  # authored member id -> EnemyBase
var _enabled := true
var _clock := 0.0
var _flow_cell := Vector2i(-2147483648, -2147483648)
var _flow_revision := -1


func configure(world: CampaignWorld, player: Player, defeated: Array[String]) -> void:
	_world = world
	_definition = world.definition
	_player = player
	_defeated = defeated.duplicate()
	_actors = Node3D.new()
	_actors.name = "ActiveEncounterActors"
	add_child(_actors)
	# bind(), not connect(): this node is created and freed with every world
	# build, and the bus outlives it. EventBus.bind disconnects on tree exit, so
	# the ownership contract is explicit instead of relying on Godot dropping
	# connections when the target is freed.
	EventBus.bind(self, EventBus.enemy_killed, _on_enemy_killed)


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
	var nav_revision := _world.nav.get_revision()
	if not _active.is_empty() and (player_cell != _flow_cell or nav_revision != _flow_revision):
		_world.nav.rebuild_flow_field(at, FLOW_RADIUS)
		_flow_cell = player_cell
		_flow_revision = nav_revision
	var spawned := 0
	for group in _definition.encounters:
		var center := Vector3(group.center.x, 0.2, group.center.y)
		if center.distance_to(at) > float(group.activate_radius):
			continue
		for member in group.members:
			if _active.size() >= _definition.max_active_enemies or spawned >= SPAWNS_PER_TICK:
				return
			var id := String(member.id)
			if id in _defeated or _active.has(id):
				continue
			var distance := member.at.distance_to(at)
			if distance > SPAWN_DISTANCE:
				continue
			if _spawn(member):
				spawned += 1


func _spawn(member: CampaignMember) -> bool:
	if _active.size() >= _definition.max_active_enemies or _active.has(String(member.id)) or String(member.id) in _defeated:
		return false
	var config := ContentRegistry.get_enemy(StringName(String(member.type)))
	if config == null or config.scene == null:
		EventBus.report_error("Campaign enemy resource is missing: %s" % String(member.type))
		return false
	var scene := COMMANDER_SCENE if String(member.type) == CampaignContract.ENCOUNTER_COMMANDER else config.scene
	var root := scene.instantiate()
	if not root is EnemyBase:
		root.free()
		EventBus.report_error("Campaign encounter scene is not an EnemyBase")
		return false
	var actor := root as EnemyBase
	actor.name = String(member.id)
	_actors.add_child(actor)
	actor.global_position = _safe_spawn_position(member.at)
	actor.reset_physics_interpolation()
	actor.set_bounds(_definition.containment_half())
	actor.initialize(config, _player, 0)
	actor.set_spawn_serial(_definition.spawn_ids().find(String(member.id)))
	actor.set_nav_grid(_world.nav)
	_active[String(member.id)] = actor
	_world.nav.rebuild_flow_field(_player.global_position, FLOW_RADIUS)
	EventBus.enemy_spawned.emit(actor, config.archetype_id)
	var boss := actor.get_boss_controller()
	if boss != null:
		# The inherited commander scene authors three finite phases, no summons.
		boss.begin_fight(0, "command deck")
	return true


func _safe_spawn_position(authored: Vector3) -> Vector3:
	if authored.distance_to(_player.global_position) >= PLAYER_CLEARANCE and _world.nav.is_walkable(authored):
		return authored
	for radius in CLEARANCE_RINGS:
		for step in range(RING_SAMPLES):
			var angle := TAU * float(step) / float(RING_SAMPLES)
			var candidate := authored + Vector3(cos(angle) * float(radius), 0.0, sin(angle) * float(radius))
			if candidate.distance_to(_player.global_position) >= PLAYER_CLEARANCE and _world.nav.is_walkable(candidate):
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
		if id not in _defeated:
			_defeated.append(id)
			member_defeated.emit(id, credits)
		return


func member_position(member: CampaignMember) -> Vector3:
	var actor := _active.get(String(member.id)) as EnemyBase
	if is_instance_valid(actor) and actor.is_alive():
		return actor.global_position
	return member.at


func remaining(encounter_id: String) -> int:
	var group := _definition.encounter(encounter_id)
	var count := 0
	for member in group.members:
		if String(member.id) not in _defeated:
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
			if String(member.id) not in _defeated and member.at.distance_to(at) < 20.0:
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
		"defeated": _defeated.duplicate(), "enabled": _enabled}
