import bpy
from pathlib import Path
from mathutils import Vector
O=Path(__file__).parent;stage='optimized' if 'optimized' in bpy.data.filepath else 'source'
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=16;s.render.resolution_x=1000;s.render.resolution_y=650;s.render.resolution_percentage=100
s.world=bpy.data.worlds.new('FixedQAWorld');s.world.color=(.5,.5,.5);s.view_settings.view_transform='Standard';s.view_settings.look='None';s.view_settings.exposure=1
for name,pos,power,size in [('Key',(-3,-4,7),650,5),('Fill',(4,3,5),400,4)]:
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.size=size;ob=bpy.data.objects.new(name,d);s.collection.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector((0,0,.7))-ob.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('FixedReference');ob=bpy.data.objects.new('FixedReference',d);s.collection.objects.link(ob);s.camera=ob;d.type='ORTHO';d.ortho_scale=15
for name,pos in [('game',(5,-7,5)),('front',(0,-8,3)),('back',(0,8,3)),('side',(8,0,3))]:
 ob.location=pos;ob.rotation_euler=(Vector((0,0,.3))-ob.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=str(O/(stage+'_'+name+'.png'));bpy.ops.render.render(write_still=True)
