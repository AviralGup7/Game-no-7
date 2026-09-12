# Skill 04: AI Agent Productivity Tricks & Pitfalls in Game-no-7

A fast reference guide of lessons, patterns, and time-saving techniques for agents working on this repository.

---

## 1. Git & Remote Rebase Conflicts with Binary Assets
- **Issue**: Concurrent pushes or rebase operations can report conflicts on binary files (`.glb`, `.png`, `.bin`).
- **Resolution**:
  ```bash
  # Accept the locally built assets during rebase:
  git checkout --theirs data/ docs/HARDENING.md
  git add data/ docs/HARDENING.md
  GIT_EDITOR=true git rebase --continue
  ```
- **Rule**: Never run `git push --force`. Always pull with `--rebase`, resolve conflicts cleanly, and verify all validation gates pass before pushing.

---

## 2. Python Environment & Dependency Constraints
- **Constraint**: The Python shell environment does not guarantee global `numpy` or `trimesh`.
- **Solution**: Always author scripts using pure Python standard library (`struct`, `json`, `math`, `pathlib`, `subprocess`).
- **C Helper Binaries**: When heavy computation or fast image processing is needed, write a single-file C utility and compile it with `gcc -O3 script.c -o script -lm` (executes in < 50ms).

---

## 3. The `validate_resources.py` & `HARDENING.md` Count Contract
- When authoring new `.tscn` (scenes) or `.tres` (resources), the total validated file count changes.
- `tests/python/test_regress_run_modes.py::DocCountTests` checks `docs/HARDENING.md` against `validate_resources.py`.
- **Quick Fix**: Check the total validated file count with `python3 tool/validate_resources.py` and update `Validated files: X/X` in `docs/HARDENING.md`.

---

## 4. Godot 4.x Scene & Resource Authoring
- **`load_steps`**: `load_steps` in `.tscn` and `.tres` must equal the total number of `[ext_resource]` + `[sub_resource]` tags + 1.
- **Resource Names**: Never leave `resource_name` mismatched or referencing nonexistent IDs.
- **Collision Shapes**: Place `CollisionShape3D` nodes inside `StaticBody3D` (World Geometry on `collision_layer = 1`, `collision_mask = 0`).

---

## 5. Three.js Review Previews for Live Inspection
- The project provides live web previews (`tool/wall_preview.html`, `tool/hero_preview.html`, `tool/hd_preview.html`).
- Start the server using:
  ```bash
  python3 tool/serve_art.py --port 8000
  ```
- `tool/serve_art.py` is configured to allow `assets/`, `tool/`, and `data/` endpoints, allowing interactive 3D model inspection in real time.
