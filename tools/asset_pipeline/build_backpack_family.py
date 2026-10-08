"""在独立后台Blender中按冻结契约构建三款背包，不读取或修改交互会话。"""
import bpy, math, json, hashlib, shutil, struct
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'assets/art/items_weapons'
OUT = ROOT / 'outputs/backpacks_20261008'
PALETTE = ROOT / 'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
ROLES = ['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
COLS = ['01_制作组件_已统一材质','02_游戏输出_整合模型','10_骨骼与动画','80_挂点_交互接口','90_展示环境_灯光相机']

def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def rel(p): return p.relative_to(ROOT).as_posix()
def save_json(p, data): p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def mesh_obj(name, verts, faces, role, cell, collection):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces); mesh.update()
    obj = bpy.data.objects.new(name,mesh); collection.objects.link(obj)
    mesh.materials.append(bpy.data.materials[ROLES[role]])
    uv = mesh.uv_layers.new(name='PaletteUV'); uv.active_render = True
    cx, cy = (cell[0]+.5)/10, 1-(cell[1]+.5)/10
    for poly in mesh.polygons:
        for i, li in enumerate(poly.loop_indices):
            a = 2*math.pi*i/len(poly.loop_indices)
            uv.data[li].uv = (cx+.023*math.cos(a),cy+.023*math.sin(a))
        poly.use_smooth = True
    return obj

def rounded_outline(w,h,r,n=2):
    points=[]
    for cx,cz,start in [(w/2-r,h/2-r,0),(-w/2+r,h/2-r,90),(-w/2+r,-h/2+r,180),(w/2-r,-h/2+r,270)]:
        for i in range(n+1):
            a=math.radians(start+90*i/n)
            points.append((cx+r*math.cos(a),cz+r*math.sin(a)))
    return points

def loft(name,w,h,depth,center,cell,col,r=.08,n=1,rings=3):
    outline=rounded_outline(w,h,min(r,w*.45,h*.45),n)
    verts=[]; faces=[]; count=len(outline)
    levels=[(depth/2,.90),(0,1),(-depth/2,.90)] if rings==3 else [(depth/2,1),(-depth/2,1)]
    for y,scale in levels:
        verts.extend((x*scale+center[0],y+center[1],z*scale+center[2]) for x,z in outline)
    for k in range(len(levels)-1):
        for i in range(count):
            j=(i+1)%count
            faces.append((k*count+i,k*count+j,(k+1)*count+j,(k+1)*count+i))
    faces += [tuple(reversed(range(count))),tuple(range((len(levels)-1)*count,len(levels)*count))]
    return mesh_obj(name,verts,faces,1,cell,col)

def ribbon(name,points,width,cell,col,axis='x',role=1):
    verts=[]
    for p in points:
        d=Vector((width/2,0,0)) if axis=='x' else Vector((0,0,width/2))
        verts.extend([tuple(Vector(p)-d),tuple(Vector(p)+d)])
    faces=[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(points)-1)]
    return mesh_obj(name,verts,faces,role,cell,col)

def buckle(name,x,y,z,w,h,cell,col):
    verts=[]
    for scale in [1,.56]:
        verts.extend([(x-w*.5*scale,y,z-h*.5*scale),(x+w*.5*scale,y,z-h*.5*scale),(x+w*.5*scale,y,z+h*.5*scale),(x-w*.5*scale,y,z+h*.5*scale)])
    return mesh_obj(name,verts,[(i,(i+1)%4,(i+1)%4+4,i+4) for i in range(4)],2,cell,col)

def handle(name,z,cell,col,seg=6):
    verts=[]; faces=[]
    for i in range(seg+1):
        a=math.pi*i/seg
        for radius,y in [(.094,.018),(.064,.018),(.064,-.018),(.094,-.018)]:
            verts.append((radius*math.cos(a),y,z+radius*math.sin(a)))
    for i in range(seg):
        for j in range(4): faces.append((i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j))
    faces.extend([(3,2,1,0),tuple(range(seg*4,seg*4+4))])
    return mesh_obj(name,verts,faces,1,cell,col)

