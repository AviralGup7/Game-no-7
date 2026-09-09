class_name UiModal
extends Node
## Owns the single modal ConfirmationDialog used for destructive / confirm-then-act
## flows (leave run, quit, …) so no screen has to hand-build one. Confirms queue
## FIFO so overlapping requests serialise instead of stomping; each dialog is sized
## from the live viewport and text scale and focus returns to the opener.
##
## UiRoot keeps a handle to the underlying dialog (`_confirm`) for engine-level
## tests; every "confirm then act" flow routes through UiModal.confirm() so callers
## never construct or size a ConfirmationDialog themselves.

var dialog: ConfirmationDialog
var _queue: Array = []
var _pending_command: Callable = Callable()
var _pending_ok: String = ""
var _focus_owner: Control
var _wired := false


func _init() -> void:
	dialog = ConfirmationDialog.new()
	add_child(dialog)
	_wire()


func _wire() -> void:
	if _wired or dialog == null:
		return
	_wired = true
	dialog.confirmed.connect(_on_confirmed)
	dialog.canceled.connect(_on_canceled)


func is_open() -> bool:
	return dialog != null and dialog.visible


func get_dialog() -> ConfirmationDialog:
	return dialog


## Queue a "confirm then act" prompt. `command` runs only if the player confirms;
## cancelling just closes (and an adjacent flow may decide to keep the modal state).
func confirm(title: String, body: String, ok: String, cancel: String, command: Callable) -> void:
	_queue.append({"title": title, "body": body, "ok": ok, "cancel": cancel, "command": command})
	_advance()


func cancel_all() -> void:
	_queue.clear()
	_pending_command = Callable()
	if dialog != null and dialog.visible:
		dialog.hide()
	_restore_focus()


func _advance() -> void:
	if dialog == null or _queue.is_empty() or dialog.visible:
		return
	var req: Dictionary = _queue[0]
	_queue.remove_at(0)
	dialog.title = String(req["title"])
	dialog.dialog_text = String(req["body"])
	dialog.ok_button_text = String(req["ok"])
	dialog.cancel_button_text = String(req["cancel"])
	_pending_command = req["command"] as Callable
	_pending_ok = String(req["ok"])
	_capture_focus()
	_present()


## Size the modal from the live viewport and the text scale so the message never
## clips at 200% text or overflows a small phone screen.
func _present() -> void:
	var view := Vector2(1280, 720)
	if get_viewport() != null:
		view = get_viewport().get_visible_rect().size
	var scale := 1.0
	if SaveManager != null and SaveManager.get_settings() != null:
		scale = clampf(SaveManager.get_settings().text_scale, 0.8, 2.0)
	var width := int(clampf(view.x * 0.8, 320.0, 560.0 * scale))
	var height := int(clampf(200.0 * scale, 180.0, maxf(view.y * 0.8, 180.0)))
	dialog.min_size = Vector2i(mini(width, int(view.x)), mini(height, int(view.y)))
	dialog.popup_centered(dialog.min_size)
	for button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
		if button != null:
			button.custom_minimum_size = Vector2(150, UiTheme.TOUCH_MIN)
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.get_ok_button().grab_focus.call_deferred()


func _capture_focus() -> void:
	_focus_owner = null
	if get_viewport() != null:
		_focus_owner = get_viewport().gui_get_focus_owner() as Control


func _restore_focus() -> void:
	if _focus_owner != null and is_instance_valid(_focus_owner) and _focus_owner.is_inside_tree():
		_focus_owner.grab_focus.call_deferred()
	_focus_owner = null


func _on_confirmed() -> void:
	# Destructive confirms read as a "back"/dismiss cue (matching legacy ui_back
	# expectations for leave/quit); a cancelled confirm always ticks the back cue.
	UiFactory.play_press(_pending_ok)
	var command := _pending_command
	_pending_command = Callable()
	_restore_focus()
	if command.is_valid():
		command.call()
	_advance()


func _on_canceled() -> void:
	UiFactory.play_press("CANCEL")
	_pending_command = Callable()
	_restore_focus()
	_advance()
