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
var _ik_dampen := false
var _ik_dampen_hold := 0.0
# Animation timing is driven only by WeaponInstance (windup/cooldown/reload);
# there is no legacy attack-controller timing path anymore.


func _ready() -> void:
	_player = get_parent() as Player
	_weapons = _player.get_node_or_null("WeaponManager") as WeaponManager
	_connect_combat_signals()
	if not _bind_animation():
		# The model mount (VisualMount) normally runs first, but never depend on
		# sibling order: retry once after every _ready has run.
		set_physics_process(false)
		call_deferred("_bind_animation_deferred")


func _bind_animation_deferred() -> void:
	if _bind_animation():
		set_physics_process(true)


## Locate the mounted rig's AnimationPlayer and prepare private loop clips.
## Returns false when no rig is mounted yet (the fallback capsule stays visible).
func _bind_animation() -> bool:
	if _animation != null:
		return true
	if _player == null:
		return false
	var char_root := _player.get_node_or_null("VisualRoot/CharacterModel")
	_animation = HeroRigContract.animation_player(char_root)
	if _animation == null:
		return false
	var visual := _character_visual()
	if visual != null and bool(visual.get_meta(HeroRigContract.AUTHORED_IDLE_META, false)):
		# Stride distances are measured on the retargeted adult-length leg chains.
		walk_cycle_distance = 1.6
		run_cycle_distance = 2.1
	# The mount auto-plays its idle clip; stop it before swapping libraries.
	_animation.stop()
	# Only the three loop clips need private resources; other imported clips stay shared.
	for library_name in _animation.get_animation_library_list():
		var library := _animation.get_animation_library(library_name).duplicate() as AnimationLibrary
		for clip in [idle_clip, walk_clip, run_clip]:
			if library.has_animation(clip):
			var loop := library.get_animation(clip).duplicate() as Animation
			loop.loop_mode = Animation.LOOP_LINEAR
			_lock_hip_xz(loop)
			library.remove_animation(clip)
			library.add_animation(clip, loop)
		_animation.remove_animation_library(library_name)
		_animation.add_animation_library(library_name, library)
	_animation.animation_finished.connect(_on_finished)
	_animation.root_motion_track = NodePath()
	_locked = false
	_play(idle_clip)
	return true


static func _lock_hip_xz(anim: Animation) -> void:
	if anim == null:
		return
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(anim.track_get_path(i)).to_lower()
		if "hips" not in path and "pelvis" not in path and "root" not in path:
			continue
		for k in range(anim.track_get_key_count(i)):
			var value: Variant = anim.track_get_key_value(i, k)
			if value is Vector3:
				var v := value as Vector3
				v.x = 0.0
				v.z = 0.0
				anim.track_set_key_value(i, k, v)


## Gameplay signals stay connected even when no rig is mounted, so a late mount
## (or the fallback capsule) never leaves animation permanently unwired.
func _connect_combat_signals() -> void:
	if _player == null:
		return
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


func _exit_tree() -> void:
	if EventBus == null:
		return
	if EventBus.skill_cast.is_connected(_on_skill_cast):
		EventBus.skill_cast.disconnect(_on_skill_cast)
	if EventBus.player_leveled_up.is_connected(_on_level_up):
		EventBus.player_leveled_up.disconnect(_on_level_up)
	if EventBus.boss_slain.is_connected(_on_boss_victory):
		EventBus.boss_slain.disconnect(_on_boss_victory)


func _pin_visual_xz() -> void:
	if _player == null:
		return
	var visual := _player.get_node_or_null("VisualRoot") as Node3D
	if visual != null:
		visual.position.x = 0.0
		visual.position.z = 0.0
	var model := _player.get_node_or_null("VisualRoot/CharacterModel") as Node3D
	if model != null:
		model.position.x = 0.0
		model.position.z = 0.0


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_pin_visual_xz()
	var plant := FootPlant.apply(_player, 0.14, _delta)
	var want_dampen := absf(plant) > 0.06
	if want_dampen == _ik_dampen:
		_ik_dampen_hold = 0.0
	else:
		_ik_dampen_hold += _delta
		if _ik_dampen_hold >= 0.2:
			_ik_dampen = want_dampen
			_ik_dampen_hold = 0.0
	var equipment := _player.get_node_or_null("PlayerEquipment") as PlayerEquipment if _player != null else null
	if equipment != null:
		equipment.set_slope_ik_dampen(_ik_dampen)
	else:
		_ik_dampen_hold = 0.0
	if _animation == null:
		return
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
	if _hold_bow_draw(inst):
		return
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var clip := idle_clip if speed < 0.15 else (walk_clip if speed < 3.0 else run_clip)
	var playback := 1.0
	if clip != idle_clip:
		var stride := walk_cycle_distance if clip == walk_clip else run_cycle_distance
		playback = clampf(speed * _length(clip) / maxf(stride, 0.1), 0.08, 2.8)
	_play(clip, false, playback)


