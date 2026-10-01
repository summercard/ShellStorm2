"""Saved-geometry plan audit against separately measured reference landmarks.

This checks roof-plane layout, not falsely rectified CAD or unknown shop interiors.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

R=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent))
import tower04_plan_v002 as P
folder=Path(bpy.data.filepath).parent
cat=json.loads((folder/'catalog.json').read_text(encoding='utf8'))
packages={p['slug']:p for p in cat['packages']}
# Independently read roof-surface bbox pixels from image2 (not wall bottoms).
truth={'oval_roof':[88,286,378,503],'leaf_canopy':[240,156,959,331],
 'glass_pavilion':[942,243,1154,389],'lawn_court':[970,354,1173,497],
 'planter_00':[595,349,679,438],'planter_01':[702,402,822,465],
 'planter_02':[875,322,936,375],'planter_03':[881,401,921,442]}
cam=bpy.data.objects['CAM_图纸校准']; sc=bpy.context.scene
sc.camera=cam; sc.render.resolution_x=1448; sc.render.resolution_y=1086
bpy.context.view_layer.update()
def points(slug):
    return [o.matrix_world@v.co for n in packages[slug]['objects'] for o in [bpy.data.objects[n]] for v in o.data.vertices]
def screen(v):
    q=world_to_camera_view(sc,cam,v); return (q.x*1448,(1-q.y)*1086)
errors=[]; checks=[]
for slug,ref in truth.items():
    vertices=points(slug); box=P.bounds([screen(v) for v in vertices])
    delta_center=[abs((box[j]+box[j+2]-ref[j]-ref[j+2])/2)/[1448,1086][j] for j in range(2)]
    delta_size=[abs((box[j+2]-box[j])-(ref[j+2]-ref[j]))/[1448,1086][j] for j in range(2)]
    contact=min(v.z for v in vertices)
    # Base slabs begin below their finish surface by documented source thickness.
    target={'oval_roof':24.78,'leaf_canopy':29.64,'glass_pavilion':25,'lawn_court':25.027}.get(slug,25.025)
    if slug=='leaf_canopy': target=29.64
    passed=max(delta_center)<=.05 and max(delta_size)<=.08 and abs(contact-target)<.035
    checks.append(dict(slug=slug,reference_bbox=ref,observed_bbox=box,normalized_center_error=delta_center,normalized_size_error=delta_size,observed_min_z=contact,expected_min_z=target,passed=passed))
    if not passed: errors.append('reference_bbox_or_base:'+slug)
# Pavilion end-to-end axis must have the same screen slope as the actual drawing.
a,b=P.PAVILION[0],P.PAVILION[1]
observed=math.degrees(math.atan2(screen(Vector((*b,25)))[1]-screen(Vector((*a,25)))[1],screen(Vector((*b,25)))[0]-screen(Vector((*a,25)))[0]))
reference=math.degrees(math.atan2(329-244,1150-977))
if abs(observed-reference)>5: errors.append('pavilion_axis')
# Actual floor triangle centroids of the painted strips must remain on roof.
for slug in ('slow_lane','main_walk'):
    for name in packages[slug]['objects']:
        ob=bpy.data.objects[name]
        for face in ob.data.polygons:
            if face.normal.z<.9: continue
            q=ob.matrix_world@face.center
            if not P.inside((q.x,q.y),P.DECK): errors.append('walkway_outside:'+slug); break
            if slug=='slow_lane' and any(P.inside((q.x,q.y),poly) for poly in P.ISLANDS+[P.LAWN]):
                errors.append('slow_lane_under_landscape:'+slug); break
# Exposed void witness locations must contain neither deck nor painted floor.
witness=[P.xy(p) for p in [(429,369),(488,407),(519,440)]]
if any(P.inside(p,P.DECK) for p in witness): errors.append('crescent_filled')
report=dict(passed=not errors,errors=errors,checks=checks,pavilion_axis_error_deg=abs(observed-reference),deck_floor_bounds=P.bounds(P.DECK),roof_z=25,canopy_clearance_height=4.8,guardrail_height=1.2,planter_height=.6,walkway_widths_nominal=[2,4],void_witnesses=witness,no_post_build_scaling=cat['no_post_build_scaling'],uncertainties=cat['uncertainties'],interpretation='roof-plane trace correspondence; original perspective sketch is not a measured CAD survey')
(folder/'qa/reference_plan_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2))
raise SystemExit(0 if not errors else 1)
