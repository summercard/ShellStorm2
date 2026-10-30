"""Build independent manor component wrappers; never write a room scene."""
import json,hashlib,struct,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
S=ROOT/'art_source/environments/tower_zones/expedition/source/common_components/v017'
W=ROOT.parent/'ShellStorm2-work/manor_v017'
C=json.loads((S/'component_catalog.json').read_text(encoding='utf-8'))['components']
POST='res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd'
def v(a):return 'Vector3('+', '.join(f'{x:g}' for x in a)+')'
for e in C:
 slug=e['slug'];w,d,h=e['bounds_size_m'];boxes=[]
 if e['component_family']=='wall':
  boxes=[([-1.8,1.4,0],[1.4,2.8,.3]),([1.8,1.4,0],[1.4,2.8,.3])] if slug=='manor_wall_door' else [([0,1.4,0],[5,2.8,.3])]
 elif e['component_family']=='floor':boxes=[([0,h/2,0],[5,h,5])]
 # Furniture/decor are optional visual assets: no implicit gameplay obstacles.
 policy='segmented_door_piers' if slug=='manor_wall_door' else ('structural_box' if boxes else 'visual_only')
 folder=ROOT/'assets/art/environments/tower_zones/expedition/runtime/common_components'/slug;folder.mkdir(parents=True,exist_ok=True)
 path=folder/('env_'+slug+'_root_top3d.tscn');e['prefab_path']=path.relative_to(ROOT).as_posix()
 e['collision_policy']=policy;e['collision_shape_count']=len(boxes)
 lines=['[gd_scene load_steps=%d format=3]'%(2+len(boxes)),'',f'[ext_resource type="PackedScene" path="res://{e["visual_glb"]}" id="1"]','']
 for i,(pos,size) in enumerate(boxes):lines.extend([f'[sub_resource type="BoxShape3D" id="Shape_{i}"]','size = '+v(size),''])
 lines.extend([f'[node name="{slug}" type="Node3D"]',f'metadata/asset_id = "{e["component_id"]}"','metadata/asset_version = "v017"','metadata/level_id = "expedition_03"',f'metadata/display_name_zh = "{e["name_zh"]}"',f'metadata/source_blend = "res://{e["component_blend"]}"','metadata/origin_contract = "bottom_center"','metadata/forward_axis = "+Z"','metadata/up_axis = "+Y"','metadata/collision_owner = "godot_wrapper"',f'metadata/collision_policy = "{policy}"',f'metadata/collision_shape_count = {len(boxes)}','metadata/bounds_size_m = '+v([w,h,d]),'metadata/room_owned_geometry = false','metadata/preserve_authored_palette = true',f'metadata/component_family = "{e["component_family"]}"','metadata/grid_unit_m = 5.0' if e['category']=='architecture' else 'metadata/grid_unit_m = 0.0','', '[node name="Visual" parent="." instance=ExtResource("1")]',''])
 if boxes:
  lines.extend(['[node name="CollisionBody" type="StaticBody3D" parent="."]','collision_layer = 1','collision_mask = 0',''])
  for i,(pos,size) in enumerate(boxes):lines.extend([f'[node name="Collision_{i}" type="CollisionShape3D" parent="CollisionBody"]','position = '+v(pos),f'shape = SubResource("Shape_{i}")',''])
 path.write_text('\n'.join(lines),encoding='utf-8')
 e['prefab_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
 # Explicit palette post-import hook, applied by the official Godot importer.
 glb=ROOT/e['visual_glb'];name=glb.name;res='res://'+e['visual_glb'];md5=hashlib.md5(res.encode()).hexdigest();dest=f'res://.godot/imported/{name}-{md5}.scn'
 imp=f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"
path="{dest}"
[deps]
source_file="{res}"
dest_files=["{dest}"]
[params]
nodes/root_scale=1.0
nodes/apply_root_scale=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
import_script/path="{POST}"
animation/import=false
'''
 glb.with_suffix('.glb.import').write_text(imp,encoding='utf-8')
 # Reject embedded image copies and whole-room exports.
 raw=glb.read_bytes();length,typ=struct.unpack_from('<II',raw,12);j=json.loads(raw[20:20+length]);assert not j.get('images') and not j.get('textures')
 assert len(j.get('meshes',[])) in [1,2],slug
 mpath=S/'component_packages'/slug/'asset_manifest.json';m=json.loads(mpath.read_text(encoding='utf-8'));m.update(prefab_path=e['prefab_path'],prefab_sha256=e['prefab_sha256'],collision_policy=policy,collision_shape_count=len(boxes),import_status='pending_validation');mpath.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
(S/'component_catalog.json').write_text(json.dumps({'components':C},ensure_ascii=False,indent=2),encoding='utf-8')
# Standalone validation project: no game autoloads, saves, or production room files.
Q=W/'godot_validation';Q.mkdir(parents=True,exist_ok=True)
(Q/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Manor isolated component validation"\n[display]\nwindow/size/viewport_width=1600\nwindow/size/viewport_height=1500\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nenvironment/defaults/default_clear_color=Color(0.025,0.025,0.025,1)\n',encoding='utf-8')
files=[e[k] for e in C for k in ['visual_glb','prefab_path']]+['assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png','tools/asset_pipeline/scene_facility_shared_palette_post_import.gd']
for rel in files:
 dest=Q/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,dest)
 if rel.endswith('.glb'):shutil.copy2(str(ROOT/rel)+'.import',str(dest)+'.import')
for name in ['component_catalog.json','component_instances.json']:shutil.copy2(S/name,Q/name)
print('Built',len(C),'independent prefabs; staged isolated project',Q)
