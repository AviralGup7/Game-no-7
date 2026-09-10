# Input remapping resilience review

## Research basis

The input settings layer was reviewed against:

- [Godot InputEvent documentation](https://github.com/godotengine/godot-docs/blob/master/tutorials/inputs/inputevent.rst), which recommends action-based input and runtime InputMap customization.
- [Godot InputEventKey 4.6 documentation](https://docs.godotengine.org/en/4.6/classes/class_inputeventkey.html), which states that mappings should have only one of `keycode`, `physical_keycode`, or `unicode` set and explains how event equality is determined.
- [Godot InputMap remapping guidance](https://uhiyama-lab.com/en/notes/godot/input-map-key-binding-management/), which recommends serializing compact device-specific data instead of trying to persist InputEvent objects, restoring defaults, detecting conflicts, and consuming the capture event.
- [Godot's physical-key documentation issue](https://github.com/godotengine/godot/issues/82091), which documents the difference between physical layout-independent keys and the localized display label.

## Weakness found

The previous loader erased an action's working keyboard/gamepad bindings before validating its saved array. A malformed or unsupported entry could therefore turn a valid action into an unbound action. It also serialized every keyboard event as a physical key with code zero when the platform only supplied `keycode`; zero is not a usable key identity. Finally, rebinding accepted malformed zero-value events.

## Implemented contract

- Deserialization is transactional per action: entries are parsed, type-checked, range-checked, and deduplicated before `InputMap` is mutated.
- If an action contains no valid saved bindings, its project defaults remain untouched.
- Existing `kind: key` data remains compatible as the legacy physical-key representation.
- New keyboard data distinguishes `key_physical` from `keycode`, preserving logical-key fallback on platforms that do not provide a physical code.
- Zero-value and malformed codes are rejected; joypad button values are bounded.
- Rebinding uses the same validity checks as save restoration.
- The existing action allowlist, per-action cap, and conflict detection remain in place.

## QA checklist for Godot/device testing

1. Corrupt one action's saved array and verify its project default binding remains usable.
2. Load a legacy `kind: key` binding and verify it still restores.
3. Save a key event with only `keycode` set and verify it round-trips as `keycode` rather than zero physical code.
4. Try negative, zero, string, and oversized codes and verify they are ignored.
5. Restore duplicate entries and verify only one binding is installed.
6. Rebind using an empty `InputEventKey` and verify the operation is rejected.
7. Test non-QWERTY keyboard layouts: physical bindings should remain layout-independent while labels should remain understandable.
8. Verify the settings UI still offers reset-to-default controls and conflict warnings.
