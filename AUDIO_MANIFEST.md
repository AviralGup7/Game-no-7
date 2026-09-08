# Audio manifest — Last Stand: Arena

Reviewed **2026-09-07** for the current melee arena-survival loop. Only clearly
licensed recordings are accepted; no ripped audio, paid packs, or voice cloning.

## Approved sources

| Pack / recording | Creator | Original source | Download source | Licence |
|---|---|---|---|---|
| RPG Audio 1.0 | Kenney | https://kenney.nl/assets/rpg-audio | `Boyquotes/kenney-rpg-audio-for-godot` | CC0-1.0 |
| Impact Sounds 1.0 | Kenney | https://kenney.nl/assets/impact-sounds | `Boyquotes/kenney-impact-sounds-for-godot` | CC0-1.0 |
| Interface Sounds 1.0 | Kenney | https://kenney.nl/assets/interface-sounds | `Calinou/kenney-interface-sounds` | CC0-1.0 |
| Epic Boss Battle [Seamlessly Looping] | Juhani Junkala / SubspaceAudio | https://opengameart.org/content/boss-battle-music | `AureaFUNSoft/SomniumRevise` (Ogg conversion) | CC0-1.0 |
| Medieval: The Old Tower Inn (loop version) | RandomMind | https://opengameart.org/content/medieval-the-old-tower-inn | `ashawkey/GlyphChess` (Ogg conversion) | CC0-1.0 |

The original creator pages explicitly license these assets **CC0**. Personal and
commercial use, modification, and redistribution in source and compiled games are
permitted; attribution is not required. Credit is retained voluntarily. The two
music mirrors identify the original works; only those tracks and their source
notices are selected, not any other music or game code from those repositories.

Exact immutable revisions, download URLs, local paths, original names, acquisition
dates, sizes, and per-file SHA-256 checksums are in `assets/manifest.json`. Source
notices are saved under `ASSET_LICENSES/`. GitHub's public content API is used
because direct creator-download hosts are not reachable from this workspace.

## Enemy telegraph cues (encounter pass, 2026-09-08)

`data/audio/enemy_windup.wav`, `data/audio/enemy_dash.wav` and
`data/audio/enemy_explosion.wav` are **original synthesized works** generated for
the enemy telegraph/charge/detonation feedback (rising swell, falling swoosh, low
boom). They are project-generated content dedicated to the public domain (CC0);
no third-party recordings were used. They register automatically by file base
name and are played through the existing optional-cue path in `EnemyAudio`
(a missing cue is still a logged no-op).

## Runtime fallback (procedural audio)

Until staged packs are wired into `res://data/audio/`, the game is never silent:
`ProceduralSfx` deterministically synthesizes every referenced cue at startup
(SFX: `player_attack`, `player_hurt`, `player_death`, `player_dodge`, `enemy_hit`,
`enemy_death`, `enemy_attack`, `enemy_spawn`, `pickup`, `upgrade_select`; music:
`music_menu`, `music_calm`, `music_battle`, `music_boss`, `music_victory`). Real
drops always take precedence — procedural fill never overwrites a registered cue.

## Format and integration

- Music is already compressed **Ogg Vorbis**, not oversized WAV masters or previews.
  These are upstream conversions of the looping tracks; local files are byte-for-byte
  copies, renamed to stable cue IDs. No local re-encoding was performed.
- RPG/impact sounds are **Ogg Vorbis**. Interface sounds are the Godot mirror's
  **PCM WAV** conversions (short clips, suitable for inexpensive mobile playback).
- Downloading a file is not the same as connecting an event or animation. The
  cue mapping and integration status are documented in `docs/ASSET_CATALOG.md`.
- Existing AudioManager fallback remains safe if an optional cue is absent.

See `THIRD_PARTY_ASSETS.md` for shared asset policy and restore/verification commands.

## Planned cue map (not registered in the running game yet)

Paths below are relative to `assets/audio/`. Every file is in the checksum lock.
The full variant lists, intended buses, loop flags, and suggested gains are in
`assets/catalog.json`. Those JSON fields are **planning metadata**, not Godot
import settings or a new audio registry. `data/audio/` is still unchanged.

| Cue | Downloaded file(s) | Intended use |
|---|---|---|
| `player_attack` | `sfx/rpg/knife_slice.ogg`, `sfx/rpg/knife_slice_2.ogg` | Melee swing |
| `player_hurt` | `sfx/impact/impact_punch_medium_000.ogg`, `sfx/impact/impact_punch_medium_001.ogg` | Player impact (non-vocal) |
| `player_dodge` | `sfx/rpg/cloth_1.ogg`, `sfx/rpg/cloth_2.ogg`, `sfx/rpg/cloth_3.ogg` | Cloth swish |
| `player_death` | `sfx/impact/impact_soft_heavy_000.ogg` | Body fall (non-vocal) |
| `enemy_attack` | `sfx/rpg/chop.ogg` | Melee attack |
| `enemy_hit` | `sfx/impact/impact_wood_medium_000.ogg`, `sfx/impact/impact_generic_light_000.ogg`, `sfx/impact/impact_generic_light_001.ogg` | Impact / bone-like knock |
| `enemy_death` | `sfx/impact/impact_wood_heavy_000.ogg`, `sfx/impact/impact_punch_heavy_000.ogg` | Heavy impact |
| `enemy_spawn` | `sfx/interface/open_001.wav` | Spawn notification |
| `upgrade_select` | `sfx/interface/confirmation_001.wav`, `sfx/interface/confirmation_002.wav` | Upgrade choice |
| `pickup` | `sfx/rpg/handle_coins.ogg`, `sfx/rpg/handle_coins_2.ogg` | Currency collection |
| `wave_started` | `sfx/impact/impact_bell_heavy_000.ogg` | Wave bell |
| `game_over` | `sfx/interface/error_006.wav` | Run-end notification |
| `ui_confirm` | `sfx/interface/click_001.wav` | Button press |
| `ui_back` | `sfx/interface/back_001.wav` | Back / cancel |
| `footstep` | `sfx/impact/footstep_concrete_000.ogg`, `sfx/impact/footstep_concrete_001.ogg`, `sfx/impact/footstep_concrete_002.ogg`, `sfx/impact/footstep_concrete_003.ogg` | Stone/concrete footsteps |
| `equip` | `sfx/rpg/draw_knife_1.ogg` | Weapon draw (reserve) |
| `item_drop` | `sfx/rpg/drop_leather.ogg` | Item drop (reserve) |
| `arena_menu` | `music/arena_menu.ogg` | Menu music — 49.95 s, stereo 44.1 kHz, loop-ready |
| `arena_gameplay` | `music/arena_gameplay.ogg` | Combat music — 123.43 s, stereo 44.1 kHz, loop-ready |

### Mixer / import notes

All 31 files decode successfully and contain non-silent audio. A few of the
original RPG Vorbis files decode with peaks above 0 dBFS, so they should not be
played together at full gain. Source audio was deliberately **not normalized or
re-encoded**. Start SFX around −8 dB (footsteps lower), then mix on the target
device; the two music sources also have different loudness. Suggested gains are
not applied to gameplay yet.

Enable **Loop** on the two music streams in Godot and audition their transitions.
Leave SFX non-looping. Wrap clips/variants in `AudioStreamRandomizer` resources
named after these cue IDs under `data/audio/` so the existing `ContentRegistry`
can discover them; then connect menu/wave/UI events that currently have no call
site. Downloaded music and `catalog.json` alone do not start playback.
