extends RefCounted
## In-memory save storage double. Lets SaveManager-shaped logic be tested without a
## real user:// filesystem. Wire it in where persistence is injected.

var _data: Dictionary = {}
var _fail_next_write := false


func set_fail_next_write(value: bool) -> void:
	_fail_next_write = value


func read() -> Variant:
	if _data.is_empty():
		return null
	return _data.duplicate(true)


func write(contents: Variant) -> bool:
	if _fail_next_write:
		_fail_next_write = false
		return false
	if contents is Dictionary:
		_data = contents.duplicate(true)
		return true
	return false


func has_data() -> bool:
	return not _data.is_empty()
