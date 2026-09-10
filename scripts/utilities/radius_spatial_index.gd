class_name RadiusSpatialIndex
extends RefCounted

## A uniform grid over a bounded XZ region for "which entities are within R of P".
## Built for ArenaHazards, but it knows nothing about hazards: it indexes into the
## caller's snapshot arrays and hands back element indices.
##
## Why a grid rather than a quadtree: the contents are a few dozen similarly sized
## bodies that each move a few centimetres per physics tick, and the whole structure is
## rebuilt from scratch every tick. Rehashing into a grid is O(n) with no allocation,
## while a tree costs O(n log n) to rebuild and its cells churn exactly when things move
## — the case trees handle worst. Cell size follows the usual rule of thumb (about twice
## the largest query radius, erring large), so a query visits a 2x2 to 3x3 block of
## buckets and a running victim changes bucket every tens of ticks rather than every one.
##
## Buckets are singly linked lists carved out of two PackedInt32Arrays — a head per cell,
## a next-link per element — so a rebuild only writes ints into arrays that are already
## the right size: no per-cell Array, no dictionary of buckets, no per-tick allocation.
##
## Cost per tick as shipped: one pass to bucket ~40 victims, then an O(victims-nearby)
## visit per hazard that actually cares this tick.

const MAX_ELEMENTS := 96
const MAX_RESULTS := 96
## Targeting bits. The index does not know what a victim is, only which team it is on.
const FLAG_PLAYER := 1
const FLAG_ENEMY := 2

var cell_size: float = 4.0
var cells_x: int = 0
var cells_z: int = 0

var _origin_x: float = 0.0
var _origin_z: float = 0.0
var _heads: PackedInt32Array = PackedInt32Array()
var _next: PackedInt32Array = PackedInt32Array()
var _x: PackedFloat32Array = PackedFloat32Array()
var _z: PackedFloat32Array = PackedFloat32Array()
var _pad: PackedFloat32Array = PackedFloat32Array()
var _flags: PackedInt32Array = PackedInt32Array()
var _results: PackedInt32Array = PackedInt32Array()
var _count: int = 0
var _max_pad: float = 0.0

## Instrumentation for the debug overlay: how much work the grid is actually doing.
var rebuilds: int = 0
var overflow_count: int = 0
var queries: int = 0
var visited: int = 0


## `half` is the arena's half-extent; `largest_radius` the biggest query the caller will
## make. Cells are derived so the region is at least 2x2 and at most ~16x16 buckets.
func setup(center: Vector3, half: float, largest_radius: float) -> void:
	var extent := maxf(half, 1.0) * 2.0
	var wanted := clampf(maxf(largest_radius, 0.5) * 2.0, 2.0, extent * 0.5)
	cell_size = wanted if is_finite(wanted) else 4.0
	cells_x = maxi(int(ceilf(extent / cell_size)), 2)
	cells_z = cells_x
	_origin_x = center.x - extent * 0.5
	_origin_z = center.z - extent * 0.5
	var cells := cells_x * cells_z
	if _heads.size() != cells:
		_heads.resize(cells)
	_heads.fill(-1)
	_next.resize(MAX_ELEMENTS)
	_x.resize(MAX_ELEMENTS)
	_z.resize(MAX_ELEMENTS)
	_pad.resize(MAX_ELEMENTS)
	_flags.resize(MAX_ELEMENTS)
	_results.resize(MAX_RESULTS)
	_count = 0
	_max_pad = 0.0


## Empties the buckets without touching the arrays: an O(cells) fill, not a reallocation.
func begin_update() -> void:
	_heads.fill(-1)
	_count = 0
	_max_pad = 0.0
	rebuilds += 1


## Adds one element. Returns its index in the caller's snapshot arrays, or -1 when the
## index is full (a caller that overflows must not silently lose a victim, so it counts).
func insert(pos: Vector3, flags: int, pad: float) -> int:
	if _count >= MAX_ELEMENTS:
		overflow_count += 1
		return -1
	var i := _count
	_count += 1
	var clean_x := pos.x if is_finite(pos.x) else 0.0
	var clean_z := pos.z if is_finite(pos.z) else 0.0
	_x[i] = clean_x
	_z[i] = clean_z
	_pad[i] = maxf(pad, 0.0)
	_max_pad = maxf(_max_pad, _pad[i])
	_flags[i] = flags
	var cell := _cell_of(clean_x, clean_z)
	_next[i] = _heads[cell]
	_heads[cell] = i
	return i


## Fills `_results` with the indices whose padded circle overlaps `center`/`radius` and
## that carry at least one of `flag_mask`'s bits (0 = everyone). Only one query may be
## live at a time: callers process the results before querying again.
func query(center: Vector3, radius: float, flag_mask: int) -> int:
	queries += 1
	var found := 0
	if _count == 0 or radius <= 0.0:
		return 0
	var reach := radius + _max_pad
	var clean_x := center.x if is_finite(center.x) else 0.0
	var clean_z := center.z if is_finite(center.z) else 0.0
	var min_cx := _cell_index_x(clean_x - reach)
	var max_cx := _cell_index_x(clean_x + reach)
	var min_cz := _cell_index_z(clean_z - reach)
	var max_cz := _cell_index_z(clean_z + reach)
	for cz in range(min_cz, max_cz + 1):
		for cx in range(min_cx, max_cx + 1):
			var element := _heads[cz * cells_x + cx]
			while element != -1:
				visited += 1
				if (flag_mask == 0 or (_flags[element] & flag_mask) != 0) and found < MAX_RESULTS:
					var dx := _x[element] - clean_x
					var dz := _z[element] - clean_z
					var pad := _pad[element]
					var allowed := radius + pad
					if dx * dx + dz * dz <= allowed * allowed:
						_results[found] = element
						found += 1
				element = _next[element]
	return found


func result_index(at: int) -> int:
	return _results[at]


func element_position(at: int) -> Vector3:
	return Vector3(_x[at], 0.0, _z[at])


func element_flags(at: int) -> int:
	return _flags[at]


func element_count() -> int:
	return _count


func clear() -> void:
	_count = 0
	_heads.fill(-1)


func debug_snapshot() -> Dictionary:
	return {
		"cells": cells_x * cells_z,
		"cell_size": snappedf(cell_size, 0.01),
		"elements": _count,
		"rebuilds": rebuilds,
		"queries": queries,
		"visited": visited,
		"overflow": overflow_count,
	}


func _cell_index_x(world_x: float) -> int:
	var cell := int(floorf((world_x - _origin_x) / cell_size))
	return clampi(cell, 0, cells_x - 1)


func _cell_index_z(world_z: float) -> int:
	var cell := int(floorf((world_z - _origin_z) / cell_size))
	return clampi(cell, 0, cells_z - 1)


func _cell_of(world_x: float, world_z: float) -> int:
	return _cell_index_z(world_z) * cells_x + _cell_index_x(world_x)
