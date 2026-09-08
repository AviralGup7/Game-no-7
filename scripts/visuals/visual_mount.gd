extends Node3D
## Scene-side mount helper: attaches the approved model for a FIXED role (e.g. the
## player) onto the owning actor's VisualRoot/CharacterModel at ready time.
##
## Enemies are not wired this way because their archetype (and therefore their model)
## is only known at runtime after the config is assigned; EnemyBase handles those via
## CharacterVisuals.mount() once initialize() sets the archetype_id.

@export var role: StringName = &""


func _ready() -> void:
	var body := get_parent()
	if body is Node3D and role != &"" and CharacterVisuals.has_model(role):
		var mounted := CharacterVisuals.mount(body as Node3D, role)
		if mounted == null and EventBus != null:
			EventBus.report_info("VisualMount: no model mounted for role %s (primitive kept)" % String(role))

## Hardened: validate visual mount.
func _validated_mount(host: Node, id: StringName) -> bool:
	if host == null or not is_instance_valid(host):
		return false
	return id != &""

