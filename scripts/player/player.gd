extends CharacterBody3D
class_name Player

## Coordinates movement, combat, health, death, and external commands for the player.
## Composition: CharacterController (motion), HealthComponent (health), AttackController
## (attack timing), ProgressionComponent (upgrades), TargetingComponent (aim). UI and
## future weapon systems talk to THIS node through the stable command interface below.

signal move_started()
signal move_stopped()
signal attack_started()
signal attack_hit(target: Node, result: DamageResult)
signal attack_finished()
signal damaged(result: DamageResult)
signal dodged()
signal died()
signal respawned()
signal upgrade_applied(upgrade_id: StringName)

## Movement intent coming from the virtual joystick (normalized screen space).
var _move_input := Vector2.ZERO
var _control_enabled := false
var _is_dead := false
var _using_actions := true   # dev: fall back to keyboard/controller actions when no joystick input

## Component references (cached in _ready; tolerant if a scene variant omits them).
var _controller: Node = null
var _health: Node = null
var _attack: Node = null
var _progression: Node = null
var _targeting: Node = null
var _feedback: Node = null
var _player_audio: Node = null

@export var walk_speed: float = 6.0


func _ready() -> void:
	_controller = get_node_or_null("CharacterController")
	_health = get_node_or_null("HealthComponent")
	_attack = get_node_or_null("AttackController")
	_progression = get_node_or_null("ProgressionComponent")
	_targeting = get_node_or_null("TargetingComponent")
	_feedback = get_node_or_null("PlayerFeedback")
	_player_audio = get_node_or_null("PlayerAudio")
	if _health != null:
		_health.health_changed.connect(_on_health_changed)
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)
	if _attack != null:
		_attack.attack_started.connect(_on_attack_started)
		_attack.attack_finished.connect(_on_attack_finished)
		_attack.attack_hit.connect(_on_attack_hit)


func _physics_process(delta: float) -> void:
	if not _control_enabled or _is_dead:
		return
	if _using_actions:
		if Input.is_action_just_pressed("attack"):
			request_attack()
		if Input.is_action_just_pressed("dodge"):
			request_dodge()
	var move := _gather_move_input()
	if _controller != null:
		_controller.call("tick", move, delta)
	_track_move_signals(move)


func set_control_enabled(enabled: bool) -> void:
	_control_enabled = enabled
	if not enabled:
		_clear_input()


func enable_action_input(enabled: bool) -> void:
	_using_actions = enabled


## ---------- Command interface ----------

func set_move_input(input_vector: Vector2) -> void:
	_move_input = input_vector
	if _move_input.length_squared() > 1.0:
		_move_input = _move_input.normalized()


func clear_move_input() -> void:
	_move_input = Vector2.ZERO
	if _controller != null and _controller.has_method("tick"):
		_controller.call("tick", Vector2.ZERO, 0.0)


func request_attack() -> void:
	if _is_dead or not _control_enabled:
		return
	if _attack != null and _attack.has_method("request_attack"):
		_attack.call("request_attack")


func request_dodge() -> void:
	if _is_dead or not _control_enabled:
		return
	# Dodge rolls are scheduled with the combat phase; for now signal intent only.
	AudioManager.play_sfx(&"player_dodge")
	dodged.emit()


func apply_damage(payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	if _health == null or not _health.has_method("take_damage"):
		result.ignored_reason = &"no_health_component"
		return result
	if _is_dead:
		result.ignored_reason = DamageResult.IGNORE_DEAD
		return result
	var taken: Variant = _health.call("take_damage", payload)
	if taken is DamageResult:
		return taken
	result.ignored_reason = &"invalid_result"
	return result


func apply_upgrade(upgrade_id: StringName) -> void:
	if _progression != null and _progression.has_method("apply_upgrade_by_id"):
		if bool(_progression.call("apply_upgrade_by_id", upgrade_id)):
			upgrade_applied.emit(upgrade_id)
			AudioManager.play_sfx(&"upgrade_select")
			_rebuild_derived_stats()


func reset_for_new_run(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	_is_dead = false
	_control_enabled = false
	_clear_input()
	if _health != null and _health.has_method("reset"):
		_health.call("reset", 100.0)
	if _progression != null and _progression.has_method("reset"):
		_progression.call("reset")
	if _attack != null and _attack.has_method("reset_attack_state"):
		_attack.call("reset_attack_state")
	_rebuild_derived_stats()
	respawned.emit()


func _rebuild_derived_stats() -> void:
	if _controller == null or _progression == null:
		return
	var speed := walk_speed
	if _progression.has_method("get_stat"):
		speed = float(_progression.call("get_stat", &"move_speed_multiplier", walk_speed))
	if _controller.has_method("set_move_speed"):
		_controller.call("set_move_speed", speed)


func is_alive() -> bool:
	return not _is_dead


## ---------- Internal ----------

func _gather_move_input() -> Vector2:
	var v := _move_input
	if _using_actions and _move_input == Vector2.ZERO:
		var x := Input.get_axis("move_left", "move_right")
		var y := Input.get_axis("move_up", "move_down")
		v = Vector2(x, y)
		if v.length_squared() > 1.0:
			v = v.normalized()
	return v


func _track_move_signals(move: Vector2) -> void:
	if _was_moving and move == Vector2.ZERO:
		move_stopped.emit()
	elif not _was_moving and move != Vector2.ZERO:
		move_started.emit()
	_was_moving = move != Vector2.ZERO


func _clear_input() -> void:
	_move_input = Vector2.ZERO


func _on_health_changed(current: float, maximum: float) -> void:
	EventBus.player_health_changed.emit(current, maximum)


func _on_damaged(result: DamageResult) -> void:
	damaged.emit(result)
	if _feedback != null and _feedback.has_method("play_hit_feedback"):
		_feedback.call("play_hit_feedback")
	if _player_audio != null and _player_audio.has_method("play_hurt"):
		_player_audio.call("play_hurt")


func _on_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	_control_enabled = false
	_clear_input()
	died.emit()
	EventBus.player_died.emit()
	if _player_audio != null and _player_audio.has_method("play_death"):
		_player_audio.call("play_death")
	if GameRoot != null:
		GameRoot.request_game_over()


func _on_attack_started() -> void:
	attack_started.emit()
	EventBus.report_info("Player attack started")
	if _feedback != null and _feedback.has_method("play_attack_feedback"):
		_feedback.call("play_attack_feedback")
	if _player_audio != null and _player_audio.has_method("play_attack"):
		_player_audio.call("play_attack")


func _on_attack_finished() -> void:
	attack_finished.emit()


func _on_attack_hit(target: Node, result: DamageResult) -> void:
	attack_hit.emit(target, result)


func get_progression_snapshot() -> Dictionary:
	if _progression != null and _progression.has_method("get_debug_snapshot"):
		return _progression.call("get_debug_snapshot")
	return {}


func get_debug_snapshot() -> Dictionary:
	var hp: Dictionary = {}
	if _health != null and _health.has_method("get_debug_snapshot"):
		hp = _health.call("get_debug_snapshot")
	var ctl: Dictionary = {}
	if _controller != null and _controller.has_method("get_debug_snapshot"):
		ctl = _controller.call("get_debug_snapshot")
	return {
		"position": global_position,
		"health": hp,
		"controller": ctl,
		"alive": is_alive(),
		"control_enabled": _control_enabled,
		"progression": get_progression_snapshot(),
	}


var _was_moving := false
