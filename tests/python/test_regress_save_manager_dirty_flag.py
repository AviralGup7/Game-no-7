"""Regression: SaveManager dirty flag + SaveSchema rounding — guards Batch1 & Batch3 persistence fixes."""
from __future__ import annotations
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class SaveManagerTests(unittest.TestCase):
    def test_dirty_flag_only_on_success(self):
        txt=read("scripts/save/save_manager.gd")
        self.assertIn("if ok:",txt)
        self.assertIn("\tif ok:\n\t\t_dirty = false",txt)
        self.assertNotIn("_write_raw(SAVE_PATH, JSON.stringify(_save))\n\t_dirty = false\n\tif ok:",txt)
    def test_save_schema_int_rounding(self):
        txt=read("scripts/save/save_schema.gd")
        self.assertIn("_int_or(roundf(float(v)), 0)",txt)
        self.assertIn("func _string_int_map",txt)
        self.assertIn("maxi(_int_or(roundf(float(v)), 0), 0)",txt)

    def test_save_commit_is_non_destructive_and_durable(self):
        txt=read("scripts/save/save_manager.gd")
        self.assertIn("file.flush()", txt)
        self.assertIn("file.get_error()", txt)
        self.assertIn("Three backup generations", read("docs/SAVE_RESILIENCE.md"))
        self.assertIn("HashingContext.HASH_SHA256", txt)
        # A rename failure must not remove the last known-good destination.
        commit = txt[txt.index("func _write_raw"):]
        self.assertNotIn("remove_absolute(ProjectSettings.globalize_path(path))", commit)
        self.assertIn("BACKUP_3_PATH", txt)

    def test_integrity_is_verified_before_normalization(self):
        txt=read("scripts/save/save_manager.gd")
        self.assertLess(txt.index("raw = _read_raw(candidate)"), txt.index("validate_save_data(raw)"))
        self.assertIn("if parsed.has(INTEGRITY_KEY) and not _integrity_valid(parsed, text)", txt)
        self.assertIn('"algorithm": "sha256"', txt)

    def test_backup_rotation_skips_missing_generations(self):
        txt=read("scripts/save/save_manager.gd")
        self.assertIn("func _copy_save_file(", txt)
        self.assertIn('if text.is_empty() or text == "null":', txt)
        self.assertNotIn("JSON.stringify(_read_raw(BACKUP_2_PATH))", txt)

    def test_run_build_seed_key_is_seed(self):
        txt=read("scripts/save/save_schema.gd")
        self.assertIn('out.seed = _seed_or(seed_raw)', txt)
        self.assertNotIn("out.run_seed =", txt)

if __name__=="__main__": unittest.main()