def bedroll(col):
    verts=[]; faces=[]; n=10
    for x,r in [(-.355,.090),(-.32,.107),(.32,.107),(.355,.090)]:
        for i in range(n):
            a=2*math.pi*i/n
            verts.append((x,-.003+math.cos(a)*r,.305+math.sin(a)*r))
    for k in range(3):
        for i in range(n): faces.append((k*n+i,k*n+(i+1)%n,(k+1)*n+(i+1)%n,(k+1)*n+i))
    faces.extend([tuple(reversed(range(n))),tuple(range(3*n,4*n))])
    mesh_obj('顶部卷铺盖',verts,faces,1,(8,5),col)
    for s in [-1,1]:
        points=[]
        for i in range(7):
            a=math.pi*.12+math.pi*1.7*i/6
            points.append((s*.18,-.003+.110*math.cos(a),.305+.110*math.sin(a)))
        ribbon('卷铺盖固定带'+str(s),points,.049,(9,2),col)
        buckle('卷铺盖扣'+str(s),s*.18,-.116,.299,.065,.05,(9,3),col)
        # 端面压印卷纹：独立窄带，不增加贴图或材质。
        points=[]
        for i in range(7):
            a=i*math.pi*1.5/6; r=.064*(1-i/9)
            points.append((s*.357,-.003+math.cos(a)*r,.305+math.sin(a)*r))
        verts=[]
        for x,y,z in points: verts.extend([(x,y-.004,z),(x,y+.004,z)])
        mesh_obj('卷铺盖端面卷纹'+str(s),verts,[(2*i,2*i+1,2*i+3,2*i+2) for i in range(6)],1,(7,5),col)

def make_template():
    path=BASE/'_templates/prp/prp_template_source_v001.blend'
    if path.exists():
        return path
    path.parent.mkdir(parents=True,exist_ok=True)
    (path.parent/'.gdignore').write_text('',encoding='utf-8')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root=bpy.data.collections.new('PRP_静态道具模板_中文资产管理'); bpy.context.scene.collection.children.link(root)
    for name in COLS: root.children.link(bpy.data.collections.new(name))
    image=bpy.data.images.load(str(PALETTE)); image.filepath=str(PALETTE)
    for i,name in enumerate(ROLES):
        m=bpy.data.materials.new(name); m.use_nodes=True; m.use_fake_user=True
        nt=m.node_tree; p=nt.nodes.get('Principled BSDF')
        p.inputs['Metallic'].default_value=[.86,.02,.18,0][i]
        p.inputs['Roughness'].default_value=[.28,.72,.16,.4][i]
        p.inputs['Coat Weight'].default_value=[.15,0,.65,0][i]
        texture=nt.nodes.new('ShaderNodeTexImage'); texture.image=image; texture.interpolation='Closest'
        uv=nt.nodes.new('ShaderNodeUVMap'); uv.uv_map='PaletteUV'; nt.links.new(uv.outputs['UV'],texture.inputs['Vector']); nt.links.new(texture.outputs['Color'],p.inputs['Base Color'])
        if i==3:
            nt.links.new(texture.outputs['Color'],p.inputs['Emission Color']); p.inputs['Emission Strength'].default_value=1.3
    anchor=bpy.data.objects.new('ItemRoot',None); root.children[COLS[3]].objects.link(anchor)
    sample=loft('模板示例件',.2,.2,.1,(0,0,0),(7,5),root.children[COLS[1]])
    sample.parent=anchor
    scene=bpy.context.scene; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
    scene['template_provenance']='06指定模板缺失；按用户批准的场景四材质覆盖及静态分支完整补建；无骨架'
    bpy.ops.wm.save_as_mainfile(filepath=str(path))
    return path

