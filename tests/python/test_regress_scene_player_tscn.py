"""Regression: player.tscn load_steps — 26 after ember_scepter/moonlance/venom_chain integration (was 25 with 6 weapons)."""
from __future__ import annotations
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class PlayerSceneTests(unittest.TestCase):
    def test_player_tscn_load_steps_is_26(self):
        txt=read("scenes/player/player.tscn")
        first=txt.splitlines()[0] if txt else ""
        m=re.search(r"load_steps=(\d+)",first)
        self.assertIsNotNone(m)
        self.assertEqual(int(m.group(1)),26)
        ext=len(re.findall(r"\[ext_resource",txt))
        sub=len(re.findall(r"\[sub_resource",txt))
        self.assertEqual(ext+sub+1,26)
if __name__=="__main__": unittest.main()
