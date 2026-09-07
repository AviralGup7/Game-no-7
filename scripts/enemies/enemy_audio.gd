extends Node
class_name EnemyAudio

## Requests enemy sounds from AudioManager. All cues are optional; a missing cue is a
## logged no-op, never a gameplay or audio failure.

func play_hit() -> void:
	AudioManager.play_sfx(&"enemy_hit")


func play_attack() -> void:
	AudioManager.play_sfx(&"enemy_attack")


func play_death() -> void:
	AudioManager.play_sfx(&"enemy_death")


func play_spawn() -> void:
	AudioManager.play_sfx(&"enemy_spawn")
