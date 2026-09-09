# UI Redesign — "Last Stand: Arena"

A cohesive visual overhaul of the whole interface toward a **polished dark-arena**
look: deep space-navy surfaces, a refined cyan/gold accent system, crisper raised
cards with soft shadows, glossy rounded meters, and a clear gold **primary
action** on every screen.

> These PNGs are **design previews**, hand-rendered from the exact tokens below
> with the game's real Rajdhani font. The Godot editor binary is not installable
> in this environment, so they stand in for engine screenshots. The source of
> truth is the GDScript.

## Preview index

| File | Screen | Source |
|---|---|---|
| `ui_main_menu.png` | Main menu hero + CTAs | `scripts/ui/menu_panel.gd` |
| `ui_gameplay_hud.png` | In-game HUD (top plate, vitals, minimap, skill bar, touch controls, boss bar) | `scripts/ui/game_hud.gd` + `ui_root.gd` |
| `ui_pause.png` | Pause overlay | `scripts/ui/ui_root.gd` (`_build_pause`) |
| `ui_upgrade.png` | Upgrade selection cards | `scripts/ui/upgrade_panel.gd` |
| `ui_run_summary.png` | Victory / run-ended screen | `scripts/ui/run_summary_panel.gd` |

## What changed in code

**Design tokens & theme — `scripts/ui/ui_theme.gd`**
- New refined palette (tokens below) with dedicated health/stamina/XP/danger
  colours, plus `EDGE_SOFT`, `SURFACE_ALT`, `SURFACE_TOP` for depth.
- New chrome builders used across the UI: `plate()` (raised card w/ shadow),
  `row_card()`, `glass()` (translucent plate over gameplay), `bar()` (meter fill),
  `control()` (buttons).
- Theme `create()` now styles buttons (subtle rest → cyan hover → loud gold
  press), raised panels, LineEdit, ProgressBar trough/fill and sliders globally —
  so every button, card and meter across all screens inherits the new look.

**Widget factory — `scripts/ui/ui_factory.gd`**
- Added `primary()`: the gold, high-emphasis action button used for the single
  strongest CTA on a screen (START RUN, RESUME RUN, ENTER ARENA, CONTINUE…).

**In-game HUD — `scripts/ui/game_hud.gd`**
- Rebuilt the top plate: gold wave badge + objective left, coin chip + a stacked
  SCORE label/value right, gold-rimmed pause target.
- Rebuilt the vitals dock: HEALTH row (name + live numbers) with a glossy rounded
  green bar; stamina bar in blue; XP/level bar in violet; weapon + objective rows.
- Translucent glass plates with a crisp rim so meters read over any arena.
- All geometry still comes from the shared `UiLayout` solver — nothing overlaps,
  and the Android touch-target floor is preserved.

**Menus — `scripts/ui/menu_panel.gd`, `scripts/ui/ui_root.gd` (pause), `run_setup_panel.gd`**
- Hero typography: kicker → wordmark → gold arena underline → hairline rule →
  tagline, with primary gold CTA and icon-badged secondary buttons.
- Player-profile card (best / wave / bank / prestige) is now its own raised plate.
- Pause and Run Setup lead with the gold primary button.

## Design tokens

| Role | Value |
|---|---|
| `INK` (deepest bg) | `#06090f` |
| `SURFACE` / `SURFACE_ALT` / `SURFACE_TOP` | `#0e1726` / `#15233a` / `#1c2f4d` |
| `EDGE` / `EDGE_SOFT` | `#33506f` / `#203349` |
| `TEXT` / `MUTED` | `#eaf2fa` / `#92a7bd` |
| `GOLD` / `CYAN` | `#f4c76b` / `#55d3e6` |
| `HEALTH` / `STAMINA` / `XP` / `DANGER` | `#46e0a2` / `#6cc0ff` / `#c789f0` / `#ff5a52` |

## Modular structure (single-sourced chrome)

Reusable widgets live in one place so screens compose instead of re-implement:

| Primitive (`scripts/ui/ui_factory.gd`) | Consumers |
|---|---|
| `primary()` — gold CTA button | START RUN, RESUME RUN, ENTER ARENA, CONTINUE |
| `overlay()` — full-screen scaffold (blocking panel + scroll/centre + optional scrim) | settings, armory, status, pause via `UiRoot._mount_overlay` |
| `gauge()` — shared meter | health / stamina / XP bars (in `UiGauges`) |
| `metric()` — caption + gauge group | generic labelled bars |
| `select_card()` — title + dropdown + description | Run Setup pickers |
| `screen_header()` — eyebrow + title + subtitle hero | settings, armory, pause, status |
| `kicker()` / `hairline()` — hero accent type | main-menu hero |

- **`scripts/ui/ui_gauges.gd`** — the in-run vitals dock (health / stamina /
  level / weapon / objective) owns both its construction and value formatting.
  It ships as a reusable packed scene (`scenes/ui/ui_gauges.tscn`, instantiated by
  `GameHud`) so it is an editor surface, while meters are still built exclusively
  from `UiFactory.gauge` so HUD and boss meters can never drift apart.
- **`scripts/ui/ui_modal.gd`** (`UiModal`) — owns the single confirm
  `ConfirmationDialog` (queue, viewport/text-scale sizing, focus restore). Leave /
  quit / destructive "confirm then act" flows route through `UiModal.confirm()`;
  `UiRoot` keeps a handle for engine tests.
- **`GameHud` dirty-flag setters** — score / currency / wave / combo and the
  0.15 s weapon poll skip all label/tooltip work when the value is unchanged.
- Boss frame is its own widget and reuses the shared `UiTheme.bar` fill token.

## Verification & remaining work

- All UI scripts parse clean under `gdlint 4.5.0` (Godot 4 parser).
- All **427** Python regression tests pass, including UI/theme/layout guards and
  the modularisation guards in `tests/python/test_regress_ui_modular.py`
  (shared vocabulary stays single-sourced, meters only built in `UiFactory.gauge`
  and the layered boss frame, HUD loads the packed `UiGauges` scene, confirms
  route through `UiModal`, and the runtime UI runner smokes the new components).
- The behavioural geometry contract (no overlaps, inside safe area at every
  Android resolution) is enforced at runtime by `tests/ui/ui_test_runner.gd` —
  run it in the Godot editor once available to confirm.

**Recommended next step:** open the project in Godot 4.4.1 and re-verify visuals
on a device/emulator; the code changes are complete but pixel-polish is best
confirmed against the live engine.
