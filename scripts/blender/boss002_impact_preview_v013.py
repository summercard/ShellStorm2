"""Source-only impact presentation; executed inside the v013 authoring context."""
import random
rng=random.Random(13)
studio=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=studio
fx=bpy.data.collections.new('BOSS002_IMPACT_PREVIEW');studio.collection.children.link(fx)
fx['preview_only']=True;fx['export']=False;fx['impact_frame']=33
studio.frame_set(33);ob=bpy.data.objects['Keyboard outer shell'];ev=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh()
origin=sum((ev.matrix_world@v.co for v in me.vertices),Vector())/len(me.vertices);ev.to_mesh_clear();origin.z=.04
def material(name,color,emission=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.85;p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emission;return m
mint=material('PREVIEW_ImpactMint',(.32,.85,.46),1.6)
dust=material('PREVIEW_ImpactDust',(.39,.43,.35))
rock=material('PREVIEW_ImpactDebris',(.14,.20,.16))
def adopt(ob,mat):
 for col in list(ob.users_collection):col.objects.unlink(ob)
 fx.objects.link(ob);ob.data.materials.append(mat);ob['preview_only']=True;ob['export']=False
 return ob
def key(ob,frame,loc,scale):
 ob.location=loc;ob.scale=scale;ob.keyframe_insert('location',frame=frame);ob.keyframe_insert('scale',frame=frame)
def visible(ob,start,end):
 for frame,value in [(1,True),(start-1,True),(start,False),(end,False),(end+1,True),(55,True)]:
  ob.hide_render=value;ob.keyframe_insert('hide_render',frame=frame)
 # Source viewport visibility follows the scale keys; hide_viewport would hide editing.
 if ob.animation_data:
  for fc in ob.animation_data.action.fcurves:
   for k in fc.keyframe_points:k.interpolation='CONSTANT' if fc.data_path=='hide_render' else 'LINEAR'
for i in range(2):
 bpy.ops.mesh.primitive_torus_add(major_radius=1,minor_radius=.025,major_segments=64,minor_segments=6)
 ob=adopt(bpy.context.object,mint);ob.name='Impact expanding ring %d'%i;start=33+i*2
 key(ob,1,origin,(0,0,0));key(ob,start-1,origin,(0,0,0));key(ob,start,origin,(.6,.42,1));key(ob,start+5,origin,(1.7,1.25,.7));key(ob,start+11,origin,(2.3,1.7,0));key(ob,55,origin,(0,0,0));visible(ob,start,start+10)
for i in range(14):
 angle=math.tau*i/14+rng.uniform(-.12,.12);direction=Vector((math.cos(angle),math.sin(angle),0));radius=rng.uniform(.08,.17)
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1)
 ob=adopt(bpy.context.object,dust);ob.name='Impact dust puff %02d'%i
 key(ob,1,origin,(0,0,0));key(ob,32,origin,(0,0,0));key(ob,33,origin+direction*.45,(radius,radius,.06));key(ob,38,origin+direction*1.25+Vector((0,0,.12)),(radius*2.5,radius*2,.18));key(ob,46,origin+direction*2.05+Vector((0,0,.18)),(0,0,0));key(ob,55,origin,(0,0,0));visible(ob,33,45)
for i in range(16):
 angle=math.tau*i/16+rng.uniform(-.15,.15);direction=Vector((math.cos(angle),math.sin(angle),0));size=rng.uniform(.025,.07);reach=rng.uniform(.8,1.9);height=rng.uniform(.3,.75)
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1)
 ob=adopt(bpy.context.object,rock if i%3 else mint);ob.name='Impact debris %02d'%i
 key(ob,1,origin,(0,0,0));key(ob,32,origin,(0,0,0));key(ob,33,origin+direction*.3,(size,size,size*1.5));key(ob,38,origin+direction*reach*.65+Vector((0,0,height)),(size,size,size*1.5));key(ob,45,origin+direction*reach,(size*.5,size*.5,size*.4));key(ob,48,origin+direction*reach,(0,0,0));key(ob,55,origin,(0,0,0));visible(ob,33,47)
bpy.context.window.scene=s
