class_name UpgradePanel
extends Control

## Upgrade-choice screen, extracted from ui_root. Builds one card per offered
## upgrade (rarity colour, stack counts) and reports presses through
## `choice_pressed`. It never touches progression: ui_root validates the pick via
## GameRoot and then locks the panel through lock_selection().

signal choice_pressed(upgrade_id: StringName)

var _cards_box: HBoxContainer = null
var _note: Label = null
var _card_buttons: Array[Button] = []
var _selection_locked := false


func _ready() -> void:
	name = "UpgradePanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks through to HUD
	var box := UiFactory.center_box(self)
	UiFactory.title(UiText.get(&"upgrades_title"), box, UiFactory.font_scaled(30))
	var sub := Label.new()
	sub.text = UiText.get(&"upgrade_choose_hint")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", UiFactory.font_scaled(15))
	box.add_child(sub)
	_cards_box = HBoxContainer.new()
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_box.add_theme_constant_override("separation", 18)
	box.add_child(_cards_box)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", UiFactory.font_scaled(16))
	box.add_child(_note)
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
	_note.text = UiText.get(&"upgrade_none") if _card_buttons.is_empty() else ""


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
	btn.custom_minimum_size = Vector2(170, 200)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var stack := _current_stack(cfg.upgrade_id)
	var rarity := String(cfg.rarity).to_upper()
	var body := "%s\n[%s]\n\n%s" % [cfg.display_name, rarity, cfg.description]
	if stack > 0:
		body += "\nstack %d/%d" % [stack, cfg.max_stacks]
	btn.text = body
	btn.add_theme_font_size_override("font_size", UiFactory.font_scaled(13))
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
	var run := GameRoot.get_run()
	if run == null:
		return 0
	return int(run.selected_upgrades.get(upgrade_id, 0))


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
