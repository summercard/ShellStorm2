# Final camera, reflection, join and data cleanup.
root.name='粉色电竞卧室_参考还原_v001'
for c in root.children:
 if c.name.endswith(('.001','.002')):c.name=c.name[:-4]
# Corner cap overlap was producing a black coplanar patch.
o=next(o for o in packs['01_房间外壳'].objects if o.name.startswith('左墙上压边'));o.location.y=-.045;o.dimensions.y=2.94
# Pink light must be behind the TV glass.
o=bpy.data.objects['粉色背墙洗墙'];o.location=( -.65,1.392,1.421);o.rotation_euler=(Vector((-.65,1.5,1.49))-o.location).to_track_quat('-Z','Y').to_euler()
# Sofa perimeter stitches follow the padded silhouette without spline overshoot.
COL=packs['07_矮沙发']
for o in list(COL.objects):
 if o.name.startswith('靠背缝线'):bpy.data.objects.remove(o,do_unlink=True)
for xx in [-.16,.29]:
 pts=[]
 for i in range(64):
  a=2*pi*i/64
  px=xx+.199*math.copysign(abs(cos(a))**.38,cos(a))
  pz=.414+.139*math.copysign(abs(sin(a))**.48,sin(a))
  pts.append((px,-.567,pz))
 tube('贴合靠背拼缝',pts,.0015,(.74,.7,.72),'fabric',True)
# Make rolled duvet corners stop at the side drop rather than double-drop.
o=next(o for o in packs['06_床与床品'].objects if o.name.startswith('粉色垂坠被面'))
for j in range(77):
 y=-.555+j*1.015/76
 for i in range(73):
  u=-1+2*i/72;side=max(0,(abs(u)*.412-.377)/.035);foot=max(0,(-y-.465)/.09)
  o.data.vertices[j*73+i].co.z=.483-max(.132*side**.72,.104*foot**.72)+.0025*sin(i*.49+j*.28)+.002*sin(j*.61)*abs(u)**4
# Remove former edge seam curves, rebuild on corrected surface.
COL=packs['06_床与床品']
for o in list(COL.objects):
 if o.name.startswith(('被边缝线','被脚弧形滚边')):bpy.data.objects.remove(o,do_unlink=True)
for sg in [-1,1]:
 pts=[]
 for j in range(36):
  y=-.54+j*.987/35;x=1.1+sg*.393
  z=.485-max(.132*((.393-.377)/.035)**.72,.104*max(0,(-y-.465)/.09)**.72)
  pts.append((x,y,z))
 tube('被边缝线',pts,.002,(.93,.20,.45),'fabric')
pts=[]
for i in range(51):
 u=-1+2*i/50;xx=1.1+u*.408;zz=.485-max(.132*max(0,(abs(u)*.408-.377)/.035)**.72,.104*((.535-.465)/.09)**.72)
 pts.append((xx,-.535,zz))
tube('被脚弧形滚边',pts,.002,(.9,.16,.4),'fabric')
# More natural flat front comparison, with a complete uncropped frame.
o=bpy.data.objects['验收_正视'];o.location=(0,-8,2.02);o.rotation_euler=(Vector((0,.1,1.0))-o.location).to_track_quat('-Z','Y').to_euler();o.data.ortho_scale=3.98
# White presentation background while retaining the established illumination.
scene.render.film_transparent=True
n=scene.node_tree.nodes;l=scene.node_tree.links;gl=next(x for x in n if x.type=='GLARE');out=next(x for x in n if x.type=='COMPOSITE')
aa=n.new('CompositorNodeAlphaOver');aa.inputs[0].default_value=1;aa.inputs[1].default_value=(.92,.94,.96,1);l.new(gl.outputs['Image'],aa.inputs[2]);l.new(aa.outputs[0],out.inputs[0])
# Strip leftover data from default cube and earlier construction passes.
for datablocks in [bpy.data.meshes,bpy.data.curves,bpy.data.cameras,bpy.data.lights]:
 for d in list(datablocks):
  if d.users==0:datablocks.remove(d)
used={m for o in scene.objects if o.type in {'MESH','CURVE'} for m in o.data.materials}
for m in list(bpy.data.materials):
 if m not in used:bpy.data.materials.remove(m,do_unlink=True)
for m in used:m.name=m.name.split('.')[0]
scene.camera=bpy.data.objects['验收_参考轴测'];scene.cycles.samples=64
scene['制作范围']='设计稿独立房间高细节还原；未修改 ShellStorm2 现有场景'
scene['参考尺寸']='净尺寸350 × 300 × 200 mm；1 Blender单位=100mm'
scene['检查视图']='轴测、正视、俯视、家具近景'
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/粉色电竞卧室_高还原_v001.blend')
print('final source saved',len(used),'shared materials')
