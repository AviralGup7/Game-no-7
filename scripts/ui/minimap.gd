class_name Minimap
extends Control

## Circular arena minimap: player wedge, enemy dots (red, gold for elites, big
## purple for the boss), pickup pips and hazard rings, all projected from world
## XZ into a small radar. Updates at 15 Hz (not every frame) to stay cheap on
## mobile GPUs. Pure projection math is static so tests can pin it.

const UPDATE_INTERVAL := 1.0 / 15.0
const DOT_RADIUS := 2.5
const ELITE_RADIUS := 3.5
const BOSS_RADIUS := 5.0
const PLAYER_COLOR := Color(0.4, 1.0, 0.5)
const ENEMY_COLOR := Color(1.0, 0.3, 0.25)
const ELITE_COLOR := Color(1.0, 0.8, 0.2)
const BOSS_COLOR := Color(0.8, 0.3, 1.0)
const PICKUP_COLOR := Color(0.5, 0.85, 1.0)

var arena_half := 12.0
var _accum := 0.0
var _player: Node3D = null
var _enemies: Array = []
var _pickups: Array = []
var _north_up := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(140, 140)


## World XZ -> minimap local point. `radius_px` is the radar radius; positions
## outside the arena clamp to the rim.
static func project_to_map(world_xz: Vector2, center_px: Vector2, radius_px: float, half: float) -> Vector2:
	var half_safe := maxf(half, 0.01)
	var norm := world_xz / half_safe
	if norm.length() > 1.0:
		norm = norm.normalized()
	return center_px + norm * radius_px


func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_accum += delta
	if _accum < UPDATE_INTERVAL:
		return
	_accum = 0.0
	_refresh_targets()
	queue_redraw()


func _refresh_targets() -> void:
	if not is_inside_tree():
		return
	var world_arena := get_tree().current_scene.get_node_or_null("WorldRoot/Arena") as Arena if get_tree().current_scene != null else null
	if world_arena != null:
		arena_half = world_arena.get_interior_half()
	var players := get_tree().get_nodes_in_group("player")
	_player = players[0] as Node3D if not players.is_empty() else null
	_enemies = get_tree().get_nodes_in_group("enemies")
	_pickups = get_tree().get_nodes_in_group(Pickup.PICKUP_GROUP)


func _draw() -> void:
	var center := size * 0.5
	var radius := maxf(minf(size.x, size.y) * 0.5 - 4.0, 8.0)
	# Frame: dark disc + rim.
	draw_circle(center, radius + 2.0, Color(0.05, 0.06, 0.08, 0.75))
	draw_arc(center, radius + 2.0, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
	# Range rings.
	draw_arc(center, radius * 0.5, 0, TAU, 32, Color(1, 1, 1, 0.08), 1.0)
	for p in _pickups:
		var pickup := p as Pickup
		if pickup != null and pickup.is_active():
			_dot(center, radius, pickup.global_position, PICKUP_COLOR, DOT_RADIUS * 0.7)
	for e in _enemies:
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var enemy := e as Damageable
		if enemy != null and not enemy.is_alive():
			continue
		var color := ENEMY_COLOR
		var r := DOT_RADIUS
		if (e as Node).is_in_group("boss"):
			color = BOSS_COLOR
			r = BOSS_RADIUS
		elif enemy is EnemyBase and (enemy as EnemyBase).is_elite():
			color = ELITE_COLOR
			r = ELITE_RADIUS
		_dot(center, radius, (e as Node3D).global_position, color, r)
	if _player != null and is_instance_valid(_player):
		var pp := project_to_map(Vector2(_player.global_position.x, _player.global_position.z), center, radius, arena_half)
		var facing := Vector2(-_player.global_transform.basis.z.x, -_player.global_transform.basis.z.z)
		if facing.length_squared() < 0.01:
			facing = Vector2.UP
		facing = facing.normalized()
		var side := Vector2(-facing.y, facing.x)
		draw_colored_polygon([pp + facing * 6.0, pp - facing * 4.0 + side * 4.0, pp - facing * 4.0 - side * 4.0], PLAYER_COLOR)


func _dot(center: Vector2, radius: float, world_pos: Vector3, color: Color, r: float) -> void:
	draw_circle(project_to_map(Vector2(world_pos.x, world_pos.z), center, radius, arena_half), r, color)

