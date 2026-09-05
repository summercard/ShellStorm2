import bpy, math, random, os
from mathutils import Vector
from math import sin,cos,pi,sqrt
OUT='/Users/summercards/ShellStorm2/output/kawaii_jelly_v001'
random.seed(12)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.name='Q弹果冻_互动场景'
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
for c in list(bpy.data.collections):
 if not c.objects and not c.children:bpy.data.collections.remove(c)
root=bpy.data.collections.new('01_果冻_固定底面');scene.collection.children.link(root)
facecol=bpy.data.collections.new('02_表情_随果冻形变');scene.collection.children.link(facecol)
studio=bpy.data.collections.new('90_展示_相机灯光');scene.collection.children.link(studio)
def mat(name,c,rough=.3,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;return m,p
jelly,p=mat('草莓果冻_透光凝胶',(.88,.115,.265),.18)
p.inputs['Transmission Weight'].default_value=.58;p.inputs['IOR'].default_value=1.36;p.inputs['Coat Weight'].default_value=.38;p.inputs['Coat Roughness'].default_value=.14;p.inputs['Subsurface Weight'].default_value=.075;p.inputs['Subsurface Radius'].default_value=(1,.33,.25)
black,p=mat('可可色眼睛',(.027,.009,.015),.17);p.inputs['Coat Weight'].default_value=.35
white,p=mat('奶白色高光',(.98,.94,.90),.16)
blush,p=mat('桃粉腮红',(.99,.13,.21),.43);p.inputs['Subsurface Weight'].default_value=.12
base,p=mat('奶油薄荷陶瓷',(.53,.79,.72),.26);p.inputs['Coat Weight'].default_value=.3
floor,p=mat('暖奶油背景',(.88,.81,.72),.63)
bubble,p=mat('内部小气泡',(.98,.55,.64),.12);p.inputs['Transmission Weight'].default_value=.75;p.inputs['IOR'].default_value=1.05
rim,p=mat('盘沿奶白',(.95,.89,.78),.26)
def link(o,c):
 for oc in list(o.users_collection):oc.objects.unlink(o)
 c.objects.link(o)
def mesh(name,v,f,m,c=root):
 me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update();o=bpy.data.objects.new(name,me);c.objects.link(o);me.materials.append(m)
 for p in me.polygons:p.use_smooth=True
 return o
def follow(o):
 o['jelly_deform']=True
 a=o.data.attributes.new('jelly_rest','FLOAT_VECTOR','POINT')
 for i,v in enumerate(o.data.vertices):a.data[i].vector=v.co
 return o
def sphere(name,loc,scale,m,c=facecol,seg=32,rings=20,deform=True):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=True,rotation=False,scale=True);link(o,c);o.data.materials.append(m)
 for p in o.data.polygons:p.use_smooth=True
 if deform:follow(o)
 return o
# Closed exact hemisphere with a triangulated flat cut disk.
N=96;R=48;v=[];f=[]
for j in range(R):
 t=j/R*pi/2
 for i in range(N):a=i*2*pi/N;v.append((cos(t)*cos(a),cos(t)*sin(a),sin(t)))
top=len(v);v.append((0,0,1));bottom=len(v);v.append((0,0,0))
for j in range(R-1):
 for i in range(N):a=j*N+i;b=j*N+(i+1)%N;f.append((a,b,b+N,a+N))
for i in range(N):f.append(((R-1)*N+i,(R-1)*N+(i+1)%N,top));f.append((bottom,(i+1)%N,i))
body=follow(mesh('果冻本体_平切面固定',v,f,jelly));body['jelly_body']=True
vg=body.vertex_groups.new(name='固定切面_权重1');vg.add(list(range(N))+[bottom],1,'REPLACE')
for p in body.data.polygons:
 if all(abs(body.data.vertices[i].co.z)<1e-6 for i in p.vertices):p.use_smooth=False
# Face lies immediately outside the spherical front surface.
def surface(x,z,extra=.014):return (x,-sqrt(max(.01,1-x*x-z*z))-extra,z)
for sg in [-1,1]:
 x=sg*.26;z=.44;loc=surface(x,z)
 sphere('左眼' if sg<0 else '右眼',loc,(.052,.025,.078),black)
 sphere('眼睛大高光',(loc[0]-.014,loc[1]-.024,loc[2]+.025),(.014,.007,.019),white,seg=24,rings=16)
 sphere('眼睛小高光',(loc[0]+.015,loc[1]-.025,loc[2]-.022),(.006,.004,.008),white,seg=16,rings=12)
 loc=surface(sg*.43,.315,.016);sphere('软桃腮红',loc,(.086,.013,.039),blush)
 for k in range(2):
  loc2=surface(sg*(.415+k*.035),.32,.032);sphere('腮红奶白点',loc2,(.008,.004,.012),white,seg=16,rings=12)
