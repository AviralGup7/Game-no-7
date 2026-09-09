extends RefCounted
## Focused independent suite; no edit to the shared multi-agent test runner.
## godot --headless --path . --script res://tests/run_player_tests.gd

class Target extends Damageable:
	var alive := true
	var hits := 0

	func is_alive() -> bool:
		return alive

	func apply_damage(_payload: DamagePayload) -> DamageResult:
		hits += 1
		var result := DamageResult.new()
		result.accepted = true
		result.final_amount = 12.0
		return result

class Juice extends Node:
	var requests := 0
	var trauma := 0.0

	func request_hitstop(_duration: float) -> void:
		requests += 1

	func add_trauma(amount: float) -> void:
		trauma += amount

var root: Window
var _completed_cases := 0
var _checks := 0
var _failures: Array[String] = []


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures.append(label)


func run(viewport: Window) -> Dictionary:
	root = viewport
	_test_buffer()
	_test_combo_and_interrupt()
	_test_dodge_timing()
	_test_motion_and_targeting()
	_test_player_scene()
	_check("all integration scenarios reached completion", _completed_cases == 6)
	return {"checks": _checks, "failures": _failures}


func _test_buffer() -> void:
	var buffer := AttackBuffer.new()
	var count := [0]
	var accept := func() -> bool:
		count[0] += 1
		return true
	buffer.push(0.18)
	buffer.tick(0.02, func() -> bool: return false)
	_check("rejected buffered press remains pending", buffer.remaining > 0.0)
	buffer.tick(0.02, accept)
	buffer.tick(0.02, accept)
	_check("buffer consumes exactly one press", count[0] == 1 and buffer.remaining == 0.0)
	buffer.push(0.1)
	buffer.tick(0.11, accept)
	_check("expired input never fires", count[0] == 1)
	buffer.push(0.1)
	buffer.clear()
	buffer.tick(0.01, accept)
	_check("cancel clears queued attack", count[0] == 1)

	_completed_cases += 1

func _test_combo_and_interrupt() -> void:
	# Combo chaining is owned by WeaponInstance (combo_step / _chain_left); the
	# legacy ComboChain helper was removed with AttackController.
	var config := WeaponConfig.new()
	config.ammo_per_magazine = 4
	config.windup = 0.1
	config.reload_seconds = 0.2
	var inst := WeaponInstance.new(config, 17)
	inst.try_start_attack()
	inst.cancel_attack()
	_check("interrupt cannot refill ammunition", inst.ammo == 3)
	_check("interrupt retains recovery", inst.phase == WeaponInstance.PHASE_RECOVERY and inst.try_start_attack() == 0)
	_check("cancelled windup cannot hit", not inst.tick(0.05))
	inst.tick(1.0)
	_check("interrupted weapon eventually ready", inst.is_ready())
	inst.start_reload()
	inst.cancel_attack()
	_check("interrupt preserves reload timer", inst.is_reloading())
	inst.tick(0.25)
	_check("reload still restores magazine", inst.ammo == 4)

	_completed_cases += 1

func _test_dodge_timing() -> void:
	var body := CharacterBody3D.new()
	var dodge := DodgeController.new()
	body.add_child(dodge)
	root.add_child(body)
	dodge.duration = 0.1
	dodge.distance = 1.0
	dodge.recovery_duration = 0.1
	dodge.cooldown = 0.2
	dodge.request(Vector3.RIGHT)
	dodge.tick(0.05)
	_check("dodge burst uses distance divided by duration", is_equal_approx(body.velocity.x, 10.0))
	dodge.tick(0.1)
	_check("last dodge step clips burst travel", is_equal_approx(body.velocity.x, 5.0))
	_check("burst overshoot carries into recovery", dodge.get_phase() == DodgeController.PHASE_RECOVER and is_equal_approx(dodge._elapsed, 0.05))
	dodge.tick(0.2)
	_check("recovery overshoot carries into cooldown", is_equal_approx(dodge.get_cooldown_remaining(), 0.05))
	dodge.tick(0.06)
	_check("overshot dodge cycle can return ready", dodge.is_ready())
	body.free()

	_completed_cases += 1

