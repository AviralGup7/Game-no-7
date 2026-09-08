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
        self.assertIn("int(round(float(v)))",txt)
        self.assertIn("func _string_int_map",txt)
        self.assertIn("maxi(int(round(float(v))), 0)",txt)
if __name__=="__main__": unittest.main()