# Small w-shaped smile, converted to a deforming mesh.
cu=bpy.data.curves.new('微笑曲线','CURVE');cu.dimensions='3D';cu.bevel_depth=.012;cu.bevel_resolution=4
sp=cu.splines.new('BEZIER');pts=[(-.087,.359),(-.056,.325),(-.026,.327),(0,.354),(.026,.327),(.056,.325),(.087,.359)];sp.bezier_points.add(len(pts)-1)
for b,(x,z) in zip(sp.bezier_points,pts):b.co=surface(x,z,.024);b.handle_left_type='AUTO';b.handle_right_type='AUTO'
o=bpy.data.objects.new('小小W形微笑',cu);facecol.objects.link(o);cu.materials.append(black);bpy.context.view_layer.objects.active=o;o.select_set(True);body.select_set(False);bpy.ops.object.convert(target='MESH');follow(bpy.context.object)
# A few small bubbles deepen the gelatin material without cluttering the silhouette.
for i,(x,y,z,s) in enumerate([(-.62,-.28,.46,.024),(.53,-.18,.57,.018),(-.26,.08,.77,.022),(.27,.2,.46,.027),(-.50,.35,.18,.019),(.57,.16,.23,.018)]):sphere('内部气泡_%02d'%i,(x,y,z),(s,s,s),bubble,root,seg=20,rings=12)
# Low ceramic saucer: lathed profile, no floating bottom.
profile=[(0,-.11),(1.07,-.11),(1.16,-.092),(1.205,-.065),(1.215,-.015),(1.195,.018),(1.175,.024),(1.145,.015),(1.13,-.013),(1.06,-.021),(1.025,-.015),(1.01,-.005),(0,-.005)]
v=[];f=[];N=128
for r,z in profile:
 for i in range(N):a=2*pi*i/N;v.append((r*cos(a),r*sin(a),z))
for j in range(len(profile)-1):
 for i in range(N):a=j*N+i;b=j*N+(i+1)%N;f.append((a,b,b+N,a+N))
mesh('薄荷色小托盘',v,f,base,studio)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.112));o=bpy.context.object;o.name='摄影背景';link(o,studio);o.data.materials.append(floor)
def area(name,loc,power,size,target=(0,0,.4),color=(1,1,1)):
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=color;o=bpy.data.objects.new(name,d);studio.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o
area('左上大柔光',(-3,-4,5),450,3.2,color=(1,.84,.79));area('右后透光',(2,2.5,3.2),500,2.3,color=(1,.88,.82));area('前侧填充',(3,-3,2.3),130,2.4,color=(.78,.9,1))
d=bpy.data.cameras.new('果冻展示相机');cam=bpy.data.objects.new('果冻展示相机',d);studio.objects.link(cam);cam.location=(2.1,-5,2.1);cam.rotation_euler=(Vector((0,0,.40))-cam.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=3.22;scene.camera=cam
scene.world.use_nodes=True;p=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND');p.inputs[0].default_value=(.8,.84,.9,1);p.inputs[1].default_value=.25
scene.render.engine='CYCLES';scene.cycles.samples=64;scene.cycles.use_denoising=True;scene.render.resolution_x=1200;scene.render.resolution_y=1100;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.filepath=OUT+'/renders/果冻_静止.png';scene.view_settings.view_transform='AgX'
scene['jelly_radius']=1.0;scene['jelly_stiffness']=48.0;scene['jelly_damping']=2.8;scene['jelly_status']='点击右侧 Q弹果冻 面板开始交互'
for o in scene.objects:o.select_set(False)
body.select_set(True);bpy.context.view_layer.objects.active=body
for a in bpy.context.screen.areas:
 if a.type=='VIEW_3D':
  a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.region_3d.view_camera_zoom=13;a.spaces.active.overlay.show_overlays=False;a.spaces.active.shading.type='MATERIAL';a.spaces.active.show_region_ui=True
for m in list(bpy.data.materials):
 if m.users==0:bpy.data.materials.remove(m)
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/Q弹果冻_可交互_v001.blend')
print('Built exact closed hemisphere',len(body.data.vertices),'vertices')
