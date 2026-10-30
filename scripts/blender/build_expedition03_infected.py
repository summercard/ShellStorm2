"""Author the expedition03 infected T-pose source. Run with Blender 4.5 -b."""
import bpy, bmesh, math, json, sys, hashlib, shutil
from pathlib import Path
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from workspace_paths import work_path
SLUG = 'enm_melee_expedition03_infected01'
ASSET = 'ENM-MELEE-EXPEDITION03-INFECTED01'
SKEL = 'SKEL-INFECTED01-002'
VERSION = 'v002'
ARM_LENGTH_FACTOR = 0.50
SOURCE = ROOT / 'art_source/enemies/enemy_3d' / SLUG / 'source'
PALETTE = ROOT / 'assets/art/shared/palette/npc_palette_10x10_512.png'
WORK = work_path('sessions/2026-10-30_expedition03_infected/v002/run.json').parent
MODEL = SOURCE / (SLUG + '_model_' + VERSION + '.blend')
ANIM = SOURCE / (SLUG + '_animation_' + VERSION + '.blend')
COLORS = {'shirt':(0,0),'shirt_shadow':(0,1),'shirt_deep':(0,2),'skin':(0,3),
          'skin_shadow':(0,4),'pants':(0,5),'pants_light':(0,6),'mouth':(0,7),'tongue':(0,8),
          'ivory':(1,0),'pupil':(1,1),'iris':(1,2),'stain':(1,3),'tongue_shadow':(1,4),
          'belly':(1,5),'khaki':(1,6),'cloth_light':(1,7),'leather':(1,8)}

def make_material(name, metal, rough, coat=0, emission=0):
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nt = mat.node_tree; nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial'); out.location=(500,0)
    bs = nt.nodes.new('ShaderNodeBsdfPrincipled'); bs.location=(200,0)
    bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough
    bs.inputs['Coat Weight'].default_value=coat
    uv = nt.nodes.new('ShaderNodeUVMap'); uv.uv_map='PaletteUV'; uv.location=(-600,0)
    tex = nt.nodes.new('ShaderNodeTexImage'); tex.image=IMAGE; tex.interpolation='Closest'; tex.location=(-350,0)
    nt.links.new(uv.outputs['UV'],tex.inputs['Vector']); nt.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    if emission:
        nt.links.new(tex.outputs['Color'],bs.inputs['Emission Color']); bs.inputs['Emission Strength'].default_value=emission
    nt.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
    mat.diffuse_color=(.6,.55,.45,1)
    return mat

def collection(name,parent):
    c=bpy.data.collections.new(name); parent.children.link(c); return c

class Mesh:
    def __init__(self,name,col,bone): self.name=name; self.col=col; self.bone=bone; self.v=[]; self.f=[]; self.c=[]; self.m=[]
    def vert(self,p): self.v.append(tuple(p)); return len(self.v)-1
    def face(self,ids,color,mat=1):
        ids=list(ids)
        if len(ids)==3: tris=[ids]
        else:
            vec=[Vector(self.v[i]) for i in ids]
            tris=[[ids[p if isinstance(p,int) else min(range(len(vec)),key=lambda k:(vec[k]-p).length_squared)] for p in t] for t in tessellate_polygon([vec])]
        for tri in tris: self.f.append(tri); self.c.append(color); self.m.append(mat)
    def ring(self,points): return [self.vert(p) for p in points]
    def band(self,a,b,color,mat=1,alt=None):
        for i in range(len(a)):
            self.face([a[i],a[(i+1)%len(a)],b[(i+1)%len(a)],b[i]], alt[i] if alt else color,mat)
    def cap(self,a,color,mat=1): self.face(a,color,mat)
    def finish(self):
        me=bpy.data.meshes.new(self.name); me.from_pydata(self.v,[],self.f); me.update()
        ob=bpy.data.objects.new(self.name,me); self.col.objects.link(ob)
        for mat in MATS: me.materials.append(mat)
        uv=me.uv_layers.new(name='PaletteUV'); uv.active_render=True; me.uv_layers.active=uv
        for p,color,mi in zip(me.polygons,self.c,self.m):
            p.material_index=mi
            r,c=COLORS[color]; cx=(c+.5)/10; cy=1-(r+.5)/10
            for k,li in enumerate(p.loop_indices):
                a=math.pi/2+2*math.pi*k/len(p.loop_indices)
                uv.data[li].uv=(cx+.026*math.cos(a),cy+.026*math.sin(a))
        bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(me); bm.free()
        ob['asset_id']=ASSET; ob['part']=self.name; ob['deform_bone']=self.bone
        ob['color_edit']='UV Editing > PaletteUV > select face island > move into NPC palette cell'
        vg=ob.vertex_groups.new(name=self.bone); vg.add(list(range(len(me.vertices))),1,'REPLACE')
        ob.parent=RIG; mod=ob.modifiers.new('Skeleton','ARMATURE'); mod.object=RIG
        OBJECTS.append(ob); return ob

