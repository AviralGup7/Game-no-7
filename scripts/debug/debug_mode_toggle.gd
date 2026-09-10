class_name DebugModeToggle
extends VBoxContainer
## Reusable debug-mode switch shared by the main menu and Settings. Reflects the
## DebugErrorHandler flag and writes back through it; the handler persists the
## choice itself, so the toggle needs no save plumbing of its own. References the
## autoload directly by name like every other UI panel (see docs/ARCHITECTURE.md).

var _check: CheckButton
var _syncing := false


func _ready() -> void:
	_check = UiFactory.check("Debug mode: freeze on error with a copyable report", self, DebugErrorHandler.is_debug_mode(), _on_toggled, 20)
	var note := UiFactory.label("When ON, errors freeze the game instead of crashing, with full details to copy.", self, 16)
	note.modulate = UiTheme.MUTED
	DebugErrorHandler.debug_mode_changed.connect(_on_external_change)


func _on_toggled(enabled: bool) -> void:
	if _syncing:
		return
	DebugErrorHandler.set_debug_mode(enabled)
	UiFactory.play_press("TOGGLE")


func _on_external_change(enabled: bool) -> void:
	_syncing = true
	if _check != null:
		_check.set_pressed_no_signal(enabled)
	_syncing = false
