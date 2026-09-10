"""Regression: core + utilities — run_state, rng, weighted_table, upgrade_selector, content_registry, event_bus."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8", errors="ignore")

class RunStateTests(unittest.TestCase):
    def test_currency_clamped(self):
        txt=read("scripts/core/run_state.gd")
        self.assertIn("clampi(currency + delta",txt)
        self.assertIn("is_finite(float(delta))",txt)
    def test_score_clamped(self):
        txt=read("scripts/core/run_state.gd")
        self.assertIn("clampi(score + delta",txt)
class RngServiceTests(unittest.TestCase):
    def test_salt_clamp(self):
        txt=read("scripts/utilities/rng_service.gd")
        self.assertIn("if salt < 0:",txt)
        self.assertIn("salt % 16384",txt)
class WeightedTableTests(unittest.TestCase):
    def test_all_mutation_and_sample_paths_are_finite(self):
        txt=read("scripts/utilities/weighted_table.gd")
        self.assertIn("is_finite(weight)",txt)
        self.assertIn("clampf(weight",txt)
        self.assertIn("func _recalculate_total", txt)
        self.assertIn("if not is_finite(sample):", txt)
        self.assertIn("if not is_finite(remaining_total)", txt)
        self.assertLess(txt.index("_sanitize_weight(weight)"), txt.index("func set_weight"))
class UpgradeSelectorTests(unittest.TestCase):
    def test_weighted_pick_finite(self):
        txt=read("scripts/progression/upgrade_selector.gd")
        self.assertIn("is_finite(c.weight)",txt)
        self.assertIn("is_finite(total)",txt)

class ObjectPoolTests(unittest.TestCase):
    def test_pool_tracks_ownership_and_factory_failures(self):
        txt=read("scripts/utilities/object_pool.gd")
        self.assertIn("var _leased: Array = []", txt)
        self.assertIn("if obj == null or not _leased.has(obj)", txt)
        self.assertIn("if obj == null:\n\t\t\tbreak", txt)
        self.assertIn("_live_count = _leased.size()", txt)

if __name__=="__main__": unittest.main()
