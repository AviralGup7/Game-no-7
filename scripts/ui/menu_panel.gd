class_name MenuPanel
extends Control

signal navigate(screen: StringName)
signal quit_requested()
var _records: Label
var _row: HBoxContainer

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var box := UiFactory.center_box(self)
	UiFactory.label("S U R V I V E   /   A D A P T   /   R I S E", box, 18).modulate = UiTheme.CYAN
	var wordmark := UiFactory.title("LAST STAND", box, 68)
	wordmark.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	wordmark.add_theme_constant_override("outline_size", 6)
	UiFactory.title("A R E N A", box, 30).modulate = UiTheme.GOLD
	UiFactory.label("Modes. Builds. Prestige. Make every stand count.", box, 22).modulate = UiTheme.MUTED
	# Primary CTA is visually dominant; secondary actions share one row below it.
	var play := UiFactory.button("START RUN", box, 26, Vector2(280, 96))
	UiTheme.decorate(play, "play")
	play.pressed.connect(func() -> void: navigate.emit(&"run_setup"))
	var daily := UiFactory.button("DAILY CHALLENGE  /  TODAY'S SEED", box, 22)
	daily.tooltip_text = "Play today's fixed seed"
	UiTheme.decorate(daily, "star")
	daily.pressed.connect(func() -> void: navigate.emit(&"daily"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_M)
	box.add_child(row)
	_row = row
	for entry in [["ARMORY", &"armory", "trophy"], ["SETTINGS", &"settings", "gear"], ["HOW TO PLAY", &"help", "gamepad"]]:
		var b := UiFactory.button(entry[0], row, 20, Vector2(0, UiTheme.TOUCH_MIN))
		b.clip_text = true
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		UiTheme.decorate(b, entry[2])
		var destination: StringName = entry[1]
		b.pressed.connect(func() -> void: navigate.emit(destination))
	_records = UiFactory.label("", box, 20)
	_records.modulate = UiTheme.MUTED
	resized.connect(_fit)
	_fit.call_deferred()
	if not OS.has_feature("mobile"):
		UiFactory.button("QUIT", box, 18).pressed.connect(func() -> void: quit_requested.emit())
	refresh()

## Narrow phones in portrait cannot fit three side-by-side buttons without the
## labels clipping, so the secondary row stacks below a threshold.
func _fit() -> void:
	if _row != null:
		_row.vertical = size.x < 560.0


func refresh() -> void:
	var prestige := 0
	var title := "Unproven"
	if SaveManager != null and SaveManager.has_method("get_prestige_rank"):
		prestige = int(SaveManager.call("get_prestige_rank"))
		title = Prestige.title_for(prestige)
	_records.text = "PERSONAL BEST  %s    /    WAVE %d    /    BANK %d\n%s  •  Prestige %d" % [
		SaveManager.get_best_score(), SaveManager.get_best_wave(), SaveManager.get_meta_wallet(),
		title, prestige]
	if not SaveManager.is_tutorial_completed():
		_records.text += "\nFirst stand? Controls and a guided coach are ready for you."

## Hardened: validate menu id.
func _validated_menu_id(id: StringName) -> bool:
	if id == &"":
		return false
	return true
