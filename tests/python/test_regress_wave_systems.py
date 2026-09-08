"""Regression: waves — planner, manager, director, config, mutators, spawn."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8",errors="ignore")

class WavePlannerTests(unittest.TestCase):
    def test_generate_wave_clamps(self):
        txt=read("scripts/waves/wave_planner.gd")
        self.assertIn("maxi(wave_number, 1)",txt)
    def test_validated_archetype_count(self):
        txt=read("scripts/waves/wave_planner.gd")
        self.assertIn("_validated_archetype_count",txt)

class WaveManagerTests(unittest.TestCase):
    def test_guards_elapsed(self):
        txt=read("scripts/waves/wave_manager.gd")
        self.assertIn("\"elapsed_seconds\" in run",txt)
    def test_validated_wave_number(self):
        txt=read("scripts/waves/wave_manager.gd")
        self.assertIn("_validated_wave_number",txt)

class DifficultyDirectorTests(unittest.TestCase):
    def test_prune_finite(self):
        txt=read("scripts/waves/difficulty_director.gd")
        self.assertIn("is_finite(_now)",txt)
        self.assertIn("is_finite(float(t0))",txt)
    def test_validated_factor(self):
        txt=read("scripts/waves/difficulty_director.gd")
        self.assertIn("_validated_director_factor",txt)

class WaveConfigTests(unittest.TestCase):
    def test_validated_counts(self):
        txt=read("scripts/waves/wave_config.gd")
        self.assertIn("_validated_counts",txt)
        self.assertIn("clampi(enemy_count",txt)

class WaveMutatorsTests(unittest.TestCase):
    def test_validated_weight(self):
        txt=read("scripts/waves/wave_mutators.gd")
        self.assertIn("_validated_mutator_weight",txt)

class SpawnLedgerLikeTests(unittest.TestCase):
    def test_drop_table_clamped(self):
        txt=read("scripts/pickups/drop_table.gd")
        self.assertIn("_validated_drop_chance",txt)
    def test_pickup_validated(self):
        txt=read("scripts/pickups/pickup.gd")
        self.assertIn("_validated_value",txt)

class PickupManagerTests(unittest.TestCase):
    def test_validated_drop(self):
        txt=read("scripts/pickups/pickup_manager.gd")
        self.assertIn("_validated_drop_pos",txt)
        self.assertIn("clampi(pool_size",txt)

if __name__=="__main__": unittest.main()
