"""Regression: guardrails — export presets, catalog, vitality typo."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class GuardRailsTests(unittest.TestCase):
    def test_no_vitality_tome_typo_anywhere(self):
        bad=[]
        for p in ROOT.rglob("*.gd"):
            txt=p.read_text(errors="ignore")
            if '&"vitality Tome"' in txt:
                bad.append(str(p.relative_to(ROOT)))
            if p.name!="meta_progression.gd" and "vitality Tome" in txt:
                bad.append(str(p.relative_to(ROOT)))
        self.assertEqual(bad,[])
        self.assertIn('StringName("vitality Tome")',read("scripts/meta/meta_progression.gd"))
    def test_export_presets_still_no_permissions(self):
        cfg=read("export_presets.cfg")
        offending=[ln for ln in cfg.splitlines() if ln.startswith("permissions/")]
        self.assertEqual(offending,[])
    def test_catalog_uses_resource_ids(self):
        txt=read("tool/validate_assets.py")
        self.assertIn("content_ids",txt)
if __name__=="__main__": unittest.main()
