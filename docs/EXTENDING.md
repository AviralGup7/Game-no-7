# EXTENDING.md — How to add content without rewriting core systems

Content is added through **data resources + registries + scenes**, not core rewrites.
The `ContentRegistry` autoload discovers `.tres` files under `res://data/<kind>/`,
validates them, and caches them. This file shows each common extension.

## 1. Add a new enemy archetype

1. Create `res://scenes/enemies/<name>_enemy.tscn` instancing/deriving the enemy base
   contract (added in the enemy phase) with its own stats/model/animation.
2. Create `res://data/enemies/<name>_enemy.tres` with `class EnemyConfig`:
   `archetype_id`, `display_name`, `scene`, stats, `color_tint`, `tags`, `unlock_wave`.
3. Restart/refresh — the registry validates it (missing scene, bad values, duplicates)
   and exposes `ContentRegistry.get_enemy(&"<name>")`.
4. Add it to wave data so it can appear, plus a `WaveSpawnEntry`.

No core script changes.

## 2. Add a new upgrade

1. Create `res://data/upgrades/<name>.tres` (`class UpgradeConfig`).
2. Set `upgrade_id`, `display_name`, `description`, `rarity`, `max_stacks`,
   `stat_modifiers` (use the stable modifier keys listed in `upgrade_config.gd`),
   `prerequisites`, `exclusions`, `unlock_wave`, `weight`, `disabled`.
3. Validation checks modifier keys/prerequisites/exclusions/rarity automatically.

The upgrade panel still renders whatever the selection system returns — no UI rewrite.

## 3. Add a new arena

1. Create `res://scenes/arena/<name>_arena.tscn` following the canonical arena tree:
   `PlayerStart`, `SpawnPoints`/markers in group `enemy_spawn_point`, colliders,
   environment. `arena.gd` handles marker discovery generically.
2. Create `res://data/arenas/<name>.tres` (`class ArenaConfig`) pointing at the scene,
   with a `default_camera_profile` and `background_music_cue`.
3. Unlock it via `SaveManager.unlock_arena("<name>")` (or ship pre-unlocked).

## 4. Add a new weapon

1. Add an attack profile data resource under `res://data/weapons/`.
2. Implement it through the player's `AttackController` interface (cooldown, range,
   damage, payload) — keep player input/score/UI contracts unchanged.

## 5. Add a new audio cue

1. Drop an `.ogg` in `res://data/audio/<cue_id>.ogg` (registry auto-registers it with
   `AudioManager` keyed by file base name).
2. Play it anywhere via `AudioManager.play_sfx(&"<cue_id>")` (music via `play_music`).
3. Log its licence in `AUDIO_MANIFEST.md` and store the licence file in
   `ASSET_LICENSES/`.

Optional cues are safe: a missing cue logs a diagnostic and never crashes.

## 6. Add a new UI panel

1. Add a panel `Control` (or extend `ui_root.gd`'s `_build_screens`).
2. Drive it from `GameRoot` state via `EventBus.game_state_changed` and the panel
   switching in `ui_root.gd` — UI never mutates global state, it calls the narrow
   `GameRoot` command API.

## 7. Add a new test

1. Create `res://tests/unit/test_<area>.gd` exposing `static func suite() -> Array`
   of `{name, passed, why}` dictionaries (see existing tests).
2. Add the path to `UNIT_SUITES` in `res://tests/run_tests.gd`.
3. Run `godot --headless --path . --script res://tests/run_tests.gd`.

## Conventions

- Stable IDs as `StringName`; never magic numbers — put tuning in the relevant `.tres`.
- Validate new content resources (`validate()` returns problems).
- Prefer typed resources; keep large logic out of one script.
