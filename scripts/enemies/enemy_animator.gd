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

## Keys understood in animation_map (all optional; missing keys keep the current
## clip running): "idle", "run", "attack", "hurt", "death".
const KEY_IDLE := &"idle"
const KEY_RUN := &"run"
const KEY_ATTACK := &"attack"
const KEY_HURT := &"hurt"
const KEY_DEATH := &"death"
const KEY_STUN := &"stun"
const KEY_CAST := &"cast"

const RUN_PACE_REFERENCE_SPEED := 3.5

@export var model_scene: PackedScene = null
## Longest-axis size the model is fitted into (ModelVisual), in meters.
@export var model_extent: float = 1.8
@export var animation_map: Dictionary = {}
## Cosmetic facing correction (degrees around Y) if a source rig faces the wrong
## way after import; does not touch collision or navigation.
@export var yaw_offset_degrees: float = 0.0

var _host: EnemyBase = null
var _player: AnimationPlayer = null
var _clips: Dictionary = {}
var _current_state := &"idle"
var _dead := false


func _ready() -> void:
	_host = get_parent() as EnemyBase
	_mount_model()
	if _host == null:
		return
	if _host.has_signal("state_changed"):
		_host.state_changed.connect(_on_state_changed)
	if _host.has_signal("attack_started"):
		_host.attack_started.connect(_on_attack_started)
	if _host.has_signal("died"):
		_host.died.connect(_on_died)
	if EventBus != null and not EventBus.status_applied.is_connected(_on_status_applied):
		EventBus.status_applied.connect(_on_status_applied)
	# Boss telegraphs drive a cast-like anticipation where available.
	var boss := _host.get_node_or_null("BossController")
	if boss != null and boss.has_signal("telegraph_started"):
		if not boss.telegraph_started.is_connected(_on_boss_telegraph):
			boss.telegraph_started.connect(_on_boss_telegraph)


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
	var players := wrapper.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_player = players[0] as AnimationPlayer
	for key in animation_map:
		var clip := String(animation_map[key])
		if clip.is_empty() or _player == null or not _player.has_animation(clip):
			continue
		_clips[StringName(String(key))] = clip
		if StringName(String(key)) in [KEY_IDLE, KEY_RUN]:
			var anim := _player.get_animation(clip)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR


func _process(_delta: float) -> void:
	if _player == null or _host == null or _dead:
		return
	# Pace the run cycle with actual movement speed so slow brutes plod and fast
	# skirmishers scamper.
	if _player.current_animation == _clip(KEY_ATTACK) or _player.current_animation == _clip(KEY_HURT) or _player.current_animation == _clip(KEY_DEATH):
		return
	if _current_state == &"stunned":
		_player.speed_scale = 0.05
		return
	if _current_state == &"ranged" and _clips.has(KEY_CAST) and _player.current_animation == _clip(KEY_CAST):
		_player.speed_scale = 0.35
	elif _current_state in [&"chase", &"dash"] and _clips.has(KEY_RUN):
		var pace := clampf(_host.desired_speed / RUN_PACE_REFERENCE_SPEED, 0.7, 1.8)
		_player.speed_scale = pace
	elif _player.speed_scale != 1.0:
		_player.speed_scale = 1.0


func _on_state_changed(previous: StringName, current: StringName) -> void:
	_current_state = current
	if _dead:
		return
	# Cancelled ranged windup must drop CAST. Attack on the same frame is owned
	# by _on_attack_started — do not play IDLE first.
	if previous == &"ranged" and current != &"ranged" and current != &"attack":
		_loop(KEY_IDLE)
	match current:
		&"idle", &"fuse":
			_loop(KEY_IDLE)
		&"attack":
			# Owned by _on_attack_started; do not overwrite with IDLE.
			pass
		&"chase", &"dash":
			_loop(KEY_RUN)
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
			_one_shot(KEY_STUN if _clips.has(KEY_STUN) else KEY_HURT)


func _on_attack_started() -> void:
	if _dead:
		return
	# Scale the strike clip so it lands around the end of the windup.
	var speed := 1.0
	var cfg := _host.get_config() if _host != null else null
	var clip := _clip(KEY_ATTACK)
	if cfg != null and clip != "" and _player != null:
		var anim := _player.get_animation(clip)
		if anim != null and cfg.attack_windup > 0.01:
			speed = clampf(anim.length / (cfg.attack_windup + 0.15), 0.5, 3.0)
	_one_shot(KEY_ATTACK, speed)


func _on_status_applied(target: Node, effect_id: StringName, _stacks: int) -> void:
	if _dead or target != _host:
		return
	if effect_id == &"stun":
		_one_shot(KEY_STUN if _clips.has(KEY_STUN) else KEY_HURT, 1.0)
	elif effect_id in [&"shock", &"slow"] and _clips.has(KEY_CAST):
		# Subtle cast hit for shock/slow application (non-interrupting).
		pass


func _on_boss_telegraph(kind: StringName, duration: float) -> void:
	if _dead:
		return
	var clip := KEY_CAST if _clips.has(KEY_CAST) else KEY_ATTACK
	# Scale cast to telegraph duration so anticipation reads synchronously.
	var cname := _clip(clip)
	if _player != null and cname != "" and _player.has_animation(cname):
		var anim := _player.get_animation(cname)
		var speed := clampf(anim.length / maxf(duration, 0.2), 0.5, 2.5)
		_one_shot(clip, speed)
	else:
		_one_shot(clip)

## Stagger feedback arrives through the Hurt STATE (poise-guarded hits intentionally
## do not play the flinch — the EnemyFeedback flash covers them).


func _on_died() -> void:
	_dead = true
	_one_shot(KEY_DEATH)


func _loop(key: StringName) -> void:
	var clip := _clip(key)
	if clip == "" or _player == null:
		return
	if _player.current_animation == clip:
		return
	_player.speed_scale = 1.0
	_player.play(clip)


func _hold_pose(key: StringName) -> void:
	var clip := _clip(key)
	if clip == "" or _player == null:
		return
	# Tiny speed so a later ATTACK one-shot on the same clip is not skipped.
	_player.play(clip, -1.0, 0.05)
	_player.seek(0.0, true)


func _one_shot(key: StringName, speed: float = 1.0) -> void:
	var clip := _clip(key)
	if clip == "" or _player == null:
		return
	var blend := 0.08
	if key == KEY_ATTACK:
		var cfg := _host.get_config() if _host != null else null
		blend = 0.08 if cfg != null and cfg.attack_windup < 0.2 else 0.12
	_player.play(clip, blend, maxf(speed, 0.05))
	if key == KEY_DEATH:
		var anim := _player.get_animation(clip)
		if anim != null and anim.resource_local_to_scene == false:
			var copy := anim.duplicate() as Animation
			copy.loop_mode = Animation.LOOP_NONE
			copy.resource_local_to_scene = true
			# Replace only this player's view of the clip.
			anim.loop_mode = Animation.LOOP_NONE
	if _player.current_animation_position > 0.04:
		_player.seek(0.0, true)


func _clip(key: StringName) -> String:
	if not _clips.has(key):
		return ""
	return String(_clips[key])
