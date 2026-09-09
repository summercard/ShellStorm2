"""Close cyclic Actions in the specified animation master with a smooth end correction."""
import sys
from pathlib import Path
import bpy

path=Path(sys.argv[sys.argv.index('--')+1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(path))
bpy.context.preferences.filepaths.save_version=0
for action in bpy.data.actions:
    if not action.get('loop',False): continue
    for curve in action.fcurves:
        points=list(curve.keyframe_points)
        if not points: continue
        start,end=points[0].co.x,points[-1].co.x
        difference=points[-1].co.y-points[0].co.y
        for point in points:
            t=max(0.0,min(1.0,((point.co.x-start)/(end-start)-0.75)/0.25))
            point.co.y-=difference*t*t*(3-2*t)
    action['loop_seam']='last quarter smooth correction to first key'
bpy.ops.wm.save_as_mainfile(filepath=str(path))
print('CHARACTER_ACTION_LOOPS_CLOSED')
