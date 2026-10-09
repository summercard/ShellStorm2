# -*- coding: utf-8 -*-
"""Editable environment VFX source. Blender 4.5, no runtime handlers/drivers."""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector
from math import sin, cos, pi

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/vfx/environment_3d/bird_flocks'
OUT=ROOT/'outputs/bird_flocks_v001'
PAL=ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
MAT_SOURCE=ROOT/'assets/art/environments/tower_zones/shared/source/common_components/v001/generic_scene_components_source_v001.blend'
ROLE='02_细腻哑光_青绿大面'
FPS=30
def sat(x): return max(0,min(1,x))
def smooth(x): x=sat(x); return x*x*(3-2*x)
def mix(a,b,t): return a+(b-a)*t
def collection(name,scene):
    c=bpy.data.collections.new(name); scene.collection.children.link(c); return c
def aim(o,p): o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
def make_material():
    with bpy.data.libraries.load(str(MAT_SOURCE),link=False) as (a,b): b.materials=[ROLE]
    mat=b.materials[0]; mat.name=ROLE
    image=bpy.data.images.load(str(PAL),check_existing=True)
    image.filepath=str(PAL)
    for node in mat.node_tree.nodes:
        if node.type=='TEX_IMAGE': node.image=image; node.interpolation='Closest'
        if node.type=='UVMAP': node.uv_map='PaletteUV'
    mat.diffuse_color=(.558,.617,.687,1)
    return mat

class Geometry:
    def __init__(self): self.v=[]; self.f=[]; self.groups={}
    def add(self,v,f,bone):
        n=len(self.v); self.v.extend(v); self.f.extend([tuple(n+i for i in face) for face in f]); self.groups.setdefault(bone,[]).extend(range(n,len(self.v)))
    def ellipsoid(self,c,r,bone,rings=4,segs=8):
        v=[(c[0],c[1],c[2]+r[2])]
        for j in range(1,rings):
            a=pi*j/rings
            for i in range(segs):
                b=2*pi*i/segs; v.append((c[0]+r[0]*sin(a)*cos(b),c[1]+r[1]*sin(a)*sin(b),c[2]+r[2]*cos(a)))
        v.append((c[0],c[1],c[2]-r[2])); f=[]
        for i in range(segs): f.append((0,1+i,1+(i+1)%segs))
        for j in range(rings-2):
            for i in range(segs):
                a=1+j*segs+i; b=1+j*segs+(i+1)%segs
                f.extend([(a,a+segs,b),(b,a+segs,b+segs)])
        for i in range(segs): f.append((len(v)-1,len(v)-1-segs+(i+1)%segs,len(v)-1-segs+i))
        self.add(v,f,bone)
    def slab(self,outline,bone,thick=.012):
        n=len(outline); c=tuple(sum(p[j] for p in outline)/n for j in range(3))
        v=list(outline)+[(c[0],c[1],c[2]+thick),(c[0],c[1],c[2]-thick)]
        self.add(v,[(i,(i+1)%n,n) for i in range(n)]+[((i+1)%n,i,n+1) for i in range(n)],bone)
    def rod(self,a,b,r,bone):
        axis=(Vector(b)-Vector(a)).normalized(); u=axis.cross(Vector((1,0,0)))
        if u.length<.01: u=axis.cross(Vector((0,1,0)))
        u.normalize(); w=axis.cross(u)
        v=[tuple(Vector(p)+r*(cos(i*pi/2)*u+sin(i*pi/2)*w)) for p in (a,b) for i in range(4)]
        self.add(v,[(0,3,2,1),(4,5,6,7)]+[(i,(i+1)%4,(i+1)%4+4,i+4) for i in range(4)],bone)

