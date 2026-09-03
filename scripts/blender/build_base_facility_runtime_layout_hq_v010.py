#!/usr/bin/env python3
"""Build Base 99 HQ v010: loft facilities and stair-detail pass only."""

from __future__ import annotations

import hashlib, importlib.util, json, math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
INPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v009.blend"
OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v010.blend"
PACKAGE_ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v010"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v010"
CATALOG = VERIFY / "base_facility_component_catalog_v010.json"
TREE = VERIFY / "base_facility_component_tree_v010.txt"
LOCK_REPORT = VERIFY / "base_facility_locked_scope_v009_v010.json"
OUT9 = "02_游戏输出_独立资产包_v009"
OUT10 = "02_游戏输出_独立资产包_v010"
OLD_LOFT_SLUGS = {
    "metal_bed_storage", "bed_privacy_curtain", "loft_bar_table", "loft_bar_stool_01",
    "loft_bar_stool_02", "loft_workbench", "loft_computer_terminal", "loft_radio",
    "loft_first_aid_kit", "loft_fire_extinguisher", "loft_supply_cabinet",
}

spec = importlib.util.spec_from_file_location("base_v009", PROJECT / "scripts/blender/build_base_facility_runtime_layout_hq_v009.py")
v009 = importlib.util.module_from_spec(spec); spec.loader.exec_module(v009)
base = v009.base


def setup():
    base.SOURCE = bpy.data.collections["01_制作组件_已统一材质"]
    # Editable sources must stay selectable while text curves are converted.
    base.SOURCE.hide_viewport = False; base.SOURCE.hide_render = True
    base.OUTPUT = bpy.data.collections[OUT9]
    base.MATS.clear(); base.MATS.update({
        "metal": bpy.data.materials["01_精工金属_紫色骨架"],
        "matte": bpy.data.materials["02_细腻哑光_青绿大面"],
        "gloss": bpy.data.materials["03_清漆反光_紫粉点缀"],
        "emit": bpy.data.materials["04_柔和自发光_UI灯光"],
    })


def ensure_child(parent, name):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in parent.children: parent.children.link(c)
    return c


def package(parent, name, slug, category="loft"):
    c = ensure_child(parent, name)
    c["资产包"] = True; c["资产包键"] = slug; c["资产类别"] = category
    c["源场景资产ID"] = "ENV-BASE99-ART-LAYOUT-3D"
    c["未来导出目录"] = str((PACKAGE_ROOT / category / slug).relative_to(PROJECT))
    c["组织版本"] = "v010"; c["当前状态"] = "已深化归类_待独立导出"
    c["本批次范围"] = "参考图二楼设施与楼梯部分"
    return c


def tag(o): o["v010_scope"] = "loft_and_stair_detail"; return o
def box(n,l,s,r,c,t,b=.035,ob=False,rot=(0,0,0)): return tag(base.add_box(n,l,s,r,c,b,t,ob,rot))
def cyl(n,l,rad,d,r,c,t,v=16,rot=(0,0,0)): return tag(base.add_cylinder(n,l,rad,d,r,c,v,t,False,rot))
def sphere(n,l,rad,r,c,t): return tag(base.add_sphere(n,l,rad,r,c,t))
def beam(n,a,b,th,r,c,t): return tag(base.add_beam(n,a,b,th,r,c,t))
def text_north(n,body,l,size,r,c,t,ex=.018):
    bpy.ops.object.select_all(action="DESELECT")
    return tag(base.add_text(n,body,l,size,r,c,ex,"CENTER",(math.pi/2,0,0),t))
def text_west(n,body,l,size,r,c,t,ex=.018):
    bpy.ops.object.select_all(action="DESELECT")
    return tag(base.add_text(n,body,l,size,r,c,ex,"CENTER",(math.pi/2,0,-math.pi/2),t))


