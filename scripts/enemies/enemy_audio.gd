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


## Gains match the catalogue's suggested mix (-8 dB SFX bed, spawns softer since
## they arrive in bursts). Slight per-play pitch variance keeps packs of enemies
## from sounding like one machine-gunned sample. (Global RNG is auto-seeded.)
func _play(cue_id: StringName, volume_db: float = -8.0, pitch_lo: float = 0.95, pitch_hi: float = 1.05) -> bool:
	var manager := _am()
	if manager == null:
		return false
	return bool(manager.play_sfx(cue_id, volume_db, randf_range(pitch_lo, pitch_hi)))


func play_hit() -> void:
	_play(&"enemy_hit", -8.0, 0.94, 1.06)


func play_attack() -> void:
	_play(&"enemy_attack", -8.0, 0.95, 1.05)


func play_death() -> void:
	_play(&"enemy_death", -8.0, 0.9, 1.0)


func play_spawn() -> void:
	_play(&"enemy_spawn", -10.0, 0.95, 1.05)


## Optional polish cues (procedural/drop-in; missing = no-op).
func play_windup() -> void:
	if not _play(&"enemy_windup", -10.0, 0.97, 1.03):
		return
	var manager := _am()
	if manager != null:
		var host := get_parent()
		var boss_tell := host != null and host.get_node_or_null("BossController") != null
		AudioManager.duck_music(1.1 if boss_tell else 0.22, 5.0)


func play_dash() -> void:
	_play(&"enemy_dash", -10.0, 0.95, 1.05)


func play_explosion() -> void:
	_play(&"enemy_explosion", -6.0, 0.92, 1.0)
