class_name PlayerReactions
extends RefCounted

## Component-signal reactions for Player, extracted so the root keeps the input and
## physics contract while this module owns "what each gameplay signal looks like"
## (feedback + audio + the signals Player re-emits on its own behalf).
##
## Bound once from `_ready` with the typed component references (the
## PlayerBuild/PlayerCombat idiom). The event-bus reactions that also touch Player
## state stay on the root: the kill feeds are named by `_unbind_run_events`, and
## `_on_damaged`/`_on_died` own the death latch.

var _host: Player = null
var _health: HealthComponent = null
var _progression: ProgressionComponent = null
var _feedback: PlayerFeedback = null
var _audio: PlayerAudio = null


func bind(
	host: Player,
	health: HealthComponent,
	progression: ProgressionComponent,
	feedback: PlayerFeedback,
	audio: PlayerAudio
) -> void:
	_host = host
	_health = health
	_progression = progression
	_feedback = feedback
	_audio = audio


## Bloodlust-style heal: valid enemy kills heal the real HealthComponent.
func on_enemy_kill_heal() -> void:
	if not _host.is_alive():
		return
	var heal_amount := _progression.get_stat(&"healing_on_kill", 0.0)
	if heal_amount > 0.0:
		_health.heal(heal_amount)


func on_health_changed(current: float, maximum: float) -> void:
	EventBus.player_health_changed.emit(current, maximum)


func on_leveled_up(new_level: int) -> void:
	_host._emit_leveled_up(new_level)
	# The ExperienceComponent owns the level reward (heal + stamina) and already
	# plays the `level_up` sting; the player owns the banner. A second stacked
	# chime here only muddied the celebration, so this plays nothing.
	if EventBus != null:
		EventBus.announcement.emit(&"level_up", "Level %d!" % new_level, &"info")


func on_weapon_attack_resolved(_weapon_id: StringName, hit_count: int, was_crit: bool) -> void:
	_host._emit_attack_finished()
	if hit_count > 0 and _feedback != null:
		_feedback.play_impact_feedback(was_crit)


func on_attack_started() -> void:
	_host._emit_attack_started()
	if _feedback != null:
		_feedback.play_attack_feedback()
	if _audio != null:
		_audio.play_attack()


func on_dodge_started() -> void:
	if _audio != null:
		_audio.play_dodge()
	if _feedback != null:
		_feedback.play_dodge_feedback()
