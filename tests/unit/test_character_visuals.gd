extends RefCounted

## Exercises the approved-model mounting path (scripts/visuals/character_visuals.gd)
## with off-tree nodes so no live scene or autoload is required. Real imported rigs
## are only exercised for a small, representative role; everything else checks the
## defensive fallbacks (no model role / no mount / idempotency).

static func suite() -> Array:
	var results: Array = []
	# 1) No-model role keeps the primitive and returns null.
	var body1 := _make_body()
	var r1 := CharacterVisuals.mount(body1, &"no_such_role")
	results.append({"name": "unknown role keeps primitive", "passed": r1 == null})
	if body1 != null:
		body1.free()

	# 2) Body without a CharacterModel mount is safe (no crash, null).
	var bare := Node3D.new()
	var r2 := CharacterVisuals.mount(bare, &"basic")
	results.append({"name": "no mount node returns null", "passed": r2 == null})
	bare.free()

	# 3) A real role mounts the approved model and hides the primitive Body.
	var body3 := _make_body()
	var mounted := CharacterVisuals.mount(body3, &"basic")
	var ok_mount := mounted != null
	if ok_mount:
		var cv := body3.get_node_or_null("VisualRoot/CharacterModel/CharacterVisual")
		ok_mount = cv != null
		var primitive := body3.get_node_or_null("VisualRoot/CharacterModel/Body")
		ok_mount = ok_mount and (primitive == null or not (primitive as Node3D).visible)
	results.append({
		"name": "approved model mounts + primitive hidden",
		"passed": ok_mount,
		"why": "mounted=%s" % str(mounted != null),
	})
	if mounted != null:
		# 4) Idempotent: a second mount reuses the existing wrapper (no duplicate model).
		var mount_node := body3.get_node("VisualRoot/CharacterModel")
		var before := mount_node.get_child_count()
		var again := CharacterVisuals.mount(body3, &"basic")
		var after := mount_node.get_child_count()
		var visuals := 0
		for c in mount_node.get_children():
			if c.name == &"CharacterVisual":
				visuals += 1
		results.append({
			"name": "mount is idempotent (no duplicate models)",
			"passed": again != null and before == after and visuals == 1,
			"why": "before=%d after=%d visuals=%d" % [before, after, visuals],
		})
		body3.free()

	return results


static func _make_body() -> Node3D:
	var root := Node3D.new()
	var visual := Node3D.new()
	visual.name = &"VisualRoot"
	root.add_child(visual)
	var mount := Node3D.new()
	mount.name = &"CharacterModel"
	visual.add_child(mount)
	var body := MeshInstance3D.new()
	body.name = &"Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 1.4, 0.8)
	body.mesh = box
	mount.add_child(body)
	return root
