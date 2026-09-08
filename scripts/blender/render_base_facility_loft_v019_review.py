import bpy,sys,json
from pathlib import Path
from mathutils import Vector
R=Path('/Users/summercards/ShellStorm2/outputs/verification/base_facility_loft_v019');tag=sys.argv[-1]
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=48;s.cycles.use_denoising=True;s.render.use_freestyle=False;s.render.resolution_x=1500;s.render.resolution_y=880;s.render.resolution_percentage=100
# Temporary review rig, identical before and after; never saved over layout scene.
cu=bpy.data.cameras.new('ReviewCamera');cam=bpy.data.objects.new('ReviewCamera',cu);s.collection.objects.link(cam);s.camera=cam;cu.type='ORTHO'
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
for n,loc,power,size,col in [('warm',(0,9,13),1800,8,(1,.65,.36)),('fill',(7,5,12),900,7,(.55,.72,1))]:
 d=bpy.data.lights.new(n,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=col;o=bpy.data.objects.new(n,d);s.collection.objects.link(o);o.location=loc;aim(o,(5,11,6))
views=[('full',(-11,-11,20),(4.6,10,7.2),22.0),('bed',(-7,-4,15),(.3,11.15,7.1),10.2),('sofa',(-1,-2,13),(6.25,11.65,7.4),10.0),('top',(5,10,30),(5,10,6),21.2)]
for name,loc,target,scale in views:
 cam.location=loc;aim(cam,target);cu.ortho_scale=scale;s.render.filepath=str(R/(tag+'_'+name+'.png'));bpy.ops.render.render(write_still=True)
(R/(tag+'_render_settings.json')).write_text(json.dumps({'views':views,'engine':'CYCLES','samples':48,'freestyle':False,'temporary_review_lights':'1800W warm 8m / 900W cool 7m','view_transform':s.view_settings.view_transform}))
