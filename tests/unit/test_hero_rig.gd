extends RefCounted
## Native import/pose/mount checks. Runs in NODE_SUITES after the tree is live.

static func suite() -> Array:
	var results: Array = []
	var scene := load(HeroRigContract.MODEL_PATH) as PackedScene
	if scene == null:
		return [{"name": "Warden imports as PackedScene", "passed": false}]
	var model := scene.instantiate() as Node3D
	var missing := HeroRigContract.missing_requirements(model)
	results.append({"name": "production rig covers complete animator contract", "passed": missing.is_empty(), "why": str(missing)})
	model.free()
	_test_directions(results)
	_test_mount_and_poses(results)
	_test_fallback(results)
	_test_materials(results)
	return results


static func _fixture() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var visual := Node3D.new()
	visual.name = &"VisualRoot"
	body.add_child(visual)
	var mount := Node3D.new()
	mount.name = &"CharacterModel"
	visual.add_child(mount)
	var primitive := MeshInstance3D.new()
	primitive.name = &"Body"
	primitive.mesh = CapsuleMesh.new()
	mount.add_child(primitive)
	var collision := CollisionShape3D.new()
	collision.name = &"CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.9
	collision.shape = capsule
	collision.position.y = 0.95
	body.add_child(collision)
	return body


static func _test_mount_and_poses(results: Array) -> void:
	var body := _fixture()
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	body.position = Vector3(2, 0, -3)
	body.rotation.y = 0.6
	var original := body.global_transform
	var collision := body.get_node("CollisionShape3D") as CollisionShape3D
	var shape := collision.shape
	var wrapper := CharacterVisuals.mount(body, &"player")
	results.append({"name": "live hero selects Warden, not silent KayKit fallback", "passed": wrapper != null and wrapper.get_meta(HeroRigContract.MODEL_PATH_META, "") == HeroRigContract.MODEL_PATH})
	if wrapper == null:
		body.free()
		return
	CharacterVisuals.start_breathing(wrapper)
	results.append({"name": "grounded hero never receives float/breathing tween", "passed": not wrapper.has_meta(CharacterVisuals.BREATHING_TWEEN_META) and wrapper.position == Vector3.ZERO})
	var animation := HeroRigContract.animation_player(wrapper)
	var skeleton := HeroRigContract.skeleton(wrapper)
	var head := skeleton.find_bone("head")
	animation.play(&"Idle", 0.0)
	animation.seek(0.2, true)
	skeleton.force_update_all_bone_transforms()
	var idle_head := skeleton.get_bone_global_pose(head).origin
	var poses_vary := true
	var clips_usable := true
	for clip in HeroRigContract.REQUIRED_CLIPS:
		var anim := animation.get_animation(clip)
		clips_usable = clips_usable and anim != null and anim.length > 0 and anim.get_track_count() > 0
		animation.play(clip, 0.0)
		animation.seek(anim.length * 0.35, true)
		skeleton.force_update_all_bone_transforms()
		for bone in range(skeleton.get_bone_count()):
			poses_vary = poses_vary and skeleton.get_bone_global_pose(bone).origin.is_finite()
	results.append({"name": "all required clips seek to finite skeletal poses", "passed": clips_usable and poses_vary})
	animation.play(&"Death_A", 0.0)
	animation.seek(animation.get_animation(&"Death_A").length, true)
	skeleton.force_update_all_bone_transforms()
	var fallen_head := skeleton.get_bone_global_pose(head).origin
	results.append({"name": "death lowers head into a fallen pose (not an idle alias)", "passed": fallen_head.y < idle_head.y * 0.65})
	animation.play(&"Idle", 0.0)
	animation.seek(0.2, true)
	skeleton.force_update_all_bone_transforms()
	results.append({"name": "idle fully resets a death pose", "passed": skeleton.get_bone_global_pose(head).origin.is_equal_approx(idle_head)})
	results.append({"name": "animation never moves physics body or resizes capsule", "passed": body.global_transform.is_equal_approx(original) and collision.shape == shape and is_equal_approx((shape as CapsuleShape3D).radius, 0.45) and is_equal_approx((shape as CapsuleShape3D).height, 1.9)})
	results.append({"name": "repeated hero mount reuses one visual", "passed": CharacterVisuals.mount(body, &"player") == wrapper})
	body.free()


static func _test_fallback(results: Array) -> void:
	var body := _fixture()
	# An importable mesh with no combat rig is just as unusable as a missing file.
	var config := {"path": "res://assets/scifi/guns/gladius.glb",
		"fallback_path": HeroRigContract.FALLBACK_PATH, "height": 1.84, "yaw": PI, "idle": "Idle"}
	var fallback := CharacterVisuals._mount_config(body, &"player", config)
	results.append({"name": "incomplete hero retries the complete KayKit rig", "passed": fallback != null and fallback.get_meta(HeroRigContract.MODEL_PATH_META, "") == HeroRigContract.FALLBACK_PATH})
	body.free()
	body = _fixture()
	config["fallback_path"] = "res://assets/scifi/guns/gladius.glb"
	var failed := CharacterVisuals._mount_config(body, &"player", config)
	var primitive := body.get_node("VisualRoot/CharacterModel/Body") as MeshInstance3D
	results.append({"name": "both failed rigs leave primitive visible and no partial mount", "passed": failed == null and primitive.visible and body.get_node_or_null("VisualRoot/CharacterModel/CharacterVisual") == null})
	body.free()


static func _test_directions(results: Array) -> void:
	for yaw in [0.0, 0.7, PI, -1.2]:
		var facing := Vector3.FORWARD.rotated(Vector3.UP, yaw)
		var right := facing.cross(Vector3.UP)
		results.append({"name": "directional dodge matches facing at yaw %s" % yaw,
			"passed": HeroRigContract.directional_dodge(facing, facing) == &"Dodge_Forward"
			and HeroRigContract.directional_dodge(facing, -facing) == &"Dodge_Backward"
			and HeroRigContract.directional_dodge(facing, right) == &"Dodge_Right"
			and HeroRigContract.directional_dodge(facing, -right) == &"Dodge_Left"})


static func _test_materials(results: Array) -> void:
	var model := (load(HeroRigContract.MODEL_PATH) as PackedScene).instantiate() as Node3D
	var mesh := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var source := mesh.get_active_material(0) as BaseMaterial3D
	results.append({"name": "native robot uses vertex palette without bitmap textures", "passed": source != null and source.albedo_texture == null and source.normal_texture == null})
	HdMaterials.polish(model, &"player", true)
	var polished := mesh.get_active_material(0) as BaseMaterial3D
	results.append({"name": "PBR maps and unit factors survive the material pass", "passed": polished != source and polished.albedo_texture == source.albedo_texture and polished.normal_texture == source.normal_texture and polished.roughness_texture == source.roughness_texture and polished.metallic_texture == source.metallic_texture and polished.roughness == source.roughness and polished.metallic == source.metallic})
	results.append({"name": "authored PBR still receives anisotropic filtering", "passed": polished.texture_filter == HdMaterials.FILTER_ANISO})
	model.free()
