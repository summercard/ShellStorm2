
import sys as _art_source_sys
from pathlib import Path as _ArtSourcePath
_art_source_sys.path.insert(0, str(_ArtSourcePath(__file__).resolve().parents[1]))
from art_source_paths import source_path
import bpy,json,math,hashlib,shutil
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');O=R/'outputs/rooftop_courtyard_v001';B=R/'assets/art/environments/rooftop_courtyard_3d'
s=bpy.data.scenes['复古天台庭院_v001'];bpy.context.window.scene=s;s.frame_set(1);bpy.context.view_layer.update()
# Save geometry refinement as new source, preserve v001.
DEST=source_path(B/'source/prp_rooftop_courtyard/prp_rooftop_courtyard_source_v002.blend')
# Remove factory data that are not part of this facility.
for ob in list(bpy.data.objects):
    if ob.name in ('Cube','Camera','Light'):bpy.data.objects.remove(ob,do_unlink=True)
used={m for ob in s.objects if ob.type=='MESH' for m in ob.data.materials if m}
for mat in list(bpy.data.materials):
    if mat not in used:bpy.data.materials.remove(mat,do_unlink=True)
# Clamp slab surface-only detail geometry to actual base. Foundation corners unaffected.
for ob in s.objects:
    if ob.type=='MESH' and ob.get('package_id')=='courtyard_slab':
        for v in ob.data.vertices:
            if v.co.z>.32:v.co.x=max(-7.48,min(7.48,v.co.x));v.co.y=max(-4.98,min(4.98,v.co.y))
# Warm gray timber, avoid random blue boards across big surfaces.
for ob in s.objects:
    if ob.type!='MESH':continue
    if ob.get('package_id') in ['timber_deck','corduroy_sofa']:
        uv=ob.data.uv_layers['PaletteUV']
        for p in ob.data.polygons:
            u=uv.data[p.loop_start].uv
            if int(u.x*10)==9 and int(u.y*10)==7:
                for li in p.loop_indices:uv.data[li].uv.x-=.1;uv.data[li].uv.y-=.7
    if ob.get('package_id') in ['crt_television','valve_radio','leather_case_1','leather_case_2','leather_case_3','side_table'] and '自发光' not in ob.name and '可编辑源' not in ob.name:
        # Preserve palette material boundary while rounding visible focus box edges.
        mod=ob.modifiers.new('细腻圆角_一段','BEVEL');mod.width=.013;mod.segments=2;mod.affect='EDGES';mod.limit_method='ANGLE'
        bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.modifier_apply(modifier=mod.name);ob.select_set(False)
        uv=ob.data.uv_layers['PaletteUV']
        for p in ob.data.polygons:
            coords=[uv.data[li].uv.copy() for li in p.loop_indices];u=sum(t.x for t in coords)/len(coords);v=sum(t.y for t in coords)/len(coords);c=min(9,max(0,int(u*10)));r=min(9,max(0,int(v*10)))
            for j,li in enumerate(p.loop_indices):a=math.tau*j/len(p.loop_indices);uv.data[li].uv=((c+.5)/10+.025*math.cos(a),(r+.5)/10+.025*math.sin(a))
# Light-energy flicker is confined to display lights (room lights belong to Godot later).
for name,base in [('棚下灯泡暖光',75),('收音机灯丝近光',5)]:
    d=bpy.data.objects[name].data
    for f in range(1,242,12):d.energy=base*(1+.045*math.sin(f*.33)+.025*math.sin(f*.73));d.keyframe_insert(data_path='energy',frame=f)