def bird(index,c,mat,group):
    name=f'鸟{index+1:02d}'
    arm=bpy.data.armatures.new(name+'_可编辑骨架'); ob=bpy.data.objects.new(name+'_动作控制',arm); c.objects.link(ob); ob.parent=group
    bpy.context.view_layer.objects.active=ob; ob.select_set(True); bpy.ops.object.mode_set(mode='EDIT')
    definitions={'body':((0,0,0),None),'head':((0,.15,.065),'body'),'tail':((0,-.17,0),'body')}
    for s,label in ((1,'R'),(-1,'L')):
        definitions['wing_'+label]=((s*.075,.035,.025),'body')
        definitions['tip_'+label]=((s*.32,.025,.025),'wing_'+label)
        definitions['leg_'+label]=((s*.048,-.015,-.062),None)
        definitions['foot_'+label]=((s*.048,-.005,-.174),None)
    for n,(p,parent) in definitions.items():
        b=arm.edit_bones.new(n); b.head=p; b.tail=Vector(p)+Vector((0,.09,0))
        if parent: b.parent=arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT'); ob.select_set(False)
    arm.display_type='STICK'; ob.show_in_front=True
    g=Geometry(); g.ellipsoid((0,-.015,0),(.09,.202,.102),'body')
    g.ellipsoid((0,.168,.085),(.065,.085,.067),'head')
    g.add([(-.027,.22,.07),(.027,.22,.07),(0,.22,.105),(0,.303,.068),(0,.23,.047)],[(0,2,3),(2,1,3),(1,4,3),(4,0,3),(0,4,1,2)],'head')
    g.slab([(-.035,-.15,.015),(.035,-.15,.015),(.087,-.345,-.013),(.04,-.362,-.016),(0,-.352,-.016),(-.04,-.362,-.016),(-.087,-.345,-.013)],'tail',.009)
    for s,label in ((1,'R'),(-1,'L')):
        def wing(poly,n):
            p=[(s*x,y,z) for x,y,z in poly]
            if s<0:p.reverse()
            g.slab(p,n)
        wing([(.055,.075,.025),(.24,.09,.02),(.335,.025,.025),(.32,-.1,.018),(.17,-.15,.014),(.055,-.08,.02)],'wing_'+label)
        wing([(.32,.027,.025),(.49,-.013,.016),(.65,-.095,.006),(.53,-.13,.008),(.60,-.16,.005),(.49,-.18,.008),(.54,-.205,.002),(.40,-.20,.007),(.32,-.10,.018)],'tip_'+label)
        g.rod((s*.048,-.015,-.062),(s*.048,-.005,-.174),.011,'leg_'+label)
        for dx in (-.023,0,.023):
            g.rod((s*.048,-.005,-.174),(s*.048+dx,.055-abs(dx)*.4,-.174),.005,'foot_'+label)
        g.rod((s*.048,-.005,-.174),(s*.048,-.035,-.174),.004,'foot_'+label)
    me=bpy.data.meshes.new(name+'_低模'); me.from_pydata(g.v,[],g.f); me.update()
    mesh=bpy.data.objects.new(name+'_白色剪影',me); c.objects.link(mesh); mesh.parent=ob; me.materials.append(mat)
    uv=me.uv_layers.new(name='PaletteUV'); uv.active_render=True
    for face in me.polygons:
        for k,li in enumerate(face.loop_indices):
            a=2*pi*k/len(face.loop_indices); uv.data[li].uv=(.95+.021*cos(a),.05+.021*sin(a))
    for n,ids in g.groups.items(): mesh.vertex_groups.new(name=n).add(ids,1,'REPLACE')
    mod=mesh.modifiers.new('鸟翼与身体骨骼','ARMATURE'); mod.object=ob
    scale=[1,.92,1.05,.96,.88,1.02,.94][index]; ob.scale=(scale,)*3
    ob['individual_seed']=index; ob['bird_scale']=scale; ob['forward']='+Y'; ob['ground_contact_height']=.179*scale
    for p in ob.pose.bones:p.rotation_mode='XYZ'
    return ob,mesh

# Each bird has its own offset, wingbeat frequency, glide window, and landing/takeoff time.
ANCHORS=[(-1.65,-.48),(-.55,.12),(.65,-.4),(1.8,.25),(-1.15,1.05),(.22,1.28),(1.5,1.45)]
def ground_walk(t,i):
    start=6.3+.18*i; x,y=ANCHORS[i]; yaw=(-.7+.24*i)
    gait=0; activity='rest'
    # Explicit finite travel blocks create pauses and keep feet/translation in sync.
    for k,(offset,duration,turn) in enumerate(((0,1.35,.18),(3.8,1.15,-.52),(7.0,1.05,.37))):
        a=start+offset; u=sat((t-a)/duration); heading=yaw+turn
        if a-.35<t<a:
            return x,y,mix(yaw,heading,smooth((t-a+.35)/.35)),0,0,'rest'
        dist=.36*(u-sin(2*pi*u)/(2*pi))
        x-=sin(heading)*dist; y+=cos(heading)*dist
        if a<=t<a+duration:
            speed=.36/duration*(1-cos(2*pi*u)); gait=speed/.62
            return x,y,heading,gait,(t-a)*3.5,'walk'
        if t>=a+duration:yaw=heading
    return x,y,yaw,0,0,activity

