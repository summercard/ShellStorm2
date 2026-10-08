"""Subtle angled longgun/machinegun carry; preserve all firing/sidearm actions."""
from pathlib import Path
import sys,json,math,ast
import bpy
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_bunny_directional_v027 as d
h=d.h
tree=ast.parse((Path(__file__).parent/'author_bunny_firing_v030.py').read_text(encoding='utf-8'))
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='solve'],type_ignores=[]),'<arm-solver>','exec'))
SOURCE=h.BASE/'source/animation/chr_bunny01_animation_v030.blend'
TARGET=h.BASE/'source/animation/chr_bunny01_animation_v031.blend'
OUT=h.ROOT/'outputs/character_pipeline/carry_v031'

def geometry(obj,dg):
    eo=obj.evaluated_get(dg);mesh=eo.to_mesh()
    verts=[eo.matrix_world@v.co for v in mesh.vertices]
    tree=BVHTree.FromPolygons(verts,[list(p.vertices) for p in mesh.polygons])
    eo.to_mesh_clear();return tree,verts

assert not TARGET.exists() or '--replace-generated' in sys.argv
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
original={a.name:h.curves_digest(a) for a in bpy.data.actions if not a.library}
for a in bpy.data.actions:
    if not a.library:a.use_fake_user=True
report={}
for scene in list(bpy.data.scenes):
    state=scene.get('preview_clip','')
    if not state.startswith(('longgun_','machinegun_')) or '_fire_' in state:continue
    family=state.split('_')[0];bpy.context.window.scene=scene
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    gun=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
    rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
    prior=rig.animation_data.action;first,last=map(int,prior.frame_range);period=last-first
    samples=[];guns=[]
    for f in range(first,last+1):
        scene.frame_set(f);dg=bpy.context.evaluated_depsgraph_get()
        samples.append({p.name:p.matrix.copy() for p in rig.evaluated_get(dg).pose.bones})
        guns.append(gun.evaluated_get(dg).matrix_world.copy())
    a=bpy.data.actions.new('anim_bunny01_'+state+'_v031')
    for k in prior.keys():a[k]=prior[k]
    rig.animation_data.action=a
    gun.animation_data.action=bpy.data.actions.new('PREVIEW_ONLY_'+state+'_v031')
    gun.animation_data.action['preview_only']=True
    previous={}
    shift=Vector((0,-.035,0)) if family=='machinegun' else Vector()
    pitch=math.radians(-4 if family=='longgun' else -6)
    for i,source in enumerate(samples):
        posed={n:m.copy() for n,m in source.items()}
        p=guns[i].translation+shift
        rot=Matrix.Rotation(math.radians(-8),4,'Z')@guns[i].to_quaternion().to_matrix().to_4x4()@Matrix.Rotation(pitch,4,'X')
        solve(rig,rest,posed,'r',p)
        solve(rig,rest,posed,'l',p+rot.to_3x3()@Vector(gun['support_local']))
        h.key_pose(rig,rest,posed,i+first,previous)
        gun.location=p;gun.rotation_mode='QUATERNION';gun.rotation_quaternion=rot.to_quaternion()
        for prop in ('location','rotation_quaternion'):gun.keyframe_insert(prop,frame=i+first)
    h.cyclic(a,period);h.cyclic(gun.animation_data.action,period)
    scene['source_revision']='v031_reference_carry_angle';scene['production_status']='authored'
    err=0.;preserved=0.;scale=0.;start=None
    for i in range(period*2+1):
        f=first+i/2;scene.frame_set(int(f),subframe=f%1);dg=bpy.context.evaluated_depsgraph_get()
        er=rig.evaluated_get(dg);gm=gun.evaluated_get(dg).matrix_world;rotation=gm.to_quaternion().to_matrix()
        mats={p.name:p.matrix.copy() for p in er.pose.bones}
        if start is None:start=mats
        for side in ('r','l'):
            wanted=gm.translation+(rotation@Vector(gun['support_local']) if side=='l' else Vector())
            err=max(err,(er.pose.bones['hand_'+side].tail-wanted).length)
        scale=max(scale,*(abs(v-1) for m in mats.values() for v in m.to_scale()))
        if i%2==0:
            for n in ('root','chest','head','ear_l','ear_r','foot_l','foot_r'):
                preserved=max(preserved,*(abs(mats[n][x][y]-samples[i//2][n][x][y]) for x in range(4) for y in range(4)))
    loop=max(abs(mats[n][x][y]-start[n][x][y]) for n in mats for x in range(4) for y in range(4))
    assert max(err,preserved,scale,loop)<1e-4,(state,err,preserved,scale,loop)
    intersections=0;gap=10.
    for f in [first,first+period*.25,first+period*.5,first+period*.75,last]:
        scene.frame_set(int(f),subframe=f%1);dg=bpy.context.evaluated_depsgraph_get()
        bodies=[o for o in scene.objects if o.type=='MESH' and not o.hide_render and o.name.startswith(('SRC_Body','SRC_Head'))]
        weapons=[o for o in scene.objects if o.type=='MESH' and o.get('preview_only') and not o.hide_render]
        assert bodies and weapons
        for b in bodies:
            tb,vb=geometry(b,dg)
            for g in weapons:
                tg,vg=geometry(g,dg);intersections+=len(tb.overlap(tg))
                gap=min(gap,min(tb.find_nearest(v)[3] for v in vg),min(tg.find_nearest(v)[3] for v in vb))
    report[state]=dict(grip_error=err,preserved_body_ears_feet_error=preserved,unit_scale_error=scale,loop_error=loop,body_head_intersections=intersections,min_surface_gap=gap,offset=list(shift),yaw_delta_deg=-8,pitch_delta_deg=math.degrees(pitch))
    print('CARRY_REFINED',state,'intersections',intersections,'gap',gap,flush=True)
    assert intersections==0,(state,intersections)
    scene.frame_set(1)
assert len(report)==18
assert all(h.curves_digest(bpy.data.actions[n])==v for n,v in original.items())
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'source_validation.json').write_text(json.dumps(report,indent=2))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)
print('V031_AUTHORED',len(report),flush=True)
