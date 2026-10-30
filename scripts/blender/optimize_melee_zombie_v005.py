"""800-triangle / 16-bone small zombie revision. Run with Blender --background.

Builds staged dual masters and GLB outside the project before publication.
Originals are read from the dated before_edits backup for repeatability.
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from workspace_paths import work_path

OUT = work_path('sessions/2026-10-30_melee_800/staged/placeholder').parent
BACKUP = ROOT.parent / 'ShellStorm2-backup/2026-10-30_melee_800/before_edits'
SOURCE = Path('art_source/enemies/normal_enemy_3d/melee_chaser/source')
REMOVE = {'L_Hand': 'L_Forearm', 'R_Hand': 'R_Forearm',
          'L_Foot': 'L_Calf', 'R_Foot': 'R_Calf'}
SKEL = 'SKEL-MELEE-ZOMBIE01-004'
CLIPS = {'idle': (96, True), 'walking': (48, True), 'running': (24, True),
         'attack': (51, False), 'hurt': (24, False), 'dead': (72, False)}


def neutral_bind_positions():
    """Bake removed wrists/ankles in their existing idle pose, in binding space.

    Invert the *merged* LBS transform per vertex, rather than dropping animated
    wrist/ankle offsets and allowing the extremities to snap to their T-pose.
    """
    bpy.ops.wm.open_mainfile(filepath=str(BACKUP / SOURCE / 'animation' /
                                        'enm_melee_fungboar01_animation_v004.blend'))
    scene = bpy.context.scene
    rig = next(o for o in scene.objects if o.type == 'ARMATURE')
    mesh = next(o for o in scene.objects if o.type == 'MESH')
    rig.animation_data.action = bpy.data.actions['idle']
    rig.animation_data.action_slot = rig.animation_data.action.slots[0]
    scene.frame_set(1)
    bpy.context.view_layer.update()
    transforms = {b.name: rig.pose.bones[b.name].matrix @ b.matrix_local.inverted()
                  for b in rig.data.bones}
    positions = []
    for v in mesh.data.vertices:
        old = Matrix(((0.,) * 4,) * 4)
        new = Matrix(((0.,) * 4,) * 4)
        for g in v.groups:
            n = mesh.vertex_groups[g.group].name
            old += transforms[n] * g.weight
            new += transforms[REMOVE.get(n, n)] * g.weight
        positions.append(new.inverted() @ (old @ v.co))
    return positions


NEUTRAL_POSITIONS = neutral_bind_positions()


def curves(action):
    return [c for layer in action.layers for strip in layer.strips
            for bag in strip.channelbags for c in bag.fcurves]


def signature(rig):
    rows = [(b.name, b.parent.name if b.parent else None,
             [[round(v, 7) for v in row] for row in b.matrix_local])
            for b in rig.data.bones]
    return hashlib.sha256(json.dumps(rows).encode()).hexdigest()


def digest_mesh(mesh):
    rows = {'v': [[round(x, 7) for x in v.co] for v in mesh.vertices],
            'p': [list(p.vertices) for p in mesh.polygons],
            'uv': [[round(x, 7) for x in u.uv] for u in mesh.uv_layers.active.data]}
    return hashlib.sha256(json.dumps(rows).encode()).hexdigest()


def activate(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def reuse_shared_texture(path):
    """Keep the existing shared PNG instead of creating a new Godot extraction.

    Verify byte identity before removing the embedded copy. Mesh/skin/animation
    bufferView payloads are copied without any numerical conversion.
    """
    raw = path.read_bytes()
    json_length = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + json_length])
    binary = raw[28 + json_length:]
    shared = ROOT / 'assets/art/shared/textures/enemies/tex_color_0fcad02b82d254f23eab.png'
    assert len(doc['images']) == 1
    image = doc['images'][0]
    image_view = image.pop('bufferView')
    view = doc['bufferViews'][image_view]
    assert binary[view['byteOffset']:view['byteOffset'] + view['byteLength']] == shared.read_bytes()
    image.pop('mimeType', None)
    image['uri'] = '../../../../shared/textures/enemies/' + shared.name
    output = bytearray()
    mapping = {}
    views = []
    for i, original in enumerate(doc['bufferViews']):
        if i == image_view:
            continue
        while len(output) % 4:
            output.append(0)
        v = dict(original)
        start = original.get('byteOffset', 0)
        v['byteOffset'] = len(output)
        output.extend(binary[start:start + original['byteLength']])
        mapping[i] = len(views)
        views.append(v)
    for accessor in doc['accessors']:
        assert 'sparse' not in accessor
        if 'bufferView' in accessor:
            accessor['bufferView'] = mapping[accessor['bufferView']]
    doc['bufferViews'] = views
    doc['buffers'][0]['byteLength'] = len(output)
    while len(output) % 4:
        output.append(0)
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    path.write_bytes(struct.pack('<4sII', b'glTF', 2, 28 + len(encoded) + len(output)) +
                     struct.pack('<I4s', len(encoded), b'JSON') + encoded +
                     struct.pack('<I4s', len(output), b'BIN\0') + output)


def build(kind, old_name, new_name):
    bpy.ops.wm.open_mainfile(filepath=str(BACKUP / SOURCE / kind / old_name))
    scene = bpy.context.scene
    rig = next(o for o in scene.objects if o.type == 'ARMATURE')
    mesh = next(o for o in scene.objects if o.type == 'MESH')
    rig.animation_data_clear()
    for p in rig.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for v, position in zip(mesh.data.vertices, NEUTRAL_POSITIONS):
        v.co = position
    # Preserve the same rest-space shape; merge all removed deform influences.
    for src, dst in REMOVE.items():
        source = mesh.vertex_groups[src]
        target = mesh.vertex_groups[dst]
        for v in mesh.data.vertices:
            sw = sum(g.weight for g in v.groups if g.group == source.index)
            tw = sum(g.weight for g in v.groups if g.group == target.index)
            if sw:
                target.add([v.index], sw + tw, 'REPLACE')
        mesh.vertex_groups.remove(source)
    activate(rig)
    bpy.ops.object.mode_set(mode='EDIT')
    for name in REMOVE:
        rig.data.edit_bones.remove(rig.data.edit_bones[name])
    bpy.ops.object.mode_set(mode='OBJECT')
    for a in bpy.data.actions:
        for layer in a.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for c in list(bag.fcurves):
                        if any('"' + name + '"' in c.data_path for name in REMOVE):
                            bag.fcurves.remove(c)
    # Protect recognizable head/hand silhouettes more than broad torso regions.
    protect = mesh.vertex_groups.new(name='QA_DecimateImportance')
    head = mesh.vertex_groups['Head'].index
    forearms = {mesh.vertex_groups[n].index for n in ('L_Forearm', 'R_Forearm')}
    for v in mesh.data.vertices:
        importance = max([g.weight * (0.85 if g.group == head else 0.35)
                          for g in v.groups if g.group == head or g.group in forearms] or [0.0])
        protect.add([v.index], importance, 'REPLACE')
    activate(mesh)
    dec = mesh.modifiers.new('Budget800', 'DECIMATE')
    # Put decimation ahead of armature so it operates on the binding geometry.
    bpy.ops.object.modifier_move_up(modifier=dec.name)
    dec.use_collapse_triangulate = True
    dec.vertex_group = protect.name
    dec.vertex_group_factor = 0.65
    lo, hi = 0.0, 1.0
    best = 0.0
    for _ in range(30):
        dec.ratio = (lo + hi) / 2
        bpy.context.view_layer.update()
        count = dec.face_count
        if count <= 800:
            best = dec.ratio
            lo = dec.ratio
        else:
            hi = dec.ratio
    dec.ratio = best
    bpy.ops.object.modifier_apply(modifier=dec.name)
    mesh.vertex_groups.remove(mesh.vertex_groups['QA_DecimateImportance'])
    # Normalize weights after collapse; omit tiny influences, max four per vertex.
    for v in mesh.data.vertices:
        weights = sorted([(g.group, g.weight) for g in v.groups if g.weight > 1e-7],
                         key=lambda item: -item[1])[:4]
        total = sum(w for _, w in weights)
        assert total > 0, v.index
        for g in mesh.vertex_groups:
            g.remove([v.index])
        for i, w in weights:
            mesh.vertex_groups[i].add([v.index], w / total, 'REPLACE')
    rig['skeleton_id'] = SKEL
    rig['source_status'] = 'authored'
    rig['finger_design'] = 'No finger or hand bones; hands deform with forearms'
    rig['leg_design'] = 'Thigh and calf only; feet deform with calves'
    rig['asset_version'] = 'v005'
    mesh['uv_policy'] = 'Preserved asymmetric UV; 512 basecolor'
    mesh['triangle_budget'] = 800
    scene['asset_version'] = 'v005'
    scene['skeleton_id'] = SKEL
    # The simplified ankle bind is tilted relative to the old T-pose. Put the
    # binding-space soles on Z=0 without shifting any animated world-space pose.
    bind_lift = -min(v.co.z for v in mesh.data.vertices)
    translation = Vector((0, 0, bind_lift))
    hip_local_shift = rig.data.bones['Hip'].matrix_local.to_3x3().inverted() @ translation
    for v in mesh.data.vertices:
        v.co += translation
    activate(rig)
    bpy.ops.object.mode_set(mode='EDIT')
    for b in rig.data.edit_bones:
        if b.name != 'Root':
            b.head += translation
            b.tail += translation
    bpy.ops.object.mode_set(mode='OBJECT')
    for action in bpy.data.actions:
        for c in curves(action):
            if c.data_path == 'pose.bones["Hip"].location':
                for key in c.keyframe_points:
                    for coordinate in (key.co, key.handle_left, key.handle_right):
                        coordinate.y -= hip_local_shift[c.array_index]
    for image in list(bpy.data.images):
        if image.source == 'FILE':
            texture = ROOT / SOURCE / 'model/textures' / Path(image.filepath).name
            if texture.is_file():
                # Fresh image data also removes obsolete packed-file paths from
                # the pre-art_source-migration masters.
                replacement = bpy.data.images.load(str(texture), check_existing=False)
                replacement.colorspace_settings.name = image.colorspace_settings.name
                image.user_remap(replacement)
                name = image.name
                bpy.data.images.remove(image)
                replacement.name = name
                replacement.pack()
                replacement.filepath = ('//textures/' if kind == 'model' else '//../model/textures/') + texture.name
    frames_report = {}
    if kind == 'animation':
        rig.animation_data_create()
        for name, (frames, loop) in CLIPS.items():
            a = bpy.data.actions[name]
            a.use_fake_user = True
            a['clip_id'] = name
            a['duration_seconds'] = frames / 30
            a['loop'] = loop
            a.use_frame_range = True
            a.frame_start = 1
            a.frame_end = 1 + frames
            rig.animation_data.action = a
            rig.animation_data.action_slot = a.slots[0]
            # With ankle articulation deliberately removed, lift only visual Hip
            # as needed. Keep AI/root motion and collision completely unchanged.
            corrections = []
            hip_matrices = []
            for frame in range(1, frames + 2):
                scene.frame_set(frame)
                hip_matrices.append(rig.pose.bones['Hip'].matrix.copy())
                dg = bpy.context.evaluated_depsgraph_get()
                obj = mesh.evaluated_get(dg)
                evaluated = obj.to_mesh()
                floor = min((obj.matrix_world @ v.co).z for v in evaluated.vertices)
                obj.to_mesh_clear()
                corrections.append(max(0.0, 0.0005 - floor))
            # Make the ground compensation continuous through loop seams.
            if loop:
                corrections[-1] = corrections[0] = max(corrections[0], corrections[-1])
            for frame, lift in enumerate(corrections, 1):
                scene.frame_set(frame)
                hip = rig.pose.bones['Hip']
                world = hip_matrices[frame - 1].copy()
                world.translation.z += lift
                hip.matrix = world
                hip.keyframe_insert(data_path='location', frame=frame, group='Hip')
            for c in curves(a):
                if c.data_path == 'pose.bones["Hip"].location':
                    for key in c.keyframe_points:
                        key.interpolation = 'LINEAR'
            # Check rotational interpolation too: a grounded integer pose alone
            # does not guarantee that the shoe stays above ground between keys.
            for _ in range(3):
                extra = [0.0] * (frames + 1)
                for quarter in range(4, (frames + 1) * 4 + 1):
                    f = quarter / 4
                    scene.frame_set(int(f), subframe=f % 1)
                    obj = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
                    evaluated = obj.to_mesh()
                    floor = min((obj.matrix_world @ v.co).z for v in evaluated.vertices)
                    obj.to_mesh_clear()
                    deficit = max(0., 0.0005 - floor)
                    i = min(frames, int(f) - 1)
                    extra[i] = max(extra[i], deficit)
                    if f % 1:
                        extra[min(i + 1, frames)] = max(extra[min(i + 1, frames)], deficit)
                if max(extra) < 0.00001:
                    break
                if loop:
                    extra[0] = extra[-1] = max(extra[0], extra[-1])
                for i in range(frames + 1):
                    corrections[i] += extra[i]
                    scene.frame_set(i + 1)
                    world = hip_matrices[i].copy()
                    world.translation.z += corrections[i]
                    rig.pose.bones['Hip'].matrix = world
                    rig.pose.bones['Hip'].keyframe_insert(data_path='location', frame=i + 1, group='Hip')
            minimum = 1e9
            for quarter in range(4, (frames + 1) * 4 + 1):
                scene.frame_set(quarter // 4, subframe=(quarter % 4) * .25)
                dg = bpy.context.evaluated_depsgraph_get()
                obj = mesh.evaluated_get(dg)
                evaluated = obj.to_mesh()
                minimum = min(minimum, min((obj.matrix_world @ v.co).z for v in evaluated.vertices))
                obj.to_mesh_clear()
            frames_report[name] = {'minimum_z': minimum, 'curves': len(curves(a)),
                                   'maximum_visual_hip_lift_m': max(corrections)}
        rig.animation_data.action = bpy.data.actions['idle']
        rig.animation_data.action_slot = rig.animation_data.action.slots[0]
        scene.frame_start = 1
        scene.frame_end = 96
        scene.frame_set(1)
        scene['clip_id'] = 'idle'
    tri = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
    assert tri == 800, tri
    assert len(rig.data.bones) == 16
    result = {'triangles': tri, 'vertices': len(mesh.data.vertices),
              'bones': [b.name for b in rig.data.bones], 'skeleton_signature': signature(rig),
              'mesh_signature': digest_mesh(mesh.data), 'clips': frames_report,
              'bind_floor_rebase_m': bind_lift,
              'rest_bounds': [[min(v.co[i] for v in mesh.data.vertices),
                               max(v.co[i] for v in mesh.data.vertices)] for i in range(3)]}
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / new_name), relative_remap=False)
    if kind == 'animation':
        activate(rig)
        mesh.select_set(True)
        # Selection has precisely the visual mesh and rig. No preview props exist.
        bpy.ops.export_scene.gltf(filepath=str(OUT / 'enm_melee_fungboar01_visual_top3d.glb'),
                                  export_format='GLB', use_selection=True,
                                  export_animations=True, export_animation_mode='ACTIONS',
                                  export_anim_slide_to_zero=True,
                                  export_frame_range=False, export_force_sampling=True,
                                  export_skins=True, export_morph=False, export_yup=True,
                                  export_cameras=False, export_lights=False)
        reuse_shared_texture(OUT / 'enm_melee_fungboar01_visual_top3d.glb')
    return result


model = build('model', 'enm_melee_fungboar01_model_v003.blend', 'enm_melee_fungboar01_model_v004.blend')
animation = build('animation', 'enm_melee_fungboar01_animation_v004.blend', 'enm_melee_fungboar01_animation_v005.blend')
assert model['mesh_signature'] == animation['mesh_signature']
assert model['skeleton_signature'] == animation['skeleton_signature']
work_path('sessions/2026-10-30_melee_800/source_report.json').write_text(
    json.dumps({'model': model, 'animation': animation}, indent=2), encoding='utf-8')
print('MELEE_800_STAGED_OK', json.dumps(animation))
