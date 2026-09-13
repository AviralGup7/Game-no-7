class_name CampaignUI
extends Control
## Shipping navigation: Continue/New Campaign -> connected station. Auxiliary
## screens pause simulation and retire touch ownership, including Android Back.

var definition: CampaignDefinition
var director: CampaignDirector
var _safe: UiSafeArea
var _hud: CampaignHud
var _numbers: DamageNumberLayer
var _screens: Dictionary = {}
var _active := "menu"
var _modal: UiModal
var _settings: SettingsPanel
var _armory: CampaignArmory
var _map: CampaignMap
var _map_brief: Label
var _continue: Button
var _resume_info: Label
var _result: Label
var _result_brief: Label
var _retry: Button
var _status: Label
var _menu_message: Label
var _backdrop: MenuBackdrop
var _last_quality := &""
var _save_error_shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	_safe = UiSafeArea.new()
	add_child(_safe)
	add_child(ShooterReticle.new())
	_numbers = DamageNumberLayer.new()
	add_child(_numbers)
	_hud = CampaignHud.new()
	_safe.add_child(_hud)
	_hud.map_requested.connect(open_map)
	_modal = UiModal.new()
	add_child(_modal)
	_build_menu()
	_build_pause()
	_build_map()
	_build_auxiliary()
	_build_result()
	var status_body := _screen("status")
	_status = UiFactory.title("CONNECTING TO STATION ZERO", status_body, 32)
	UiFactory.button("MAIN MENU", status_body, 22).pressed.connect(GameRoot.request_main_menu)
	EventBus.game_state_changed.connect(_on_state)
	EventBus.settings_changed.connect(_apply_settings)
	EventBus.save_failed.connect(_on_save_failed)
	EventBus.save_completed.connect(func() -> void:
		_save_error_shown = false
		_menu_message.text = "")
	EventBus.announcement.connect(_on_announcement)
	EventBus.enemy_damaged.connect(_on_damage)
	_safe.safe_area_changed.connect(_relayout)
	_safe.resized.connect(_relayout)
	_apply_settings(SaveManager.get_settings())
	_on_state(&"", GameRoot.get_current_state())


func _screen(id: String) -> VBoxContainer:
	var overlay := UiFactory.overlay(_safe, 0.82)
	_screens[id] = overlay.panel
	return overlay.box as VBoxContainer


func _build_menu() -> void:
	var body := _screen("menu")
	UiFactory.kicker("LAST STAND / A CONTINUOUS CAMPAIGN", body)
	UiFactory.title("STATION ZERO", body, 58)
	UiFactory.hairline(body)
	UiFactory.label("THE LONG WAY HOME", body, 26)
	UiFactory.label("Six connected districts. One silent station.\nRestore power, find the survivors and take back the way home.", body, 22)
	_resume_info = UiFactory.label("", body, 20)
	_resume_info.modulate = UiTheme.CYAN
	_continue = UiFactory.button("CONTINUE CAMPAIGN", body, 24)
	_continue.pressed.connect(func() -> void: GameRoot.start_campaign())
	UiFactory.button("NEW CAMPAIGN", body, 22).pressed.connect(_new_campaign)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	UiFactory.button("SETTINGS", row, 20).pressed.connect(func() -> void: _show("settings"))
	UiFactory.button("ARMORY", row, 20).pressed.connect(func() -> void: _show("armory"))
	UiFactory.label("Left thumb: MOVE  /  Hold FIRE and slide to AIM\nApproach a console and tap INTERACT. Green rings save a checkpoint.", body, 18)
	_menu_message = UiFactory.label("", body, 20)
	_menu_message.modulate = UiTheme.GOLD


func _new_campaign() -> void:
	if not SaveManager.has_campaign():
		GameRoot.start_campaign(true)
		return
	_modal.confirm("START A NEW CAMPAIGN?", "Replace this campaign's objectives, loadout and checkpoints? Your settings, armory purchases and banked credits are kept.",
		"NEW CAMPAIGN", "KEEP CURRENT", func() -> void: GameRoot.start_campaign(true))


func _build_pause() -> void:
	var body := _screen("pause")
	UiFactory.screen_header(body, "STATION ZERO", "CAMPAIGN PAUSED", 38,
		"Objectives and cleared encounters are saved. Continue starts at your last checkpoint.")
	UiFactory.button("RESUME", body, 24).pressed.connect(GameRoot.request_resume)
	UiFactory.button("STATION MAP / OBJECTIVE", body, 22).pressed.connect(func() -> void: _show("map"))
	UiFactory.button("SETTINGS", body, 22).pressed.connect(func() -> void: _show("settings"))
	UiFactory.button("ARMORY / LOADOUT", body, 22).pressed.connect(func() -> void: _show("armory"))
	UiFactory.button("RETURN TO CHECKPOINT", body, 22).pressed.connect(func() -> void:
		_modal.confirm("RETURN TO CHECKPOINT?", "Completed objectives, credits and defeated enemies are kept. Health and stamina are restored at your last checkpoint.",
			"RETURN", "CANCEL", _retry_checkpoint))
	UiFactory.button("SAVE & MAIN MENU", body, 22).pressed.connect(_save_and_menu)


