extends Node3D
## UI test fixture: only public intent/getter contracts; no real world, AI or Main.
signal attack_started()
signal dodged()
var move_input := Vector2.ZERO
var controls_enabled := true

func _ready() -> void:
	var progression := ProgressionComponent.new()
	progression.name = "ProgressionComponent"
	add_child(progression)
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	add_child(health)
	var stamina := StaminaComponent.new()
	stamina.name = "StaminaComponent"
	add_child(stamina)
	var experience := ExperienceComponent.new()
	experience.name = "ExperienceComponent"
	add_child(experience)
	var skills := SkillController.new()
	skills.name = "SkillController"
	add_child(skills)

func is_alive() -> bool: return true
func set_control_enabled(enabled: bool) -> void: controls_enabled = enabled
func set_move_input(value: Vector2) -> void: move_input = value
func apply_upgrade(id: StringName) -> bool:
	return $ProgressionComponent.apply_upgrade_by_id(id)
func request_attack() -> void: attack_started.emit()
func request_dodge() -> bool:
	dodged.emit()
	return true
func request_weapon_switch() -> bool: return false
func request_skill(slot: int) -> bool: return $SkillController.try_cast_slot(slot)