def ground_state(t,i):
    land=3.1+.20*i; leave=17.0+[0,.48,.18,.80,.34,1.03,.66][i]
    x,y,yaw,gait,phase,activity=ground_walk(t,i)
    h=.179*[1,.92,1.05,.96,.88,1.02,.94][i]; dip=0
    if t<land:
        u=sat(t/land); rem=1-u
        x=ANCHORS[i][0]-.6*rem; y=ANCHORS[i][1]-7*rem*rem
        z=h+3.3*rem*rem
        flight=1; fold=0; yaw=-.04; pitch=.28*smooth((u-.65)/.25)
        leg=smooth((u-.72)/.2); activity='approach'
    elif t<land+.85:
        dt=t-land; x,y=ANCHORS[i]; z=h; dip=.027*sin(pi*sat(dt/.28)) if dt<.28 else 0
        flight=1-smooth(dt/.42); fold=smooth((dt-.18)/.62); pitch=.23*(1-smooth(dt/.45)); leg=1; yaw=mix(-.04,-.7+.24*i,smooth(dt/.85)); activity='settle'
    elif t<leave-.55:
        z=h+.007*gait*abs(sin(2*pi*phase)); flight=0; fold=1; pitch=0; leg=1
    elif t<leave:
        q=sat((t-(leave-.55))/.55); z=h; dip=.035*sin(pi*q); flight=smooth((q-.2)/.7); fold=1-smooth(q); pitch=-.15*sin(pi*q); gait=0; leg=1; activity='anticipation'
    else:
        dt=t-leave; yaw=mix(yaw,-.72,smooth(dt/1.3)); distance=.65*dt+3*(dt-1+math.exp(-dt))
        x+=.64*distance; y+=.77*distance
        z=h+1.35*dt+.5*(dt-1+math.exp(-dt)); flight=1; fold=0; leg=1-smooth(dt/.48); pitch=.22*(1-smooth(dt/2)); gait=0; activity='depart'
    return dict(x=x,y=y,z=z,yaw=yaw,flight=flight,fold=fold,pitch=pitch,leg=leg,gait=gait,step=phase,activity=activity,leave=leave,land=land,dip=dip)

def flight_state(t,i):
    # Soft broken V, rather than a rigid duplicated line.
    side=1 if i%2 else -1; rank=(i+1)//2
    x=-9+1.5*t-rank*.70+.10*sin(t*1.1+i)
    y=side*rank*.70+.24*sin(t*.75+i*.62)
    z=2.6+.13*rank+.13*sin(t*1.6+i*.8)
    yaw=-pi/2+.08*cos(t*.75+i*.62)
    glide=smooth((sin(t*1.35+i*1.7)-.42)/.43)
    return dict(x=x,y=y,z=z,yaw=yaw,flight=1-glide*.94,fold=0,pitch=.025*sin(t*2+i),leg=0,gait=0,step=0,activity='flight')