func _test_motion_and_targeting() -> void:
	var body := CharacterBody3D.new()
	var controller := CharacterController.new()
	body.add_child(controller)
	root.add_child(body)
	_check("touch right maps world right", controller.screen_to_world_dir(Vector2.RIGHT).is_equal_approx(Vector3.RIGHT))
	_check("touch up maps world forward", controller.screen_to_world_dir(Vector2.UP).is_equal_approx(Vector3.FORWARD))
	_check("analog magnitude preserved", is_equal_approx(controller.screen_to_world_dir(Vector2(0.25, 0)).length(), 0.25))
	_check("diagonal magnitude capped", is_equal_approx(controller.screen_to_world_dir(Vector2(1, 1)).length(), 1.0))
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.rotation.y = PI / 2.0
	camera.make_current()
	_check("movement follows camera yaw", controller.screen_to_world_dir(Vector2.UP).is_equal_approx(Vector3.LEFT))
	controller.face_direction(Vector3.RIGHT)
	_check("body and combat forward rotate together", (-body.global_basis.z).is_equal_approx(Vector3.RIGHT))
	camera.free()
	var locomotion := PlayerLocomotion.new()
	locomotion.bind(body, null, controller)
	locomotion.set_using_actions(false)
	locomotion.set_move_input(Vector2(0.3, -0.2))
	_check("touch command remains authoritative", locomotion.gather() == Vector2(0.3, -0.2))
	locomotion.set_bounds(5.0)
	body.position = Vector3(6, 0, 0)
	body.velocity = Vector3(4, 0, 3)
	locomotion.clamp_to_bounds()
	_check("bounds preserve tangential wall slide", body.position.x == 4.5 and body.velocity == Vector3(0, 0, 3))
	locomotion.set_bounds(0.1)
	locomotion.clamp_to_bounds()
	_check("tiny bounds cannot invert clamp", body.position.x == 0.0)
	var before_stop := body.position
	locomotion.clear_and_idle()
	_check("touch stop does not integrate physics", body.position == before_stop and body.velocity.x == 0.0 and body.velocity.z == 0.0)
	var targeting := TargetingComponent.new()
	body.add_child(targeting)
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	var near := Target.new()
	var far := Target.new()
	root.add_child(near)
	root.add_child(far)
	near.position = Vector3(0, 0, 1)
	far.position = Vector3(0, 0, -8)
	_check("close rear threat beats distant forward target", targeting.pick_best_target([far, near]) == near)
	near.alive = false
	_check("dead targets are filtered", targeting.pick_best_target([near, far]) == far)
	far.position.z = -20
	_check("range rejects distant targets", targeting.pick_best_target([near, far]) == null)
	far.position = Vector3(0, 0, -2)
	near.alive = true
	near.position = far.position
	_check("target ties preserve deterministic input order", targeting.pick_best_target([near, far]) == near)
	near.free()
	far.free()
	body.free()

	_completed_cases += 1

