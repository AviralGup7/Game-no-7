class_name EnemyAnimator
extends Node

## Mounts the archetype's supplied 3D model + animation set onto the enemy's
## VisualRoot/CharacterModel (see docs/ASSET_CATALOG.md role map) and drives its
## AnimationPlayer from the EnemyBase command surface: state changes select the
## idle/run loops, attack_started plays the strike clip scaled to the windup,
## damage/death play one-shot hit/death clips. Fitting goes through ModelVisual so
## physics dimensions are untouched; when the model or any clip is missing the
## component is a no-op and the primitive visual stays. Add one as a child of the
## enemy scene root with `model_scene`, `model_extent` and `animation_map` set.
##
## Clip playback is presentation only: one-shots lock until `animation_finished`
## then resume locomotion for the live AI state (so a chase that never re-enters
## chase does not freeze on the last attack frame). Shared imported Animation
## resources are duplicated per instance — mutating loop_mode on the GLB would
## leak across every enemy of that archetype.

## Keys understood in animation_map (all optional; missing keys keep the current
## clip running): idle, run, attack, hurt, death, stun, cast, telegraph, dash, spawn.
const KEY_IDLE := EnemyClipCatalog.KEY_IDLE
const KEY_RUN := EnemyClipCatalog.KEY_RUN
const KEY_ATTACK := EnemyClipCatalog.KEY_ATTACK
const KEY_HURT := EnemyClipCatalog.KEY_HURT
const KEY_DEATH := EnemyClipCatalog.KEY_DEATH
const KEY_STUN := EnemyClipCatalog.KEY_STUN
const KEY_CAST := EnemyClipCatalog.KEY_CAST
const KEY_TELEGRAPH := EnemyClipCatalog.KEY_TELEGRAPH
const KEY_DASH := EnemyClipCatalog.KEY_DASH
const KEY_SPAWN := EnemyClipCatalog.KEY_SPAWN

const RUN_PACE_REFERENCE_SPEED := EnemyClipCatalog.RUN_PACE_REFERENCE_SPEED

@export var model_scene: PackedScene = null
## Longest-axis size the model is fitted into (ModelVisual), in meters.
@export var model_extent: float = 1.8
@export var animation_map: Dictionary = {}
## Cosmetic facing correction (degrees around Y) if a source rig faces the wrong
## way after import; does not touch collision or navigation.
@export var yaw_offset_degrees: float = 0.0
@export var blend_seconds: float = 0.08

var _host: EnemyBase = null
var _player: AnimationPlayer = null
var _clips: Dictionary = {}
var _current_state := &"idle"
var _dead := false
var _locked := false
var _lock_key: StringName = &""
var _paused_for_ai := false
var _spawned := false


func _ready() -> void:
	_host = get_parent() as EnemyBase
	_mount_model()
	if _host == null:
		return
	if not _host.state_changed.is_connected(_on_state_changed):
		_host.state_changed.connect(_on_state_changed)
	if not _host.attack_started.is_connected(_on_attack_started):
		_host.attack_started.connect(_on_attack_started)
	if not _host.died.is_connected(_on_died):
		_host.died.connect(_on_died)
	if not _host.initialized.is_connected(_on_initialized):
		_host.initialized.connect(_on_initialized)
	if EventBus != null and not EventBus.status_applied.is_connected(_on_status_applied):
		EventBus.status_applied.connect(_on_status_applied)
	var boss := _host.get_boss_controller()
	if boss != null and not boss.telegraph_started.is_connected(_on_boss_telegraph):
		boss.telegraph_started.connect(_on_boss_telegraph)


