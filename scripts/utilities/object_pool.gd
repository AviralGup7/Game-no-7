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
# Explicit ownership tracking prevents an object from being released into a
# different pool (or released twice) and silently corrupting live_count.
var _leased: Array = []
var _live_count := 0
var _total_created := 0
var _max_size: int = 256
var _tag: String = "pool"


## `pool_max_size` / `pool_tag`, not `max_size` / `tag`: those are this class'
## own accessors (`max_size()`, `tag()`).
func _init(create_fn: Callable = Callable(), reset_fn: Callable = Callable(), prewarm: int = 0, pool_max_size: int = 256, pool_tag: String = "pool") -> void:
	_create_fn = create_fn
	_reset_fn = reset_fn
	_max_size = maxi(pool_max_size, 1)
	_tag = pool_tag
	if prewarm > 0:
		prewarm_pool(prewarm)


## Fill the free list up to `count` idle objects (no-op without a create fn).
func prewarm_pool(count: int) -> void:
	if not _create_fn.is_valid():
		return
	var target := mini(count, _max_size)
	while _free.size() < target:
		var obj: Variant = _create_fn.call()
		# A failed factory must not seed null entries or make this loop unbounded.
		if obj == null:
			break
		_free.append(obj)
		_total_created += 1


## Take an object from the pool (freshly created when empty). Returns null when
## no create fn is configured or a factory fails. Every successful acquire is
## recorded so release can reject foreign and duplicate objects safely.
func acquire() -> Variant:
	if not _create_fn.is_valid():
		return null
	var obj: Variant = null
	while not _free.is_empty() and obj == null:
		obj = _free.pop_back()
	if obj == null:
		obj = _create_fn.call()
		if obj == null:
			return null
		_total_created += 1
	if _reset_fn.is_valid():
		_reset_fn.call(obj)
	_leased.append(obj)
	_live_count = _leased.size()
	return obj


## Return an object. Only objects currently leased from this pool are accepted;
## unknown/duplicate releases are ignored. Reset on release prevents stale state
## from leaking into a later use, while the acquire reset remains a second line
## of defence for callers whose reset function depends on activation context.
func release(obj: Variant) -> void:
	if obj == null or not _leased.has(obj):
		return
	_leased.erase(obj)
	_live_count = _leased.size()
	if _reset_fn.is_valid():
		_reset_fn.call(obj)
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
