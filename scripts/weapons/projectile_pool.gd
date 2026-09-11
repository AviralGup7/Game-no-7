class_name ProjectilePool
extends Node

## Scene-tree pool of Projectile nodes shared by player weapons and enemy
## shooters. Pre-spawns a fixed budget at _ready (no mid-fight allocation),
## hands out projectiles via `fire()`, and reclaims them on `release_requested`.
## When exhausted it recycles the oldest active projectile rather than failing,
## so heavy volleys degrade gracefully instead of dropping shots silently.

signal pool_exhausted_recycled()

## Detection sphere used when a projectile scene has no authored shape, and the
## default the Projectile sweep starts from (see Projectile.sweep_radius).
const SWEEP_RADIUS := 0.25

@export var pool_size: int = 48
@export var projectile_scene: PackedScene = null

var _idle: Array[Projectile] = []
var _active: Array[Projectile] = []
var _fallback_mesh: SphereMesh = null
## Live-in-air cap from the performance governor. -1 means "pool_size".
## Fire never lets `_active` grow past this even when idle leftover remains.
var _live_cap: int = -1
## GAME_OVER freeze: fire() returns null until a new pool is built.
var _isolated := false


func _ready() -> void:
	add_to_group("projectile_pool")
	Projectile.ensure_shared_tints()
	_fallback_mesh = SphereMesh.new()
	_fallback_mesh.radius = 0.18
	_fallback_mesh.height = 0.36
	for i in range(maxi(pool_size, 1)):
		var p := _make_projectile()
		_idle.append(p)


func _make_projectile() -> Projectile:
	var p: Projectile = null
	if projectile_scene != null:
		var inst: Node = projectile_scene.instantiate()
		if inst is Projectile:
			p = inst as Projectile
		elif inst != null:
			# Rejected scene roots are not reference counted or owned by the tree.
			inst.free()
	if p == null:
		p = _make_fallback_projectile()
	add_child(p)
	p.pool_reset()
	if not p.release_requested.is_connected(_on_release_requested):
		p.release_requested.connect(_on_release_requested)
	var shape := p.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		if shape.shape == null:
			var sphere := SphereShape3D.new()
			sphere.radius = SWEEP_RADIUS
			shape.shape = sphere
		# The swept test must agree with the authored overlap volume or the two hit
		# paths disagree about what a hit is; a sphere shape hands us its radius.
		var authored = shape.shape
		if authored != null and authored.get_class() == "SphereShape3D":
			p.sweep_radius = float(authored.radius)
	return p


## Minimal code-built projectile so the pool works with zero scene assets.
func _make_fallback_projectile() -> Projectile:
	var p := Projectile.new()
	# Pooled shots are detection-only bodies: they answer to no query themselves
	# and only *ask* the space about the mask in CollisionLayers.
	p.collision_layer = CollisionLayers.NO_LAYER
	p.collision_mask = CollisionLayers.PROJECTILE_HIT_MASK
	p.sweep_radius = SWEEP_RADIUS
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = SWEEP_RADIUS
	shape_node.shape = sphere
	p.add_child(shape_node)
	var visual := Node3D.new()
	visual.name = "Visual"
	p.add_child(visual)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = _fallback_mesh
	visual.add_child(mesh)
	return p


## Fire one projectile. `config` is forwarded to Projectile.launch() (must at
## least carry origin + direction). Returns the projectile, or null if the pool
## node is not inside the tree or the run has been isolated.
func fire(config: Dictionary) -> Projectile:
	if _isolated or not is_inside_tree():
		return null
	var p := _obtain()
	if p == null:
		return null
	p.launch(config)
	return p


## Fire a fan of projectiles sharing a config except direction.
func fire_volley(config: Dictionary, directions: Array[Vector3]) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for dir in directions:
		# Deep copy so per-projectile direction and nested status arrays don't alias.
		var cfg := config.duplicate(true)
		cfg["direction"] = dir
		var p := fire(cfg)
		if p != null:
			out.append(p)
	return out


func _obtain() -> Projectile:
	var p: Projectile = null
	var cap := live_cap()
	# Governor cap wins over leftover idle: a LOW phone with a 48-slot pool
	# still cannot keep 48 shots in the air.
	if cap > 0 and _active.size() >= cap and not _active.is_empty():
		p = _active.pop_front()
		if p != null:
			p.pool_reset()
		pool_exhausted_recycled.emit()
	elif not _idle.is_empty():
		p = _idle.pop_back()
	elif not _active.is_empty():
		# Recycle the oldest active projectile (deterministic, no allocation).
		p = _active.pop_front()
		if p != null:
			p.pool_reset()
		pool_exhausted_recycled.emit()
	else:
		# Pool is empty and nothing active — create an emergency fallback so
		# callers never receive null and degrade gracefully.
		p = _make_projectile()
		# _make_projectile already added to tree and wired; ensure not double-idled.
		if p in _idle:
			_idle.erase(p)
		if p in _active:
			_active.erase(p)
	if p == null:
		return null
	if p in _active:
		_active.erase(p)
	_active.append(p)
	return p


func _on_release_requested(p: Projectile) -> void:
	release(p)


func release(p: Projectile) -> void:
	if p == null:
		return
	_active.erase(p)
	if p not in _idle:
		p.pool_reset()
		_idle.append(p)


func release_all() -> void:
	for p in _active.duplicate():
		release(p)


## Drain every in-flight shot and refuse further fire() until a new pool is
## built. Called from RunIsolation at GAME_OVER while WorldRoot stays up.
func isolate_run() -> void:
	release_all()
	_isolated = true


func is_isolated() -> bool:
	return _isolated


## Push a live-in-air cap. Extra active shots are recycled oldest-first so a
## tier drop cannot leave a HIGH volley simulating on a LOW phone.
func apply_budget(cap: int) -> void:
	_live_cap = clampi(cap, 1, maxi(pool_size, 1))
	while _active.size() > live_cap() and not _active.is_empty():
		var oldest: Projectile = _active.pop_front()
		if oldest == null:
			continue
		oldest.pool_reset()
		if oldest not in _idle:
			_idle.append(oldest)


func live_cap() -> int:
	if _live_cap > 0:
		return _live_cap
	return maxi(pool_size, 1)


func idle_count() -> int:
	return _idle.size()


func active_count() -> int:
	return _active.size()


func get_debug_snapshot() -> Dictionary:
	return {
		"idle": _idle.size(),
		"active": _active.size(),
		"pool_size": pool_size,
		"live_cap": live_cap(),
		"isolated": _isolated,
	}
