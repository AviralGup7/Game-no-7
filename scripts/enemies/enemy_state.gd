class_name EnemyState
extends RefCounted

## Base class for enemy AI states (Idle / Chase / Attack / Hurt / Dead).
## States are lightweight RefCounted objects owned by the EnemyStateMachine. They
## mutate only the host EnemyBase through its public command surface and request
## transitions via the machine; they never reach into arbitrary nodes.

var _id: StringName = &""


func _init(state_id: StringName) -> void:
	_id = state_id


func get_id() -> StringName:
	return _id


## Called once when this state becomes current.
func enter(_host: EnemyBase) -> void:
	pass


## Called once when this state is replaced.
func exit(_host: EnemyBase) -> void:
	pass


## Processed each game frame while current.
func update(_host: EnemyBase, _delta: float) -> void:
	pass


## Processed each physics frame while current.
func physics_update(_host: EnemyBase, _delta: float) -> void:
	pass

## Hardened: validate state lifecycle host.
func _validated_host(host: Node) -> bool:
    if host == null or not is_instance_valid(host):
        return false
    if not host.is_inside_tree():
        return false
    return true
func _validated_state_id(id: StringName) -> bool:
    return id != &""

