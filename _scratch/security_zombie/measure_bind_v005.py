import bpy, json
from pathlib import Path
from mathutils import Vector
P = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
CASES = {
    'MELEE_MODEL': P/'assets/art/enemies/normal_enemy_3d/melee_chaser/source/model/enm_melee_fungboar01_model_v002.blend',
    'POLICE_V005': P/'assets/art/enemies/normal_enemy_3d/ranged_caster/source/model/enm_ranged_sporeshooter01_model_v005.blend',
}
for label, path in CASES.items():
    bpy.ops.wm.open_mainfile(filepath=str(path))
    sc = bpy.context.scene
    arm = next(o for o in sc.objects if o.type == 'ARMATURE')
    meshes = [o for o in sc.objects if o.type == 'MESH']
    dg = bpy.context.evaluated_depsgraph_get()
    out = {'armature': arm.name, 'arm_obj_scale': [round(v, 5) for v in arm.scale],
           'bones': len(arm.data.bones)}
    # bone world extents
    zs, xs, ys = [], [], []
    for b in arm.data.bones:
        for v in (b.head_local, b.tail_local):
            w = arm.matrix_world @ v
            xs.append(w.x); ys.append(w.y); zs.append(w.z)
    out['armature_world_bbox'] = [round(max(xs)-min(xs), 4), round(max(ys)-min(ys), 4), round(max(zs)-min(zs), 4)]
    out['armature_z_range'] = [round(min(zs), 4), round(max(zs), 4)]
    info = []
    for m in meshes:
        ev = m.evaluated_get(dg)
        ws = [m.matrix_world @ Vector(c) for c in ev.bound_box]
        mb = [max(p[i] for p in ws) - min(p[i] for p in ws) for i in range(3)]
        info.append({'name': m.name, 'obj_scale': [round(v, 5) for v in m.scale],
                     'world_bbox': [round(v, 4) for v in mb],
                     'z_range': [round(min(p[2] for p in ws), 4), round(max(p[2] for p in ws), 4)],
                     'modifiers': [(md.type, getattr(md, 'object', None).name if getattr(md, 'object', None) else None) for md in m.modifiers],
                     'parent': (m.parent.name if m.parent else None),
                     'vgroups': len(m.vertex_groups)})
    out['meshes'] = info
    print('==== %s ====' % label)
    print(json.dumps(out, ensure_ascii=False, indent=2))
