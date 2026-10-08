"""Reopen source: grip endpoints, scale, loops and untouched clips."""
from pathlib import Path
import sys,json,math
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import author_bunny_weapon_idles_v025 as h
SOURCE=h.BASE/'source/animation/chr_bunny01_animation_v032.blend'
OUT=h.ROOT/'outputs/character_pipeline/switch_v032'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
result={}
for scene in bpy.data.scenes:
    name=scene.get('preview_clip','')
    transition=('_stow_' in name or '_draw_' in name)
    swing=name.startswith('unarmed_') and name.endswith(('forward','backward'))
    if not transition and not swing:continue
    bpy.context.window.scene=scene;rig=next(o for o in scene.objects if o.type=='ARMATURE')
    gun=next((o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket')),None) if transition else None
    a=rig.animation_data.action;first,last=map(int,a.frame_range);scale=0.;grip=0.;samples=[]
    for i in range((last-first)*2+1):
        f=first+i/2;scene.frame_set(int(f),subframe=f%1);dg=bpy.context.evaluated_depsgraph_get();er=rig.evaluated_get(dg)
        scale=max(scale,*(abs(v-1) for p in er.pose.bones for v in p.matrix.to_scale()))
        samples.append(er.pose.bones['hand_r'].tail.copy())
        if gun:grip=max(grip,(er.pose.bones['hand_r'].tail-gun.evaluated_get(dg).matrix_world.translation).length)
    assert scale<1e-4 and grip<.002,(name,scale,grip)
    span=max(p.y for p in samples)-min(p.y for p in samples)
    if swing:
        assert span>.4 and (samples[0]-samples[-1]).length<1e-4,(name,span)
    if transition:
        target=Vector((-.36 if name.endswith('0') else .36,-.54,.82))
        assert (samples[-1 if '_stow_' in name else 0]-target).length<1e-4
    result[name]=dict(scale_error=scale,grip_error=grip,palm_forward_back_span=span)
(OUT/'source_validation.json').write_text(json.dumps(result,indent=2))
print('V032_SOURCE_VALIDATED',len(result))
