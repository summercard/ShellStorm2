import bpy
from mathutils import Vector
from pathlib import Path
out=Path('I:/工作项目/shellstrom2/ShellStorm2/_scratch/xiaojunzhu_intake')
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=16;s.render.resolution_x=1000;s.render.resolution_y=700;s.render.resolution_percentage=100
s.world.color=(0.7,0.7,0.7)
for loc in [(0,2,3),(0,-2,2)]:
 d=bpy.data.lights.new('inspect','AREA');d.energy=150;d.size=3;o=bpy.data.objects.new('inspect',d);s.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,0.8))-o.location).to_track_quat('-Z','Y').to_euler()
c=bpy.data.cameras.new('inspect');c.type='ORTHO';c.ortho_scale=.36;o=bpy.data.objects.new('inspect',c);s.collection.objects.link(o);s.camera=o
for name,loc,target in [('left_top',(-.56,0,3),(-.56,.025,.76)),('right_top',(.56,0,3),(.56,.025,.76)),('left_front',(-.56,3,.76),(-.56,.025,.76))]:
 o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
