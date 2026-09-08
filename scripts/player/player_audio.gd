extends Node
class_name PlayerAudio

## Requests player-specific sounds from AudioManager. Optional cues never break
## gameplay; AudioManager already logs and no-ops for missing streams.

@export var step_distance: float = 1.8
@export var walk_step_distance: float = 0.9
@export var low_health_threshold: float = 0.25
var _step_travel := 0.0
var _low_health := false
var _player: Player
var _weapons: WeaponManager
var _dodge: DodgeController


func _ready() -> void:
	_player = get_parent() as Player
	_dodge = _player.get_node_or_null("DodgeController") as DodgeController
	_weapons = _player.get_node_or_null("WeaponManager") as WeaponManager
	if _weapons != null:
		_weapons.weapon_switched_local.connect(_on_switch)
		_weapons.reload_started.connect(_on_reload)
	var health := _player.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		health.health_changed.connect(_on_health)
	EventBus.projectile_fired.connect(_on_shot)


func _physics_process(delta: float) -> void:
	if not _player.is_control_enabled() or not _player.is_on_floor() or (_dodge != null and _dodge.is_dodging()):
		_step_travel = 0.0
		return
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if speed < 0.15:
		_step_travel = 0.0
		return
	_step_travel += speed * delta
	var stride := maxf(walk_step_distance if speed < 3.0 else step_distance, 0.2)
	if _step_travel >= stride:
		_step_travel = fmod(_step_travel, stride)
		AudioManager.play_sfx(&"player_step", -16.0)


func _on_switch(_old: StringName, _new: StringName) -> void:
	AudioManager.play_sfx(&"player_switch", -8.0)


func _on_reload(_id: StringName) -> void:
	AudioManager.play_sfx(&"player_reload", -8.0)


func _on_shot(source: Node, _id: StringName) -> void:
	if source == _player:
		AudioManager.play_sfx(&"player_shot", -8.0, 1.25)


func _on_health(current: float, maximum: float) -> void:
	var low := current > 0.0 and current / maxf(maximum, 1.0) <= low_health_threshold
	if low and not _low_health:
		AudioManager.play_sfx(&"player_low_health", -12.0)
	_low_health = low


func play_attack() -> void:
	var inst := _weapons.active_instance() if _weapons != null else null
	if inst == null or inst.config.is_melee():
		var step := inst.combo_step if inst != null else 1
		AudioManager.play_sfx(&"player_attack", -8.0, 1.0 + 0.04 * (step - 1))


func play_hurt() -> void:
	AudioManager.play_sfx(&"player_hurt", -8.0)


func play_dodge() -> void:
	AudioManager.play_sfx(&"player_dodge", -8.0)


func play_death() -> void:
	AudioManager.play_sfx(&"player_death", -8.0)


func play_upgrade() -> void:
	AudioManager.play_sfx(&"upgrade_select")


func play_pickup() -> void:
	AudioManager.play_sfx(&"pickup")

## Hardened: validate audio cue.
func _validated_cue(cue: StringName) -> bool:
    return cue != &""

