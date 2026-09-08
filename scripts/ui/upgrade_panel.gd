class_name UpgradePanel
extends Control

## Upgrade-choice screen, extracted from ui_root. Builds one card per offered
## upgrade (rarity colour, stack counts) and reports presses through
## `choice_pressed`. It never touches progression: ui_root validates the pick via
## GameRoot and then locks the panel through lock_selection().

signal choice_pressed(upgrade_id: StringName)
signal exit_requested()

var _cards_box: GridContainer = null
var _note: Label = null
var _card_buttons: Array[Button] = []
var _selection_locked := false
var _empty_back: Button


func _ready() -> void:
	name = "UpgradePanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks through to HUD
	var box := UiFactory.center_box(self)
	UiFactory.title(UiText.lookup(&"upgrades_title"), box, UiFactory.font_scaled(30))
	var sub := Label.new()
	sub.text = UiText.lookup(&"upgrade_choose_hint")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", UiFactory.font_scaled(20))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	_cards_box = GridContainer.new()
	_cards_box.columns = 3
	resized.connect(_layout_cards)
	_cards_box.add_theme_constant_override("h_separation", 16)
	_cards_box.add_theme_constant_override("v_separation", 16)
	box.add_child(_cards_box)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", UiFactory.font_scaled(20))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	_empty_back = UiFactory.button("RETURN TO MENU", box, 20)
	_empty_back.pressed.connect(func() -> void: exit_requested.emit())
	_empty_back.visible = false
	visible = false


## Show a fresh offer (unlocks + rebuilds the cards). Unknown ids are skipped.
func present(choices: Array) -> void:
	_selection_locked = false
	_clear_cards()
	for raw_id in choices:
		var cfg := ContentRegistry.get_upgrade(StringName(String(raw_id)))
		if cfg == null:
			continue
		_add_card(cfg)
	if _note == null:
		return
	_note.text = UiText.lookup(&"upgrade_none") if _card_buttons.is_empty() else "Choose carefully. Only one card can be kept."
	_empty_back.visible = _card_buttons.is_empty()
	_layout_cards()
	UiTheme.apply_text_scale(_cards_box, SaveManager.get_settings().text_scale)
	UiFactory.focus_first.call_deferred(self)


## Lock the panel after GameRoot accepted a pick (cards go non-interactive).
func lock_selection() -> void:
	_selection_locked = true
	for btn in _card_buttons:
		btn.disabled = true


func is_locked() -> bool:
	return _selection_locked


func _clear_cards() -> void:
	if _cards_box == null:
		return
	for c in _cards_box.get_children():
		_cards_box.remove_child(c)
		c.queue_free()
	_card_buttons.clear()


func _add_card(cfg: UpgradeConfig) -> void:
	if _cards_box == null:
		return
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 220)
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var stack := _current_stack(cfg.upgrade_id)
	var rarity := String(cfg.rarity).to_upper()
	var body := "%s\n%s\n\n%s" % [cfg.display_name, rarity, cfg.description]
	body += "\n\nRANK %d → %d / %d" % [stack, stack + 1, cfg.max_stacks]
	btn.text = body
	btn.icon = cfg.icon if cfg.icon != null else preload("res://assets/ui/upgrades/award.png")
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", 28)
	btn.add_theme_font_size_override("font_size", UiFactory.font_scaled(22))
	btn.add_theme_color_override("font_color", _rarity_color(cfg.rarity))
	var id := cfg.upgrade_id
	btn.pressed.connect(func() -> void: _on_card_pressed(id))
	_cards_box.add_child(btn)
	_card_buttons.append(btn)


func _on_card_pressed(upgrade_id: StringName) -> void:
	if _selection_locked:
		return
	choice_pressed.emit(upgrade_id)


func _current_stack(upgrade_id: StringName) -> int:
	if GameRoot == null or not GameRoot.has_method("get_run"):
		return 0
	var run: Variant = GameRoot.call("get_run")
	if run == null:
		return 0
	if run is Dictionary:
		return int((run as Dictionary).get("selected_upgrades", {}).get(upgrade_id, 0)) if (run as Dictionary).get("selected_upgrades", {}) is Dictionary else 0
	if "selected_upgrades" in run:
		var sel: Variant = (run as Object).get("selected_upgrades")
		if sel is Dictionary:
			return int((sel as Dictionary).get(upgrade_id, 0))
	return 0


func _rarity_color(rarity: StringName) -> Color:
	match rarity:
		&"common":
			return Color(0.8, 0.83, 0.86)
		&"rare":
			return Color(0.42, 0.68, 0.98)
		&"epic":
			return Color(0.75, 0.5, 0.95)
		&"legendary":
			return Color(0.98, 0.75, 0.35)
	return Color.WHITE


func show_feedback(message: String) -> void:
	_note.text = message

func _layout_cards() -> void:
	if _cards_box != null:
		_cards_box.columns = 1 if size.x < 1000 or SaveManager.get_settings().text_scale > 1.3 else 3

## Hardened: validate upgrade card index.
func _validated_card_index(i: int, n: int) -> int:
    if n <= 0:
        return -1
    if i < 0 or i >= n:
        return -1
    return i

