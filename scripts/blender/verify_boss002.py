import bpy,json,math,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/enemies/bosses/enm_boss_monitor002'
version='v002' if '--v002' in sys.argv else 'v001'
bpy.ops.wm.open_mainfile(filepath=str(BASE/f'source/enm_boss_monitor002_source_{version}.blend'))
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s
obs=list(s.objects);dg=bpy.context.evaluated_depsgraph_get();verts=[];tri=0
for o in obs:
    if o.type not in ['MESH','CURVE','FONT']:continue
    e=o.evaluated_get(dg);m=e.to_mesh();verts.extend(o.matrix_world@v.co for v in m.vertices);m.calc_loop_triangles();tri+=len(m.loop_triangles);e.to_mesh_clear()
lo=[min(p[i] for p in verts) for i in range(3)];hi=[max(p[i] for p in verts) for i in range(3)]
face=[o for o in obs if o.get('face_flat')]
flatness={o.name:max((o.matrix_world@v.co).y for v in o.data.vertices)-min((o.matrix_world@v.co).y for v in o.data.vertices) for o in face}
coils=[o for o in obs if o.name.startswith('Continuous spring cable')]
gloves=[o for o in obs if o.name.startswith('Sculpted glove')]
checks={'no_armatures':not any(o.type=='ARMATURE' for o in bpy.data.objects),'no_armature_modifiers':not any(m.type=='ARMATURE' for o in obs for m in o.modifiers),'no_actions':len(bpy.data.actions)==0,'no_vertex_weights':all(len(o.vertex_groups)==0 for o in obs if o.type=='MESH'),'source_only_asset':all(o.type in ['MESH','CURVE','FONT'] for o in obs),'face_is_flat':len(face)>10 and max(flatness.values())<1e-5,'two_spring_arms':len(coils)==2,'tpose_level_palms':len(gloves)==2 and abs(gloves[0].location.z-gloves[1].location.z)<.001,'unit_scale':all(max(abs(v-1) for v in o.scale)<1e-5 for o in obs),'standing_on_ground':abs(lo[2])<.015,'portrait_screen':bpy.data.objects['Portrait display'].dimensions.z>bpy.data.objects['Portrait display'].dimensions.x*1.5,'code_editable':len([o for o in obs if o.name.startswith('CODE_')])==21,'face_floats_in_front':all(min((o.matrix_world@v.co).y for v in o.data.vertices)>.4 for o in face),'source_reference_present':(BASE/'reference/design.png').exists()}
out={'asset_id':'ENM-BOSS-MONITOR002-3D','checks':checks,'passed':all(checks.values()),'object_count':len(obs),'evaluated_triangles':tri,'bounds_min':lo,'bounds_max':hi,'dimensions_m':[hi[i]-lo[i] for i in range(3)],'planar_face_max_deviation_m':max(flatness.values()),'armatures':len(bpy.data.armatures),'actions':len(bpy.data.actions),'runtime_validation':'not executed; source-only user scope'}
(BASE/('previews/hands_v002/source_audit.json' if version=='v002' else 'previews/source_audit.json')).write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(out,ensure_ascii=False,indent=2))
assert out['passed'],checks
