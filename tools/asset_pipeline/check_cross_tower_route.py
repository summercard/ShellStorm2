"""Check the accepted native route without generating or replacing its layout."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
folder = ROOT / 'assets/art/environments/open_world/runtime/cross_tower_route'
scene = folder / 'env_cross_tower_route_root_top3d.tscn'
text = scene.read_text(encoding='utf8')
report = json.loads((folder / 'acceptance.json').read_text(encoding='utf8'))
assert not report['failures'] and report['checks'] >= 308
assert report['renderer'] != 'headless', 'requires an actual renderer'
assert report['scene_sha256'] == hashlib.sha256(scene.read_bytes()).hexdigest(), 'stale runtime acceptance'
assert not re.search(r'type="(?:[^"]*Material|MultiMeshInstance3D)"', text)
assert 'minimap' not in text.lower()
assert 'metadata/north_bridge_opening_x = 20.0' in text
assert 'metadata/asset_version = "v002"' in text
assert text.count('instance=ExtResource("jib")') == 4
assert 'Girder_' not in text and 'Deck_' not in text
assert 'scale =' not in text
for path in re.findall(r'path="res://([^"]+)"', text):
    assert (ROOT / path).is_file(), path
assert 'CrossTowerRoute' in (ROOT / 'scenes/TowerDescent3D.tscn').read_text(encoding='utf8')
print('CROSS_TOWER_ROUTE_CHECK_OK', report['checks'], 'physics/render checks; zero new material resources')
