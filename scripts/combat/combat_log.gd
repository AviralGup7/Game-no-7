class_name CombatLog
extends RefCounted

## Fixed-size ring buffer of recent combat events for debugging, analytics and
## the (optional) in-game combat feed. Entries are plain dictionaries with a
## monotonic sequence number; the buffer never reallocates past capacity.
## Headless-testable, no tree access.

const DEFAULT_CAPACITY := 128
const KIND_DAMAGE := &"damage"
const KIND_HEAL := &"heal"
const KIND_KILL := &"kill"
const KIND_STATUS := &"status"
const KIND_SKILL := &"skill"
const KIND_SYSTEM := &"system"

var _entries: Array = []
var _capacity := DEFAULT_CAPACITY
var _seq := 0


func _init(capacity: int = DEFAULT_CAPACITY) -> void:
	_capacity = maxi(capacity, 8)


func capacity() -> int:
	return _capacity


func size() -> int:
	return _entries.size()


func clear() -> void:
	_entries.clear()


## Append one entry. Returns its sequence number.
func record(kind: StringName, text: String, data: Dictionary = {}) -> int:
	_seq += 1
	_entries.append({
		"seq": _seq,
		"kind": kind,
		"text": text,
		"data": data,
		"msec": Time.get_ticks_msec(),
	})
	while _entries.size() > _capacity:
		_entries.pop_front()
	return _seq


func log_damage(source_id: StringName, target_name: String, amount: float, was_crit: bool, target_died: bool) -> int:
	return record(KIND_DAMAGE, "%s hit %s for %d%s%s" % [
		String(source_id), target_name, int(round(amount)),
		" CRIT" if was_crit else "",
		" (killed)" if target_died else "",
	], {"amount": amount, "crit": was_crit, "killed": target_died})


func log_heal(target_name: String, amount: float) -> int:
	return record(KIND_HEAL, "%s healed %d" % [target_name, int(round(amount))], {"amount": amount})


func log_kill(archetype_id: StringName, score: int) -> int:
	return record(KIND_KILL, "%s slain (+%d)" % [String(archetype_id), score], {"score": score})


## Newest-first slice of the last `count` entries.
func recent(count: int) -> Array:
	var n := mini(maxi(count, 0), _entries.size())
	if n <= 0:
		return []
	return _entries.slice(_entries.size() - n).duplicate().reverse()


## All entries of one kind, oldest-first.
func filter_kind(kind: StringName) -> Array:
	var out: Array = []
	for e in _entries:
		if e["kind"] == kind:
			out.append(e)
	return out


## Aggregate damage dealt per source_id across buffered damage entries.
func damage_by_source() -> Dictionary:
	var totals: Dictionary = {}
	for e in _entries:
		if e["kind"] != KIND_DAMAGE:
			continue
		var data: Dictionary = e["data"]
		var key := String(e["text"].split(" ")[0])
		totals[key] = float(totals.get(key, 0.0)) + float(data.get("amount", 0.0))
	return totals


func latest_seq() -> int:
	return _seq