func _exit_tree() -> void:
	if _host != null and is_instance_valid(_host):
		if _host.state_changed.is_connected(_on_state_changed):
			_host.state_changed.disconnect(_on_state_changed)
		if _host.attack_started.is_connected(_on_attack_started):
			_host.attack_started.disconnect(_on_attack_started)
		if _host.died.is_connected(_on_died):
			_host.died.disconnect(_on_died)
		if _host.initialized.is_connected(_on_initialized):
			_host.initialized.disconnect(_on_initialized)
		var boss := _host.get_boss_controller()
		if boss != null and is_instance_valid(boss) and boss.telegraph_started.is_connected(_on_boss_telegraph):
			boss.telegraph_started.disconnect(_on_boss_telegraph)
	if EventBus != null and EventBus.status_applied.is_connected(_on_status_applied):
		EventBus.status_applied.disconnect(_on_status_applied)
	if _player != null and is_instance_valid(_player) and _player.animation_finished.is_connected(_on_finished):
		_player.animation_finished.disconnect(_on_finished)


func _mount_model() -> void:
	if model_scene == null:
		return
	var wrapper := ModelVisual.create(model_scene, model_extent)
	if wrapper == null:
		return
	if not is_zero_approx(yaw_offset_degrees):
		wrapper.rotation.y = deg_to_rad(yaw_offset_degrees)
	var mount: Node3D = null
	if _host != null:
		mount = _host.get_node_or_null("VisualRoot/CharacterModel") as Node3D
	if mount == null:
		wrapper.free()
		return
	# The model replaces the primitive placeholder body when present.
	var primitive := mount.get_node_or_null("Body")
	if primitive != null:
		primitive.visible = false
	mount.add_child(wrapper)
	# HD material pass (anisotropic filtering + tuned roughness/metallic) keeps the
	# approved enemy art crisp and grounded under the new HD arena lighting.
	HdMaterials.polish(wrapper)
	_player = _find_animation_player(wrapper)
	if _player == null:
		return
	_install_private_clips()
	if not _player.animation_finished.is_connected(_on_finished):
		_player.animation_finished.connect(_on_finished)
	_player.root_motion_track = NodePath()
	_loop(KEY_IDLE)


func _find_animation_player(wrapper: Node) -> AnimationPlayer:
	# Kenney skeletons expose Idle; creature GLBs (rat/spider) do not — fall
	# back to the first AnimationPlayer on the mounted wrapper.
	var via_contract := HeroRigContract.animation_player(wrapper)
	if via_contract != null:
		return via_contract
	var players := wrapper.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return null
	return players[0] as AnimationPlayer


## Duplicate every mapped clip into a per-instance library so loop_mode / hip
## locks cannot leak into the imported GLB shared by the rest of the pack.
func _install_private_clips() -> void:
	if _player == null:
		return
	var mapped: Dictionary = {}
	for raw_key in animation_map:
		var key := StringName(String(raw_key))
		var clip := String(animation_map[raw_key])
		if clip.is_empty() or not _player.has_animation(clip):
			continue
		mapped[key] = clip
	if mapped.is_empty():
		return
	for library_name in _player.get_animation_library_list():
		var original := _player.get_animation_library(library_name)
		if original == null:
			continue
		var library := original.duplicate() as AnimationLibrary
		if library == null:
			continue
		var loop_names: Dictionary = {}
		var hip_names: Dictionary = {}
		for key in mapped:
			var clip_name: String = mapped[key]
			if EnemyClipCatalog.is_locomotion(key):
				loop_names[clip_name] = true
			if EnemyClipCatalog.should_lock_hips(key):
				hip_names[clip_name] = true
		var seen: Dictionary = {}
		for key in mapped:
			var clip: String = mapped[key]
			if seen.has(clip) or not library.has_animation(clip):
				continue
			seen[clip] = true
			var src := library.get_animation(clip)
			if src == null:
				continue
			var local := src.duplicate() as Animation
			if local == null:
				continue
			local.loop_mode = Animation.LOOP_LINEAR if loop_names.has(clip) else Animation.LOOP_NONE
			local.resource_local_to_scene = true
			if hip_names.has(clip):
				_lock_hip_xz(local)
			library.remove_animation(clip)
			library.add_animation(clip, local)
		_player.remove_animation_library(library_name)
		_player.add_animation_library(library_name, library)
	for key in mapped:
		_clips[key] = mapped[key]


