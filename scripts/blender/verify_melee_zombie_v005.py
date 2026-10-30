"""Reopen both optimized masters and validate skinning at quarter frames."""
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from workspace_paths import work_path

SOURCE = ROOT / 'art_source/enemies/normal_enemy_3d/melee_chaser/source'
EXPECTED = {'Root', 'Hip', 'Waist', 'Spine02', 'Neck', 'Head',
            'L_Clavicle', 'L_Upperarm', 'L_Forearm',
            'R_Clavicle', 'R_Upperarm', 'R_Forearm',
            'L_Thigh', 'L_Calf', 'R_Thigh', 'R_Calf'}
CLIPS = {'idle': (96, True), 'walking': (48, True), 'running': (24, True),
         'attack': (51, False), 'hurt': (24, False), 'dead': (72, False)}


def skeleton_signature(rig):
    rows = [(b.name, b.parent.name if b.parent else None,
             [[round(v, 7) for v in row] for row in b.matrix_local]) for b in rig.data.bones]
    return hashlib.sha256(json.dumps(rows).encode()).hexdigest()


report = {}
for kind, filename in [('model', 'enm_melee_fungboar01_model_v004.blend'),
                       ('animation', 'enm_melee_fungboar01_animation_v005.blend')]:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE / kind / filename))
    scene = bpy.context.scene
    assert len(bpy.data.objects) == 2, 'Visual rig + mesh only'
    rig = next(o for o in scene.objects if o.type == 'ARMATURE')
    mesh = next(o for o in scene.objects if o.type == 'MESH')
    assert set(b.name for b in rig.data.bones) == EXPECTED
    assert rig['skeleton_id'] == 'SKEL-MELEE-ZOMBIE01-004'
    assert all(abs(v - 1) < 1e-6 for o in (rig, mesh) for v in o.scale)
    assert sum(len(p.vertices) - 2 for p in mesh.data.polygons) == 800
    assert set(g.name for g in mesh.vertex_groups) == EXPECTED
    assert len(mesh.data.uv_layers) > 0
    for v in mesh.data.vertices:
        assert 0 < len(v.groups) <= 4
        assert abs(sum(g.weight for g in v.groups) - 1) < 1e-5
        assert all(math.isfinite(x) for x in v.co)
    images = []
    for material in mesh.data.materials:
        for node in material.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and node.image:
                image = node.image
                assert image.packed_file and tuple(image.size) == (512, 512)
                assert Path(bpy.path.abspath(image.filepath)).is_file()
                images.append({'name': image.name, 'size': list(image.size), 'packed': True})
    assert images
    entry = {'skeleton_signature': skeleton_signature(rig), 'images': images, 'clips': {}}
    if kind == 'animation':
        assert set(a.name for a in bpy.data.actions) == set(CLIPS)
        for name, (frames, loop) in CLIPS.items():
            action = bpy.data.actions[name]
            assert abs(action.frame_range[1] - action.frame_range[0] - frames) < 1e-5
            assert action['loop'] == loop
            curves = [c for l in action.layers for s in l.strips for bag in s.channelbags for c in bag.fcurves]
            assert all(any('"' + bone + '"' in c.data_path for bone in EXPECTED) for c in curves)
            rig.animation_data.action = action
            rig.animation_data.action_slot = action.slots[0]
            poses = []
            floor = 1e9
            max_height = 0
            for quarter in range(4, 4 * (frames + 1) + 1):
                scene.frame_set(quarter // 4, subframe=quarter % 4 / 4)
                for p in rig.pose.bones:
                    assert max(abs(s - 1) for s in p.scale) < 1e-5
                assert rig.pose.bones['Root'].matrix_basis.translation.length < 1e-6
                obj = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
                evaluated = obj.to_mesh()
                points = [obj.matrix_world @ v.co for v in evaluated.vertices]
                assert all(math.isfinite(x) for p in points for x in p)
                floor = min(floor, min(p.z for p in points))
                max_height = max(max_height, max(p.z for p in points))
                if quarter == 4:
                    entry.setdefault('pose_bounds', {})[name] = [
                        [min(p[i] for p in points), max(p[i] for p in points)] for i in range(3)]
                obj.to_mesh_clear()
                if quarter in (4, 4 * (frames + 1)):
                    poses.append({p.name: p.matrix.copy() for p in rig.pose.bones})
            assert floor >= -0.00001, (name, floor)
            seam = max(abs(poses[0][n][i][j] - poses[1][n][i][j])
                       for n in EXPECTED for i in range(4) for j in range(4))
            if loop:
                assert seam < 0.0001, (name, seam)
            entry['clips'][name] = {'minimum_z': floor, 'maximum_z': max_height,
                                    'loop_seam_matrix_error': seam if loop else None,
                                    'quarter_frame_samples': frames * 4 + 1}
    report[kind] = entry
assert report['model']['skeleton_signature'] == report['animation']['skeleton_signature']
glb = ROOT / 'assets/art/enemies/normal_enemy_3d/melee_chaser/components/enm_melee_fungboar01_visual_top3d.glb'
raw = glb.read_bytes()
size = struct.unpack_from('<I', raw, 12)[0]
doc = json.loads(raw[20:20 + size])
assert len(doc['meshes']) == len(doc['skins']) == 1
assert not doc.get('cameras') and not doc.get('lights')
assert len(doc['skins'][0]['joints']) == 16
assert set(a['name'] for a in doc['animations']) == set(CLIPS)
accessors = doc['accessors']
assert sum(accessors[p['indices']]['count'] // 3 for m in doc['meshes'] for p in m['primitives']) == 800
for action in doc['animations']:
    duration = max(accessors[s['input']]['max'][0] for s in action['samplers'])
    assert abs(duration - CLIPS[action['name']][0] / 30) < 1e-5
report['glb'] = {'triangles': 800, 'bones': 16, 'clips': 6, 'sha256': hashlib.sha256(raw).hexdigest()}
work_path('sessions/2026-10-30_melee_800/reopen.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('MELEE_800_REOPEN_OK samples=1266 triangles=800 bones=16 clips=6')
