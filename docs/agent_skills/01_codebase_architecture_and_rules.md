# Skill 01: Codebase Architecture, Typing Rules & Hardening Gates

This module defines the architectural invariants, strict GDScript rules, and automated validation gates required when working on the `Game-no-7` codebase.

---

## 1. Architectural Philosophy: Typed & Data-Driven
- **No Duck Typing**: Duck typing (`has_method("...")`, `.call("...")`, unchecked `node.get(...)`) is strictly banned by `tool/check_typed_arch.py` and `tool/validate_guards.py`.
- **Hard-Typed Boundaries**: All functions declare explicit return types (`-> void`, `-> bool`, `-> Vector3`, etc.). Every variable, parameter, and array must be statically typed (e.g. `Array[StringName]`, `Dictionary[StringName, StatusEffect]`).
- **Data-Driven Definitions**: Content (weapons, enemies, skills, upgrades, arenas, mutators) is defined via Godot Resource files (`.tres`) extending `ValidatedConfig` subclasses under `data/`, loaded dynamically by `ContentRegistry` and validated at load time.

---

## 2. Inlined Hardening & Runtime Guard Invariants
The codebase adheres to systematic hardening invariants checked by `tool/validate_guards.py`:

1. **Finite Physics & Numbers**:
   - Every float entering physics, locomotion, steering, or damage must be checked with `is_finite()` and clamped with `clampf()` or `clampi()`.
   - Never allow `NaN` or `INF` to enter `global_position`, `velocity`, `scale`, or camera transforms.
2. **Safe Entity Lifetimes**:
   - All signal emissions and pooled callbacks must check `is_instance_valid(target)`.
   - All time scale modifications (`Engine.time_scale`) must be restored on `_exit_tree()`.
3. **Bounded Collections**:
   - Object pools (`ProjectilePool`, `EffectPool`, `PickupManager`) must clamp capacity with `clampi(size, 1, MAX)` to prevent out-of-memory errors on mobile targets.
4. **No Dictionary State Channels**:
   - Game state across boundaries must pass through typed records (e.g. `WaveModifiers`, `DamagePayload`, `CombatResult`), never untyped Dictionary keys.

---

## 3. Hermetic Static Analysis Gates (Must Pass Before Push)

Run the gate suite whenever making changes:
```bash
python3 tool/validate_resources.py && \
python3 tool/validate_assets.py && \
python3 tool/validate_guards.py && \
python3 tool/check_typed_arch.py && \
python3 tool/check_engine_api.py && \
python3 tool/check_scene_paths.py && \
python3 tool/check_string_formats.py && \
python3 tool/check_signals.py
```

### Gate Responsibilities:
- **`validate_resources.py`**: Validates `load_steps`, `ext_resource` existence, and scene integrity across all 170+ scenes and resources.
- **`validate_assets.py`**: Verifies PNG signatures/IHDR chunks, glTF 2.0 binary buffers, Ogg Vorbis audio containers, and checksum locks.
- **`validate_guards.py`**: Asserts 201+ inlined runtime guards and guarantees legacy validation wrappers remain absent.
- **`check_typed_arch.py`**: Enforces strict typing, verifies project classes, and flags unsafe dynamic property lookups.
- **`check_engine_api.py`**: Validates all typed accesses against the Godot 4.4.1 ClassDB manifest (`tool/godot_api_manifest.json`).
- **`check_scene_paths.py`**: Statically resolves all `get_node()` strings against `.tscn` node hierarchies.
- **`check_string_formats.py`**: Validates `%` string formatting syntax, arities, and types against engine `String::sprintf` rules.
- **`check_signals.py`**: Statically checks signal definitions, argument counts, and connected callable arities.

---

## 4. Test Suite Execution
- **Python Regression Suite (1050+ tests)**:
  ```bash
  python3 -m unittest discover -s tests/python -p "test_*.py"
  ```
- **Document Count Synchronization**:
  When adding or removing `.tscn` or `.tres` files, update the count in `docs/HARDENING.md` line 223 and line 319 (`Validated files: N/N`) to ensure `DocCountTests` in `test_regress_run_modes.py` remains green.
