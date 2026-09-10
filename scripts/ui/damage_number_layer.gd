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
	# Every label's position is re-solved from a world projection in _process, so
	# letting the interpolation system also blend the layer between physics ticks
	# would double-smooth the numbers (they would trail the hit by a tick). Children
	# inherit this.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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


var _hud_block: Rect2 = Rect2()
var _skill_block: Rect2 = Rect2()
var _minimap_block: Rect2 = Rect2()
var _text_scale := 1.0


func set_text_scale(value: float) -> void:
	_text_scale = clampf(value, 0.8, 2.0)


func set_minimap_block(rect: Rect2) -> void:
	_minimap_block = rect


func set_hud_block(rect: Rect2) -> void:
	_hud_block = rect


func set_skill_block(rect: Rect2) -> void:
	_skill_block = rect


func spawn_damage_number(world_pos: Vector3, amount: float, was_crit: bool = false, color: Color = Color.WHITE, follow: Node3D = null, player_owned: bool = false, is_heal: bool = false) -> void:
	if not is_heal and amount > 0.0 and amount < 1.5 and not was_crit and not player_owned:
		# Chip / DoT ticks stay as bursts, not stacked labels.
		return
	if _live.size() >= _max_live:
		_evict_non_player(3 if player_owned else 1, is_heal)
		if _live.size() >= _max_live:
			return
	var screen: Variant = _project(world_pos)
	if screen == null:
		return
	var label := _obtain(player_owned)
	label.text = str(CriticalSystem.display_value(amount, was_crit))
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if was_crit else color)
	label.add_theme_font_size_override("font_size", int((22 * CRIT_SCALE if was_crit else 22) * _text_scale))
	label.add_theme_constant_override("outline_size", int(6.0 + _text_scale * 3.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	var jitter := Vector2(0 if _reduced_motion else randf_range(-12, 12), -8)
	if was_crit:
		jitter.x = clampf(jitter.x + 18.0, -28.0, 28.0)
		jitter.y -= 16.0
	label.position = _avoid_hud(_unstick((screen as Vector2) + jitter, player_owned))
	label.visible = true
	label.modulate.a = 1.0
	label.scale = Vector2.ONE * (1.3 if was_crit and not _reduced_motion else 1.0)
	_live.append({
		"label": label,
		"timer": LIFE_SECONDS,
		"crit": was_crit,
		"follow": follow,
		"offset": Vector3(0, 1.2, 0),
		"jitter": jitter,
		"last_world": world_pos,
		"player": player_owned,
		"heal": is_heal,
	})


func spawn_heal_number(world_pos: Vector3, amount: float) -> void:
	spawn_damage_number(world_pos, amount, false, Color(0.45, 1.0, 0.5), null, true, true)


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
	label.position = _unstick((screen as Vector2) + Vector2(-20, -12), false)
	label.visible = true
	label.modulate.a = 1.0
	_live.append({"label": label, "timer": LIFE_SECONDS * 1.2, "crit": big})


func _obtain(prefer_keep_player: bool = false) -> Label:
	for label in _pool:
		if not label.visible:
			return label
	# Pool exhausted: reuse the oldest live label. Hide it first so the caller
	# starts from a clean state instead of inheriting the dropped entry's tween.
	if _live.is_empty():
		var extra := _make_label()
		_pool.append(extra)
		return extra
	var pick := 0
	if prefer_keep_player:
		for i in range(_live.size()):
			if not bool(_live[i].get("player", false)) and not bool(_live[i].get("heal", false)):
				pick = i
				break
	var oldest: Dictionary = _live.pop_at(pick)
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
		var follow: Node3D = entry.get("follow", null) as Node3D
		if follow != null and is_instance_valid(follow) and follow.is_inside_tree() \
				and not (follow is Damageable and not (follow as Damageable).is_alive()):
			var world: Vector3 = follow.global_position + (entry.get("offset", Vector3.UP) as Vector3)
			entry["last_world"] = world
			var projected: Variant = _project(world)
			if projected != null:
				var jitter: Vector2 = entry.get("jitter", Vector2.ZERO)
				label.position = _avoid_hud((projected as Vector2) + jitter)
				label.position.y -= rise * (1.0 - frac)
		elif entry.has("last_world"):
			var projected_last: Variant = _project(entry["last_world"])
			if projected_last != null:
				label.position = _avoid_hud(projected_last as Vector2)
				label.position.y -= rise * (1.0 - frac)
			entry["follow"] = null
		else:
			label.position.y -= rise * delta * (0.4 + 0.6 * frac)
		label.modulate.a = minf(frac * 2.0, 1.0)
		if not _reduced_motion and bool(entry.get("crit", false)):
			label.scale = label.scale.lerp(Vector2.ONE, delta * 6.0)
		if float(entry["timer"]) <= 0.0:
			label.visible = false
			_live.remove_at(index)


func _evict_non_player(count: int = 1, allow_heal: bool = false) -> void:
	var left := count
	for i in range(_live.size() - 1, -1, -1):
		if left <= 0:
			return
		var entry: Dictionary = _live[i]
		if bool(entry.get("player", false)):
			continue
		if not allow_heal and bool(entry.get("heal", false)):
			continue
		(entry["label"] as Label).visible = false
		_live.remove_at(i)
		left -= 1


func clear_all() -> void:
	for entry in _live:
		(entry["label"] as Label).visible = false
	_live.clear()


func live_count() -> int:
	return _live.size()


const STACK_CELL := 26.0


## Nudge a new number so it does not sit on the same pixel as a live one (crowds
## at 30 FPS otherwise stack into an unreadable blob).
func _unstick(pos: Vector2, player_owned: bool = false) -> Vector2:
	var p := pos
	for _i in range(8):
		var hit := false
		for entry in _live:
			var other: Label = entry["label"]
			if not other.visible:
				continue
			if other.position.distance_to(p) < STACK_CELL:
				var other_heal := bool(entry.get("heal", false))
				var other_crit := bool(entry.get("crit", false))
				if other_heal:
					p.x -= STACK_CELL * 1.6
					p.y -= 10.0
				elif other_crit:
					p.x += STACK_CELL * 0.6
				if player_owned:
					p.x -= STACK_CELL
					p.y -= 18.0
				else:
					p.y -= STACK_CELL
					p.x += 8.0
				hit = true
				break
		if not hit:
			break
	return p


func _avoid_hud(pos: Vector2) -> Vector2:
	if _hud_block.size.x > 1.0 and _hud_block.grow(8.0).has_point(pos):
		pos.y = _hud_block.end.y + 12.0
	if _minimap_block.size.x > 1.0 and _minimap_block.grow(8.0).has_point(pos):
		pos.x = _minimap_block.position.x - 36.0
	if _skill_block.size.x > 1.0 and _skill_block.grow(8.0).has_point(pos):
		pos.y = _skill_block.position.y - 28.0
	var vp := get_viewport_rect()
	var pad := Vector2(8, 8)
	if get_viewport() != null:
		var safe := DisplayServer.get_display_safe_area()
		if safe.size.x > 1.0:
			pad.x = maxf(pad.x, float(safe.position.x))
			pad.y = maxf(pad.y, float(safe.position.y))
	pos.x = clampf(pos.x, vp.position.x + pad.x, vp.end.x - 48.0)
	pos.y = clampf(pos.y, vp.position.y + pad.y, vp.end.y - 32.0)
	return pos