def torus(n,l,major,minor,r,c,t,rot=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(align="WORLD", major_segments=24, minor_segments=8, location=l, major_radius=major, minor_radius=minor, rotation=rot)
    src=bpy.context.object; base.link_only(src,base.SOURCE); src.name=n+"__源"; base.assign_material(src,r,base.COLORS[c])
    return tag(base.publish(src,t,n))


def pulse(obj, phase=0, low=.94, high=1.03):
    obj.scale=(1,1,1); obj.keyframe_insert("scale",frame=1+phase)
    obj.scale=(low,low,low); obj.keyframe_insert("scale",frame=22+phase)
    obj.scale=(high,high,high); obj.keyframe_insert("scale",frame=44+phase)
    obj.scale=(1,1,1); obj.keyframe_insert("scale",frame=65+phase)
    if obj.animation_data and obj.animation_data.action:
        for fc in obj.animation_data.action.fcurves:
            for kp in fc.keyframe_points: kp.interpolation="SINE"


def remove_old_loft(output):
    loft = next((c for c in output.children if c.name.startswith("30_阁楼")), None)
    if not loft: raise RuntimeError("missing loft category")
    for c in list(loft.children):
        if c.get("资产包键") in OLD_LOFT_SLUGS:
            for obj in list(c.objects):
                src=bpy.data.objects.get(obj.name+"__源")
                bpy.data.objects.remove(obj,do_unlink=True)
                if src: bpy.data.objects.remove(src,do_unlink=True)
            loft.children.unlink(c); bpy.data.collections.remove(c)
    loft.name="30_二楼生活工作设施"
    return loft


def bed(p):
    x,y=-.3,11.5
    for px in (-2.4,1.8):
        for py in (10.55,12.45): cyl(f"二楼床_支腿_{px}_{py}",(px,py,6.34),.09,.65,"metal","dark_gray",p,12)
    box("二楼床_厚重金属床框",(x,y,6.57),(4.55,2.25,.30),"metal","dark_gray",p,.10)
    box("二楼床_床垫",(x,y,6.88),(4.28,2.06,.42),"matte","green",p,.16)
    box("二楼床_折叠被毯",(.15,11.50,7.15),(3.05,1.94,.22),"matte","teal",p,.13)
    for i,py in enumerate((11.04,11.93)):
        box(f"二楼床_白色枕头_{i+1:02d}",(-1.85,py,7.23),(.84,.72,.23),"matte","light_gray",p,.15,rot=(0,.08,0))
    for i,py in enumerate((10.72,12.28)):
        box(f"二楼床_床下收纳箱_{i+1:02d}",(.60,py,6.28),(1.35,.70,.48),"matte","dark_gray",p,.08)
        box(f"二楼床_床下箱扣_{i+1:02d}",(.60,py-.39,6.30),(.30,.05,.12),"metal","orange",p,.02)


def nightstand(p):
    box("二楼床头柜_主体",(-3.12,11.52,6.62),(1.05,1.05,1.10),"matte","dark_gray",p,.11)
    for z in (6.48,6.84):
        box(f"二楼床头柜_抽屉_{z}",(-3.12,10.96,z),(.88,.08,.28),"matte","purple",p,.035)
        box(f"二楼床头柜_拉手_{z}",(-3.12,10.90,z),(.28,.05,.06),"metal","light_gray",p,.015)
    box("二楼床头柜_书本",(-3.18,11.52,7.24),(.55,.42,.09),"matte","orange",p,.025,rot=(0,0,.12))
    cyl("二楼床头柜_水杯",(-2.78,11.25,7.35),.10,.26,"matte","light_gray",p,16)


def lamp(p):
    cyl("二楼床头灯_底座",(-3.25,11.82,7.25),.22,.09,"metal","dark_gray",p,20)
    cyl("二楼床头灯_灯杆",(-3.25,11.82,7.62),.045,.68,"metal","light_gray",p,12)
    shade=box("二楼床头灯_暖橙灯罩_自发光",(-3.25,11.82,8.00),(.48,.48,.38),"emit","orange",p,.10)
    light_data=bpy.data.lights.new("二楼床头灯_暖光","POINT"); light_data.color=(1,.29,.07); light_data.energy=42; light_data.shadow_soft_size=1.1
    light=bpy.data.objects.new("二楼床头灯_暖光",light_data); p.objects.link(light); light.location=(-3.25,11.82,7.85); tag(light); pulse(shade,8,.94,1.04)


def rug(p, name, center, size, color="warm_gray"):
    box(name+"_软质主体",(center[0],center[1],6.09),(size[0],size[1],.055),"matte",color,p,.14)
    for i,x in enumerate((center[0]-size[0]*.32,center[0],center[0]+size[0]*.32)):
        box(f"{name}_编织纹_{i+1:02d}",(x,center[1],6.123),(.035,size[1]*.82,.018),"matte","purple",p,.006)


def curtain(p):
    x,y=2.72,11.52
    cyl("二楼条纹隔断_顶杆",(x,y,8.62),.055,2.70,"metal","dark_gray",p,16,rot=(math.pi/2,0,0))
    for py in (10.25,12.79): beam(f"二楼条纹隔断_吊杆_{py}",(x,py,8.62),(x,py,8.92),.035,"metal","dark_gray",p)
    for i in range(7):
        py=10.35+i*.39; color="rust" if i%2==0 else "purple"
        panel=box(f"二楼条纹隔断_布帘片_{i+1:02d}",(x,py,7.58),(.10,.41,1.98),"matte",color,p,.035,rot=(0,.03*math.sin(i),0))
        panel.keyframe_insert("rotation_euler",frame=1); panel.rotation_euler.y+=.035*(-1 if i%2 else 1); panel.keyframe_insert("rotation_euler",frame=48); panel.rotation_euler.y-=.035*(-1 if i%2 else 1); panel.keyframe_insert("rotation_euler",frame=96)


def sofa(p):
    x,y=6.05,11.60
    box("二楼沙发_加厚底座",(x,y,6.43),(4.05,1.75,.55),"matte","dark_gray",p,.20)
    for i,px in enumerate((4.75,6.05,7.35)):
        box(f"二楼沙发_座垫_{i+1:02d}",(px,11.28,6.84),(1.20,1.05,.36),"matte","green",p,.17)
        box(f"二楼沙发_靠背软垫_{i+1:02d}",(px,12.18,7.34),(1.20,.38,1.22),"matte","teal",p,.18,rot=(-.10,0,0))
    for px in (3.88,8.22): box(f"二楼沙发_扶手_{px}",(px,11.57,7.00),(.34,1.75,.82),"matte","green",p,.15)
    for i,(px,c) in enumerate(((4.85,"purple"),(6.15,"blue"),(7.28,"red"))):
        box(f"二楼沙发_彩色靠枕_{i+1:02d}",(px,11.82,7.35),(.70,.28,.62),"matte",c,p,.18,rot=(-.10,0,.08*(-1 if i%2 else 1)))


def coffee_table(p):
    x,y=6.1,8.75
    box("二楼茶几_木质台面",(x,y,6.72),(3.00,1.45,.18),"matte","rust",p,.09)
    for px in (4.85,7.35):
        for py in (8.20,9.30): cyl(f"二楼茶几_金属腿_{px}_{py}",(px,py,6.39),.055,.62,"metal","dark_gray",p,12)
    box("二楼茶几_遥控器",(5.72,8.65,6.85),(.42,.20,.08),"gloss","black",p,.035,rot=(0,0,.12))
    cyl("二楼茶几_杯子",(6.35,8.90,6.93),.105,.23,"matte","light_gray",p,16)
    box("二楼茶几_小盘",(6.82,8.60,6.87),(.42,.34,.05),"gloss","purple",p,.05)


def stool(p, idx, loc, color):
    cyl(f"二楼坐墩{idx:02d}_软座",(loc[0],loc[1],6.55),.48,.62,"matte",color,p,24)
    torus(f"二楼坐墩{idx:02d}_底部包边",(loc[0],loc[1],6.25),.40,.055,"metal","dark_gray",p)


def side_table(p):
    x,y=1.75,8.48
    box("二楼辅助小桌_台面",(x,y,6.66),(1.20,.86,.14),"matte","rust",p,.08)
    for px in (1.28,2.22):
        for py in (8.15,8.81): cyl(f"二楼辅助小桌_腿_{px}_{py}",(px,py,6.38),.045,.52,"metal","dark_gray",p,10)
    cyl("二楼辅助小桌_杯子",(1.55,8.45,6.84),.09,.22,"matte","teal",p,14)
    box("二楼辅助小桌_个人终端",(1.95,8.45,6.81),(.34,.24,.06),"gloss","blue",p,.03)


def workstation(p):
    x,y=9.30,13.60
    box("二楼工位_厚实桌面",(x,y,6.88),(4.10,1.15,.18),"matte","dark_gray",p,.09)
    for px in (7.55,11.05): box(f"二楼工位_侧柜腿_{px}",(px,y,6.46),(.42,1.08,.78),"metal","dark_gray",p,.07)
    for i,px in enumerate((8.45,10.05)):
        box(f"二楼工位_显示器外框_{i+1:02d}",(px,13.94,7.72),(1.35,.15,.92),"metal","purple",p,.08)
        screen=box(f"二楼工位_显示器屏幕_{i+1:02d}_自发光",(px,13.84,7.72),(1.16,.035,.73),"emit","cyan" if i==0 else "blue",p,.035)
        cyl(f"二楼工位_显示器支架_{i+1:02d}",(px,13.73,7.16),.055,.38,"metal","dark_gray",p,12)
        pulse(screen,i*14,.96,1.025)
    box("二楼工位_键盘",(9.15,13.12,7.02),(1.20,.38,.07),"gloss","dark_gray",p,.035)
    box("二楼工位_鼠标",(10.12,13.08,7.04),(.23,.34,.09),"gloss","purple",p,.07)
    for px in (7.90,10.75):
        box(f"二楼工位_音箱_{px}",(px,13.18,7.35),(.28,.30,.58),"matte","black",p,.05)
        cyl(f"二楼工位_音箱单元_{px}",(px,13.00,7.38),.085,.025,"gloss","cyan",p,16,rot=(math.pi/2,0,0))
    box("二楼工位_小主机",(10.85,13.50,7.44),(.48,.72,.96),"metal","dark_gray",p,.07)
    box("二楼工位_主机状态灯_自发光",(10.84,13.10,7.65),(.10,.035,.08),"emit","green",p,.02)
    cyl("二楼工位_咖啡杯",(7.55,13.05,7.10),.10,.25,"matte","light_gray",p,16)


def office_chair(p):
    x,y=9.25,12.20
    cyl("二楼办公椅_五星脚中心",(x,y,6.28),.16,.20,"metal","dark_gray",p,16)
    for i in range(5):
        a=i*2*math.pi/5; end=(x+.58*math.cos(a),y+.58*math.sin(a),6.18)
        beam(f"二楼办公椅_五星脚_{i+1:02d}",(x,y,6.23),end,.055,"metal","dark_gray",p)
        cyl(f"二楼办公椅_脚轮_{i+1:02d}",end,.075,.10,"metal","black",p,12,rot=(math.pi/2,0,0))
    cyl("二楼办公椅_升降杆",(x,y,6.63),.07,.72,"metal","light_gray",p,14)
    box("二楼办公椅_坐垫",(x,y,7.02),(1.15,1.05,.28),"matte","teal",p,.17)
    box("二楼办公椅_靠背",(x,12.68,7.72),(1.18,.28,1.42),"matte","green",p,.18,rot=(-.08,0,0))


def neon(p):
    box("GOOD_VIBES_霓虹背板",(9.35,14.70,8.35),(2.30,.10,.86),"metal","dark_gray",p,.06)
    a=text_north("GOOD_VIBES_GOOD文字_自发光","GOOD",(9.35,14.62,8.55),.25,"emit","magenta",p,.012)
    b=text_north("GOOD_VIBES_VIBES文字_自发光","VIBES",(9.35,14.62,8.20),.25,"emit","magenta",p,.012)
    pulse(a,12,.94,1.05); pulse(b,18,.94,1.05)


def cabinet(p, label, x, color):
    box(f"二楼{label}分类柜_主体",(x,14.18,7.00),(1.10,.88,1.80),"matte","dark_gray",p,.11)
    box(f"二楼{label}分类柜_柜门",(x,13.68,7.00),(.94,.08,1.55),"matte",color,p,.06)
    text_north(f"二楼{label}分类柜_标签_自发光",label,(x,13.60,7.45),.17,"emit","light_gray",p,.008)
    box(f"二楼{label}分类柜_拉手",(x+.30,13.57,6.92),(.08,.04,.35),"metal","light_gray",p,.02)
    for sx in (-.42,.42):
        for z in (6.35,7.65): cyl(f"二楼{label}分类柜_固定件_{sx}_{z}",(x+sx,13.55,z),.035,.025,"metal","light_gray",p,8,rot=(math.pi/2,0,0))


def crate(p, idx, loc, color, label):
    box(f"二楼收纳箱{idx:02d}_主体",loc,(1.15,.82,.62),"matte",color,p,.09)
    for px in (loc[0]-.48,loc[0]+.48): box(f"二楼收纳箱{idx:02d}_侧包角_{px}",(px,loc[1],loc[2]),(.10,.84,.64),"metal","dark_gray",p,.02)
    box(f"二楼收纳箱{idx:02d}_锁扣",(loc[0],loc[1]-.44,loc[2]),(.28,.05,.18),"metal","light_gray",p,.025)
    text_north(f"二楼收纳箱{idx:02d}_{label}标签",label,(loc[0],loc[1]-.48,loc[2]+.05),.11,"matte","light_gray",p,.006)


def wall_decor(p):
    box("二楼工具洞洞板_主体",(.55,14.70,8.05),(3.60,.10,1.55),"metal","mid_gray",p,.06)
    for r in range(4):
        for c in range(10): cyl(f"二楼工具洞洞板_孔_{r}_{c}",(-.98+c*.34,14.62,7.52+r*.34),.025,.025,"metal","dark_gray",p,8,rot=(math.pi/2,0,0))
    for i,x in enumerate((-.55,.05,.65,1.25)): beam(f"二楼工具洞洞板_工具_{i+1:02d}",(x,14.55,7.65),(x+.12,14.55,8.25),.045,"metal","light_gray",p)
    text_north("二楼EXPLORE海报_文字_自发光","EXPLORE",(-1.90,14.60,8.15),.16,"emit","orange",p,.008)
    box("二楼EXPLORE海报_底板",(-1.90,14.70,8.02),(1.35,.09,1.60),"matte","dark_gray",p,.05)


def plant(p):
    cyl("二楼吊挂植物_花盆",(3.15,14.25,8.28),.25,.38,"matte","rust",p,18)
    for i in range(7):
        a=i*2*math.pi/7; beam(f"二楼吊挂植物_叶片_{i+1:02d}",(3.15,14.25,8.18),(3.15+.35*math.cos(a),14.25+.28*math.sin(a),7.55-.12*(i%3)),.075,"matte","green",p)
    for py in (14.05,14.45): beam(f"二楼吊挂植物_吊绳_{py}",(3.15,py,8.45),(3.15,py,8.92),.025,"metal","dark_gray",p)


def add_l_stair_details(p):
    p["组织版本"]="v010"; p["本批次范围"]="既有L型楼梯结构锁定，仅新增表面与安全细节"
    for run,prefix in (("西墙第一跑","L梯_西墙第一跑踏步_"),("北墙第二跑","L梯_北墙第二跑踏步_")):
        for i in range(1,11):
            step=bpy.data.objects[f"{prefix}{i:02d}"]; loc=step.location; dim=step.dimensions
            if run=="西墙第一跑":
                box(f"L梯v010_{run}_前缘防滑条_{i:02d}",(loc.x,loc.y-dim.y*.47,loc.z+dim.z*.52),(dim.x*.86,.055,.035),"metal","light_gray",p,.008)
                box(f"L梯v010_{run}_暖光踏步灯_{i:02d}_自发光",(loc.x,loc.y-dim.y*.53,loc.z+dim.z*.18),(dim.x*.78,.025,.045),"emit","orange",p,.006)
            else:
                box(f"L梯v010_{run}_前缘防滑条_{i:02d}",(loc.x-dim.x*.47,loc.y,loc.z+dim.z*.52),(.055,dim.y*.86,.035),"metal","light_gray",p,.008)
                box(f"L梯v010_{run}_暖光踏步灯_{i:02d}_自发光",(loc.x-dim.x*.53,loc.y,loc.z+dim.z*.18),(.025,dim.y*.78,.045),"emit","orange",p,.006)
    box("L梯v010_转角平台防滑钢板",(-13.8,13.8,3.07),(1.78,1.78,.055),"metal","mid_gray",p,.03)
    for y in (13.06,14.54): box(f"L梯v010_转角平台警示条_{y}",(-13.8,y,3.11),(1.65,.08,.025),"matte","yellow",p,.008)
    box("L梯v010_顶层接驳无缝压板",(-4.82,13.8,6.105),(.32,1.82,.055),"metal","light_gray",p,.018)
    text_west("L梯v010_STAY_CURIOUS标识_自发光","STAY CURIOUS",(-14.62,11.1,5.15),.18,"emit","orange",p,.009)


def east_stair(p):
    x=13.15; y0=9.65; dy=.46; dz=.285
    for i in range(10):
        y=y0+i*dy; z=6.18+i*dz
        box(f"二楼东侧上行梯_踏步_{i+1:02d}",(x,y,z),(1.82,.46,.285),"metal","dark_gray",p,.045)
        box(f"二楼东侧上行梯_防滑面_{i+1:02d}",(x,y-.19,z+.16),(1.55,.06,.035),"metal","light_gray",p,.008)
        box(f"二楼东侧上行梯_暖光灯_{i+1:02d}_自发光",(x,y-.235,z+.04),(1.42,.025,.045),"emit","orange",p,.006)
    box("二楼东侧上行梯_顶部接驳平台",(x,14.45,8.94),(2.05,1.05,.16),"metal","dark_gray",p,.05)
    box("二楼东侧上行梯_底部无缝压板",(x,9.37,6.08),(1.82,.32,.055),"metal","light_gray",p,.018)
    for sx in (12.18,14.12):
        beam(f"二楼东侧上行梯_侧梁_{sx}",(sx,9.45,6.02),(sx,14.18,8.82),.10,"metal","dark_gray",p)
        for i in range(6):
            y=9.45+i*.92; z=6.55+i*.55
            cyl(f"二楼东侧上行梯_栏杆柱_{sx}_{i:02d}",(sx,y,z),.045,1.0,"metal","dark_gray",p,10)
        beam(f"二楼东侧上行梯_扶手_{sx}",(sx,9.45,7.05),(sx,14.18,9.82),.065,"metal","dark_gray",p)
    p["接口契约"]="bottom platform top Z=6.105; first tread top Z=6.3225; top landing top Z=9.02"


def leaf_packages(root):
    out=[]
    def walk(c):
        if c.get("资产包"): out.append(c)
        for ch in c.children: walk(ch)
    walk(root); return out


def objsig(o):
    data=None
    if o.type=="MESH":
        coords=tuple(round(float(c),6) for v in o.data.vertices for c in v.co)
        data=(len(o.data.vertices),len(o.data.polygons),hashlib.sha256(repr(coords).encode()).hexdigest(),tuple(m.name if m else None for m in o.data.materials))
    return {"type":o.type,"parent":o.parent.name if o.parent else None,"matrix":[round(float(c),7) for row in o.matrix_world for c in row],"dim":[round(float(c),7) for c in o.dimensions],"data":data}


def locked(root):
    d={}
    for p in leaf_packages(root):
        if p.get("资产包键") in OLD_LOFT_SLUGS: continue
        for o in p.objects:
            if not o.get("v010_scope"): d[o.name]=objsig(o)
    return d


def bbox(objects):
    pts=[o.matrix_world@Vector(c) for o in objects for c in o.bound_box] if objects else []
    if not pts:return [0,0,0],[0,0,0]
    lo=[min(p[i] for p in pts) for i in range(3)]; hi=[max(p[i] for p in pts) for i in range(3)]
    return [round((lo[i]+hi[i])/2,4) for i in range(3)],[round(hi[i]-lo[i],4) for i in range(3)]


def write_catalog(root):
    VERIFY.mkdir(parents=True,exist_ok=True); entries=[]
    for p in sorted(leaf_packages(root),key=lambda c:c.name):
        cat=p.get("资产类别","uncategorized"); slug=p.get("资产包键",p.name); p["组织版本"]="v010"
        p["未来导出目录"]=str((PACKAGE_ROOT/cat/slug).relative_to(PROJECT)); folder=PROJECT/p["未来导出目录"]; folder.mkdir(parents=True,exist_ok=True)
        objs=sorted(p.objects,key=lambda o:o.name); center,size=bbox(objs)
        e={"asset_id":"ENV-BASE99-ART-LAYOUT-3D","package_id":f"ENV-BASE99-ART-LAYOUT-3D::{slug}","display_name":p.name,"asset_slug":slug,"category":cat,"version":"v010","collection_path":p.name,"future_export_directory":p["未来导出目录"],"source_blend":str(OUTPUT_BLEND.relative_to(PROJECT)),"object_count":len(objs),"mesh_count":sum(o.type=="MESH" for o in objs),"light_count":sum(o.type=="LIGHT" for o in objs),"object_names":[o.name for o in objs],"world_center_m":center,"bounding_size_m":size,"local_origin":"preserve scene master world placement","forward_axis":"Blender +Y north","material_roles":sorted({o.get("material_role") for o in objs if o.get("material_role")}),"has_animation":any(o.animation_data and o.animation_data.action for o in objs),"expected_export":f"{slug}_visual_top3d_v001.glb","collision_status":"not_authored_in_this_partial_blender_pass","export_status":"not_exported"}
        (folder/"asset_manifest.json").write_text(json.dumps(e,ensure_ascii=False,indent=2)+"\n",encoding="utf-8"); entries.append(e)
    doc={"schema":"shellstorm2.base_facility.component_catalog.v2","organization_version":"v010","source_asset_id":"ENV-BASE99-ART-LAYOUT-3D","scope":"loft facilities and stairs only","package_count":len(entries),"floor_tile_package_count":sum(e["category"]=="floor" for e in entries),"packages":entries}
    CATALOG.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    TREE.write_text("基地场景独立资产包树 v010\n"+"\n".join(f"{e['category']}/{e['asset_slug']} objects={e['object_count']}" for e in entries)+"\n",encoding="utf-8")
    return doc


def camera(name,loc,target,scale):
    coll=bpy.data.collections["90_展示环境_灯光相机"]; src=bpy.data.objects["基地微缩模型_英雄相机"]
    cam=src.copy(); cam.data=src.data.copy(); cam.name=name; cam.data.name=name; coll.objects.link(cam); cam.location=loc; cam.rotation_euler=(Vector(target)-cam.location).to_track_quat("-Z","Y").to_euler(); cam.data.type="ORTHO"; cam.data.ortho_scale=scale; tag(cam); return cam


def render(cam,path,x=1600,y=1000):
    s=bpy.context.scene; s.camera=cam; s.render.filepath=str(path); s.render.resolution_x=x; s.render.resolution_y=y; s.render.resolution_percentage=100; bpy.ops.render.render(write_still=True)


def main():
    if Path(bpy.data.filepath).resolve()!=INPUT_BLEND.resolve(): raise RuntimeError("must start from v009")
    if OUTPUT_BLEND.exists(): raise RuntimeError(f"target exists: {OUTPUT_BLEND}")
    setup(); output=bpy.data.collections[OUT9]; before=locked(output); output.name=OUT10; base.OUTPUT=output
    loft=remove_old_loft(output)
    packs={}
    def P(num,name,slug,cat="loft"): packs[slug]=package(loft,f"{num}_{name}_资产包",slug,cat); return packs[slug]
    bed(P(31,"床架床品与床下收纳","loft_bed_and_bedding")); nightstand(P(32,"床头柜与生活物件","loft_nightstand")); lamp(P(33,"暖光床头灯","loft_bedside_lamp")); rug(P(34,"床边小地毯","loft_bedside_rug"),"二楼床边地毯",(-.2,9.85),(4.2,1.0),"warm_gray"); curtain(P(35,"条纹隔断帘","loft_striped_privacy_curtain")); sofa(P(36,"三人休闲沙发","loft_lounge_sofa")); coffee_table(P(37,"生活茶几与桌面物件","loft_coffee_table")); rug(P(38,"休闲区地毯","loft_lounge_rug"),"二楼休闲地毯",(6.05,9.8),(5.2,3.2),"purple"); stool(P(39,"圆形坐墩01","loft_pouf_01"),1,(3.45,8.10),"teal"); stool(P(40,"圆形坐墩02","loft_pouf_02"),2,(8.65,8.15),"green"); side_table(P(41,"辅助小桌","loft_side_table")); workstation(P(42,"双屏电脑工位","loft_computer_workstation")); office_chair(P(43,"办公椅","loft_office_chair")); neon(P(44,"GOOD VIBES霓虹标识","loft_good_vibes_neon")); cabinet(P(45,"MEDICAL分类柜","loft_medical_cabinet"),"MEDICAL",5.10,"red"); cabinet(P(46,"BATTERY分类柜","loft_battery_cabinet"),"BATTERY",6.35,"teal"); cabinet(P(47,"FOOD分类柜","loft_food_cabinet"),"FOOD",7.60,"orange"); crate(P(48,"收纳箱01","loft_storage_crate_01"),1,(10.40,14.25,6.38),"orange","TOOLS"); crate(P(49,"收纳箱02","loft_storage_crate_02"),2,(11.45,14.25,6.38),"blue","SUPPLY"); wall_decor(P(50,"工具洞洞板与EXPLORE海报","loft_wall_utility_decor")); plant(P(51,"吊挂植物","loft_hanging_plant"))
    stair_cat=ensure_child(output,"15_楼梯深化与过渡结构")
    old_stair=next(p for p in leaf_packages(output) if p.get("资产包键")=="northwest_l_stair")
    add_l_stair_details(old_stair)
    east=package(stair_cat,"52_东侧上行过渡楼梯_资产包","east_upper_transition_stair","architecture"); east_stair(east)
    after=locked(output)
    if before!=after:
        changed=sorted(k for k in before.keys()&after.keys() if before[k]!=after[k]); raise RuntimeError(f"locked scope changed {changed[:10]} added={sorted(after.keys()-before.keys())[:10]} removed={sorted(before.keys()-after.keys())[:10]}")
    doc=write_catalog(output); h=hashlib.sha256(json.dumps(before,sort_keys=True).encode()).hexdigest(); LOCK_REPORT.write_text(json.dumps({"input":str(INPUT_BLEND.relative_to(PROJECT)),"output":str(OUTPUT_BLEND.relative_to(PROJECT)),"locked_object_count":len(before),"locked_match":True,"locked_signature_v009":h,"locked_signature_v010":h,"package_count":doc["package_count"],"floor_tile_package_count":doc["floor_tile_package_count"]},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    loftcam=camera("基地微缩模型_二楼参考验收相机",(-18,-10,15),(3.2,11.0,6.6),25.0); staircam=camera("基地微缩模型_楼梯接口验收相机",(-21,4,10),(-8.5,12.0,4.5),20.0)
    bpy.context.scene["v010_scope"]="二楼设施与楼梯深化"; bpy.context.scene["v010_locked_count"]=len(before); bpy.context.scene["v010_package_count"]=doc["package_count"]
    base.SOURCE.hide_viewport=True; base.SOURCE.hide_render=True
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND)); VERIFY.mkdir(parents=True,exist_ok=True)
    render(bpy.data.objects["基地微缩模型_英雄相机"],VERIFY/"base_facility_runtime_layout_hq_v010.png")
    render(bpy.data.objects["基地微缩模型_顶视相机"],VERIFY/"base_facility_runtime_layout_hq_v010_top.png")
    render(loftcam,VERIFY/"base_facility_runtime_layout_hq_v010_loft_facilities.png")
    render(staircam,VERIFY/"base_facility_runtime_layout_hq_v010_stair_interfaces.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND)); print(f"BASE_FACILITY_V010_BUILT packages={doc['package_count']} locked={len(before)}")


if __name__=="__main__": main()
