class_name SpawnLedger
extends RefCounted

## Authoritative spawn accounting, extracted from SpawnManager. Owns the pending
## queue plus the planned/spawned/defeated/failed counters and the bounded-retry
## rule for the queue head. Event-driven by the manager: entries leave the plan
## ONLY on success (pop_on_success) or exhausted retries (note_attempt), defeats
## are recorded ONLY for genuinely killed enemies, and splitter children EXTEND
## the plan — so a wave can neither under-fill nor falsely complete.
## Pure (no tree/autoload access): fully headless-testable.

## Bounded retries per queue-head before it is counted as a failed spawn (prevents
## infinite retry loops while never treating a failed spawn as a defeat).
const MAX_FAILED_ATTEMPTS := 6

var _pending: Array[StringName] = []
var _planned_count := 0
var _spawned_count := 0
var _defeated_count := 0
var _failed_count := 0
var _attempt_head: StringName = &""
var _attempt_count := 0


## Register a new spawn plan (ordered flat queue of archetype ids).
func reset(queue: Array[StringName]) -> void:
	clear()
	_pending = queue.duplicate()
	_planned_count = _pending.size()


func clear() -> void:
	_pending.clear()
	_planned_count = 0
	_spawned_count = 0
	_defeated_count = 0
	_failed_count = 0
	_attempt_head = &""
	_attempt_count = 0


func is_empty() -> bool:
	return _pending.is_empty()


## PEEK, don't pop: the head leaves the plan only via pop_on_success/note_attempt.
func peek() -> StringName:
	if _pending.is_empty():
		return &""
	return _pending[0]


## Tell the ledger which head is being attempted so retries reset when it changes.
func note_head(archetype: StringName) -> void:
	if archetype != _attempt_head:
		_attempt_head = archetype
		_attempt_count = 0


## Success: remove the head from the plan and count the spawn.
func pop_on_success() -> void:
	if _pending.is_empty():
		return
	_pending.pop_front()
	_spawned_count += 1
	_attempt_head = &""
	_attempt_count = 0


## A spawn attempt failed. Returns true when the retry bound is exhausted and the
## head was dropped as FAILED (counted separately from defeats); false = retry.
func note_attempt() -> bool:
	_attempt_count += 1
	if _attempt_count < MAX_FAILED_ATTEMPTS:
		return false
	if not _pending.is_empty():
		_pending.pop_front()
	_failed_count += 1
	_attempt_head = &""
	_attempt_count = 0
	return true


func attempt_count() -> int:
	return _attempt_count


## Splitter children join the pending queue AND extend the plan, so completion
## still requires killing everything.
func extend_one(archetype: StringName) -> void:
	_pending.append(archetype)
	_planned_count += 1


## A genuinely killed enemy is counted as defeated (called on its death path only).
func record_defeat() -> void:
	_defeated_count += 1


func planned_count() -> int:
	return _planned_count


func pending_count() -> int:
	return _pending.size()


func spawned_count() -> int:
	return _spawned_count


func defeated_count() -> int:
	return _defeated_count


func failed_count() -> int:
	return _failed_count


func snapshot() -> Dictionary:
	return {
		"planned": _planned_count,
		"pending": _pending.size(),
		"spawned": _spawned_count,
		"defeated": _defeated_count,
		"failed": _failed_count,
	}
