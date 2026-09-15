import bpy, math
from mathutils import Vector
from collections import Counter

root=bpy.data.collections['楼梯区_组件化美术管理_v020']
editable=bpy.data.collections.new('01_制作组件_v020墙地深化')
root.children.link(editable)
editable.hide_render=True;editable.hide_viewport=True
output=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('asset_detail_version')=='v020']
for o in output:
    if o.modifiers:
        source=o.copy();source.data=o.data.copy();source.name=o.name+'_制作源';editable.objects.link(source)
        source['output_object']=o.name
        me=bpy.data.meshes.new_from_object(o.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        o.modifiers.clear();o.data=me
        uv=me.uv_layers.get('PaletteUV')
        for p in me.polygons:
            cell=Counter((min(9,max(0,int(uv.data[k].uv.x*10))),min(9,max(0,int(uv.data[k].uv.y*10)))) for k in p.loop_indices).most_common(1)[0][0]
            for j,k in enumerate(p.loop_indices):
                a=2*math.pi*j/len(p.loop_indices)
                uv.data[k].uv=((cell[0]+.5)/10+.026*math.cos(a),(cell[1]+.5)/10+.026*math.sin(a))
        me.uv_layers.active=uv;uv.active_render=True

display=bpy.data.collections['90_展示与验收_沿用v016镜头']
for o in list(bpy.context.scene.collection.objects):
    if o.type in ['LIGHT','CAMERA']:
        if o.name not in display.objects:display.objects.link(o)
        bpy.context.scene.collection.objects.unlink(o)
def area(name,pos,target,energy,color,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.color=color;data.shape='DISK';data.size=size
    o=bpy.data.objects.new(name,data);display.objects.link(o);o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('v020_楼梯井柔光',(40,15,-5),(40,12,-20),1700,(.40,.55,1),12)
area('v020_上平台蓝色反射',(42,0,-5),(40,1,-9),650,(.025,.15,1),4)
area('v020_楼梯墙暖反射',(46,10,-10),(43,10,-14),380,(1,.21,.035),4)
s=bpy.context.scene;s.world.use_nodes=True
bg=s.world.node_tree.nodes.get('Background')
if bg:bg.inputs['Color'].default_value=(.015,.022,.038,1);bg.inputs['Strength'].default_value=.30
s['asset_source_version']='v020'
s['runtime_imported']=False
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
print('FINALIZED',len(output),len(editable.objects))
