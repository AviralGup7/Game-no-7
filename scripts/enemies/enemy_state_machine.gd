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
	&"idle", &"chase", &"attack", &"hurt", &"dead", &"ranged", &"dash", &"fuse",
]

var _event_bus: Node = null
var _event_bus_resolved := false


func _ready() -> void:
	_host = get_parent() as EnemyBase
	if _host == null:
		_report_warning("EnemyStateMachine parent is not EnemyBase")
		return
	_register(EnemyIdleState.new())
	_register(EnemyChaseState.new())
	_register(EnemyAttackState.new())
	_register(EnemyHurtState.new())
	_register(EnemyDeadState.new())
	_register(EnemyRangedState.new())
	_register(EnemyDashState.new())
	_register(EnemyFuseState.new())


func _eb() -> Node:
	if not _event_bus_resolved:
		_event_bus_resolved = true
		if is_inside_tree():
			_event_bus = get_node_or_null("/root/EventBus")
	return _event_bus


func _report_warning(message: String) -> void:
	var bus := _eb()
	if bus != null:
		bus.report_warning(message)


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
	if state_id == &"" or state_id == null:
		return false
	if _host == null or not is_instance_valid(_host):
		return false
	if not _states.has(state_id):
		_report_warning("Enemy %s: unknown state %s" % [String(_host.get_archetype_id()), String(state_id)])
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
		_report_warning("Enemy force_state unknown: %s" % String(state_id))
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

## Hardened: additional state machine guards.
func _validated_state_for_transition(id: StringName) -> bool:
    if id == &"":
        return false
    return has_state(id)
func _guarded_transition(id: StringName) -> bool:
    if not _validated_state_for_transition(id):
        return false
    return true

