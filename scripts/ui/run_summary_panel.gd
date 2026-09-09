class_name RunSummaryPanel
extends Control
## Immutable display snapshot + three local presentation pages. Rewards are already
## banked by MetaProgression on run_ended; Continue NEVER claims/grants them again.
signal menu_requested()
signal armory_requested()
signal page_changed(page: StringName)
var _summary: Dictionary = {}
var _weapon := "Not recorded"
var _bank_before := 0
var _reward := 0
var _bank_after := 0
var _page := &"game_over"
var _body: VBoxContainer
var _save_warning := ""
var _achievements: Array[StringName] = []

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	_body = UiFactory.center_box(self)
	EventBus.run_started.connect(_on_run_started)
	EventBus.weapon_equipped.connect(func(id: StringName, _slot: int) -> void: _record_weapon(id))
	EventBus.weapon_switched.connect(func(_old: StringName, id: StringName) -> void: _record_weapon(id))
	EventBus.run_ended.connect(func(_score: int, _wave: int, _best: int) -> void: capture())
	EventBus.save_failed.connect(func(_reason: StringName) -> void:
		_save_warning = "Saving failed. Progress may not survive closing the game."
		if visible: show_page(_page))
	EventBus.achievement_unlocked.connect(func(id: StringName) -> void:
		if id not in _achievements: _achievements.append(id))
	EventBus.save_completed.connect(func() -> void:
		var had_warning := not _save_warning.is_empty()
		_save_warning = ""
		if had_warning and visible: show_page(_page))

func _on_run_started(_id: int, _seed: int) -> void:
	_bank_before = SaveManager.get_meta_wallet()
	_summary.clear()
	_achievements.clear()
	# run_started follows world construction, so keep weapon_equipped's value.
	var player := GameRoot.get_active_player()
	if is_instance_valid(player):
		_record_weapon(player.get_weapon_manager().active_weapon_id())

func _record_weapon(id: StringName) -> void:
	var cfg := ContentRegistry.get_weapon(id)
	_weapon = cfg.display_name if cfg != null else String(id)

func capture() -> void:
	var run := GameRoot.get_run()
	if run == null:
		return
	_summary = run.summary().duplicate(true)
	_finish_capture.call_deferred(int(_summary.get("run_id", 0)))

func _finish_capture(run_id: int) -> void:
	if GameRoot.get_current_state() != GameRoot.State.GAME_OVER or int(_summary.get("run_id", -1)) != run_id:
		return
	_bank_after = SaveManager.get_meta_wallet()
	_reward = maxi(_bank_after - _bank_before, 0)
	show_page(&"game_over")

static func duration(seconds: float) -> String:
	var total := maxi(int(round(maxf(seconds, 0.0))), 0)
	return "%02d:%02d" % [total / 60, total % 60]

static func performance(summary: Dictionary) -> String:
	var seconds := float(summary.get("elapsed_seconds", 0.0))
	var pace := float(summary.get("kills", 0)) * 60.0 / seconds if seconds > 0.0 else 0.0
	return "Best combo  %d\nDamage taken  %.1f\nKill pace  %.1f / min" % [
		int(summary.get("best_combo", 0)), float(summary.get("damage_taken", 0.0)), pace]

func show_page(page: StringName) -> void:
	_page = page
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	match page:
		&"game_over": _build_game_over()
		&"run_summary": _build_summary()
		&"meta_reward": _build_rewards()
	if not _save_warning.is_empty():
		UiFactory.label(_save_warning, _body).modulate = UiTheme.GOLD
	UiTheme.apply_text_scale(_body, SaveManager.get_settings().text_scale)
	page_changed.emit(page)
	if visible:
		UiFactory.focus_first.call_deferred(self)

func _build_game_over() -> void:
	var victory := bool(_summary.get("victory", false))
	UiFactory.label("THE ARENA REMEMBERS" if not victory else "THE STAND HOLDS", _body, 18).modulate = UiTheme.GOLD
	UiFactory.title("VICTORY" if victory else "LAST STAND ENDED", _body, 44)
	UiFactory.title(str(_summary.get("score", 0)), _body, 64)
	var mode_id := StringName(String(_summary.get("mode_id", "standard")))
	UiFactory.label("%s  /  Wave %d  /  %s survived" % [
		GameMode.display_name(mode_id), _summary.get("current_wave", 0),
		duration(_summary.get("elapsed_seconds", 0.0))], _body, 22)
	UiFactory.label("Personal best  %d" % SaveManager.get_best_score(), _body)
	UiFactory.button("VIEW RUN SUMMARY", _body, 24).pressed.connect(func() -> void: show_page(&"run_summary"))

