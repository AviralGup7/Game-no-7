"""Regression: combat hardening — area_damage, critical, hitstop, payload/result, weapons."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8", errors="ignore")

class AreaDamageTests(unittest.TestCase):
    def test_validated_radial(self):
        txt=read("scripts/combat/area_damage.gd")
        self.assertIn("_validated_radial_args",txt)
        self.assertIn("is_finite(radius)",txt)
        self.assertIn("is_finite(damage)",txt)
        self.assertIn("is_instance_valid(v)",txt)
    def test_tie_deterministic_still(self):
        txt=read("scripts/combat/area_damage.gd")
        self.assertIn("Strict < keeps candidate order stable",txt)

class HitstopTests(unittest.TestCase):
    def test_validated_hitstop(self):
        txt=read("scripts/combat/hitstop_manager.gd")
        self.assertIn("_validated_hitstop",txt)
        self.assertIn("clampf(duration",txt)

class DamagePayloadTests(unittest.TestCase):
    def test_validated_amount(self):
        txt=read("scripts/combat/damage_payload.gd")
        self.assertIn("_validated_amount",txt)
        self.assertIn("is_safely_valid",txt)
        self.assertIn("is_finite(a)",txt)
    def test_deep_duplicate(self):
        txt=read("scripts/combat/damage_payload.gd")
        self.assertIn("metadata.duplicate(true)",txt)

class DamageResultTests(unittest.TestCase):
    def test_validated_final(self):
        txt=read("scripts/combat/damage_result.gd")
        self.assertIn("_validated_final",txt)

class CriticalTests(unittest.TestCase):
    def test_finite_and_validated(self):
        txt=read("scripts/combat/critical_system.gd")
        self.assertIn("is_finite(base_chance)",txt)
        self.assertIn("is_instance_valid(rng)",txt)
        self.assertIn("_validated_crit_chance",txt)

class WeaponConfigTests(unittest.TestCase):
    def test_validated_stats(self):
        txt=read("scripts/weapons/weapon_config.gd")
        self.assertIn("_validated_weapon_stats",txt)
        self.assertIn("clampf(damage",txt)

class MeleeResolverTests(unittest.TestCase):
    def test_validated_melee(self):
        txt=read("scripts/weapons/melee_resolver.gd")
        self.assertIn("_validated_melee",txt)
        self.assertIn("is_finite(damage)",txt)

class RangedResolverTests(unittest.TestCase):
    def test_validated_launch(self):
        txt=read("scripts/weapons/ranged_resolver.gd")
        self.assertIn("_validated_ranged_launch",txt)

class ProjectileTests(unittest.TestCase):
    def test_finite_delta_and_validated(self):
        txt=read("scripts/weapons/projectile.gd")
        self.assertIn("is_finite(delta)",txt)
        self.assertIn("is_instance_valid(self)",txt)
        self.assertIn("_validated_launch_dict",txt)

class WeaponManagerTests(unittest.TestCase):
    def test_validated_weapon_id(self):
        txt=read("scripts/weapons/weapon_manager.gd")
        self.assertIn("_validated_weapon_id",txt)
        self.assertIn("has_method(\"get_weapon\")",txt)

class CombatLogTests(unittest.TestCase):
    def test_validated_log(self):
        txt=read("scripts/combat/combat_log.gd")
        self.assertIn("_validated_log_entry",txt)

class CombatQueryTests(unittest.TestCase):
    def test_validated_radius(self):
        txt=read("scripts/combat/combat_query.gd")
        self.assertIn("_validated_query_radius",txt)

if __name__=="__main__": unittest.main()