def audit(collection,contract):
    triangles=0; bounds=[]; faces=0
    for obj in collection.objects:
        if obj.type!='MESH': continue
        mesh=obj.data; mesh.calc_loop_triangles(); triangles+=len(mesh.loop_triangles)
        assert len(mesh.uv_layers)==1 and mesh.uv_layers.active.name=='PaletteUV' and mesh.uv_layers.active.active_render
        assert tuple(obj.scale)==(1,1,1)
        for mat in mesh.materials:
            assert mat.name in ROLES
            tex=next(n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE')
            assert tex.interpolation=='Closest' and not tex.image.packed_file
            assert Path(bpy.path.abspath(tex.image.filepath)).resolve()==PALETTE.resolve()
        for p in mesh.polygons:
            uv=[mesh.uv_layers.active.data[i].uv[:] for i in p.loop_indices]
            cells={(int(u*10),int(v*10)) for u,v in uv}; assert len(cells)==1
            cx,cy=next(iter(cells))
            assert all(.015 < u-cx/10 < .085 and .015 < v-cy/10 < .085 for u,v in uv)
            area=abs(sum(uv[i][0]*uv[(i+1)%len(uv)][1]-uv[(i+1)%len(uv)][0]*uv[i][1] for i in range(len(uv))))/2
            assert area>1e-7
            assert p.area>1e-9
            faces+=1
        bounds.extend(obj.matrix_world@v.co for v in mesh.vertices)
    minimum=Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
    maximum=Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
    expected=Vector(tuple(contract['dimensions_m'][k] for k in ['width','depth','height']))
    assert (maximum-minimum-expected).length<1e-5
    assert (maximum+minimum).length<1e-5
    assert triangles<=500,(contract['asset_id'],triangles)
    assert not any(o.type in ['ARMATURE','LIGHT','CAMERA'] for o in collection.objects)
    return {'triangles':triangles,'polygon_count':faces,'bbox_blender_min':list(minimum),'bbox_blender_max':list(maximum),'uv_faces_checked':faces,'uv_nonzero_area':True,'uv_single_cell_safe':True,'shared_palette_external_closest':True,'shoulder_straps':False}

def build(size,template):
    folder=BASE/'props'/('backpack_'+size)
    c=json.loads((folder/'asset_contract.json').read_text('utf-8'))
    source=ROOT/c['source_blend']; optimized=ROOT/c['optimized_blend']; glb=ROOT/c['stable_glb']
    if (folder/'source_manifest.json').exists():
        return
    if source.exists():
        backup=OUT/(source.stem+'_interrupted.blend')
        if not backup.exists(): shutil.copy2(source,backup)
    shutil.copy2(template,source)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    for image in bpy.data.images:
        if image.source == 'FILE': image.filepath=str(PALETTE)
    root=next(iter(bpy.context.scene.collection.children)); root.name=c['source_collection']
    output=root.children[COLS[1]]; editable=root.children[COLS[0]]
    for obj in list(output.objects): bpy.data.objects.remove(obj,do_unlink=True)
    anchor=bpy.data.objects['ItemRoot']
    main={'small':(7,1),'medium':(7,3),'large':(7,5)}[size]
    pale=(8,9); dark=(9,2) if size=='large' else (7,2) if size=='medium' else (6,1)
    if size=='small':
        loft('圆顶包体',.43,.46,.19,(0,.025,-.018),main,output,r=.19,n=2)
        loft('浅粉前袋',.31,.19,.072,(0,-.095,-.13),(8,1),output,r=.06,n=2)
        ribbon('前袋拉链', [(-.12,-.133,-.09),(.12,-.133,-.09)],.009,pale,output,axis='z')
        loft('拉链拉片',.022,.055,.011,(-.112,-.14,-.117),pale,output,r=.008)
        for s in [-1,1]:
            loft('侧袋'+str(s),.08,.17,.145,(s*.228,.012,-.13),main,output,r=.03)
        handle('顶部提手',.208,main,output)
    else:
        large=size=='large'
        loft('包体',.55 if large else .46,.63 if large else .57,.235,(0,.025,-.07 if large else -.02),main,output,r=.13,n=1 if large else 2)
        loft('浅色前袋',.45 if large else .35,.215,.065,(0,-.109,-.235 if large else -.16),pale,output,r=.07,n=1)
        loft('圆角翻盖',.48 if large else .41,.265,.045,(0,-.107,.11 if large else .135),(8,5) if large else (8,3),output,r=.085,n=1 if large else 2)
        for s in [-1,1]:
            loft('侧袋'+str(s),.11,.255,.17,(s*(.30 if large else .255),.01,-.185 if large else -.135),pale if large else main,output,r=.038)
        for x in ([-.16,.16] if large else [0]):
            ribbon('前盖扣带'+str(x),[(x,-.089,.255 if large else .30),(x,-.135,.205),(x,-.144,-.015),(x,-.147,-.205 if large else -.18)],.046 if large else .05,dark,output)
            buckle('前盖扣'+str(x),x,-.153,-.024,.073,.075,pale,output)
        handle('顶部提手',.348 if large else .271,dark,output,seg=4 if large else 6)
        if large: bedroll(output)
    bpy.context.view_layer.update()
    objects=list(output.objects)
    # 将所有附件包络直接写回顶点坐标，冻结整包尺寸；对象与根缩放均保持1。
    vertices=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
    low=Vector(tuple(min(v[i] for v in vertices) for i in range(3))); high=Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
    center=(low+high)/2; span=high-low
    dims=c['dimensions_m']; target=Vector((dims['width'],dims['depth'],dims['height']))
    for obj in objects:
        for v in obj.data.vertices:
            v.co=Vector(tuple((v.co[i]-center[i])*target[i]/span[i] for i in range(3)))
        obj.parent=anchor
        obj.name='prp_backpack_'+size+'_'+obj.name
        clone=obj.copy(); clone.data=obj.data.copy(); clone.name=c['display_name_zh']+'_制作组件_'+obj.name.split('_')[-1]; editable.objects.link(clone)
        clone.parent=None
    editable.hide_render=True; editable.hide_viewport=True
    root.children[COLS[4]].hide_render=True
    report=audit(output,c)
    bpy.context.scene['asset_contract']=json.dumps(c,ensure_ascii=False)
    bpy.context.scene['source_version']='v001'
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    source_sha=digest(source)
    # 导出副本：只保留输出；执行退化面/重复点检查，不破坏有面积的逐面UV。
    optimized.parent.mkdir(parents=True,exist_ok=True)
    for o in list(editable.objects): bpy.data.objects.remove(o,do_unlink=True)
    import bmesh
    removed=0
    for obj in output.objects:
        bm=bmesh.new(); bm.from_mesh(obj.data)
        dead=[f for f in bm.faces if f.calc_area()<1e-10]
        removed+=len(dead)
        if dead: bmesh.ops.delete(bm,geom=dead,context='FACES')
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(obj.data); bm.free()
    bpy.ops.wm.save_as_mainfile(filepath=str(optimized))
    bpy.ops.wm.open_mainfile(filepath=str(optimized))
    output=bpy.data.collections[COLS[1]]
    after=audit(output,c)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in output.objects: obj.select_set(True)
    bpy.data.objects['ItemRoot'].select_set(True)
    glb.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_image_format='NONE',export_materials='EXPORT',export_animations=False,export_cameras=False,export_lights=False,export_extras=True)
    data=glb.read_bytes(); length,kind=struct.unpack_from('<II',data,12); doc=json.loads(data[20:20+length])
    assert not doc.get('images') and not doc.get('textures')
    triangles=sum(doc['accessors'][p['indices']]['count']//3 for m in doc['meshes'] for p in m['primitives'])
    assert triangles==report['triangles'] and triangles<=500
    assert digest(source)==source_sha
    manifest={**report,'asset_id':c['asset_id'],'logical_id':c['logical_id'],'source_version':'v001','source_blend':rel(source),'source_sha256_before':source_sha,'source_sha256_after':digest(source),'optimized_blend':rel(optimized),'optimized_sha256':digest(optimized),'stable_glb':rel(glb),'glb_sha256':digest(glb),'glb_triangles':triangles,'glb_embedded_images':False,'optimization':{'degenerate_faces_removed':removed,'triangles_before':report['triangles'],'triangles_after':after['triangles'],'reduction_ratio':0,'note':'按最终预算直接构建低模；无安全可删的外表面，保留背面、底面及提手；执行退化检查和法线一致化，不虚报三角化为减面'},'template_resolution':c['template_resolution'],'runtime_integrated':False,'visual_acceptance':'pending','material_roles':ROLES,'palette_sha256':digest(PALETTE)}
    save_json(folder/'source_manifest.json',manifest)
    print('BACKPACK_SOURCE_OK',size,triangles)

def skeletons():
    for size in ['small','medium','large']:
        folder=BASE/'props'/('backpack_'+size)
        c=json.loads((folder/'asset_contract.json').read_text('utf-8'))
        p=ROOT/c['stable_prefab']; p.parent.mkdir(parents=True,exist_ok=True)
        if not p.exists():
            p.write_text('[gd_scene format=3]\n\n[node name="ItemRoot" type="Node3D"]\nmetadata/asset_id = "'+c['asset_id']+'"\nmetadata/asset_version = "v001"\nmetadata/production_state = "pending_authoring"\n',encoding='utf-8')

if __name__=='__main__':
    import sys
    if '--skeletons' in sys.argv:
        skeletons()
    else:
        OUT.mkdir(parents=True,exist_ok=True)
        template=make_template()
        for size in ['small','medium','large']: build(size,template)