func _build_summary() -> void:
	UiFactory.title("YOUR RUN, IN REVIEW", _body, 34)
	var arena := ContentRegistry.get_arena(StringName(_summary.get("arena_id", "")))
	var mode_id := StringName(String(_summary.get("mode_id", "standard")))
	var mode_label := "Daily challenge" if GameRoot.is_daily_run() else GameMode.display_name(mode_id)
	if bool(_summary.get("victory", false)):
		mode_label += "  •  VICTORY"
	UiFactory.label("%s  /  %s" % [arena.display_name if arena != null else "Arena", mode_label], _body)
	# Prestige identity: rank title + worn cosmetic title / equipped cosmetics.
	var prestige_line := _prestige_identity_line()
	if not prestige_line.is_empty():
		UiFactory.label(prestige_line, _body, 18).modulate = UiTheme.GOLD
	var stats := UiFactory.card(_body)
	UiFactory.label("SCORE  %d     KILLS  %d     WAVE  %d\nBOSSES  %d     TIME  %s     RUN COINS  %d\nFINAL WEAPON  %s" % [
		_summary.get("score", 0), _summary.get("kills", 0), _summary.get("current_wave", 0),
		_summary.get("bosses_slain", 0),
		duration(_summary.get("elapsed_seconds", 0.0)), _summary.get("currency", 0), _weapon], stats, 24)
	UiFactory.label(performance(_summary), stats, 22)
	UiFactory.title("UPGRADES KEPT THIS RUN", _body, 22)
	var upgrades: Dictionary = _summary.get("selected_upgrades", {})
	var lines := PackedStringArray()
	var transforms := PackedStringArray()
	for id in upgrades:
		var cfg := ContentRegistry.get_upgrade(StringName(id))
		var label := "%s  ×%d" % [cfg.display_name if cfg != null else String(id), upgrades[id]]
		if cfg != null and cfg.is_transformative():
			transforms.append(label + "  [TRANSFORM]")
		else:
			lines.append(label)
	if not transforms.is_empty():
		UiFactory.label("TRANSFORMS\n" + "\n".join(transforms), _body, 20).modulate = UiTheme.CYAN
	UiFactory.label("\n".join(lines) if not lines.is_empty() else ("No stat upgrades." if not transforms.is_empty() else "No upgrades selected this run."), _body)
	UiFactory.label("Seed %s  •  Local run %s" % [_summary.get("seed", 0), _summary.get("run_id", 0)], _body, 16)
	UiFactory.button("CONTINUE TO REWARDS", _body, 24).pressed.connect(func() -> void: show_page(&"meta_reward"))

## Prestige rank title + the cosmetics the player has earned (title / trail / aura
## / banners). Empty for an unproven, cosmetic-less save so nothing is shown.
func _prestige_identity_line() -> String:
	if SaveManager == null:
		return ""
	var rank := SaveManager.get_prestige_rank()
	var unlocked := SaveManager.get_unlocked_cosmetics()
	var parts := PackedStringArray()
	if rank > 0:
		parts.append("Prestige %d — %s" % [rank, Prestige.title_for(rank)])
	var title_id := Cosmetics.active_title(unlocked)
	if title_id != &"":
		parts.append("Title: %s" % Cosmetics.display_name(title_id))
	var worn := PackedStringArray()
	var trail_id := Cosmetics.active_trail(unlocked)
	if trail_id != &"":
		worn.append(Cosmetics.display_name(trail_id))
	var aura_id := Cosmetics.active_aura(unlocked)
	if aura_id != &"":
		worn.append(Cosmetics.display_name(aura_id))
	for banner_id in Cosmetics.active_banners(unlocked):
		worn.append(Cosmetics.display_name(banner_id))
	if not worn.is_empty():
		parts.append("Cosmetics: " + ", ".join(worn))
	return "   •   ".join(parts)


func _build_rewards() -> void:
	UiFactory.title("BUILD YOUR NEXT STAND", _body, 36)
	UiFactory.title("+%d BANKED COINS" % _reward, _body, 36).modulate = UiTheme.GOLD
	UiFactory.label("Wallet after this run: %d\nRewards are handled automatically by the Armory system.\nContinue does not claim or grant coins a second time." % _bank_after, _body)
	if not _achievements.is_empty():
		var names := PackedStringArray()
		var definitions := Achievements.definitions()
		for id in _achievements:
			names.append(String(definitions.get(id, {}).get("name", id)))
		UiFactory.label("ACHIEVEMENTS UNLOCKED\n" + " / ".join(names), _body, 22).modulate = UiTheme.CYAN
	UiFactory.button("VISIT ARMORY", _body, 24).pressed.connect(func() -> void: armory_requested.emit())
	UiFactory.button("RETRY SAME MODE", _body, 22).pressed.connect(func() -> void:
		if GameRoot.get_current_state() == GameRoot.State.GAME_OVER: GameRoot.request_restart())
	UiFactory.button("MAIN MENU", _body, 22).pressed.connect(func() -> void: menu_requested.emit())
	UiFactory.button("REVIEW SUMMARY", _body, 18).pressed.connect(func() -> void: show_page(&"run_summary"))

func get_debug_snapshot() -> Dictionary:
	return {"page": _page, "summary": _summary.duplicate(true), "reward": _reward, "wallet": _bank_after}
