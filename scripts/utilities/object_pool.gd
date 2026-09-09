class_name ObjectPool
extends RefCounted

## Generic object pool for hot-path allocations (projectiles, pickups, damage
## numbers, hit effects). Backed by injected create/reset Callables so it stays
## type-agnostic and headless-testable without a scene tree.
##
## Usage:
##   var pool := ObjectPool.new(Callable(self, "_make_fx"), Callable(self, "_reset_fx"), 16)
##   var fx = pool.acquire()
##   ... use ...
##   pool.release(fx)

var _create_fn: Callable
var _reset_fn: Callable
var _free: Array = []
var _live_count := 0
var _total_created := 0
var _max_size: int = 256
var _tag: String = "pool"


func _init(create_fn: Callable = Callable(), reset_fn: Callable = Callable(), prewarm: int = 0, max_size: int = 256, tag: String = "pool") -> void:
	_create_fn = create_fn
	_reset_fn = reset_fn
	_max_size = maxi(max_size, 1)
	_tag = tag
	if prewarm > 0:
		prewarm_pool(prewarm)


## Fill the free list up to `count` idle objects (no-op without a create fn).
func prewarm_pool(count: int) -> void:
	if not _create_fn.is_valid():
		return
	var target := mini(count, _max_size)
	while _free.size() < target:
		_free.append(_create_fn.call())
		_total_created += 1


## Take an object from the pool (freshly created when empty). Returns null when
## no create fn is configured.
func acquire() -> Variant:
	if not _create_fn.is_valid():
		return null
	var obj: Variant = null
	if _free.is_empty():
		obj = _create_fn.call()
		_total_created += 1
	else:
		obj = _free.pop_back()
	if _reset_fn.is_valid() and obj != null:
		_reset_fn.call(obj)
	_live_count += 1
	return obj


## Return an object. Unknown/duplicate releases are ignored defensively; objects
## beyond max_size are dropped so the pool cannot grow without bound.
func release(obj: Variant) -> void:
	if obj == null:
		return
	if obj in _free:
		return
	_live_count = maxi(_live_count - 1, 0)
	if _free.size() >= _max_size:
		_free_release_overflow(obj)
		return
	_free.append(obj)


func _free_release_overflow(obj: Variant) -> void:
	if obj is Node and is_instance_valid(obj):
		(obj as Node).queue_free()


## Number of idle objects ready to acquire.
func idle_count() -> int:
	return _free.size()


## Number of objects currently checked out.
func live_count() -> int:
	return _live_count


func total_created() -> int:
	return _total_created


func max_size() -> int:
	return _max_size


func tag() -> String:
	return _tag


## Drop all idle objects (frees Nodes). Live checkouts are unaffected.
func clear_idle() -> void:
	for obj in _free:
		_free_release_overflow(obj)
	_free.clear()


func get_debug_snapshot() -> Dictionary:
	return {
		"tag": _tag,
		"idle": _free.size(),
		"live": _live_count,
		"total_created": _total_created,
		"max_size": _max_size,
	}
