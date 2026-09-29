"""Export the v022 seated action and the complete motion library from its Blender source."""
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_character_bundle import signature

ROOT = Path(__file__).resolve().parents[2]
OLD = ROOT / 'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v021'
VERSION = Path(bpy.data.filepath).resolve().parents[2].name
assert VERSION in {'v022', 'v023', 'v024'}, VERSION
PACKAGE = OLD.parent / VERSION
SOURCE = PACKAGE / f'source/animation/chr_bunny01_animation_{VERSION}.blend'
OUTPUT = PACKAGE / 'exports'
OUTPUT.mkdir(parents=True, exist_ok=True)
assert Path(bpy.data.filepath).resolve() == SOURCE.resolve(), bpy.data.filepath

scene = next(scene for scene in bpy.data.scenes if scene.get('preview_clip') == 'seated')
bpy.context.window.scene = scene
rig = next(obj for obj in scene.objects if obj.type == 'ARMATURE')
expected = json.loads((OLD / 'character_transfer_ledger_v021.json').read_text())['skeleton_sha256']
assert signature(rig) == expected, 'Skeleton rest changed'
component_rest = {name: Matrix(value) for name, value in json.loads(scene['runtime_component_rest']).items()}
axis = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
clips = {}
for action in list(bpy.data.actions):
    if 'state_id' not in action:
        continue
    rig.animation_data.action = action
    frames = []
    first, last = map(int, action.frame_range)
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        globals_by_name = {}
        for name, rest in component_rest.items():
            source_name = 'chest' if name == 'body' else name
            globals_by_name[name] = (
                rig.pose.bones[source_name].matrix
                @ rig.data.bones[source_name].matrix_local.inverted()
                @ rest
                if source_name in rig.pose.bones else rest
            )
        matrices = {
            name: (
                globals_by_name['head'].inverted() @ matrix if name.startswith('ear_')
                else globals_by_name['root'].inverted() @ matrix if name not in ('root', 'feet')
                else matrix
            )
            for name, matrix in globals_by_name.items()
        }
        values = {}
        for name, matrix in matrices.items():
            translation, rotation, scaling = (axis @ matrix @ axis.inverted()).decompose()
            values[name] = {
                'p': list(translation),
                'q': [rotation.x, rotation.y, rotation.z, rotation.w],
                's': list(scaling),
            }
        frames.append(values)
    state_id = str(action['state_id'])
    assert state_id not in clips, f'duplicate clip: {state_id}'
    clips[state_id] = {'duration': float(action['duration']), 'loop': bool(action['loop']), 'frames': frames}

expected_clips = set(json.loads((OLD / 'exports/anim_bunny01_library_v021.json').read_text())['clips']) | {'seated'}
if VERSION == 'v024':
    expected_clips.add('climbing')
assert set(clips) == expected_clips
assert clips['seated']['loop'] and len(clips['seated']['frames']) == 73
if VERSION == 'v024':
    # Blender retains unkeyed pose channels across Action switches; keep the
    # proven v023 runtime samples byte-for-byte and add only the new clip.
    previous = json.loads((OLD.parent / 'v023/exports/anim_bunny01_library_v023.json').read_text())['clips']
    for name, clip in previous.items():
        clips[name] = clip
json_path = OUTPUT / f'anim_bunny01_library_{VERSION}.json'
json_path.write_text(json.dumps({'schema': 2, 'skeleton_sha256': expected, 'clips': clips}, separators=(',', ':')))

# Export an animation-only glTF for DCC review and future Skeleton3D consumers.
for obj in list(bpy.data.objects):
    if obj != rig:
        bpy.data.objects.remove(obj, do_unlink=True)
for mesh in list(bpy.data.meshes):
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
glb_path = OUTPUT / f'anim_bunny01_library_{VERSION}.glb'
bpy.ops.export_scene.gltf(
    filepath=str(glb_path), export_format='GLB', use_selection=True,
    export_animations=True, export_skins=False, export_morph=False, export_yup=True,
)

files = [SOURCE, json_path, glb_path]
ledger = {
    'asset_id': 'CHR-PLY-CAPSULE01-3D-BUNNY01',
    'version': VERSION,
    'base_model_version': 'v021',
    'skeleton_sha256': expected,
    'animation_adapter': 'anatomical_to_rigid_node_map',
    'collision_owner': 'scenes/Player3D.tscn',
    'clips': {name: {'duration': clip['duration'], 'loop': clip['loop'], 'frame_count': len(clip['frames'])} for name, clip in clips.items()},
    'files': [{'path': str(file.relative_to(ROOT)).replace('\\', '/'), 'sha256': hashlib.sha256(file.read_bytes()).hexdigest(), 'bytes': file.stat().st_size} for file in files],
}
(PACKAGE / f'character_transfer_ledger_{VERSION}.json').write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + '\n')
print('SEATED_ANIMATION_EXPORTED', len(clips), len(clips['seated']['frames']), json_path)
