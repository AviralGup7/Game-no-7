"""Regression: HealthComponent emit & InputRemapper clear — guards Batch1 fixes."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class HealthInputTests(unittest.TestCase):
    def test_health_component_emits_on_max_change(self):
        txt=read("scripts/player/health_component.gd")
        self.assertIn("func set_max_health",txt)
        self.assertIn("health_changed.emit(current_health, max_health)",txt)
        self.assertIn("not is_equal_approx(max_health, new_max)",txt)
    def test_input_remapper_clears_before_restore(self):
        txt=read("scripts/utilities/input_remapper.gd")
        self.assertIn("InputMap.action_erase_event",txt)
        self.assertIn("MAX_BINDS_PER_ACTION",txt)
        self.assertIn("# Clear existing remappable bindings before restoring",txt)
    def test_armor_vitality_not_needed_here(self): pass
if __name__=="__main__": unittest.main()
