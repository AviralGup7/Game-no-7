extends Node
class_name PlayerAudio

## Requests player-specific sounds from AudioManager. Optional cues never break
## gameplay; AudioManager already logs and no-ops for missing streams.

func play_attack() -> void:
	AudioManager.play_sfx(&"player_attack")


func play_hurt() -> void:
	AudioManager.play_sfx(&"player_hurt")


func play_dodge() -> void:
	AudioManager.play_sfx(&"player_dodge")


func play_death() -> void:
	AudioManager.play_sfx(&"player_death")


func play_upgrade() -> void:
	AudioManager.play_sfx(&"upgrade_select")


func play_pickup() -> void:
	AudioManager.play_sfx(&"pickup")
