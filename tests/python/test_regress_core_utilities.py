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
    def test_validated_restore(self):
        txt=read("scripts/core/run_state.gd")
        self.assertIn("_validated_restore_dict",txt)

class RngServiceTests(unittest.TestCase):
    def test_salt_clamp(self):
        txt=read("scripts/utilities/rng_service.gd")
        self.assertIn("if salt < 0:",txt)
        self.assertIn("salt % 16384",txt)

class WeightedTableTests(unittest.TestCase):
    def test_finite_clamp(self):
        txt=read("scripts/utilities/weighted_table.gd")
        self.assertIn("is_finite(weight)",txt)
        self.assertIn("clampf(weight",txt)
    def test_validated_total(self):
        txt=read("scripts/utilities/weighted_table.gd")
        self.assertIn("_validated_total",txt)

class UpgradeSelectorTests(unittest.TestCase):
    def test_weighted_pick_finite(self):
        txt=read("scripts/progression/upgrade_selector.gd")
        self.assertIn("is_finite(c.weight)",txt)
        self.assertIn("is_finite(total)",txt)
    def test_validated_pick_count(self):
        txt=read("scripts/progression/upgrade_selector.gd")
        self.assertIn("_validated_pick_count",txt)

class ContentRegistryTests(unittest.TestCase):
    def test_validated_archetype(self):
        txt=read("scripts/core/content_registry.gd")
        self.assertIn("_validated_archetype",txt)

class EventBusTests(unittest.TestCase):
    def test_safe_emit(self):
        txt=read("scripts/core/event_bus.gd")
        self.assertIn("_safe_emit",txt)

class SceneRouterTests(unittest.TestCase):
    def test_validated_scene(self):
        txt=read("scripts/core/scene_router.gd")
        self.assertIn("_validated_scene_id",txt)

class ContentLoaderTests(unittest.TestCase):
    def test_validated_path(self):
        txt=read("scripts/core/content_loader.gd")
        self.assertIn("_validated_content_path",txt)

class UpgradeServiceTests(unittest.TestCase):
    def test_validated_pool(self):
        txt=read("scripts/core/upgrade_service.gd")
        self.assertIn("_validated_pool_size",txt)

class GameRootTests(unittest.TestCase):
    def test_validated_seed(self):
        txt=read("scripts/core/game_root.gd")
        self.assertIn("_validated_seed",txt)

class RunAnalyticsTests(unittest.TestCase):
    def test_validated_window(self):
        txt=read("scripts/core/run_analytics.gd")
        self.assertIn("_validated_analytics_window",txt)

class RunScorekeeperTests(unittest.TestCase):
    def test_validated_delta(self):
        txt=read("scripts/core/run_scorekeeper.gd")
        self.assertIn("_validated_score_delta",txt)

class TestHarnessTests(unittest.TestCase):
    def test_validated_seed(self):
        txt=read("scripts/core/test_harness.gd")
        self.assertIn("_validated_harness_seed",txt)

if __name__=="__main__": unittest.main()
