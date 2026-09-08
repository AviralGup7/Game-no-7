extends RefCounted

## Enemy scene inheritance contract (QA audit "Architecture findings" fix).
##
## All 8 archetype scenes MUST be `enemy_base.tscn` child scenes that override only
## their unique parts. This suite instantiates every archetype with the real engine
## and asserts:
##   1. every shared base node exists with the base script/type — the invariant that
##      hand-copied scenes silently broke (a base edit missed 5 of 8 enemies);
##   2. per-archetype overrides survive inheritance (collision shapes, materials,
##      marker offsets, nav distances, animator config, boss phase plan);
##   3. untouched properties still resolve to the base defaults (proving the values
##      come from `enemy_base.tscn`, not from per-scene copies).
##
## Scenes are instantiated but never added to the tree, so no autoloads are needed.

const ARCHETYPES := {
	&"basic":   {"scene": "res://scenes/enemies/basic_enemy.tscn"},
	&"fast":    {"scene": "res://scenes/enemies/fast_enemy.tscn"},
	&"heavy":   {"scene": "res://scenes/enemies/heavy_enemy.tscn"},
	&"dasher":  {"scene": "res://scenes/enemies/dasher_enemy.tscn"},
	&"exploder": {"scene": "res://scenes/enemies/exploder_enemy.tscn"},
	&"ranged":  {"scene": "res://scenes/enemies/ranged_enemy.tscn"},
	&"splitter": {"scene": "res://scenes/enemies/splitter_enemy.tscn"},
	&"warlord": {"scene": "res://scenes/enemies/warlord_enemy.tscn"},
}

# Shared wiring every archetype must carry. name -> [expected class, expected script].
const SHARED_NODES := {
	"HealthComponent": ["Node", "res://scripts/player/health_component.gd"],
	"EnemyFeedback": ["Node", "res://scripts/enemies/enemy_feedback.gd"],
	"EnemyAudio": ["Node", "res://scripts/enemies/enemy_audio.gd"],
	"EnemyStateMachine": ["Node", "res://scripts/enemies/enemy_state_machine.gd"],
	"StatusManager": ["Node", "res://scripts/status/status_manager.gd"],
	"ModifierReceiver": ["Node", ""],
	"NavigationAgent3D": ["NavigationAgent3D", ""],
	"CollisionShape3D": ["CollisionShape3D", ""],
	"TargetingOrigin": ["Marker3D", ""],
	"AttackOrigin": ["Marker3D", ""],
	"VisualRoot": ["Node3D", ""],
	"VisualRoot/CharacterModel": ["Node3D", ""],
	"VisualRoot/CharacterModel/Body": ["MeshInstance3D", ""],
	"VisualRoot/AnimationPlayer": ["AnimationPlayer", ""],
}


static func suite() -> Array:
	var results: Array = []
	for id in ARCHETYPES:
		results.append_array(_check_archetype(id))
	results.append(_check_roster_size())
	return results


static func _check_roster_size() -> Dictionary:
	return {
		"name": "roster has 8 enemy archetypes",
		"passed": ARCHETYPES.size() == 8,
		"why": "found %d" % ARCHETYPES.size(),
	}


