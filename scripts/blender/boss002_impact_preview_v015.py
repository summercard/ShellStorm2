"""Hand-drawn atlas cards and short cyan/magenta interference accents."""
studio=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=studio
fx=bpy.data.collections.new('BOSS002_IMPACT_PREVIEW');studio.collection.children.link(fx)
fx['preview_only']=True;fx['export']=False;fx['impact_frame']=33
fx['style']='image-2 hand-drawn 2D impact + cyan/magenta electronic interference'
atlas=bpy.data.images.load(str(B/'textures/impact_v014/impact_atlas.png'));atlas.pack()
mat=bpy.data.materials.new('PREVIEW_HandDrawnImpactAtlas');mat.use_nodes=True
nodes=mat.node_tree.nodes;nodes.clear();tex=nodes.new('ShaderNodeTexImage');tex.image=atlas
transparent=nodes.new('ShaderNodeBsdfTransparent');emit=nodes.new('ShaderNodeEmission');emit.inputs['Strength'].default_value=1.1
mix=nodes.new('ShaderNodeMixShader');out=nodes.new('ShaderNodeOutputMaterial');links=mat.node_tree.links
links.new(tex.outputs['Color'],emit.inputs['Color']);links.new(tex.outputs['Alpha'],mix.inputs[0]);links.new(transparent.outputs[0],mix.inputs[1]);links.new(emit.outputs[0],mix.inputs[2]);links.new(mix.outputs[0],out.inputs[0])
def center_at(frame):
 studio.frame_set(frame);ob=bpy.data.objects['Keyboard outer shell'];ev=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();c=sum((ev.matrix_world@v.co for v in me.vertices),Vector())/len(me.vertices);ev.to_mesh_clear();return c
origin=center_at(33);origin.z=.06
def sprite(name,cell,ground=False):
 mesh=bpy.data.meshes.new(name);mesh.from_pydata([(-.5,-.5,0),(.5,-.5,0),(.5,.5,0),(-.5,.5,0)],[],[(0,1,2,3)])
 uv=mesh.uv_layers.new();cx=cell%2;cy=1-cell//2
 for loop,coord in zip(uv.data,[(0,0),(1,0),(1,1),(0,1)]):loop.uv=((cx+coord[0])*.5,(cy+coord[1])*.5)
 ob=bpy.data.objects.new(name,mesh);fx.objects.link(ob);mesh.materials.append(mat);ob['preview_only']=True;ob['export']=False;ob.visible_shadow=False
 if not ground:ob.rotation_euler=(Vector((5,12,5.5))-origin).to_track_quat('Z','Y').to_euler()
 return ob
def key(ob,frame,loc,size):
 ob.location=loc;ob.scale=(size,size,size);ob.keyframe_insert('location',frame=frame);ob.keyframe_insert('scale',frame=frame)
def envelope(ob,start,peak,end,loc,size):
 size*=1.65
 key(ob,1,loc,0);key(ob,start-1,loc,0);key(ob,start,loc,size*.5);key(ob,peak,loc,size);key(ob,end,loc,size*.3);key(ob,end+1,loc,0);key(ob,55,loc,0)
 for f,hidden in [(1,True),(start-1,True),(start,False),(end,False),(end+1,True),(55,True)]:ob.hide_render=hidden;ob.keyframe_insert('hide_render',frame=f)
 for fc in ob.animation_data.action.fcurves:
  for k in fc.keyframe_points:k.interpolation='CONSTANT' if fc.data_path=='hide_render' else 'LINEAR'
# White ink is the main impact; the two neon colors are secondary accents.
envelope(sprite('Ink ground shock ring',1,True),33,37,43,origin,3.4)
envelope(sprite('Ink impact left',0),33,35,38,origin+Vector((1.1,.22,.55)),1.5)
envelope(sprite('Ink impact right',0),34,36,39,origin+Vector((-1.2,-.1,.55)),1.2)
envelope(sprite('Magenta impact glitch',3),33,35,40,origin+Vector((-.9,.05,1.0)),1.1)
envelope(sprite('Cyan impact slash',2),33,35,39,origin+Vector((.7,0,1.0)),1.1)
for i,f in enumerate([28,30,32]):
 loc=center_at(f)+Vector((-.1,.12,.16))
 envelope(sprite('Cyan descending slash %d'%i,2),f,f+1,f+2,loc,1.15+i*.12)
 envelope(sprite('Magenta descending glitch %d'%i,3),f+1,f+1,f+2,loc+Vector((.4,-.1,.12)),.55)
# Sparse flat scanline fragments flash beside the display during anticipation/hit.
def neon(name,color):
 m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=1.8;return m
cyan=neon('PREVIEW_GlitchCyan',(0,.5,1));pink=neon('PREVIEW_GlitchMagenta',(1,.015,.35))
for i in range(12):
 ob=sprite('Electronic scan fragment %02d'%i,3);ob.data.materials.clear();ob.data.materials.append(cyan if i%2==0 else pink)
 for v in ob.data.vertices:v.co.y*=.08 if i%3 else .18
 sign=1 if i%2 else -1;loc=Vector((sign*(.8+.14*(i%3)),.75,1.9+.19*(i%5)))
 start=23+i%3 if i<6 else 32+i%3
 envelope(ob,start,start+1,start+2,loc,.23+.09*(i%4))
bpy.context.window.scene=s
