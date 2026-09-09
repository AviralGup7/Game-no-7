"""Regression: waves — planner, manager, director, config."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8",errors="ignore")

class WavePlannerTests(unittest.TestCase):
    def test_generate_wave_clamps(self):
        txt=read("scripts/waves/wave_planner.gd")
        self.assertIn("maxi(wave_number, 1)",txt)

class DifficultyDirectorTests(unittest.TestCase):
    def test_prune_finite(self):
        txt=read("scripts/waves/difficulty_director.gd")
        self.assertIn("is_finite(_now)",txt)
        self.assertIn("is_finite(float(t0))",txt)

class WaveConfigTests(unittest.TestCase):
    def test_validated_counts(self):
        txt=read("scripts/waves/wave_config.gd")
        # Authored ranges are enforced by @export_range + validate().
        self.assertIn("@export_range(1, 60) var maximum_simultaneous_enemies",txt)
        self.assertIn("func validate() -> Array[String]:",txt)

class PickupManagerTests(unittest.TestCase):
    def test_pool_size_clamped(self):
        txt=read("scripts/pickups/pickup_manager.gd")
        self.assertIn("clampi(pool_size",txt)

if __name__=="__main__": unittest.main()
