import bpy, math,json
from mathutils import Vector
from pathlib import Path
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';T=B/'source/textures_v003'
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v002.blend'))
src=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=src
def signature(o):return [list(o.matrix_world[i]) for i in range(4)]
for o in list(src.objects):
    if o.type=='FONT' or o.get('face_flat') or o.name.startswith(('CRT scanline','Typing cursor','Sculpted glove')):bpy.data.objects.remove(o,do_unlink=True)
coll=bpy.data.collections['04_GLOVES_default'];white=bpy.data.materials['Warm ivory gloves']
def addmesh(n,v,f):
    m=bpy.data.meshes.new(n);m.from_pydata(v,[],f);m.update();o=bpy.data.objects.new(n,m);coll.objects.link(o);m.materials.append(white);return o
def capsule(n,a,b,r):
    a,b=Vector(a),Vector(b);axis=(b-a).normalized();u=axis.cross(Vector((0,0,1))).normalized();v=axis.cross(u).normalized();vs=[];rings=10;seg=16
    for j in range(rings+1):
        phi=-math.pi/2+math.pi*j/rings;center=a if j<=rings/2 else b
        for i in range(seg):
            th=2*math.pi*i/seg;p=center+axis*r*math.sin(phi)+(u*math.cos(th)+v*math.sin(th))*r*math.cos(phi);vs.append(tuple(p))
    fs=[(j*seg+i,j*seg+(i+1)%seg,(j+1)*seg+(i+1)%seg,(j+1)*seg+i) for j in range(rings) for i in range(seg)]
    return addmesh(n,vs,fs)
for sign,side in [(-1,'R'),(1,'L')]:
    y=-.08;z=2.01;bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=(sign*2.52,y,z));p=bpy.context.object;p.scale=(.30,.235,.105)
    for c in list(p.users_collection):c.objects.unlink(p)
    coll.objects.link(p);p.data.materials.append(white);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);parts=[p]
    for i,(x1,y1,x2,y2,r) in enumerate([(2.70,y-.145,3.04,y-.25,.088),(2.74,y,3.16,y,.097),(2.70,y+.145,3.04,y+.25,.09),(2.43,y+.16,2.64,y+.36,.108)]):
        parts.append(capsule('Round digit '+str(i),(sign*x1,y1,z),(sign*x2,y2,z),r))
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    bpy.context.view_layer.objects.active=p;bpy.ops.object.join();p.name='Sculpted glove '+side
    m=p.modifiers.new('Weld rounded fingers','REMESH');m.mode='VOXEL';m.voxel_size=.019;m.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=m.name)
    m=p.modifiers.new('Soft cloth','SMOOTH');m.factor=.65;m.iterations=3;bpy.ops.object.modifier_apply(modifier=m.name)
    p['finger_count']=4;p['thumb_count']=1;p['pose']='open_flat';p['slot_id']='04_GLOVES'
    for f in p.data.polygons:f.use_smooth=True
# Reduce curve tessellation before converting so cable silhouette has an intentional budget.
for o in list(src.objects):
    for m in list(o.modifiers):
        if m.type=='BEVEL':m.segments=1
        if m.type=='SUBSURF':o.modifiers.remove(m)
    if o.type=='CURVE':
        o.data.bevel_resolution=1;o.data.resolution_u=8
        for sp in o.data.splines:
            if sp.type=='POLY' and len(sp.points)>200:
                pts=[p.co.copy() for p in sp.points];new=o.data.splines.new('POLY');sel=pts[::3]
                if sel[-1]!=pts[-1]:sel.append(pts[-1])
                new.points.add(len(sel)-1)
                for p,q in zip(new.points,sel):p.co=q
                o.data.splines.remove(sp)
bpy.ops.object.select_all(action='DESELECT')
for o in src.objects:o.select_set(o.type in ('MESH','CURVE'))
bpy.context.view_layer.objects.active=next(o for o in src.objects if o.type=='MESH');bpy.ops.object.convert(target='MESH')
def triangles(o):o.data.calc_loop_triangles();return len(o.data.loop_triangles)
def group(o):
    for c in o.users_collection:
        if c.name[:2].isdigit():return c.name[:2]
    return '00'
