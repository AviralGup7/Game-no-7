extends RefCounted

## Enemy scene inheritance contract (QA audit "Architecture findings" fix).
##
## All 8 archetype scenes MUST be `enemy_base.tscn` child scenes that override only
## their unique parts. This suite instantiates every archetype with the real engine
## and asserts:
##   1. every shared base node exists with the base script/type — the invariant that
##      hand-copied scenes silently broke (a base edit missed 5 of 8 enemies);
##   2. per-archetype overrides survive inheritance (collision shapes/meshes,
##      materials, marker offsets, nav distances, animator config, boss phase plan);
##   3. untouched properties still resolve to the base defaults (proving the values
##      come from `enemy_base.tscn`, not from per-scene copies).
##
## Scenes are instantiated but never added to the tree, so no autoloads are needed.

const ARCHETYPES := {
	&"basic":    "res://scenes/enemies/basic_enemy.tscn",
	&"fast":     "res://scenes/enemies/fast_enemy.tscn",
	&"heavy":    "res://scenes/enemies/heavy_enemy.tscn",
	&"dasher":   "res://scenes/enemies/dasher_enemy.tscn",
	&"exploder": "res://scenes/enemies/exploder_enemy.tscn",
	&"ranged":   "res://scenes/enemies/ranged_enemy.tscn",
	&"splitter": "res://scenes/enemies/splitter_enemy.tscn",
	&"warlord":  "res://scenes/enemies/warlord_enemy.tscn",
}

# Shared nodes every archetype must carry. name -> [expected class, expected script].
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

# Full-roster golden values, pinned from the shipped scenes (the five refactored
# archetypes: pre-refactor copies; basic/fast/heavy: pre-existing inheritance).
#   shape:   [type, radius, height]       — CollisionShape3D.shape
#   mesh:    [type, radius, height]       — Body.mesh ("" type = any capsule)
#   albedo:  Body surface material color
#   nav:     [path_desired, target_desired, height_tolerance]
#   target:  TargetingOrigin position     (null = base default Vector3(0, 1.1, 0))
#   attack:  AttackOrigin position         (null = base default Vector3(0, 0.8, -0.5))
#   anim:    [model_extent, model_path, attack_clip]  (Animator config)
const GOLD := {
	&"basic": {
		"shape": ["CapsuleShape3D", 0.5, 1.6], "mesh": ["CapsuleMesh", 0.45, 1.4],
		"albedo": Color(0.85, 0.5, 0.2, 1), "nav": [1.5, 1.2, 0.6],
		"target": null, "attack": null,
		"anim": [1.7, "res://assets/characters/skeletons/Skeleton_Minion.glb", "1H_Melee_Attack_Slice_Horizontal"],
	},
	&"fast": {
		"shape": ["CapsuleShape3D", 0.5, 1.6], "mesh": ["CapsuleMesh", 0.45, 1.4],
		"albedo": Color(0.85, 0.5, 0.2, 1), "nav": [1.5, 1.2, 0.6],
		"target": null, "attack": null,
		"anim": [1.65, "res://assets/characters/skeletons/Skeleton_Rogue.glb", "1H_Melee_Attack_Stab"],
	},
	&"heavy": {
		"shape": ["CapsuleShape3D", 0.5, 1.6], "mesh": ["CapsuleMesh", 0.45, 1.4],
		"albedo": Color(0.85, 0.5, 0.2, 1), "nav": [1.5, 1.2, 0.6],
		"target": null, "attack": null,
		"anim": [1.85, "res://assets/characters/skeletons/Skeleton_Warrior.glb", "1H_Melee_Attack_Chop"],
	},
	&"dasher": {
		"shape": ["CapsuleShape3D", 0.4, 1.3], "mesh": ["CapsuleMesh", 0.35, 1.1],
		"albedo": Color(0.95, 0.75, 0.2, 1), "nav": [1.5, 1.2, 0.6],
		"target": Vector3(0, 1.0, 0), "attack": Vector3(0, 0.7, -0.5),
		"anim": [0.85, "res://assets/characters/creatures/Rat.glb", "RatArmature|Rat_Attack"],
	},
	&"exploder": {
		"shape": ["SphereShape3D", 0.55, 0.0], "mesh": ["SphereMesh", 0.5, 1.0],
		"albedo": Color(1, 0.3, 0.15, 1), "nav": [1.5, 1.2, 0.6],
		"target": Vector3(0, 1.0, 0), "attack": Vector3(0, 0.6, -0.5),
		"anim": [1.9, "res://assets/characters/monsters/Demon.gltf", "Punch"],
		"emissive": true,
	},
	&"ranged": {
		"shape": ["CapsuleShape3D", 0.45, 1.5], "mesh": ["CapsuleMesh", 0.4, 1.3],
		"albedo": Color(0.55, 0.35, 0.85, 1), "nav": [1.5, 1.2, 0.6],
		"target": null, "attack": null,
		"anim": [1.7, "res://assets/characters/skeletons/Skeleton_Mage.glb", "Spellcast_Shoot"],
	},
	&"splitter": {
		"shape": ["CapsuleShape3D", 0.6, 1.5], "mesh": ["CapsuleMesh", 0.55, 1.3],
		"albedo": Color(0.35, 0.75, 0.55, 1), "nav": [1.5, 1.2, 0.6],
		"target": null, "attack": null,
		"anim": [1.3, "res://assets/characters/creatures/Spider.glb", "SpiderArmature|Spider_Attack"],
	},
	&"warlord": {
		"shape": ["CapsuleShape3D", 0.9, 2.6], "mesh": ["CapsuleMesh", 0.85, 2.4],
		"albedo": Color(0.6, 0.12, 0.35, 1), "nav": [2.0, 1.8, 0.6],
		"target": Vector3(0, 1.8, 0), "attack": Vector3(0, 1.2, -0.8),
		"anim": [2.6, "res://assets/characters/monsters/BlueDemon.gltf", "Punch"],
		"boss": true,
	},
}