def animate(ob,i,kind,end):
    b=ob.pose.bones
    for frame in range(1,end+1):
        t=(frame-1)/FPS; d=flight_state(t,i) if kind=='flyby' else ground_state(t,i)
        ob.location=(d['x'],d['y'],d['z']); ob.rotation_euler=(0,0,d['yaw'])
        ob.keyframe_insert('location',frame=frame,group='路径'); ob.keyframe_insert('rotation_euler',frame=frame,group='路径')
        for p in b:p.location=(0,0,0); p.rotation_euler=(0,0,0); p.scale=(1,1,1)
        # Fast downstroke, slower recovery; articulated wingtips lag behind shoulders.
        phase=2*pi*((2.75+i*.071)*t)+i*1.13
        flap=sin(phase)+.22*sin(2*phase+.45)
        amp=d['flight']; fold=d['fold']
        clearance=smooth((d['z']-.18)/.6) if kind=='ground' else 1
        wing_angle=mix(.52+.28*flap,.76*flap+.1,clearance)*amp+.08*(1-amp)
        for s,label in ((1,'R'),(-1,'L')):
            w=b['wing_'+label]; tip=b['tip_'+label]
            w.rotation_euler=(mix(.055*amp*cos(phase),pi/2,fold),-s*wing_angle*(1-fold), -s*pi/2*fold)
            w.scale.y=mix(1,.46,fold)  # feather fan closes as the wing folds
            # folding each distal half back over the body produces a clean perched silhouette.
            tip.rotation_euler=(0,s*(-(2*pi-3.05)*fold-.35*amp*sin(phase-.68)*clearance),-s*.15*amp*(1-sin(phase-.4)))
            leg=b['leg_'+label]; foot=b['foot_'+label]
            tuck=1-d['leg']; leg.rotation_euler.x=1.10*tuck
            leg.location.z=-d.get('dip',0); leg.scale.z=1-d.get('dip',0)/.112
            foot.location.y=-.09*tuck; foot.location.z=.065*tuck
            if d['gait']>.001:
                # Duty cycle: planted for 60%, airborne for 40%. Body speed envelope fades strides.
                u=(d['step']+(0 if s==1 else .5))%1; a=.052*d['gait']
                if u<.6: fy=a*(1-2*u/.6); fz=0
                else: q=(u-.6)/.4; fy=-a*cos(pi*q); fz=.028*sin(pi*q)*d['gait']
                foot.location.y+=fy; foot.location.z+=fz
                leg.rotation_euler.x=math.atan2(fy,.112-fz)
        b['body'].rotation_euler=(d['pitch'],.045*amp*sin(t*2.1+i),.018*amp*cos(phase))
        b['body'].location.z=.01*amp*sin(phase-.5)-d.get('dip',0)
        b['tail'].rotation_euler=(.07*amp*sin(phase-.9)-.12*d['pitch'],0,.08*sin(t*1.3+i))
        # Unequal head checks, two pecks, one preen, and a rapid shared alert before departure.
        if kind=='ground' and d['activity'] in ('rest','walk','anticipation'):
            peck=0
            for center in (8.8+i*.24,12.4-i*.19):
                peck+=math.exp(-((t-center)/.17)**2)*1.0
                peck+=math.exp(-((t-center-.45)/.14)**2)*.48
            preen=math.exp(-((t-(14.6+.13*i))/.40)**2) if i in (1,4) else 0
            look=.36*sin(t*1.8+i)*(.5+.5*sin(t*.73+i))
            alert=smooth((t-(d['leave']-.85))/.3)
            b['head'].rotation_euler=(-peck+.15*alert,preen*.3,look*(1-alert)+preen*1.0)
            b['body'].rotation_euler.x-=.48*peck
            b['head'].location.y=.011*d['gait']*sin(2*pi*d['step'])
        else:b['head'].rotation_euler=(-.45*d['pitch'],0,.08*sin(t*1.4+i))
        for p in b:
            p.keyframe_insert('rotation_euler',frame=frame,group=p.name)
            p.keyframe_insert('location',frame=frame,group=p.name)
            p.keyframe_insert('scale',frame=frame,group=p.name)
    act=ob.animation_data.action; act.name=f'{kind}_bird_{i+1:02d}_baked_30fps'; act.use_fake_user=True
    for fc in act.fcurves:
        for key in fc.keyframe_points:key.interpolation='LINEAR'

def setup_preview(scene,kind):
    c=collection('90_展示与验收_不导出',scene)
    data=bpy.data.cameras.new('参考镜头'); cam=bpy.data.objects.new('参考镜头_全景',data); c.objects.link(cam); scene.camera=cam
    data.type='ORTHO'; data.ortho_scale=11 if kind=='flyby' else 8.1
    cam.location=(4,-9,11); aim(cam,(0,.2,1.8 if kind=='flyby' else .4))
    if kind=='flyby':
        for f in range(1,scene.frame_end+1):
            x=-9+1.5*(f-1)/30-1.2; cam.location=(x+4,-9,11); aim(cam,(x,0,2.8)); cam.keyframe_insert('location',frame=f); cam.keyframe_insert('rotation_euler',frame=f)
    for name,pos,power,size in [('主光',(2,-3,8),1400,7),('轮廓',(-4,4,6),1000,5)]:
        ld=bpy.data.lights.new(name,'AREA'); lo=bpy.data.objects.new(name,ld); c.objects.link(lo); lo.location=pos; ld.energy=power; ld.shape='DISK'; ld.size=size; aim(lo,(0,0,0))
    scene.world=bpy.data.worlds.new('深蓝灰展示背景'); scene.world.use_nodes=True; scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.035,.05,.075,1); scene.world.node_tree.nodes['Background'].inputs[1].default_value=.6
    scene.render.engine='BLENDER_EEVEE_NEXT'; scene.eevee.taa_render_samples=32
    scene.render.resolution_x=1280; scene.render.resolution_y=800; scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX'
    scene.display.shading.light='STUDIO'; scene.display.shading.studiolight_rotate_z=.4
    scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_shadows=True; scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type='BOTH'; scene.display.shading.background_type='WORLD'; scene.world.color=(.035,.05,.075)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=='VIEW_3D':
                a.spaces.active.region_3d.view_perspective='CAMERA'; a.spaces.active.overlay.show_extras=False
    return cam

