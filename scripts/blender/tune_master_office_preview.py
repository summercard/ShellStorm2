import bpy, os
from mathutils import Vector
cam=bpy.data.objects.get('CAMERA_45_DEGREE')
cam.location=(11.5,-11.5,12.5)
cam.rotation_euler=(Vector((0.0,0.0,2.7))-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.lens=42
scene=bpy.context.scene
scene.world.color=(0.06,0.075,0.10)
for o in bpy.data.objects:
    if o.type=='LIGHT':
        if o.name=='KEY_SOFT': o.data.energy=2600; o.data.size=10
        elif o.name=='FILL_BLUE': o.data.energy=1100
# add warm fill inside room
if not bpy.data.objects.get('WARM_FILL'):
    bpy.ops.object.light_add(type='AREA', location=(1,-2,7))
    l=bpy.context.object; l.name='WARM_FILL'; l.data.energy=900; l.data.color=(1.0,0.55,0.28); l.data.size=7
    l.rotation_euler=(Vector((0,0,0))-l.location).to_track_quat('-Z','Y').to_euler()
# make selected structural material slightly brighter
for mn in ['palette_wall','palette_floor','palette_floor_worn']:
    m=bpy.data.materials.get(mn)
    if m:
      bs=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
      if bs: bs.inputs['Base Color'].default_value=tuple(min(1,c*1.55) for c in bs.inputs['Base Color'].default_value[:3])+(1,)
scene.render.filepath=r'I:/工作项目/shellstorm2/ShellStorm2/art_source/environments/tower_zones/battle/source/room_types/master_office/v001/master_office_preview.png'
bpy.ops.wm.save_as_mainfile()
bpy.ops.render.render(write_still=True)
print('tuned')
