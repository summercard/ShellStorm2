import bpy,json,math
from pathlib import Path
from mathutils import Vector
P=Path('/Users/summercards/ShellStorm2');R=P/'outputs/verification/base_facility_loft_v019'
cat=json.loads((R/'catalog.json').read_text())
def setface(o,p,ce):
 u=o.data.uv_layers['PaletteUV']
 for j,li in enumerate(p.loop_indices):a=j*math.tau/len(p.loop_indices)+.3;u.data[li].uv=(ce[0]+.022*math.cos(a),ce[1]+.022*math.sin(a))
for rec in cat:
 c=bpy.data.collections[rec['collection']];slug=rec['package_id']
 for o in c.all_objects:
  if o.type!='MESH':continue
  if slug=='loft_pouf_01':o.location+=Vector((-3.10,-.55,0))
  for p in o.data.polygons:
   u=o.data.uv_layers['PaletteUV'];a=u.data[p.loop_start].uv;ce=((math.floor(a.x*10)+.5)/10,(math.floor(a.y*10)+.5)/10);new=None
   if slug=='loft_floor_finish' and abs(ce[1]-.75)<.01:new=(max(.05,ce[0]-.20),.75)
   elif slug=='loft_bed_and_bedding' and abs(ce[1]-.45)<.01:new=(.25,.45)
   elif slug=='loft_lounge_sofa' and abs(ce[1]-.45)<.01:new=(max(.15,ce[0]-.15)//.1*.1+.05,.45)
   elif slug=='loft_explore_poster' and abs(ce[0]-.85)<.01 and abs(ce[1]-.75)<.01:new=(.95,.95)
   if new:setface(o,p,new)
  o.data.uv_layers.active_index=0;o.data.uv_layers['PaletteUV'].active_render=True
bpy.context.view_layer.update()
for rec in cat:
 out=bpy.data.collections[rec['output_collection']];pts=[o.matrix_world@Vector(p) for o in out.objects if o.type=='MESH' for p in o.bound_box];lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)];rec['center']=[(a+b)/2 for a,b in zip(lo,hi)];rec['dimensions']=[b-a for a,b in zip(lo,hi)];rec['local_origin']=[rec['center'][0],rec['center'][1],lo[2]]
 folder=P/'source/art/blender/base_facility_layout/component_packages/v019'/rec['package_id'];(folder/'asset_manifest.json').write_text(json.dumps(rec,ensure_ascii=False,indent=2))
(R/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
