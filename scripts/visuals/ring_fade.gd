extends Node3D
## One-shot feedback ring: expands + fades out, then hides itself for pooling.
## Driven only while a ring is alive, so pooled idle rings cost nothing.

var _active := false
var _elapsed := 0.0
var _duration := 0.6
var _base_scale := 1.0


func _ready() -> void:
	# Idle pooled rings are inert; process only runs while one is animating.
	set_process(false)


func trigger(duration: float) -> void:
	_duration = maxf(duration, 0.05)
	_elapsed = 0.0
	_base_scale = scale.x
	_active = true
	visible = true
	# Reset material alpha so reused pooled rings do not start invisible for one frame.
	var mi := get_node_or_null(&"Disc") as MeshInstance3D
	if mi != null and mi.material_override is StandardMaterial3D:
		var mat := mi.material_override as StandardMaterial3D
		var c: Color = mat.albedo_color
		c.a = 0.45
		mat.albedo_color = c
	set_process(true)


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	# Gentle expansion then dissolve.
	var grow := 1.0 + 0.35 * t
	scale = Vector3(_base_scale * grow, _base_scale * grow, _base_scale * grow)
	var mi := get_node_or_null(&"Disc") as MeshInstance3D
	if mi != null and mi.material_override is StandardMaterial3D:
		var mat := mi.material_override as StandardMaterial3D
		var c: Color = mat.albedo_color
		c.a = 0.45 * (1.0 - t)
		mat.albedo_color = c
	if t >= 1.0:
		_active = false
		visible = false
		set_process(false)

## Hardened: clamp fade time.
func _validated_fade_time(t: float) -> float:
    if not is_finite(t) or t <= 0.0:
        return 0.5
    return clampf(t, 0.05, 5.0)

