# Asset Attribution & Licences

Every third-party asset in this repository is **CC0 1.0 Universal (public
domain dedication)**. CC0 imposes **no attribution requirement** — this file
exists as a provenance record, not a legal obligation.

Keeping it matters anyway: if a licence is ever questioned (Play review, an
acquirer, a takedown claim), this is the evidence trail. Never ship an asset
you cannot trace to a source URL and a licence.

---

## Sound effects — `assets/audio/sfx/`

All from **Kenney**'s *Interface Sounds* pack, released **CC0**.

| File in repo | Original | Used for |
|---|---|---|
| `shade.ogg` | `click_001.ogg` | A cell is shaded out |
| `shade_alt.ogg` | `select_001.ogg` | Alternate shade sound (see note) |
| `circle.ogg` | `switch_002.ogg` | A cell is ringed as definitely-stays |
| `erase.ogg` | `drop_001.ogg` | A mark is cleared |
| `wrong.ogg` | `drop_002.ogg` | A mark contradicts the answer |
| `puzzle_complete.ogg` | `confirmation_004.ogg` | Puzzle solved |
| `streak_up.ogg` | `confirmation_002.ogg` | Daily streak extended |
| `hint_used.ogg` | `bong_001.ogg` | A hint was shown |
| `button_tap.ogg` | `click_001.ogg` | Any button press |
| `navigate_back.ogg` | `back_001.ogg` | Leaving a screen |

Pack: <https://kenney.nl/assets/interface-sounds> · Mirror used:
<https://gamesounds.xyz/?dir=Kenney's+Sound+Pack/Interface+Sounds> ·
Licence: [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/)

**Note on two shade samples:** a run of quick marks played from a single
sample sounds like a machine gun. `AudioService.playShade()` alternates the
two so it stays soft.

**Duration check — this caught a real problem.** Kenney's pack contains
several files around **10 ms long**, which are silent in practice. `click_002`
and `click_004` were both measured at 10 ms and rejected; `select_001` (43 ms)
was used instead. Every shipped file was measured with `ffprobe` and is at
least 43 ms. Never assume a sound file makes a sound.

**`wrong.ogg` is a soft drop, not a buzzer.** Someone who has just marked a
square incorrectly is already mildly frustrated; a harsh error tone reads as
being told off. Kenney's `error_*.ogg` files were deliberately rejected.

---

## Music — `assets/audio/music/`

By **MintoDog** via OpenGameArt.org, released **CC0**.

| File in repo | Original | Source |
|---|---|---|
| `music_menu.ogg` | `cozy_puzzle_stage_select_bpm100.ogg` | [Cozy Puzzle Stage Select](https://opengameart.org/content/cozy-puzzle-stage-select) |
| `music_gameplay.ogg` | `cozy_puzzle_in-game_2_bpm90.ogg` | [Cozy Puzzle In-Game 2](https://opengameart.org/content/cozy-puzzle-in-game-2) |

Artist page: <https://opengameart.org/users/mintodog> ·
Licence: [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/)

**Modifications:** loudness-normalised to −18 LUFS (TP −2 dBTP), re-encoded to
Vorbis q2 for mobile size. Musical content unchanged.

Music **defaults to OFF**. Audio that starts unasked is an uninstall trigger
for this audience — many play near others, in care settings, or with hearing
aids.

---

## Board, icons and store graphics

**Not third-party assets — generated from source in this repo.**

The board is a `CustomPainter` (`lib/widgets/hitori_board.dart`); icons and
store graphics come from `tool/generate_icons.py` (Pillow). Byte-reproducible;
CI regenerates and fails on drift. No third-party licence surface at all.

---

## Adding new assets

1. Confirm the licence is **CC0** or **Pixabay Content Licence**. Avoid CC-BY
   unless you will genuinely maintain an attribution screen; avoid CC-BY-SA
   and any NonCommercial (`NC`) licence entirely — `NC` is incompatible with
   an ad-monetised app.
2. Record the source URL and licence **in this file, in the same commit**.
3. **Measure the duration.** Anything under ~30 ms is inaudible.
4. Re-run `tool/verify_assets.sh`.