def ellipse(cx,cy,z,rx,ry,n=10):
    return [(cx+rx*math.sin(2*math.pi*i/n),cy-ry*math.cos(2*math.pi*i/n),z) for i in range(n)]

def tube(name,col,bone,levels,color,n=6,mat=1):
    m=Mesh(name,col,bone); rings=[]
    for x,y,z,ry,rz in levels:
        rings.append(m.ring([(x,y+ry*math.cos(2*math.pi*i/n),z+rz*math.sin(2*math.pi*i/n)) for i in range(n)]))
    for a,b in zip(rings,rings[1:]):m.band(a,b,color,mat)
    # Both ends overlap torso/hand geometry; omit invisible interior caps.
    return m.finish()

def patch(name,col,bone,points,color,mat=1):
    m=Mesh(name,col,bone)
    garment=bpy.data.objects.get('破旧衬衫_梨形大轮廓')
    if garment and name.startswith(('旧衣污斑','衬衫破口','衬衫门襟')):
        # Clip the color shape to each host triangle in XZ, then interpolate Y.
        # This preserves the cloth surface through ridges instead of sinking
        # a large flat color polygon beneath a curved low-poly garment.
        cross=lambda a,b:a[0]*b[1]-a[1]*b[0]
        for face in garment.data.polygons:
            if face.normal.y>=-.05:continue
            tri=[garment.data.vertices[i].co for i in face.vertices]
            t=[(v.x,v.z) for v in tri];orient=cross((t[1][0]-t[0][0],t[1][1]-t[0][1]),(t[2][0]-t[0][0],t[2][1]-t[0][1]))
            if abs(orient)<1e-10:continue
            poly=[(p[0],p[2]) for p in points]
            for j in range(3):
                a=t[j];b=t[(j+1)%3];edge=(b[0]-a[0],b[1]-a[1])
                def distance(p):return cross(edge,(p[0]-a[0],p[1]-a[1]))*(1 if orient>0 else -1)
                clipped=[]
                for k,p in enumerate(poly):
                    q=poly[(k+1)%len(poly)];dp=distance(p);dq=distance(q)
                    if dp>=-1e-9:clipped.append(p)
                    if (dp>=0)!=(dq>=0):
                        f=dp/(dp-dq);clipped.append((p[0]+f*(q[0]-p[0]),p[1]+f*(q[1]-p[1])))
                poly=clipped
                if len(poly)<3:break
            if len(poly)<3:continue
            clean=[]
            for p in poly:
                if not clean or math.dist(p,clean[-1])>1e-7:clean.append(p)
            if len(clean)>2 and math.dist(clean[0],clean[-1])<1e-7:clean.pop()
            if len(clean)<3:continue
            n=(tri[1]-tri[0]).cross(tri[2]-tri[0])
            surface=[(x,tri[0].y-(n.x*(x-tri[0].x)+n.z*(z-tri[0].z))/n.y-.0012,z) for x,z in clean]
            m.face(m.ring(surface),color,mat)
    else:m.face(m.ring(points),color,mat)
    return m.finish()