static func _lock_hip_xz(anim: Animation) -> void:
	if anim == null:
		return
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		if not EnemyClipCatalog.hip_lock_bone_match(String(anim.track_get_path(i))):
			continue
		for k in range(anim.track_get_key_count(i)):
			var value: Variant = anim.track_get_key_value(i, k)
			if value is Vector3:
				var v := value as Vector3
				v.x = 0.0
				v.z = 0.0
				anim.track_set_key_value(i, k, v)


func _process(_delta: float) -> void:
	if _player == null or _host == null or _dead:
		return
	if not is_finite(_delta) or _delta < 0.0:
		return
	if not _host.is_ai_enabled():
		if not _paused_for_ai:
			_player.pause()
			_paused_for_ai = true
		return
	if _paused_for_ai:
		_paused_for_ai = false
		_player.play()
	if _locked:
		return
	if _current_state == &"stunned":
		_player.speed_scale = EnemyClipCatalog.stun_hold_speed()
		return
	if _current_state == &"ranged" and _clips.has(KEY_CAST) and _player.current_animation == _clip(KEY_CAST):
		_player.speed_scale = EnemyClipCatalog.ranged_hold_speed()
	elif _current_state in [&"chase", &"dash"] and _clips.has(KEY_RUN):
		_player.speed_scale = EnemyClipCatalog.run_pace(_host.desired_speed)
	elif _player.speed_scale != 1.0:
		_player.speed_scale = 1.0


func _on_initialized(_archetype_id: StringName) -> void:
	if _dead or _spawned:
		return
	_spawned = true
	if _clips.has(KEY_SPAWN):
		_one_shot(KEY_SPAWN)
	else:
		_loop(KEY_IDLE)


func _on_state_changed(previous: StringName, current: StringName) -> void:
	_current_state = current
	if _dead:
		return
	# Cancelled ranged windup must drop CAST. Attack on the same frame is owned
	# by _on_attack_started — do not play IDLE first.
	if previous == &"ranged" and current != &"ranged" and current != &"attack":
		_locked = false
		_loop(KEY_IDLE)
	match current:
		&"idle", &"fuse":
			if not _locked:
				_loop(KEY_IDLE)
		&"attack":
			# Owned by _on_attack_started; do not overwrite with IDLE.
			pass
		&"chase":
			if not _locked:
				_loop(KEY_RUN)
		&"dash":
			_play_dash()
		&"ranged":
			# Hold aim/cast. Missing CAST must not idle-walk through the windup.
			if _clips.has(KEY_CAST) and _clip(KEY_CAST) != _clip(KEY_ATTACK):
				_loop(KEY_CAST)
			elif _clips.has(KEY_ATTACK):
				_hold_pose(KEY_ATTACK)
			else:
				_loop(KEY_IDLE)
		&"hurt":
			_one_shot(KEY_HURT)
		&"stunned":
			_one_shot(EnemyClipCatalog.resolve_key(Callable(self, "_has_clip"), KEY_STUN))


func _play_dash() -> void:
	if _clips.has(KEY_DASH):
		var facing := Vector3.FORWARD
		var direction := Vector3.FORWARD
		if _host != null:
			facing = -_host.global_transform.basis.z
			direction = Vector3(_host.velocity.x, 0.0, _host.velocity.z)
			if direction.length_squared() < 0.0001:
				direction = Vector3(_host.desired_dir.x, 0.0, _host.desired_dir.z)
		var named := EnemyClipCatalog.directional_dash(facing, direction)
		if _player != null and _player.has_animation(named):
			_play_named(named, true, 1.0, KEY_DASH)
			return
		_one_shot(KEY_DASH)
		return
	if not _locked:
		_loop(KEY_RUN)


