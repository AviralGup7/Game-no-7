class_name EnemyStateMachine
extends Node

## Owns enemy state transitions. Registers one instance per EnemyState id and keeps
## exactly one current state. All transitions route through change_to() so lifecycle
## (exit -> swap -> enter) and bookkeeping happen in one place. Invalid transitions
## are rejected with a diagnostic, never thrown.

signal state_changed(previous_state: StringName, current_state: StringName)

var _states: Dictionary = {}        # StringName -> EnemyState
var _current: EnemyState = null
var _host: EnemyBase = null

const STATE_IDS := [
	&"idle", &"chase", &"attack", &"hurt", &"dead",
]


func _ready() -> void:
	_host = get_parent() as EnemyBase
	if _host == null:
		EventBus.report_warning("EnemyStateMachine parent is not EnemyBase")
		return
	_register(EnemyIdleState.new())
	_register(EnemyChaseState.new())
	_register(EnemyAttackState.new())
	_register(EnemyHurtState.new())
	_register(EnemyDeadState.new())


func _register(state: EnemyState) -> void:
	_states[state.get_id()] = state


func get_host() -> EnemyBase:
	return _host


func get_current() -> StringName:
	if _current == null:
		return &""
	return _current.get_id()


func has_state(state_id: StringName) -> bool:
	return _states.has(state_id)


## Change to `state_id`. Returns false when unknown or already current.
func change_to(state_id: StringName) -> bool:
	if _host == null:
		return false
	if not _states.has(state_id):
		EventBus.report_warning("Enemy %s: unknown state %s" % [String(_host.get_archetype_id()), String(state_id)])
		return false
	if _current != null and _current.get_id() == state_id:
		return false
	var previous := get_current()
	if _current != null:
		_current.exit(_host)
	_current = _states[state_id]
	_current.enter(_host)
	state_changed.emit(previous, state_id)
	if _host.has_signal("state_changed"):
		_host.emit_signal("state_changed", previous, state_id)
	return true


## Force a transition from any context (used by damage/death handlers).
func force_state(state_id: StringName) -> bool:
	if not _states.has(state_id):
		EventBus.report_warning("Enemy force_state unknown: %s" % String(state_id))
		return false
	if _current != null and _current.get_id() == state_id:
		return true
	return change_to(state_id)


func update(delta: float) -> void:
	if _current == null:
		return
	_current.update(_host, delta)


func physics_update(delta: float) -> void:
	if _current == null:
		return
	_current.physics_update(_host, delta)


## Stop the machine without emitting (used during teardown).
func stop() -> void:
	_current = null
	_states.clear()