def tetra(name,col,bone,points,color,mat=1):
    m=Mesh(name,col,bone);a=m.ring(points)
    for f in [(0,1,2),(0,3,1),(1,3,2),(2,3,0)]:m.face([a[i] for i in f],color,mat)
    return m.finish()

def add_bone(name,head,tail,parent=None):
    b=RIG.data.edit_bones.new(name);b.head=head;b.tail=tail
    if parent:b.parent=RIG.data.edit_bones[parent]
    return b

def shorten_arms(rig, meshes, edit_meshes=True):
    """Shorten only the arms from the shoulder, retaining all cross sections."""
    def arm_x(x):
        return x if abs(x)<=.18 else math.copysign(.18+(abs(x)-.18)*ARM_LENGTH_FACTOR,x)
    if edit_meshes:
        for ob in meshes:
            if ob.name.startswith(('短袖.','前臂.','简化爪掌.')):
                for vert in ob.data.vertices:vert.co.x=arm_x(vert.co.x)
                ob.data.update()
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    for bone in rig.data.edit_bones:
        if bone.name.startswith(('upper_arm.','forearm.','hand.')):
            bone.head.x=arm_x(bone.head.x);bone.tail.x=arm_x(bone.tail.x)
    bpy.ops.object.mode_set(mode='OBJECT');rig.select_set(False)
    rig['skeleton_id']=SKEL;rig['asset_version']=VERSION;rig['arm_length_factor']=ARM_LENGTH_FACTOR

