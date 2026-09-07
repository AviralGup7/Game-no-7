# Audio Manifest — Licences & Provenance

Every externally sourced audio asset is logged here with its licence. Policy mirrors
`THIRD_PARTY_ASSETS.md`: only clearly licensed (preferably CC0/public-domain) audio
is accepted; no ripped or copyrighted tracks.

## Current state

No third-party audio is committed yet. The game is never silent anyway:
`ProceduralSfx` deterministically synthesizes every referenced cue at startup, and
real drops in `res://data/audio/` (`.tres`/`.ogg`/`.wav`/`.mp3`, registered by the
`ContentRegistry` keyed by file base name) always take precedence over the
procedural fallback. The referenced cue ids are:

- SFX: `player_attack`, `player_hurt`, `player_death`, `player_dodge`,
  `enemy_hit`, `enemy_death`, `enemy_attack`, `enemy_spawn`, `pickup`,
  `upgrade_select`
- Music: `music_menu`, `music_calm`, `music_battle`, `music_boss`, `music_victory`

## Per-audio record (template)

| Field | Value |
|---|---|
| Cue id | `player_attack` |
| File | `assets/audio/sfx/…` |
| Source URL / download | _exact_ |
| Creator | _name_ |
| Licence | CC0 / … |
| Attribution | none / text |
| Where used | player attack |
| Date downloaded | YYYY-MM-DD |
| Checksum | sha256 |

Before adding audio: (1) confirm source, (2) asset/name, (3) licence, (4) commercial
use, (5) redistribution in the compiled game, (6) attribution, (7) download URL, (8)
modification rights, (9) compatibility — and store supplied licence files under
`ASSET_LICENSES/`.
