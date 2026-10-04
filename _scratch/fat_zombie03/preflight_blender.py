import bpy, json, hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[2]
pkg = root / 'assets/art/enemies/normal_enemy_3d/fat_zombie03'
transfer = json.loads((pkg / 'runtime/character_transfer_ledger.json').read_text(encoding='utf-8'))
out = root / 'outputs/fat_zombie03_integration'
out.mkdir(parents=True, exist_ok=True)
report = {'files': [], 'sources': {}, 'errors': []}
for entry in transfer['files']:
    f = root / entry['path']
    ok = f.exists() and hashlib.sha256(f.read_bytes()).hexdigest() == entry['sha256']
    report['files'].append({'path': entry['path'], 'hash_matches': ok})
    if not ok: report['errors'].append('Hash mismatch: ' + entry['path'])

for field in ['model_source', 'animation_source']:
    bpy.ops.wm.open_mainfile(filepath=str(root / transfer[field]))
    scene = bpy.context.scene
    rig = next(o for o in scene.objects if o.type == 'ARMATURE')
    mesh = next(o for o in scene.objects if o.type == 'MESH')
    signature = hashlib.sha256(json.dumps([(b.name, b.parent.name if b.parent else None,
        [round(x, 6) for row in b.matrix_local for x in row]) for b in rig.data.bones]).encode()).hexdigest()
    data = {'signature': signature, 'bones': len(rig.data.bones),
        'vertices': len(mesh.data.vertices), 'triangles': sum(len(p.vertices)-2 for p in mesh.data.polygons),
        'materials': len(mesh.data.materials), 'object_scales': [list(rig.scale), list(mesh.scale)],
        'images': [{'name': im.name, 'size': list(im.size)} for im in bpy.data.images if im.has_data and im.users],
        'shape_keys': list(mesh.data.shape_keys.key_blocks.keys()), 'clips': {}}
    if signature != transfer['skeleton_signature']: report['errors'].append(field + ' skeleton mismatch')
    if len(rig.data.bones) != 66: report['errors'].append(field + ' bone count')
    if any(abs(v-1)>1e-6 for o in [rig,mesh] for v in o.scale): report['errors'].append(field+' scale')
    if field == 'animation_source':
        keys = mesh.data.shape_keys
        shape_action = keys.animation_data.action if keys.animation_data else None
        for planned in transfer['planned_clips']:
            name = planned['name']
            rig.animation_data.action = bpy.data.actions[name]
            if keys.animation_data: keys.animation_data.action = shape_action if name == 'dead' else None
            if name != 'dead': keys.key_blocks['BellyGroundCompression'].value = 0
            min_z = 100
            root_error = 0
            scale_error = 0
            bounds = None
            start_pose = None
            end_pose = None
            for k in range(planned['last_frame'] * 2 + 1):
                f = k / 2
                scene.frame_set(int(f), subframe=f%1)
                bpy.context.view_layer.update()
                ev = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
                me = ev.to_mesh()
                min_z = min(min_z, min(v.co.z for v in me.vertices)*.7)
                if k == 0:
                    bounds = [[min(v.co[i] for v in me.vertices)*.7, max(v.co[i] for v in me.vertices)*.7] for i in range(3)]
                ev.to_mesh_clear()
                root_error = max(root_error, max(abs(rig.pose.bones['Root'].matrix_basis[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4)))
                scale_error = max(scale_error, max(abs(v-1) for b in rig.pose.bones for v in b.scale))
                pose = [x for b in rig.pose.bones for row in b.matrix for x in row]
                if k == 0: start_pose = pose
                end_pose = pose
            seam = max(abs(x-y) for x,y in zip(start_pose,end_pose))
            data['clips'][name] = {'min_z_m': min_z, 'root_error': root_error, 'bone_scale_error': scale_error,
                'first_frame_bounds_m': bounds, 'endpoint_error': seam, 'samples': planned['last_frame']*2+1}
            if root_error>1e-6 or scale_error>1e-6 or min_z<-.005: report['errors'].append(name+' source pose/ground')
            if planned['loop'] and seam>1e-5: report['errors'].append(name+' loop seam')
    report['sources'][field] = data

report['passed'] = not report['errors']
(out / 'preflight_blender.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('FAT_ZOMBIE03_PREFLIGHT_' + ('OK' if report['passed'] else 'FAILED'), json.dumps(report['errors']), flush=True)