def build(kind):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene; scene.name='01_七鸟空中掠过' if kind=='flyby' else '02_七鸟落地停留再飞走'
    scene.render.fps=FPS; scene.frame_start=1; scene.frame_end=361 if kind=='flyby' else 721; scene.unit_settings.system='METRIC'
    scene['category']='场景特效'; scene['status']='Blender源已完成；未接入Godot'; scene['palette_cell']='R10C10 冷白 #C5CED8'; scene['animation_notes']='7 birds; baked independent keyframes; single-shot; no handlers; +Y forward, +Z up; ground Z=0'
    mat=make_material(); c=collection('02_游戏输出_鸟群资产包',scene)
    group=bpy.data.objects.new('鸟群_整体移动缩放控制',None); c.objects.link(group)
    group['asset_id']='VFX-ENV-BIRDS-'+('FLYBY' if kind=='flyby' else 'GROUND')+'-3D'; group['asset_version']='v001'; group['collision']='none'; group['bird_count']=7
    birds=[]
    for i in range(7):
        ob,mesh=bird(i,c,mat,group); animate(ob,i,kind,scene.frame_end); birds.append((ob,mesh))
    for label,frame in ([('开始掠过',1),('展翼与滑翔',120),('离开',361)] if kind=='flyby' else [('接近',1),('错峰落地',94),('全部收翼',156),('走动与啄地',225),('张望与理羽',420),('警觉蹬地',500),('依次起飞',526),('飞离',660)]):scene.timeline_markers.new(label,frame=frame)
    setup_preview(scene,kind)
    txt=bpy.data.texts.new('使用说明_请先阅读'); txt.write('场景特效 / 7只白色低模鸟\n空格播放时间轴。所有动作已烘焙，不需要运行脚本。\n选鸟的动作控制骨架，Pose Mode 可编辑；动作编辑器按骨骼分组。\n整体移动请操作 鸟群_整体移动缩放控制。\n90_展示与验收 集合仅相机灯光，不导出。\n地面 Z=0，+Y为鸟前方，+Z为上。\n单次演出：首尾不连接，不应循环中途瞬移。\n材质直接继承场景共享哑光材质；PaletteUV位于R10C10冷白区。\n源文件已完成，未导出GLB/未接入Godot。\n')
    scene.frame_set(150 if kind=='flyby' else 285)
    bpy.ops.object.select_all(action='DESELECT'); group.select_set(True); bpy.context.view_layer.objects.active=group
    folder=BASE/'source'/kind/'v001'; folder.mkdir(parents=True,exist_ok=True); OUT.mkdir(parents=True,exist_ok=True)
    path=folder/f'vfx_env_birds_{kind}_source_v001.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(path))
    # Relative external palette dependency, no private texture copy.
    for im in bpy.data.images:
        if im.source=='FILE':im.filepath=bpy.path.relpath(str(PAL))
    bpy.ops.wm.save_as_mainfile(filepath=str(path))
    manifest=dict(asset_id=group['asset_id'],name_zh=scene.name,category='特效',subcategory='场景特效',version='v001',status='Blender源已完成',source_blend=str(path.relative_to(ROOT)),bird_count=7,fps=FPS,frame_range=[1,scene.frame_end],duration_seconds=(scene.frame_end-1)/FPS,material=ROLE,material_source=str(MAT_SOURCE.relative_to(ROOT)),palette=str(PAL.relative_to(ROOT)),palette_cell='R10C10',palette_rgb=[197,206,216],loop=False,root=group.name,collection=c.name,collision='none',runtime_integrated=False,exported=False,mesh_count=7,bones_per_bird=len(birds[0][0].data.bones),triangles_per_bird=sum(len(p.vertices)-2 for p in birds[0][1].data.polygons))
    (folder/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    for label,f in ([('hero',150),('spread',185)] if kind=='flyby' else [('hero',285),('landing',108),('takeoff',535)]):
        scene.frame_set(f); scene.render.filepath=str(OUT/f'{kind}_{label}.png'); bpy.ops.render.render(write_still=True)
    print('BIRD_SOURCE_DONE',path,flush=True)

if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['flyby','ground']
    for kind in args:build(kind)
