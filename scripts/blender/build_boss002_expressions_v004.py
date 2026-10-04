import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';T=B/'source/textures_v004';P=B/'previews/expressions_v004';P.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v003.blend'))
src=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=src
names=['default','suspicious','angry','sleepy','taunting','glitched']
face=bpy.data.collections['02_FACE_default']
ctrl=bpy.data.objects.new('ExpressionController',None);face.objects.link(ctrl);ctrl.empty_display_type='PLAIN_AXES';ctrl.empty_display_size=.12;ctrl.location=(0,0,3.65)
ctrl['expression_index']=0;ctrl.id_properties_ui('expression_index').update(min=0,max=5,description='0 default | 1 suspicious | 2 angry | 3 sleepy | 4 taunting | 5 glitched')
ctrl['expression_names']=' / '.join(names);ctrl['usage']='Set expression_index 0..5; timeline preview changes every 24 frames. Remove preview Action for manual selection.'
image=bpy.data.images.load(str(T/'expressions_atlas.png'),check_existing=True);image.pack()
mat=bpy.data.materials.new('Boss002 Six Expression Atlas');mat.use_nodes=True;mat.surface_render_method='DITHERED';nodes=mat.node_tree.nodes;nodes.clear();links=mat.node_tree.links
out=nodes.new('ShaderNodeOutputMaterial');out.location=(800,0)
mix=nodes.new('ShaderNodeMixShader');mix.location=(580,0);em=nodes.new('ShaderNodeEmission');em.inputs[1].default_value=.85;em.location=(360,0)
tr=nodes.new('ShaderNodeBsdfTransparent');tr.location=(360,-140);tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Linear';tex.extension='CLIP';tex.location=(80,100)
uv=nodes.new('ShaderNodeTexCoord');uv.location=(-720,100);offset=nodes.new('ShaderNodeCombineXYZ');offset.location=(-700,-180);add=nodes.new('ShaderNodeVectorMath');add.operation='ADD';add.location=(-180,100)
for axis,expr in [(0,'(int(e)%3)/3.0'),(1,'-floor(int(e)/3)/2.0')]:
    f=offset.inputs[axis].driver_add('default_value');d=f.driver;d.type='SCRIPTED';v=d.variables.new();v.name='e';v.type='SINGLE_PROP';v.targets[0].id=ctrl;v.targets[0].data_path='["expression_index"]';d.expression=expr
links.new(uv.outputs['UV'],add.inputs[0]);links.new(offset.outputs[0],add.inputs[1]);links.new(add.outputs[0],tex.inputs[0]);links.new(tex.outputs['Color'],em.inputs[0]);links.new(tex.outputs['Alpha'],mix.inputs[0]);links.new(tr.outputs[0],mix.inputs[1]);links.new(em.outputs[0],mix.inputs[2]);links.new(mix.outputs[0],out.inputs[0])
alpha=nodes.new('ShaderNodeMath');alpha.operation='GREATER_THAN';alpha.inputs[1].default_value=.65;links.new(tex.outputs['Alpha'],alpha.inputs[0]);links.new(alpha.outputs[0],mix.inputs[0])
# Fixed registration boxes, same physical scale in all six states; preserve transparent padding.
regions={'large_eye':[10,40,270,285],'round_eye':[275,40,510,285],'mouth':[70,288,452,485]}
poses={'large_eye':(.57,.49,3.055,.98,.94),'round_eye':(-.72,.49,2.91,.74,.77),'mouth':(-.13,.50,2.015,1.42,.79)}
per_boxes={
'large_eye':[[32,90,261,275],[559,113,737,248],[1042,64,1291,279],[39,596,223,753],[551,576,740,794],[1076,587,1260,768]],
'round_eye':[[312,94,495,264],[819,131,981,248],[1320,75,1509,261],[317,624,480,732],[816,570,993,750],[1324,574,1499,756]],
'mouth':[[111,304,408,441],[640,303,903,446],[1156,287,1409,473],[105,804,413,934],[622,775,899,942],[1157,782,1401,953]]}
def driver(socket,values):
    f=socket.driver_add('default_value');d=f.driver;v=d.variables.new();v.name='e';v.type='SINGLE_PROP';v.targets[0].id=ctrl;v.targets[0].data_path='["expression_index"]';d.expression=str(tuple(values))+'[min(5,max(0,int(e)))]'
