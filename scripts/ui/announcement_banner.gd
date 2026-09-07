class_name AnnouncementBanner
extends Label

## Centre-screen announcement line (wave incoming, boss, mutators, level-ups).
## Queues EventBus.announcement events so overlapping triggers play in sequence
## instead of stomping each other; severity tints the text. Reduced-motion
## collapses the scale pop.

const SHOW_SECONDS := 2.2
const FADE_SECONDS := 0.4

var _queue: Array = []  # [{text, severity}]
var _timer := 0.0
var _reduced_motion := false


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 30)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 8)
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if EventBus != null and not EventBus.announcement.is_connected(_on_announcement):
		EventBus.announcement.connect(_on_announcement)


func set_reduced_motion(reduced: bool) -> void:
	_reduced_motion = reduced


func announce(text: String, severity: StringName = &"info") -> void:
	_queue.append({"text": text, "severity": severity})


func _on_announcement(_key: StringName, text: String, severity: StringName) -> void:
	announce(text, severity)


func _process(delta: float) -> void:
	if _timer > 0.0:
		_timer -= delta
		if _timer <= FADE_SECONDS:
			modulate.a = maxf(_timer / FADE_SECONDS, 0.0)
		elif not _reduced_motion:
			var pop := 1.0 + 0.15 * clampf((_timer - SHOW_SECONDS + 0.3) / 0.3, 0.0, 1.0)
			scale = Vector2.ONE * pop
		if _timer <= 0.0:
			modulate.a = 0.0
		return
	if _queue.is_empty():
		return
	var next: Dictionary = _queue.pop_front()
	text = String(next["text"])
	add_theme_color_override("font_color", _severity_color(StringName(String(next["severity"]))))
	_timer = SHOW_SECONDS + FADE_SECONDS
	modulate.a = 1.0
	scale = Vector2.ONE * (1.0 if _reduced_motion else 1.25)


func _severity_color(severity: StringName) -> Color:
	match severity:
		&"danger":
			return Color(1.0, 0.35, 0.3)
		&"warning":
			return Color(1.0, 0.8, 0.3)
		&"victory":
			return Color(0.5, 1.0, 0.55)
		&"info":
			return Color(0.75, 0.9, 1.0)
	return Color.WHITE


func pending_count() -> int:
	return _queue.size()
