class_name EnemyClipCatalog
extends RefCounted

## Pure clip-key / playback math for EnemyAnimator. Headless-testable: no tree,
## no AnimationPlayer, no autoloads. The animator remains the only node that
## touches a live rig; this catalog decides *which* key and *how fast*.
##
## Keys are optional in each scene's `animation_map`. Missing keys keep the
## current clip running (the v1 contract). One-shot keys lock the player until
## `animation_finished`; locomotion keys loop on private clip copies.

const KEY_IDLE := &"idle"
const KEY_RUN := &"run"
const KEY_ATTACK := &"attack"
const KEY_HURT := &"hurt"
const KEY_DEATH := &"death"
const KEY_STUN := &"stun"
const KEY_CAST := &"cast"
const KEY_TELEGRAPH := &"telegraph"
const KEY_DASH := &"dash"
const KEY_SPAWN := &"spawn"

const RUN_PACE_REFERENCE_SPEED := 3.5
const MIN_CLIP_LENGTH := 0.3
const DEFAULT_BLEND := 0.08
const ATTACK_BLEND_SLOW := 0.12

const ONE_SHOT_KEYS: Array[StringName] = [
	KEY_ATTACK, KEY_HURT, KEY_DEATH, KEY_STUN, KEY_CAST, KEY_TELEGRAPH, KEY_DASH, KEY_SPAWN
]
const LOCOMOTION_KEYS: Array[StringName] = [KEY_IDLE, KEY_RUN]


static func is_locomotion(key: StringName) -> bool:
	return key in LOCOMOTION_KEYS


static func is_one_shot(key: StringName) -> bool:
	return key in ONE_SHOT_KEYS


static func is_known_key(key: StringName) -> bool:
	return is_locomotion(key) or is_one_shot(key)


## Locomotion key for an EnemyStateMachine id. Attack/hurt/stun/ranged/dead
## are one-shots owned by the matching signal, not by this map.
static func locomotion_for_state(state: StringName) -> StringName:
	match state:
		&"chase":
			return KEY_RUN
		&"dash":
			return KEY_DASH
		&"idle", &"fuse":
			return KEY_IDLE
		_:
			return KEY_IDLE


static func holds_pose_in_state(state: StringName) -> bool:
	return state in [&"ranged", &"stunned"]


static func finite_length(length: float) -> float:
	if not is_finite(length) or length <= 0.0:
		return MIN_CLIP_LENGTH
	return length


## Scale a strike clip so contact lands around the end of the authored windup.
static func windup_speed(clip_length: float, windup: float) -> float:
	var length := finite_length(clip_length)
	if not is_finite(windup) or windup <= 0.01:
		return 1.0
	return clampf(length / (windup + 0.15), 0.5, 3.0)


## Scale a telegraph/cast clip to the tell duration.
static func telegraph_speed(clip_length: float, duration: float) -> float:
	var length := finite_length(clip_length)
	var dur := duration if (is_finite(duration) and duration > 0.0) else 0.2
	return clampf(length / maxf(dur, 0.2), 0.5, 2.5)


static func run_pace(speed: float) -> float:
	var s := speed if is_finite(speed) else 0.0
	return clampf(s / RUN_PACE_REFERENCE_SPEED, 0.7, 1.8)


static func blend_for(key: StringName, windup: float = 0.0) -> float:
	if key != KEY_ATTACK:
		return DEFAULT_BLEND
	if is_finite(windup) and windup >= 0.2:
		return ATTACK_BLEND_SLOW
	return DEFAULT_BLEND


## Stun falls back to hurt; telegraph falls back to cast then attack; dash
## falls back to run. Missing still means "keep the current clip".
static func resolve_key(has_clip: Callable, key: StringName) -> StringName:
	if has_clip.is_valid() and bool(has_clip.call(key)):
		return key
	match key:
		KEY_STUN:
			return KEY_HURT if (has_clip.is_valid() and bool(has_clip.call(KEY_HURT))) else &""
		KEY_TELEGRAPH:
			if has_clip.is_valid() and bool(has_clip.call(KEY_CAST)):
				return KEY_CAST
			if has_clip.is_valid() and bool(has_clip.call(KEY_ATTACK)):
				return KEY_ATTACK
			return &""
		KEY_DASH:
			return KEY_RUN if (has_clip.is_valid() and bool(has_clip.call(KEY_RUN))) else &""
		KEY_SPAWN:
			return KEY_IDLE if (has_clip.is_valid() and bool(has_clip.call(KEY_IDLE))) else &""
		KEY_CAST:
			return KEY_ATTACK if (has_clip.is_valid() and bool(has_clip.call(KEY_ATTACK))) else &""
		_:
			return &""


## Directional dash clip names (Kenney dodge family). Godot forward is -Z;
## delegated to HeroRigContract so player and enemy share the facing rule.
static func directional_dash(facing: Vector3, direction: Vector3) -> StringName:
	return HeroRigContract.directional_dodge(facing, direction)


static func dash_fallback_clip() -> StringName:
	return &"Dodge_Forward"


static func hip_lock_bone_match(path: String) -> bool:
	var lower := path.to_lower()
	return "hips" in lower or "pelvis" in lower or "root" in lower


static func should_lock_hips(key: StringName) -> bool:
	return is_locomotion(key)


static func loop_mode_for(key: StringName) -> int:
	return 1 if is_locomotion(key) else 0  # 1 = LOOP_LINEAR, 0 = LOOP_NONE


static func stun_hold_speed() -> float:
	return 0.05


static func ranged_hold_speed() -> float:
	return 0.35


static func resume_after_one_shot(state: StringName) -> StringName:
	match state:
		&"chase":
			return KEY_RUN
		&"dash":
			return KEY_DASH
		&"ranged":
			return KEY_CAST
		&"stunned":
			return KEY_STUN
		&"attack":
			return KEY_IDLE
		&"hurt":
			return KEY_IDLE
		&"dead":
			return KEY_DEATH
		_:
			return KEY_IDLE
