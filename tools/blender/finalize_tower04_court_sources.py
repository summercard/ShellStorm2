"""Finalize staged courtyard sources, with checksummed draft backups."""
import bpy,sys,json,hashlib,shutil,math
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent));import tower04_court_common as H
R=H.R;F=R/'assets/art/environments/open_world/source/tower_04_2/v002';lod=sys.argv[-1];meta=json.loads((F/f'{lod}_catalog.json').read_text(encoding='utf8'));p=R/meta['source_blend']
assert hashlib.sha256(p.read_bytes()).hexdigest()==meta['source_sha256']
backup=R.parent/'_scratch/tower04_v010'/('court_'+lod+'_pre_final.blend')
if backup.exists():assert hashlib.sha256(backup.read_bytes()).hexdigest()==meta['source_sha256']
else:shutil.copy2(p,backup)
bpy.ops.wm.open_mainfile(filepath=str(p));H.setup_materials()
if lod=='far':
 for d in meta['definitions']:
  mesh=bpy.data.meshes[d['mesh']];obj=next(o for o in bpy.data.objects if o.type=='MESH' and o.data==mesh)
  if d['family'] not in ('tree','bush','vine','soil','planter','pot'):continue
  # A single shared reduced mesh updates every linked placement of the same definition.
  proxy=obj.copy();proxy.data=mesh.copy();bpy.context.scene.collection.objects.link(proxy);bpy.context.view_layer.objects.active=proxy
  mod=proxy.modifiers.new('远景地被轮廓简化','DECIMATE');mod.ratio=.20;mod.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=mod.name)
  new=proxy.data;uv=new.uv_layers.active;colors=[];indices=[]
  for face in new.polygons:
   q=sum((uv.data[i].uv for i in face.loop_indices),__import__('mathutils').Vector((0,0)))/face.loop_total
   colors.append((max(0,min(9,int(q.x*10))),max(0,min(9,int((1-q.y)*10)))));indices.append(face.material_index)
  slots=list(new.materials)
  for u in list(new.uv_layers):new.uv_layers.remove(u)
  new.materials.clear();H.uv_mesh(new,colors,indices,slots)
  for o in list(bpy.data.objects):
   if o.type=='MESH' and o.data==mesh:o.data=new
  bpy.data.objects.remove(proxy,do_unlink=True);bpy.data.meshes.remove(mesh);new.name=d['mesh'];d['triangles']=sum(len(f.vertices)-2 for f in new.polygons)
# No fourth role is used by the unlit garden; don't retain an unused emission datablock.
for m in list(bpy.data.materials):
 if not any(m in list(me.materials) for me in bpy.data.meshes):bpy.data.materials.remove(m)
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(p))
layout=bpy.data.collections['02_游戏输出_分区实例'];meta['visible_triangles']=H.tri_count(layout.all_objects);meta['source_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();meta['material_roles']=[m.name for m in bpy.data.materials]
for d in meta['definitions']:
 f=F/'component_packages'/d['slug']/f'{lod}_manifest.json';a=json.loads(f.read_text(encoding='utf8'));a.update(triangles=d['triangles'],material_roles=meta['material_roles']);f.write_text(json.dumps(a,ensure_ascii=False,indent=2),encoding='utf8')
(F/f'{lod}_catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8');print('FINALIZED',lod,meta['visible_triangles'],flush=True)
