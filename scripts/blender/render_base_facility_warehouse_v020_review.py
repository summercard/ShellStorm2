import bpy,sys,json
from mathutils import Vector
from pathlib import Path
R=Path('/Users/summercards/ShellStorm2/outputs/verification/base_facility_warehouse_v020');tag=sys.argv[-1];s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=24;s.cycles.use_denoising=True;s.render.use_freestyle=False;s.render.resolution_x=1350;s.render.resolution_y=1000;s.render.resolution_percentage=100
cu=bpy.data.cameras.new('仓库固定检视');cam=bpy.data.objects.new(cu.name,cu);s.collection.objects.link(cam);s.camera=cam;cu.type='ORTHO'
def aim(o,t):o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
for n,loc,target,energy,color in [('warm',(-10,-5,8),(-13,-5,1),1000,(1,.64,.35)),('fill',(-5,-10,8),(-11,-8,1),600,(.5,.72,1)),('east',(8,-10,7),(13,-10,1),800,(.65,.8,1))]:
 d=bpy.data.lights.new(n,'AREA');d.energy=energy;d.shape='DISK';d.size=6;d.color=color;o=bpy.data.objects.new(n,d);s.collection.objects.link(o);o.location=loc;aim(o,target)
views=[('west',(-1,4,17),(-12.2,-6,1.6),17.3),('bench',(-4,1,11),(-12.6,-3.3,2.05),8.7),('east',(1,-1,15),(12.9,-10.3,1.0),9.3),('top',(0,-6,35),(0,-6,0),32)]
for name,loc,t,scale in views:
 cam.location=loc;aim(cam,t);cu.ortho_scale=scale;s.render.filepath=str(R/(tag+'_'+name+'.png'));bpy.ops.render.render(write_still=True)
(R/(tag+'_render.json')).write_text(json.dumps({'views':views,'samples':24,'resolution':[1350,1000],'freestyle':False,'temporary_rig':'1000W warm + 600W cool west; 800W east'}))
