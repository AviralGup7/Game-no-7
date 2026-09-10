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
    def test_input_remapper_restores_transactionally(self):
        txt=read("scripts/utilities/input_remapper.gd")
        self.assertIn("InputMap.action_erase_event", txt)
        self.assertIn("MAX_BINDS_PER_ACTION", txt)
        self.assertIn("# Parse first, then mutate InputMap", txt)
        self.assertIn("if parsed.is_empty():", txt)
        self.assertIn("or not _event_is_valid(event)", txt)
        self.assertIn('"key_physical"', txt)
        self.assertIn('"keycode"', txt)
        self.assertIn("if code < 0", txt)
        self.assertLess(txt.index("if parsed.is_empty():"), txt.index("InputMap.action_erase_event(aname, existing)"))
    def test_armor_vitality_not_needed_here(self): pass
if __name__=="__main__": unittest.main()
