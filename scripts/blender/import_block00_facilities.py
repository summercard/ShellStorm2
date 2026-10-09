"""Protect authoring sources, optimize independent meshes, reopen, export each facility."""
import bpy,bmesh,json,hashlib,math,struct
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
B=R/'assets/art/environments/master_office_3d'
OUT=B/'source/env_block00_story_rooms/export/v001';OUT.mkdir(parents=True,exist_ok=True)
sources=[B/'source/env_father_office/v002/env_father_office_source_v002.blend',B/'source/env_block00_story_rooms/v001/env_block00_story_rooms_source_v001.blend']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
protected={str(p):sha(p) for p in sources}
exclude={'wall_panel','wall_door','floor_panel','floor_fractured'}
records=[]
bpy.ops.wm.read_factory_settings(use_empty=True)
for src in sources:
 catalog=json.loads((src.parent/'component_catalog.json').read_text(encoding='utf8'))
 for d in catalog:
  if d['slug'] in exclude:continue
  with bpy.data.libraries.load(str(src),link=False) as (a,z):z.collections=[d['collection']]
  original=z.collections[0]
  coll=bpy.data.collections.new('EXPORT_'+d['slug']);bpy.context.scene.collection.children.link(coll)
  before=after=0;ops=[];bb=[]
  for old in list(original.all_objects):
   if old.type!='MESH':continue
   obj=bpy.data.objects.new(old.name,old.data.copy());coll.objects.link(obj)
   obj.matrix_world=old.matrix_basis.copy()
   for i,m in enumerate(obj.data.materials):
    if m:obj.data.materials[i]=m.copy()
   mesh=obj.data;mesh.calc_loop_triangles();before+=len(mesh.loop_triangles)
   bm=bmesh.new();bm.from_mesh(mesh)
   # Face-island PaletteUV means vertices must remain split across UV seams.
   isolated=[v for v in bm.verts if not v.link_faces]
   zero=[f for f in bm.faces if f.calc_area()<1e-12]
   if zero:bmesh.ops.delete(bm,geom=zero,context='FACES')
   if isolated:bmesh.ops.delete(bm,geom=isolated,context='VERTS')
   # Dissolve only coplanar connected edges with continuous UV and material.
   n0=len(bm.faces)
   bmesh.ops.dissolve_limit(bm,angle_limit=0.00001,verts=list(bm.verts),edges=list(bm.edges),delimit={'NORMAL','MATERIAL','SEAM','SHARP','UV'})
   dissolved=n0-len(bm.faces)
   bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free();mesh.update();mesh.calc_loop_triangles();after+=len(mesh.loop_triangles)
   ops.append({'mesh':obj.name,'removed_zero_area':len(zero),'removed_isolated_vertices':len(isolated),'coplanar_faces_dissolved':dissolved,'dissolve_angle_rad':.00001,'preserve_delimiters':['NORMAL','MATERIAL','SEAM','SHARP','UV'],'internal_faces_removed':0,'reason':'Back/bottom surfaces can be visible when reused; retain. Per-face palette UV seams lock connected simplification; no silhouette decimation.'})
   bb.extend([list(obj.matrix_world@Vector(v)) for v in obj.bound_box])
  rid=('ENV-BLOCK00-WALL-FRACTURED' if d['slug']=='wall_fractured' else 'PRP-BLOCK00-'+d['slug'].replace('_','-').upper())
  prefix='env_' if d['slug']=='wall_fractured' else 'prp_'
  stem=prefix+'block00_'+d['slug']
  glb=B/'components'/stem/(stem+'_visual.glb');glb.parent.mkdir(parents=True,exist_ok=True)
  runtime=B/'runtime'/stem/(stem+'_root.tscn')
  records.append(dict(d,asset_id=rid,source_path=str(src.relative_to(R)).replace('\\','/'),source_sha256_before=protected[str(src)],optimized_collection=coll.name,triangles_before=before,triangles_after=after,reduction_ratio=(before-after)/before,budget=None,budget_source='No approved numeric per-component budget; preserve authored low-poly silhouette',operations=ops,glb_path=str(glb.relative_to(R)).replace('\\','/'),prefab_path=str(runtime.relative_to(R)).replace('\\','/'),bounds_min=[min(p[i] for p in bb) for i in range(3)],bounds_max=[max(p[i] for p in bb) for i in range(3)]))
  bpy.data.collections.remove(original)
opt=OUT/'block00_facilities_optimized_v001.blend'
scene=bpy.context.scene;scene['role']='optimized';scene['protected_sources']=json.dumps(protected)
bpy.ops.wm.save_as_mainfile(filepath=str(opt))
bpy.ops.wm.open_mainfile(filepath=str(opt))
assert Path(bpy.data.filepath)==opt
for d in records:
 bpy.ops.object.select_all(action='DESELECT')
 c=bpy.data.collections[d['optimized_collection']]
 for o in c.objects:o.select_set(True)
 bpy.context.view_layer.objects.active=next(iter(c.objects))
 bpy.ops.export_scene.gltf(filepath=str(R/d['glb_path']),export_format='GLB',use_selection=True,export_image_format='NONE',export_yup=True,export_cameras=False,export_lights=False,export_animations=False)
 data=(R/d['glb_path']).read_bytes();n=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+n]);assert not g.get('images') and not g.get('textures')
 count=sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes'] for p in m['primitives']);assert count==d['triangles_after'],(d['slug'],count,d['triangles_after'])
 d.update(optimized_path=str(opt.relative_to(R)).replace('\\','/'),optimized_sha256=sha(opt),source_sha256_after=sha(R/d['source_path']),glb_sha256=sha(R/d['glb_path']),export_triangles=count,optimized_reopened_before_export=True,role='optimized',fidelity_acceptance='pending')
 assert d['source_sha256_before']==d['source_sha256_after']
assert all(sha(Path(p))==h for p,h in protected.items())
(OUT/'import_manifest.json').write_text(json.dumps({'schema':'shellstorm2.block00.facilities.import','protected_sources':protected,'components':records,'source_unchanged':True,'runtime_integrated':False},ensure_ascii=False,indent=2),encoding='utf8')
print('BLOCK00_COMPONENT_EXPORT_OK',len(records),sum(d['triangles_before'] for d in records),sum(d['triangles_after'] for d in records))
