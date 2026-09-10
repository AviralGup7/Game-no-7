# Agent 5 — UI / UX handoff

## Scope and baseline

Work is based on the untouched session baseline `2b8094a` on `arena/01a07e66-game-no-7`. No other agent branch was pulled in. Changes are limited to `scripts/ui/`, UI tests, and this document. GameRoot, Main, Player, Enemy, WaveManager, ContentRegistry, MetaProgression, SaveManager and the save schema are **not changed**.

## Screens and flow

| Presentation | Implementation / behavior |
|---|---|
| Boot / loading / error | Canonical state-to-screen mapping; noninteractive HUD while loading; menu recovery action |
| Main menu | Rajdhani typography, lightweight vector arena motif, supplied icons, personal records, bank balance, first-run invitation |
| Run setup | Explicit preview before starting; supplied arena catalogue, tags and unlock milestones; weapon catalogue, descriptions and base stats |
| Daily challenge | Today's UTC card, fixed weapon and mutators, offline/shared-seed explanation; midnight change requires review again |
| Gameplay HUD | Numeric health/stamina/XP meters, low-health text warning, level cap, wave defeat progress, score, combo, currency, current weapon/phase/ammo and pause |
| Skills | Full names, optional supplied icons, visible locked levels, cooldown seconds, remapped ready-key hints, declined-action feedback |
| Upgrades | Responsive 3-column / single-column cards, supplied icons, rarity labels, next stack preview, validated selection, rejected-choice feedback, double-tap lock |
| Boss / wave feedback | Boss HP numbers and phase labels, visible trailing damage bar, reduced-motion snap; bounded/coalesced announcements and separate persistent coach text |
| Pause | Resume, help, settings; confirmation before restart/abandon; subordinate settings/help return to pause rather than accidentally resuming |
| Settings | Staged copy, explicit Save / discard-on-Back, volumes with percentages, mute, vibration, aim assist, reduced motion, contrast, text size and saved quality |
| Armory | Existing prices/ranks/wallet, purchase feedback, visible prerequisites and missing coin amounts (not tooltip-only), maxed state and read-only achievement gallery |
| Game over | Headline score, wave, survival duration and personal best |
| Run summary | Arena/mode, score, kills, wave, duration, run coins, final weapon, best combo, damage taken, kill pace, upgrade stacks, seed/run ID |
| Meta reward | Observed wallet delta after finalization; already-banked explanation; Armory, retry same mode, review and menu actions |
| Onboarding / help | Movement, attack, stamina/dodge, skills, switching, XP, upgrades, boss/minimap and permanent-vs-run progression; remapped key labels, explicit coach skip/replay |

Local navigation completes:

`MENU → SETUP / DAILY PREVIEW → PLAYING → WAVE_TRANSITION → UPGRADE_SELECTION → PLAYING / BOSS → GAME_OVER → RUN_SUMMARY → META_REWARD → ARMORY / RETRY / MENU`

`RUN_SUMMARY`, `META_REWARD`, `SETUP`, `HELP`, `SETTINGS` and `ARMORY` are **presentation pages**, not additional GameRoot states. Reward review never calls a grant or claim command. A deep-copied run summary is taken at `run_ended`; wallet display is deferred until all finalization observers have run.

## Important baseline limitations (do not paper over in UI)

