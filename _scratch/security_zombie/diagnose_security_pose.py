import bpy, json
from pathlib import Path
from mathutils import Vector
P=Path(r'I:\工作项目\shellstrom2\ShellStorm2')
ANIM=P/'assets/art/enemies/normal_enemy_3d/security_zombie/source/animation/enm_security_zombie_animation_v001.blend'
bpy.ops.wm.open_mainfile(filepath=str(ANIM))
sc=bpy.context.scene
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
a=bpy.data.actions.get('armed_idle')
arm.animation_data_create(); arm.animation_data.action=a
sc.frame_set(25); bpy.context.view_layer.update()
print('ARM',arm.name,'matrix',tuple(round(x,3) for x in arm.matrix_world.translation))
for n in ['L_Upperarm','L_Forearm','L_Hand','R_Upperarm','R_Forearm','R_Hand']:
    pb=arm.pose.bones[n]
    h=arm.matrix_world @ pb.head
    t=arm.matrix_world @ pb.tail
    print(n,'head',tuple(round(x,3) for x in h),'tail',tuple(round(x,3) for x in t),'len',round((t-h).length,3))
for o in bpy.data.objects:
    if o.name in ('WeaponRoot','GripSocket','SupportHandSocket','MuzzleSocket'):
        print(o.name,'world',tuple(round(x,3) for x in o.matrix_world.translation),'parent',o.parent.name if o.parent else None,'ptype',o.parent_type)
# mesh bbox
for o in bpy.data.objects:
    if o.type=='MESH' and 'security_short_shotgun' in o.name:
        pts=[o.matrix_world @ Vector(c) for c in o.bound_box]
        lo=Vector((min(p.x for p in pts),min(p.y for p in pts),min(p.z for p in pts))); hi=Vector((max(p.x for p in pts),max(p.y for p in pts),max(p.z for p in pts)))
        print('GEO',o.name,'lo',tuple(round(x,3) for x in lo),'hi',tuple(round(x,3) for x in hi))