static func _check_archetype(id: StringName) -> Array:
	var out: Array = []
	var tag := String(id)
	var packed: PackedScene = load(ARCHETYPES[id]["scene"])
	out.append({"name": tag + ": scene loads", "passed": packed != null})
	if packed == null:
		return out
	var enemy := packed.instantiate()
	if enemy == null:
		out.append({"name": tag + ": instantiates", "passed": false, "why": "instantiate() null"})
		return out

	# 1) Root contract: the scene IS an EnemyBase on the enemy collision layers.
	out.append({
		"name": tag + ": root runs enemy_base.gd",
		"passed": enemy.get_script() != null \
			and String((enemy.get_script() as Resource).resource_path) == "res://scripts/enemies/enemy_base.gd",
		"why": "script=%s" % str(enemy.get_script()),
	})
	out.append({
		"name": tag + ": collision layers from contract (4/5)",
		"passed": int(enemy.collision_layer) == 4 and int(enemy.collision_mask) == 5,
		"why": "layer=%d mask=%d" % [enemy.collision_layer, enemy.collision_mask],
	})

	# 2) Every shared node exists with the base script/type — the copy-rot check.
	var missing: Array[String] = []
	for path in SHARED_NODES:
		var expect: Array = SHARED_NODES[path]
		var n := enemy.get_node_or_null(NodePath(path))
		if n == null:
			missing.append(path + " absent")
			continue
		if not n.is_class(expect[0]):
			missing.append("%s is %s" % [path, n.get_class()])
		var want_script: String = expect[1]
		if want_script != "":
			var s: Script = n.get_script()
			if s == null or String(s.resource_path) != want_script:
				missing.append("%s script=%s" % [path, str(s)])
	out.append({
		"name": tag + ": all shared base nodes present with base wiring",
		"passed": missing.is_empty(),
		"why": "; ".join(missing),
	})

	# 3) Per-archetype overrides survive inheritance (values pinned from pre-refactor scenes).
	var shape_node := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape: Resource = shape_node.shape if shape_node != null else null
	var body := enemy.get_node_or_null("VisualRoot/CharacterModel/Body") as MeshInstance3D
	var body_mesh: Resource = body.mesh if body != null else null
	var nav := enemy.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	var targeting := enemy.get_node_or_null("TargetingOrigin") as Marker3D
	var attack := enemy.get_node_or_null("AttackOrigin") as Marker3D
	var animator := enemy.get_node_or_null("EnemyAnimator")

	match id:
		&"basic", &"fast", &"heavy":
			# Unchanged from the base scene: capsule 0.5/1.6, base nav defaults.
			out.append(_capsule_check(tag + ": collision", shape, 0.5, 1.6))
			out.append(_nav_check(tag, nav, 1.5, 1.2))
		&"dasher":
			out.append(_capsule_check(tag + ": collision", shape, 0.4, 1.3))
			out.append(_capsule_check(tag + ": body mesh", body_mesh, 0.35, 1.1))
			out.append(_origin_check(tag + ": targeting", targeting, Vector3(0, 1.0, 0)))
			out.append(_origin_check(tag + ": attack", attack, Vector3(0, 0.7, -0.5)))
			out.append(_nav_check(tag, nav, 1.5, 1.2))
			out.append(_animator_check(tag, animator, 0.85,
				"res://assets/characters/creatures/Rat.glb", &"RatArmature|Rat_Attack"))
		&"exploder":
			var sphere := shape as SphereShape3D
			out.append({
				"name": tag + ": sphere collision r=0.55",
				"passed": sphere != null and is_equal_approx(sphere.radius, 0.55),
				"why": "shape=%s" % str(shape),
			})
			var mat: StandardMaterial3D = null
			if body != null and body.get_surface_material_override_count() > 0:
				mat = body.get_surface_material_override(0) as StandardMaterial3D
			out.append({
				"name": tag + ": emissive material survives",
				"passed": mat != null and mat.emission_enabled \
					and mat.emission.is_equal_approx(Color(1, 0.3, 0.15, 1)),
				"why": "mat=%s" % str(mat),
			})
			out.append(_origin_check(tag + ": attack", attack, Vector3(0, 0.6, -0.5)))
			out.append(_animator_check(tag, animator, 1.9,
				"res://assets/characters/monsters/Demon.gltf", &"Punch"))
		&"ranged":
			out.append(_capsule_check(tag + ": collision", shape, 0.45, 1.5))
			# Markers match the base — inherited, not re-specified.
			out.append(_origin_check(tag + ": targeting", targeting, Vector3(0, 1.1, 0)))
			out.append(_origin_check(tag + ": attack", attack, Vector3(0, 0.8, -0.5)))
			out.append(_animator_check(tag, animator, 1.7,
				"res://assets/characters/skeletons/Skeleton_Mage.glb", &"Spellcast_Shoot"))
		&"splitter":
			out.append(_capsule_check(tag + ": collision", shape, 0.6, 1.5))
			out.append(_animator_check(tag, animator, 1.3,
				"res://assets/characters/creatures/Spider.glb", &"SpiderArmature|Spider_Attack"))
		&"warlord":
			out.append(_capsule_check(tag + ": collision", shape, 0.9, 2.6))
			out.append(_origin_check(tag + ": targeting", targeting, Vector3(0, 1.8, 0)))
			out.append(_origin_check(tag + ": attack", attack, Vector3(0, 1.2, -0.8)))
			out.append(_nav_check(tag, nav, 2.0, 1.8))
			out.append(_animator_check(tag, animator, 2.6,
				"res://assets/characters/monsters/BlueDemon.gltf", &"Punch"))
			out.append(_boss_plan_check(tag, enemy))
		_:
			out.append({"name": tag + ": known archetype", "passed": false, "why": "uncovered archetype"})

	enemy.free()
	return out