func _build_map() -> void:
	var body := _screen("map")
	UiFactory.screen_header(body, "CONNECTED STATION / NORTH UP", "STATION MAP", 34)
	_map = CampaignMap.new()
	_map.custom_minimum_size = Vector2(0, 360)
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_map)
	_map.bind(definition)
	UiFactory.label("WHITE / YOU    GOLD / OBJECTIVE & ROUTE    GREEN / CHECKPOINT    SQUARE / SUPPLIES", body, 16)
	_map_brief = UiFactory.label("", body, 22)
	UiFactory.button("BACK", body, 22).pressed.connect(_close_auxiliary)


func _build_auxiliary() -> void:
	var settings_body := _screen("settings")
	UiFactory.title("SETTINGS", settings_body, 34)
	_settings = SettingsPanel.new()
	settings_body.add_child(_settings)
	_settings.close_requested.connect(_close_auxiliary)
	var armory_body := _screen("armory")
	UiFactory.screen_header(armory_body, "PERMANENT UPGRADES", "STATION ARMORY", 34)
	_armory = CampaignArmory.new()
	armory_body.add_child(_armory)
	_armory.close_requested.connect(_close_auxiliary)


func _build_result() -> void:
	var body := _screen("result")
	UiFactory.kicker("STATION ZERO", body)
	_result = UiFactory.title("SIGNAL LOST", body, 46)
	_result_brief = UiFactory.label("", body, 24)
	_retry = UiFactory.button("RETRY FROM CHECKPOINT", body, 24)
	_retry.pressed.connect(_retry_checkpoint)
	UiFactory.button("MAIN MENU", body, 22).pressed.connect(_save_and_menu)


func bind_session(session: CampaignDirector) -> void:
	if is_instance_valid(director):
		if director.message.is_connected(_hud.show_message):
			director.message.disconnect(_hud.show_message)
	director = session
	_hud.bind(session)
	_map.bind(definition, session)
	_armory.director = session
	if session != null:
		session.message.connect(_hud.show_message)


func _show(id: String) -> void:
	_cancel_input()
	_active = id
	for key in _screens:
		var screen: Control = _screens[key]
		screen.visible = key == id
	_hud.visible = id == "playing"
	_backdrop.visible = id != "playing"
	if id == "menu":
		var progress := CampaignProgress.reconcile(SaveManager.get_campaign(), definition)
		_continue.visible = bool(progress.started)
		_continue.text = "RETURN TO STATION" if bool(progress.completed) else "CONTINUE CAMPAIGN"
		_resume_info.text = "%d / %d OBJECTIVES COMPLETE · CHECKPOINT / %s" % [int(progress.mission), definition.missions.size(), String(progress.checkpoint).to_upper()] if bool(progress.started) else "A FIXED WORLD TO EXPLORE / PLAY AT YOUR OWN PACE"
	elif id == "map":
		_map.queue_redraw()
		if is_instance_valid(director):
			var mission := director.current_mission()
			_map_brief.text = String(mission.get("brief", "The evacuation route is open. Explore the station and recover the remaining supplies."))
	elif id == "settings":
		_settings.refresh()
	elif id == "armory":
		_armory.refresh()
	elif id == "result":
		var victory := GameRoot.get_run().victory
		_result.text = "THE WAY HOME IS OPEN" if victory else "SIGNAL LOST"
		_result_brief.text = "Power restored. Survivors connected. Lockdown broken.\nYour campaign is complete; you can return to explore the station." if victory else "Your objectives, upgrades and cleared encounters are kept.\nRedeploy at your last saved checkpoint."
		_retry.text = "EXPLORE STATION" if victory else "RETRY FROM CHECKPOINT"
	elif id == "status":
		_status.text = "STATION COULD NOT BE LOADED" if GameRoot.get_current_state() == GameRoot.State.ERROR else "CONNECTING TO STATION ZERO"
	if id in _screens:
		UiTheme.apply_text_scale(_screens[id], SaveManager.get_settings().text_scale)
		UiFactory.focus_first(_screens[id])


func _on_state(_old: StringName, state: StringName) -> void:
	match state:
		GameRoot.State.MAIN_MENU:
			_show("menu")
		GameRoot.State.PLAYING:
			_show("playing")
		GameRoot.State.PAUSED:
			_show("pause")
		GameRoot.State.GAME_OVER:
			_show("result")
		_:
			_show("status")


