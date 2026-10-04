import bpy, math, json
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]; B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v001.blend'))
src=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=src
coll=bpy.data.collections['04_GLOVES_default'];white=bpy.data.materials['Warm ivory gloves']
def stats():
    dg=bpy.context.evaluated_depsgraph_get();out={};basefaces=0
    for o in src.objects:
        if o.type not in ('MESH','CURVE','FONT'):continue
        if o.type=='MESH':basefaces+=len(o.data.polygons)
        e=o.evaluated_get(dg);m=e.to_mesh();m.calc_loop_triangles();out[o.name]=len(m.loop_triangles);e.to_mesh_clear()
    return {'evaluated_triangles':sum(out.values()),'base_mesh_polygons':basefaces,'glove_triangles':{k:v for k,v in out.items() if k.startswith('Sculpted glove')},'objects':out}
before=stats()
for o in list(coll.objects):
    if o.name.startswith(('Sculpted glove','Glove stitch')):bpy.data.objects.remove(o,do_unlink=True)
def ellipsoid(name,loc,scale):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=loc)
    o=bpy.context.object;o.name=name;o.scale=scale
    for c in list(o.users_collection):c.objects.unlink(o)
    coll.objects.link(o);o.data.materials.append(white)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return o
def finger(name,a,b,r):
    a,b=Vector(a),Vector(b);o=ellipsoid(name,(a+b)/2,(r,r*.8,(b-a).length/2+r))
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
# Palm planes are horizontal XY, palm down, all fingers extend along arm X.
for sign,side in [(-1,'R'),(1,'L')]:
    y=-.08;z=2.01
    pieces=[ellipsoid('Palm', (sign*2.53,y,z),(.30,.23,.095))]
    specs=[(2.70,y-.145,3.12,y-.26,.077),(2.76,y,3.25,y,.083),(2.70,y+.145,3.09,y+.255,.078)]
    for i,(x1,y1,x2,y2,r) in enumerate(specs):pieces.append(finger('Finger'+str(i+1),(sign*x1,y1,z),(sign*x2,y2,z),r))
    pieces.append(finger('Thumb',(sign*2.44,y+.17,z),(sign*2.66,y+.43,z-.008),.093))
    bpy.ops.object.select_all(action='DESELECT')
    for o in pieces:o.select_set(True)
    bpy.context.view_layer.objects.active=pieces[0];bpy.ops.object.join();o=bpy.context.object;o.name='Sculpted glove '+side
    mod=o.modifiers.new('Unified four finger glove','REMESH');mod.mode='VOXEL';mod.voxel_size=.014;mod.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=o.modifiers.new('Smooth cloth','SMOOTH');mod.factor=.65;mod.iterations=3;bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=o.modifiers.new('Sculpt surface','SUBSURF');mod.levels=1
    o['finger_count']=4;o['thumb_count']=1;o['pose']='open_flat_palm_down';o['slot_id']='04_GLOVES';o['variant_id']='default'
    for p in o.data.polygons:p.use_smooth=True
src['stage']='authored_unrigged';src['asset_version']='v002';src['hands']='four fingers total: 1 thumb + 3 fingers; open, palm down'
after=stats()
unchanged={k:v for k,v in before['objects'].items() if not k.startswith(('Sculpted glove','Glove stitch'))}
assert all(after['objects'].get(k)==v for k,v in unchanged.items())
report={'before':{k:v for k,v in before.items() if k!='objects'},'after':{k:v for k,v in after.items() if k!='objects'},'unrelated_objects_unchanged':True,'rigs':len(bpy.data.armatures),'actions':len(bpy.data.actions),'pose':'open flat, palm down, 1 thumb + 3 fingers','props':'retained in original positions; open hands do not grip props'}
out=B/'previews/hands_v002';out.mkdir(exist_ok=True)
(out/'audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v002.blend'))
scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=scene;cam=scene.camera;scene.cycles.samples=32
def render(name,loc,target,scale):
    cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
    scene.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
render('overview',(4,11,7),(-.2,0,1.7),8.1)
render('hand_detail',(3.8,3.8,7),(2.73,-.02,2.01),1.65)
render('hands_top',(0,0,12),(0,0,1.7),7.9)
print(json.dumps(report,indent=2))
