"""初始化SKYLINE稳定组件及整楼场景；保留已有布局，不回灌源文件。"""
import hashlib
import json
from pathlib import Path
from assemble_openworld_towers import assembly, quote, write

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'assets/art/environments/open_world'

def main():
    manifest = json.loads((BASE / 'source/skyline_08/export/v004/export_manifest.json').read_text(encoding='utf8'))
    catalog = json.loads((BASE / 'source/skyline_08/v004/catalog.json').read_text(encoding='utf8'))
    old = json.loads((ROOT / 'outputs/skyline08_import_20260930/before_runtime.json').read_text(encoding='utf8'))
    template_path = BASE / 'components/tower_02/roof_column_04/env_tower_02_roof_column_04_visual_top3d.glb.import'
    template = template_path.read_text(encoding='utf8')
    for record in manifest['records']:
        path = ROOT / record['prefab']
        assert not path.exists(), '拒绝覆盖已有组件：' + str(path)
        write(path, '[gd_scene load_steps=3 format=3]\n\n'
              f'[ext_resource type="PackedScene" path="res://{record["glb"]}" id="1"]\n\n'
              '[ext_resource type="Script" path="res://tools/asset_pipeline/skyline08_existing_material_bind.gd" id="bind"]\n\n'
              f'[node name="{record["slug"]}" type="Node3D"]\n'
              'script = ExtResource("bind")\n'
              f'metadata/asset_id = {quote(record["asset_id"])}\n'
              'metadata/asset_version = "v004"\nmetadata/block_id = "open_world"\n'
              'metadata/asset_category = "大地图场景景观"\nmetadata/collision_status = "none_visual_only"\n'
              f'metadata/source_blend = {quote(manifest["source"])}\n\n'
              '[node name="Visual" type="Node3D" parent="."]\n\n'
              '[node name="ImportedModel" parent="Visual" instance=ExtResource("1")]\n')
        imp = ROOT / (record['glb'] + '.import')
        assert not imp.exists()
        resource = 'res://' + record['glb']
        cache = 'res://.godot/imported/' + Path(record['glb']).name + '-' + hashlib.md5(resource.encode()).hexdigest() + '.scn'
        text = '\n'.join(line for line in template.splitlines() if not line.startswith('uid='))
        original_source = 'res://assets/art/environments/open_world/components/tower_02/roof_column_04/env_tower_02_roof_column_04_visual_top3d.glb'
        original_cache = 'res://.godot/imported/env_tower_02_roof_column_04_visual_top3d.glb-1838049137aeb0f545dbde779aa6266b.scn'
        text = text.replace(original_source, resource).replace(original_cache, cache)
        text = text.replace('scene_facility_shared_palette_post_import.gd', 'skyline08_existing_material_post_import.gd')
        text = text.replace('nodes/root_name=""', 'nodes/root_name="SkylineVisualReused"')
        write(imp, text + '\n')
        write(path.parent / 'asset_manifest.json', json.dumps(dict(record, version='v004', source=manifest['source'], collision='none_visual_only', existing_material_resources=old['old_material_resources']), ensure_ascii=False, indent=2) + '\n')
    target = BASE / 'runtime/skyline_08/env_skyline_08_root_top3d.tscn'
    assembly(target, 'Skyline08', catalog['asset_id'], manifest, manifest['records'], [0,0,0])
    write(target.parent / 'asset_manifest.json', json.dumps(dict(asset_id=catalog['asset_id'], version='v004', source=manifest['source'], source_sha256=manifest['source_sha256'], prefab=target.relative_to(ROOT).as_posix(), component_count=len(manifest['records']), collision='none_visual_only', category='大地图场景景观', layout_owner='Godot TSCN', coordinate_map=manifest['coordinate_map'], existing_material_resources=old['old_material_resources'], placement=dict(scene='scenes/TowerDescent3D.tscn', node='Blocks/Rooftop/CrossTowerRoute/Skyline08', final_world=[10,-100.5,-90])), ensure_ascii=False, indent=2) + '\n')
    print('SKYLINE_ASSEMBLY_OK', len(manifest['records']))

if __name__ == '__main__':
    main()
