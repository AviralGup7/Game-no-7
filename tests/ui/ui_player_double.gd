extends Player
## UI test fixture: a REAL Player built in code — same class, same typed component
## contract as player.tscn, but with no world, AI or Main. This keeps the UI suites
## exercising the exact typed Player API (and GameRoot's Player-typed active-player
## reference) instead of a parallel duck-typed stand-in.
##
## REQUIRED components are all present (see the required/optional table in
## player.gd / docs/ARCHITECTURE.md); genuinely optional presentation components
## (PlayerFeedback, PlayerAudio, legacy AttackController) stay absent on purpose —
## exactly the optionality the architecture allows.

func _ready() -> void:
	_add_component("CharacterController", CharacterController.new())
	_add_component("HealthComponent", HealthComponent.new())
	_add_component("ProgressionComponent", ProgressionComponent.new())
	_add_component("TargetingComponent", TargetingComponent.new())
	_add_component("DodgeController", DodgeController.new())
	_add_component("StaminaComponent", StaminaComponent.new())
	_add_component("ExperienceComponent", ExperienceComponent.new())
	_add_component("WeaponManager", WeaponManager.new())
	_add_component("StatusManager", StatusManager.new())
	_add_component("SkillController", SkillController.new())
	super._ready()


func _add_component(node_name: String, node: Node) -> void:
	node.name = node_name
	add_child(node)
