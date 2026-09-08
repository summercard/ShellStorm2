import bpy,json,importlib.util,hashlib
from pathlib import Path
from mathutils import Vector
P=Path('/Users/summercards/ShellStorm2');R=P/'outputs/verification/base_facility_east_v021'
spec=importlib.util.spec_from_file_location('v',P/'.codex/skills/blender-game-prop-standard/scripts/validate_game_prop.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
cat=json.loads((R/'catalog.json').read_text());results=[]
for rec in cat:
 c=bpy.data.collections[rec['collection']];output=bpy.data.collections[rec['output_collection']];uv=[v.audit_palette_uv(o) for o in c.all_objects if o.type=='MESH'];bbox=[]
 for o in output.objects:
  if o.type=='MESH':bbox.extend(o.matrix_world@Vector(p) for p in o.bound_box)
 actual=[[min(p[i] for p in bbox) for i in range(3)],[max(p[i] for p in bbox) for i in range(3)]]
 badmat=[]
 for o in c.all_objects:
  if o.type!='MESH':continue
  for m in o.data.materials:
   for n in m.node_tree.nodes:
    if n.type=='TEX_IMAGE' and (Path(bpy.path.abspath(n.image.filepath)).resolve()!=P/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png' or n.image.packed_file or n.interpolation!='Closest'):badmat.append(m.name)
 results.append({'collection':c.name,'uv_pass':all(u['valid_island_polygon_count']==u['polygon_count'] and u['active_uv']=='PaletteUV' and u['active_render_uv']=='PaletteUV' and not u['extra_uv_layers'] for u in uv),'faces':sum(u['polygon_count'] for u in uv),'valid_islands':sum(u['valid_island_polygon_count'] for u in uv),'material_errors':sorted(set(badmat)),'unique_ownership':all(len(o.users_collection)==1 for o in c.all_objects),'not_empty':len(output.objects)>0,'bbox':actual,'source_hidden':bpy.data.collections[rec['source_collection']].hide_render and bpy.data.collections[rec['source_collection']].hide_viewport,'output_count':len(output.objects)})
rep={'passed':all(x['uv_pass'] and not x['material_errors'] and x['unique_ownership'] and x['not_empty'] and x['source_hidden'] for x in results),'packages':results}
# Ground facilities must have disjoint plan envelopes; distributed plant instances are excluded.
pairs=[]
physical=[x for x in results if not x['collection'].startswith('83_')]
for i,a in enumerate(physical):
 for b in physical[i+1:]:
  overlap=[min(a['bbox'][1][k],b['bbox'][1][k])-max(a['bbox'][0][k],b['bbox'][0][k]) for k in [0,1]]
  if all(t>0.015 for t in overlap):pairs.append({'a':a['collection'],'b':b['collection'],'xy_overlap':overlap})
rep['layout_overlaps']=pairs;rep['layout_pass']=not pairs;rep['passed']=rep['passed'] and not pairs
(R/'scoped_validation.json').write_text(json.dumps(rep,ensure_ascii=False,indent=2));print('SCOPED',rep['passed'])
