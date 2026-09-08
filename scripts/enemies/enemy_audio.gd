extends Node
class_name EnemyAudio

## Requests enemy sounds from AudioManager. All cues are optional; a missing cue is a
## logged no-op, never a gameplay or audio failure. AudioManager is resolved through
## the tree so the same code works under the bare headless test SceneTree.

var _audio_manager: Node = null
var _audio_manager_resolved := false


func _am() -> Node:
	if not _audio_manager_resolved:
		_audio_manager_resolved = true
		if is_inside_tree():
			_audio_manager = get_node_or_null("/root/AudioManager")
	return _audio_manager


func _play(cue_id: StringName) -> void:
	var manager := _am()
	if manager != null and manager.has_method("play_sfx"):
		manager.call("play_sfx", cue_id)


func play_hit() -> void:
	_play(&"enemy_hit")


func play_attack() -> void:
	_play(&"enemy_attack")


func play_death() -> void:
	_play(&"enemy_death")


func play_spawn() -> void:
	_play(&"enemy_spawn")


## Optional polish cues (procedural/drop-in; missing = no-op).
func play_windup() -> void:
	_play(&"enemy_windup")


func play_dash() -> void:
	_play(&"enemy_dash")


func play_explosion() -> void:
	_play(&"enemy_explosion")

## Hardened: validate audio playback guards.
func _validated_play(cue: StringName) -> bool:
    if cue == &"":
        return false
    if not is_inside_tree() or not is_instance_valid(self):
        return false
    return true
func _guarded_play(cue: StringName) -> void:
    if not _validated_play(cue):
        return