func _on_attack_started() -> void:
	if _dead:
		return
	var speed := 1.0
	var cfg := _host.get_config() if _host != null else null
	var clip := _clip(KEY_ATTACK)
	if cfg != null and clip != "" and _player != null:
		speed = EnemyClipCatalog.windup_speed(_length(clip), cfg.attack_windup)
	_one_shot(KEY_ATTACK, speed)


func _on_status_applied(target: Node, effect_id: StringName, _stacks: int) -> void:
	if _dead or target != _host:
		return
	if effect_id == &"stun":
		_one_shot(EnemyClipCatalog.resolve_key(Callable(self, "_has_clip"), KEY_STUN), 1.0)


func _on_boss_telegraph(_kind: StringName, duration: float) -> void:
	if _dead:
		return
	var key := EnemyClipCatalog.resolve_key(Callable(self, "_has_clip"), KEY_TELEGRAPH)
	if key == &"":
		return
	var cname := _clip(key)
	var speed := EnemyClipCatalog.telegraph_speed(_length(cname), duration)
	_one_shot(key, speed)


func _on_died() -> void:
	_dead = true
	_locked = true
	_one_shot(KEY_DEATH)


func _on_finished(_finished_clip: StringName) -> void:
	if _dead:
		return
	_locked = false
	_lock_key = &""
	_resume_locomotion()


func _resume_locomotion() -> void:
	var key := EnemyClipCatalog.resume_after_one_shot(_current_state)
	if key == KEY_DEATH:
		return
	if key == KEY_DASH:
		_play_dash()
		return
	if key == KEY_CAST:
		if _clips.has(KEY_CAST) and _clip(KEY_CAST) != _clip(KEY_ATTACK):
			_loop(KEY_CAST)
		elif _clips.has(KEY_ATTACK):
			_hold_pose(KEY_ATTACK)
		else:
			_loop(KEY_IDLE)
		return
	if key == KEY_STUN:
		var stun := EnemyClipCatalog.resolve_key(Callable(self, "_has_clip"), KEY_STUN)
		if stun != &"":
			_hold_pose(stun)
		return
	_loop(key)


func _loop(key: StringName) -> void:
	var clip := _clip(key)
	if clip == "" or _player == null:
		return
	if _player.current_animation == clip:
		return
	_player.speed_scale = 1.0
	_player.play(clip, blend_seconds)


func _hold_pose(key: StringName) -> void:
	var clip := _clip(key)
	if clip == "" or _player == null:
		return
	# Tiny speed so a later ATTACK one-shot on the same clip is not skipped.
	_player.play(clip, -1.0, EnemyClipCatalog.stun_hold_speed())
	_player.seek(0.0, true)


func _one_shot(key: StringName, speed: float = 1.0) -> void:
	if key == &"":
		return
	var clip := _clip(key)
	_play_named(clip, true, speed, key)


func _play_named(clip: String, restart: bool, speed: float, key: StringName) -> void:
	if clip == "" or _player == null:
		_locked = _dead
		return
	if not _player.has_animation(clip):
		_locked = _dead
		return
	var windup := 0.0
	var cfg := _host.get_config() if _host != null else null
	if cfg != null:
		windup = cfg.attack_windup
	var blend := EnemyClipCatalog.blend_for(key, windup)
	_player.play(clip, blend, maxf(speed, 0.05))
	if restart and _player.current_animation_position > 0.04:
		_player.seek(0.0, true)
	_locked = EnemyClipCatalog.is_one_shot(key) or _dead
	_lock_key = key if _locked else &""


func _length(clip: String) -> float:
	if _player == null or clip == "" or not _player.has_animation(clip):
		return EnemyClipCatalog.MIN_CLIP_LENGTH
	var anim := _player.get_animation(clip)
	if anim == null:
		return EnemyClipCatalog.MIN_CLIP_LENGTH
	return EnemyClipCatalog.finite_length(anim.length)


func _clip(key: StringName) -> String:
	if not _clips.has(key):
		return ""
	return String(_clips[key])


func _has_clip(key: StringName) -> bool:
	return _clips.has(key) and String(_clips[key]) != ""
