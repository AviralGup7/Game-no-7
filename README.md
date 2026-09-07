# Last Stand: Arena

A polished, expandable **third-person arena survival / action game** for Android,
built with **Godot 4.x** and **GDScript** (landscape, touch controls, mobile-optimised
rendering).

You fight waves of enemies in a compact arena. Enemies pursue and attack; you move
with a virtual joystick, attack with a melee weapon, dodge, pick upgrades between
waves, and chase a high score. When you fall, you see your run summary and can
instantly restart.

> **Project status — arena build-out + meta game (see `CHANGELOG.md`).** Beyond the
> Phase 1–4 foundation (project config, combat, integrated run loop, deterministic
> upgrade selection), the game now ships: 8 enemy archetypes (incl. splitter mites and
> a 3-phase Warlord boss) with elites, 6 weapons in a 2-slot switchable loadout,
> 5 active skills + 8 status effects, 7 wave mutators + adaptive difficulty director,
> 3 arena configs with hazards, a meta game (banked-currency armory, 19 achievements,
> playable daily challenge), full settings (volumes, remapping, accessibility), and
> procedural audio fallback so the game is never silent. All content stays data-driven
> (`.tres` under `res://data/`) and headless-tested.

---

## Key principles

- **Data-driven content.** New enemies, arenas, upgrades, weapons, cameras and audio
  are added as typed `.tres` resources under `res://data/`, discovered + validated by
  the `ContentRegistry` autoload. Core systems are not rewritten to add content.
- **Deterministic + testable.** Score, wave generation, upgrade selection, save
  validation and spawn logic expose pure/deterministic functions exercised headlessly.
- **Graceful failure.** Missing optional assets, a corrupted save, or an invalid
  content resource produce diagnostics + fallback, never a crash.
- **Legally safe assets.** Every third-party asset is logged with its licence in
  `THIRD_PARTY_ASSETS.md` / `AUDIO_MANIFEST.md`; no unattributed or unclear assets.
- **Reproducible.** Godot version, Android requirements, build + CI steps are pinned
  in `docs/BUILD.md`; `scripts/build_android.sh` and the GitHub Actions workflow build
  from a fresh clone.

---

## Getting started (development)

1. Install the pinned Godot 4.x editor (see `docs/BUILD.md` for the exact version).
2. Clone this repository.
3. `godot --path . --editor` to import assets, then press **F5** (or run the
   `scenes/main/main.tscn` scene).
4. Keyboard dev controls: `WASD`/arrows to move, `Space`/`Enter` to attack,
   `Shift` to dodge, `Q`/`E`/`R` for skills, `Tab` to switch weapons, `Esc` to pause
   (attack/dodge/skills/weapon-switch are remappable in Settings).
5. On an Android device/emulator, touch: left-side floating joystick, right-side
   attack + dodge + weapon-switch buttons, tappable skill bar.

Run the headless unit tests:

```bash
godot --headless --path . --import          # first run: import + generate caches
godot --headless --path . --script res://tests/run_tests.gd
```

---

## Repository map

```
assets/        downloaded third-party assets + placeholders (textures, materials, fonts)
scenes/        main, arena, player, ui (canonical scene tree)
scripts/       core autoloads + per-system controllers/state
data/          typed .tres content: enemies, upgrades, arenas, cameras, weapons,
               skills, status, pickups, waves, audio
tests/         unit suites + doubles + run_tests.gd (headless runner)
docs/          BUILD.md, ART_STYLE.md, EXTENDING.md
tool/          repository/resource validation tooling
scripts/       build automation (build_android.sh, download_assets.py)
.github/       CI workflow that builds + tests from a fresh clone
```

See `docs/EXTENDING.md` for how to add a new enemy / upgrade / arena / weapon / cue
/ UI panel / test.

## Documentation

| Doc | Purpose |
|---|---|
| `docs/BUILD.md` | Godot/Android versions, export + signing, build/test commands |
| `docs/ART_STYLE.md` | Visual style, palette, scale, lighting, UI + future content rules |
| `docs/EXTENDING.md` | Step-by-step extension guides |
| `THIRD_PARTY_ASSETS.md` | Visual asset licences + provenance |
| `AUDIO_MANIFEST.md` | Audio asset licences + provenance |
| `CHANGELOG.md` | Per-phase progress |
