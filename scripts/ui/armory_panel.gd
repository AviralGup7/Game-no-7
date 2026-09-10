class_name ArmoryPanel
extends VBoxContainer

## Spendable meta-progression shop: lists every ARMORY entry with rank pips,
## price and prerequisite state, and routes purchases through MetaProgression
## (which validates, applies live, persists and announces). Finds the meta node
## via the "meta_progression" group; refresh() rebuilds the list so balances
## are always current when the screen opens. Code-built, no scene assets.

signal close_requested()

var _wallet_label: Label = null
var _rows: VBoxContainer = null
var _feedback: Label
var _gallery: AchievementGallery
var _persistence: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_wallet_label = Label.new()
	_wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wallet_label.add_theme_font_size_override("font_size", 20)
	add_child(_wallet_label)
	UiFactory.label("Permanent ranks carry into every stand. Purchases are applied and saved by the Armory system.", self, 20)
	_feedback = UiFactory.label("", self, 20)
	_feedback.modulate = UiTheme.GOLD
	_persistence = UiFactory.label("", self, 20)
	_persistence.modulate = UiTheme.GOLD
	EventBus.save_failed.connect(func(_reason: StringName) -> void:
		_persistence.text = "Saving failed. Purchases may not survive closing the game.")
	EventBus.save_completed.connect(func() -> void: _persistence.text = "")
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", UiTheme.SPACE_S)
	add_child(_rows)
	_gallery = AchievementGallery.new()
	add_child(_gallery)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(220, UiTheme.TOUCH_MIN)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		UiFactory.play_press("Close")
		close_requested.emit())
	add_child(close)
	refresh()


func _meta() -> MetaProgression:
	if not is_inside_tree():
		return null
	var nodes := get_tree().get_nodes_in_group("meta_progression")
	if nodes.is_empty():
		return null
	return nodes[0] as MetaProgression


## Rebuild every row from live meta state. Safe when meta is absent (empty shop).
func refresh() -> void:
	if _rows == null:
		return
	_gallery.refresh()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var meta := _meta()
	if meta == null:
		_wallet_label.text = "Armory unavailable"
		return
	var prestige_line := ""
	var rank := meta.get_prestige_rank()
	var title := meta.prestige_title()
	var cost := meta.prestige_cost()
	var verdict := meta.can_prestige()
	prestige_line = "  •  %s (P%d)" % [title, rank]
	_wallet_label.text = "Banked coins: %d%s" % [meta.get_wallet(), prestige_line]
	# Prestige row sits above the shop list.
	_rows.add_child(_make_prestige_row(meta, rank, cost, verdict))
	for item_id in MetaProgression.ARMORY:
		_rows.add_child(_make_row(meta, StringName(String(item_id))))
	UiTheme.apply_text_scale(_rows, SaveManager.get_settings().text_scale)


func _make_prestige_row(meta: MetaProgression, rank: int, cost: int, verdict: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_M)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := Label.new()
	name.text = "PRESTIGE  %d/%d  —  %s" % [rank, Prestige.max_rank(), Prestige.title_for(rank)]
	name.add_theme_font_size_override("font_size", 22)
	info.add_child(name)
	var blurb := Label.new()
	# Printed from the ladder the ranks are actually applied from, not from a constant that could
	# disagree with it (the promise on this row is the one thing the player prices a reset against).
	blurb.text = "+%.0f%% score / +%.0f%% banked coins permanently. Resets armory stat ranks; keeps unlocks." % [
		Prestige.score_bonus_per_rank() * 100.0, Prestige.currency_bonus_per_rank() * 100.0]
	blurb.add_theme_font_size_override("font_size", 18)
	blurb.modulate = UiTheme.MUTED
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(blurb)
	row.add_child(info)
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(180, UiTheme.TOUCH_MIN)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	match verdict:
		&"ok":
			buy.text = "PRESTIGE  %d" % cost
			buy.pressed.connect(func() -> void:
				UiFactory.play_press("PRESTIGE")
				if meta.perform_prestige():
					_feedback.text = "Prestige %d — %s" % [meta.get_prestige_rank(), meta.prestige_title()]
					AudioManager.play_sfx(&"upgrade_select", -8.0)
				else:
					_feedback.text = "Prestige declined."
				refresh())
		&"maxed":
			buy.text = "MAX PRESTIGE"
			buy.disabled = true
		&"unavailable":
			# The ladder is authored content now, so "cannot price prestige" is a real state: say it
			# instead of offering rank 1 for 0 coins, which is what consts-on-zero used to do.
			buy.text = "PRESTIGE UNAVAILABLE"
			buy.disabled = true
			buy.tooltip_text = "res://data/prestige/ladder.tres did not load."
		&"armory_incomplete":
			buy.text = "ARMORY %d%%+" % int(round(Prestige.armory_completion_required() * 100.0))
			buy.disabled = true
			buy.tooltip_text = "Unlock more armory ranks first (%.0f%% complete)." % (meta.armory_completion() * 100.0)
		_:
			buy.text = "%d" % cost
			buy.disabled = true
			buy.tooltip_text = "Need %d banked coins" % maxi(cost - meta.get_wallet(), 0)
	row.add_child(buy)
	return row


func _make_row(meta: MetaProgression, item_id: StringName) -> Control:
	var def: Dictionary = MetaProgression.ARMORY[item_id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_M)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(0, 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rank := meta.get_rank(item_id)
	var max_rank := int(def["max_rank"])
	var name := Label.new()
	name.text = "%s  %d/%d" % [String(def["name"]), rank, max_rank]
	name.add_theme_font_size_override("font_size", 22)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name)
	var blurb := Label.new()
	blurb.text = String(def["blurb"])
	blurb.add_theme_font_size_override("font_size", 20)
	blurb.modulate = UiTheme.MUTED
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(blurb)
	row.add_child(info)
	var verdict := meta.can_purchase(item_id)
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(160, UiTheme.TOUCH_MIN)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	match verdict:
		&"ok":
			buy.text = "BUY  %d" % meta.price_of(item_id)
			var id := item_id
			buy.pressed.connect(func() -> void: _on_buy(meta, id))
		&"maxed":
			buy.text = "MAXED"
			buy.disabled = true
		&"missing_prerequisite":
			buy.text = "LOCKED"
			buy.disabled = true
			buy.tooltip_text = "Requires: %s" % _prereq_names(def)
			blurb.text += "\nLOCKED — " + buy.tooltip_text
		_:
			buy.text = "%d" % meta.price_of(item_id)
			buy.disabled = true
			buy.tooltip_text = "Not enough banked coins"
			blurb.text += "\nNeed %d more banked coins." % maxi(meta.price_of(item_id) - meta.get_wallet(), 0)
	row.add_child(buy)
	return row


func _prereq_names(def: Dictionary) -> String:
	var names: PackedStringArray = PackedStringArray()
	for req in Array(def.get("requires", [])):
		var rdef: Dictionary = MetaProgression.ARMORY.get(StringName(String(req)), {})
		names.append(String(rdef.get("name", req)))
	return ", ".join(names)


func _on_buy(meta: MetaProgression, item_id: StringName) -> void:
	UiFactory.play_press("BUY")
	if UiCommands.purchase(get_tree(), item_id):
		_feedback.text = "%s purchased. Rank %d." % [MetaProgression.ARMORY[item_id]["name"], meta.get_rank(item_id)]
		AudioManager.play_sfx(&"upgrade_select", -8.0)
	else:
		_feedback.text = "Purchase declined. Balance or availability changed."
	refresh()
