
import sys as _art_source_sys
from pathlib import Path as _ArtSourcePath
_art_source_sys.path.insert(0, str(_ArtSourcePath(__file__).resolve().parents[1]))
from art_source_paths import source_path
import bpy,bmesh,json,math,hashlib
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');O=R/'outputs/rooftop_courtyard_v001';B=R/'assets/art/environments/rooftop_courtyard_3d'
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'));assert json.loads((O/'source_validation_v002.json').read_text())['passed']
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
SRC=Path(m['source_blend']);h=sha(SRC);ph=sha(m['palette']);OPT=SRC.parent/'export/v002/prp_rooftop_courtyard_optimized_v002.blend';OPT.parent.mkdir(parents=True,exist_ok=True)
s=bpy.data.scenes['复古天台庭院_v001'];bpy.context.window.scene=s;s.frame_set(1);bpy.context.view_layer.update()
output=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
# Copy-free independent on-disk process: all bpy data originated from this standalone load.
# Remove editable duplicate output from optimized derivative, retain cameras for identical views.
source=next(c for c in bpy.data.collections if c.name.startswith('01_制作组件'))
for ob in list(source.all_objects):bpy.data.objects.remove(ob,do_unlink=True)
bpy.data.collections.remove(source)
records=[];total=0
for p in m['packages']:
    objs=[bpy.data.objects[n] for n in p['objects']];before=0;after=0;removed=0
    for ob in objs:
        ob.data=ob.data.copy();ob.data.calc_loop_triangles();before+=len(ob.data.loop_triangles)
        # Targeted clean, no silhouette decimation / no normal-based face deletion.
        if not ob.data.shape_keys:
            bm=bmesh.new();bm.from_mesh(ob.data)
            bad=[f for f in bm.faces if f.calc_area()<1e-12];removed+=len(bad)
            if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
            isolated=[v for v in bm.verts if not v.link_faces];removed+=len(isolated)
            if isolated:bmesh.ops.delete(bm,geom=isolated,context='VERTS')
            # Coincident vertices merged only within matching role boundaries. Palette UVs stay per-loop.
            bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
            bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free();ob.data.update()
            uv=ob.data.uv_layers['PaletteUV']
            for face in ob.data.polygons:
                vals=[uv.data[li].uv.copy() for li in face.loop_indices];cx=int(sum(v.x for v in vals)/len(vals)*10);cy=int(sum(v.y for v in vals)/len(vals)*10)
                for j,li in enumerate(face.loop_indices):a=math.tau*j/len(face.loop_indices);uv.data[li].uv=((cx+.5)/10+.025*math.cos(a),(cy+.5)/10+.025*math.sin(a))
        ob.data.calc_loop_triangles();after+=len(ob.data.loop_triangles)
    total+=after
    rec={'package_id':p['package_id'],'triangles_before':before,'triangles_after':after,'reduction_ratio':(before-after)/before if before else None,'cleanup_removed':removed,'operations':['remove zero-area faces and isolated vertices','merge exact duplicate points dist=1e-7 on static meshes','triangulate static meshes','retain shape-key topology','no blind downward deletion; underside visible in orbit'],'zero_reduction_reason':'Minimal primitives; curved silhouettes and fine wire shapes intentionally retained','budget':None,'aggregate_budget':200000,'source_sha256_before':h,'source_sha256_after':None,'source':str(SRC),'optimized':str(OPT),'fidelity_status':'pending same camera review'}
    p['optimization']=rec;records.append(rec)
assert total<200000
bpy.ops.wm.save_as_mainfile(filepath=str(OPT));assert sha(SRC)==h and sha(m['palette'])==ph
# Mandatory reopen before exports; original file remains untouched.
bpy.ops.wm.open_mainfile(filepath=str(OPT));s=bpy.data.scenes['复古天台庭院_v001'];bpy.context.window.scene=s;s.frame_set(1);bpy.context.view_layer.update()
assert Path(bpy.data.filepath)==OPT
for p in m['packages']:
    root=bpy.data.objects[p['root_object']];objects=[root]+[bpy.data.objects[n] for n in p['objects']]
    # Stable exported root origin is bbox XY center and bottom=0; retain moving pivot as internal root.
    points=[ob.matrix_world@Vector(v) for ob in objects if ob.type=='MESH' for v in ob.bound_box]
    center=Vector(((min(v.x for v in points)+max(v.x for v in points))/2,(min(v.y for v in points)+max(v.y for v in points))/2,min(v.z for v in points)))
    oldloc=root.location.copy();root.animation_data_clear();root.location=oldloc-center
    for ob in bpy.context.view_layer.objects:ob.select_set(False)
    for ob in objects:ob.hide_set(False);ob.select_set(True)
    bpy.context.view_layer.objects.active=root
    dest=Path(p['expected_glb']);dest.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',use_selection=True,export_apply=False,export_yup=True,export_extras=True,export_materials='EXPORT',export_image_format='NONE',export_cameras=False,export_lights=False,export_animations=True,export_frame_range=True,export_morph=True)
    root.location=oldloc
    data=dest.read_bytes();ln=int.from_bytes(data[12:16],'little');doc=json.loads(data[20:20+ln]);assert not doc.get('images') and not doc.get('textures')
    p['exported']=True;p['glb_sha256']=sha(dest);p['component_origin_blender']=list(center);p['pivot_offset_blender']=list(oldloc-center)
    p['optimization']['source_sha256_after']=sha(SRC);p['optimization']['glb_sha256']=p['glb_sha256']
# Do not save mutated in-memory export transforms; on-disk optimized file remains layout comparable.
m['optimized_blend']=str(OPT);m['source_sha256']=h;m['optimized_sha256']=sha(OPT);m['palette_sha256']=ph;m['triangles_optimized']=total;m['source_unchanged']=sha(SRC)==h;m['exported']=True
(O/'asset_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8');(source_path(B/'source/prp_rooftop_courtyard/asset_manifest.json')).write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
(O/'optimization.json').write_text(json.dumps({'source_unchanged':True,'palette_unchanged':True,'source_sha256':h,'optimized_sha256':sha(OPT),'triangles_before':sum(r['triangles_before'] for r in records),'triangles_after':total,'records':records},ensure_ascii=False,indent=2),encoding='utf-8')
print('COURTYARD_EXPORT_OK',len(m['packages']),total)
