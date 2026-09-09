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
	vertical_alignment = VERTICAL_ALIGNMENT_TOP
	clip_text = false
	# The coach line hangs off the bottom of the banner rect and follows it on
	# every resize, so it can never land on top of the announcement text.
	_coach = UiFactory.label("", self, 20)
	_coach.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_coach.offset_top = 4
	_coach.offset_bottom = 40
	_coach.position.y = size.y + 4.0
	_coach.modulate = UiTheme.CYAN
	_coach.add_theme_color_override("font_outline_color", Color.BLACK)
	_coach.add_theme_constant_override("outline_size", 6)
	if EventBus != null and not EventBus.announcement.is_connected(_on_announcement):
		EventBus.announcement.connect(_on_announcement)
	if EventBus != null and not EventBus.wave_completed.is_connected(_on_wave_cleared):
		EventBus.wave_completed.connect(_on_wave_cleared)


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


func _on_wave_cleared(wave: int, bonus: int) -> void:
	announce("WAVE %d CLEARED / +%d SCORE" % [wave, bonus], &"victory")


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
	_pop_in()


## Small entrance pop so new announcements land with weight instead of blinking
## in. Skipped under reduced motion (matches the documented behavior).
func _pop_in() -> void:
	if _reduced_motion or not is_inside_tree():
		scale = Vector2.ONE
		return
	pivot_offset = size * 0.5
	scale = Vector2(0.92, 0.92)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	if _coach == null:
		return
	_coach.text = message
	_coach.scale = Vector2.ONE
	_coach.position.y = size.y + 4.0

func clear_pending() -> void:
	_queue.clear()
	_timer = 0
	self_modulate.a = 0
	scale = Vector2.ONE

func clear_all() -> void:
	clear_pending()
	set_coach("")