func open_map() -> void:
	if GameRoot.get_current_state() == GameRoot.State.PLAYING:
		GameRoot.request_pause()
	if GameRoot.get_current_state() == GameRoot.State.PAUSED:
		_show("map")


func _close_auxiliary() -> void:
	_settings.cancel_edit()
	_show("pause" if GameRoot.get_current_state() == GameRoot.State.PAUSED else "menu")


func _save_and_menu() -> void:
	if is_instance_valid(director) and not director.save_progress(true):
		_modal.confirm("SAVING FAILED", "Your latest progress may not survive closing the app. Return to the menu anyway?", "RETURN", "CANCEL", GameRoot.request_main_menu)
		return
	GameRoot.request_main_menu()


func _retry_checkpoint() -> void:
	if is_instance_valid(director) and not director.save_progress(true):
		return
	GameRoot.request_restart()


func _on_save_failed(_reason: StringName) -> void:
	_menu_message.text = "Saving failed. Free some device storage and try again."
	_hud.show_message("SAVING FAILED / Progress may not survive closing the app.")
	if not _save_error_shown:
		_save_error_shown = true
		if GameRoot.get_current_state() == GameRoot.State.PLAYING:
			GameRoot.request_pause()
		_modal.confirm("SAVING FAILED", "Your latest progress may not survive closing the app. Free some device storage, then retry the save.",
			"RETRY SAVE", "CLOSE", SaveManager.save_now)


func _on_announcement(_id: StringName, text: String, _severity: StringName) -> void:
	if _active == "menu":
		_menu_message.text = text
	else:
		_hud.show_message(text)


func _on_damage(enemy: Node, result: DamageResult) -> void:
	if result != null and result.accepted and is_instance_valid(enemy) and enemy is Node3D:
		var actor := enemy as Node3D
		_numbers.spawn_damage_number(actor.global_position + Vector3.UP * 1.2, result.final_amount, result.was_critical, Color.WHITE, actor)


func _apply_settings(settings: SettingsData) -> void:
	theme = UiTheme.create(settings)
	UiTheme.apply_text_scale(self, settings.text_scale)
	_hud.apply_settings(settings)
	_numbers.set_reduced_motion(settings.reduced_motion)
	_numbers.set_text_scale(settings.text_scale)
	if settings.graphics_quality != _last_quality:
		_last_quality = settings.graphics_quality
		var tier := [&"low", &"medium", &"high", &"ultra"].find(_last_quality)
		for node in get_tree().get_nodes_in_group("performance_monitor"):
			var monitor := node as PerformanceMonitor
			if monitor != null:
				monitor.set_tier(maxi(tier, 0))
				PoolGovernor.apply(monitor, self)
	for node in get_tree().get_nodes_in_group("hitstop_manager"):
		var hitstop := node as HitstopManager
		if hitstop != null:
			hitstop.set_reduced_motion(settings.reduced_motion)
	_relayout.call_deferred()


func _cancel_input() -> void:
	_hud.cancel_input()
	var camera := get_tree().get_first_node_in_group("camera_rig") as CameraRig
	if camera != null:
		camera.cancel_touch_input()


func _relayout() -> void:
	_cancel_input()
	_hud.apply_layout()
	_numbers.set_hud_block(_hud._vitals.get_global_rect())
	_numbers.set_skill_block(_hud._skills.get_global_rect())
	_numbers.set_minimap_block(_hud._mini.get_global_rect())
	_map.custom_minimum_size.y = clampf(_safe.size.y * 0.48, 240, 440)


func _input(event: InputEvent) -> void:
	if _active == "settings" and _settings.is_rebinding():
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _modal.is_open():
			return
		if _active != "playing":
			_back()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and is_instance_valid(director):
		director.try_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("campaign_map"):
		open_map()
		get_viewport().set_input_as_handled()


func _back() -> void:
	if _modal.is_open():
		_modal.cancel_all()
	elif _active in ["settings", "armory", "map"]:
		_close_auxiliary()
	elif _active == "pause":
		GameRoot.request_resume()
	elif _active == "playing":
		GameRoot.request_pause()
	elif _active == "menu":
		_modal.confirm("CLOSE STATION ZERO?", "Your saved campaign will be here when you return.", "CLOSE", "CANCEL", func() -> void:
			SaveManager.save_now()
			get_tree().quit())
	else:
		_save_and_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _hud != null:
		_back()


func get_debug_snapshot() -> Dictionary:
	return {"screen": _active, "hud": _hud.get_debug_snapshot(), "modal": _modal.is_open()}
