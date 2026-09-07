# Audio Manifest — Licences & Provenance

Every externally sourced audio asset is logged here with its licence. Policy mirrors
`THIRD_PARTY_ASSETS.md`: only clearly licensed (preferably CC0/public-domain) audio
is accepted; no ripped or copyrighted tracks.

## Current state

No third-party audio is committed yet. The `AudioManager` autoload gracefully no-ops
for any cue that has no registered stream, so the game is fully playable silent while
audio is still being sourced. Audio is added as streams registered by the
`ContentRegistry` from `res://data/audio/` and referenced by stable cue ids such as:

- `player_attack`, `player_hurt`, `player_dodge`, `player_death`
- `enemy_hit`, `enemy_death`
- `upgrade_select`, `pickup`, `wave_started`, `game_over`
- `arena_menu` (music), `arena_gameplay` (music)

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
