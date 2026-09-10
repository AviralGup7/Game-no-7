extends RefCounted

## Headless unit tests for the debug-mode error pipeline's pure core: ErrorReport
## formatting + DebugLogBuffer eviction. Neither script touches an autoload, the
## tree, or the filesystem, so this suite runs in the synchronous phase.

static func suite() -> Array:
	var results: Array = []

	var report := ErrorReport.build("Boom", "Something failed", [], {}, PackedStringArray())
	results.append({
		"name": "build wraps title/message in copy markers",
		"passed": report.contains(ErrorReport.BEGIN_MARKER) and report.contains("Boom") and report.contains("Something failed") and report.contains(ErrorReport.END_MARKER),
		"why": "",
	})

	results.append({
		"name": "build with empty stack carries the no-stack note",
		"passed": ErrorReport.build("T", "M", [], {}, PackedStringArray()).contains(ErrorReport.NO_STACK_NOTE),
		"why": "",
	})

	var frames := ErrorReport.format_stack([{"function": "_ready", "source": "res://game.gd", "line": 12}])
	results.append({
		"name": "dict stack frames format as #index func() source:line",
		"passed": frames.size() == 1 and frames[0].contains("#0") and frames[0].contains("_ready()") and frames[0].contains("res://game.gd:12"),
		"why": "",
	})

	var mixed := ErrorReport.format_stack(["custom frame text"])
	results.append({
		"name": "string stack entries pass through numbered",
		"passed": mixed.size() == 1 and mixed[0] == "#0 custom frame text",
		"why": "",
	})

	var odd := ErrorReport.format_stack([42, null, {}])
	results.append({
		"name": "malformed stack entries degrade to placeholders, never break",
		"passed": odd.size() == 3 and odd[0].contains("#0") and odd[2].contains("(unknown)"),
		"why": "",
	})

	var sorted_report := ErrorReport.build("T", "M", [], {"zebra": 1, "apple": 2}, PackedStringArray())
	results.append({
		"name": "context keys are sorted for stable diffs",
		"passed": sorted_report.find("apple: 2") >= 0 and sorted_report.find("apple: 2") < sorted_report.find("zebra: 1"),
		"why": "",
	})

	var bare := ErrorReport.build("", "   ", [], {}, PackedStringArray())
	results.append({
		"name": "empty title/message degrade to placeholders",
		"passed": bare.contains("(untitled error)") and bare.contains("(no message)") and bare.contains(ErrorReport.END_MARKER),
		"why": "",
	})

	var logged := ErrorReport.build("T", "M", [], {}, PackedStringArray(["first", "second"]))
	results.append({
		"name": "log tail is embedded oldest-first",
		"passed": logged.find("first") >= 0 and logged.find("first") < logged.find("second"),
		"why": "",
	})

	var data_dir := OS.get_user_data_dir()
	var redact_ok := ErrorReport.redact("plain text") == "plain text"
	if not data_dir.is_empty():
		var masked := ErrorReport.redact(data_dir + "/logs/x.log")
		redact_ok = redact_ok and masked.begins_with("user://") and not masked.contains(data_dir)
	results.append({
		"name": "redact masks the user-data dir, leaves other text alone",
		"passed": redact_ok,
		"why": "",
	})

	var stamp := ErrorReport.filename_stamp()
	results.append({
		"name": "filename stamp is non-empty with no colons",
		"passed": not stamp.is_empty() and not stamp.contains(":"),
		"why": "",
	})

	var clock := ErrorReport.utc_now()
	results.append({
		"name": "utc_now is an ISO-8601 Zulu timestamp",
		"passed": clock.contains("T") and clock.ends_with("Z"),
		"why": "",
	})

	var buffer := DebugLogBuffer.new(3)
	for i in 5:
		buffer.push("line%d" % i)
	results.append({
		"name": "log buffer evicts oldest past the cap and counts drops",
		"passed": buffer.size() == 3 and buffer.dropped_count() == 2,
		"why": "",
	})

	results.append({
		"name": "log buffer tail returns the newest lines in order",
		"passed": buffer.tail(2) == PackedStringArray(["line3", "line4"]),
		"why": "",
	})

	results.append({
		"name": "log buffer tail edges: zero is empty, over-count clamps",
		"passed": buffer.tail(0).is_empty() and buffer.tail(99).size() == 3,
		"why": "",
	})

	buffer.clear()
	results.append({
		"name": "log buffer clear resets lines and drop count",
		"passed": buffer.size() == 0 and buffer.dropped_count() == 0 and buffer.tail(5).is_empty(),
		"why": "",
	})

	return results
