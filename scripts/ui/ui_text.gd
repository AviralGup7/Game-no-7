class_name UiText
extends RefCounted

## Centralized UI string lookup, extracted from ui_root. Default English strings
## (single shipped language for now). Localization swaps this table or the whole
## lookup for translated packs later without touching call sites.
## Pure: fully headless-testable.


const TEXT := {
	"app_title": "LAST STAND",
	"app_subtitle": "ARENA",
	"play": "PLAY",
	"daily": "DAILY CHALLENGE",
	"armory": "ARMORY",
	"settings": "SETTINGS",
	"quit": "QUIT",
	"resume": "RESUME",
	"restart": "RESTART",
	"main_menu": "MAIN MENU",
	"best_score": "Best score",
	"best_wave": "Best wave",
	"score": "SCORE",
	"wave": "WAVE",
	"combo": "COMBO",
	"currency": "COINS",
	"hp": "HP",
	"paused": "PAUSED",
	"game_over": "GAME OVER",
	"kills": "Kills",
	"time_survived": "Time survived",
	"wave_reached": "Wave reached",
	"upgrades_title": "CHOOSE AN UPGRADE",
	"upgrade_choose_hint": "Choose one — your hero keeps it until the run ends.",
	"upgrade_none": "No upgrades available this round.",
	"upgrade_selected_fx": "APPLIED",
	"retry": "RETRY",
	"close_settings": "CLOSE",
	"reset_settings": "RESET SETTINGS",
	"mute": "Mute audio",
	"vibration": "Vibration",
	"reduced_motion": "Reduced motion",
	"high_contrast": "High contrast",
	"version": "v0.4.0",
}


## Look up a UI string; unknown keys echo back so missing entries stay visible.
static func get(key: StringName) -> String:
	var k := String(key)
	if TEXT.has(k):
		return TEXT[k]
	return k
