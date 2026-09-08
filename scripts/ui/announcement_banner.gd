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
var _coach: Label


func _ready() -> void:
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 30)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 8)
	self_modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach = UiFactory.label("", self, 20)
	_coach.set_anchors_preset(PRESET_TOP_WIDE)
	_coach.offset_top = 110
	_coach.offset_bottom = 185
	_coach.add_theme_color_override("font_outline_color", Color.BLACK)
	_coach.add_theme_constant_override("outline_size", 6)
	if EventBus != null and not EventBus.announcement.is_connected(_on_announcement):
		EventBus.announcement.connect(_on_announcement)
	EventBus.wave_completed.connect(func(wave: int, bonus: int) -> void:
		announce("WAVE %d CLEARED / +%d SCORE" % [wave, bonus], &"victory"))


func set_reduced_motion(reduced: bool) -> void:
	_reduced_motion = reduced
	if reduced: scale = Vector2.ONE


func announce(text: String, severity: StringName = &"info") -> void:
	if text.is_empty(): return
	for entry in _queue:
		if entry.text == text: return
	if _queue.size() >= 6: _queue.pop_front()
	if severity == &"danger":
		_timer = 0
		_queue.push_front({"text": text, "severity": severity})
	else:
		_queue.append({"text": text, "severity": severity})


func _on_announcement(_key: StringName, text: String, severity: StringName) -> void:
	announce(text, severity)


func _process(delta: float) -> void:
	if _timer > 0.0:
		_timer -= delta
		if _timer <= FADE_SECONDS:
			self_modulate.a = 1.0 if _reduced_motion and _timer > 0 else maxf(_timer / FADE_SECONDS, 0.0)
		if _timer <= 0.0:
			self_modulate.a = 0.0
		return
	if _queue.is_empty():
		return
	var next: Dictionary = _queue.pop_front()
	text = String(next["text"])
	add_theme_color_override("font_color", _severity_color(StringName(String(next["severity"]))))
	_timer = SHOW_SECONDS + FADE_SECONDS
	self_modulate.a = 1.0
	scale = Vector2.ONE


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


func set_coach(message: String) -> void:
	if _coach != null: _coach.text = message

func clear_pending() -> void:
	_queue.clear()
	_timer = 0
	self_modulate.a = 0
	scale = Vector2.ONE

func clear_all() -> void:
	clear_pending()
	set_coach("")

## Hardened: validate banner text.
func _validated_banner_text(t: String) -> bool:
	if t.is_empty():
		return false
	if t.length() > 200:
		return false
	return true

