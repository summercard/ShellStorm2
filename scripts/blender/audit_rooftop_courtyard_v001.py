import bpy,json,math,sys,hashlib
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');O=R/'outputs/rooftop_courtyard_v001'
s=bpy.data.scenes['复古天台庭院_v001'];bpy.context.window.scene=s;s.frame_set(1);bpy.context.view_layer.update()
out=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
objs=[o for o in out.all_objects if o.type=='MESH'];dg=bpy.context.evaluated_depsgraph_get();tri=0;areas={'neutral':0.,'accent':0.};bounds=[]
for ob in objs:
    ev=ob.evaluated_get(dg);me=ev.to_mesh();me.calc_loop_triangles();tri+=len(me.loop_triangles)
    uv=me.uv_layers['PaletteUV']
    for poly in me.polygons:
        u=uv.data[poly.loop_start].uv;col=int(u.x*10);row=int(u.y*10)
        key='neutral' if col==9 or (col==8 and row in [0,6,7]) else 'accent';areas[key]+=poly.area
    bounds.extend([ob.matrix_world@Vector(v) for v in ob.bound_box]);ev.to_mesh_clear()
slab=next(o for o in objs if o.get('package_id')=='courtyard_slab');bbox=[slab.matrix_world@Vector(v) for v in slab.bound_box]
size=[max(v[i] for v in bbox)-min(v[i] for v in bbox) for i in range(3)]
assert abs(size[0]-15)<1e-5 and abs(size[1]-10)<1e-5
assert tri<200000
empty=[c.name for c in out.children if not any(o.type=='MESH' for o in c.all_objects)]
multiple=[o.name for o in objs if len(o.users_collection)!=1];assert not empty and not multiple
# Confirm 10 cm rise, not slab thickness counted as decking.
deck=next(o for o in objs if o.get('package_id')=='timber_deck');decktop=max((deck.matrix_world@Vector(v)).z for v in deck.bound_box);slabtop=max(v.z for v in bbox)
assert abs(decktop-slabtop-.105)<.015
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
for p in m['packages']:
    pos=[o for o in objs if o.get('package_id')==p['package_id']];pts=[o.matrix_world@Vector(v) for o in pos for v in o.bound_box]
    p['bbox_world']=[[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]]
    p['dimensions']=[p['bbox_world'][1][i]-p['bbox_world'][0][i] for i in range(3)]
    folder=R/'art_source/environments/rooftop_courtyard_3d/source/prp_rooftop_courtyard'/('component_packages_'+m['version'])/p['package_id']
    (folder/'asset_manifest.json').write_text(json.dumps(p,ensure_ascii=False,indent=2),encoding='utf-8')
m['bbox_world']=[[min(v[i] for v in bounds) for i in range(3)],[max(v[i] for v in bounds) for i in range(3)]]
m['evaluated_triangles']=tri;m['neutral_surface_area_ratio']=areas['neutral']/sum(areas.values())
(O/'asset_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
report={'passed':True,'slab_dimensions_m':size,'slab_top_z':slabtop,'deck_top_z':decktop,'deck_rise_m':decktop-slabtop,'triangles_evaluated':tri,'triangle_limit':200000,'packages':len(m['packages']),'output_meshes':len(objs),'empty_packages':empty,'multi_owner_objects':multiple,'neutral_surface_area_ratio':m['neutral_surface_area_ratio'],'accent_surface_area_ratio':1-m['neutral_surface_area_ratio'],'bbox_world':m['bbox_world'],'source_original_scene_backup':'session_before.blend','existing_rooftop_modified':False,'runtime_integrated':False,'notes':['Area ratio is geometry area, not projected rendered pixel ratio; saturation judged on render.','14 specified motions tracked in feature acceptance, not all accepted automatically.']}
(O/'task_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(report,ensure_ascii=False))
