"""纯 Python 校验 v004 五件 GLB：结构、材质、几何包围盒、无内嵌贴图。

不依赖 Blender：直接解析 GLB 的 JSON chunk。
"""
from __future__ import annotations

import json
import struct
from pathlib import Path

BATTLE = Path(r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/environments/tower_zones/battle')
CC = BATTLE / 'components' / 'common_components'

TARGETS = {
    'wall_standard_5m': CC / 'wall_standard_5m' / 'wall_standard_5m_visual_top3d_v004.glb',
    'wall_door_5m': CC / 'wall_door_5m' / 'wall_door_5m_visual_top3d_v004.glb',
    'door_5m': CC / 'door_5m' / 'door_5m_visual_top3d_v004.glb',
    'floor_tile_r01_c01': CC / 'floor_tile_5m' / 'floor_tile_r01_c01_visual_top3d_v004.glb',
    'floor_tile_r01_c02': CC / 'floor_tile_5m' / 'floor_tile_r01_c02_visual_top3d_v004.glb',
}


def read_glb(path: Path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', data, 0)
    assert magic == b'glTF', f'{path.name}: 不是 GLB'
    assert version == 2, f'{path.name}: glTF 版本 {version}'
    assert length == len(data), f'{path.name}: 长度字段 {length} != 实际 {len(data)}'
    off = 12
    js = None
    while off < length:
        clen, ctype = struct.unpack_from('<I4s', data, off)
        off += 8
        if ctype == b'JSON':
            js = json.loads(data[off:off + clen].decode('utf8'))
        off += clen
    assert js is not None, f'{path.name}: 缺 JSON chunk'
    return js


def mat4_apply(m, p):
    x, y, z = p
    return [m[0] * x + m[4] * y + m[8] * z + m[12],
            m[1] * x + m[5] * y + m[9] * z + m[13],
            m[2] * x + m[6] * y + m[10] * z + m[14]]


def bounds(js):
    lo = [1e9] * 3
    hi = [-1e9] * 3
    nodes = js.get('nodes', [])
    meshes = js.get('meshes', [])
    accs = js.get('accessors', [])

    def walk(ni, parent):
        n = nodes[ni]
        local = n.get('matrix')
        if local is None:
            t = n.get('translation', [0, 0, 0])
            s = n.get('scale', [1, 1, 1])
            # 只处理平移+等比缩放（本导出不含旋转节点）
            local = [s[0], 0, 0, 0, 0, s[1], 0, 0, 0, 0, s[2], 0, t[0], t[1], t[2], 1]
        world = parent.copy()
        # parent @ local
        w = [0.0] * 16
        for c in range(4):
            for r in range(4):
                w[c * 4 + r] = sum(parent[k * 4 + r] * local[c * 4 + k] for k in range(4))
        if 'mesh' in n:
            for prim in meshes[n['mesh']].get('primitives', []):
                ai = prim['attributes'].get('POSITION')
                if ai is None:
                    continue
                a = accs[ai]
                for corner in _corners(a.get('min'), a.get('max')):
                    p = mat4_apply(w, corner)
                    for i in range(3):
                        lo[i] = min(lo[i], p[i])
                        hi[i] = max(hi[i], p[i])
        for ch in n.get('children', []):
            walk(ch, w)

    def _corners(mn, mx):
        for x in (mn[0], mx[0]):
            for y in (mn[1], mx[1]):
                for z in (mn[2], mx[2]):
                    yield (x, y, z)

    ident = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    for scene in js.get('scenes', []):
        for ni in scene.get('nodes', []):
            walk(ni, ident)
    return lo, hi


ok = True
for slug, path in TARGETS.items():
    if not path.is_file():
        print('MISSING', path)
        ok = False
        continue
    js = read_glb(path)
    lo, hi = bounds(js)
    size = [round(hi[i] - lo[i], 4) for i in range(3)]
    imgs = js.get('images', [])
    mats = js.get('materials', [])
    mesh_names = [m.get('name', '') for m in js.get('meshes', [])]
    print('%-20s glb=%.1f KB  meshes=%2d materials=%d images=%d' %
          (slug, path.stat().st_size / 1024, len(mesh_names), len(mats), len(imgs)))
    print('%-20s godot_aabb lo=%s hi=%s size=%s' % ('', [round(v, 4) for v in lo],
                                                    [round(v, 4) for v in hi], size))
    print('%-20s material_names=%s' % ('', [m.get('name', '') for m in mats]))
    # 断言：底面中心（Godot 坐标 Y 向上，底面 = y min ≈ 0；XZ 居中）
    if abs(lo[1]) > 1e-3:
        print('   FAIL 底面不在 y=0:', lo[1]); ok = False
    if abs((lo[0] + hi[0]) / 2.0) > 1e-3:
        print('   FAIL X 不居中'); ok = False
    if abs((lo[2] + hi[2]) / 2.0) > 0.05:
        print('   FAIL Z 中心漂移过大:', (lo[2] + hi[2]) / 2.0); ok = False
    if imgs:
        print('   FAIL 不应内嵌贴图（走公共色盘）'); ok = False

print()
print('GLB_VERIFY_OK' if ok else 'GLB_VERIFY_FAIL')
