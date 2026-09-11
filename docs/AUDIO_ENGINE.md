# Audio playback engine v2 — contract honored, clicks gone, layers real

Date: 2026-09-10 · Files: `scripts/audio/audio_manager.gd`,
`scripts/audio/music_manager.gd`, `scripts/audio/audio_config.gd`,
`scripts/audio/sfx_policy.gd` (new), `tests/unit/test_audio_policy.gd`,
`tests/python/test_regress_audio_engine.py`, `tests/run_tests.gd`.

## What the audit found (v1)

The audio subsystem shipped a **data-driven schema the playback engine never
read**:

1. **Dead contract.** `AudioConfig` declared per-cue `max_voices` (voice
   limit), `cooldown` ("spam guard"), per-play `volume_var_db` / `pitch_var`
   randomization, `bus` routing, `loop`, and `music_layer` ("for adaptive
   mixing"). None of it was consumed: `play_sfx` routed everything to one
   hard-coded bus, used a single global 16-voice cap, never rolled volume or
   pitch, and MusicManager never read `music_layer`. `RngService.STREAM_AUDIO`
   (701) existed but was unused — the intent was obvious, the wiring absent.
2. **Clicks and pops.** Every SFX voice started at full volume in sample 0
   (onset click), and a stolen/recycled voice was hard `stop()`ed mid-tail —
   a step function, which is exactly the broadband pop that audio research
   warns about.
3. **No per-cue voice discipline.** One hot cue (footsteps, shots) could
   retrigger every frame and monopolize all 16 global voices; steal policy was
   global-oldest rather than per-cue.
4. **Phantom "UI" bus.** `AudioConfig.VALID_BUSES` listed `"UI"`; the bus was
   never created and never routed to, so menu clicks mixed into combat SFX.
5. **Dead parallel music path.** `AudioManager` carried its own
   `_music_player` with `play_music` / `stop_music` — a hard switch, no
   crossfade, **zero callers** (MusicManager is the only music driver).
6. **Fake "4-layer intensity mixer".** MusicManager's layers were a
   ±4.5 dB volume nudge on a single bed. Real stems were unsupported; the
   `music_layer` config field was dead.

## Research (three web passes, 2026-09-10)

- **Voice management (FMOD/Wwise semantics).** Per-event *max instances*;
  *stealing policies* where "Oldest — stop the instance that started the
  longest time ago. Useful for very frequent events"; *cooldown* as "minimum
  time between instances … a nice safety net" against spam; and the
  practitioner consensus that the most efficient limiter is **code-side rules
  in the engine**, not DSP-side tricks.
- **Click/pop prevention.** Abrupt stop = multiplication by a step = energy
  at all frequencies = audible pop; the fix is a fade-out over **~30 ms**
  with a **1−t²** shape ("still sounds like an abrupt stop, but there will be
  no audible pop"), plus a few-ms fade-in on clip starts.
- **Adaptive music layering (vertical remixing).** Stems composed to work in
  any combination, faded by game intensity; layer volume may be continuous;
  the standard transition rule from a Godot 4 layered-music implementation:
  **asymmetric timing — "tension should snap up fast and release slowly"** —
  plus a **minimum dwell** that suppresses transition re-evaluation during
  state flicker ("dwell time ended up being more impactful than phrase
  alignment"), and phase-syncing newly joined stems to the playing bed.

## Design (v2)

### SfxPolicy (new, pure, headless)

`SfxPolicy` is the per-cue voice governor: `try_play(cue, now)` returns
`REJECT` (inside the cooldown window — suppression stays silent so the guard
cannot move the spam into the report channel), `FRESH`, or `STEAL` with the
**oldest** active voice token of that cue. The engine reports
`voice_started` / `voice_ended` so occupancy stays accurate. Deterministic
for identical input sequences (unit-pinned).

### AudioManager (SFX path rebuilt)

- `register_cue(cue_id, stream, config = null)` — explicit configs override
  the built-in `AudioConfig.for_cue()` table (hand-tuned spam guards for
  footsteps/shots/hits, cap-1 for one-shot feedback, UI-bus routing for menu
  cues; generic cues stay variance-free because multi-variant streams already
  carry their own ±3 dB randomization).
- `play_sfx` now: config lookup → policy decision → per-play volume/pitch
  roll → claim. Claims: idle player (immediate) → per-cue steal (policy's
  oldest) → global oldest at the 16-voice ceiling (v1 fallback).
- **Click-safe lifecycle:** every start ramps 0→target over 12 ms; a steal
  whose victim still has audio in the air gets a 30 ms **1−t²** fade-out and
  the new play rides a **pending-claim queue** that fires when the fade
  completes — no path hard-cuts a live voice.
- Bus routing from config, including the now-real **"UI" bus** (created in
  `_ensure_buses`, previewable in settings).
- Dead parallel music path removed — MusicManager is the only music owner.
- Preserved pins: `_sfx_pool` / `_cues` (soak + stress scripts iterate them),
  `get_cue_stream`, `is_background_muted`, ducking, background mute,
  `MAX_SFX_VOICES`, `play_sfx` signature.

### MusicManager (real vertical layering)

- State bed keeps v1's pop-free A/B crossfade (outgoing-volume capture
  included). Above it, **two stem players** carry intensity layers using the
  cue convention `music_<bed>_l2` / `music_<bed>_l3` (stems are named after
  the *resolved* bed, so arena-override beds get their own stem family).
  **No stems registered → single-bed behavior, i.e. v1** (graceful).
- Intensity: heat → layer 0..3 (boss always peaks; battle maps heat across
  1..3). Stem levels are a pure function of the layer; fades are
  **asymmetric** (up 0.6 s / down 2.0 s) and downward moves hold for a
  **0.4 s dwell** — heat flicker during rapid hits cannot machine-gun the
  stems, but real lulls release promptly and rises are immediate.
- **Phase sync**: a stem joining mid-track seeks to the active bed's
  playback position so layered loops stay in step (best-effort).
- **No hard cuts**: a stem whose stream changes fades the old audio out,
  swaps at the fade end, and fades the new stream in (the swap rides a
  pending slot; a state flicker back cancels the stale swap).
- Pure decisions are static: `target_layer_for`, `stem_targets`,
  `stem_fade_seconds` — unit-tested headlessly.
- Preserved API: `request_state`, `get_state/get_heat/get_layer`,
  `begin_tracking`, `add_heat`, `get_debug_snapshot`,
  `music_state_changed`, bed crossfade + heat hysteresis constants.

## Testing

- `tests/unit/test_audio_policy.gd` (registered in `tests/run_tests.gd`):
  SfxPolicy (cooldown window, per-cue cap, oldest-steal, slot release,
  cooldown-outranks-cap, cue isolation, default cap, determinism),
  `AudioConfig.for_cue` (tuned contracts, generic default, all validate
  clean), MusicManager layering (layer mapping, monotone stem levels,
  asymmetry, dwell > 0, boss hottest).
- `tests/python/test_regress_audio_engine.py`: shape guards — policy wired
  into `play_sfx` (silent rejects), click-safe constants + 1−t² shape,
  fade-protected stealing (per-cue then global), UI bus, config-overrides
  seam, dead music path removed, fake volume-nudge layer removed, stem
  convention + asymmetry + dwell + phase sync + pending swap, v1 API and
  soak/stress seams preserved.

Honest caveat: the Godot runtime suite still only executes in CI (no binary
in this sandbox); everything above is verified via gdparse/gdlint + the 541-
test Python gate + desk simulation of the unit-suite math and the fade/
pending state machine.

## v3 — bus isolation, spatial Foley, mix snapshots (2026-09-11)

v2 left three presentation holes:

1. **Shared 2D pool.** UI and combat SFX still claimed the same 16
   `AudioStreamPlayer`s. A full combat bed could steal a menu click (the UI
   *bus* existed; the *voice* did not).
2. **No world position.** Enemy hits/deaths/dashes played at listener volume
   regardless of distance.
3. **No pause duck for Foley.** Pause muted nothing on the SFX bus, so world
   hits kept playing under the overlay. MusicManager already owned the bed.

What landed (without reopening the v2 playback engine):

- **UI VoiceBank** (4 voices, token base 100, bus always `UI`). `play_sfx`
  routes `cfg.bus == UI` here; skill/wave/boss cues stay on the 16-voice SFX
  pool. Soak/stress still iterate `_sfx_pool`.
- **SpatialVoicePool** of 16 `AudioStreamPlayer3D` (token base 200, SFX bus).
  `play_sfx_at` / `play_sfx_on` cull via `SpatialAttenuation` *before* a
  voice is claimed, then follow the emitter. `EnemyAudio` uses `play_sfx_on`.
  UI and music cues refuse spatialization.
- **MixSnapshot** offsets on top of SettingsData. Pause ducks SFX −14 dB and
  leaves UI at 0. Music offset is always 0 — MusicManager remains the only
  music owner. Listener is an `AudioListener3D` child of AudioManager,
  snapped to the active player (`GameRoot.set_active_player` →
  `bind_listener`); the player scene is not modified.
- **Procedural stems** `music_battle_l2/l3`, `music_boss_l2/l3`,
  `music_calm_l2` so the v2 stem mixer has something to fade when no
  recorded stem is registered.
- **EnemyAnimator** private clip libraries (no shared `loop_mode` mutation),
  one-shot lock until `animation_finished`, directional dash via
  `HeroRigContract`, stun/cast/telegraph/dash/spawn keys.

Pins: `tests/unit/test_spatial_audio.gd`,
`tests/python/test_regress_audio_spatial.py`,
`tests/python/test_regress_enemy_animator.py`. v2 pins unchanged.
