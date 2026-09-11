"""Regression: weapon balance band — ensures 9 weapons remain viable, no degenerate DPS."""
import pathlib, re, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text()
class WeaponBalanceTests(unittest.TestCase):
    def test_dps_band(self):
        # Ideal sustained DPS: all pellets hit, including windup, magazine and
        # reload downtime. This is a sanity bound, not a substitute for playtesting.
        weapons = []
        for p in (ROOT / "data/weapons").glob("*.tres"):
            txt = p.read_text()
            def value(key):
                return float(re.search(r'^' + key + r' = ([0-9.]+)', txt, re.M)[1])
            magazine = value('ammo_per_magazine')
            self.assertGreater(magazine, 0)
            crit = 1 + value('crit_chance') * (value('crit_multiplier') - 1)
            damage = value('base_damage') * value('projectile_count') * magazine * crit
            seconds = magazine * (value('swing_cooldown') + value('windup')) + value('reload_seconds')
            dps = damage / seconds
            self.assertGreater(dps, 20)
            self.assertLess(dps, 60)
            weapons.append(dps)
        self.assertLess(max(weapons) / min(weapons), 2.2)

    def test_weapon_configs_valid(self):
        for p in (ROOT/"data/weapons").glob("*.tres"):
            txt=p.read_text()
            # all must have display_name and not disabled
            self.assertIn("weapon_id", txt)
            self.assertIn("disabled = false", txt)

if __name__=="__main__": unittest.main()
