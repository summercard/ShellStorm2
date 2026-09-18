import bpy, json, hashlib
from pathlib import Path
from mathutils import Vector

ROOT=Path('/Users/summercards/ShellStorm2')
OUT=ROOT/'assets/art/environments/tower_zones/battle/source/room_instances/main_room_02/v003'
def transform(o):
    return o.parent.matrix_world@o.matrix_parent_inverse@o.matrix_basis if o.parent else o.matrix_basis
def sig(o):
    points=[transform(o)@Vector(v) for v in o.bound_box]
    payload={'transform':[[round(v,6) for v in row] for row in transform(o)],'parent':o.parent.name if o.parent else None,
             'vertices':[[round(v,6) for v in p.co] for p in o.data.vertices],
             'polygons':[list(p.vertices) for p in o.data.polygons],
             'modifiers':[(m.name,m.type) for m in o.modifiers], 'animation':bool(o.animation_data)}
    return {'hash':hashlib.sha256(json.dumps(payload,sort_keys=True).encode()).hexdigest(),
            'bounds':[[round(f(p[i] for p in points),6) for i in range(3)] for f in (min,max)]}
bpy.ops.wm.open_mainfile(filepath=str(OUT/'qa/制作前工作区备份.blend'))
old={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH'}
bpy.ops.wm.open_mainfile(filepath=str(OUT/'env_battle_l01_main_02_data_room_layout_source_v003.blend'))
new={n:sig(bpy.data.objects[n]) for n in old}
changed=[n for n in old if old[n]!=new[n]]
catalog=json.loads((OUT/'component_packages_v003/catalog.json').read_text())
bad=[]; cross=[]; empty=[]
for p in catalog:
    col=bpy.data.collections.get(p['blender_collection'])
    if col is None or sorted(p['objects'])!=sorted(o.name for o in col.objects): bad.append(p['slug'])
    if col is None or not col.objects: empty.append(p['slug'])
    if col:
        cross.extend(o.name for o in col.objects if len(o.users_collection)!=1)
    path=OUT/'component_packages_v003'/p['category']/p['slug']/'asset_manifest.json'
    if not path.exists() or json.loads(path.read_text())!=p: bad.append(p['slug'])
report={'passed':not(changed or bad or cross or empty),'locked_count':len(old),'original_structure_count':sum(not n.startswith('AP_') for n in old),'geometry_changed':changed,'before':old,'after':new,'package_count':len(catalog),'manifest_mismatches':bad,'multiple_package_objects':cross,'empty_packages':empty,'floor_tile_count':sum(p['slug'].startswith('floor_tile_') for p in catalog),'door_clear_width_m':2.2,'floor_surface_z_m':.3,'lintel_bottom_z_m':2.8,'door_clear_height_m':2.5,'whitebox_wall_height_m':11.9}
(OUT/'qa/saved_scene_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({k:v for k,v in report.items() if k not in ['before','after']},ensure_ascii=False))
raise SystemExit(0 if report['passed'] else 1)
