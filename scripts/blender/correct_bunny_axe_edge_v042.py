"""Roll the authored axe grip so its silver -X edge leads the downward cut."""
from pathlib import Path
import bpy, math, sys, json
from mathutils import Quaternion, Vector
R=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(R/'scripts'))
from workspace_paths import work_path
SOURCE=R/'art_source/characters/player/chr_player_capsule01_3d/variants/bunny01/source/animation/chr_bunny01_animation_v041.blend'
TARGET=SOURCE.with_name('chr_bunny01_animation_v042.blend')
if not SOURCE.exists():
    SOURCE=R.parent/'ShellStorm2-backup/2026-10-17_axe_edge_v042/retired_sources/chr_bunny01_animation_v041.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
for library in bpy.data.libraries:
    if 'chr_bunny01_model_v021.blend' in library.filepath:
        model=R/'art_source/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v021/source/model/chr_bunny01_model_v021.blend'
        if Path(bpy.path.abspath(library.filepath)).resolve()!=model.resolve():
            library.filepath=str(model)
            library.reload()
roll=Quaternion((0,1,0),-math.pi/2)
report={}
for scene in bpy.data.scenes:
    state=scene.get('preview_clip','')
    if not state.startswith('melee_axe_'):continue
    bpy.context.window.scene=scene
    grip=next(o for o in scene.objects if o.name.startswith('PREVIEW_GripSocket'))
    action=grip.animation_data.action
    first,last=map(int,action.frame_range)
    values=[]
    for f in range(first,last+1):
        scene.frame_set(f)
        values.append((f,grip.rotation_quaternion.copy()@roll))
    previous=None
    for f,q in values:
        if previous is not None and previous.dot(q)<0:q.negate()
        grip.rotation_quaternion=q;grip.keyframe_insert('rotation_quaternion',frame=f);previous=q.copy()
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
    # Blade plane local XY must lie in the forward/vertical cutting plane.
    min_alignment=1.0
    for f,q in values:
        normal=q@Vector((0,0,1))
        min_alignment=min(min_alignment,abs(normal.x))
    assert min_alignment>.98,(state,min_alignment)
    if state.endswith('_active'):
        scene.frame_set(first+round((last-first)*.45))
        edge=grip.rotation_quaternion@Vector((-1,0,0))
        assert edge.z<-.98,(state,tuple(edge))
    scene['source_revision']='v042_axe_edge_alignment'
    report[state]={'blade_plane_normal_lateral_alignment':min_alignment,'roll_degrees':-90}
assert len(report)==14,len(report)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=True)
out=work_path('sessions/2026-10-17_axe_edge_v042/source_alignment.json')
out.write_text(json.dumps(report,indent=2))
print('AXE_EDGE_SOURCE_OK',len(report))
