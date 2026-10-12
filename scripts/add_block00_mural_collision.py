"""第四间门厅壁画补碰撞（用户反馈：98F 第四间的壁画没有阻挡）。

壁画在 2026-10-09 反馈轮里从"悬挂"改成"向后倾 22°、侧倾 6°、斜靠地面"，
但它当时被归入无交互装饰，`collision_policy = visual_only`，玩家可以直接穿过画板。
本脚本只把 Godot 稳定 Prefab 的碰撞补上并回写导入清单；Blender 源、GLB、
布局场景（lobby_facilities.tscn）与实例姿态一律不动。

碰撞盒取组件局部包围盒（10.3 × 6.28 × 0.37 m），与 `assemble_block00_facilities.py`
对 solid 组件用的是同一套公式，因此盒体随实例 transform 一起倾斜，
底面恰为实测最低网格点 0.091m，不穿地、不与房间壳体重叠。
"""
from pathlib import Path
import hashlib
import json
import re

R = Path(__file__).resolve().parents[1]
M = R / 'art_source/environments/master_office_3d/source/env_block00_story_rooms/export/v001/import_manifest.json'
O = R / 'outputs/block00_mural_collision_20261012'
O.mkdir(parents=True, exist_ok=True)

SLUG = 'constructivist_mural'
manifest = json.loads(M.read_text('utf8'))
d = next(x for x in manifest['components'] if x['slug'] == SLUG)
prefab = R / d['prefab_path']
text = prefab.read_text('utf8')

# ---- 1. Prefab 侧：确认碰撞已就位，且盒体与清单包围盒严格一致 --------------
assert 'metadata/collision_policy = "fitted_box"' in text, 'Prefab 碰撞策略未更新'
assert '[node name="Collision" type="StaticBody3D" parent="."]' in text, 'Prefab 缺 Collision 节点'
assert 'shape = SubResource("Box")' in text, 'Prefab 缺 CollisionShape3D'
a, b = d['bounds_min'], d['bounds_max']
size = [b[i] - a[i] for i in range(3)]
box = [size[0], size[2], size[1]]
pos = [(a[0] + b[0]) / 2, (a[2] + b[2]) / 2, -(a[1] + b[1]) / 2]
for value in box + pos:
    assert f'{value + 0.0:.7f}' in text, f'Prefab 盒参数与清单包围盒不一致: {value + 0.0:.7f}'
sha_prefab = hashlib.sha256(prefab.read_bytes()).hexdigest()

# ---- 2. 清单侧：只改 mural 条目内的两个值，其余逐字节保持 -------------------
old_policy, old_sha = d['collision_policy'], d['prefab_sha256']
assert old_policy == 'visual_only' and old_sha != sha_prefab, '清单已是目标状态，勿重跑'
raw = M.read_text('utf8')
start = raw.index(f'"slug": "{SLUG}"')
end = raw.index('\n  }', start) + len('\n  }')
segment = raw[start:end]
segment, n_policy = re.subn(r'("collision_policy": ")visual_only(")', r'\1fitted_box\2', segment)
segment, n_sha = re.subn(r'("prefab_sha256": ")[0-9a-f]{64}(")', lambda m: m.group(1) + sha_prefab + m.group(2), segment)
assert n_policy == 1 and n_sha == 1, (n_policy, n_sha)
M.write_text(raw[:start] + segment + raw[end:], encoding='utf8')

# ---- 3. 证据 ---------------------------------------------------------------
(O / 'delta.json').write_text(json.dumps({
    'asset_id': d['asset_id'],
    'prefab_path': d['prefab_path'],
    'collision_policy': [old_policy, 'fitted_box'],
    'prefab_sha256': [old_sha, sha_prefab],
    'box_size_m': box,
    'box_center_local_m': pos,
    'source_formula': 'assemble_block00_facilities.py solid-box formula (bounds_min/max -> Godot local)',
    'blender_source_unchanged': True,
    'glb_unchanged': True,
    'lobby_layout_unchanged': True,
}, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
print('MURAL_COLLISION_ADDED', d['asset_id'], 'policy', old_policy, '->', 'fitted_box')
print('box', box, 'center', pos, 'sha', sha_prefab[:16])
