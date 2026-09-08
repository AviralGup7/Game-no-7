class_name PlayerAnimation
extends Node

## Cosmetic only: clips never apply damage or move the collision body.
## Contact is aligned to the authoritative windup, not animation method tracks.
@export var idle_clip: StringName = &"Idle"
@export var walk_clip: StringName = &"Walking_A"
@export var run_clip: StringName = &"Running_A"
@export var attack_clips: Array[StringName] = [&"1H_Melee_Attack_Slice_Horizontal", &"1H_Melee_Attack_Slice_Diagonal", &"1H_Melee_Attack_Chop"]
@export var weapon_attack_clips: Dictionary[StringName, StringName] = {
	&"sentinel_spear": &"2H_Melee_Attack_Stab",
	&"stormhammer": &"2H_Melee_Attack_Chop",
	&"warreaxe": &"2H_Melee_Attack_Slice",
	&"twinfangs": &"Dualwield_Melee_Attack_Slice",
	&"ember_scepter": &"Spellcast_Shoot",
	&"moonlance": &"2H_Melee_Attack_Stab",
	&"venom_chain": &"Dualwield_Melee_Attack_Slice",
}
@export var ranged_clip: StringName = &"2H_Ranged_Shoot"
@export var dodge_clip: StringName = &"Dodge_Forward"
@export var hurt_clip: StringName = &"Hit_A"
@export var death_clip: StringName = &"Death_A"
@export var reload_clip: StringName = &"2H_Ranged_Reload"
@export var victory_clip: StringName = &"Cheer"
@export var skill_cast_clips: Dictionary[StringName, StringName] = {
	&"bladestorm": &"2H_Melee_Attack_Spin",
	&"phantom_rush": &"Dodge_Forward",
	&"seismic_slam": &"2H_Melee_Attack_Chop",
	&"frost_nova": &"Spellcast_Shoot",
	&"frost_nova_skill": &"Spellcast_Shoot",
	&"warcry": &"Spellcast_Raise",
	&"warcry_skill": &"Spellcast_Raise",
	&"mending_light": &"Spellcast_Raise",
	&"chain_lightning": &"Spellcast_Shoot",
	&"shatterwave": &"Spellcast_Shoot",
}
@export_range(0.05, 0.9) var contact_fraction: float = 0.32
@export var blend_seconds: float = 0.07
@export var walk_cycle_distance: float = 1.8
@export var run_cycle_distance: float = 3.6

var _player: Player
var _animation: AnimationPlayer
var _weapons: WeaponManager
var _locked := false
var _dead := false
var _attack_clip: StringName = &""
var _reloading := false
var _contact_aligned := false
var _paused_for_control := false
# LEGACY ISOLATED: AttackController not used for animation timing.
# Authoritative timing is WeaponInstance (windup/cooldown/reload) only.


func _ready() -> void:
	_player = get_parent() as Player
	_weapons = _player.get_node_or_null("WeaponManager") as WeaponManager
	var char_root := _player.get_node_or_null("VisualRoot/CharacterModel")
	_animation = (char_root.find_child("AnimationPlayer", true, false) as AnimationPlayer) if char_root != null else null
	if _animation == null:
		set_physics_process(false)
		return
	# Only the three loop clips need private resources; other imported clips stay shared.
	for library_name in _animation.get_animation_library_list():
		var library := _animation.get_animation_library(library_name).duplicate() as AnimationLibrary
		for clip in [idle_clip, walk_clip, run_clip]:
			if library.has_animation(clip):
				var loop := library.get_animation(clip).duplicate() as Animation
				loop.loop_mode = Animation.LOOP_LINEAR
				library.remove_animation(clip)
				library.add_animation(clip, loop)
		_animation.remove_animation_library(library_name)
		_animation.add_animation_library(library_name, library)
	_animation.animation_finished.connect(_on_finished)
	_player.attack_started.connect(_on_attack)
	_player.dodged.connect(_on_dodge)
	_player.damaged.connect(_on_hurt)
	_player.died.connect(_on_death)
	_player.respawned.connect(reset)
	if _weapons != null:
		_weapons.attack_resolved.connect(_on_contact)
		_weapons.weapon_switched_local.connect(_on_switch)
	if EventBus != null:
		if not EventBus.skill_cast.is_connected(_on_skill_cast):
			EventBus.skill_cast.connect(_on_skill_cast)
		if not EventBus.player_leveled_up.is_connected(_on_level_up):
			EventBus.player_leveled_up.connect(_on_level_up)
		if not EventBus.boss_slain.is_connected(_on_boss_victory):
			EventBus.boss_slain.connect(_on_boss_victory)
	_play(idle_clip)


func _physics_process(_delta: float) -> void:
	if _dead:
		return
	if not _player.is_control_enabled():
		if not _paused_for_control:
			_animation.pause()
			_paused_for_control = true
		return
	if _paused_for_control:
		_paused_for_control = false
		_animation.play()
	var inst := _weapons.active_instance() if _weapons != null else null
	var reloading := inst != null and inst.is_reloading()
	if reloading and not _reloading:
		_locked = true
		_play(reload_clip, true, _length(reload_clip) / maxf(inst.reload_remaining(), 0.01))
	_reloading = reloading
	if _locked:
		return
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var clip := idle_clip if speed < 0.15 else (walk_clip if speed < 3.0 else run_clip)
	var playback := 1.0
	if clip != idle_clip:
		var stride := walk_cycle_distance if clip == walk_clip else run_cycle_distance
		playback = clampf(speed * _length(clip) / maxf(stride, 0.1), 0.08, 2.0)
	_play(clip, false, playback)


