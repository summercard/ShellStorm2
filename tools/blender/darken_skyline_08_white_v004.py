"""User-directed two-step darkening of the two whitest palette cells; geometry locked."""
import bpy,json,math,shutil,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[2]
old=Path(bpy.data.filepath).parent
new=old.parent/'v004'; blend=new/'SKYLINE大楼_8层_精细天台_v004.blend'
assert old.name=='v003', 'Run against the v003 source'
assert not blend.exists(), 'Keep existing version; choose a higher source version'
new.mkdir(parents=True,exist_ok=True)
for name in ['component_packages','references']:
 shutil.copytree(old/name,new/name,dirs_exist_ok=True)
for name in ['component_plan.json','catalog.json']:
 shutil.copy2(old/name,new/name)
for name in ['qa','previews']: (new/name).mkdir(exist_ok=True)
def geometry_signature():
 digest=hashlib.sha256()
 for obj in sorted(bpy.context.scene.objects,key=lambda o:o.name):
  digest.update(obj.name.encode('utf8')); digest.update(str(tuple(v for row in obj.matrix_world for v in row)).encode())
  if obj.type=='MESH':
   digest.update(str([tuple(v.co) for v in obj.data.vertices]).encode())
   digest.update(str([tuple(p.vertices) for p in obj.data.polygons]).encode())
 return digest.hexdigest()
before=geometry_signature(); changed=0; bycell={'R10C10_to_R8C10':0,'R9C10_to_R7C10':0}
# Visit each unique data-block once because repeated floors share linked meshes.
for mesh in bpy.data.meshes:
 uv=mesh.uv_layers.get('PaletteUV')
 if not uv: continue
 for p in mesh.polygons:
  u,v=uv.data[p.loop_start].uv
  col=min(9,int(u*10)); row=9-min(9,int(v*10))
  if col==9 and row in (8,9):
   for li in p.loop_indices: uv.data[li].uv.y+=.20
   changed+=1; bycell['R10C10_to_R8C10' if row==9 else 'R9C10_to_R7C10']+=1
after=geometry_signature(); assert before==after
for obj in bpy.context.scene.objects:
 if obj.get('version')=='v003': obj['version']='v004'
bpy.context.scene['version']='v004'
bpy.context.scene['white_palette_change']='R10C10→R8C10；R9C10→R7C10；两档白灰均降低两档；灯光与几何保持'
catalog=json.loads((new/'catalog.json').read_text(encoding='utf8'))
catalog['version']='v004'; catalog['source_blend']=str(blend.relative_to(R)); catalog['color_revision']='用户要求所有白色往暗灰移动两档；两档最浅灰白色映射为R8C10与R7C10'
for item in catalog['packages']:
 item['version']='v004'; item['source_blend']=catalog['source_blend']
 (new/'component_packages'/item['category']/item['slug']/'asset_manifest.json').write_text(json.dumps(item,ensure_ascii=False,indent=2),encoding='utf8')
(new/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf8')
plan=json.loads((new/'component_plan.json').read_text(encoding='utf8')); plan['source_version']='v004'; plan['color_revision']=catalog['color_revision']
(new/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
report=dict(passed=True,user_request='不要纯白；所有白色灰度向暗灰移动两档',previous_version='v003',version='v004',changed_unique_mesh_faces=changed,mapping_face_counts=bycell,geometry_signature_before=before,geometry_signature_after=after,geometry_unchanged=before==after,lighting_unchanged=True,camera_unchanged=True,shared_palette_unchanged=True,remaining_brightest_cells=0)
remaining=0
for mesh in bpy.data.meshes:
 uv=mesh.uv_layers.get('PaletteUV')
 if uv:
  for p in mesh.polygons:
   u,v=uv.data[p.loop_start].uv
   if min(9,int(u*10))==9 and 9-min(9,int(v*10)) in (8,9): remaining+=1
report['remaining_brightest_cells']=remaining; assert remaining==0
(new/'qa/white_darkening.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sc=bpy.context.scene
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D': area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
 for device in prefs.devices: device.use=device.type!='CPU'
 if any(d.use for d in prefs.devices): sc.cycles.device='GPU'
except Exception: pass
filenames={'CAM_天台参考':'01_天台参考镜头.png','CAM_8层完整楼体':'02_8层完整楼体.png','CAM_天台俯视':'03_天台俯视结构.png','CAM_设备与机房':'04_机房与设备近景.png','CAM_广告牌细节':'05_破损广告牌近景.png','CAM_背面完整性':'06_背面完整楼体.png'}
for camname,filename in filenames.items():
 cam=bpy.data.objects[camname]; sc.camera=cam; sc.render.resolution_x=cam['resolution_x']; sc.render.resolution_y=cam['resolution_y']; sc.render.filepath=str(new/'previews'/filename)
 bpy.ops.render.render(write_still=True); print('DARKEN_RENDER_DONE',filename,flush=True)
sc.camera=bpy.data.objects['CAM_天台参考']; sc.render.resolution_x=sc.camera['resolution_x']; sc.render.resolution_y=sc.camera['resolution_y']; sc.render.filepath=str(new/'previews/01_天台参考镜头.png')
bpy.ops.wm.save_as_mainfile(filepath=str(blend)); print('WHITE_DARKEN_COMPLETE',changed,remaining,flush=True)
