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
	&"player":    { "path": "res://assets/characters/warden/ArenaWarden.glb", "fallback_path": "res://assets/characters/adventurers/Knight.glb", "height": 1.84, "yaw": PI, "idle": "Idle" },
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
	# /root/EventBus is the EventBus autoload by construction; the tree lookup
	# (not the global identifier) keeps this static usable in the autoload-free
	# headless harness.
	if eb != null:
		eb.report_diagnostic(message, &"warning")


## Mount the approved model for `role` under `body`'s VisualRoot/CharacterModel.
## Returns the mounted model wrapper (a Node3D) on success, or null when the actor has
## no mount / no model / an unimported model (in which case the primitive is kept).
static func mount(body: Node3D, role: StringName) -> Node3D:
	if body == null or not ROLE_MODELS.has(role):
		return null
	return _mount_config(body, role, ROLE_MODELS[role])


## Config seam keeps fallback behavior testable without deleting source files.
static func _mount_config(body: Node3D, role: StringName, cfg: Dictionary) -> Node3D:
	if body == null:
		return null
	var mount_node := body.get_node_or_null("VisualRoot/CharacterModel") as Node3D
	if mount_node == null:
		_report_mount_issue("CharacterVisuals: no VisualRoot/CharacterModel mount point for role %s (primitive kept)" % String(role))
		return null
	# Idempotent: never double-mount on a pooled/re-used actor.
	var existing := mount_node.get_node_or_null("CharacterVisual")
	if existing != null and existing.get_child_count() > 0:
		return existing as Node3D

	var path := String(cfg["path"])
	var instance := _load_compatible_model(path, role == &"player")
	if instance == null and cfg.has("fallback_path"):
		path = String(cfg["fallback_path"])
		instance = _load_compatible_model(path, role == &"player")
	if instance == null:
		return null
	var authored_hero := role == &"player" and path == HeroRigContract.MODEL_PATH

	var wrapper := Node3D.new()
	wrapper.name = &"CharacterVisual"
	wrapper.set_meta(HeroRigContract.MODEL_PATH_META, path)
	wrapper.set_meta(HeroRigContract.AUTHORED_IDLE_META, authored_hero)
	instance.name = &"Model"
	wrapper.add_child(instance)
	mount_node.add_child(wrapper)

	# Hide the source's alternate-loadout equipment BEFORE measuring: swords and
	# shields extend sideways/forward and would otherwise shrink the fit and drag
	# the visible body off the capsule axis. (PlayerEquipment repeats this rule.)
	_hide_equipment(instance as Node3D)

	var target_height := 1.78 if role == &"player" and not authored_hero else float(cfg["height"])
	var factor := _fit_factor(instance, target_height)
	if factor <= 0.0:
		# No usable geometry -> keep the primitive and tear down the mount.
		mount_node.remove_child(wrapper)
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
		mount_node.remove_child(wrapper)
		wrapper.free()
		_report_mount_issue("CharacterVisuals: model has no visible mesh bounds for role %s: %s (primitive kept)" % [String(role), path])
		return null
	var bounds := measured as AABB
	(instance as Node3D).position = Vector3(
		-bounds.get_center().x,
		-bounds.position.y,
		-bounds.get_center().z
	)

	_hide_primitive(mount_node)
	_add_ground_shadow(mount_node)
	_play_idle(instance as Node3D, String(cfg.get("idle", "")))
	# HD material pass: anisotropic filtering + role-tuned roughness/metallic so the
	# authored metal/roughness atlas remains physically distinct under arena lighting.
	HdMaterials.polish(instance as Node3D, role, authored_hero)
	# The Warden has baked, grounded idle motion. Never add a whole-body float tween.
	if role == &"player":
		start_breathing(wrapper)
	return wrapper


## Validate while detached. An incomplete rig must never hide the visible fallback.
static func _load_compatible_model(path: String, require_combat: bool) -> Node3D:
	if not ResourceLoader.exists(path):
		_report_mount_issue("CharacterVisuals: model missing: %s (trying fallback)" % path)
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		_report_mount_issue("CharacterVisuals: model failed to import: %s (trying fallback)" % path)
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		_report_mount_issue("CharacterVisuals: model root is not a Node3D: %s (trying fallback)" % path)
		return null
	if require_combat:
		var missing := HeroRigContract.missing_requirements(instance)
		if not missing.is_empty():
			instance.free()
			_report_mount_issue("CharacterVisuals: incomplete hero %s: %s (trying fallback)" % [path, ", ".join(missing)])
			return null
	_hide_equipment(instance as Node3D)
	if _fit_factor(instance as Node3D, 1.0) <= 0.0:
		instance.free()
		_report_mount_issue("CharacterVisuals: model has no usable geometry: %s (trying fallback)" % path)
		return null
	return instance as Node3D


## Play a looping idle clip when the imported rig exposes one; otherwise no-op.
## The loop flag is forced (same as EnemyAnimator) so the fallback idle never
## plays once and freezes on the last frame when no animator drives the rig.
static func _play_idle(root: Node3D, clip: String) -> void:
	if clip.is_empty():
		return
	for player in root.find_children("*", "AnimationPlayer", true, false):
		var anim_player := player as AnimationPlayer
		if anim_player == null or not anim_player.has_animation(StringName(clip)):
			continue
		# A PackedScene's library is shared by all instances. Make idle private
		# before changing its loop mode (including the mount's pre-bind autoplay).
		for library_name in anim_player.get_animation_library_list():
			var source_library := anim_player.get_animation_library(library_name)
			for name in source_library.get_animation_list():
				var full_name := String(name) if library_name == &"" else String(library_name) + "/" + String(name)
				if full_name != clip:
					continue
				var library := source_library.duplicate() as AnimationLibrary
				var idle := source_library.get_animation(name).duplicate() as Animation
				idle.loop_mode = Animation.LOOP_LINEAR
				library.remove_animation(name)
				library.add_animation(name, idle)
				anim_player.remove_animation_library(library_name)
				anim_player.add_animation_library(library_name, library)
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
	if bool(wrapper.get_meta(HeroRigContract.AUTHORED_IDLE_META, false)):
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
static func _hide_primitive(mount_node: Node3D) -> void:
	var body := mount_node.get_node_or_null("Body")
	if body is MeshInstance3D:
		body.visible = false
		return
	# Some archetype scenes nest the primitive deeper under CharacterModel.
	for m in mount_node.find_children("Body", "MeshInstance3D", false, false):
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
