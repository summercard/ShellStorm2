"""Create v010 rig and four authored cycles without changing mesh geometry.

One-time authoring only. Subsequent artist edits use export_character_bundle.py.
"""
from pathlib import Path
import math
import json
import bpy
from mathutils import Matrix, Vector, Euler, Quaternion

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production'
PACKAGE = BASE/'v010'
TAU = math.tau

def collection(name, parent):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c

def transform(p, r=(0, 0, 0)):
    return Matrix.Translation(Vector(p)) @ Euler(r).to_matrix().to_4x4()

def main():
    model = PACKAGE/'source/model/chr_bunny01_model_v010.blend'
    animation = PACKAGE/'source/animation/chr_bunny01_animation_v010.blend'
    if model.exists() or animation.exists():
        raise RuntimeError('Authoring version already exists; preserve artist edits')
    bpy.ops.wm.open_mainfile(filepath=str(BASE/'v009/source/model/chr_bunny01_model_v009.blend'))
    bpy.context.preferences.filepaths.save_version = 0
    rig = bpy.data.objects['RIG_bunny01']
    old_rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    rig.animation_data_clear()
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    for bone in list(eb):
        eb.remove(bone)
    specs = {}
    def bone(name, head, tail, parent=None, deform=True):
        b = eb.new(name)
        b.head, b.tail = head, tail
        if parent: b.parent = eb[parent]
        b.use_connect = False
        b.use_deform = deform
        specs[name] = parent
        return b
    bone('root', (0,0,0), (0,.08,0), deform=False)
    bone('waist', (0,0,.20), (0,0,.38), 'root')
    bone('chest', (0,0,.38), (0,0,.55), 'waist')
    for name in ['head','ear_l','ear_r']:
        p = old_rest[name].translation
        bone(name, p, p+Vector((0,.08,0)), 'chest' if name=='head' else 'head')
    for side, sign in [('l',-1),('r',1)]:
        wrist = old_rest['hand_'+side].translation
        ankle = old_rest['foot_'+side].translation
        shoulder = Vector((sign*.17,.01,.50))
        elbow = Vector((sign*.35,.055,.43))
        bone('upper_arm_'+side, shoulder, elbow, 'chest')
        bone('forearm_'+side, elbow, wrist, 'upper_arm_'+side)
        bone('hand_'+side, wrist, wrist+Vector((0,-.08,0)), 'forearm_'+side)
        # Unweighted finger chains: thumb, index, and one combined three-finger chain.
        for name, x, length in [('thumb',-sign*.035,.035),('index',-sign*.012,.048),('fingers',sign*.022,.045)]:
            p = wrist+Vector((x,-.055,0))
            middle = p+Vector((0,-length,0))
            bone(name+'_01_'+side,p,middle,'hand_'+side)
            bone(name+'_02_'+side,middle,middle+Vector((0,-length*.75,0)),name+'_01_'+side)
        hip = Vector((sign*.12,0,.26))
        knee = Vector((sign*.13,-.055,.13))
        bone('thigh_'+side,hip,knee,'waist')
        bone('shin_'+side,knee,ankle,'thigh_'+side)
        bone('foot_'+side,ankle,ankle+Vector((0,-.12,0)),'shin_'+side)
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.data.name = 'SKEL_bunny01_v002'
    rig['skeleton_id'] = 'SKEL-BUNNY01-002'
    rig.show_in_front = True
    rig.data.display_type = 'OCTAHEDRAL'
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH' or 'bone_id' not in obj: continue
        component = obj['bone_id']
        obj['component_id'] = component
        obj['bone_id'] = 'waist' if component=='body' else component
        # Existing vertices, topology, UVs, material slots and transforms are untouched.
        obj.vertex_groups.clear()
        group = obj.vertex_groups.new(name=obj['bone_id'])
        group.add(list(range(len(obj.data.vertices))),1.0,'REPLACE')
        for modifier in obj.modifiers:
            if modifier.type == 'ARMATURE': modifier.object = rig
    from export_character_bundle import signature
    sig = signature(rig)
    rig['skeleton_sha256'] = sig
    scene = bpy.context.scene
    scene['skeleton_sha256'] = sig
    scene['file_role'] = 'model'
    scene['runtime_component_rest'] = json.dumps({k:[list(row) for row in m] for k,m in old_rest.items()})
    scene['motion_schema'] = 2
    model.parent.mkdir(parents=True,exist_ok=True)
    animation.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(model))

    # Linked geometry/materials; independent animation rig with identical rest data.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(model),link=True) as (_, dest):
        dest.collections=['01_部件']
    linked=dest.collections[0]
    bpy.context.scene.collection.children.link(linked)
    rig=bpy.data.objects['RIG_bunny01'].copy()
    rig.data=rig.data.copy()
    rig.name='RIG_bunny01'
    collection('00_共享骨架',bpy.context.scene.collection).objects.link(rig)
    preview=collection('01_动作预览_关联模型',bpy.context.scene.collection)
    for obj in list(linked.all_objects):
        if obj.type!='MESH': continue
        copy=obj.copy()
        preview.objects.link(copy)
        copy.parent=rig
        for mod in copy.modifiers:
            if mod.type=='ARMATURE': mod.object=rig
        copy.hide_render=obj.get('variant_id')=='chibi_anime'
        copy.hide_set(copy.hide_render)
    bpy.context.scene.collection.children.unlink(linked)
    scene=bpy.context.scene
    scene.unit_settings.system='METRIC'
    scene.render.fps=60
    scene['file_role']='animation'
    scene['skeleton_sha256']=sig
    scene['motion_schema']=2
    scene['model_source']='../model/chr_bunny01_model_v010.blend'
    scene['runtime_component_rest']=json.dumps({k:[list(row) for row in m] for k,m in old_rest.items()})
    rig.animation_data_create()
    rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
    # Endpoint goals preserve floating hands/feet. Intermediate bones articulate for future skins.
    def pose_cycle(state, t):
        run='moving' in state
        armed=state.startswith('armed_')
        w=TAU*t
        breath=math.sin(w)
        stride=math.sin(w)
        bounce=.5-.5*math.cos(2*w)
        sway=math.sin(w-.25)
        posed={n:m.copy() for n,m in rest.items()}
        waist_delta=transform((.012*sway if run else .008*math.sin(w),
                               -.018 if armed else 0,
                               (-.008+(.032 if not armed else .022)*bounce) if run else .010*breath),
                              ((.095 if armed else .06) if run else (.04 if armed else .012*breath),
                               .035*stride if run else .012*math.sin(w),
                               (.055 if not armed else .025)*stride if run else .018*math.sin(w)))
        posed['waist']=waist_delta@rest['waist']
        chest_delta=waist_delta@transform((0,0,.004*breath),(-.02*breath,.0,-.035*stride if run else -.012*math.sin(w-.3)))
        posed['chest']=chest_delta@rest['chest']
        head_delta=transform((.008*math.sin(w-.3),-.006 if armed else 0,
                             .012*bounce if run else .007*math.sin(w-.32)),
                            ((.025 if armed else 0)+.016*math.sin(w-.35), .014*math.sin(w-.2),
                             -.022*stride if run else .025*math.sin(w-.4)))
        posed['head']=head_delta@rest['head']
        for side,sign in [('l',-1),('r',1)]:
            phase=(t+(0 if side=='l' else .5))%1
            a=TAU*phase
            foot=old_rest['foot_'+side].translation.copy()
            if run:
                # Stance returns under the body; swing has a high passing pose and soft contact.
                if phase<.58:
                    u=phase/.58
                    foot.y+=-.135+.27*u
                    lift=0
                    pitch=.08*math.sin(math.pi*u)
                else:
                    u=(phase-.58)/.42
                    ease=u*u*(3-2*u)
                    foot.y+=.135-.27*ease
                    lift=(.10 if armed else .14)*math.sin(math.pi*u)**2
                    pitch=-.32*math.sin(TAU*u)
                foot.z+=lift
                foot.x+=sign*.008*math.sin(a)
            else:
                pitch=.012*math.sin(w+sign*.3)
            # Hand clear silhouettes: open relaxed sides versus a compact ready stance.
            wrist=old_rest['hand_'+side].translation.copy()
            if armed:
                wrist=Vector((sign*.19,-.235 if side=='r' else -.28,.43 if side=='r' else .415))
                wrist.z+=(.009*bounce if run else .005*breath)
                wrist.y+=.009*math.sin(w-.15)
                hand_rot=(.10+.035*breath,sign*.08,sign*.09)
            else:
                wrist.y+=sign*.14*stride if run else .012*math.sin(w-.35)
                wrist.z+=(.015+.025*bounce) if run else .010*math.sin(w-.25)
                wrist.x+=sign*(.012+.012*math.sin(w-.2))
                hand_rot=(sign*.48*stride if run else .07*math.sin(w-.4),0,sign*.08)
            for upper,lower,end,target,origin,bend in [
                ('upper_arm_','forearm_','hand_',wrist,chest_delta,Vector((sign*.07,.065,0))),
                ('thigh_','shin_','foot_',foot,waist_delta,Vector((0,-.075,0)))]:
                u,l,e=upper+side,lower+side,end+side
                start=origin@rest[u].translation
                joint=(start+target)*.5+bend
                for n,p,q in [(u,start,joint),(l,joint,target)]:
                    direction=q-p
                    rotation=Vector((0,1,0)).rotation_difference(direction.normalized())
                    posed[n]=Matrix.LocRotScale(p,rotation,Vector((1,direction.length/rig.data.bones[n].length,1)))
                # Endpoint rest orientation retained: rigid mesh orientation remains unchanged.
                rot=hand_rot if end=='hand_' else (pitch,0,sign*.02 if run else 0)
                posed[e]=transform(target,rot)@rest[e].to_3x3().to_4x4()
            for prefix in ['thumb','index','fingers']:
                for segment in ['01','02']:
                    n=prefix+'_'+segment+'_'+side
                    parent=rig.data.bones[n].parent.name
                    curl=(.38 if prefix=='thumb' else .58) if armed else .08
                    posed[n]=posed[parent]@rest[parent].inverted()@rest[n]@Euler((curl,0,0)).to_matrix().to_4x4()
            ear='ear_'+side
            lag=math.sin((2*w if run else w)-.65+sign*.18)
            posed[ear]=posed['head']@rest['head'].inverted()@rest[ear]@Euler(
                ((.13 if run else .045)*lag +(.09 if armed else 0),sign*.025*lag,sign*(.035+.03*lag))).to_matrix().to_4x4()
        return posed
    durations={'idle':3.2,'moving':.8,'armed_idle':2.8,'armed_moving':.8}
    for state,duration in durations.items():
        action=bpy.data.actions.new('anim_bunny01_'+state+'_v010')
        action.use_fake_user=True
        action['state_id']=state
        action['loop']=True
        action['duration']=duration
        action['authorship']='v010 original poses: breath / contact-down-pass-up / ready / stabilized armed stride'
        rig.animation_data.action=action
        total=round(duration*60)
        for index in range(total+1):
            posed=pose_cycle(state,index/total)
            for b in rig.data.bones:
                parent=b.parent.name if b.parent else None
                local=posed[parent].inverted()@posed[b.name] if parent else posed[b.name]
                rest_local=rest[parent].inverted()@rest[b.name] if parent else rest[b.name]
                p=rig.pose.bones[b.name]
                p.rotation_mode='QUATERNION'
                p.matrix_basis=rest_local.inverted()@local
                for prop in ['location','rotation_quaternion','scale']:
                    p.keyframe_insert(prop,frame=index+1,group=b.name)
        for curve in action.fcurves:
            curve.modifiers.new('CYCLES')
            for key in curve.keyframe_points:
                key.interpolation='BEZIER'
                key.handle_left_type=key.handle_right_type='AUTO_CLAMPED'
        for phase,label in [(0,'接触 / 起始'),(.145,'下沉'),(.36,'经过'),(.5,'交换支撑'),(.72,'腾起')]:
            marker=action.pose_markers.new(label)
            marker.frame=1+round(total*phase)
    rig.animation_data.action=bpy.data.actions['anim_bunny01_idle_v010']
    scene.frame_start=1
    scene.frame_end=193
    scene.frame_set(1)
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    rig.show_in_front=True
    # Save a convenient pose/Action Editor workspace, without adding preview geometry.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='DOPESHEET_EDITOR':
                area.spaces.active.mode='ACTION'
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_location=Vector((0,0,.65))
                area.spaces.active.region_3d.view_distance=2.7
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.wm.save_as_mainfile(filepath=str(animation),relative_remap=True)
    print('V010_AUTHORING_SAVED',model,animation)

if __name__=='__main__':
    import sys
    sys.path.insert(0,str(Path(__file__).resolve().parent))
    main()