1. **Main's state subscription is broken in the baseline.** `scripts/main/main.gd` connects `GameRoot.game_state_changed`, but GameRoot only emits `EventBus.game_state_changed`. Main's `_ready()` therefore cannot finish creating its persistent directors; normal wave/meta/tutorial integration needs the system-owning branch to repair this subscription. Agent 5 deliberately does not patch Main or synthesize a second world/meta manager.
2. **Arena selection is wired.** `UiCommands.select_arena(id)` delegates to `GameRoot.request_arena_selection(id)`, which calls `ContentRegistry.select_arena()`. Catalogue browsing still does not mutate selection until launch. Locked arenas (unlock_wave above the player's best wave) stay preview-only.
3. **Starter-weapon selection is wired.** `GameRoot.set_pending_weapon` / `get_daily_weapon` honour mode-fixed loadouts, then the daily card, then the setup pick, then Gladius. Armory-locked weapons stay preview-only until purchased.
4. **No GameRoot purchase/input facades.** `UiCommands` prefers `request_armory_purchase(id) -> bool`, `request_attack`, `request_dodge`, `request_weapon_switch`, `request_skill(slot)` and `request_move_input(value)` if present. Until then it retains the baseline's validated `MetaProgression.purchase` and Player input-intent APIs. These are explicit exceptions to GameRoot-only routing, not direct gameplay-state mutations. Do not change their boolean refusal semantics.
5. **FPS remains session-only; remaps persist.** Keyboard/gamepad rebindings serialize through `SettingsData.input_bindings` (save schema 6) and are restored on boot. FPS cap is still this-session. Touch layout adapts automatically.
6. **Reward ownership stays in MetaProgression.** UI displays the observed wallet change; it does not duplicate the run-currency conversion formula, write balances, or issue a second claim. If a future branch introduces asynchronous reward claims, replace the observed finalization contract with its authoritative receipt event.
7. **Exported content discovery is owned by ContentRegistry/ContentLoader.** Setup handles `.tres.remap` filenames, but relies on the registry to resolve arena/weapon IDs. The baseline loader itself must support exported resource paths; UI must not create its own gameplay registry.

## Synchronization contracts to preserve

- `EventBus.game_state_changed(previous, current)` uses the existing StringName state names.
- `run_started(run_id, seed)` follows world/player construction. `run_ended(score, wave, best)` follows RunState finalization and save recording.
- Health: `player_health_changed(current, maximum)` and `HealthComponent.current_health / max_health` for initial snapshots.
- Stamina: `stamina_changed(current, maximum)` and `StaminaComponent.get_current() / get_max()`.
- XP: active player's `ExperienceComponent.xp_changed(xp, level, into, required)` plus its existing read methods. UI never computes or awards XP.
- Weapons: `weapon_equipped(id, slot)`, `weapon_switched(old_id, new_id)`, active player's `WeaponManager.active_weapon_id()`.
- Skills: active player's `SkillController` read/cooldown/unlock methods. Casts use the player command facade, not direct controller mutation.
- Upgrades: `upgrade_choices_presented(Array[StringName])`, `upgrade_selected(id)`, `GameRoot.request_upgrade_selection(id) -> bool`.
- Bosses: `boss_spawned`, `boss_phase_changed`, `run_ended`, optional boss `died` signal and HealthComponent child.
- `RunState.summary()` retains score/currency/kills/wave/elapsed/best_combo/damage_taken/selected_upgrades/arena/seed/run_id keys. Unknown future metrics are not fabricated.
- `settings_changed(SettingsData)`, `save_failed(reason)`, `save_completed()` and existing SaveManager/meta getters remain authoritative.
- `get_announcement_banner()` remains available on the UI root for Main's TutorialManager binding.
- `get_debug_snapshot()` retains active_screen, joystick_active and joystick_value for existing debug tooling.

## Layout and accessibility

- All interactive screens are inside a single safe-area host. Physical Android display-safe rectangles are mapped into logical canvas coordinates; the 3D camera is untouched.
- Major panels scroll vertically, follow focus and fit the available width. Large text and narrower viewports turn upgrade cards into a single column.
- Touch movement capture, skills, dodge, swap and attack have separate regions. Capture is cancelled on modals, focus loss and releases outside a button. Desktop hides the movement/action overlay but retains mouse/keyboard-accessible skills.
- Attack/dodge/swap have explicit labels. Primary touch targets are 96–120 logical pixels, with 96-pixel skill buttons on the 1280-wide mobile canvas; narrower logical canvases use 64-pixel skills.
- Reduced motion removes banner scale effects, damage-number drift/pop and boss trailing interpolation. Status is communicated with labels/numbers, not color alone. Contrast and font scale update existing controls without compounding scale.
- No shaders, background videos, network services, new downloaded assets, or large binary assets are added. Supplied Rajdhani Regular/Bold, menu icons, and upgrade textures are used.

## Validation

UI runner: `GODOT=/path/to/godot scripts/ui/run_ui_validation.sh`

- Dedicated real-node UI fixture, isolated XDG save directory, two passes against fresh then existing profile.
- Covers boot/menu/setup, arena browsing without mutating selection, command-launched standard/daily runs, pause/settings/back/resume, settings staging and rebind cancellation/conflict, touch capture cancellation, upgrade validation and double taps, HUD event updates, boss/reduced-motion, bounded effects, summary/reward idempotence, Armory purchases and persistence.
- Layout matrix: 960×540, 1280×720, 1600×720, 1024×768, 720×1280; physical safe-area projection; 200% text/high contrast/reduced motion.
- This is geometry/interaction validation, **not** a claim of physical Android device testing or GPU screenshot review.

Full suite commands and final results are recorded below after execution.

### Executed results (Godot 4.4.1, 2026-09-08)

The environment did not contain Godot, and release-binary downloads failed. A **4.4.1-stable source build** was compiled in ignored `.cache/` for CPU/headless validation. It has no GPU renderer or Android toolchain; its renderer/fontconfig diagnostics are tooling limitations, not evidence of screenshot/device coverage.

| Check | Result |
|---|---|
| `python3 tool/validate_resources.py` | **PASS**, 70 shipped resource/scene files |
| `python3 scripts/download_assets.py --verify` | **PASS**, 222/222 approved files |
| `python3 tool/validate_assets.py` | **PASS**, 81 models, 79 PNGs, 31 audio files, 2 fonts |
| `python3 -m unittest discover -s tests/python -v` | **PASS**, 37 tests |
| `gdlint scripts tests` | **PASS** |
| `node tool/validate_gltf.cjs` | **PASS**, 81 models / 0 errors; 49 existing asset warnings (`NODE_SKINNED_MESH_NON_ROOT`, `IMAGE_FEATURES_UNSUPPORTED`, `NODE_SKINNED_MESH_LOCAL_TRANSFORMS`) |
| Native `tests/validate_asset_imports.gd` | **193 resources / 0 asset assertion failures**; global baseline script errors still occur during autoload startup |
| Native import + `tests/run_tests.gd`, unmodified gameplay baseline | **BLOCKED / incomplete** by baseline parser errors below. The old runner misleadingly prints `52 total, 0 failed` after aborting suite initialization; this is **not a pass** |
| UI runner on this branch without compatibility fixes | **BLOCKED** by the same CombatLog/scorekeeper startup errors; the new runner correctly exits nonzero |
| UI runner, isolated compatibility copy | **PASS: 194 checks on fresh save and 194 on existing save**, no GDScript runtime/parse errors. Five geometry profiles include button containment and stick/skills/action non-overlap, plus 200% text settings. An initial narrow-layout overlap found by the tests was corrected by deferring the skill container resize after minimum-size invalidation |
| Full existing GDScript suite, isolated compatibility copy | **289 tests, 8 failures**; the same 8 failures were reproduced with baseline UI in a separate comparison copy |
| Main menu smoke, isolated compatibility copy | Main scene and UI instantiated without GDScript errors after correcting Main's EventBus subscription |
| Android debug export | **BLOCKED**: export/build template, Android SDK/build-tools/platform-tools, Java SDK configuration and debug keystore are absent. No APK or physical-device result is claimed |
| `git diff --check` | **PASS** |

The UI test runs can leave an AudioStreamWAV/AudioStreamPlaybackWAV shutdown warning in the dummy-audio build. Verbose leak inspection identifies audio playback, not leaked UI controls.

### Exact external blockers / validation-copy changes

These were changed **only in ignored comparison/validation copies**, never in this branch's gameplay files:

- `scripts/combat/combat_log.gd:74`: `recent()` returns `.reverse()`, but Godot 4.4.1's `Array.reverse()` returns void. The copy reverses a local array then returns it.
- `scripts/core/run_scorekeeper.gd`: calls nonexistent `CombatLog.log()` at run reset/bonus recording. The existing method is `record()`; the copy uses it.
- `scripts/utilities/rng_service.gd`: oversized unsigned hex literals produce signed-int conversion errors. The copy substitutes their signed two's-complement equivalents.
- `tests/unit/test_waves.gd:92` (`name_ok`) and `tests/unit/test_upgrades.gd:18` (`valid`): variant-derived boolean inference fails; the copies explicitly annotate `bool`.
- `scripts/main/main.gd:29`: state subscription corrected from GameRoot to EventBus in the integration copy only.

After those compatibility changes, the **unchanged existing tests** still fail for generated-wave count caps, MeleeResolver nearest-first targets, four AreaDamage shape/chain cases, and two CombatLog cases. They fail identically with baseline UI and Agent 5 UI. Several combat tests access global transforms before nodes enter the tree. Their owners should resolve those tests/systems rather than changing UI to conceal the failures.

### UI API migration and CI integration

`UiText.get()` was an **existing UI-owned compile blocker**: it conflicts with native `Object.get()` (including the static/non-static signature). It is now `UiText.lookup(key: StringName) -> String`. UI call sites and the two UiText assertions in `tests/unit/test_extracted_modules.gd` were migrated; all other assertions in that shared test file are untouched. Other branches must use `lookup`, not reintroduce `get`.

Add `scripts/ui/run_ui_validation.sh` alongside the existing CI suite once the core blockers are resolved. It runs on an isolated temporary XDG profile, then reuses that profile to check existing-save behavior. It requires both an explicit passing check count **and** absence of GDScript errors, rather than trusting Godot's exit code alone.

Persistent personal-best labels read SaveManager's authoritative values, avoiding GameRoot's initial autoload-order cache before the save has loaded. Achievement presentation reads `Achievements.definitions()` / saved unlocks only. Coach skip/replay uses the existing tutorial-completed save flag; neither introduces new progression fields.