# Physical paper corner surface: pages and newspaper aren't interface geometry.
out=next(c for c in bpy.data.collections if c.name.startswith('02_游戏输出'))
mat=bpy.data.materials['02_细腻哑光_青绿大面']
m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
for slug,zh,pos,size in [('open_book_page','50_微风旧书书页',(-2.54,-.2,1.18),(.61,.42)),('newspaper_corner','51_报纸微翘边角',(-.56,2.27,1.41),(.12,.38))]:
    c=bpy.data.collections.new(zh+'_资产包');out.children.link(c);e=bpy.data.objects.new('prp_'+slug+'_root',None);c.objects.link(e);e.location=pos;e['package_id']=slug;e['asset_version']='v002'
    verts=[];faces=[]
    for j in range(5):
        for i in range(7):verts.append(((i/6-.5)*size[0],(j/4-.5)*size[1],.005+.012*(i/6)**3))
    for j in range(4):
        for i in range(6):faces.append((j*7+i,j*7+i+1,(j+1)*7+i+1,(j+1)*7+i))
    me=bpy.data.meshes.new(slug);me.from_pydata(verts,[],faces);me.materials.append(mat);uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
    for p in me.polygons:
        for j,li in enumerate(p.loop_indices):a=math.tau*j/len(p.loop_indices);uv.data[li].uv=(.85+.025*math.cos(a),.65+.025*math.sin(a))
    ob=bpy.data.objects.new(zh+'_主体',me);c.objects.link(ob);ob.parent=e;ob['package_id']=slug
    ob.shape_key_add(name='Basis');key=ob.shape_key_add(name='书报边角轻掀')
    for v in key.data:v.co.z+=.025*(v.co.x/size[0]+.5)**3
    for f in [1,61,121,181,241]:key.value=.5+.5*math.sin((f-1)*math.tau/240);key.keyframe_insert(data_path='value',frame=f)
    m['packages'].append({'package_id':slug,'name_zh':zh,'collection':c.name,'root_object':e.name,'objects':[ob.name],'origin_blender':list(pos),'kind':'fixed_display_attachment','fixed_display_attachment':True,'animations':[{'type':'paper_shape','max_displacement_m':.025}],'expected_glb':str(B/'components'/slug/('prp_'+slug+'_visual_top3d.glb')),'exported':False})
# Shape corner on posters rather than swinging rigid wall-mounted whole poster.
for p in m['packages']:
    if p['package_id'].startswith('cinema_poster_'):
        ob=bpy.data.objects[p['objects'][0]];ob.shape_key_add(name='Basis');k=ob.shape_key_add(name='海报边角轻掀')
        pts=[v.co for v in ob.data.vertices];ym=max(v.y for v in pts);zm=max(v.z for v in pts)
        for v in k.data:
            if v.co.y>ym-.08 and v.co.z>zm-.1:v.co.x+=.025
        for f in [1,61,121,181,241]:k.value=.5+.5*math.sin((f-1)*math.tau/240);k.keyframe_insert(data_path='value',frame=f)
        p['animations'].append({'type':'poster_corner_shape','max_displacement_m':.025})
# Exclude empty initial scene. One asset scene, four exact roles.
for sc in list(bpy.data.scenes):
    if sc!=s:bpy.data.scenes.remove(sc)
scene_src=next(c for c in bpy.data.collections if c.name.startswith('01_制作组件'));scene_src.hide_render=True;scene_src.hide_viewport=True
s.camera=bpy.data.objects['全景第三视角'];s.frame_set(1);bpy.context.view_layer.update()
tri=0
for p in m['packages']:
    p['version']='v002';p['source_blend']=str(DEST);obs=[bpy.data.objects[n] for n in p['objects']];pts=[ob.matrix_world@Vector(v) for ob in obs for v in ob.bound_box]
    p['bbox_world']=[[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]];p['dimensions']=[p['bbox_world'][1][i]-p['bbox_world'][0][i] for i in range(3)]
    p['triangles']=0
    for ob in obs:ob.data.calc_loop_triangles();p['triangles']+=len(ob.data.loop_triangles)
    tri+=p['triangles']
    folder=source_path(B/'source/prp_rooftop_courtyard/component_packages_v002'/p['package_id']);folder.mkdir(parents=True,exist_ok=True);(folder/'asset_manifest.json').write_text(json.dumps(p,ensure_ascii=False,indent=2),encoding='utf-8')
m['version']='v002';m['source_blend']=str(DEST);m['triangles_source']=tri;m['motion_features']=['radio_breathing','desk_fan','canvas_breeze','bulb_sway_flicker','tv_static','thermos_steam','foliage_breeze','wire_clothesline','ac_fan','poster_corner','tuning_pointer','puddle_ripple','rope_net','paper_corner'];m['runtime_integrated']=False
assert tri<200000
(O/'asset_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8');(source_path(B/'source/prp_rooftop_courtyard/asset_manifest.json')).write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(DEST));print('REFINEMENT_OK',tri,len(m['packages']))