def author():
    global IMAGE,MATS,RIG,OBJECTS
    assert PALETTE.exists(), str(PALETTE)
    SOURCE.mkdir(parents=True,exist_ok=True)
    # Before iteration, preserve the previous authored files outside the project.
    for p in [MODEL,ANIM]:
        if p.exists():
            bak=WORK/'before_iteration';bak.mkdir(exist_ok=True);shutil.copy2(p,bak/p.name)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
    top=collection('远征03_普通感染者_中文资产管理',bpy.context.scene.collection)
    output=collection('02_游戏输出_TPose',top)
    body=collection('Body_身体与破衬衫',output);head=collection('Head_凸眼大口长舌',output)
    hands=collection('Hands_TPose双臂',output);feet=collection('Feet_短腿与赤足',output)
    skeleton=collection('01_骨架_TPose参考',top)
    IMAGE=bpy.data.images.load(str(PALETTE),check_existing=True);IMAGE.filepath=bpy.path.relpath(str(PALETTE),start=str(SOURCE))
    IMAGE.colorspace_settings.name='sRGB'
    MATS=[make_material('NPC_01_精工金属',.85,.3),make_material('NPC_02_细腻哑光',0,.76),
          make_material('NPC_03_清漆反光',0,.32,.35),make_material('NPC_04_柔和自发光',0,.4,0,.12)]
    arm=bpy.data.armatures.new(SKEL);RIG=bpy.data.objects.new('Armature',arm);skeleton.objects.link(RIG)
    RIG['skeleton_id']=SKEL;RIG['asset_id']=ASSET;RIG['level_id']='expedition_03'
    RIG.show_in_front=True;arm.display_type='STICK';bpy.context.view_layer.objects.active=RIG;RIG.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    add_bone('root',(0,0,0),(0,0,.15));add_bone('pelvis',(0,0,.28),(0,0,.59),'root')
    add_bone('spine',(0,0,.59),(0,0,.95),'pelvis');add_bone('chest',(0,0,.95),(0,0,1.2),'spine')
    add_bone('neck',(0,0,1.2),(.015,0,1.31),'chest');add_bone('head',(.015,0,1.31),(.025,0,1.6),'neck')
    add_bone('jaw',(.02,-.12,1.39),(.02,-.18,1.28),'head');add_bone('tongue',(.02,-.20,1.39),(.01,-.33,1.11),'jaw')
    for side,s in [('L',1),('R',-1)]:
        add_bone('upper_arm.'+side,(s*.17,0,1.16),(s*.50,0,1.16),'chest')
        add_bone('forearm.'+side,(s*.50,0,1.16),(s*.76,0,1.16),'upper_arm.'+side)
        add_bone('hand.'+side,(s*.76,0,1.16),(s*.94,0,1.16),'forearm.'+side)
        add_bone('thigh.'+side,(s*.20,0,.46),(s*.25,0,.23),'pelvis')
        add_bone('shin.'+side,(s*.25,0,.23),(s*.26,0,.07),'thigh.'+side)
        add_bone('foot.'+side,(s*.26,0,.07),(s*.27,-.15,.04),'shin.'+side)
    bpy.ops.object.mode_set(mode='OBJECT');RIG.select_set(False);OBJECTS=[]
    # Ten-sided bell silhouette, deliberately uneven torn hem; no subdivision.
    m=Mesh('破旧衬衫_梨形大轮廓',body,'spine')
    hem=ellipse(0,0,.56,.425,.254)
    for i in range(10):hem[i]=(hem[i][0],hem[i][1],.535+[0,.035,-.035,.005,-.02,.015,.045,-.025,.025,-.02][i])
    rings=[m.ring(hem),m.ring(ellipse(0,0,.83,.355,.235)),m.ring(ellipse(0,.005,1.15,.215,.145)),m.ring(ellipse(.015,0,1.29,.11,.10))]
    for j,(a,b) in enumerate(zip(rings,rings[1:])):
        m.band(a,b,'shirt',alt=['shirt','shirt','shirt_shadow','shirt_shadow','shirt_deep','shirt_shadow','shirt_shadow','shirt','shirt','cloth_light'])
    m.cap(rings[-1],'shirt_shadow');m.cap(rings[0],'shirt_deep');m.finish()
    # Broad low trousers taper to two short exposed ankles.
    m=Mesh('深灰宽裤_低重心',body,'pelvis')
    for side in [-1,1]:
        rr=[m.ring(ellipse(side*.21,.01,.18,.185,.17,6)),m.ring(ellipse(side*.18,.015,.35,.29,.255,6)),m.ring(ellipse(side*.13,.01,.62,.23,.16,6))]
        for a,b in zip(rr,rr[1:]):m.band(a,b,'pants',alt=['pants_light','pants_light','pants','pants','pants','pants'])
        m.cap(rr[0],'pants');m.cap(rr[-1],'pants');
    m.finish()
    # A torn triangular opening reads as exposed belly, with cloth flaps.
    patch('衬衫破口_露腹',body,'spine',[(-.19,-.258,.55),(.13,-.254,.55),(.10,-.244,.72),(-.035,-.250,.78)],'belly')
    patch('衬衫门襟',body,'spine',[(.017,-.242,.76),(.028,-.242,.76),(.036,-.147,1.15),(.026,-.147,1.15)],'shirt_deep')
    patch('左翻领',body,'chest',[(-.117,-.119,1.28),(-.022,-.164,1.20),(-.068,-.191,1.11),(-.166,-.127,1.21)],'cloth_light')
    patch('右翻领',body,'chest',[(.102,-.125,1.285),(.031,-.169,1.205),(.10,-.184,1.135),(.163,-.115,1.22)],'shirt_shadow')
    # Open head: actual recessed mouth surrounded by a skin ring, not a dark sticker.
    m=Mesh('歪头_凹陷大口',head,'head')
    outer=[(-.095,-.133,1.58),(.078,-.115,1.6),(.164,-.135,1.51),(.163,-.142,1.36),(.10,-.118,1.235),(-.05,-.117,1.22),(-.14,-.132,1.30),(-.15,-.133,1.47)]
    inner=[(-.06,-.192,1.485),(.055,-.190,1.50),(.112,-.190,1.442),(.095,-.185,1.33),(.055,-.180,1.278),(-.05,-.180,1.275),(-.105,-.187,1.34),(-.10,-.192,1.43)]
    a=m.ring(outer);b=m.ring(inner);back=m.ring([(x*.9,.09,z) for x,y,z in outer]);deep=m.ring([(x,.005,z) for x,y,z in inner])
    m.band(a,b,'skin');m.band(a,back,'skin_shadow');m.cap(back,'skin_shadow');m.band(b,deep,'mouth');m.cap(deep,'mouth');m.finish()
    for side,s,x,z in [('L',1,.088,1.515),('R',-1,-.035,1.54)]:
        m=Mesh('凸眼眼白.'+side,head,'head')
        ring=m.ring([(x+.051*math.cos(i*math.pi/4),-.194,z+.049*math.sin(i*math.pi/4)) for i in range(8)])
        front=m.vert((x,-.249,z));back=m.vert((x,-.145,z))
        for i in range(8):m.face([ring[i],ring[(i+1)%8],front],'ivory',2);m.face([ring[(i+1)%8],ring[i],back],'ivory',2)
        m.finish()
        patch('红虹膜.'+side,head,'head',[(x+.017*math.cos(i*math.pi/3),-.250,z+.019*math.sin(i*math.pi/3)) for i in range(6)],'iris',2)
        patch('黑瞳.'+side,head,'head',[(x+.007*math.cos(i*math.pi/2),-.251,z+.010*math.sin(i*math.pi/2)) for i in range(4)],'pupil',2)
        patch('眼睛微光.'+side,head,'head',[(x-.004,-.252,z+.007),(x+.001,-.252,z+.007),(x-.003,-.252,z+.013)],'ivory',3)
    m=Mesh('垂落长舌',head,'tongue')
    shape=[(-.018,-.218,1.395),(.065,-.228,1.39),(.082,-.298,1.25),(.061,-.329,1.13),(.013,-.337,1.105),(-.042,-.329,1.13),(-.055,-.302,1.22),(-.035,-.242,1.35)]
    front=m.ring(shape);back=m.ring([(x,y+.026,z) for x,y,z in shape]);m.cap(front,'tongue',2);m.cap(back,'tongue_shadow',2);m.band(front,back,'tongue_shadow',2);m.finish()
    for i,(x,z) in enumerate([(-.066,1.465),(.075,1.462),(.084,1.331)]):
        tipz=z-.065 if i<2 else z+.047
        tetra('参差尖牙_'+str(i+1),head,'head',[(x-.017,-.203,z),(x+.017,-.203,z),(x,-.17,z),(x+.004,-.219,tipz)],'ivory')
    for i,(x,z,dx) in enumerate([(-.065,1.579,-.022),(.025,1.59,.025),(.103,1.57,.040)]):
        patch('稀疏头发_'+str(i),head,'head',[(x-.006,-.02,z-.015),(x+.005,-.02,z-.015),(x+dx,-.021,min(1.6,z+.025))],'pupil')
    for side,s in [('L',1),('R',-1)]:
        tube('短袖.'+side,hands,'upper_arm.'+side,[(s*.18,0,1.16,.133,.132),(s*.49,0,1.16,.099,.10)],'shirt_shadow' if s<0 else 'shirt')
        tube('前臂.'+side,hands,'forearm.'+side,[(s*.46,0,1.16,.067,.066),(s*.77,-.004,1.16,.046,.047)],'skin')
        m=Mesh('简化爪掌.'+side,hands,'hand.'+side)
        outline=[(.75,1.205),(.90,1.195),(.95,1.167),(.935,1.115),(.845,1.107),(.792,1.09)]
        a=m.ring([(s*x,-.051,z) for x,z in outline]);b=m.ring([(s*x,.035,z) for x,z in outline]);m.cap(a,'skin');m.cap(b,'skin_shadow');m.band(a,b,'skin');m.finish()
        m=Mesh('短小脚踝.'+side,feet,'shin.'+side)
        a=m.ring(ellipse(s*.245,.015,.055,.044,.048,4));b=m.ring(ellipse(s*.25,.015,.22,.052,.055,4));m.band(a,b,'skin_shadow');m.cap(a,'skin_shadow');m.cap(b,'skin_shadow');m.finish()
        m=Mesh('宽扁赤足.'+side,feet,'foot.'+side)
        a=m.ring([(s*.19,.055,0),(s*.32,.045,0),(s*.36,-.17,0),(s*.195,-.19,0)])
        b=m.ring([(s*.20,.045,.077),(s*.30,.040,.075),(s*.33,-.15,.035),(s*.20,-.17,.035)])
        m.band(a,b,'skin');m.cap(a,'skin_shadow');m.cap(b,'skin');m.finish()
    # Small isolated grime shapes; same shared matte material, UV distinguishes color.
    for i,(x,y,z,s) in enumerate([(-.265,-.203,.68,.044),(.205,-.207,.84,.035),(-.15,-.158,1.01,.025),(.29,-.174,.59,.026),(-.245,-.161,.94,.024)]):
        patch('旧衣污斑_'+str(i),body,'spine',[(x-s,y-.004,z-.025),(x+s*.7,y-.004,z-.015),(x+s,y-.004,z+.021),(x-s*.4,y-.004,z+.036)],'stain')
    for i,z in enumerate([.91,1.055]):
        garment=bpy.data.objects['破旧衬衫_梨形大轮廓']
        hit,loc,_,_=garment.ray_cast(Vector((.028,-2,z)),Vector((0,1,0)))
        y=loc.y-.003 if hit else -.235+(z-.83)*.281
        tetra('衬衫旧扣_'+str(i),body,'spine',[(.022,y-.008,z-.006),(.034,y-.008,z-.006),(.029,y-.013,z+.007),(.029,y+.001,z)],'leather',0)
    shorten_arms(RIG,OBJECTS)
    RIG['creation_height_m']=1.6;RIG['pose']='T Pose';RIG['forward']='-Y';RIG['root_scale']='1,1,1'
    scene=bpy.context.scene;scene['asset_id']=ASSET;scene['palette']='NPC shared 512 x 512 / 10 x 10 / PaletteUV'
    scene['production_status']='authored';scene['scope']='Source only; no gameplay or runtime binding'
    scene.render.engine='BLENDER_EEVEE_NEXT';scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast'
    scene.view_settings.exposure=-.25
    # Keep a clean model-only source; camera and lights are added only after saving.
    for ob in OBJECTS:ob.select_set(True)
    bpy.context.view_layer.objects.active=OBJECTS[0]
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.shading.type='MATERIAL';area.spaces.active.overlay.show_floor=False
                area.spaces.active.region_3d.view_distance=2.6;area.spaces.active.region_3d.view_location=(0,0,.83)
            if area.type=='IMAGE_EDITOR':area.spaces.active.image=IMAGE
    bpy.ops.wm.save_as_mainfile(filepath=str(MODEL))
    # Separate animation reference master uses the exact same rest skeleton and linked model geometry.
    mesh_specs=[(ob.name,ob.data.name,ob['deform_bone']) for ob in OBJECTS]
    for ob in list(OBJECTS):bpy.data.objects.remove(ob,do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users==0:bpy.data.meshes.remove(me)
    for mat in list(bpy.data.materials):
        if mat.users==0:bpy.data.materials.remove(mat)
    bpy.ops.wm.save_as_mainfile(filepath=str(ANIM))
    with bpy.data.libraries.load(str(MODEL),link=True) as (src,dst):dst.meshes=[n for _,n,_ in mesh_specs]
    linked={me.name:me for me in dst.meshes}
    for name,data_name,bone in mesh_specs:
        ob=bpy.data.objects.new(name,linked[data_name]);output.objects.link(ob);ob.parent=RIG
        ob['deform_bone']=bone;ob['asset_id']=ASSET
        # Linked meshes retain deform vertex indices, local groups provide the names.
        ob.vertex_groups.new(name=bone)
        mod=ob.modifiers.new('Skeleton','ARMATURE');mod.object=RIG
    RIG.animation_data_create();act=bpy.data.actions.new('TPOSE_reference');act.use_fake_user=True;RIG.animation_data.action=act
    for pb in RIG.pose.bones:
        pb.rotation_mode='XYZ';pb.keyframe_insert(data_path='rotation_euler',frame=1,group=pb.name)
    bpy.context.scene.frame_start=1;bpy.context.scene.frame_end=1
    for lib in bpy.data.libraries:
        lib.filepath=bpy.path.relpath(bpy.path.abspath(lib.filepath),start=str(SOURCE))
    bpy.ops.wm.save_as_mainfile(filepath=str(ANIM))
    # Reload actual authored model for render/evaluated statistics.
    bpy.ops.wm.open_mainfile(filepath=str(MODEL))
    stats={'asset_id':ASSET,'model':str(MODEL.relative_to(ROOT)),'animation':str(ANIM.relative_to(ROOT))}
    obs=[o for o in bpy.context.scene.objects if o.type=='MESH']
    stats['objects']=len(obs);stats['vertices']=sum(len(o.data.vertices) for o in obs)
    stats['polygons']=sum(len(o.data.polygons) for o in obs)
    stats['triangles']=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in obs)
    pts=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
    stats['bounds_min']=[min(p[i] for p in pts) for i in range(3)];stats['bounds_max']=[max(p[i] for p in pts) for i in range(3)]
    stats['height_m']=stats['bounds_max'][2]-stats['bounds_min'][2];stats['materials']=[m.name for m in bpy.data.materials]
    stats['skeleton_id']=SKEL;stats['bones']=len(bpy.data.objects['Armature'].data.bones)
    stats['parts']=[{'name':o.name,'faces':len(o.data.polygons)} for o in obs]
    for key,p in [('model_sha256',MODEL),('animation_sha256',ANIM)]:stats[key]=hashlib.sha256(p.read_bytes()).hexdigest()
    (WORK/'build_stats.json').write_text(json.dumps(stats,ensure_ascii=False,indent=2),encoding='utf-8')
    print('MODEL_STATS',json.dumps(stats,ensure_ascii=False))
    assert stats['triangles']<=500, stats['triangles']
    render_previews()

