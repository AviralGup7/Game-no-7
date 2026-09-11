#!/usr/bin/env python3
"""Bake tiny shared station panels and missing structural props. No runtime generation.
Run with the optional Pillow authoring dependency from tool/hero/requirements.txt.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[1]

def build():
    target = ROOT / 'assets/environment/space_station'
    image = Image.new('RGB', (64, 64), '#7d8995')
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 63, 63), outline='#253341', width=2)
    draw.line((3, 3, 60, 3), fill='#bbc6d0')
    draw.line((3, 3, 3, 60), fill='#bbc6d0')
    for x in (6, 57):
        for y in (6, 57):
            draw.rectangle((x, y, x+1, y+1), fill='#354454')
    image.save(target / 'panel.png', optimize=True)
    # Geometry exactly fills the existing 1.4 x 4 x 1.4 structural collider.
    (target / 'support.tscn').write_text('''[gd_scene load_steps=5 format=3]

[sub_resource type="StandardMaterial3D" id="Metal"]
albedo_color = Color(0.25, 0.32, 0.4, 1)
metallic = 0.65
roughness = 0.65

[sub_resource type="StandardMaterial3D" id="Light"]
albedo_color = Color(0.15, 0.8, 1, 1)
emission_enabled = true
emission = Color(0.05, 0.55, 0.9, 1)
emission_energy_multiplier = 1.5

[sub_resource type="BoxMesh" id="Body"]
size = Vector3(1.4, 4, 1.4)
material = SubResource("Metal")

[sub_resource type="BoxMesh" id="Strip"]
size = Vector3(0.09, 3.3, 1.42)
material = SubResource("Light")

[node name="StationSupport" type="Node3D"]
[node name="Body" type="MeshInstance3D" parent="."]
position = Vector3(0, 2, 0)
mesh = SubResource("Body")
[node name="Strip" type="MeshInstance3D" parent="."]
position = Vector3(0, 2, 0)
mesh = SubResource("Strip")
''')
    for name, color, metal, rough in [
        ('arena_floor_rock', '0.48, 0.55, 0.63', .55, .8),
        ('arena_wall_brick', '0.65, 0.72, 0.8', .45, .7),
        ('arena_wall_stone', '0.5, 0.6, 0.7', .5, .7),
        ('arena_stone', '0.5, 0.6, 0.7', .5, .7),
        ('arena_marble', '0.72, 0.8, 0.9', .6, .55),
        ('arena_wood', '0.3, 0.4, 0.5', .65, .65),
        ('arena_metal', '0.48, 0.58, 0.68', .7, .5),
    ]:
        # Retain resource paths so scene links and gameplay tinting stay compatible.
        (ROOT / f'assets/materials/{name}.tres').write_text(f'''[gd_resource type="StandardMaterial3D" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://assets/environment/space_station/panel.png" id="1_panel"]

[resource]
resource_name = "Station modular panel"
albedo_color = Color({color}, 1)
albedo_texture = ExtResource("1_panel")
metallic = {metal}
roughness = {rough}
uv1_triplanar = true
uv1_world_triplanar = true
uv1_scale = Vector3(0.5, 0.5, 0.5)
texture_filter = 3
''')
    files = []
    for name in ('panel.png', 'support.tscn'):
        path = target / name
        files.append({'path': str(path.relative_to(ROOT)), 'bytes': path.stat().st_size,
                      'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    recipe = ROOT / 'tool/build_scifi_environment.py'
    (target / 'build_report.json').write_text(json.dumps({
        'schema_version': 1, 'recipe': 'station_environment_v1',
        'recipe_sha256': hashlib.sha256(recipe.read_bytes()).hexdigest(),
        'files': files}, indent=2) + '\n')
    print('Baked shared 64x64 panel and collider-matched station support.')

if __name__ == '__main__':
    build()
