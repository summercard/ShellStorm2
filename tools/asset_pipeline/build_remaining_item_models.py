"""Author full-bodied item silhouettes and derive budgeted ground meshes from source parts."""
import bpy, bmesh, json, math, os, sys, hashlib, shutil
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'scripts'),str(ROOT/'tools/asset_pipeline')]
from workspace_paths import work_path
from remaining_item_specs import SPECS, BLUEPRINT_IDS
import build_reference_items_20261014 as art
OUT=work_path('sessions/2026-10-14_remaining_items/build_report.json').parent
MEASURE=json.loads((OUT/'runtime_dimensions.json').read_text('utf8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf8')

def box(name,pos,size,color='blue',role=1,angle=0):
    o=art.box(name,pos,size,role,color,min(size)*.16);o.rotation_euler.z=angle;return o
def lathe(name,profile,pos=(0,0,0),color='blue',role=1,n=6,axis='z'):
    o=art.lathe(name,profile,role,color,axis,pos,n=48)
    o['ring_count']=len(profile);o['low_n']=n
    return o
def cyl(name,pos,r,h,color='silver',role=0,n=6,axis='z'):
    return lathe(name,[(-h/2,r),(h/2,r)],pos,color,role,n,axis)
def egg(name,pos,r,h,color='pink',role=2,n=6):
    return lathe(name,[(-h/2,r*.25),(-h*.24,r*.88),(h*.12,r),(h*.39,r*.65),(h/2,r*.05)],pos,color,role,n)
def ring(name,pos,r,t,color='gold',axis='z',n=8):
    o=art.lathe(name,[(-t/2,r-t),(-t/2,r),(t/2,r),(t/2,r-t),(-t/2,r-t)],0,color,axis,pos,n=48,caps=False)
    o['ring_count']=5;o['low_n']=n;o['open_profile']=True;return o
def plate(name,points,thick,color='blue',role=1):return art.plate(name,points,thick,role,color,axis='y')
def mark(name,pos,size,color='gold'):
    return box(name,pos,size,color,2)

def build_shape(kind):
    if kind=='beacon':
        lathe('厚实信标底座',[(0,.32),(.07,.4),(.18,.36)],color='blue',n=8)
        cyl('立柱',(0,0,.39),.13,.44,'silver')
        egg('发射圆顶',(0,0,.72),.28,.4,'pink')
        ring('金色信号环',(0,0,.70),.42,.065,n=8)
        box('开关面',(0,-.33,.13),(.16,.04,.09),'gold')
    elif kind=='key':
        ring('大型钥匙环',(0,0,.77),.32,.13,axis='y',n=8)
        box('钥匙柄',(0,0,.35),(.19,.17,.62),'gold',0)
        box('钥匙齿一',(.16,0,.10),(.38,.18,.14),'gold',0)
        box('钥匙齿二',(.12,0,.30),(.3,.18,.13),'gold',0)
        cyl('环上锁芯',(0,-.035,.77),.11,.16,'blue',1,6,'y')
    elif kind=='cells':
        for i in [-1,0,1]:
            cyl('饱满电芯',(i*.24,0,.4),.145,.65,'cyan' if i==0 else 'blue',1)
            cyl('金色触点',(i*.24,0,.77),.072,.11,'gold')
        box('下固定框',(0,0,.10),(.82,.34,.14),'dark')
        box('粉色束带',(0,-.17,.43),(.82,.07,.19),'pink')
        box('提手',(0,0,.9),(.46,.13,.10),'silver',0)
    elif kind.startswith('module_'):
        color={'module_basic':'blue','module_advanced':'pink','module_efficient':'cyan'}[kind]
        box('圆角模块壳',(0,0,.44),(.62,.34,.72),color)
        box('底部接口',(0,0,.065),(.44,.30,.13),'dark')
        for x in [-.13,.13]:box('金色接点',(x,-.17,.075),(.07,.05,.14),'gold',0)
        cyl('银色镜圈',(0,-.20,.51),.25,.12,'silver',0,8,'y')
        cyl('凸镜面',(0,-.28,.51),.19,.065,'cyan',2,8,'y')
        if kind=='module_basic':box('单条标识',(0,-.19,.16),(.25,.05,.075),'white')
        elif kind=='module_advanced':
            for x in [-.14,.14]:box('双灯标识',(x,-.19,.16),(.1,.05,.1),'gold')
        else:
            o=plate('节能叶片',[(-.13,.08),(.10,.13),(.13,.27),(-.08,.23)],.055,'gold');o.location.y=-.19
    elif kind=='scroll':
        box('厚蓝图纸页',(0,0,.47),(.72,.12,.80),'blue')
        for z in [.08,.87]:cyl('卷轴纸卷',(0,0,z),.13,.89,'cyan',1,8,'x')
        box('中部扣带',(.24,-.08,.48),(.12,.045,.76),'gold',0)
        for pos,size in [((-.13,-.085,.64),(.25,.04,.09)),((-.21,-.085,.46),(.09,.04,.3)),((-.10,-.085,.32),(.30,.04,.07))]:box('白色图纸线',pos,size,'white')
    elif kind in ['standard','sticky','piercing','explosive','homing','blackhole','balloon','bounce']:
        cyl('模块底座',(0,0,.08),.25,.16,'silver',0,8)
        cyl('接口短节',(0,0,.2),.19,.14,'dark',1)
        if kind=='standard':
            lathe('蓝色标准弹芯',[(.23,.23),(.63,.23),(.83,.12),(.88,.02)],color='blue',n=8)
            cyl('金色环',(0,0,.39),.255,.09,'gold')
            box('白条标识',(0,-.24,.58),(.10,.04,.22),'white')
        elif kind=='sticky':
            egg('黏液主团',(0,0,.61),.35,.63,'cyan',n=8)
            for x,z in [(-.25,.34),(.24,.40),(0,.29)]:egg('垂落胶滴',(x,-.13,z),.10,.28,'cyan',n=4)
        elif kind=='bounce':
            o=plate('厚回旋镖',[(-.43,.77),(-.30,.90),(0,.61),(.30,.90),(.43,.77),(.10,.30),(-.10,.30)],.20,'pink')
            cyl('中央回旋芯',(0,-.13,.5),.14,.075,'gold',0,8,'y')
            for x in [-.29,.29]:box('白色端翼',(x,-.115,.76),(.14,.035,.10),'white',angle=x)
        elif kind=='piercing':
            cyl('蓝色驱动套',(0,0,.38),.23,.30,'blue',1,8)
            lathe('穿甲尖锥',[(.51,.25),(.70,.20),(1.03,.008)],color='silver',role=0,n=8)
            for x in [-1,1]:box('金色稳定翼',(x*.22,0,.31),(.14,.18,.27),'gold',0)
        elif kind=='explosive':
            egg('圆胖爆弹',(0,0,.57),.34,.64,'pink',n=8)
            cyl('引信盖',(0,0,.91),.15,.10,'silver')
            box('引信拉杆',(.12,0,1.0),(.34,.14,.10),'gold',0)
            box('警示竖条',(0,-.335,.61),(.1,.04,.20),'white')
            box('警示点',(0,-.31,.42),(.1,.04,.08),'white')
        elif kind=='homing':
            egg('金色蜂卵',(0,0,.61),.30,.72,'gold',2,n=8)
            cyl('黑色蜂腰',(0,0,.55),.306,.13,'dark',1,8)
            for x in [-1,1]:egg('短小蜂翼',(x*.29,0,.63),.12,.34,'cyan',n=4)
        elif kind=='blackhole':
            egg('黑洞球核',(0,0,.61),.29,.54,'dark',n=8)
            ring('紫粉吸积环',(0,0,.61),.43,.09,'pink',axis='y',n=8)
            box('金色环扣',(0,-.06,.19),(.20,.15,.16),'gold',0)
        else:
            egg('饱满气球',(0,0,.72),.35,.68,'pink',n=8)
            lathe('气球结',[(.3,.13),(.39,.04),(.44,.11)],color='pink',n=6)
            box('高光标记',(-.13,-.30,.85),(.10,.045,.17),'white')
    elif kind=='fan':
        box('安装脚',(0,0,.09),(.38,.33,.18),'dark')
        box('短支架',(0,0,.3),(.16,.18,.4),'blue')
        ring('圆形厚风罩',(0,0,.66),.38,.10,'blue','y',8)
        for angle in [0,2.0944,4.1888]:
            o=plate('三叶扇叶',[(-.05,.0),(.19,.09),(.22,.26),(.05,.26)],.08,'pink');
            o.location.z=.66;o.rotation_euler.y=angle
        cyl('金色轮毂',(0,-.09,.66),.11,.16,'gold',0,6,'y')
    elif kind=='sticker':
        box('下层厚贴纸',(-.09,.02,.43),(.63,.12,.70),'blue',angle=-.12)
        box('上层粉贴纸',(.07,-.07,.51),(.63,.13,.70),'pink',angle=.08)
        # raised pair of overlapping rounded rectangles is legible from overhead.
        for x,z in [(-.045,.48),(.10,.61)]:
            box('复制图标',(x,-.15,z),(.30,.05,.29),'white')
            box('图标内窗',(x,-.18,z),(.19,.025,.18),'cyan')
        cyl('金色贴纸卷边',(.37,-.01,.5),.075,.63,'gold',0,6)
    elif kind=='bat':
        lathe('饱满球棒',[(0,.12),(.15,.23),(.85,.24),(1.12,.13),(1.40,.08)],color='blue',n=8)
        cyl('握柄胶套',(0,0,1.53),.09,.44,'pink',1,8)
        cyl('棒尾球钮',(0,0,1.79),.14,.10,'gold',0,8)
        cyl('金属箍',(0,0,.21),.247,.12,'silver',0,8)
        for z in [1.42,1.56,1.7]:cyl('握柄防滑圈',(0,0,z),.098,.035,'dark',1,6)
    elif kind=='blade':
        plate('宽厚断刃',[(-.34,0),(.13,.08),(.34,.21),(.30,1.50),(-.30,1.50)],.17,'blue')
        plate('银色刃口',[(-.34,0),(-.25,.10),(-.22,1.48),(-.30,1.50)],.19,'silver',0)
        box('金属护手',(0,0,1.58),(.9,.25,.18),'gold',0)
        cyl('饱满握柄',(0,0,1.9),.10,.52,'pink',1,8)
        cyl('配重尾端',(0,0,2.22),.16,.14,'silver',0,8)
        box('刀身嵌条',(.09,-.105,.84),(.12,.05,1.04),'cyan',2)
        for z in [1.78,1.94,2.1]:cyl('防滑箍',(0,0,z),.108,.04,'dark',1)
    elif kind=='axe':
        cyl('粗壮斧柄',(0,0,1.32),.085,2.1,'blue',1,8)
        plate('宽大斧头',[(-.76,.02),(-.8,.77),(-.28,.65),(.20,.55),(.24,.20),(-.25,.17)],.24,'blue')
        plate('宽银刃',[(-.76,.02),(-.8,.77),(-.65,.74),(-.61,.06)],.27,'silver',0)
        plate('后侧尖锤',[(.16,.19),(.57,.34),(.16,.55)],.23,'gold',0)
        cyl('粉色握套',(0,0,1.94),.12,.57,'pink',1,8)
        cyl('尾部配重',(0,0,2.30),.16,.13,'silver',0,8)
        cyl('斧头轴钉',(0,-.15,.38),.13,.12,'gold',0,8,'y')

def sampled_mesh(src):
    n=int(src['low_n']);rings=int(src['ring_count']);old=src.data
    vs=[old.vertices[k*48+int(i*48/n)].co.copy() for k in range(rings) for i in range(n)]
    faces=[(k*n+i,k*n+(i+1)%n,(k+1)*n+(i+1)%n,(k+1)*n+i) for k in range(rings-1) for i in range(n)]
    if not src.get('open_profile'):faces.extend([tuple(reversed(range(n))),tuple(range((rings-1)*n,rings*n))])
    mesh=bpy.data.meshes.new(src.name+'_减面');mesh.from_pydata(vs,[],faces);mesh.update();return mesh
def bounds(objects):
    pts=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
    return Vector([min(v[i] for v in pts) for i in range(3)]),Vector([max(v[i] for v in pts) for i in range(3)])
def uv_repair(obj):
    uv=obj.data.uv_layers.active
    for face in obj.data.polygons:
        coords=[uv.data[i].uv.copy() for i in face.loop_indices]
        center=sum(coords,Vector((0,0)))/len(coords)
        cx=(min(9,max(0,int(center.x*10)))+.5)/10;cy=(min(9,max(0,int(center.y*10)))+.5)/10
        for k,i in enumerate(face.loop_indices):
            a=2*math.pi*k/len(face.loop_indices);uv.data[i].uv=(cx+.022*math.cos(a),cy+.022*math.sin(a))
def join_output(objects,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();obj=bpy.context.object;obj.name=name
    return obj
def tris(obj):obj.data.calc_loop_triangles();return len(obj.data.loop_triangles)
def save_source(path):
    path.parent.mkdir(parents=True,exist_ok=True)
    art_img=bpy.data.images.get('设施低亮多巴胺色盘_10x10_512.png')
    for img in bpy.data.images:
        if img.source=='FILE':img.filepath='//'+os.path.relpath(art.PAL,path.parent).replace('\\','/')
    temp=OUT/path.name;bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(temp),relative_remap=False);shutil.copy2(temp,path)
def emit_runtime(obj,source,folder,stem,role,contract):
    glb=folder/'components'/f'{stem}_{role}_visual_top3d.glb';scene=folder/'runtime'/f'{stem}_{role}_root_top3d.tscn'
    glb.parent.mkdir(parents=True,exist_ok=True);scene.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_image_format='NONE',export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    dims=contract['godot_dimensions_m']
    scene.write_text(f'''[gd_scene load_steps=2 format=3]
[ext_resource type="PackedScene" path="res://{glb.relative_to(ROOT).as_posix()}" id="1"]
[node name="ItemRoot" type="Node3D"]
metadata/asset_id = "{contract['asset_id']}"
metadata/logical_id = "{contract['logical_id']}"
metadata/model_role = "{role}"
metadata/asset_version = "v001"
metadata/triangle_count = {tris(obj)}
metadata/dimensions_m = Vector3({dims[0]}, {dims[1]}, {dims[2]})
metadata/collision_intent = "external_gameplay_owner"
[node name="Visual" parent="." instance=ExtResource("1")]
''',encoding='utf8')
    imp=Path(str(glb)+'.import')
    if not imp.exists():imp.write_text('[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n[params]\nmeshes/generate_lods=false\nanimation/import=false\nimport_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"\ngltf/embedded_image_handling=0\n',encoding='utf8')
    return {'source_blend':source.relative_to(ROOT).as_posix(),'sha256':sha(source),'triangles':tris(obj),'glb':glb.relative_to(ROOT).as_posix(),'prefab':scene.relative_to(ROOT).as_posix(),'glb_sha256':sha(glb),'prefab_sha256':sha(scene)}

def build(spec):
    slug,name,logical,aid,domain,kind=spec;melee=kind in ['bat','blade','axe']
    folder=ROOT/'art_source/items_weapons'/domain/slug;folder.mkdir(parents=True,exist_ok=True)
    stem=('itm_' if domain=='props' else 'wpn_')+slug
    runtime=ROOT/'assets/art/items_weapons'/domain/slug
    bpy.ops.wm.open_mainfile(filepath=str(art.TEMPLATE))
    for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
    for c in list(bpy.data.collections):bpy.data.collections.remove(c)
    root=bpy.data.collections.new(name+'_中文资产管理');bpy.context.scene.collection.children.link(root)
    cols={n:bpy.data.collections.new(n) for n in art.COLS}
    for col in cols.values():root.children.link(col)
    art.NAME=name;art.COMPONENTS=cols[art.COLS[0]];art.setup_materials();build_shape(kind)
    parts=list(art.COMPONENTS.objects)
    bpy.context.view_layer.update();lo,hi=bounds(parts);original_center=(lo+hi)/2
    measurement=MEASURE['bp_'+logical.removeprefix('weapon_')]['native'] if melee else MEASURE[logical]['factory']
    target=max(measurement['xyz_size_m'])
    if kind=='scroll':target=.90 # shared physical blueprint sheet, specified batch design
    factor=target/(hi.z-lo.z)
    shift=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    # Every low part is sampled from these source vertices, not independently rebuilt.
    for part in parts:
        part.data.transform(Matrix.Scale(factor,4)@Matrix.Translation(-shift)@part.matrix_world);part.matrix_world=Matrix.Identity(4)
        for m in part.modifiers:
            if m.type=='BEVEL':m.width*=factor
    if melee:
        # Authoring Z (head to grip) maps to Godot +Z: head forward -Z, existing grip at 0.
        lower=measurement['xyz_min_m'][2]
        transform=Matrix(((1,0,0,0),(0,0,-1,-lower),(0,1,0,0),(0,0,0,1)))
        for part in parts:part.data.transform(transform)
    lo,hi=bounds(parts);size=hi-lo
    dims=[size.x,size.z,size.y]
    contract={'asset_id':aid,'logical_id':logical,'name':name,'slug':slug,'domain':domain,'kind':kind,'content_ids':BLUEPRINT_IDS if kind=='scroll' else [logical],
        'godot_dimensions_m':dims,'measurement':measurement,'principal_length_m':target,'origin':'existing_grip' if melee else 'bottom_center',
        'animation_tier':'tier_0_static','materials':art.ROLES,'budget_triangles':[100,200],'status':'authored',
        'geometry_design':'饱满可辨轮廓；源组件采样减面；无碰撞；公共色盘'}
    write(folder/'asset_contract.json',contract)
    output=cols[art.COLS[1]];highparts=[];dg=bpy.context.evaluated_depsgraph_get()
    for part in parts:
        mesh=bpy.data.meshes.new_from_object(part.evaluated_get(dg),depsgraph=dg)
        ob=bpy.data.objects.new(part.name+'_高精度',mesh);output.objects.link(ob)
        mat=part.data.materials[0];u=part.data.uv_layers.active.data[0].uv
        cell=(int(u.x*10),9-int(u.y*10));color=next(k for k,v in art.C.items() if v==cell)
        art.uv_assign(ob,art.ROLES.index(mat.name),color);highparts.append(ob)
    high=join_output(highparts,stem+'_整合输出')
    art.COMPONENTS.hide_viewport=True;art.COMPONENTS.hide_render=True
    anchor=bpy.data.objects.new('GripSocket' if melee else 'ItemRoot',None);cols[art.COLS[3]].objects.link(anchor)
    anchor['asset_id']=aid
    if melee:
        for label,pos in [('MeleeHitBase',(0,0,0)),('MeleeHitTip',(0,-measurement['xyz_min_m'][2],0))]:
            o=bpy.data.objects.new(label,None);o.location=pos;cols[art.COLS[3]].objects.link(o)
    highlo,highhi=bounds([high]);center=(highlo+highhi)/2;extent=max(highhi-highlo)
    cam,aim=art.camera_light(cols[art.COLS[4]],center,extent)
    cam.location=center+Vector((1.4,-2.6,1.6))*extent;aim(cam,center)
    scene=bpy.context.scene;scene.cycles.samples=20;scene.render.resolution_x=480;scene.render.resolution_y=480
    scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
    highpath=folder/'source'/f'{stem}_source_v001.blend';save_source(highpath)
    preview=emit_runtime(high,highpath,runtime,stem,'preview',contract)
    for image in bpy.data.images:
        if image.source=='FILE':image.filepath=str(art.PAL)
    scene.render.filepath=str(OUT/(slug+'_preview.png'));bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(high,do_unlink=True)
    lowparts=[]
    for part in parts:
        mesh=sampled_mesh(part) if 'ring_count' in part else part.data.copy()
        ob=bpy.data.objects.new(part.name+'_地面派生',mesh);output.objects.link(ob)
        # Keep source per-part palette color, then join, triangulate and repair islands.
        mat=part.data.materials[0];u=part.data.uv_layers.active.data[0].uv
        cell=(int(u.x*10),9-int(u.y*10));color=next(k for k,v in art.C.items() if v==cell)
        art.uv_assign(ob,art.ROLES.index(mat.name),color);lowparts.append(ob)
    low=join_output(lowparts,stem+'_地面整合输出')
    bpy.context.view_layer.objects.active=low
    if tris(low)>198:
        dec=low.modifiers.new('轮廓保留减面','DECIMATE');dec.ratio=194/tris(low);dec.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=dec.name)
    bm=bmesh.new();bm.from_mesh(low.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(low.data);bm.free()
    if tris(low)<100:
        bm=bmesh.new();bm.from_mesh(low.data);bmesh.ops.subdivide_edges(bm,edges=list(bm.edges),cuts=1,use_grid_fill=True);bm.to_mesh(low.data);bm.free()
        dec=low.modifiers.new('预算重整','DECIMATE');dec.ratio=150/tris(low);dec.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=dec.name)
    uv_repair(low)
    # Preserve the high output envelope after reductions, per-axis in authored coordinates.
    ll,lh=bounds([low])
    for v in low.data.vertices:
        for i in range(3):v.co[i]=highlo[i]+(v.co[i]-ll[i])*(highhi[i]-highlo[i])/max(1e-8,lh[i]-ll[i])
    assert 100<=tris(low)<=200,(slug,tris(low))
    lowpath=folder/'source'/f'{stem}_ground_source_v001.blend';save_source(lowpath)
    ground=emit_runtime(low,lowpath,runtime,stem,'ground',contract)
    for image in bpy.data.images:
        if image.source=='FILE':image.filepath=str(art.PAL)
    scene.render.filepath=str(OUT/(slug+'_ground.png'));bpy.ops.render.render(write_still=True)
    contract['model_variants']={'preview':preview,'ground':ground};contract['status']='exported_pending_godot_validation'
    write(folder/'asset_contract.json',contract);write(folder/'source_manifest.json',contract);write(runtime/'asset_manifest.json',contract)
    print('REMAINING_ITEM_DONE',slug,ground['triangles'],flush=True)
    return contract

if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    report=[]
    for spec in SPECS:
        if args and spec[0] not in args:continue
        value=build(spec);report.append(value);write(OUT/(spec[0]+'_report.json'),value)
    write(OUT/'build_report.json',report)
