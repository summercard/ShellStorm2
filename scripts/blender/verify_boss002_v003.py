import bpy,json
from pathlib import Path
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v003.blend'))
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;dg=bpy.context.evaluated_depsgraph_get();n=0
for o in s.objects:
    if o.type=='MESH':
        e=o.evaluated_get(dg);m=e.to_mesh();m.calc_loop_triangles();n+=len(m.loop_triangles);e.to_mesh_clear()
images=[bpy.data.materials[x].node_tree.nodes for x in ['Image2 green terminal','Image2 flat facial atlas']]
checks={'under_20000':n<20000,'no_text_geometry':not any(o.type=='FONT' or o.name.startswith('Key legend') for o in s.objects),'no_rig':len(bpy.data.armatures)==0,'no_actions':len(bpy.data.actions)==0,'applied_modifiers':all(len(o.modifiers)==0 for o in s.objects),'textures_packed':all(any(node.type=='TEX_IMAGE' and node.image.packed_file for node in nodes) for nodes in images),'four_fingers':all(bpy.data.objects['Sculpted glove '+side].get('finger_count')==4 for side in ['L','R']),'three_face_planes':len([o for o in s.objects if o.name.startswith('Texture ')])==3}
out={'triangles_reopened':n,'checks':checks,'passed':all(checks.values())};(B/'previews/optimized_v003/reopen_audit.json').write_text(json.dumps(out,indent=2),encoding='utf-8');print(json.dumps(out));assert out['passed']