func _test_player_scene() -> void:
	var registry := root.get_node("ContentRegistry")
	var bus := root.get_node("EventBus")
	var audio := root.get_node("AudioManager")
	var save := root.get_node("SaveManager")
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	_check("canonical player scene loads", packed != null)
	if packed == null:
		return
	var source_scene := load(HeroRigContract.MODEL_PATH) as PackedScene
	var source_model := source_scene.instantiate()
	var source_animation := HeroRigContract.animation_player(source_model)
	var source_idle := source_animation.get_animation(&"Idle")
	var source_loop_mode := source_idle.loop_mode
	source_model.free()
	var player := packed.instantiate() as Player
	root.add_child(player)
	# Explicit fake-clock ticks below, never depend on test runner wall time.
	player.set_physics_process(false)
	for node in player.find_children("*", "Node", true, false):
		node.set_physics_process(false)
	player.enable_action_input(false)
	player.reset_for_new_run(Transform3D.IDENTITY)
	player.set_control_enabled(true)
	_test_touch(player)
	var manager := player.get_node("WeaponManager") as WeaponManager
	var dodge := player.get_node("DodgeController") as DodgeController
	var stamina := player.get_node("StaminaComponent") as StaminaComponent
	var animation := player.get_node("PlayerAnimation") as PlayerAnimation
	var equipment := player.get_node("PlayerEquipment") as PlayerEquipment
	var feedback := player.get_node("PlayerFeedback") as PlayerFeedback
	var health := player.get_node("HealthComponent") as HealthComponent
	_check("Warden animation player found", animation._animation != null)
	if animation._animation == null:
		player.free()
		return
	var hero := player.get_node("VisualRoot/CharacterModel/CharacterVisual") as Node3D
	_check("player uses production Warden, not fallback", hero.get_meta(HeroRigContract.MODEL_PATH_META, "") == HeroRigContract.MODEL_PATH)
	_check("idle bob cannot detach feet from arena", not hero.has_meta(CharacterVisuals.BREATHING_TWEEN_META))
	for clip in HeroRigContract.REQUIRED_CLIPS:
		_check("supplied clip: " + String(clip), animation._animation.has_animation(clip))
	_check("locomotion loops do not mutate source animations", source_idle.loop_mode == source_loop_mode and animation._animation.get_animation(&"Idle") != source_idle)
	_check("equipped starter has model and hand socket", equipment._model != null and equipment._socket.bone_idx >= 0)
	player.velocity = Vector3(1, 0, 0)
	animation._physics_process(0.01)
	_check("slow analog motion walks", animation._animation.current_animation == "Walking_A")
	player.velocity = Vector3(6, 0, 0)
	animation._physics_process(0.01)
	_check("fast motion runs", animation._animation.current_animation == "Running_A")
	_check("run playback follows travelled stride", is_equal_approx(animation._animation.speed_scale, 6.0 * animation._length(&"Running_A") / animation.run_cycle_distance))
	player.velocity = Vector3.ZERO
	animation._physics_process(0.01)
	_check("stopped motion idles", animation._animation.current_animation == "Idle")
	var target := Target.new()
	target.add_to_group("enemies")
	root.add_child(target)
	target.position = Vector3(1.0, 0, 0)
	var starts := [0]
	player.attack_started.connect(func() -> void: starts[0] += 1)
	player.request_attack()
	_check("weapon path emits attack start", starts[0] == 1)
	_check("attack faces selected enemy", (-player.global_basis.z).dot(Vector3.RIGHT) > 0.99)
	_check("attack plays actual swing", animation._animation.current_animation == "1H_Melee_Attack_Slice_Horizontal")
	manager.tick(0.01)
	_check("windup cannot hit early", target.hits == 0)
	player.request_attack()
	manager.tick(0.2)
	_check("melee resolves once at contact", target.hits == 1)
	_check("contact frame stays aligned to authoritative windup", is_equal_approx(animation._animation.current_animation_position, animation._length(animation._attack_clip) * animation.contact_fraction))
	player._attack_buffer.tick(0.01, player._try_attack)
	_check("early combo input is buffered", starts[0] == 2 and manager.active_instance().combo_step == 2)
	player._attack_buffer.tick(0.01, player._try_attack)
	_check("buffer cannot create extra swings", starts[0] == 2)
	player.set_move_input(Vector2.ZERO)
	var before := stamina.get_current()
	_check("standing dodge accepted", player.request_dodge())
	_check("dodge follows facing", dodge._dir.dot(Vector3.RIGHT) > 0.99)
	_check("accepted dodge spends configured stamina", stamina.get_current() == before - dodge.stamina_cost)
	before = stamina.get_current()
	stamina._since_spend = 0.4
	_check("cooldown rejects repeated dodge", not player.request_dodge())
	_check("rejected dodge does not spend stamina", stamina.get_current() == before)
	_check("rejected dodge does not delay stamina regeneration", stamina._since_spend == 0.4)
	_check("dodge cancels attack chain", manager.active_instance().combo_step == 0)
	_check("dodge uses actual animation", animation._animation.current_animation == "Dodge_Forward")
	var payload := DamagePayload.new()
	payload.amount = 5.0
	payload.status_effects = [&"burn"]
	var statuses := player.get_node("StatusManager") as StatusManager
	statuses.apply_effect(registry.get_status_effect(&"guard"))
	var shield := statuses.shield_remaining()
	_check("dodge grants real invulnerability", not player.apply_damage(payload).accepted)
	_check("ignored damage cannot apply status riders", not statuses.has_effect(&"burn"))
	_check("dodged damage cannot consume shields", statuses.shield_remaining() == shield)
	statuses.clear_all()
	payload.status_effects.clear()
	var clock := player._health_now()
	player.set_control_enabled(false)
	player._physics_process(10.0)
	_check("modal controls freeze dodge health clock", player._health_now() == clock and health.is_invulnerable())
	player.set_control_enabled(true)
	feedback._physics_process(0.01)
	_check("invulnerability has cyan mesh feedback", feedback._last_color.b > feedback._last_color.r)
	dodge.tick(dodge.duration)
	dodge.tick(0.01)
	_check("recovery no longer adds full-speed travel", is_zero_approx(player.velocity.x) and is_zero_approx(player.velocity.z))
	dodge.tick(dodge.recovery_duration)
	dodge.tick(2.0)
	_check("dodge cooldown returns to ready", dodge.is_ready())
	player._gameplay_time += 1.0
	_check("invulnerability ends in gameplay time", not health.is_invulnerable())
	player.apply_damage(payload)
	_check("accepted damage plays hurt clip", animation._animation.current_animation == "Hit_A")
	feedback._physics_process(0.01)
	_check("hit feedback uses real mesh overlay", feedback._meshes[0].material_overlay != null)
	health.current_health = 20.0
	feedback._physics_process(1.0)
	_check("low health uses steady red cue", feedback._last_color.r > feedback._last_color.b and feedback._last_color.a > 0.0)
	var ranged: WeaponConfig = registry.get_weapon(&"sunbow")
	manager.equip(ranged, 1)
	_check("weapon command switches loadout", player.request_weapon_switch())
	_check("equipped model follows weapon ID", equipment._equipped == &"sunbow" and equipment._model != null)
	player.request_attack()
	_check("ranged clip selected", animation._animation.current_animation == "2H_Ranged_Shoot")
	bus.emit_signal("projectile_fired", player, &"sunbow")
	_check("shot event displays muzzle feedback", equipment._muzzle.visible)
	equipment._process(0.1)
	_check("muzzle flash expires", not equipment._muzzle.visible)
	player.request_weapon_switch()
	manager.tick(3.0)
	_check("holstered cooldown advances", manager.slot_instance(1).is_ready())
	# Exported cost, interruption policy, exhaustion and stun apply to touch commands too.
	dodge.reset()
	manager.tick(2.0)
	dodge.can_interrupt_attack = false
	player.request_attack()
	before = stamina.get_current()
	_check("dodge respects non-interruptible attack policy", not player.request_dodge() and stamina.get_current() == before)
	dodge.can_interrupt_attack = true
	player._cancel_combat()
	stamina.restore_full()
	stamina.try_spend(stamina.get_max())
	_check("exhaustion blocks dodge without starting cooldown", not player.request_dodge() and dodge.is_ready())
	stamina.restore_full()
	dodge.stamina_cost = 10.0
	_check("exported dodge cost is used", player.request_dodge() and stamina.get_current() == 90.0)
	dodge.reset()
	player._gameplay_time += 1.0
	statuses.apply_effect(registry.get_status_effect(&"stun"))
	var starts_before: int = starts[0]
	player.request_attack()
	_check("stun rejects attack commands", starts[0] == starts_before)
	_check("stun rejects dodge and switch commands", not player.request_dodge() and not player.request_weapon_switch())
	statuses.clear_all()
	# Reload-start signal also covers the automatic empty-magazine path.
	var ammo_config := WeaponConfig.new()
	ammo_config.weapon_id = &"test_ammo"
	ammo_config.ammo_per_magazine = 1
	ammo_config.reload_seconds = 0.2
	manager.equip(ammo_config, 1)
	manager.switch_to(1)
	var ammo_inst := manager.active_instance()
	ammo_inst.ammo = 0
	var reloads := [0]
	manager.reload_started.connect(func(_id: StringName) -> void: reloads[0] += 1)
	player.request_attack()
	_check("automatic reload emits existing signal once", reloads[0] == 1 and ammo_inst.is_reloading())
	animation._physics_process(0.01)
	_check("reload uses supplied animation", animation._animation.current_animation == "2H_Ranged_Reload")
	player.set_control_enabled(false)
	player.request_attack()
	_check("disabled controls reject attacks", not player.is_control_enabled() and player._attack_buffer.remaining == 0.0)
	player.set_move_input(Vector2.RIGHT)
	_check("modal touch input cannot leak into resume", player._locomotion.current_input() == Vector2.ZERO)
	animation._physics_process(0.01)
	_check("modal controls pause live animation", animation._paused_for_control and not animation._animation.is_playing())
	player.set_control_enabled(true)
	player._on_died()
	_check("death is terminal animation", animation._dead and animation._animation.current_animation == "Death_A")
	_check("death clears velocity and attack input", player.velocity == Vector3.ZERO and player._attack_buffer.remaining == 0.0)
	animation._on_finished(&"Death_A")
	animation._physics_process(1.0)
	_check("death pose cannot return to idle", animation._animation.current_animation == "Death_A")
	player.reset_for_new_run(Transform3D.IDENTITY)
	_check("respawn resets animation and feedback", not animation._dead and animation._animation.current_animation == "Idle" and feedback._last_color == Color.TRANSPARENT)
	_check("respawn cannot restart whole-body bob", not hero.has_meta(CharacterVisuals.BREATHING_TWEEN_META))
	for side in [&"Dodge_Forward", &"Dodge_Backward", &"Dodge_Left", &"Dodge_Right"]:
		var direction: Vector3 = {&"Dodge_Forward": Vector3.FORWARD, &"Dodge_Backward": Vector3.BACK, &"Dodge_Left": Vector3.LEFT, &"Dodge_Right": Vector3.RIGHT}[side]
		player.rotation.y = 0.0
		dodge._dir = direction
		animation._on_dodge()
		_check("runtime directional dodge: " + String(side), animation._animation.current_animation == String(side))
	animation.reset()
	for weapon_id in equipment.models:
		manager.equip(registry.get_weapon(weapon_id), 0)
		manager.switch_to(0)
		_check("model mapping: " + String(weapon_id), equipment._model != null)
		if equipment._model != null:
			_check("source grip preserved: " + String(weapon_id), (equipment._model.get_child(0) as Node3D).position == Vector3.ZERO)
		if weapon_id == &"sunbow":
			_check("bow long axis uses the aiming socket's up direction", equipment._model.basis.y.normalized().is_equal_approx(Vector3.BACK))
		if weapon_id == &"twinfangs":
			_check("dual wield has offhand dagger", equipment._second_model != null)
	for cue in [&"player_attack", &"player_hurt", &"player_dodge", &"player_death", &"player_step", &"player_shot", &"player_switch", &"player_reload", &"player_low_health"]:
		_check("recorded cue registered: " + String(cue), audio.get_cue_stream(cue) is AudioStreamRandomizer)
	var juice := Juice.new()
	root.add_child(juice)
	juice.add_to_group("hitstop_manager")
	var settings: SettingsData = save.get_settings()
	var previous_reduced := settings.reduced_motion
	settings.reduced_motion = false
	feedback._last_impact_frame = -1
	feedback.play_impact_feedback(true)
	feedback.play_impact_feedback(true)
	_check("cleave requests hitstop once per physics frame", juice.requests == 1 and juice.trauma > 0.0)
	settings.reduced_motion = true
	feedback._last_impact_frame = -1
	feedback.play_impact_feedback(true)
	feedback.play_hit_feedback()
	_check("reduced motion suppresses trauma and hit flashes", juice.requests == 1 and feedback._flash_left == 0.0)
	settings.reduced_motion = previous_reduced
	juice.free()
	target.free()
	player.free()

	_completed_cases += 1

func _test_touch(player: Player) -> void:
	var joystick := load("res://scripts/ui/virtual_joystick.gd").new() as Control
	root.add_child(joystick)
	joystick.connect("value_changed", player.set_move_input)
	var touch := InputEventScreenTouch.new()
	touch.index = 1
	touch.position = Vector2(100, 100)
	touch.pressed = true
	joystick.call("_gui_input", touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(148, 52)
	joystick.call("_gui_input", drag)
	var move := player._locomotion.current_input()
	_check("real touch drag reaches player command", move.x > 0.0 and move.y < 0.0 and move.length() < 1.0)
	touch.index = 2
	touch.pressed = false
	joystick.call("_gui_input", touch)
	_check("second finger release cannot cancel movement finger", player._locomotion.current_input() == move)
	touch.index = 1
	joystick.call("_gui_input", touch)
	_check("movement finger release clears input", player._locomotion.current_input() == Vector2.ZERO)
	joystick.free()
	_completed_cases += 1
