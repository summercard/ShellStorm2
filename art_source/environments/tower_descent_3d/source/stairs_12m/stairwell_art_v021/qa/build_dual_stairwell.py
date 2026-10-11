import bpy, json, hashlib, math
from pathlib import Path
from mathutils import Matrix, Vector

ROOT=Path(__file__).resolve().parents[1]
PREV=ROOT.parent/'stairwell_art_v020'
LEAVES=['通用墙组件_资产包','通用地板组件_资产包','通用楼梯组件_资产包','墙面装甲与结构框_装饰组件','地面导光与警示_装饰组件','工业管线_装饰组件','灯带与发光几何_装饰组件','楼层标识与海报_装饰组件','控制盒_装饰组件','固定绿植_装饰组件']
assert 'v020' in bpy.data.filepath

def mat(loc,rot_z):return Matrix.Translation(Vector(loc)) @ Matrix.Rotation(rot_z,4,'Z')
ROOT_A=mat((-32.5,0,0),math.pi)
ROOT_B=mat((32.5,0,-9),0)

output={o for name in LEAVES for o in bpy.data.collections[name].objects if o.type=='MESH'}
assert len(output)==382
membership={o.name:bpy.data.collections[name].name for name in LEAVES for o in bpy.data.collections[name].objects if o in output}
before={o.name:{'world':[list(r) for r in o.matrix_world],'collection':membership[o.name]} for o in output}
(ROOT/'qa').mkdir(parents=True,exist_ok=True);(ROOT/'renders').mkdir(parents=True,exist_ok=True)
(ROOT/'qa'/'before_layout.json').write_text(json.dumps(before,ensure_ascii=False,indent=2))

bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'env_tower_stairwell_dual_art_source_v021.blend'),compress=True)
for c in bpy.data.collections:
    if c.name=='楼梯区_组件化美术管理_v020':c.name='楼梯区_双楼梯间美术管理_v021'
    elif c.name=='02_游戏输出_组件包_v020':c.name='02_游戏输出_双楼梯组件包_v021'
main=bpy.data.collections['楼梯区_双楼梯间美术管理_v021']
out=bpy.data.collections['02_游戏输出_双楼梯组件包_v021']
roots=bpy.data.collections.new('00_楼梯间装配根_资产包');out.children.link(roots)

def root(name,asset_id,loc,rot,floors):
    o=bpy.data.objects.new(name,None);roots.objects.link(o);o.matrix_world=mat(loc,rot)
    o['asset_id']=asset_id;o['floor_range']=floors;o['component_type']='完整楼梯间装配根';o['source_version']='v021';o['scale_contract']='1,1,1';return o
ra=root('楼梯A_100至99层_装配根','ENV-TOWER-STAIRWELL-ROOFTOP-12M',(-32.5,0,0),math.pi,'100F-99F')
rb=root('楼梯B_99至98层_装配根','ENV-TOWER-STAIRWELL-GENERIC-12M',(32.5,0,-9),0,'99F-98F')

# The current v020 visual occupies the B contract transform. Preserve its root-local assembly,
# move the authored objects to A, and leave independent copied data at B.
pairs={}
for old in sorted(output,key=lambda o:o.name):
    old_name=old.name;old_world=old.matrix_world.copy();local=ROOT_B.inverted() @ old_world
    clone=old.copy();clone.data=old.data.copy();clone.animation_data_clear();bpy.data.collections[membership[old_name]].objects.link(clone)
    clone.name='楼梯B_99至98层__'+old_name;clone.parent=rb;clone.matrix_world=ROOT_B @ local
    old.name='楼梯A_100至99层__'+old_name;old.parent=ra;old.matrix_world=ROOT_A @ local
    for o,tag in [(old,'A_100_to_99'),(clone,'B_99_to_98')]:o['stairwell_instance']=tag;o['source_object_name']=old_name;o['asset_source_version']='v021'
    pairs[old_name]={'a':old.name,'b':clone.name,'collection':membership[old_name]}

# Duplicate the complete local lighting rig; cameras stay presentation-only and are not copied.
display=bpy.data.collections['90_展示与验收_沿用v016镜头']
lights=[o for o in bpy.context.scene.objects if o.type=='LIGHT']
for old in lights:
    local=ROOT_B.inverted() @ old.matrix_world.copy();clone=old.copy();clone.data=old.data.copy();display.objects.link(clone)
    clone.name='楼梯B_99至98层__'+old.name;clone.parent=rb;clone.matrix_world=ROOT_B @ local
    old.name='楼梯A_100至99层__'+old.name;old.parent=ra;old.matrix_world=ROOT_A @ local
    old['stairwell_instance']='A_100_to_99';clone['stairwell_instance']='B_99_to_98'

ra['paired_object_count']=len(pairs);rb['paired_object_count']=len(pairs)
(ROOT/'qa'/'pair_map.json').write_text(json.dumps(pairs,ensure_ascii=False,indent=2))
bpy.context.scene['asset_source_version']='v021';bpy.context.scene['runtime_imported']=False
bpy.context.scene['assembly_contract']='A(-32.5,0,0,Rz180); B(32.5,0,-9,Rz0)'
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
print('V021_DUAL_BUILD_OK',len(pairs),len(lights),ra.name,rb.name)
