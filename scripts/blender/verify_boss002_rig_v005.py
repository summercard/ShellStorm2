import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/rig_v005'
def verts(o):
    e=o.evaluated_get(bpy.context.evaluated_depsgraph_get());m=e.to_mesh();v=[e.matrix_world@v.co for v in m.vertices];e.to_mesh_clear();return v
def sign(rig):return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in rig.data.bones],sort_keys=True).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v004.blend'));bpy.context.window.scene=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.scene.frame_set(1)
old={o.name:verts(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name!='Stand column'}
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v005.blend'));s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;rig=bpy.data.objects['Boss002_Rig'];ctrl=bpy.data.objects['ExpressionController'];signature=sign(rig)
def update():rig.update_tag();bpy.context.view_layer.update()
def reset():
    for p in rig.pose.bones:p.location=(0,0,0);p.rotation_euler=(0,0,0);p.scale=(1,1,1)
    update()
rest={o.name:verts(o) for o in s.objects if o.type=='MESH'}
err={n:max((a-b).length for a,b in zip(v,rest[n])) for n,v in old.items()}
weights=[];unbound=[]
for o in s.objects:
    if o.type!='MESH':continue
    if o.parent_type=='BONE':continue
    if not any(m.type=='ARMATURE' for m in o.modifiers):unbound.append(o.name);continue
    for v in o.data.vertices:
        weights.append(sum(g.weight for g in v.groups))
checks={'model_no_actions':len(bpy.data.actions)==0,'expression_not_auto_animated':ctrl.animation_data is None,'all_character_meshes_skinned':not unbound,'weights_normalized':all(abs(w-1)<1e-5 for w in weights),'rest_matches_v004':max(err.values())<1e-4,'keyboard_bone_parent':all(o.parent_bone=='prop_socket.L' for o in s.objects if o.get('asset_role')=='hand_prop_keyboard')}
results={'rest_max_displacement':max(err.values()),'worst_rest_objects':sorted(err.items(),key=lambda a:-a[1])[:5],'unbound':unbound}
# Stretch only one hand, test actual coil mesh extents, opposite hand stable, prop movement.
left=next(o for o in s.objects if o.name.startswith('Continuous spring') and sum(v.x for v in rest[o.name])>0);right=next(o for o in s.objects if o.name.startswith('Continuous spring') and o!=left)
rig.pose.bones['hand_ctrl.L'].location.y=.9;update();v=verts(left);a=rest[left.name]
ratio=(max(p.x for p in v)-min(p.x for p in v))/(max(p.x for p in a)-min(p.x for p in a))
radius=(max(p.z for p in v)-min(p.z for p in v))/(max(p.z for p in a)-min(p.z for p in a))
checks['spring_extends']=ratio>1.45;checks['spring_radius_preserved']=abs(radius-1)<.03;checks['opposite_arm_independent']=max((x-y).length for x,y in zip(verts(right),rest[right.name]))<1e-4
key=bpy.data.objects['Keyboard outer shell'];km=max((x-y).length for x,y in zip(verts(key),rest[key.name]));checks['keyboard_follows_hand']=km>.8;results['spring']={'length_ratio':ratio,'radius_ratio':radius,'keyboard_displacement':km}
reset();rig.pose.bones['hand_ctrl.L'].location.y=-.4;update();v=verts(left);ratio=(max(p.x for p in v)-min(p.x for p in v))/(max(p.x for p in a)-min(p.x for p in a));checks['spring_compresses']=ratio<.8
reset();face_results=[]
for pose in ['spin','forward']:
    if pose=='spin':rig.pose.bones['monitor_spin'].rotation_euler.y=math.radians(60)
    else:
        reset();rig.pose.bones['support_01'].rotation_euler.x=-.35;rig.pose.bones['support_02'].rotation_euler.x=-.4;rig.pose.bones['monitor_tilt'].rotation_euler.x=-.25
    update()
    for name in ['large_eye','round_eye','mouth']:
        o=bpy.data.objects['Texture '+name];v=verts(o);rv=rest[o.name];n=(v[1]-v[0]).cross(v[2]-v[0]).normalized();rn=(rv[1]-rv[0]).cross(rv[2]-rv[0]).normalized();center=sum(v,Vector())/4;anchor=rig.matrix_world@rig.pose.bones['face_anchor_'+name].head
        face_results.append({'pose':pose,'slot':name,'normal_dot':n.dot(rn),'anchor_error':(center-anchor).length,'motion':(center-sum(rv,Vector())/4).length})
checks['face_upright']=all(x['normal_dot']>.9999 for x in face_results);checks['face_follows_anchor']=all(x['anchor_error']<1e-4 for x in face_results);checks['face_moves']=all(x['motion']>.05 for x in face_results);results['face']=face_results
col=bpy.data.objects['Stand column'];delta=max((x-y).length for x,y in zip(verts(col),rest[col.name]));checks['support_deforms']=delta>.1;results['support_forward_displacement']=delta
reset();rig.pose.bones['support_01'].rotation_euler.z=.66;rig.pose.bones['support_02'].rotation_euler.z=-1.13;rig.pose.bones['support_03'].rotation_euler.z=.47;update();screen=bpy.data.objects['Portrait display'];lower=sum(v.z for v in rest[screen.name])/len(rest[screen.name])-sum(v.z for v in verts(screen))/len(rest[screen.name]);checks['screen_can_move_down']=lower>.04;results['screen_drop']=lower
reset();hand=bpy.data.objects['Sculpted glove L'];rig.pose.bones['digit2_01.L'].rotation_euler.x=.6;update();checks['finger_weights_deform']=max((x-y).length for x,y in zip(verts(hand),rest[hand.name]))>.03
reset();checks['reset_exact']=max(max((x-y).length for x,y in zip(verts(bpy.data.objects[n]),v)) for n,v in rest.items())<1e-4
ctrl['expression_index']=4;ctrl.update_tag();s.frame_set(57);bpy.context.view_layer.update();checks['expression_state_persists']=ctrl['expression_index']==4
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v005.blend'));checks['dual_master_signature_matches']=sign(bpy.data.objects['Boss002_Rig'])==signature;checks['qa_actions_exist']=len([a for a in bpy.data.actions if a.name.startswith('QA_')])==5
report={'checks':checks,'passed':all(checks.values()),'results':results,'skeleton_signature':signature,'exit_code':0 if all(checks.values()) else 1,'expected_faults':[],'not_executed':['Godot import','runtime state mapping','GLB constraint baking','final gameplay animations']};(P/'audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report,indent=2));assert report['passed']
