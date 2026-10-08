"""将已验收的GLB封装到不带版本号的纯视觉PackedScene。"""
from pathlib import Path
import json, hashlib
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/items_weapons/props'
for size in ['small','medium','large']:
    folder=BASE/('backpack_'+size)
    c=json.loads((folder/'asset_contract.json').read_text('utf-8'))
    m=json.loads((folder/'source_manifest.json').read_text('utf-8'))
    assert m['triangles']<=500 and m['uv_nonzero_area'] and not m['glb_embedded_images']
    glb=ROOT/c['stable_glb']; path=ROOT/c['stable_prefab']
    assert path.exists() and glb.exists()
    d=c['dimensions_m']
    path.write_text(f'''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://{c['stable_glb']}" id="1_visual"]

[node name="ItemRoot" type="Node3D"]
metadata/asset_id = "{c['asset_id']}"
metadata/logical_id = "{c['logical_id']}"
metadata/asset_version = "v001"
metadata/model_kind = "backpack"
metadata/backpack_extra_slots = {c['extra_slots']}
metadata/triangle_count = {m['triangles']}
metadata/dimensions_m = Vector3({d['width']}, {d['height']}, {d['depth']})
metadata/front_axis = "+Z"
metadata/shoulder_straps = false
metadata/collision_intent = "none"

[node name="Visual" parent="." instance=ExtResource("1_visual")]
''',encoding='utf-8')
    import_file=Path(str(glb)+'.import')
    if import_file.exists():
        text=import_file.read_text('utf-8')
        text=text.replace('import_script/path=""','import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"')
        text=text.replace('gltf/embedded_image_handling=1','gltf/embedded_image_handling=0')
    else:
        resource='res://'+c['stable_glb']
        dest='res://.godot/imported/'+glb.name+'-'+hashlib.md5(resource.encode()).hexdigest()+'.scn'
        text=f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"
path="{dest}"

[deps]
source_file="{resource}"
dest_files=["{dest}"]

[params]
nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=1
animation/import=false
import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
_subresources={{}}
gltf/naming_version=2
gltf/embedded_image_handling=0
'''
    import_file.write_text(text,encoding='utf-8')
    print('BACKPACK_PREFAB_READY',size,m['triangles'])
