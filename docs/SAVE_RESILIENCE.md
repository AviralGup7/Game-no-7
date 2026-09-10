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

## Limits and deliberate trade-offs

Godot's portable GDScript API does not expose a cross-platform directory `fsync` barrier. `FileAccess.flush()` is therefore the strongest engine-level durability boundary available without a native Android plugin. The system favors preserving an older save over deleting it when the filesystem refuses a replacement. SHA-256 is an integrity check, not anti-cheat protection; an attacker who can edit the document can also edit its digest. This is appropriate for this offline single-player game.

## Manual fault-test checklist for a Godot/Android QA device

1. Save, force-stop during a save, relaunch, and verify primary or a backup loads.
2. Truncate primary JSON and verify backup recovery is announced.
3. Change one character in primary and verify the integrity check rejects it.
4. Fill storage or revoke write access, verify the old primary remains and save failure is surfaced.
5. Background the app immediately after unlocking an achievement, force-stop it, and verify the achievement survives after relaunch.
