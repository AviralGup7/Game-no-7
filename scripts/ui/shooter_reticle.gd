class_name ShooterReticle
extends Control

## Lightweight world-projected aim indicator. No input capture or combat authority.
## A ring fills while the current gun reloads; UI remains hidden outside a run.
var _point := Vector2.ZERO
var _show := false
var _locked := false
var _reload := -1.0


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	_show = false
	_reload = -1.0
	if GameRoot.get_current_state() not in [GameRoot.State.PLAYING, GameRoot.State.WAVE_TRANSITION]:
		queue_redraw()
		return
	var player := GameRoot.get_active_player()
	var camera := get_viewport().get_camera_3d()
	if player == null or camera == null or not player.is_alive():
		queue_redraw()
		return
	var manager := player.get_weapon_manager()
	var inst := manager.active_instance()
	if inst == null:
		queue_redraw()
		return
	var target := player.get_aim_target()
	_locked = target != null
	var aim := player.global_position - player.global_basis.z * minf(inst.effective_range(), 8.0) + Vector3.UP
	if target != null:
		aim = target.global_position + Vector3.UP * 0.8
		var shape := target.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape != null:
			aim = shape.global_position
	if not camera.is_position_behind(aim):
		_point = camera.unproject_position(aim) - global_position
		_show = Rect2(Vector2.ZERO, size).has_point(_point)
	if inst.is_reloading():
		_reload = clampf(1.0 - inst.reload_remaining() / maxf(inst.config.reload_seconds, 0.01), 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if not _show:
		return
	var color := Color(1.0, 0.55, 0.2) if _locked else Color(0.25, 0.85, 1.0)
	for axis in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(_point + axis * 5.0, _point + axis * 12.0, Color(0, 0, 0, 0.8), 4.0, true)
		draw_line(_point + axis * 5.0, _point + axis * 12.0, color, 2.0, true)
	draw_circle(_point, 1.5, color)
	if _reload >= 0.0:
		draw_arc(_point, 18.0, -PI * 0.5, -PI * 0.5 + TAU * _reload, 32, color, 2.0, true)
