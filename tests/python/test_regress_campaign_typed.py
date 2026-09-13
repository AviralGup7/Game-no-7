"""Shipping campaign typed-boundary regressions."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = json.loads((ROOT / "data/campaign/station_zero.json").read_text())

RECORDS = {
    "CampaignSector": ("campaign_sector.gd", set().union(*(r.keys() for r in DATA["sectors"]))),
    "CampaignProp": ("campaign_prop.gd", set().union(*(r.keys() for r in DATA["props"]))),
    "CampaignInteraction": ("campaign_interaction.gd", set().union(*(r.keys() for r in DATA["interactions"]))),
    "CampaignEncounter": ("campaign_encounter.gd", set().union(*(r.keys() for r in DATA["encounters"]))),
    "CampaignMember": ("campaign_member.gd", set().union(*(m.keys() for r in DATA["encounters"] for m in r["members"]))),
    "CampaignMission": ("campaign_mission.gd", set().union(*(r.keys() for r in DATA["missions"]))),
    "CampaignReward": ("campaign_reward.gd", set().union(*(r["reward"].keys() for r in DATA["missions"]))),
}

class CampaignTypedBoundary(unittest.TestCase):
    def test_record_fields_exactly_cover_authored_json(self):
        for class_name, (filename, expected) in RECORDS.items():
            text = (ROOT / "scripts/campaign" / filename).read_text()
            self.assertIn(f"class_name {class_name}", text)
            actual = set(re.findall(r"^var\s+(\w+)\s*:", text, re.M))
            self.assertEqual(expected, actual, class_name)
            documented = set(re.findall(r"JSON key:\s*(\w+)\.", text))
            self.assertEqual(expected, documented, class_name)

    def test_only_definition_loader_reads_campaign_json(self):
        hits = []
        for path in (ROOT / "scripts/campaign").glob("*.gd"):
            text = path.read_text()
            if "JsonHelpers.load_dict" in text or "JSON.parse" in text or "parse_string" in text:
                hits.append(path.name)
        self.assertEqual(["campaign_definition.gd"], hits)

    def test_encounters_never_mutate_director_progress(self):
        text = (ROOT / "scripts/campaign/campaign_encounters.gd").read_text()
        self.assertNotIn("CampaignProgressState", text)
        self.assertNotRegex(text, r"progress\s*\.\s*(defeated|interacted|visited)\s*\.")
        self.assertIn("member_defeated.emit(id, credits)", text)
        director = (ROOT / "scripts/campaign/campaign_director.gd").read_text()
        self.assertIn("progress.defeated.append(id)", director)

    def test_definition_exposes_typed_graph(self):
        text = (ROOT / "scripts/campaign/campaign_definition.gd").read_text()
        for type_name, field in [("CampaignSector", "sectors"), ("CampaignProp", "props"),
                                 ("CampaignEncounter", "encounters"), ("CampaignInteraction", "interactions"),
                                 ("CampaignMission", "missions")]:
            self.assertIn(f"var {field}: Array[{type_name}]", text)
        # The extent cap is single-sourced in CampaignBudgets; the definition
        # aliases it (pinned by tests/python/test_campaign_budgets.py).
        self.assertIn("WORLD_EXTENT_LIMIT := CampaignBudgets.WORLD_EXTENT_LIMIT", text)
        budgets = (ROOT / "scripts/campaign/campaign_budgets.gd").read_text()
        self.assertEqual(1024.0, float(re.search(r"const WORLD_EXTENT_LIMIT := ([0-9.]+)", budgets).group(1)))

if __name__ == "__main__":
    unittest.main()