for name,box in regions.items():
    o=bpy.data.objects['Texture '+name];o.data.materials.clear()
    slotmat=mat.copy();slotmat.name='Boss002 Expressions '+name;slotmat.node_tree.animation_data_clear();ns=slotmat.node_tree.nodes;ls=slotmat.node_tree.links
    slotadd=next(n for n in ns if n.type=='VECT_MATH');slotoff=next(n for n in ns if n.type=='COMBXYZ');slotuv=next(n for n in ns if n.type=='TEX_COORD')
    scale=ns.new('ShaderNodeCombineXYZ');scale.inputs[2].default_value=1;mul=ns.new('ShaderNodeVectorMath');mul.operation='MULTIPLY';ls.new(slotuv.outputs['UV'],mul.inputs[0]);ls.new(scale.outputs[0],mul.inputs[1]);ls.new(mul.outputs[0],slotadd.inputs[0])
    boxes=per_boxes[name]
    driver(slotoff.inputs[0],[b[0]/1536 for b in boxes]);driver(slotoff.inputs[1],[1-b[3]/1024 for b in boxes]);driver(scale.inputs[0],[(b[2]-b[0])/1536 for b in boxes]);driver(scale.inputs[1],[(b[3]-b[1])/1024 for b in boxes]);o.data.materials.append(slotmat)
    cx,y,cz,w,h=poses[name]
    for v,co in zip(o.data.vertices,[(cx+w/2,y,cz-h/2),(cx-w/2,y,cz-h/2),(cx-w/2,y,cz+h/2),(cx+w/2,y,cz+h/2)]):v.co=co
    coords=[(0,0),(1,0),(1,1),(0,1)]
    for i in range(4):o.data.uv_layers.active.data[i].uv=coords[i]
    o['expression_slot']=name;o['flat_sprite']=True
    # Scale sprite extents about each fixed facial anchor to preserve artwork aspect ratios.
    center=Vector((cx,y,cz))
    for v in o.data.vertices:v.co-=center
    o.location=center
    for axis,vals in [(0,[(b[2]-b[0])/260 if name=='large_eye' else (b[2]-b[0])/235 if name=='round_eye' else (b[2]-b[0])/382 for b in boxes]),(2,[(b[3]-b[1])/245 if name!='mouth' else (b[3]-b[1])/197 for b in boxes])]:
        f=o.driver_add('scale',axis);d=f.driver;v=d.variables.new();v.name='e';v.targets[0].id=ctrl;v.targets[0].data_path='["expression_index"]';d.expression=str(tuple(vals))+'[min(5,max(0,int(e)))]'
for i in range(7):
    frame=1+i*24;ctrl['expression_index']=i%6;ctrl.keyframe_insert(data_path='["expression_index"]',frame=frame)
    for sc in [src,bpy.data.scenes['BOSS002_STUDIO']]:sc.timeline_markers.new(names[i%6],frame=frame);sc.frame_end=168;sc.render.fps=24
action=ctrl.animation_data.action;action.name='BOSS002_expression_switch_preview'
for f in action.fcurves:
    for k in f.keyframe_points:k.interpolation='CONSTANT'
src.frame_set(1);src['asset_version']='v004';src['expression_count']=6;src['expression_preview']='Only material UV selection; no skeleton or gameplay animation'
def mesh_digest(o):
    data={'v':[list(v.co) for v in o.data.vertices],'p':[list(p.vertices) for p in o.data.polygons],'matrix':[list(r) for r in o.matrix_world]}
    return hashlib.sha256(json.dumps(data).encode()).hexdigest()
body={o.name:mesh_digest(o) for o in src.objects if o.type=='MESH' and not o.name.startswith('Texture ')}
tri=0
for o in src.objects:
    if o.type=='MESH':o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
assert tri==18144
manifest={'asset_id':'ENM-BOSS-MONITOR002-3D','version':'v004','atlas':'source/textures_v004/expressions_atlas.png','atlas_size':[1536,1024],'grid':[3,2],'expression_property':'ExpressionController[expression_index]','expressions':[{'index':i,'id':n,'preview_frame':1+24*i,'atlas_cell':[i%3,i//3]} for i,n in enumerate(names)],'regions_pixels_within_cell':regions,'sampling':'constant / discrete, no crossfade','preview_action':action.name,'runtime_binding':'not integrated; JSON gives row/column and UV contract for future material animation','triangles':tri,'rigged':False,'body_mesh_digests':body}
manifest['per_expression_slot_boxes_pixels']=per_boxes
(B/'source/expression_library_v004.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.object.select_all(action='DESELECT');ctrl.select_set(True);bpy.context.view_layer.objects.active=ctrl
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v004.blend'))
scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=scene;scene.cycles.samples=24;cam=scene.camera
cam.location=(0,12,2.5);cam.rotation_euler=(Vector((0,0,2.5))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=3.15
scene.render.resolution_x=900;scene.render.resolution_y=900
for i,n in enumerate(names):
    scene.frame_set(1+24*i);scene.render.filepath=str(P/(n+'.png'));bpy.ops.render.render(write_still=True)
scene.frame_set(1);cam.location=(4,11,6);cam.rotation_euler=(Vector((-.2,0,1.7))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=8.1;scene.render.resolution_x=1500;scene.render.resolution_y=1050;scene.render.filepath=str(P/'overview.png');bpy.ops.render.render(write_still=True)
print('EXPRESSION_LIBRARY_SAVED',tri)