budgets={'01':3600,'03':4300,'04':4600,'05':2200,'06':1800,'07':2000}
counts={}
for key,budget in budgets.items():
    obs=[o for o in src.objects if group(o)==key];total=sum(triangles(o) for o in obs);ratio=min(1,budget/max(1,total))
    for o in obs:
        if ratio<1 and triangles(o)>16:
            bpy.context.view_layer.objects.active=o;m=o.modifiers.new('Game triangle budget','DECIMATE');m.ratio=ratio;m.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=m.name)
    counts[key]=sum(triangles(o) for o in obs)
    for o in obs:
        if key in ('01','05','07'):
            bpy.context.view_layer.objects.active=o
            m=o.modifiers.new('Restore weighted normals','WEIGHTED_NORMAL');m.keep_sharp=True
            bpy.ops.object.modifier_apply(modifier=m.name)
# Texture planes: exact UVs, alpha handles empty space. Facial atlas is not geometry.
def textured(name,path,alpha=False,emit=.8):
    m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;n.clear();out=n.new('ShaderNodeOutputMaterial');tex=n.new('ShaderNodeTexImage');im=bpy.data.images.load(str(path),check_existing=True);tex.image=im;im.pack();em=n.new('ShaderNodeEmission');em.inputs[1].default_value=emit;m.node_tree.links.new(tex.outputs['Color'],em.inputs[0])
    if alpha:
        tr=n.new('ShaderNodeBsdfTransparent');mix=n.new('ShaderNodeMixShader');m.node_tree.links.new(tex.outputs['Alpha'],mix.inputs[0]);m.node_tree.links.new(tr.outputs[0],mix.inputs[1]);m.node_tree.links.new(em.outputs[0],mix.inputs[2]);m.node_tree.links.new(mix.outputs[0],out.inputs[0]);m.surface_render_method='DITHERED'
    else:m.node_tree.links.new(em.outputs[0],out.inputs[0])
    return m
sm=textured('Image2 green terminal',T/'screen_code.png',False,1.1);fm=textured('Image2 flat facial atlas',T/'face_atlas.png',True,.85)
def quad(name,cx,y,cz,w,h,uv,mat,collection):
    # Positive screen u goes towards Blender -X, correct from +Y viewer.
    v=[(cx+w/2,y,cz-h/2),(cx-w/2,y,cz-h/2),(cx-w/2,y,cz+h/2),(cx+w/2,y,cz+h/2)]
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],[(0,1,2,3)]);me.update();ob=bpy.data.objects.new(name,me);collection.objects.link(ob);me.materials.append(mat)
    u0,v0,u1,v1=uv;layer=me.uv_layers.new();coords=[(u0,v0),(u1,v0),(u1,v1),(u0,v1)]
    for i in range(4):layer.data[i].uv=coords[i]
    return ob
quad('Screen code texture',0,.174,2.045,1.355,2.34,(0,0,1,1),sm,bpy.data.collections['01_MONITOR_default'])
face=bpy.data.collections['02_FACE_default']
# atlas crop coordinates supplied from pixel alpha bounding boxes
boxes=json.loads((T/'atlas_regions.json').read_text())
for name,cx,cz,w,h in [('large_eye',.57,3.06,.91,.77),('round_eye',-.72,2.92,.74,.75),('mouth',-.13,2.045,1.38,.62)]:
    x0,y0,x1,y1=boxes[name];uv=(x0/1024,1-y1/1024,x1/1024,1-y0/1024);o=quad('Texture '+name,cx,.49,cz,w,h,uv,fm,face);o['face_flat']=True
total=sum(triangles(o) for o in src.objects if o.type=='MESH');assert total<20000,total
src['asset_version']='v003';src['total_triangles']=total;src['texture_model']='gpt-image-2';src['stage']='authored_unrigged_optimized'
out=B/'previews/optimized_v003';out.mkdir(exist_ok=True)
report={'triangles':total,'group_triangles':counts,'limit':20000,'under_limit':total<20000,'armatures':len(bpy.data.armatures),'actions':len(bpy.data.actions),'text_objects':sum(o.type=='FONT' for o in src.objects),'unapplied_modifiers':sum(len(o.modifiers) for o in src.objects),'texture_model':'gpt-image-2','face_triangles':6,'gloves':{o.name:triangles(o) for o in src.objects if o.name.startswith('Sculpted glove')}}
(out/'audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
bpy.ops.object.select_all(action='DESELECT');bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v003.blend'))
scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=scene;cam=scene.camera;scene.cycles.samples=32
def render(name,loc,target,scale):
    cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;scene.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
render('overview',(4,11,6),(-.2,0,1.7),8.1)
render('hand_detail',(3.8,3.8,7),(2.73,-.02,2.01),1.65)
render('face_detail',(0,12,2.6),(0,0,2.18),3.5)
print(json.dumps(report,indent=2))
