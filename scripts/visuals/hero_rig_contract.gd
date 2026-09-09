class_name HeroRigContract
extends RefCounted

## Presentation compatibility gate, NOT a combat authority. A hero is not usable
## merely because it imports: every clip the live animator selects and both weapon
## sockets must exist before CharacterVisuals hides the fallback.
const MODEL_PATH := "res://assets/characters/warden/ArenaWarden.glb"
const FALLBACK_PATH := "res://assets/characters/adventurers/Knight.glb"
const AUTHORED_IDLE_META := &"authored_idle"
const MODEL_PATH_META := &"model_path"
const REQUIRED_BONES: Array[StringName] = [&"hips", &"chest", &"head", &"handslot.l", &"handslot.r"]
const REQUIRED_CLIPS: Array[StringName] = [
	&"Idle", &"Walking_A", &"Running_A",
	&"1H_Melee_Attack_Slice_Horizontal", &"1H_Melee_Attack_Slice_Diagonal", &"1H_Melee_Attack_Chop",
	&"2H_Melee_Attack_Chop", &"2H_Melee_Attack_Slice", &"2H_Melee_Attack_Spin", &"2H_Melee_Attack_Stab",
	&"Dualwield_Melee_Attack_Slice", &"2H_Ranged_Shoot", &"2H_Ranged_Reload",
	&"Dodge_Forward", &"Dodge_Backward", &"Dodge_Left", &"Dodge_Right",
	&"Hit_A", &"Death_A", &"Spellcast_Shoot", &"Spellcast_Raise", &"Cheer",
]


static func animation_player(model: Node) -> AnimationPlayer:
	if model == null:
		return null
	for candidate in model.find_children("*", "AnimationPlayer", true, false):
		var player := candidate as AnimationPlayer
		if player != null and player.has_animation(&"Idle"):
			return player
	return null


static func skeleton(model: Node) -> Skeleton3D:
	if model == null:
		return null
	for candidate in model.find_children("*", "Skeleton3D", true, false):
		var rig := candidate as Skeleton3D
		if rig != null and rig.find_bone("handslot.r") >= 0 and rig.find_bone("handslot.l") >= 0:
			return rig
	return null


static func missing_requirements(model: Node) -> PackedStringArray:
	var missing := PackedStringArray()
	var rig := skeleton(model)
	if rig == null:
		missing.append("Skeleton3D with handslot.l / handslot.r")
	else:
		for bone in REQUIRED_BONES:
			if rig.find_bone(String(bone)) < 0:
				missing.append("bone: " + String(bone))
	var player := animation_player(model)
	for clip in REQUIRED_CLIPS:
		if player == null or not player.has_animation(clip):
			missing.append("clip: " + String(clip))
			continue
		var animation := player.get_animation(clip)
		if animation.length <= 0.0 or animation.get_track_count() == 0:
			missing.append("empty clip: " + String(clip))
		for track in animation.get_track_count():
			if animation.track_get_type(track) == Animation.TYPE_METHOD:
				missing.append("method track in cosmetic clip: " + String(clip))
	return missing


## Godot forward is -Z. Positive local X is RIGHT; facing.cross(direction)
## has the opposite sign and used to swap the left/right dodge animations.
static func directional_dodge(facing: Vector3, direction: Vector3) -> StringName:
	facing.y = 0.0
	direction.y = 0.0
	if facing.length_squared() < 0.0001 or direction.length_squared() < 0.0001:
		return &"Dodge_Forward"
	facing = facing.normalized()
	direction = direction.normalized()
	var forward := facing.dot(direction)
	var right := facing.cross(Vector3.UP).dot(direction)
	if absf(forward) >= absf(right):
		return &"Dodge_Forward" if forward >= 0.0 else &"Dodge_Backward"
	return &"Dodge_Right" if right > 0.0 else &"Dodge_Left"
