import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
O=R/'outputs/bird_flocks_v001'; O.mkdir(exist_ok=True)
kind='flyby' if 'flyby' in bpy.data.filepath else 'ground'
s=bpy.context.scene
meshes=[o for o in s.objects if o.type=='MESH']; rigs=[o for o in s.objects if o.type=='ARMATURE']
report={'kind':kind,'mesh_count':len(meshes),'rig_count':len(rigs),'material_count':len(bpy.data.materials),'frames':s.frame_end,'min_floor_z':100,'min_bird_spacing':100,'max_root_step':0,'nonfinite':0,'all_keyframes_baked':all(o.animation_data for o in rigs)}
previous={}
for f in range(1,s.frame_end+1):
    s.frame_set(f)
    for o in rigs:
        p=o.matrix_world.translation
        if o.name in previous:report['max_root_step']=max(report['max_root_step'],(p-previous[o.name]).length)
        previous[o.name]=p.copy()
        if not all(math.isfinite(v) for v in p):report['nonfinite']+=1
    report['min_bird_spacing']=min(report['min_bird_spacing'],min((a.matrix_world.translation-b.matrix_world.translation).length for i,a in enumerate(rigs) for b in rigs[i+1:]))
    if kind=='ground':
        deps=bpy.context.evaluated_depsgraph_get()
        for o in meshes:
            ev=o.evaluated_get(deps); me=ev.to_mesh()
            z=min((ev.matrix_world@v.co).z for v in me.vertices)
            if z<report['min_floor_z']:report['min_floor_z']=z; report['floor_min_at']=[f,o.name]
            ev.to_mesh_clear()
report['passed']=report['mesh_count']==7 and report['rig_count']==7 and report['nonfinite']==0 and (kind!='ground' or report['min_floor_z']>-.012)
(O/f'{kind}_motion_qa.json').write_text(json.dumps(report,indent=2),encoding='utf-8'); print(report,flush=True)
if '--check-only' in sys.argv:raise SystemExit(0 if report['passed'] else 1)
# Preview support only; not saved in either source asset.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.009)); floor=bpy.context.object; floor.name='仅视频地面'
mat=bpy.data.materials.new('仅视频背景'); mat.diffuse_color=(.058,.083,.11,1); mat.use_nodes=True; mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=mat.diffuse_color; mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.9; floor.data.materials.append(mat)
s.render.engine='BLENDER_WORKBENCH'; s.render.resolution_x=960; s.render.resolution_y=600; s.render.resolution_percentage=100
s.display.shading.light='STUDIO'; s.display.shading.studio_light='paint.sl'; s.display.shading.show_shadows=True; s.display.shading.show_cavity=True; s.display.shading.cavity_type='BOTH'
s.display.shading.show_specular_highlight=False; s.display.render_aa='8'
s.render.image_settings.file_format='PNG'
frames=O/(kind+'_frames'); frames.mkdir(exist_ok=True)
for f in range(1,s.frame_end,2):
    s.frame_set(f); s.render.filepath=str(frames/f'{(f-1)//2:04d}.png'); bpy.ops.render.render(write_still=True)
print('PREVIEW_DONE',kind,flush=True)
