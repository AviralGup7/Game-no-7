class_name CameraLockOnController
extends RefCounted

## Lock-on target ownership for CameraRig, extracted so the "what is the camera
## orbiting around" policy lives in one place instead of inside the coordinator.
##
## Owns: candidate selection (the player's TargetingComponent when present, the
## nearest living enemy otherwise), the mid-shot look target that keeps the lock
## and the player in frame, and the per-frame re-validation that drops or replaces
## a lock whose target died or left lock range.
##
## The input that starts/ends a lock stays on Player (request_lock_on); the rig only
## exposes the toggle the player calls.

## Group the candidate search reads (EnemyBase.TARGET_GROUP).
const ENEMY_GROUP := &"enemies"
## Midpoint factor used when the profile is missing (Zelda-style between player and lock).
const DEFAULT_MIDPOINT_FACTOR := 0.5


## Start a lock on the best candidate, or release the current one. False when lock-on
## is disabled/unavailable or nothing is in range (the caller keeps the old state).
func toggle(profile: CameraProfile, mode: CameraModeController, target: Node3D, tree: SceneTree) -> bool:
	if profile == null or not profile.lock_on_enabled or target == null:
		return false
	if mode.is_locked():
		mode.set_lock_target(null)
		return true
	var best := pick_candidate(target, profile, tree)
	if best == null:
		return false
	mode.set_lock_target(best)
	if RunAnalytics != null:
		RunAnalytics.note_lock_on()
	return true


## Best lock candidate: the target's TargetingComponent ranking when the target
## carries one (the player does), else the first enemy in the group. Null when the
## best candidate is beyond the profile's lock distance.
func pick_candidate(target: Node3D, profile: CameraProfile, tree: SceneTree) -> Node3D:
	if target == null or not is_instance_valid(target) or profile == null or tree == null:
		return null
	var targeting := target.get_node_or_null("TargetingComponent") as TargetingComponent
	var enemies := tree.get_nodes_in_group(String(ENEMY_GROUP))
	var best: Node = null
	if targeting != null:
		best = targeting.pick_best_target(enemies)
	elif not enemies.is_empty():
		best = enemies[0]
	if best is Node3D and is_instance_valid(best):
		var dist := (best as Node3D).global_position.distance_to(target.global_position)
		if dist <= profile.lock_on_max_distance:
			return best as Node3D
	return null


## Re-validate the held lock every frame: a freed, dead or out-of-range target is
## dropped, and when it merely left lock range the camera re-picks a replacement.
func sync_lock_target(mode: CameraModeController, target: Node3D, profile: CameraProfile, tree: SceneTree) -> void:
	if profile == null or not profile.lock_on_enabled:
		return
	if target == null or not mode.is_locked():
		return
	var held := mode.get_lock_target()
	if held == null or not is_instance_valid(held):
		mode.set_lock_target(null)
		return
	if held.global_position.distance_to(target.global_position) > profile.lock_on_max_distance:
		mode.set_lock_target(pick_candidate(target, profile, tree))
		return
	if held is Damageable and not (held as Damageable).is_alive():
		mode.set_lock_target(pick_candidate(target, profile, tree))


## Look-at point while locked: the player/lock midpoint flattened to the focus height
## so the camera never tilts at the ground between them. The caller passes a valid
## lock target (the mode controller owns the lock's lifetime).
func mid_look_target(lock_target: Node3D, focus_point: Vector3, profile: CameraProfile) -> Vector3:
	var factor := DEFAULT_MIDPOINT_FACTOR
	if profile != null:
		factor = clampf(profile.lock_on_midpoint_factor, 0.0, 1.0)
	var midpoint := focus_point.lerp(lock_target.global_position, factor)
	midpoint.y = focus_point.y
	return midpoint
