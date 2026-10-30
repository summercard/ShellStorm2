"""Run through live Blender MCP after visual approval. Export ONLY components."""
import bpy,bmesh,json,hashlib,math
from pathlib import Path
from mathutils import Vector
ROOT=Path('I:/工作项目/shellstrom2/ShellStorm2');S=ROOT/'art_source/environments/tower_zones/expedition/source/common_components/v017';W=ROOT.parent/'ShellStorm2-work/manor_v017'
source=S/'复古公馆_模块化组件母版_v017.blend';optimized=S/'export/v017/复古公馆_组件优化输出_v017.blend';optimized.parent.mkdir(parents=True,exist_ok=True)
catalog=json.loads((S/'component_catalog.json').read_text(encoding='utf-8'))['components']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert Path(bpy.data.filepath)==source, 'Open the source first in a separate MCP call'
bpy.context.window_manager.windows[0].scene=bpy.data.scenes['组件母版画廊_独立可编辑']
source_hash=sha(source)
palette=ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png';palette_hash=sha(palette)
def tris(col,evaluated=True):
 total=0
 for o in col.objects:
  if o.type!='MESH':continue
  ob=o.evaluated_get(bpy.data.scenes['组件母版画廊_独立可编辑'].view_layers[0].depsgraph) if evaluated else o
  me=ob.to_mesh();me.calc_loop_triangles();total+=len(me.loop_triangles);ob.to_mesh_clear()
 return total
def fingerprint(col):
 vv=[]
 for o in col.objects:
  if o.type=='MESH':vv.extend(tuple(round(v,4) for v in vert.co) for vert in o.data.vertices)
 return hashlib.sha256(json.dumps(sorted(vv),separators=(',',':')).encode()).hexdigest(),len(vv)
# Source per-package files are independent, can be opened alone, no external collection links.
before={}
for e in catalog:
 c=bpy.data.collections[e['collection']];before[e['slug']]=tris(c)
 package=S/'component_packages'/e['slug'];package.mkdir(parents=True,exist_ok=True)
 sc=bpy.data.scenes.new('独立组件_'+e['name_zh']);sc.collection.children.link(c)
 d=bpy.data.cameras.new('组件预览相机');d.type='ORTHO';d.ortho_scale=max(e['bounds_size_m'])*1.8
 cam=bpy.data.objects.new('组件预览相机',d);sc.collection.objects.link(cam);cam.location=(6,-8,7);cam.rotation_euler=(Vector((0,0,e['bounds_size_m'][2]/2))-cam.location).to_track_quat('-Z','Y').to_euler();sc.camera=cam
 ld=bpy.data.lights.new('组件柔光','AREA');ld.energy=1000;ld.size=5;lo=bpy.data.objects.new('组件柔光',ld);sc.collection.objects.link(lo);lo.location=(1,-3,6);lo.rotation_euler=(-lo.location).to_track_quat('-Z','Y').to_euler()
 sc.world=bpy.context.scene.world;sc.render.engine='CYCLES';sc.cycles.samples=24;sc.render.resolution_x=800;sc.render.resolution_y=800
 f=package/(e['slug']+'_source_v017.blend');bpy.data.libraries.write(str(f),{sc},fake_user=True,compress=True)
 e['component_blend']=f.relative_to(ROOT).as_posix();e['component_blend_sha256']=sha(f)
 bpy.data.scenes.remove(sc);bpy.data.objects.remove(cam,do_unlink=True);bpy.data.objects.remove(lo,do_unlink=True)
# Create a separate persisted optimized working file. Original master bytes stay frozen.
bpy.ops.wm.save_as_mainfile(filepath=str(optimized))
reports=[]
for e in catalog:
 c=bpy.data.collections[e['collection']];v_before=sum(len(o.data.vertices) for o in c.objects if o.type=='MESH');zero=0;merged=0
 for o in c.objects:
  if o.type!='MESH':continue
  bpy.context.window_manager.windows[0].scene.view_layers[0].objects.active=o
  # Master collections are in their own scene; evaluated modifiers work via depsgraph.
  dg=bpy.data.scenes['组件母版画廊_独立可编辑'].view_layers[0].depsgraph;evaluated=o.evaluated_get(dg);me=bpy.data.meshes.new_from_object(evaluated,depsgraph=dg,preserve_all_data_layers=True)
  o.modifiers.clear();o.data=me
  bm=bmesh.new();bm.from_mesh(me);nv=len(bm.verts)
  bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001);merged+=nv-len(bm.verts)
  bad=[f for f in bm.faces if f.calc_area()<1e-12];zero+=len(bad)
  if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
  loose=[v for v in bm.verts if not v.link_faces]
  if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
  # Preserve continuous curved surfaces; flat structural/furniture panels stay flat.
  for p in me.polygons:
   if len(p.vertices)>4:p.use_smooth=False
 vv=[v.co.copy() for ob in c.objects if ob.type=='MESH' for v in ob.data.vertices]
 low=Vector(tuple(min(v[k] for v in vv) for k in range(3)));high=Vector(tuple(max(v[k] for v in vv) for k in range(3)))
 shift=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
 for ob in c.objects:
  if ob.type=='MESH':
   for vert in ob.data.vertices:vert.co-=shift
   ob.data.update()
 e['source_bounds_size_m']=e['bounds_size_m'];e['bounds_size_m']=[round(v,6) for v in high-low]
 after=tris(c,False);fp,n=fingerprint(c)
 e['geometry_fingerprint']=fp;e['vertex_count']=n
 reports.append(dict(asset_id=e['component_id'],slug=e['slug'],source_path=source.relative_to(ROOT).as_posix(),optimized_path=optimized.relative_to(ROOT).as_posix(),source_sha256_before=source_hash,operations=dict(evaluate_bevels=True,merge_distance_m=.000001,merged_vertices=merged,zero_area_faces_removed=zero,recalculate_normals=True,internal_faces_preserved='Reusable module sides, undersides, leaves and occluded furniture may be seen from other angles; retained.'),triangles_before=before[e['slug']],triangles_after=after,reduction_ratio=(before[e['slug']]-after)/before[e['slug']],budget=None,budget_source='No explicit triangle budget supplied; no fabricated cap.',zero_reduction_reason='Only safe topology cleanup; no forced Decimate on furniture silhouettes or architectural interfaces.',geometry_fingerprint=fp))
bpy.ops.wm.save_as_mainfile(filepath=str(optimized))

(S/'export/v017/prepare_state.json').write_text(json.dumps(dict(catalog=catalog,reports=reports,source_hash=source_hash,palette_hash=palette_hash),ensure_ascii=False,indent=2),encoding='utf-8')
print('OPTIMIZATION_PREPARED',len(reports))
