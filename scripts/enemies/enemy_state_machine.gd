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
# State enter/exit and signal callbacks are synchronous. Queue re-entrant
# requests so one enemy can never have two states active during one transition.
var _transitioning := false
var _queued_state: StringName = &""
var _queued_force := false


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
	return _request_state(state_id, false)


## Force a transition from any context (used by damage/death handlers). A forced
## request supersedes a normal request that is still queued.
func force_state(state_id: StringName) -> bool:
	return _request_state(state_id, true)


func _request_state(state_id: StringName, forced: bool) -> bool:
	if state_id == &"" or state_id == null:
		return false
	if _host == null or not is_instance_valid(_host):
		return false
	if not _states.has(state_id):
		_report_warning("Enemy %s: unknown state %s" % [String(_host.get_archetype_id()), String(state_id)])
		return false
	if _current != null and _current.get_id() == state_id and not _transitioning:
		return forced
	if _transitioning:
		if forced or _queued_state == &"":
			_queued_state = state_id
			_queued_force = forced
		else:
			_report_warning("Enemy %s: state %s already queued; ignoring %s" % [
				String(_host.get_archetype_id()), String(_queued_state), String(state_id)])
		return true
	return _commit_state(state_id)


func _commit_state(state_id: StringName) -> bool:
	if _current != null and _current.get_id() == state_id:
		return false
	_transitioning = true
	var previous := get_current()
	if _current != null:
		_current.exit(_host)
	_current = _states[state_id]
	_current.enter(_host)
	state_changed.emit(previous, state_id)
	if _host.has_signal("state_changed"):
		_host.emit_signal("state_changed", previous, state_id)
	_transitioning = false
	if _queued_state != &"":
		var queued := _queued_state
		_queued_state = &""
		_queued_force = false
		_commit_state(queued)
	return true


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