static func _capsule_check(tag: String, res: Resource, radius: float, height: float) -> Dictionary:
	# CapsuleShape3D and CapsuleMesh share radius/height; accept either.
	var ok := (res is CapsuleShape3D or res is CapsuleMesh) \
		and is_equal_approx(float(res.get("radius")), radius) \
		and is_equal_approx(float(res.get("height")), height)
	return {
		"name": tag + ": capsule r=%s h=%s" % [radius, height],
		"passed": ok,
		"why": "res=%s" % str(res),
	}


static func _nav_check(tag: String, nav: NavigationAgent3D, path_dist: float, target_dist: float) -> Dictionary:
	var ok := nav != null and is_equal_approx(nav.path_desired_distance, path_dist) \
		and is_equal_approx(nav.target_desired_distance, target_dist)
	return {
		"name": tag + ": nav distances %s/%s" % [path_dist, target_dist],
		"passed": ok,
		"why": "nav=%s" % str(nav),
	}


static func _origin_check(tag: String, marker: Marker3D, expected: Vector3) -> Dictionary:
	var ok := marker != null and marker.position.is_equal_approx(expected)
	return {
		"name": tag + " offset %s" % expected,
		"passed": ok,
		"why": "pos=%s want=%s" % [str(marker.position) if marker != null else "null", expected],
	}


static func _animator_check(tag: String, animator: Node, extent: float,
		model_path: String, attack_anim: StringName) -> Dictionary:
	if animator == null or animator.get_script() == null:
		return {"name": tag + ": EnemyAnimator config survives", "passed": false, "why": "no animator"}
	var scene_path: String = ""
	if animator.model_scene != null:
		scene_path = String(animator.model_scene.resource_path)
	var ok := String((animator.get_script() as Resource).resource_path) == "res://scripts/enemies/enemy_animator.gd" \
		and scene_path == model_path \
		and is_equal_approx(animator.model_extent, extent) \
		and is_equal_approx(animator.yaw_offset_degrees, 180.0) \
		and (animator.animation_map.get(&"attack", &"") as StringName) == attack_anim
	return {
		"name": tag + ": EnemyAnimator config survives",
		"passed": ok,
		"why": "model=%s extent=%s yaw=%s attack=%s" % [
			scene_path, str(animator.model_extent), str(animator.yaw_offset_degrees),
			str(animator.animation_map.get(&"attack", "")),
		],
	}


static func _boss_plan_check(tag: String, boss: Node) -> Dictionary:
	var controller := boss.get_node_or_null("BossController")
	if controller == null:
		return {"name": tag + ": boss phase plan", "passed": false, "why": "no BossController node"}
	var plan: Array = controller.phase_plan
	var want := [
		["Awakening", 1.0, 1.0, 1.0, 4.2],
		["Fury", 0.66, 1.25, 1.1, 3.8],
		["Enrage", 0.33, 1.5, 1.25, 3.0],
	]
	var ok := plan.size() == want.size()
	for i in want.size():
		if i >= plan.size():
			ok = false
			break
		var p: BossPhaseConfig = plan[i]
		ok = ok and p.phase_name == String(want[i][0]) \
			and is_equal_approx(p.threshold, want[i][1]) \
			and is_equal_approx(p.damage_mult, want[i][2]) \
			and is_equal_approx(p.speed_mult, want[i][3]) \
			and is_equal_approx(p.ability_interval, want[i][4])
	return {
		"name": tag + ": boss phase plan matches shipped values",
		"passed": ok,
		"why": "plan=%s" % str(plan),
	}
