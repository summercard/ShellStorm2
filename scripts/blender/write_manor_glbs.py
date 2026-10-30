import bpy,bmesh,json,hashlib,math
from pathlib import Path
from mathutils import Vector
ROOT=Path('I:/工作项目/shellstrom2/ShellStorm2');S=ROOT/'art_source/environments/tower_zones/expedition/source/common_components/v017';W=ROOT.parent/'ShellStorm2-work/manor_v017'
source=S/'复古公馆_模块化组件母版_v017.blend';optimized=S/'export/v017/复古公馆_组件优化输出_v017.blend'
palette=ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
state=json.loads((S/'export/v017/prepare_state.json').read_text(encoding='utf-8'));catalog=state['catalog'];reports=state['reports'];source_hash=state['source_hash'];palette_hash=state['palette_hash']
assert Path(bpy.data.filepath)==optimized
active=bpy.data.scenes['组件母版画廊_独立可编辑']
bpy.context.window.scene=active
for old_scene in list(bpy.data.scenes):
 if old_scene!=active:bpy.data.scenes.remove(old_scene)
for old_object in list(bpy.data.objects):
 if old_object.users==0:bpy.data.objects.remove(old_object)
bpy.context.view_layer.update()
for e,report in zip(catalog,reports):
 c=bpy.data.collections[e['collection']]
 # An independent temporary scene provides an export view layer without realizing instances.
 sc=bpy.data.scenes['组件母版画廊_独立可编辑']
 for o in sc.objects:o.select_set(False)
 for o in c.objects:o.select_set(True)
 folder=ROOT/'assets/art/environments/tower_zones/expedition/components/common_components'/e['slug'];folder.mkdir(parents=True,exist_ok=True)
 glb=folder/('env_'+e['slug']+'_visual_top3d.glb')
 with bpy.context.temp_override(scene=sc,view_layer=sc.view_layers[0]):
  bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,use_active_scene=True,export_image_format='NONE',export_texcoords=True,export_normals=True,export_materials='EXPORT',export_animations=False,export_cameras=False,export_lights=False,export_yup=True)
 report['glb_path']=glb.relative_to(ROOT).as_posix();report['glb_sha256']=sha(glb)
 e['visual_glb']=report['glb_path'];e['glb_sha256']=report['glb_sha256'];e['optimized_blend']=optimized.relative_to(ROOT).as_posix()
 report['source_sha256_after']=sha(source);assert report['source_sha256_after']==source_hash
 # All roots and all mesh locals are identity, including collection instance offset.
 assert c.instance_offset.length<1e-8
 for o in c.objects:assert all(abs(o.matrix_local[i][j]-(1 if i==j else 0))<1e-6 for i in range(4) for j in range(4)),o.name

optimized_hash=sha(optimized)
for e,rep in zip(catalog,reports):
 rep['optimized_sha256']=optimized_hash;rep['palette_sha256_before']=palette_hash;rep['palette_sha256_after']=sha(palette);assert rep['palette_sha256_before']==rep['palette_sha256_after']
 manifest=dict(e,asset_id=e['component_id'],asset_version='v017',block_id='expedition',level_id='expedition_03',source_room_type_blend=source.relative_to(ROOT).as_posix(),source_room_type_sha256=source_hash,room_owned_geometry=False,export=rep,exported=True,runtime_integrated=False,asset_ledger='resolved_by_ledger_index:scenes',front_axis='-Y',godot_front_axis='+Z',coordinate_mapping='(bx,by,bz)->(bx,bz,-by)',local_origin=[0,0,0])
 (S/'component_packages'/e['slug']/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(S/'component_catalog.json').write_text(json.dumps({'components':catalog},ensure_ascii=False,indent=2),encoding='utf-8')
(S/'export/v017/optimization_report.json').write_text(json.dumps(dict(source_sha256=source_hash,optimized_sha256=optimized_hash,source_unchanged=sha(source)==source_hash,components=reports),ensure_ascii=False,indent=2),encoding='utf-8')
(S/'component_tree.txt').write_text('\n'.join(e['component_id']+' / '+e['collection']+' / '+e['component_blend'] for e in catalog),encoding='utf-8')
# Return the live Blender window to the editable original, never leave the optimized copy active.
# Restore original through the next MCP call.
print(json.dumps({'exported':len(reports),'source_unchanged':sha(source)==source_hash,'triangles_before':sum(r['triangles_before'] for r in reports),'triangles_after':sum(r['triangles_after'] for r in reports)},ensure_ascii=False))
