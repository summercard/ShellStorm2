"""Initialize native stable component prefabs and confirmed tower layouts.

Existing hand-edited layouts are never overwritten unless --replace-layout is explicit.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'assets/art/environments/open_world'


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding='utf-8', newline='\r\n')


def quote(value):
    return json.dumps(value, ensure_ascii=False)


def vector(value):
    return 'Vector3(%s)' % ', '.join('%.9f' % v for v in value)


def assembly(path, name, asset_id, manifest, records, origin, extra_groups=(), replace=False):
    if path.exists() and not replace:
        print('PRESERVED_HAND_EDITED_LAYOUT', path)
        return
    resources = []
    nodes = [f'[node name="{name}" type="Node3D"]',
             f'metadata/asset_id = {quote(asset_id)}',
             f'metadata/asset_version = {quote(manifest["version"])}',
             'metadata/collision_status = "none_visual_only"',
             f'metadata/source_blend = {quote(manifest["source"])}',
             f'metadata/component_count = {len(manifest["records"]) if name.startswith("Tower") else len(records)}', '']
    groups = sorted({r.get('group', r['category']) for r in records})
    for group in groups:
        nodes += [f'[node name="{group}" type="Node3D" parent="."]', '']
    for i, record in enumerate(records, 1):
        resources.append(f'[ext_resource type="PackedScene" path="res://{record["prefab"]}" id="{i}"]')
        pos = [v-o for v,o in zip(record['position_godot'], origin)]
        nodes += [f'[node name="{record["slug"]}" parent="{record.get("group",record["category"])}" instance=ExtResource("{i}")]',
                  'position = ' + vector(pos), '']
    write(path, f'[gd_scene load_steps={len(resources)+1} format=3]\n\n' + '\n'.join(resources) + '\n\n' + '\n'.join(nodes))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--replace-layout', action='store_true')
    args = parser.parse_args()
    template = (ROOT / 'assets/art/environments/tower_zones/expedition/components/room_type_components/office_room/door_wall/door_wall_visual_top3d.glb.import').read_text(encoding='utf-8')
    for slug, version in [('tower_02','v003'),('tower_03','v001')]:
        manifest = json.loads((BASE / 'source' / slug / 'export' / version / 'export_manifest.json').read_text(encoding='utf-8'))
        catalog = json.loads((BASE / 'source' / slug / version / 'catalog.json').read_text(encoding='utf-8'))
        records = manifest['records']
        for record in records:
            path = ROOT / record['prefab']
            write(path, '[gd_scene load_steps=2 format=3]\n\n'
                  f'[ext_resource type="PackedScene" path="res://{record["glb"]}" id="1"]\n\n'
                  f'[node name="{record["slug"]}" type="Node3D"]\n'
                  f'metadata/asset_id = {quote(record["asset_id"])}\n'
                  f'metadata/asset_version = {quote(version)}\n'
                  'metadata/collision_status = "none_visual_only"\n'
                  f'metadata/source_blend = {quote(manifest["source"])}\n\n'
                  '[node name="Visual" type="Node3D" parent="."]\n\n'
                  '[node name="ImportedModel" parent="Visual" instance=ExtResource("1")]\n')
            import_path = ROOT / (record['glb'] + '.import')
            if not import_path.exists():
                resource = 'res://' + record['glb']
                cache = 'res://.godot/imported/' + Path(record['glb']).name + '-' + hashlib.md5(resource.encode()).hexdigest() + '.scn'
                original_source = 'res://assets/art/environments/tower_zones/expedition/components/room_type_components/office_room/door_wall/door_wall_visual_top3d.glb'
                original_cache = 'res://.godot/imported/door_wall_visual_top3d.glb-c3d56b326c62ed43f69a3d7cbf3718da.scn'
                text = '\n'.join(line for line in template.splitlines() if not line.startswith('uid='))
                text = text.replace(original_source, resource).replace(original_cache, cache).replace('animation/import=true', 'animation/import=false')
                write(import_path, text + '\n')
            write(path.parent/'asset_manifest.json', json.dumps(dict(record, version=version, source=manifest['source'], collision='none_visual_only'), ensure_ascii=False, indent=2)+'\n')
        building_records = [r for r in records if not r['slug'].startswith('crane_')]
        for crane in catalog.get('crane_assemblies', []):
            crane_slug = crane['assembly_id'].split('/')[-1]
            x,y,z = crane['world_origin']
            origin = [x,z,-y]
            crane_path = BASE / 'runtime' / slug / 'cranes' / crane_slug / f'env_{slug}_{crane_slug}_root_top3d.tscn'
            parts = [r for r in records if r['slug'] in crane['component_packages']]
            crane_id = catalog['asset_id']+'-'+crane_slug.upper().replace('_','-')
            assembly(crane_path, crane_slug, crane_id, manifest, parts, origin, replace=args.replace_layout)
            building_records.append(dict(slug=crane_slug, category='cranes', position_godot=origin,
                                         prefab=crane_path.relative_to(ROOT).as_posix(),asset_id=crane_id,
                                         display_name=crane['collection']))
        target = BASE / 'runtime' / slug / f'env_{slug}_root_top3d.tscn'
        assembly(target, 'Tower02' if slug=='tower_02' else 'Tower03', catalog['asset_id'], manifest,
                 building_records, [0,0,0], replace=args.replace_layout)
        write(target.parent / 'asset_manifest.json', json.dumps(dict(asset_id=catalog['asset_id'], version=version,
            source=manifest['source'], source_sha256=manifest['source_sha256'], prefab=target.relative_to(ROOT).as_posix(),
            component_count=len(records), footprint_m=catalog['footprint_m'], collision='none_visual_only',
            layout_owner='Godot TSCN; rerun preserves layout by default', crane_count=len(catalog.get('crane_assemblies',[]))),ensure_ascii=False,indent=2)+'\n')
        print('TOWER_ASSEMBLY_OK', slug, len(records))


if __name__ == '__main__':
    main()