def render_previews():
    scene=bpy.context.scene;scene.render.resolution_x=1100;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
    scene.world=bpy.data.worlds.new('Preview World');scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.70,.67,.59,1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.65
    # Workbench previews preserve palette texture and give readable contact shading.
    scene.render.engine='BLENDER_EEVEE_NEXT';scene.render.image_settings.color_mode='RGBA'
    scene.eevee.taa_render_samples=48
    def area(name,loc,power,size):
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
        ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc
        ob.rotation_euler=(Vector((0,0,.85))-ob.location).to_track_quat('-Z','Y').to_euler()
    area('Key',(-3,-4,5),400,5);area('Fill',(4,-2,3),200,4);area('Rim',(2,3,4),320,3)
    data=bpy.data.cameras.new('PreviewCamera');cam=bpy.data.objects.new('PreviewCamera',data);scene.collection.objects.link(cam);scene.camera=cam
    data.type='ORTHO';data.ortho_scale=2.25
    for view,loc in [('front',(0,-6,1.25)),('overview',(3.1,-7,2.55)),('side',(6,0,1.25)),('back',(0,6,1.25))]:
        cam.location=loc;cam.rotation_euler=(Vector((0,-.02,.82))-cam.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(WORK/(SLUG+'_'+view+'_'+VERSION+'.png'));bpy.ops.render.render(write_still=True)

if __name__=='__main__':author()
