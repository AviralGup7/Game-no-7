class_name CharacterVisuals
extends RefCounted

## Replaces the live primitive capsule/box "actors" with the approved, checksum-locked
## character models from assets/catalog.json, mounted under each actor's existing
## `VisualRoot/CharacterModel` mount so the gameplay-facing `VisualRoot` semantics
## (facing via rotation.y, per-archetype `visual_scale`) are completely unchanged.
##
## Every mount is runtime + defensive:
##  - Falls back to the existing primitive if a model is missing/not imported.
##  - Fits each model to a nominal height and grounds its feet, keeping the physics
##    capsule authoritative.
##  - Rotates authored glTF +Z ("model forward") onto Godot's -Z so the existing
##    look_at / yaw-facing code points the model the right way.
##  - Loops a per-role idle clip when the imported rig exposes one, otherwise stands.
##
## No download, no engine-importer assumptions beyond ResourceLoader.load(PackedScene)
## (which the import smoke test already verifies for every model).

const ROLE_MODELS := {
	# role / archetype -> { path, height (m, before visual_scale), yaw (rad), idle }
	&"player":    { "path": "res://assets/characters/adventurers/Knight.glb",   "height": 1.78, "yaw": PI, "idle": "Idle" },
	&"basic":     { "path": "res://assets/characters/skeletons/Skeleton_Minion.glb",  "height": 1.72, "yaw": PI, "idle": "Idle" },
	&"fast":      { "path": "res://assets/characters/skeletons/Skeleton_Rogue.glb",   "height": 1.70, "yaw": PI, "idle": "Idle" },
	&"heavy":     { "path": "res://assets/characters/skeletons/Skeleton_Warrior.glb", "height": 1.95, "yaw": PI, "idle": "Idle" },
	&"ranged":    { "path": "res://assets/characters/skeletons/Skeleton_Mage.glb",    "height": 1.72, "yaw": PI, "idle": "Idle" },
	&"dasher":    { "path": "res://assets/characters/creatures/Rat.glb",              "height": 0.85, "yaw": PI, "idle": "RatArmature|Rat_Idle" },
	&"splitter":  { "path": "res://assets/characters/creatures/Spider.glb",           "height": 1.00, "yaw": PI, "idle": "SpiderArmature|Spider_Idle" },
	&"exploder":  { "path": "res://assets/characters/monsters/Demon.gltf",            "height": 1.65, "yaw": PI, "idle": "Idle" },
	&"warlord":   { "path": "res://assets/characters/monsters/BlueDemon.gltf",        "height": 2.45, "yaw": PI, "idle": "Idle" },
}


## True when `role` has approved source art that should be mounted.
static func has_model(role: StringName) -> bool:
	return ROLE_MODELS.has(role)


## Mount the approved model for `role` under `body`'s VisualRoot/CharacterModel.
## Returns the mounted model wrapper (a Node3D) on success, or null when the actor has
## no mount / no model / an unimported model (in which case the primitive is kept).
static func mount(body: Node3D, role: StringName) -> Node3D:
	if body == null or not ROLE_MODELS.has(role):
		return null
	var cfg: Dictionary = ROLE_MODELS[role]
	var mount := body.get_node_or_null("VisualRoot/CharacterModel") as Node3D
	if mount == null:
		return null
	# Idempotent: never double-mount on a pooled/re-used actor.
	var existing := mount.get_node_or_null(&"CharacterVisual")
	if existing != null and existing.get_child_count() > 0:
		return existing as Node3D

	var scene := load(String(cfg["path"]))
	if scene == null or not scene is PackedScene:
		return null
	var instance := (scene as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		return null

	var wrapper := Node3D.new()
	wrapper.name = &"CharacterVisual"
	instance.name = &"Model"
	wrapper.add_child(instance)
	mount.add_child(wrapper)

	var factor := _fit_factor(instance, float(cfg["height"]))
	if factor <= 0.0:
		# No usable geometry -> keep the primitive and tear down the mount.
		mount.remove_child(wrapper)
		wrapper.free()
		return null

	# Bake our orientation + scale on the model child only; VisualRoot keeps its own
	# gameplay-facing rotation/scale. Ground the feet and centre the footprint on XZ.
	(instance as Node3D).rotation.y = float(cfg["yaw"])
	(instance as Node3D).scale = Vector3.ONE * factor
	var bounds := _bounds(instance as Node3D, Transform3D.IDENTITY)
	(instance as Node3D).position = Vector3(
		-bounds.get_center().x * factor,
		-bounds.position.y * factor,
		-bounds.get_center().z * factor
	)

	_hide_primitive(mount)
	_play_idle(instance as Node3D, String(cfg.get("idle", "")))
	return wrapper


## Play a looping idle clip when the imported rig exposes one; otherwise no-op.
static func _play_idle(root: Node3D, clip: String) -> void:
	if clip.is_empty():
		return
	for player in root.find_children("*", "AnimationPlayer", true, false):
		if (player as AnimationPlayer).has_animation(StringName(clip)):
			(player as AnimationPlayer).play(StringName(clip))
			return


## Hide the primitive body mesh that the model replaces (visible=false keeps the node).
static func _hide_primitive(mount: Node3D) -> void:
	var body := mount.get_node_or_null("Body")
	if body is MeshInstance3D:
		body.visible = false
		return
	# Some archetype scenes nest the primitive deeper under CharacterModel.
	for m in mount.find_children("Body", "MeshInstance3D", false, false):
		m.visible = false


static func _fit_factor(instance: Node3D, target_height: float) -> float:
	var bounds := _bounds(instance, Transform3D.IDENTITY)
	if bounds.size.y <= 0.0001 or target_height <= 0.01:
		return 0.0
	return target_height / bounds.size.y


static func _bounds(node: Node3D, parent_xform: Transform3D) -> AABB:
	var local := parent_xform
	if node is Node3D:
		local = parent_xform * (node as Node3D).transform
	var out: AABB = AABB()
	var have := false
	if node is MeshInstance3D and node.mesh != null:
		out = local * (node as MeshInstance3D).mesh.get_aabb()
		have = true
	for child in node.get_children():
		var child_b := _bounds(child, local)
		if child_b.size != Vector3.ZERO or child is MeshInstance3D:
			if not have:
				out = child_b
				have = true
			else:
				out = out.merge(child_b)
	return out
