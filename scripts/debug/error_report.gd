class_name ErrorReport
extends RefCounted
## Pure error-report formatter for debug mode. Builds the single copyable text
## block the freeze overlay shows: markers, title, UTC timestamp, message, stack
## trace, device/game context, and the recent-log tail. No autoload, tree, or
## file access — the handler gathers context and passes plain data in, so
## headless unit tests can drive every function here.

const BEGIN_MARKER := "===== LAST STAND: ARENA — ERROR REPORT ====="
const END_MARKER := "===== END OF ERROR REPORT ====="
const COPY_HINT := "Copy everything between the marker lines when sharing this report."
const NO_STACK_NOTE := "(no stack trace captured)"
const EMPTY_LOG_NOTE := "(recent log is empty)"
const MAX_MESSAGE_CHARS := 4000


## Wall-clock UTC timestamp for reports, e.g. 2026-09-10T08:40:00Z.
static func utc_now() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"


## Filename-safe UTC stamp (colons are illegal on some filesystems).
static func filename_stamp() -> String:
	return utc_now().replace(":", "-")


## Mask the absolute user-data dir (on desktop it leaks the OS username, e.g.
## /home/aviral/.local/...) with the portable `user://` token. No-op when the
## dir is unknown or absent from the text.
static func redact(text: String) -> String:
	var data_dir := OS.get_user_data_dir()
	if data_dir.is_empty():
		return text
	return text.replace(data_dir, "user://")


## Normalize one stack frame (a get_stack() Dictionary or a preformatted
## String) into a single display line. Anything else becomes a placeholder so a
## malformed frame can never break the report itself.
static func format_frame(frame: Variant, index: int) -> String:
	var prefix := "#%d " % index
	if frame is String:
		var text := String(frame).strip_edges()
		return prefix + (text if not text.is_empty() else "(empty frame)")
	if frame is Dictionary:
		var entry := frame as Dictionary
		var function_name := str(entry.get("function", "(unknown)"))
		var source := str(entry.get("source", "(unknown)"))
		var line := str(entry.get("line", "?"))
		return "%s%s()  %s:%s" % [prefix, function_name, source, line]
	return prefix + "(unrecognized stack entry)"


## Format a whole stack (get_stack() output). Empty input yields the no-stack note.
static func format_stack(stack: Array) -> PackedStringArray:
	if stack.is_empty():
		return PackedStringArray([NO_STACK_NOTE])
	var lines := PackedStringArray()
	for i in stack.size():
		lines.append(format_frame(stack[i], i))
	return lines


## Drop leading stack frames that belong to the error plumbing itself
## (EventBus.report_* + the debug pipeline), so frame #0 is the true caller.
## Stops at the first external frame; non-Dictionary entries are kept as-is so a
## malformed stack can never come back empty-handed.
static func drop_internal_frames(stack: Array, internal_suffixes: Array) -> Array:
	var start := 0
	while start < stack.size():
		var entry: Variant = stack[start]
		if not entry is Dictionary:
			break
		var source := str((entry as Dictionary).get("source", ""))
		var internal := false
		for suffix in internal_suffixes:
			if not source.is_empty() and source.ends_with(str(suffix)):
				internal = true
		if not internal:
			break
		start += 1
	return stack.slice(start)


## Assemble the full copyable block. `stack` is get_stack() output (or an empty
## Array), `context` a flat String->Variant map, `log_tail` the buffered lines
## in chronological order (oldest first). Context keys are sorted so two reports
## from the same bug diff cleanly.
static func build(title: String, message: String, stack: Array, context: Dictionary, log_tail: PackedStringArray) -> String:
	var clean_title := title.strip_edges()
	if clean_title.is_empty():
		clean_title = "(untitled error)"
	var clean_message := message.strip_edges()
	if clean_message.is_empty():
		clean_message = "(no message)"
	if clean_message.length() > MAX_MESSAGE_CHARS:
		clean_message = clean_message.left(MAX_MESSAGE_CHARS) + "\n... (message truncated)"
	var lines := PackedStringArray()
	lines.append(BEGIN_MARKER)
	lines.append(COPY_HINT)
	lines.append("")
	lines.append("TITLE: " + clean_title)
	lines.append("CAPTURED (UTC): %s (%d ms)" % [utc_now(), Time.get_ticks_msec()])
	lines.append("")
	lines.append("MESSAGE:")
	lines.append(clean_message)
	lines.append("")
	lines.append("--- STACK TRACE ---")
	for frame_line in format_stack(stack):
		lines.append(frame_line)
	lines.append("")
	lines.append("--- CONTEXT ---")
	var keys := context.keys()
	keys.sort()
	if keys.is_empty():
		lines.append("(no context)")
	for key in keys:
		lines.append("%s: %s" % [str(key), str(context[key])])
	lines.append("")
	lines.append("--- RECENT LOG (oldest first) ---")
	if log_tail.is_empty():
		lines.append(EMPTY_LOG_NOTE)
	for log_line in log_tail:
		lines.append(log_line)
	lines.append(END_MARKER)
	return redact("\n".join(lines))
