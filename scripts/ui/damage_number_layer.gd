class_name DamageNumberLayer
extends Control

## Floating combat text: pooled Labels that pop at world positions (projected to
## screen), drift upward, and fade. Damage (white/yellow crits), heals (green),
## misses and status ticks share one budget honoring the PerformanceMonitor cap
## and reduced-motion settings. Feeds from spawn_damage_number() calls made by
## UI glue observing EventBus.enemy_damaged / player HealthComponent.

const DEFAULT_POOL := 32
const MAX_POOL := 64
const RISE_PIXELS := 64.0
const LIFE_SECONDS := 0.8
const CRIT_SCALE := 1.5

var _pool: Array[Label] = []
var _live: Array = []  # [{label, timer, velocity}]
var _max_live := DEFAULT_POOL
var _reduced_motion := false
var _camera: Camera3D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for i in range(DEFAULT_POOL):
		_pool.append(_make_label())


func _make_label() -> Label:
	var label := Label.new()
	label.visible = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	return label


## Raise/lower the live budget. The pool grows to match, otherwise a tier asking
## for more numbers than DEFAULT_POOL (ULTRA wants 48) silently stayed at 32.
func set_max_live(count: int) -> void:
	_max_live = clampi(count, 4, MAX_POOL)
	while _pool.size() < _max_live:
		_pool.append(_make_label())


func set_reduced_motion(reduced: bool) -> void:
	_reduced_motion = reduced
	if reduced:
		for label in _pool: label.scale = Vector2.ONE


func bind_camera(camera: Camera3D) -> void:
	_camera = camera


func _active_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	if get_viewport() != null:
		return get_viewport().get_camera_3d()
	return null


## World -> screen projection. Returns null when behind the camera.
func _project(world_pos: Vector3) -> Variant:
	var cam := _active_camera()
	if cam == null:
		return null
	if cam.is_position_behind(world_pos):
		return null
	return cam.unproject_position(world_pos)


func spawn_damage_number(world_pos: Vector3, amount: float, was_crit: bool = false, color: Color = Color.WHITE) -> void:
	if _live.size() >= _max_live:
		return
	var screen: Variant = _project(world_pos)
	if screen == null:
		return
	var label := _obtain()
	label.text = str(CriticalSystem.display_value(amount, was_crit))
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if was_crit else color)
	label.add_theme_font_size_override("font_size", int(22 * CRIT_SCALE) if was_crit else 22)
	# Cosmetic jitter: visual scatter of floating numbers, no gameplay effect.
	label.position = (screen as Vector2) + Vector2(0 if _reduced_motion else randf_range(-12, 12), -8)
	label.visible = true
	label.modulate.a = 1.0
	label.scale = Vector2.ONE * (1.3 if was_crit and not _reduced_motion else 1.0)
	_live.append({"label": label, "timer": LIFE_SECONDS, "crit": was_crit})


func spawn_heal_number(world_pos: Vector3, amount: float) -> void:
	spawn_damage_number(world_pos, amount, false, Color(0.45, 1.0, 0.5))


func spawn_text(world_pos: Vector3, text: String, color: Color = Color.WHITE, big: bool = false) -> void:
	if _live.size() >= _max_live:
		return
	var screen: Variant = _project(world_pos)
	if screen == null:
		return
	var label := _obtain()
	label.scale = Vector2.ONE
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 30 if big else 20)
	label.position = (screen as Vector2) + Vector2(-20, -12)
	label.visible = true
	label.modulate.a = 1.0
	_live.append({"label": label, "timer": LIFE_SECONDS * 1.2, "crit": big})


func _obtain() -> Label:
	for label in _pool:
		if not label.visible:
			return label
	# Pool exhausted: reuse the oldest live label. Hide it first so the caller
	# starts from a clean state instead of inheriting the dropped entry's tween.
	if _live.is_empty():
		var extra := _make_label()
		_pool.append(extra)
		return extra
	var oldest: Dictionary = _live.pop_front()
	var recycled: Label = oldest["label"]
	recycled.visible = false
	recycled.scale = Vector2.ONE
	recycled.modulate.a = 1.0
	return recycled


func _process(delta: float) -> void:
	if _live.is_empty():
		return
	var rise := 0.0 if _reduced_motion else RISE_PIXELS
	# Iterate backwards: safe removal without a per-frame Array copy or a
	# linear Dictionary search for each expired label. Survivor order is kept.
	for index in range(_live.size() - 1, -1, -1):
		var entry: Dictionary = _live[index]
		entry["timer"] = float(entry["timer"]) - delta
		var label: Label = entry["label"]
		var frac: float = clampf(float(entry["timer"]) / LIFE_SECONDS, 0.0, 1.0)
		label.position.y -= rise * delta * (0.4 + 0.6 * frac)
		label.modulate.a = minf(frac * 2.0, 1.0)
		if not _reduced_motion and bool(entry.get("crit", false)):
			label.scale = label.scale.lerp(Vector2.ONE, delta * 6.0)
		if float(entry["timer"]) <= 0.0:
			label.visible = false
			_live.remove_at(index)


func clear_all() -> void:
	for entry in _live:
		(entry["label"] as Label).visible = false
	_live.clear()


func live_count() -> int:
	return _live.size()

## Hardened: clamp damage number value.
func _validated_damage_label(v: float) -> float:
	if not is_finite(v) or v < 0.0:
		return 0.0
	return clampf(v, 0.0, 999999.0)

