"""Export the eight authored ground variants without changing their Blender sources."""
import bpy
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from workspace_paths import work_path

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf8')

reports = []
batch = json.loads((ROOT / 'art_source/items_weapons/reference_batch_20261014/ground_report.json').read_text('utf8'))
for record in batch:
    source = ROOT / record['ground_source']
    folder = source.parent.parent
    contract = json.loads((folder / 'asset_contract.json').read_text('utf8'))
    protected = {record[k]: sha(ROOT / record[k]) for k in ('preview_source', 'ground_source')}
    bpy.ops.wm.open_mainfile(filepath=str(source))
    output = bpy.data.collections['02_游戏输出_整合模型']
    bpy.ops.object.select_all(action='DESELECT')
    meshes = [o for o in output.objects if o.type == 'MESH']
    for obj in meshes:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    stem = source.stem.replace('_source_v001', '')
    domain = 'props' if record['asset_id'].startswith('ITM-') else 'weapons'
    runtime = ROOT / 'assets/art/items_weapons' / domain / record['slug']
    glb = runtime / 'components' / (stem + '_visual_top3d.glb')
    prefab = runtime / 'runtime' / (stem + '_root_top3d.tscn')
    glb.parent.mkdir(parents=True, exist_ok=True)
    prefab.parent.mkdir(parents=True, exist_ok=True)
    temp = work_path('sessions/2026-10-14_item_ground_import/exports/' + glb.name)
    bpy.ops.export_scene.gltf(filepath=str(temp), export_format='GLB', use_selection=True,
        export_yup=True, export_image_format='NONE', export_materials='EXPORT',
        export_animations=False, export_cameras=False, export_lights=False, export_extras=False)
    shutil.copy2(temp, glb)
    dims = contract['dimensions_m']
    prefab.write_text(f'''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://{glb.relative_to(ROOT).as_posix()}" id="1_visual"]

[node name="ItemRoot" type="Node3D"]
metadata/asset_id = "{contract['asset_id']}"
metadata/logical_id = "{contract['logical_id']}"
metadata/asset_version = "v001"
metadata/model_role = "ground"
metadata/triangle_count = {record['ground_triangles']}
metadata/dimensions_m = Vector3({dims['width']}, {dims['height']}, {dims['depth']})
metadata/front_axis = "+Z"
metadata/collision_intent = "external_ground_loot_pickup"

[node name="Visual" parent="." instance=ExtResource("1_visual")]
''', encoding='utf8')
    imp = Path(str(glb) + '.import')
    if not imp.exists():
        imp.write_text('''[remap]
importer="scene"
importer_version=1
type="PackedScene"

[params]
nodes/root_scale=1.0
meshes/generate_lods=false
animation/import=false
import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
gltf/embedded_image_handling=0
''', encoding='utf8')
    for path, digest in protected.items():
        if sha(ROOT / path) != digest:
            raise RuntimeError('Source changed: ' + path)
    report = dict(record, asset_id=contract['asset_id'], logical_id=contract['logical_id'], name=contract['display_name_zh'],
        glb=glb.relative_to(ROOT).as_posix(), prefab=prefab.relative_to(ROOT).as_posix(),
        glb_sha256=sha(glb), prefab_sha256=sha(prefab), source_hashes_unchanged=True,
        model_role='ground', status='exported_pending_godot_validation',
        consumer='src/world3d/GroundLootPickup3D.gd via ItemModelFactory3D')
    write(runtime / 'asset_manifest.json', report)
    reports.append(report)
write(work_path('sessions/2026-10-14_item_ground_import/export_report.json'), reports)
print('GROUND_EXPORT_COMPLETE', len(reports))
