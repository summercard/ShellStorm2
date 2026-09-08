from pathlib import Path
import json, re, hashlib

ROOT=Path(__file__).resolve().parents[2]
MANIFEST=ROOT/'source/art/blender/base_facility_layout/export/v022/export_manifest.json'
DATA=json.loads(MANIFEST.read_text())
RUNTIME=ROOT/'assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021'
WALL=ROOT/'assets/art/environments/base_facility_3d/runtime/env_base99_wall_contents_v021'

def res(p): return 'res://'+str(p.relative_to(ROOT))
def v3(a): return 'Vector3('+', '.join(f'{x:.6f}' for x in a)+')'
def godot_box(b):
 lo,hi=b['min'],b['max']; return ((lo[0]+hi[0])/2,(lo[2]+hi[2])/2,-(lo[1]+hi[1])/2),(hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1])

visual_only={'loft_bedside_lamp','corridor_emergency_light_group'}
remaining=[k for k,v in DATA['packages'].items() if v['scope']=='remaining']
for slug in remaining:
 p=DATA['packages'][slug]; glb=ROOT/p['glb']; ver=re.search(r'(v\d{3})$',glb.stem).group(1)
 target=RUNTIME/slug/f'{slug}_root_top3d_{ver}.tscn'; target.parent.mkdir(parents=True,exist_ok=True)
 center,size=godot_box(p['bbox_blender'])
 extra=''
 load=2
 if slug=='hologram_terminal_platform':
  load=4
  extra='[ext_resource type="Script" path="res://tools/asset_pipeline/play_imported_animation.gd" id="2_anim"]\n\n[sub_resource type="BoxShape3D" id="Box_bounds"]\nsize = '+v3(size)+'\n'
 elif slug not in visual_only:
  load=3; extra='[sub_resource type="BoxShape3D" id="Box_bounds"]\nsize = '+v3(size)+'\n'
 lines=[f'[gd_scene load_steps={load} format=3]','',f'[ext_resource type="PackedScene" path="{res(glb)}" id="1_visual"]']
 if extra: lines += ['',extra.rstrip()]
 lines += ['',f'[node name="{p["package"]}" type="Node3D"]']
 if slug=='hologram_terminal_platform': lines += ['script = ExtResource("2_anim")']
 lines += [f'metadata/asset_id = "ENV-BASE99-V022::{slug}"','metadata/asset_version = "v022"',
  'metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v022.blend"',
  'metadata/derived_blend = "res://source/art/blender/base_facility_layout/export/v022/base_facility_runtime_layout_hq-v022-updated_packages.blend"',
  f'metadata/source_collection = "{p["collection"]}"',f'metadata/triangles_before = {p["triangles_before"]}',
  f'metadata/triangles_after = {p["triangles_after"]}',f'metadata/downward_triangles_removed = {p["downward_triangles_removed"]}',
  f'metadata/collision_policy = "{"visual_only_no_collision" if slug in visual_only else "optimized_output_bounds_box"}"','',
  '[node name="ImportedModel" parent="." instance=ExtResource("1_visual")]']
 if slug not in visual_only:
  lines += ['','[node name="StaticCollision" type="StaticBody3D" parent="."]','collision_layer = 1','collision_mask = 1','',
   '[node name="OptimizedOutputBounds" type="CollisionShape3D" parent="StaticCollision"]',f'position = {v3(center)}','shape = SubResource("Box_bounds")']
 target.write_text('\n'.join(lines)+'\n')

# Remaining aggregate v003; updated GLBs carry baked world transforms.
old=RUNTIME/'env_base99_remaining_facilities_root_top3d_v002.tscn'; text=old.read_text()
for slug in remaining:
 glb=Path(DATA['packages'][slug]['glb']); ver=re.search(r'(v\d{3})$',glb.stem).group(1)
 text=re.sub(fr'{re.escape(slug)}_root_top3d_v\d{{3}}\.tscn',f'{slug}_root_top3d_{ver}.tscn',text)
text=text.replace('res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/volumetric_dust_fx/volumetric_dust_fx_root_top3d_v001.tscn',
 'res://assets/art/vfx/environment_3d/base_facility_dust_particles/vfx_base99_dust_particles_root_top3d_v001.tscn')
text=text.replace('[node name="64_光束尘埃动效组_资产包" parent="." instance=ExtResource("42_volumetric_dust_fx")]',
 '[node name="场景特效_光束尘埃粒子" parent="." instance=ExtResource("42_volumetric_dust_fx")]')
text=text.replace('metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"','metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v022.blend"')
text=text.replace('metadata/derived_from_version = "v021"','metadata/derived_from_version = "v022"')
text=text.replace('metadata/optimized_package_count = 24','metadata/optimized_package_count = 32\nmetadata/scene_vfx_count = 1')
# Remove old nonzero bed placement because the new v003 GLB contains v022 world placement.
text=re.sub(r'(\[node name="31_参考床架床品与床下收纳_资产包"[^\n]*\]\n)(?:position[^\n]*\nrotation[^\n]*\n)?',r'\1',text)
(RUNTIME/'env_base99_remaining_facilities_root_top3d_v003.tscn').write_text(text)

