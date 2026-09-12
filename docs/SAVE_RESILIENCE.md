# Save resilience review

## Research basis

The save pipeline was reviewed against the Godot 4 file APIs and mobile lifecycle guidance:

- Godot's [FileAccess documentation](https://docs.godotengine.org/en/4.1/classes/class_fileaccess.html) documents `flush()` as the operation that persists buffered data before a file is closed.
- Godot's [DirAccess documentation](https://docs.godotengine.org/en/4.4/classes/class_diraccess.html) documents same-filesystem `rename_absolute()` and its overwrite behavior. The save commit is a rename, not a write directly to the live file.
- Godot's [quit/lifecycle guidance](https://docs.godotengine.org/en/stable/tutorials/inputs/handling_quit_requests.html) warns that mobile apps can be killed while suspended and specifically recommends saving during `NOTIFICATION_APPLICATION_PAUSED`.
- The Godot project discussion for [syncing files before an atomic replacement](https://github.com/godotengine/godot/pull/98361) explains why explicit flushing is important for valuable user data.
- The general save-system review in [Designing Save Game Systems in Modern Engines](https://pulsegeek.com/articles/designing-save-game-systems-in-modern-engines/) recommends atomic replacement, integrity checks, versioned migrations, rotating backups, and fault simulation.

## What was weak

The previous implementation had a good temporary-file shape, but it had three dangerous gaps:

1. It deleted the live save when rename failed, turning a recoverable storage error into total loss.
2. It kept only one backup and did not detect a valid-looking JSON document whose contents had been changed or truncated in a way that still parsed.
3. It did not explicitly flush the temporary file before the rename commit.

## Implemented contract

- The primary save is written to `*.tmp`, flushed, closed, then committed with same-directory rename.
- A failed commit never deletes the destination and leaves the dirty flag set, so the next lifecycle event can retry.
- A SHA-256 integrity envelope detects accidental or partial post-write corruption. Legacy saves without an envelope remain readable and are upgraded on their next write.
- Three backup generations are retained. Loading tries primary, backup 1, backup 2, and backup 3 in order and reports recovery when an older generation is used.
- The maximum file size guard remains in place before parsing, and schema normalization/migration remains the final boundary before runtime state.
- The existing mobile pause, focus-loss, back-request, close, and exit notifications all force a flush.

## Current schema and malformed-data boundaries

The save schema is **8** (`SaveSchema.SCHEMA_VERSION`); the summary-only run-build
subdocument remains version 1. Migration from older schemas repairs only exact
legacy factory keyboard/controller pairs for pause and skills 1–3. In particular,
Skill 3 moves off reload's R key to F, and controller indices use Godot 4's
Start/shoulder/stick-button constants. Custom maps and unrelated settings are not
replaced. Normalization does not mutate the caller's original dictionary.

Wrong-type booleans/strings, malformed binding records, non-finite numbers and
invalid rank IDs are rejected or defaulted at the boundary. Saved integers are
bounded to JSON's exact double-integer range (±9,007,199,254,740,991), except run
seeds: schema 7 and later store their full nonnegative int64 value as a decimal string and
restores an integer in memory. Already-rounded legacy numeric seeds cannot have
their lost bits recovered. A non-string
integrity digest is corruption, not a castable value. Invalid JSON is parsed via
an instance `JSON.parse()` so recovery does not itself emit an engine error.
Write/flush errors are checked before commit. Nested JSON merges deep-copy the
override rather than sharing mutable containers with the caller.

Regression suites: `tests/unit/test_audit_boundaries.gd` and
`tests/unit/test_audit_runtime.gd`. Device-level power-loss/durability testing still
requires the checklist below; no headless test can prove a filesystem's power-loss
behavior.

## Campaign checkpoint subdocument (schema 8)

The additive `campaign` block contains a fixed world ID, named checkpoint,
completed mission cursor, defeated/interacted/visited IDs, XP, upgrades and the
weapon/skill loadout. Old profiles start with an unstarted campaign; settings,
banked credits, permanent ranks and legacy results are not cleared. Continue
reconciles identifiers/cursor against the authored objective ledger and restores
XP without replaying level-up boons or stacking permanent bonuses twice.

Campaign interactions record their claimed IDs and advanced objective cursor
before staging the resulting build and wallet. The existing atomic save writes
that whole profile, not a separate reward file. Kill rewards use the debounce;
objectives, caches, checkpoints, pause/death and leaving flush immediately. A
failed New Campaign write restores the previous campaign in memory. Returning
to a checkpoint resets health/stamina/cooldowns, not completed objectives or kills.

New coverage is in `tests/unit/test_campaign.gd` and the isolated
`tests/verify_campaign.gd` harness. These campaign-native additions have not been
executed in the current workspace; power-loss guarantees still require device QA.

## Checksum round-trip compatibility

Native execution found that hashing an in-memory dictionary and re-hashing its
parsed JSON does not always yield the same bytes: integers become floats and
default decimal formatting can change fractional elapsed times. New writes use
full-precision JSON-domain hashing. Verification tries that representation and
compatible legacy representations, including the **exact original payload
text**, removing only the root integrity member with a quote/nesting-aware scan.
The raw-text candidate must parse to the same document being verified; it is not
a way to authenticate a different or modified document. Every accepted envelope
still has to match its stored SHA-256.

Regressions cover fresh/existing-profile disk verification, fractional run
clocks, daily seeds above 2^53, nested/escaped member-like text, legacy digests,
and tampering. This repairs false corruption reports without treating genuine
checksum mismatches as valid saves.

## Limits and deliberate trade-offs

Godot's portable GDScript API does not expose a cross-platform directory `fsync` barrier. `FileAccess.flush()` is therefore the strongest engine-level durability boundary available without a native Android plugin. The system favors preserving an older save over deleting it when the filesystem refuses a replacement. SHA-256 is an integrity check, not anti-cheat protection; an attacker who can edit the document can also edit its digest. This is appropriate for this offline single-player game.

## Manual fault-test checklist for a Godot/Android QA device

1. Save, force-stop during a save, relaunch, and verify primary or a backup loads.
2. Truncate primary JSON and verify backup recovery is announced.
3. Change one character in primary and verify the integrity check rejects it.
4. Fill storage or revoke write access, verify the old primary remains and save failure is surfaced.
5. Background the app immediately after unlocking an achievement, force-stop it, and verify the achievement survives after relaunch.