## Sunbow: freeze on the nocked frame of 2H_Ranged_Shoot (or Aiming if present)
## while the string is held, then the attack clip plays the release.
func _hold_bow_draw(inst: WeaponInstance) -> bool:
	if inst == null or inst.config == null:
		return false
	if inst.config.weapon_id != &"sunbow":
		return false
	if not inst.config.is_ranged():
		return false
	var aim := &"2H_Ranged_Aiming"
	if _animation != null and _animation.has_animation(aim):
		_play(aim, false, 0.15)
		return true
	_play(ranged_clip, false, 0.01)
	if _animation != null and _animation.current_animation == String(ranged_clip):
		var hold := _length(ranged_clip) * 0.28
		if _animation.current_animation_position > hold + 0.02:
			_animation.seek(hold, true)
	return true


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
	if _animation == null or _dead or _contact_aligned or _attack_clip == &"" or _animation.current_animation != String(_attack_clip):
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
	if _animation != null:
		clip = HeroRigContract.directional_dodge(-_player.global_transform.basis.z, dodge.get_dodge_direction())
		if not _animation.has_animation(clip):
			clip = dodge_clip
	_play(clip, true, _length(clip) / maxf(dodge.duration + dodge.recovery_duration, 0.01))


func _on_hurt(result: DamageResult) -> void:
	if _dead or result.target_died:
		return
	_locked = true
	_play(hurt_clip, true, 2.0)


func _on_skill_cast(skill_id: StringName, caster: Node) -> void:
	if _animation == null or _dead or caster != _player:
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
	if _animation == null or _dead:
		return
	_locked = true
	_play(victory_clip if _animation.has_animation(victory_clip) else idle_clip, true, 1.1)


func _on_boss_victory(_boss_id: StringName) -> void:
	if _animation == null or _dead:
		return
	_locked = true
	_play(victory_clip if _animation.has_animation(victory_clip) else idle_clip, true, 0.9)


func _on_death() -> void:
	_dead = true
	_locked = true
	_ik_dampen = false
	_ik_dampen_hold = 0.0
	var equipment := _player.get_node_or_null("PlayerEquipment") as PlayerEquipment if _player != null else null
	if equipment != null:
		equipment.reset_ik_dampen()
	var model := _player.get_node_or_null("VisualRoot/CharacterModel") as Node3D if _player != null else null
	if model != null:
		model.position.y = 0.0
	CharacterVisuals.stop_breathing(_character_visual())
	_play(death_clip, true)


func _on_switch(_old: StringName, _new: StringName) -> void:
	_ik_dampen = false
	_ik_dampen_hold = 0.0
	var equipment := _player.get_node_or_null("PlayerEquipment") as PlayerEquipment if _player != null else null
	if equipment != null:
		equipment.reset_ik_dampen()
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
	_contact_aligned = false
	var model := _player.get_node_or_null("VisualRoot/CharacterModel") as Node3D if _player != null else null
	if model != null:
		model.position.y = 0.0
	CharacterVisuals.start_breathing(_character_visual())
	_play(idle_clip, true)


func _character_visual() -> Node3D:
	if _player == null:
		return null
	return _player.get_node_or_null("VisualRoot/CharacterModel/CharacterVisual") as Node3D


func _on_finished(_clip: StringName) -> void:
	if not _dead:
		_locked = false


func _length(clip: StringName) -> float:
	if _animation == null or not _animation.has_animation(clip):
		return 0.3
	# `has_animation` only proves the name is registered: the resource behind it can be
	# null or (for a condition-baked clip) carry a non-positive/NaN length, and this
	# value is used as a divisor for the playback speed_scale.
	var anim := _animation.get_animation(clip)
	if anim == null or not is_finite(anim.length) or anim.length <= 0.0:
		return 0.3
	return anim.length


func _play(clip: StringName, restart: bool = false, speed: float = 1.0) -> void:
	if _animation == null:
		_locked = _dead
		return
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

