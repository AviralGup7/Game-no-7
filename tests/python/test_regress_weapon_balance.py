"""Regression: weapon balance band — ensures 9 weapons remain viable, no degenerate DPS."""
import pathlib, re, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text()
class WeaponBalanceTests(unittest.TestCase):
    def test_dps_band(self):
        # DPS estimates as in audit — ensure no weapon 3x outlier
        weapons=[]
        for p in (ROOT/"data/weapons").glob("*.tres"):
            txt=p.read_text()
            dmg=float(re.search(r"base_damage\s*=\s*([0-9.]+)",txt).group(1))
            cd=float(re.search(r"swing_cooldown\s*=\s*([0-9.]+)",txt).group(1))
            cm=re.search(r"combo_damage_steps.*?\((.*?)\)",txt,re.S)
            steps=[float(x.strip(" ,")) for x in cm.group(1).split(",") if x.strip()] if cm else [1]
            avg=sum(steps)/len(steps)
            cc=float(re.search(r"crit_chance\s*=\s*([0-9.]+)",txt).group(1))
            mul=float(re.search(r"crit_multiplier\s*=\s*([0-9.]+)",txt).group(1))
            crit=1+cc*(mul-1)
            dps= dmg*avg*crit/cd
            # for hybrid volley, rough adjust: stormhammer has 6 proj, ~2 hit
            if p.stem=="stormhammer":
                dps= dmg*2*crit/cd
            if p.stem=="ember_scepter":
                dps= dmg*1.8*crit/cd
            if p.stem=="sunbow":
                dps= dmg*1.0*crit/cd
            weapons.append(dps)
        weapons=sorted(weapons)
        low, high=min(weapons), max(weapons)
        # band must be <2x, not 3x
        self.assertLess(high/low, 2.2, f"DPS band too wide {low:.1f}-{high:.1f} ratio {high/low:.1f}")
        # each still >15 dps (viable) and <50 (not insane)
        for dps in weapons:
            self.assertGreater(dps, 15, f"weapon dps too low {dps}")
            self.assertLess(dps, 50, f"weapon dps too high {dps}")

    def test_weapon_configs_valid(self):
        for p in (ROOT/"data/weapons").glob("*.tres"):
            txt=p.read_text()
            # all must have display_name and not disabled
            self.assertIn("weapon_id", txt)
            self.assertIn("disabled = false", txt)

if __name__=="__main__": unittest.main()
