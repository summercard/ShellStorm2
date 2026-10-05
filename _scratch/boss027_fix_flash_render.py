import bpy,json,math
from pathlib import Path
from mathutils import Vector
B=Path('assets/art/enemies/bosses/enm_boss_monitor002').resolve();P=B/'previews/impact_electric_v027';bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v027.blend'));r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s
checks={};states=[]
for name,f,exp,el,dz,hit in [('stun_enter',1,2,0,0,0),('stun_enter',4,2,0,0,1),('stun_enter',5,5,0,1,0),('stun_loop',20,5,0,1,0),('stun_exit',20,0,0,0,0),('special_insert',14,2,0,0,0),('special_insert',15,2,1,0,0),('special_channel',12,2,1,0,0),('special_recover',9,2,0,0,0)]:
 r.animation_data.action=bpy.data.actions[name];s.frame_set(f);actual=[round(r[k]) for k in ['expression_state','electric_active','dizzy_active','stun_hit_flash']];checks[name+'_'+str(f)]=actual==[exp,el,dz,hit];states.append([name,f,actual])
r.animation_data.action=bpy.data.actions['stun_enter'];zs=[]
for f in [19,25,31]:s.frame_set(f);zs.append(r.pose.bones['rear_axle'].matrix.translation.z)
checks['single_bounce_height']=abs(zs[1]-zs[0]-.48)<.002 and abs(zs[2]-zs[0])<.002
checks['rig_bones_64']=len(r.data.bones)==64
checks['electric_bone_parenting']=all(o.parent==r and o.parent_type=='BONE' for o in bpy.data.collections['BOSS002_DIZZY_ELECTRIC_PREVIEW'].objects if o.name.startswith('Cable current'))
checks['no_invalid_fx_drivers']=all(fc.driver.is_valid for o in bpy.data.collections['BOSS002_DIZZY_ELECTRIC_PREVIEW'].objects if o.animation_data for fc in o.animation_data.drivers)
report={'checks':checks,'states':states,'bounce_axle_z':zs,'passed':all(checks.values())};(P/'fx_audit.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)
r.animation_data.action=bpy.data.actions['stun_enter'];s.frame_set(4);s.cycles.samples=16;s.render.resolution_x=720;s.render.resolution_y=600;s.render.filepath=str(P/'stun_hit_frame4.png');bpy.ops.render.render(write_still=True)

s.render.filepath=str(P/'stun_enter/0003.png');bpy.ops.render.render(write_still=True)
