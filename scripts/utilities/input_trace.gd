class_name InputTrace
extends RefCounted

## Ring buffer of the last N touch/joystick events so a mid-run stick crash
## leaves a `[LastStand][input]` paper trail without needing logcat on this box.

const PREFIX := "[LastStand][input]"
const CAP := 20

static var _lines: PackedStringArray = PackedStringArray()
static var _seq := 0


static func record(kind: String, detail: String) -> void:
	_seq += 1
	var line := "%s #%d t=%d %s %s" % [PREFIX, _seq, Time.get_ticks_msec(), kind, detail]
	_lines.append(line)
	while _lines.size() > CAP:
		_lines.remove_at(0)


static func dump(reason: String = "dump") -> void:
	print("%s --- %s (%d events) ---" % [PREFIX, reason, _lines.size()])
	for line in _lines:
		print(line)
	if EventBus != null:
		EventBus.report_info("%s %s n=%d last=%s" % [PREFIX, reason, _lines.size(),
			_lines[_lines.size() - 1] if not _lines.is_empty() else ""])


static func snapshot() -> PackedStringArray:
	return _lines.duplicate()
