class_name DebugLogBuffer
extends RefCounted
## Bounded in-memory ring of recent log lines, kept for error reports.
## Pure data structure: no autoload, tree, or file access, so headless unit
## tests can drive it directly. The handler owns one instance and mirrors every
## pushed line to the on-disk session log.

const DEFAULT_MAX_LINES := 400


var _lines: PackedStringArray = PackedStringArray()
var _max_lines: int = DEFAULT_MAX_LINES
var _dropped: int = 0


func _init(max_lines: int = DEFAULT_MAX_LINES) -> void:
	_max_lines = maxi(max_lines, 1)


## Append one pre-formatted line, evicting the oldest past the cap.
func push(line: String) -> void:
	_lines.append(line)
	while _lines.size() > _max_lines:
		_lines.remove_at(0)
		_dropped += 1


## The newest `count` lines in chronological order (fewer when the buffer holds less).
func tail(count: int) -> PackedStringArray:
	if count <= 0 or _lines.is_empty():
		return PackedStringArray()
	var start := maxi(_lines.size() - count, 0)
	return _lines.slice(start)


func size() -> int:
	return _lines.size()


## How many lines were evicted since construction (or the last clear).
func dropped_count() -> int:
	return _dropped


func clear() -> void:
	_lines.clear()
	_dropped = 0