# Wall aggregate v003.
old=WALL/'env_base99_wall_contents_root_top3d_v002.tscn'; text=old.read_text()
for slug,p in DATA['packages'].items():
 if p['scope']=='wall':
  text=re.sub(fr'res://assets/art/environments/base_facility_3d/components/(?:env_base99_wall_contents_v021|env_base99_remaining_facilities_v021)/{re.escape(slug)}/{re.escape(slug)}_visual_top3d_v\d{{3}}\.glb',res(ROOT/p['glb']),text)
text=text.replace('metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend"','metadata/source_blend = "res://source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v022.blend"')
text=text.replace('metadata/optimized_package_count = 5','metadata/optimized_package_count = 10')
(WALL/'env_base99_wall_contents_root_top3d_v003.tscn').write_text(text)

# Stair v005 preserves the functional collision script and only replaces visuals.
stair=DATA['packages']['northwest_l_stair']; oldp=ROOT/'assets/art/environments/base_facility_3d/runtime/env_base99_stair_l_z5/env_base99_stair_l_z5_root_top3d_v004.tscn'
st=oldp.read_text().replace('env_base99_stair_l_z5_visual_top3d_v004.glb','env_base99_stair_l_z5_visual_top3d_v005.glb').replace('metadata/asset_version = "v004"','metadata/asset_version = "v005"').replace('env_base99_modular_room_assets_clean_v004.blend','../../../../../source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v022.blend')
st=st.replace('metadata/source_blend = "res://assets/art/environments/base_facility_3d/source/../../../../../source/', 'metadata/source_blend = "res://source/')
st=st.replace('layout/source/base_facility_runtime_layout_hq_v022.blend"','layout/source/base_facility_runtime_layout_hq_v022.blend"\nmetadata/derived_blend = "res://source/art/blender/base_facility_layout/export/v022/base_facility_runtime_layout_hq-v022-updated_packages.blend"')
oldp.with_name('env_base99_stair_l_z5_root_top3d_v005.tscn').write_text(st)

# Main art layout uses the new aggregates.
layout=ROOT/'assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v001.tscn'; lt=layout.read_text().replace('env_base99_wall_contents_root_top3d_v002.tscn','env_base99_wall_contents_root_top3d_v003.tscn').replace('env_base99_remaining_facilities_root_top3d_v002.tscn','env_base99_remaining_facilities_root_top3d_v003.tscn'); layout.write_text(lt)

# Separate scene-VFX ledger and batch import ledger.
vfx={'asset_id':'VFX-BASE99-SCENE-DUST-V001','version':'v001','category':'scene_vfx','scene':'assets/art/vfx/environment_3d/base_facility_dust_particles/vfx_base99_dust_particles_root_top3d_v001.tscn','replaces':'64_光束尘埃动效组_资产包','implementation':'Godot GPUParticles3D','managed_separately':True}
(ROOT/'assets/art/vfx/environment_3d/base_facility_scene_vfx_manifest_v001.json').write_text(json.dumps({'scene_vfx':[vfx]},ensure_ascii=False,indent=2)+'\n')
ledger={'asset_id':'ENV-BASE99-V022-UPDATES','version':'v022','source_blend':DATA['source_blend'],'source_sha256':hashlib.sha256((ROOT/DATA['source_blend']).read_bytes()).hexdigest(),'derived_blend':DATA['derived_blend'],'packages':DATA['packages'],'runtime':{'remaining':str((RUNTIME/'env_base99_remaining_facilities_root_top3d_v003.tscn').relative_to(ROOT)),'wall':str((WALL/'env_base99_wall_contents_root_top3d_v003.tscn').relative_to(ROOT)),'stair':'assets/art/environments/base_facility_3d/runtime/env_base99_stair_l_z5/env_base99_stair_l_z5_root_top3d_v005.tscn'},'scene_vfx':vfx}
(ROOT/'assets/art/environments/base_facility_3d/source/env_base99_updates_v022_import_manifest.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n')
globalp=ROOT/'assets/art/asset_import_manifest_v001.json'; gd=json.loads(globalp.read_text()); gd['base_facility_updates_v022']={'asset_id':ledger['asset_id'],'version':'v022','package_count':14,'import_manifest':'assets/art/environments/base_facility_3d/source/env_base99_updates_v022_import_manifest.json','runtime':ledger['runtime']}; gd['base_facility_scene_vfx']=vfx; globalp.write_text(json.dumps(gd,ensure_ascii=False,indent=2)+'\n')
print('BASE99_V022_IMPORTED packages=14 scene_vfx=1')
