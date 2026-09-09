class_name MenuPanel
extends Control

signal navigate(screen: StringName)
signal quit_requested()
var _records: Label
var _row: HBoxContainer

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var box := UiFactory.center_box(self)

	# Hero: kicker -> wordmark -> arena underline -> hairline rule -> tagline.
	UiFactory.kicker("SURVIVE / ADAPT / RISE", box)
	var wordmark := UiFactory.title("LAST STAND", box, 72)
	wordmark.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	wordmark.add_theme_constant_override("outline_size", 7)
	var arena := UiFactory.title("A R E N A", box, 30)
	arena.modulate = UiTheme.GOLD
	arena.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	arena.add_theme_constant_override("outline_size", 5)
	UiFactory.hairline(box)
	UiFactory.label("Modes. Builds. Prestige. Make every stand count.", box, 22).modulate = UiTheme.MUTED

	# Primary CTA is visually dominant (gold); secondary actions share a row below.
	var play := UiFactory.primary("START RUN", box, 26, Vector2(320, 104))
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
	for entry in [[&"ARMORY", &"armory", "trophy"], [&"SETTINGS", &"settings", "gear"], [&"HOW TO PLAY", &"help", "gamepad"]]:
		var b := UiFactory.button(String(entry[0]), row, 20, Vector2(0, UiTheme.TOUCH_MIN))
		b.clip_text = true
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		UiTheme.decorate(b, entry[2])
		var destination: StringName = entry[1]
		b.pressed.connect(func() -> void: navigate.emit(destination))

	# Player profile: personal best, wave, banked coins and prestige title.
	var records_plate := PanelContainer.new()
	records_plate.add_theme_stylebox_override("panel", UiTheme.row_card())
	records_plate.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_child(records_plate)
	_records = UiFactory.label("", records_plate, 20)
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
	prestige = SaveManager.get_prestige_rank()
	title = Prestige.title_for(prestige)
	_records.text = "PERSONAL BEST  %s    /    WAVE %d    /    BANK %d\n%s  •  Prestige %d" % [
		SaveManager.get_best_score(), SaveManager.get_best_wave(), SaveManager.get_meta_wallet(),
		title, prestige]
	if not SaveManager.is_tutorial_completed():
		_records.text += "\nFirst stand? Controls and a guided coach are ready for you."
