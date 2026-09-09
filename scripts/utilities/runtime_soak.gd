class_name RuntimeSoak
extends Node

## In-run soak + device diagnostic logger. Samples FPS, enemy count, projectiles
## and player health on a timer so a 10-minute fight (or logcat on Android) has
## a paper trail without a phone in this environment. Never changes gameplay.

const INTERVAL := 5.0
const PREFIX := "[LastStand][soak]"

var _accum := 0.0
var _elapsed := 0.0
var _min_fps := 999.0
var _max_enemies := 0
var _samples := 0
var _overlay: Label = null


func _ready() -> void:
	add_to_group("runtime_soak")
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "RuntimeSoak"
	_overlay = Label.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_theme_font_size_override("font_size", 14)
	_overlay.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.7))
	_overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_overlay.add_theme_constant_override("outline_size", 4)
	_overlay.position = Vector2(12, 8)
	_overlay.visible = OS.is_debug_build()
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	layer.add_child(_overlay)
	if EventBus != null:
		if not EventBus.run_ended.is_connected(_on_run_ended):
			EventBus.run_ended.connect(_on_run_ended)
		if not EventBus.run_started.is_connected(_on_run_started):
			EventBus.run_started.connect(_on_run_started)


func _process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if GameRoot.get_current_state() not in [GameRoot.State.PLAYING, GameRoot.State.WAVE_TRANSITION]:
		return
	_elapsed += delta
	_accum += delta
	var fps := Engine.get_frames_per_second()
	if fps > 0.0:
		_min_fps = minf(_min_fps, float(fps))
	var enemies := 0
	if is_inside_tree():
		enemies = get_tree().get_nodes_in_group("enemies").size()
	_max_enemies = maxi(_max_enemies, enemies)
	if _accum < INTERVAL:
		_refresh_overlay(float(fps), enemies)
		return
	_accum = 0.0
	_samples += 1
	_emit_sample(float(fps), enemies)


func _emit_sample(fps: float, enemies: int) -> void:
	var hp := "-"
	var wave := 0
	var player := GameRoot.get_active_player()
	if player != null and is_instance_valid(player):
		var health := player.get_health_component()
		if health != null:
			hp = "%d/%d" % [ceili(health.current_health), ceili(health.max_health)]
	var run := GameRoot.get_run()
	if run != null:
		wave = run.current_wave
	var line := "%s t=%.0fs fps=%.0f min=%.0f enemies=%d peak=%d wave=%d hp=%s" % [
		PREFIX, _elapsed, fps, _min_fps, enemies, _max_enemies, wave, hp]
	print(line)
	if EventBus != null:
		EventBus.report_info(line)
	_refresh_overlay(fps, enemies)


func _refresh_overlay(fps: float, enemies: int) -> void:
	if _overlay == null or not _overlay.visible:
		return
	_overlay.text = "FPS %.0f  min %.0f  foes %d  t %.0fs" % [fps, _min_fps, enemies, _elapsed]


func _on_run_started(_id: int, _seed: int) -> void:
	_accum = 0.0
	_elapsed = 0.0
	_min_fps = 999.0
	_max_enemies = 0
	_samples = 0


func _on_run_ended(_score: int, wave: int, _best: int) -> void:
	var line := "%s END wave=%d samples=%d min_fps=%.0f peak_enemies=%d elapsed=%.0fs" % [
		PREFIX, wave, _samples, _min_fps if _min_fps < 900.0 else 0.0, _max_enemies, _elapsed]
	print(line)
	if EventBus != null:
		EventBus.report_info(line)
	InputTrace.dump("run_ended")


func get_debug_snapshot() -> Dictionary:
	return {
		"elapsed": _elapsed,
		"min_fps": _min_fps,
		"max_enemies": _max_enemies,
		"samples": _samples,
	}


func _exit_tree() -> void:
	if EventBus == null:
		return
	if EventBus.run_ended.is_connected(_on_run_ended):
		EventBus.run_ended.disconnect(_on_run_ended)
	if EventBus.run_started.is_connected(_on_run_started):
		EventBus.run_started.disconnect(_on_run_started)