func _on_attack() -> void:
	if _dead:
		return
	var inst := _weapons.active_instance() if _weapons != null else null
	_contact_aligned = false
	var step := 1
	var windup := 0.12
	if inst != null:
		step = inst.combo_step
		windup = inst.config.windup
	_attack_clip = attack_clips[(maxi(step, 1) - 1) % attack_clips.size()] if not attack_clips.is_empty() else &"1H_Melee_Attack_Chop"
	if inst != null and inst.config.is_ranged() and not inst.config.is_melee():
		_attack_clip = ranged_clip
	if inst != null and weapon_attack_clips.has(inst.config.weapon_id):
		_attack_clip = weapon_attack_clips[inst.config.weapon_id]
	_locked = true
	_play(_attack_clip, true, _length(_attack_clip) * contact_fraction / maxf(windup, 0.01))


func _on_contact(_id: StringName, _hits: int, _crit: bool) -> void:
	var inst := _weapons.active_instance()
	if inst != null:
		_align_contact(inst.effective_cooldown())


func _align_contact(recovery: float) -> void:
	if _dead or _contact_aligned or _attack_clip == &"" or _animation.current_animation != String(_attack_clip):
		return
	_contact_aligned = true
	var length := _length(_attack_clip)
	_animation.seek(length * contact_fraction, true)
	_animation.speed_scale = length * (1.0 - contact_fraction) / maxf(recovery, 0.05)


func _on_dodge() -> void:
	if _dead:
		return
	var dodge := _player.get_node_or_null("DodgeController") as DodgeController
	if dodge == null:
		return
	_locked = true
	# Directional dodge: pick Forward/Backward/Left/Right based on dodge vector vs facing.
	var clip := dodge_clip
	if _animation != null and dodge.has_method("get_dodge_direction"):
		var dir: Vector3 = dodge.call("get_dodge_direction")
		if dir.length_squared() > 0.0001 and _player != null:
			var facing := -_player.global_transform.basis.z
			facing.y = 0.0
			if facing.length_squared() < 0.0001:
				facing = Vector3.FORWARD
			else:
				facing = facing.normalized()
			dir.y = 0.0
			dir = dir.normalized()
			var fwd := facing.dot(dir)
			var right := facing.cross(dir).y  # +right = dodge is to the right of facing
			# Prefer cardinal direction with largest component
			if absf(fwd) > absf(right):
				clip = &"Dodge_Forward" if fwd > 0 else &"Dodge_Backward"
			else:
				clip = &"Dodge_Right" if right > 0 else &"Dodge_Left"
			# Fallback if clip missing in this rig
			if not _animation.has_animation(clip):
				clip = dodge_clip
	_play(clip, true, _length(clip) / maxf(dodge.duration + dodge.recovery_duration, 0.01))


func _on_hurt(result: DamageResult) -> void:
	if _dead or result.target_died:
		return
	_locked = true
	_play(hurt_clip, true, 2.0)


func _on_skill_cast(skill_id: StringName, caster: Node) -> void:
	if _dead or caster != _player:
		return
	var clip: StringName = skill_cast_clips.get(skill_id, &"Spellcast_Shoot")
	if String(clip).is_empty() or not _animation.has_animation(clip):
		clip = &"Spellcast_Shoot"
		if not _animation.has_animation(clip):
			clip = idle_clip
	_locked = true
	# Skill cast is brief: align to ~0.4s so it reads but doesn't freeze combat.
	_play(clip, true, _length(clip) / 0.45)


func _on_level_up(_new_level: int, _xp: int) -> void:
	if _dead:
		return
	_locked = true
	_play(victory_clip if _animation.has_animation(victory_clip) else idle_clip, true, 1.1)


func _on_boss_victory(_boss_id: StringName) -> void:
	if _dead:
		return
	_locked = true
	_play(victory_clip if _animation.has_animation(victory_clip) else idle_clip, true, 0.9)


func _on_death() -> void:
	_dead = true
	_locked = true
	_play(death_clip, true)


func _on_switch(_old: StringName, _new: StringName) -> void:
	if not _dead:
		_locked = false
		_reloading = false
		_play(idle_clip, true)


func reset() -> void:
	_paused_for_control = false
	_dead = false
	_locked = false
	_reloading = false
	_attack_clip = &""
	_play(idle_clip, true)


func _on_finished(_clip: StringName) -> void:
	if not _dead:
		_locked = false


func _length(clip: StringName) -> float:
	return _animation.get_animation(clip).length if _animation.has_animation(clip) else 0.3


func _play(clip: StringName, restart: bool = false, speed: float = 1.0) -> void:
	if not _animation.has_animation(clip):
		_locked = _dead
		return
	if not is_equal_approx(_animation.speed_scale, maxf(speed, 0.01)):
		_animation.speed_scale = maxf(speed, 0.01)
	if not restart and _animation.current_animation == String(clip):
		return
	_animation.play(clip, blend_seconds)
	if restart:
		_animation.seek(0.0, true)

## Hardened: validate animation speed.
func _validated_anim_speed(s: float) -> float:
	if not is_finite(s) or s <= 0.0:
		return 1.0
	return clampf(s, 0.1, 4.0)

