"""02b: clean each independent output, persist/reopen optimized source, export GLB."""
import bpy, bmesh, json, hashlib, struct, sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(R/'scripts'))
from workspace_paths import work_path
D=R/'art_source/environments/tower_zones/expedition/source/room_types/boss_room_B/v027'
W=work_path('outputs/boss_room02_import/export.json').parent
catalog=json.loads((D/'component_catalog.json').read_text('utf8'))['components']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
protected=json.loads((W/'protected_baseline.json').read_text('utf8'))
records=[]
for c in catalog:
 slug=c['slug'];src=Path(c['component_blend']);bpy.ops.wm.open_mainfile(filepath=str(src))
 col=bpy.data.collections[c['collection']];keep=list(col.objects)
 for ob in list(bpy.data.objects):
  if ob not in keep:bpy.data.objects.remove(ob,do_unlink=True)
 # Output collections only. Never retain editable parts, presentation or room instances.
 for child in list(bpy.context.scene.collection.children):bpy.context.scene.collection.children.unlink(child)
 bpy.context.scene.collection.children.link(col)
 before=after=0;ops=[];points=[];geom=[]
 for ob in keep:
  ob.data=ob.data.copy()
  for i,m in enumerate(ob.data.materials):ob.data.materials[i]=m.copy()
  me=ob.data;me.calc_loop_triangles();before+=len(me.loop_triangles)
  old_points=[tuple(v.co) for v in me.vertices]
  bm=bmesh.new();bm.from_mesh(me)
  zero=[f for f in bm.faces if f.calc_area()<1e-12]
  if zero:bmesh.ops.delete(bm,geom=zero,context='FACES')
  loose=[v for v in bm.verts if not v.link_faces]
  if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
  # Only dissolve truly coplanar edges with continuous UV, material and normals.
  n0=len(bm.faces)
  bmesh.ops.dissolve_limit(bm,angle_limit=1e-5,verts=list(bm.verts),edges=list(bm.edges),delimit={'NORMAL','MATERIAL','SEAM','SHARP','UV'})
  dissolved=n0-len(bm.faces)
  # Duplicate-face audit keys include material and loop UV; retain opposite faces.
  uv=bm.loops.layers.uv.active;seen=set();duplicates=[]
  for f in bm.faces:
   key=(f.material_index,tuple(round(x,7) for x in f.normal),tuple(sorted((tuple(round(x,7) for x in l.vert.co),tuple(round(x,7) for x in l[uv].uv) if uv else ()) for l in f.loops)))
   if key in seen:duplicates.append(f)
   else:seen.add(key)
  if duplicates:bmesh.ops.delete(bm,geom=duplicates,context='FACES')
  # No global decimation: doors, silhouette ribs, cables and palette islands are interfaces.
  bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update();me.calc_loop_triangles();after+=len(me.loop_triangles)
  points.extend(tuple(ob.matrix_basis@v.co) for v in me.vertices)
  geom.append({'mesh':ob.name,'original_points_retained':all(tuple(v.co) in set(old_points) for v in me.vertices)})
  ops.append({'mesh':ob.name,'zero_area_faces_removed':len(zero),'loose_vertices_removed':len(loose),'duplicate_faces_removed':len(duplicates),'coplanar_faces_dissolved':dissolved,'dissolve_angle_rad':1e-5,'internal_faces_removed':0,'retained_reason':'Undersides, backs and open-frame interiors may be seen from deep shaft. UV/hard-edge delimiters lock remaining subdivision; preserve silhouette and interfaces.'})
 opt=src.parent/'export/v027'/('env_boss_room02_'+slug+'_optimized_v027.blend');opt.parent.mkdir(parents=True,exist_ok=True)
 bpy.context.scene['role']='optimized';bpy.context.scene['asset_id']=c['component_id'];bpy.context.scene['source_sha256']=protected[str(src)]
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.save_as_mainfile(filepath=str(opt));bpy.ops.wm.open_mainfile(filepath=str(opt));assert Path(bpy.data.filepath)==opt
 glb=R/'assets/art/environments/tower_zones/expedition/components/room_type_components/boss_room_02'/slug/('env_boss_room02_'+slug+'_visual_top3d.glb');glb.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.object.select_all(action='DESELECT')
 for ob in bpy.data.collections[c['collection']].objects:ob.select_set(True)
 bpy.context.view_layer.objects.active=next(iter(bpy.data.collections[c['collection']].objects))
 bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_image_format='NONE',export_extras=True,export_cameras=False,export_lights=False,export_animations=False)
 data=glb.read_bytes();n=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+n]);assert not g.get('images') and not g.get('textures')
 count=sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes'] for p in m['primitives']);assert count==after
 rec=dict(c,asset_id=c['component_id'],source_path=src.relative_to(R).as_posix(),source_sha256_before=protected[str(src)],source_sha256_after=sha(src),optimized_path=opt.relative_to(R).as_posix(),optimized_sha256=sha(opt),optimized_reopened_before_export=True,role='optimized',operations=ops,triangles_before=before,triangles_after=after,reduction_ratio=(before-after)/before,budget=None,budget_source='No approved numeric per-component budget. User requires effective face control with authored silhouette preservation.',fidelity_geometry=geom,glb_path=glb.relative_to(R).as_posix(),glb_sha256=sha(glb),export_triangles=count,prefab_path='assets/art/environments/tower_zones/expedition/runtime/room_type_components/boss_room_02/'+slug+'/env_boss_room02_'+slug+'_root_top3d.tscn',coordinate_contract={'mapping':'(x,y,z) Blender -> (x,z,-y) Godot, exporter Y-up once','front_axis_godot':'+Z','unit':'meter'},runtime_integrated=False)
 assert rec['source_sha256_before']==rec['source_sha256_after']
 records.append(rec);print('EXPORTED',slug,before,after,flush=True)
assert all(sha(Path(p))==h for p,h in protected.items())
(D/'import_manifest.json').write_text(json.dumps({'version':'v027','role':'optimized_component_export','source_unchanged':True,'protected_sources':protected,'components':records,'runtime_integrated':False},ensure_ascii=False,indent=2),encoding='utf8')
print('BOSS_ROOM02_EXPORT_OK',len(records),sum(r['triangles_before'] for r in records),sum(r['triangles_after'] for r in records))
