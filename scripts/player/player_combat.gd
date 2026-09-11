class_name PlayerCombat
extends RefCounted

## Attack / dodge / weapon-switch commands extracted from Player. Player stays the
## public facade (`request_attack`, `request_dodge`, `request_weapon_switch`) and
## still owns aim + lock-on so those input pins remain on the orchestrator.
##
## Typed refs only: no `get_node_or_null` on the command path. Headless fixtures
## that skip `bind()` are no-ops (request_* return false).

var buffer := AttackBuffer.new()
var buffer_seconds: float = 0.18

var _host: Player = null
var _weapons: WeaponManager = null
var _dodge: DodgeController = null
var _controller: CharacterController = null
var _stamina: StaminaComponent = null
var _locomotion: PlayerLocomotion = null


func bind(
	host: Player,
	weapons: WeaponManager,
	dodge: DodgeController,
	controller: CharacterController,
	stamina: StaminaComponent,
	locomotion: PlayerLocomotion,
	shared_buffer: AttackBuffer = null
) -> void:
	_host = host
	_weapons = weapons
	_dodge = dodge
	_controller = controller
	_stamina = stamina
	_locomotion = locomotion
	if shared_buffer != null:
		buffer = shared_buffer


func can_act() -> bool:
	if _host == null:
		return false
	return _host.is_control_enabled() and not _is_stunned()


func _is_stunned() -> bool:
	if _host == null:
		return false
	var status := _host.get_status_manager()
	return status != null and status.is_stunned()


## Start a swing if the weapon can accept it. Aim + attack_started stay on Player
## so the orchestrator still owns facing and presentation.
func try_start() -> bool:
	if not can_act():
		return false
	if _dodge != null and _dodge.is_dodging():
		return false
	if _weapons == null or _weapons.active_instance() == null:
		return false
	return _weapons.request_attack() > 0


## Accept an attack command: fire now, or buffer the press. Returns true when the
## command is accepted (including a buffered press), matching Player.request_attack.
func request_attack(attempt: Callable) -> bool:
	if not can_act():
		return false
	buffer.clear()
	var started := false
	if attempt.is_valid():
		started = bool(attempt.call())
	if not started:
		buffer.push(maxf(buffer_seconds, 0.0))
	return true


func request_dodge() -> bool:
	if not can_act() or _dodge == null:
		return false
	if not _dodge.is_ready():
		return false
	if not _dodge.can_interrupt_attack and is_busy():
		return false
	var cost := maxf(_dodge.stamina_cost, 0.0)
	if _stamina != null and not _stamina.try_spend(cost):
		return false
	var dir := Vector3.FORWARD
	if _host != null:
		dir = -_host.global_basis.z
	if _locomotion != null and _controller != null:
		var world := _controller.screen_to_world_dir(_locomotion.gather())
		if world.length_squared() > 0.0001:
			dir = world
	var started := _dodge.request(dir)
	if started:
		cancel()
		if _controller != null:
			_controller.face_direction(dir)
	elif _stamina != null:
		_stamina.restore(cost)
	return started


func request_weapon_switch() -> bool:
	if not can_act() or _weapons == null:
		return false
	if _dodge != null and _dodge.is_dodging():
		return false
	var switched := _weapons.cycle_weapon()
	if switched:
		buffer.clear()
	return switched


func is_busy() -> bool:
	if _weapons == null:
		return false
	var inst := _weapons.active_instance()
	return inst != null and (inst.phase == WeaponInstance.PHASE_WINDUP or inst.phase == WeaponInstance.PHASE_RECOVERY)


func cancel() -> void:
	buffer.clear()
	if _weapons != null:
		_weapons.cancel_in_progress()
