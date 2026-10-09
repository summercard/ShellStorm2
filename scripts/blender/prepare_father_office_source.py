"""Freeze the source-only room contract before Blender production."""
import json, hashlib, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/art/environments/master_office_3d/source/env_father_office/v001'
OUT.mkdir(parents=True, exist_ok=True)
(OUT.parent / '.gdignore').touch()
src = ROOT / 'source/art/blender/master_office_layout/source/block_00_master_office_layout_v002.layout.json'
layout = json.loads(src.read_text(encoding='utf-8-sig'))
room = next(r for r in layout['rooms'] if r['room_id']=='master_office')
assert room['size_m']==[15,20] and room['doors']=={'east':2.5}
ref=Path('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-535082d8-35d9-489d-9963-2fa5270e829d.png')
shutil.copy2(ref, OUT/'reference.png')
defs=[
('floor_panel','地面金属砖','floor'),('floor_fractured','开裂地砖','floor'),
('wall_panel','装甲墙板','architecture'),('wall_fractured','坍塌墙体','architecture'),
('wall_door','入口门墙','architecture'),('sofa','长条软包沙发','facilities'),
('pillow','蓝色靠枕','decoration'),('throw','垂落织物','decoration'),
('rug','磨损蓝色地毯','floor'),('display_case','奖杯植物展示柜','facilities'),
('display_console','低矮展示终端','facilities'),('side_table','圆形边桌','facilities'),
('bookcase_fallen','倒塌书柜','facilities'),('plant_withered','枯萎盆栽','decoration'),
('plant_specimen','培养植物','decoration'),('trophy','螺旋奖杯','decoration'),
('rubble_large','混凝土大碎块','decoration'),('rubble_small','混凝土小碎块','decoration'),
('paper','散落纸张','decoration'),('book_stack','固定旧书堆','decoration'),
('wall_mural','墙面浮雕与灯带','decoration'),('metal_brace','断裂斜撑','architecture'),
('monitor_fallen','脱落显示屏','decoration'),('shelf_ledge','沙发后窄置物架','facilities')]
items=[]
for slug,cn,cat in defs:
    family={'floor_fractured':'floor_panel','wall_fractured':'wall_panel','rubble_large':'rubble','rubble_small':'rubble'}.get(slug,slug)
    items.append(dict(component_id='ENV-FATHER-OFFICE-'+slug.upper().replace('_','-'),slug=slug,name_zh=cn,category=cat,component_family=family,scope='room_type_local',serves_room_types=['FATHER_OFFICE'],variant_axis='damage_state' if 'fractured' in slug or slug in ['floor_panel','wall_panel'] else None,variant_value='fractured' if 'fractured' in slug else 'intact',variant_reason='参考图可见破损状态',front_axis='+Y',allowed_rotations_y_deg=[0,90,180,270],collision_owner='future_godot_wrapper',pickup=False))
contract=dict(asset_id='ENV-BATTLE-FATHER-OFFICE-SOURCE',block_id='master_office',floor_range=[98,98],design_scope='scene_art_source_only',room_id='master_office',runtime_room_id='floor_01_exit',room_type='FATHER_OFFICE',dimensions_m=[15,20,11.9],logical_wall_height_m=12,wall_thickness_m=.3,room_frame_origin_m=[-32.5,0,0],whitebox_source=str(src.relative_to(ROOT)),whitebox_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),reference_sha256=hashlib.sha256(ref.read_bytes()).hexdigest(),room_contract=room,door_clearance_local=dict(x=[5.8,7.7],y=[1.1,3.9],z=[0,3]),scene_design_docs=['docs/v0.1/05.1_关卡区块设计.md','docs/v0.1/05.2_关卡版图白盒与生成规范.md','src/world3d/Block00MasterOfficeLayout3D.gd'],asset_ledger='assets/registry/ledger_index.json::scenes::资产主表',component_plan_frozen=True,unique_component_count=len(items),components=items,notes=['仅制作源，不修改正式房间布局或玩法。','所有展示附件为固定不可拾取几何。','东墙与南墙保存在完整结构场景；参考剖视场景隐藏面向相机的两墙。','北墙破损为视觉形态，逻辑墙边界与12米碰撞契约仍保留。'])
(OUT/'component_plan.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2),encoding='utf-8')
print(OUT)
