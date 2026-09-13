class_name EffectReadability
extends RefCounted

## Accessibility lookups for the VFX path. The EffectDirector uses these to decide
## how loud an effect may be (reduced motion), how strong its ink is (high contrast)
## and which colour reads for boss/danger telegraphs.
##
## Settings come straight from SaveManager and are null-safe, so headless runs and
## tests without a live save behave exactly like an unconfigured game.

## Deuteranopia-safe boss/danger ink: yellow outer + red inner, not green-on-sand.
## `danger` is the caller's "this outranks a normal hit" decision (boss tier, or the
## high-contrast setting) so this module needs no knowledge of the priority ladder.
static func telegraph_color(color: Color, danger: bool) -> Color:
	if high_contrast() or danger:
		if color.g > color.r and color.g > color.b:
			return Color(1.0, 0.92, 0.12)
		if color.r > 0.6:
			return Color(1.0, 0.12, 0.08)
	return color


static func reduced_motion() -> bool:
	return SaveManager != null and SaveManager.get_settings() != null and SaveManager.get_settings().reduced_motion


static func high_contrast() -> bool:
	return SaveManager != null and SaveManager.get_settings() != null and SaveManager.get_settings().high_contrast