static func suite() -> Array:
	var results: Array = []
	for id in ARCHETYPES:
		results.append_array(_check_archetype(id))
	results.append({
		"name": "roster has 8 enemy archetypes",
		"passed": ARCHETYPES.size() == 8 and GOLD.size() == 8,
		"why": "ARCHETYPES=%d GOLD=%d" % [ARCHETYPES.size(), GOLD.size()],
	})
	return results


static func _check_archetype(id: StringName) -> Array:
	var out: Array = []
	var tag := String(id)
	var packed: PackedScene = load(ARCHETYPES[id])
	out.append({"name": tag + ": scene loads", "passed": packed != null, "why": "load() returned null"})
	if packed == null:
		return out
	var enemy := packed.instantiate()
	if enemy == null:
		out.append({"name": tag + ": instantiates", "passed": false, "why": "instantiate() null"})
		return out

	# 1) Root contract: the scene IS an EnemyBase on the enemy collision layers.
	var root_script: Script = enemy.get_script()
	out.append({
		"name": tag + ": root runs enemy_base.gd",
		"passed": root_script != null and String(root_script.resource_path) == "res://scripts/enemies/enemy_base.gd",
		"why": "script=%s" % str(root_script),
	})
	out.append({
		"name": tag + ": collision layers from contract (4/5)",
		"passed": int(enemy.collision_layer) == 4 and int(enemy.collision_mask) == 5,
		"why": "layer=%s mask=%s" % [str(enemy.collision_layer), str(enemy.collision_mask)],
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

	# 3) Full-roster golden values (pinned from the shipped scenes).
	var g: Dictionary = GOLD[id]
	var shape_node := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape: Resource = shape_node.shape if shape_node != null else null
	var body := enemy.get_node_or_null("VisualRoot/CharacterModel/Body") as MeshInstance3D
	out.append(_capsule_check(tag + ": collision shape", shape,
		g["shape"][0], g["shape"][1], g["shape"][2]))
	out.append(_capsule_check(tag + ": body mesh", body.mesh if body != null else null,
		g["mesh"][0], g["mesh"][1], g["mesh"][2]))

	var mat: StandardMaterial3D = null
	if body != null and body.get_surface_override_material_count() > 0:
		mat = body.get_surface_override_material(0) as StandardMaterial3D
	var albedo_ok := mat != null and mat.albedo_color.is_equal_approx(g["albedo"])
	if g.get("emissive", false):
		albedo_ok = albedo_ok and mat.emission_enabled and mat.emission.is_equal_approx(g["albedo"])
	out.append({
		"name": tag + ": body material identity",
		"passed": albedo_ok,
		"why": "mat=%s" % str(mat),
	})

	var nav := enemy.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	out.append({
		"name": tag + ": nav distances %s/%s" % [g["nav"][0], g["nav"][1]],
		"passed": nav != null and is_equal_approx(nav.path_desired_distance, g["nav"][0]) \
			and is_equal_approx(nav.target_desired_distance, g["nav"][1]) \
			and is_equal_approx(nav.path_height_offset, g["nav"][2]),
		"why": "nav=%s" % str(nav),
	})

	var want_target: Vector3 = g["target"] if g["target"] != null else Vector3(0, 1.1, 0)
	var want_attack: Vector3 = g["attack"] if g["attack"] != null else Vector3(0, 0.8, -0.5)
	out.append(_origin_check(tag + ": targeting origin", enemy.get_node_or_null("TargetingOrigin") as Marker3D, want_target))
	out.append(_origin_check(tag + ": attack origin", enemy.get_node_or_null("AttackOrigin") as Marker3D, want_attack))
	out.append(_animator_check(tag, enemy.get_node_or_null("EnemyAnimator"), g["anim"]))

	if g.get("boss", false):
		out.append(_boss_plan_check(tag, enemy))
	else:
		out.append({
			"name": tag + ": no BossController leak",
			"passed": enemy.get_node_or_null("BossController") == null,
			"why": "BossController present on non-boss archetype",
		})

	enemy.free()
	return out


static func _capsule_check(tag: String, res: Resource, type_name: String, radius: float, height: float) -> Dictionary:
	# Shape + mesh resource classes both carry radius; only meshes/capsules carry height
	# (the golden encodes "no height to check" as 0.0, e.g. SphereShape3D).
	var check_height: bool = height > 0.0
	var ok := res != null and String(res.get_class()) == type_name \
		and is_equal_approx(float(res.get("radius")), radius)
	if ok and check_height:
		ok = is_equal_approx(float(res.get("height")), height)
	return {
		"name": tag + ": %s r=%s h=%s" % [type_name, radius, height],
		"passed": ok,
		"why": "res=%s" % str(res),
	}


static func _origin_check(tag: String, marker: Marker3D, expected: Vector3) -> Dictionary:
	var ok := marker != null and marker.position.is_equal_approx(expected)
	return {
		"name": tag + " matches %s" % expected,
		"passed": ok,
		"why": "pos=%s want=%s" % [str(marker.position) if marker != null else "null", expected],
	}


static func _animator_check(tag: String, animator: Node, anim_golden: Array) -> Dictionary:
	if animator == null or animator.get_script() == null:
		return {"name": tag + ": EnemyAnimator config survives", "passed": false, "why": "no animator"}
	var scene_path: String = ""
	if animator.model_scene != null:
		scene_path = String(animator.model_scene.resource_path)
	var ok := String((animator.get_script() as Resource).resource_path) == "res://scripts/enemies/enemy_animator.gd" \
		and scene_path == String(anim_golden[1]) \
		and is_equal_approx(animator.model_extent, anim_golden[0]) \
		and is_equal_approx(animator.yaw_offset_degrees, 180.0) \
		and String(animator.animation_map.get(&"attack", "")) == String(anim_golden[2])
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
