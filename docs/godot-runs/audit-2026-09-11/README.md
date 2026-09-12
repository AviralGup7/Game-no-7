# Audit evidence — 2026-09-11

These are raw logs, not error-filtered success reports. See
[the audit](../../PROJECT_AUDIT.md) for findings and validation limits.

## Reproduction

Use the official **4.4.1-stable** engine and the display/isolated-profile commands
in [BUILD.md](../../BUILD.md). CI uses Compatibility rendering through Xvfb/Mesa.

This sandbox instead compiled the tagged engine source because the release-binary
CDN was inaccessible. It used `platform=linuxbsd target=editor optimize=none`,
with window-system/GPU/audio backends and fontconfig disabled. Diagnostics-only
logging was added to expose GDScript frames when tracing failures. The final
commands did not use `--debug` and did not filter any engine messages.

The native command prefix was:

```bash
source scripts/godot_test_env.sh
godot_test_profile "$PWD/.cache/audit/<separate-profile>"
godot_test_timeout <seconds> <custom-godot> --headless --path "$PWD" ...
```

Each native engine process exited **0**. The custom engine's startup renderer
error (and three dummy-material errors in unit teardown) remain in the logs.
The committed strict checker correctly rejects these logs; that is recorded in
[strict-log-checks.txt](strict-log-checks.txt), not silently waived.
The cold importer additionally reported dummy-preview/fontconfig limitations.

## Files

| Log | Command / purpose |
|---|---|
| [unit.log](unit.log) | `--script res://tests/run_tests.gd` |
| [assets.log](assets.log) | `--script res://tests/validate_asset_imports.gd` |
| [player.log](player.log) | `--script res://tests/run_player_tests.gd` |
| [ui-fresh.log](ui-fresh.log), [ui-existing.log](ui-existing.log) | `res://tests/ui/ui_test_runner.tscn -- --isolated-ui-tests`, same disposable profile run twice |
| [flow.log](flow.log) | `--script res://tests/verify_flow.gd` |
| [loops.log](loops.log) | `--script res://tests/stress_loops.gd` (five loops) |
| [systems.log](systems.log) | `--script res://tests/stress_systems.gd` |
| [soak.log](soak.log) | `--script res://tests/soak_runtime.gd` (six minutes, invulnerable player) |
| [cold-import.log](cold-import.log) | Initial `--import`, before native debugging/fixes; not a clean-import claim |
| [python.log](python.log) | `python3 -m unittest discover -s tests/python -v` |
| [offline-gates.log](offline-gates.log) | Resource, typed architecture, guards, API/path/format/signal and asset checks |

No Android export, real rendering/audio, phone performance or physical-input
result is implied by these logs.
