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


## Source path of the approved model for `role` ("" when none) — for diagnostics.
static func model_path(role: StringName) -> String:
	if not ROLE_MODELS.has(role):
		return ""
	return String((ROLE_MODELS[role] as Dictionary).get("path", ""))


## Diagnose a failed/aborted mount. Failure is never fatal: the actor keeps its
## primitive fallback; the message is pushed as a warning (always visible in
## device logs) AND mirrored into the EventBus diagnostic feed when available.
static func _report_mount_issue(message: String) -> void:
	push_warning(message)
	# EventBus is an autoload: resolve it through the tree so this static stays
	# safe in minimal/headless contexts that lack the singletons.
	var eb: Node = null
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		eb = (loop as SceneTree).root.get_node_or_null("/root/EventBus")
	if eb != null and eb.has_method("report_diagnostic"):
		eb.call("report_diagnostic", message, &"warning")


## Mount the approved model for `role` under `body`'s VisualRoot/CharacterModel.
## Returns the mounted model wrapper (a Node3D) on success, or null when the actor has
## no mount / no model / an unimported model (in which case the primitive is kept).
static func mount(body: Node3D, role: StringName) -> Node3D:
	if body == null or not ROLE_MODELS.has(role):
		return null
	var cfg: Dictionary = ROLE_MODELS[role]
	var mount := body.get_node_or_null("VisualRoot/CharacterModel") as Node3D
	if mount == null:
		_report_mount_issue("CharacterVisuals: no VisualRoot/CharacterModel mount point for role %s (primitive kept)" % String(role))
		return null
	# Idempotent: never double-mount on a pooled/re-used actor.
	var existing := mount.get_node_or_null("CharacterVisual")
	if existing != null and existing.get_child_count() > 0:
		return existing as Node3D

	var path := String(cfg["path"])
	if not ResourceLoader.exists(path):
		_report_mount_issue("CharacterVisuals: model missing for role %s: %s (primitive kept)" % [String(role), path])
		return null
	var scene := load(path)
	if scene == null or not scene is PackedScene:
		_report_mount_issue("CharacterVisuals: model failed to import for role %s: %s (primitive kept)" % [String(role), path])
		return null
	var instance := (scene as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		_report_mount_issue("CharacterVisuals: model root is not a Node3D for role %s: %s (primitive kept)" % [String(role), path])
		return null

	var wrapper := Node3D.new()
	wrapper.name = &"CharacterVisual"
	instance.name = &"Model"
	wrapper.add_child(instance)
	mount.add_child(wrapper)

	# Hide the source's alternate-loadout equipment BEFORE measuring: swords and
	# shields extend sideways/forward and would otherwise shrink the fit and drag
	# the visible body off the capsule axis. (PlayerEquipment repeats this rule.)
	_hide_equipment(instance as Node3D)

	var factor := _fit_factor(instance, float(cfg["height"]))
	if factor <= 0.0:
		# No usable geometry -> keep the primitive and tear down the mount.
		mount.remove_child(wrapper)
		wrapper.free()
		_report_mount_issue("CharacterVisuals: model has no usable geometry for role %s: %s (primitive kept)" % [String(role), path])
		return null

	# Bake our orientation + scale on the model child only; VisualRoot keeps its own
	# gameplay-facing rotation/scale. Ground the feet and centre the footprint on XZ.
	(instance as Node3D).rotation.y = float(cfg["yaw"])
	(instance as Node3D).scale = Vector3.ONE * factor
	# Bounds are measured AFTER scale/rotation, so they are already in final
	# wrapper-space units: centre/ground them directly (a second `* factor` here
	# would double-count the scale and offset the body off the capsule).
	var measured: Variant = _bounds(instance as Node3D, Transform3D.IDENTITY)
	if measured == null:
		mount.remove_child(wrapper)
		wrapper.free()
		_report_mount_issue("CharacterVisuals: model has no visible mesh bounds for role %s: %s (primitive kept)" % [String(role), path])
		return null
	var bounds := measured as AABB
	(instance as Node3D).position = Vector3(
		-bounds.get_center().x,
		-bounds.position.y,
		-bounds.get_center().z
	)

	_hide_primitive(mount)
	_add_ground_shadow(mount)
	_play_idle(instance as Node3D, String(cfg.get("idle", "")))
	# Subtle breathing bob keeps the hero alive even when idle (pure visual, no gameplay).
	if role == &"player":
		start_breathing(wrapper)
	return wrapper


## Play a looping idle clip when the imported rig exposes one; otherwise no-op.
## The loop flag is forced (same as EnemyAnimator) so the fallback idle never
## plays once and freezes on the last frame when no animator drives the rig.
static func _play_idle(root: Node3D, clip: String) -> void:
	if clip.is_empty():
		return
	for player in root.find_children("*", "AnimationPlayer", true, false):
		var anim_player := player as AnimationPlayer
		if anim_player != null and anim_player.has_animation(StringName(clip)):
			var anim := anim_player.get_animation(StringName(clip))
			if anim != null and anim.loop_mode == Animation.LOOP_NONE:
				anim.loop_mode = Animation.LOOP_LINEAR
			anim_player.play(StringName(clip))
			return


## Hide alternate-loadout equipment meshes (KayKit adventurers ship swords and
## shields as part of the character model). Runs before fit/ground math so hidden
## steel cannot shrink the fit or offset the visible body off the capsule axis.
static func _hide_equipment(root: Node3D) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_name := String((node as Node).name)
		if "Sword" in mesh_name or "Shield" in mesh_name:
			(node as MeshInstance3D).hide()


static func _add_ground_shadow(parent: Node3D) -> void:
	if parent == null or parent.get_node_or_null("GroundShadow") != null:
		return
	# Soft dark disc under feet — grounds the model without a real shadow map (mobile-safe).
	# Parented to the mount (not the bobbing wrapper) so the shadow stays planted.
	var decal := MeshInstance3D.new()
	decal.name = "GroundShadow"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.45
	disc.bottom_radius = 0.45
	disc.height = 0.02
	disc.radial_segments = 12
	decal.mesh = disc
	decal.position = Vector3(0, 0.015, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0, 0, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	decal.material_override = mat
	parent.add_child(decal)


const BREATHING_TWEEN_META := &"breathing_tween"


## Idle breathing bob (looping tween, no bones). Idempotent; safe off-tree.
static func start_breathing(wrapper: Node3D) -> void:
	if wrapper == null or not is_instance_valid(wrapper):
		return
	if wrapper.has_meta(BREATHING_TWEEN_META):
		return
	if not wrapper.is_inside_tree():
		return
	# Tiny scripted bob via a lightweight tween (no bones) — keeps idle from feeling frozen.
	var tween := wrapper.create_tween()
	tween.set_loops()
	tween.tween_property(wrapper, "position:y", 0.04, 1.1).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(wrapper, "position:y", -0.04, 1.1).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	wrapper.set_meta(BREATHING_TWEEN_META, tween)


## Freeze the idle bob and replant the wrapper (death poses must rest).
static func stop_breathing(wrapper: Node3D) -> void:
	if wrapper == null or not is_instance_valid(wrapper):
		return
	if wrapper.has_meta(BREATHING_TWEEN_META):
		var tween: Variant = wrapper.get_meta(BREATHING_TWEEN_META)
		if tween is Tween and (tween as Tween).is_valid():
			(tween as Tween).kill()
		wrapper.remove_meta(BREATHING_TWEEN_META)
	wrapper.position.y = 0.0


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
	var bounds: Variant = _bounds(instance, Transform3D.IDENTITY)
	if bounds == null:
		return 0.0
	var box := bounds as AABB
	if box.size.y <= 0.0001 or target_height <= 0.01:
		return 0.0
	return target_height / box.size.y


## Union of the VISIBLE mesh bounds under `node`, or null when nothing renders.
## Hidden equipment and mesh-less placeholders never pollute the fit/ground math.
## Imported rigs also contain non-spatial Nodes (e.g. AnimationPlayer): traverse
## those safely; only Node3D contributes a transform.
static func _bounds(node: Node, parent_xform: Transform3D) -> Variant:
	var local := parent_xform
	if node is Node3D:
		local = parent_xform * (node as Node3D).transform
	var out: Variant = null
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.visible:
			out = local * mesh_instance.mesh.get_aabb()
	for child in node.get_children():
		var child_bounds: Variant = _bounds(child, local)
		if child_bounds == null:
			continue
		if out == null:
			out = child_bounds
		else:
			out = (out as AABB).merge(child_bounds as AABB)
	return out

## Hardened: validate model id before mounting.
func _validated_model_id(id: StringName) -> bool:
	if id == &"" or id == &"uninitialized":
		return false
	return has_model(id)

