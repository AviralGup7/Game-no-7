"""Regression: player.tscn load_steps — 27 after the legacy AttackController node
was removed (was 28 with it; 26 after the fallback Body capsule + material and
ember_scepter/moonlance/venom_chain integration)."""
from __future__ import annotations
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class PlayerSceneTests(unittest.TestCase):
    def test_player_tscn_load_steps_is_27(self):
        txt=read("scenes/player/player.tscn")
        first=txt.splitlines()[0] if txt else ""
        m=re.search(r"load_steps=(\d+)",first)
        self.assertIsNotNone(m)
        self.assertEqual(int(m.group(1)),27)
        ext=len(re.findall(r"\[ext_resource",txt))
        sub=len(re.findall(r"\[sub_resource",txt))
        self.assertEqual(ext+sub+1,27)
    def test_player_tscn_has_fallback_body(self):
        txt=read("scenes/player/player.tscn")
        self.assertIn('[node name="Body" type="MeshInstance3D" parent="VisualRoot/CharacterModel"]',txt)
    def test_player_tscn_body_has_mesh_subresource(self):
        # The fallback Body must actually render: mesh wired to a CapsuleMesh sub-resource.
        txt=read("scenes/player/player.tscn")
        self.assertIn('CapsuleMesh',txt)
        self.assertRegex(txt,r'mesh\s*=\s*SubResource\("[^"]+"\)')
if __name__=="__main__": unittest.main()
