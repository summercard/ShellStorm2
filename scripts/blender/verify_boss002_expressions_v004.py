import bpy,json,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/expressions_v004'
def digest(o):return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'p':[list(p.vertices) for p in o.data.polygons],'matrix':[list(r) for r in o.matrix_world]}).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v003.blend'))
before={o.name:digest(o) for o in bpy.data.scenes['BOSS002_SOURCE_TPOSE'].objects if o.type=='MESH' and not o.name.startswith('Texture ')}
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v004.blend'))
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;ctrl=bpy.data.objects['ExpressionController'];mat=bpy.data.materials['Boss002 Expressions large_eye'];offset=next(n for n in mat.node_tree.nodes if n.type=='COMBXYZ');tex=next(n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE')
states=[]
for i in range(6):
    s.frame_set(1+i*24);bpy.context.view_layer.update()
    slots={}
    for slot in ['large_eye','round_eye','mouth']:
        mm=bpy.data.objects['Texture '+slot].data.materials[0];cc=[n for n in mm.node_tree.nodes if n.type=='COMBXYZ'];slots[slot]={'offset':[cc[0].inputs[j].default_value for j in range(2)],'size':[cc[1].inputs[j].default_value for j in range(2)]}
    states.append({'frame':1+i*24,'expression_index':ctrl['expression_index'],'offset':[offset.inputs[j].default_value for j in range(2)],'slots':slots})
tri=0
for o in s.objects:
    if o.type=='MESH':o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
checks={'body_unchanged':all(digest(bpy.data.objects[n])==v for n,v in before.items()),'triangles_18144':tri==18144,'six_switch_states':all(st['expression_index']==i for i,st in enumerate(states)),'uv_driver_offsets':all(abs(st['offset'][0]-(i%3)/3)<1e-6 and abs(st['offset'][1]+(i//3)/2)<1e-6 for i,st in enumerate(states)),'texture_packed':bool(tex.image.packed_file),'atlas_size':list(tex.image.size)==[1536,1024],'no_armature':len(bpy.data.armatures)==0,'only_preview_action':len(bpy.data.actions)==1 and bpy.data.actions[0].name=='BOSS002_expression_switch_preview','three_face_planes':len([o for o in s.objects if o.name.startswith('Texture ')])==3}
lib=json.loads((B/'source/expression_library_v004.json').read_text())
checks['actual_slot_sampling']=all(abs(states[i]['slots'][slot]['offset'][0]-box[0]/1536)<1e-6 and abs(states[i]['slots'][slot]['offset'][1]-(1-box[3]/1024))<1e-6 and abs(states[i]['slots'][slot]['size'][0]-(box[2]-box[0])/1536)<1e-6 for slot,boxes in lib['per_expression_slot_boxes_pixels'].items() for i,box in enumerate(boxes))
checks.pop('uv_driver_offsets')
report={'checks':checks,'passed':all(checks.values()),'triangles':tri,'states':states,'default_frame':1,'preview_frames':[1,25,49,73,97,121],'runtime_integration':False};(P/'audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report,indent=2));assert report['passed']
