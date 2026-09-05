group('90_灯光与验收镜头')
area('主光柔光箱',(1,-3,5),(0,0,.65),380,(1,.85,.91),4)
area('左侧填充',(-3,-1,2.8),(0,.4,1),150,(.76,.86,1),3)
area('顶部柔光',(0,.9,3.7),(0,.5,0),130,(1,.91,.96),2.8)
area('粉色背墙洗墙',(-.65,1.12,1.42),(-.65,1.5,1.5),12,(1,.015,.35),1.1)
area('左侧粉色洗墙',(-1.59,.9,1.68),(-1.77,.8,1.6),8,(1,.008,.32),.65)
area('右侧粉色洗墙',(1.61,1.29,1.6),(1.7,1.5,1.6),6,(1,.008,.38),.5)
area('桌下青色洗墙',(.14,1.17,.33),(.05,1.5,.3),8,(.01,.57,1),.45)
area('床头青色洗墙',(1.26,1.36,.86),(1.28,1.5,.83),6,(.01,.62,1),.7)
area('左墙青色洗墙',(-1.58,-1.36,.39),(-1.77,-1.34,.4),6,(.01,.65,1),.65)
def camera(name,loc,target,scale):
 d=bpy.data.cameras.new(name); d.type='ORTHO';d.ortho_scale=scale;d.lens=50
 o=bpy.data.objects.new(name,d);COL.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();return o
cam=camera('验收_参考轴测',(4.1,-6.3,4.1),(0,.05,.83),4.6)
camera('验收_正视',(0,-7,2.65),(0,.23,.94),3.94)
camera('验收_俯视',(0,0,8),(0,0,0),3.95)
camera('验收_家具近景',(2.8,-4.6,3.25),(.40,.62,.67),2.65)
scene.camera=cam;scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1400;scene.render.resolution_y=1250;scene.render.resolution_percentage=100
scene.world.color=(.25,.25,.25);scene.world.use_nodes=True
bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.42,.44,.51,1);bg.inputs[1].default_value=.3
scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.use_nodes=True
nodes=scene.node_tree.nodes;nodes.clear();rl=nodes.new('CompositorNodeRLayers');gl=nodes.new('CompositorNodeGlare');gl.glare_type='FOG_GLOW';gl.quality='HIGH';gl.threshold=1.3;gl.size=7;gl.mix=-.92
out=nodes.new('CompositorNodeComposite');scene.node_tree.links.new(rl.outputs['Image'],gl.inputs['Image']);scene.node_tree.links.new(gl.outputs['Image'],out.inputs['Image'])
# remove empty construction collections and unused materials from earlier runs
for c in list(bpy.data.collections):
 if len(c.objects)==0 and len(c.children)==0 and c!=root:bpy.data.collections.remove(c)
for mat in list(bpy.data.materials):
 if mat.users==0:bpy.data.materials.remove(mat)
for area_ui in bpy.context.screen.areas:
 if area_ui.type=='VIEW_3D':
  area_ui.spaces.active.region_3d.view_perspective='CAMERA';area_ui.spaces.active.shading.type='MATERIAL'
scene.render.filepath=OUT+'/renders/01_参考轴测.png'
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/粉色电竞卧室_高还原_v001.blend')
print('saved ready for render')
