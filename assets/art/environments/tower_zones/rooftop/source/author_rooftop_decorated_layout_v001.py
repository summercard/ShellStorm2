"""Build the 100F rooftop decorated layout from linked v002 component collections.

This file owns placement only. It must not create or copy component meshes.
Run with Blender 4.5 background mode.

—— 坐标契约（2026-09-21 修正，勿删）——
本项目 Blender Z-up：X=东、Y=北；Godot 平面约定 planar +z = 南、−z = 北
（见 src/world3d/Block00MasterOfficeLayout3D.gd 的坐标契约注释）。于是
「Blender 平面 → Godot 平面」是绕 X 轴 −90° 的**真旋转**（det=+1，非镜像）：
    world.x = bx
    world.z = −by + planar_z_shift      # 本布局 planar_z_shift = 0（运行时用 (x, z, −y)）
    rotation.y = rotation_z_deg         # 同号，不是 180 − rot
本脚本所有摆位参数一律按 **Godot 世界平面坐标**书写 —— x = +东、gz = +南、h = 高度 ——
与 TowerFloorStage3D.ROOFTOP_WORLD_RECT / BASE_99_100_ATRIUM_WORLD_RECT 同口径，
写入 Blender 时只做 `by = −gz` 一步换算（见 gz_to_by()）。
⛔ 不要去改 TowerFloorStage3D 的 (x, z, −y)：那是全项目统一契约，由本布局源适应它。

—— 2026-09-21 修正记录（业主实机报「坐标偏移、范围也错、没和 99 层基地正上方的墙壁一体」）——
1. 旧版把 gz 直接当 by 写（少了 by = −gz）⇒ 整份布局在 Godot 里南北镜像：
   地砖落在 z∈[−42.5, 32.5]、女儿墙 z∈[−44.75, 34.75]，而天台壳体是 z∈[−35, 45]，
   整体**偏北 10m**：北侧溢出边界、南侧缺 10m。
2. 旧版把「房屋」做成 20m×20m（4×4 网格）。它不是独立小屋，而是
   Base100UpperShell（30×30，世界 y=0..12）的**可视围护**：
     · assets/art/props/dungeon_3d/prp_rooftop_room_*_5x12.tscn 的
       metadata/collision_owner = "Base100UpperShell3D"，
       并注明「顶面落在上层楼板（24m 封顶）下方 0.10m」；
     · prp_rooftop_roof_full_5m.tscn 明写「只用在 6×6 网格的 4×4 内圈 16 格」，
       封顶碰撞 = Base100UpperShell3D.RoofCollision（30×0.30×30 @ 本地 y=24.15）。
   ⇒ 房屋必须是 **6×6 = 30×30**、同心于世界 (0, 5)，东墙门段对齐
   Base100UpperShell3D.EAST_DOOR_CENTER_Z（本地 −7.5 ⇒ 世界 z = −2.5）。
3. 周边装饰（空调 / 花圃 / 藤蔓 / 水管）随之外扩到新外墙皮，数量按 30m 边长重排
   （水管直段 2.5m 间距：每边 8 → 12 段）。
4. 房屋围护的 24 墙 + 36 封顶**改为参照层**（group = shell_reference）：结构本体
   env_base100_upper_shell_30x30_h12 在 2026-09-20 已自带这 60 件，重放会逐面 z-fighting。
   Blender 源里保留（渲染/校核用），运行时重放组不含它。修正后重放实例 113 → 99。

—— 2026-09-21 二次修正（业主实机报「花圃花盆会悬空 / 藤蔓要更高更错落 / 挡门 / 加栏杆挂藤」）——
5. **竖向基准错位（悬空根因）**：运行时天台承重面是 y=0（TowerFloorStage3D._floor_visual_origin_y
   把地砖可视顶面对齐到 Y=0），而本布局把落地装饰写在 h=0.3（= 自持地砖顶面），偏偏地砖组
   rooftop_base **不在** ROOFTOP_LAYOUT_REPLAY_GROUPS 里 ⇒ 运行时花草整块砖厚悬空 0.30m、
   藤蔓悬空 0.35m。现统一 GROUND_H = 0 落地；自持地砖改 TILE_H = −0.30，让砖顶面落回 0.0。
6. 东侧挡门件北移：东墙藤蔓 gz −5.0 → −8.5、大盆栽 gz −4.0 → −6.2；另把正插在门洞正中的
   东墙立管 gz −2.0 → +5.5（连带固定支架）。基地东门净宽 2.2m ⇒ 门洞 gz ∈ [−3.6, −1.4]。
7. 藤蔓加高错落：11 个基座落地 + 5 个上层藤蔓叠高（2.0/2.4/2.6/3.2/3.6）⇒ 顶高 5.80~7.40m。
8. 新增「女儿墙挂藤」(parapet_ivy) 8 件，贴天台外圈女儿墙中心线（业主提供的新组件）。

—— 2026-09-21 三次修正（业主实机报「水管要接到地板 / 空调机要 90° 旋转让风扇朝外」）——
9. **新增实例朝向分量 rotation_x_deg（绕自身 X 轴的「倾倒」）**。此前 add() 只会绕 Z 轴转
   （平面朝向），而墙挂空调必须把「立式」组件倾倒 90° 才谈得上「挂」：
   组件 `hvac_small` 的顶面自带出风风扇（build_rooftop.py: `fan(...,h+.025,...)`）、前面
   （局部 −Y）自带进风格栅 —— 落地摆放时风扇朝上是对的，一挂到墙上风扇就朝天。
   故 JSON 记录增加 `rotation_x_deg`，Blender 写 `rotation_euler = (tip, 0, angle_z)`，
   运行时写 `instance.rotation.x`。⚠️ 两个引擎的欧拉序不同（Blender 默认 XYZ、Godot 默认
   YXZ），**只有 rz 分量为 0 时** Blender 的 `Rz@Rx` 与 Godot 的 `Ry@Rx` 才同序、角度才可逐值
   搬运；本布局遵守该约束（tip 只与 angle 组合，从不同时用 ry+rz）。
10. **立管落地**：`pipe_riser` 件高 4.945m、原点在底、顶端是朝 +X 的鹅颈出水口。旧版
   放在 h=5.8（5.80~10.75，顶端正好接 10.65 的环管）⇒ **管底悬在半空 5.8m**，业主实机报
   「水管要接下来接到地板」。现每处摆两段、**两段的 h 都是 4.945**：下段
   `rotation_x_deg=180` 倒装（几何绕原点翻到下方 ⇒ 包络 0~4.945m，原点即上端；鹅颈转到
   贴地 0.095m，读作立管底部的泄水口）、上段正装（包络 4.945~9.89m，鹅颈仍在顶 9.795m），
   合成一根 **0~9.89m 的连续落水管**；与 10.65 环管之间残留 0.76m，由环管本体与支架轨
   遮住（业主原话「上面基本看不到」）。连同支架补一段低位（1.5m）与原有 7.0m 位，
   覆盖 1.56~10.64m。
11. 立管与支架按各自墙面朝向给 yaw（旧版立管一律 angle=0，东西墙的鹅颈会朝墙里）。6 个
    墙挂件（4 空调 + 2 通风口）后背统一埋进墙外皮内 0.05m，不再悬空：旧版通风口后背离墙
    0.63m（`gz_shell_south + 1.28` 比半进深 0.5825 多出 0.7）。

—— 2026-09-21 四次修正（业主实机报「花盆和花圃没有阻挡」）——
12. **按件碰撞策略**：此前本布局逐件写 `collision_policy = "visual_only"`，运行时
   （TowerFloorStage3D）对每一件无条件调 `_disable_rooftop_visual_collision()` ⇒ 花箱 /
   盆栽虽是实体，玩家却能直接穿过去。现把 `collision_policy` 升级为**逐件可配**：
     · `visual_only`（默认，460 件）：维持原状 —— 组件自带碰撞一律禁用；
     · `blocking`（绿化 20 件：flowerbox 8 + plant_large 6 + plant_small 6）：运行时**先**禁用
       组件自带碰撞，再按**实测可视包络**（TowerGeometry3D.resolve_visual_bounds）生成**一个**
       BoxShape3D 代理（StaticBody3D，collision_layer=1 与家具/墙体同层，mask=0，
       PROCESS_MODE_ALWAYS 以免疫父节点流送禁用），玩家不可穿过。
   ⚠️ 代理尺寸**不写死**：一律由组件实测包络推出 —— 美术改件后不会与碰撞脱节。选点口径为
   「视觉包络」而非「盆体」，因为盆栽的枝叶同样是不可穿行的实体。
   ⚠️ 本项目 `collision_policy` 词表：`component_default`（房间装配默认）/ `visual_only` /
   `blocking`（本布局新增）；覆盖默认值必须在此登记原因（见本项）。

—— 2026-09-21 五次修正（业主实机报「花盆和花圃靠墙太远了，要挨着墙放，不然还有个空虚」）——
13. **绿化环改为背贴外皮**：旧版把整圈绿化压在「离墙中心线 2.15m」的单一环线上，而三件
   绿化陈设的半进深只有 0.55~0.87m ⇒ 每件背后空出 1.14~1.45m 可见地砖带（对比同墙空调
   是贴墙的，视觉上就是「悬空一截」）。现按**每件自身半进深**重算贴墙坐标
   （件心离墙中心线 = SHELL_WALL_T/2 − WALL_MOUNT_EMBED + half_depth，背面埋进外皮 0.05m）：
   南/北/东/西四边各自成对，背面一条线齐平、正面因进深不同自然错落。
   同时把朝向补齐：三件 front_direction 均为 −Y，yaw 取 0 / π / +π/2 / −π/2 分别朝
   南 / 北 / 东 / 西；旧版西侧花圃写成 +π/2（正面朝墙里，与同墙藤蔓的 −π/2 矛盾），已修。
   ⚠️ 贴墙后花箱与同墙藤蔓基座在进深上重叠 ≤0.53m（藤蔓是叶幕、花箱是实体）—— 读作
   「花坛落在爬藤前」，不做避让；若日后要分离，把藤蔓基座沿墙平移即可。

> 天台壳体（地砖 / 女儿墙 / 外立面 / 结构碰撞）始终由 TowerFloorStage3D 程序化拥有；
> 本布局只提供房屋围护与装饰。装饰默认 `visual_only`（不带碰撞），
> **例外**：绿化三件（花箱 / 大盆栽 / 小盆栽）登记为 `blocking`，由运行时按实测包络生成
> 碰撞代理 —— 业主 2026-09-21「花盆和花圃没有阻挡」。
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[6]
ROOFTOP = PROJECT / "assets/art/environments/tower_zones/rooftop"
LIBRARY = ROOFTOP / "source/reference_components/v002/天台区块_参考组件库_v002.blend"
OUT_DIR = ROOFTOP / "source/layouts/100f_decorated_v001"
OUT_BLEND = OUT_DIR / "rooftop_100f_decorated_layout_v001.blend"
OUT_MANIFEST = OUT_DIR / "rooftop_100f_decorated_layout_v001.json"

OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── 楼层常量（Godot 世界平面口径，与 TowerFloorStage3D 逐个对齐） ──
GRID = 5.0
ROOFTOP_RECT = (-50.0, -35.0, 90.0, 80.0)   # ROOFTOP_WORLD_RECT
ATRIUM_RECT = (-15.0, -10.0, 30.0, 30.0)    # BASE_99_100_ATRIUM_WORLD_RECT
WEST_STAIR_RECT = (-45.0, 0.0, 15.0, 30.0)  # _stair_hole_world_rect("west")
PARAPET_INSET = 0.25                        # 女儿墙厚 0.50 ⇒ 中心线内缩半厚

# ── Base100UpperShell 对齐契约（结构真源 src/world3d/Base100UpperShell3D.gd） ──
SHELL_CENTER = (0.0, 5.0)   # 30×30 建筑体在世界平面的中心
SHELL_HALF = 15.0           # 墙中心线到中心 = 15.0
SHELL_WALL_T = 0.30         # 墙厚
SHELL_WALL_H = 0.0          # 墙件底面 y（room_*_5x12 原点=底面中心，高 11.90）
SHELL_ROOF_H = 12.0         # 封顶楼板底面 y（roof_* 厚 0.30 ⇒ 12.00..12.30）
SHELL_DOOR_GZ = -2.5        # EAST_DOOR_CENTER_Z(本地 −7.5) + 中心 z 5.0
SHELL_DOOR_INDEX = 1        # 东墙第 2 段的 gz = −10 + 2.5 + 5×1 = −2.5
WINDOW_INDEXES = {2, 4}     # 沿边开窗节奏（段下标，从最小坐标端起算）

# ── 竖向基准（2026-09-21 修正，勿删）──
# 运行时天台的**承重面（可行走地面）= y = 0**：TowerFloorStage3D._floor_visual_origin_y()
# 把地砖可视顶面对齐到 Y=0，verify_rooftop_railing.gd 亦以 FLOOR_Y = 0.0 为地板基准。
# 本布局的 h 会被运行时**直接当成 y** 用（TowerFloorStage3D 重放时 Vector3(x, h, -by)），
# 于是：
#   · 一切**落地件**（花箱 / 盆栽 / 藤蔓基座 / 女儿墙 / 房屋墙 / 立管）一律 h = GROUND_H；
#   · 本布局自带的参照地砖（group=rooftop_base，**不进运行时重放**）原点是底面、厚 0.30，
#     必须写 h = TILE_H = −0.30，才能让「砖的可视顶面」落回 0.0 —— 否则 Blender 校核图里
#     地砖比运行时高一整块砖厚、落地装饰看着像陷进砖里。
# ⛔ 旧版把落地装饰写成 h = 0.3（那是自持地砖的顶面），而地砖组根本不在重放列 ⇒
#    运行时花草整块砖厚**悬空 0.30m**、藤蔓悬空 0.35m —— 业主实机报的「花圃花盆会悬空」。
GROUND_H = 0.0
FLOOR_TILE_THICKNESS = 0.3
TILE_H = GROUND_H - FLOOR_TILE_THICKNESS   # −0.30

# 99-100 基地东门（Base100UpperShell3D 东墙）净宽 2.2m、门心世界 gz = SHELL_DOOR_GZ = −2.5
# ⇒ 门洞 gz ∈ [−3.6, −1.4]。东侧一切落地件必须让开这条带。
# 2026-09-21 业主报「99-100 基地出口的藤蔓和花盆挡住门了」，相关件全部往北（−gz）挪。
EAST_DOOR_CLEAR_HALF = 1.1          # DOOR_CLEAR_WIDTH / 2
EAST_DOOR_BLOCK_GZ = (SHELL_DOOR_GZ - EAST_DOOR_CLEAR_HALF,
                      SHELL_DOOR_GZ + EAST_DOOR_CLEAR_HALF)   # (−3.6, −1.4)

# ── 逐件碰撞策略（2026-09-21 四次修正，勿删）──
# 业主实机报「花盆和花圃没有阻挡」：旧版逐件写 visual_only，运行时对每一件无条件禁用
# 组件自带碰撞 ⇒ 花箱 / 盆栽是实体却可穿过。现策略逐件可配：
#   VISUAL_ONLY —— 运行时禁用组件自带碰撞（默认，460 件）；
#   BLOCKING    —— 运行时按**实测可视包络**生成一个 BoxShape3D 代理（layer=1）挡玩家。
# ⛔ 运行时侧的真源是 src/world3d/TowerFloorStage3D.gd 的 collision_policy 分支；
#    两侧词表必须一致，改词表要同时改这里、运行时与 validator。
VISUAL_ONLY = "visual_only"
BLOCKING = "blocking"
# 登记为 blocking 的组件 slug（业主诉求：花盆 / 花圃）。其余一律 visual_only。
# ⛔ 只放「实体、玩家不该穿过」的落地陈设；藤蔓（贴墙枝叶）、水管（悬空/贴墙）不在此列。
BLOCKING_SLUGS = ("flowerbox", "plant_large", "plant_small")

# ── 墙挂件：「立式」组件的倾倒与贴墙（2026-09-21 三次修正，勿删）──
# 组件在参考组件库里都是**落地立式**做的（原点在底面中心、前面 = 局部 −Y）。
# 挂到墙上要两步：① 绕自身 **X 轴**倾倒 90°（tip），把顶面出风风扇转成朝外；
# ② 绕 Z 轴给 yaw（angle_z），把「局部 −Y = 前面」对到该面墙的外法线。
# Blender 里写作 rotation_euler = (tip, 0, angle_z)（默认 XYZ 序 ⇒ R = Rz @ Rx），
# Godot 里写作 rotation = (tip, angle_z, 0)（默认 YXZ 序 ⇒ R = Ry @ Rx）：**同序**，可逐值搬运。
# ⛔ 同时给 ry 与 rz 会打破这个同序关系（Rx 与 Rz 的先后会反过来），本布局不使用。
HVAC_SMALL_HALF_DEPTH = 1.1825      # catalog bounds_size[1] / 2 ⇒ 倾倒后变成竖向半高
HVAC_VENT_HALF_DEPTH = 0.5825       # 同上（通风口不倾倒，这是它离墙的半进深）
WALL_MOUNT_EMBED = 0.05             # 机背埋进墙外皮内 0.05m，避免与墙外皮共面 z-fighting
WALL_HALF_THICKNESS = SHELL_WALL_T / 2.0   # 0.15 ⇒ 墙中心线到外皮

# ── 立管（落水管）：件高 4.945m、原点在底、顶端鹅颈朝 +X ──
# 旧版单段放在 h=5.8 ⇒ 管底悬空 5.8m。现每处两段：下段倒装（rotation_x_deg=180，鹅颈
# 转到贴地 0.095m 读作底部泄水口）、上段正装 ⇒ 0~9.89m 连续落水管。倒装是 180° 真旋转
# （det=+1），不是镜像。
PIPE_RISER_COMPONENT_H = 4.945      # catalog bounds_size[2]
PIPE_RISER_LOWER_TIP = math.pi      # 180°，鹅颈转到贴地
PIPE_BRACKET_LOW_H = 1.5            # 低位支架（轨道 1.56~5.20）
PIPE_BRACKET_HIGH_H = 7.0           # 高位支架（轨道 7.06~10.64）

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = "100F天台_组件装饰布局_v001"
scene.unit_settings.system = "METRIC"
scene.unit_settings.length_unit = "METERS"

# Collections are linked from the frozen component source. No mesh is appended.
component_names = {
    "floor_full": "完整地砖_资产包",
    "parapet": "女儿墙直段_资产包",
    "parapet_outer": "女儿墙外角_资产包",
    "room_wall": "房间标准墙_资产包",
    "room_window": "房间窗墙_资产包",
    "room_doorwall": "房间门洞墙_资产包",
    "roof_full": "房顶完整板_资产包",
    "roof_edge": "房顶边缘板_资产包",
    "roof_corner": "房顶角板_资产包",
    "hvac_small": "小型空调机组_资产包",
    "hvac_large": "大型空调机组_资产包",
    "hvac_vent": "小通风口_资产包",
    "flowerbox": "长条花箱_资产包",
    "plant_large": "大盆栽_资产包",
    "plant_small": "小盆栽_资产包",
    "ivy": "墙面攀爬藤蔓_资产包",
    "parapet_ivy": "女儿墙挂藤_资产包",
    "pipe_straight": "直管段_资产包",
    "pipe_elbow": "转角弯管_资产包",
    "pipe_tee": "三通管_资产包",
    "pipe_riser": "立管下水管_资产包",
    "pipe_bracket": "管道支架_资产包",
}
with bpy.data.libraries.load(str(LIBRARY), link=True) as (data_from, data_to):
    data_to.collections = list(component_names.values())

missing = [name for name in component_names.values() if bpy.data.collections.get(name) is None]
if missing:
    raise RuntimeError("Missing linked component collections: " + ", ".join(missing))

root = bpy.data.collections.new("100F天台_装饰布局_v001")
scene.collection.children.link(root)
instances = bpy.data.collections.new("ROOFTOP_LAYOUT_INSTANCES")
root.children.link(instances)
helpers = bpy.data.collections.new("90_展示与验收_相机灯光")
root.children.link(helpers)

placements = []
instance_seq = 0


def gz_to_by(gz):
    """Godot 平面 z（+南）→ Blender Y（+北）。"""
    return round(-float(gz), 4)


def in_rect(x, gz, rect):
    return rect[0] <= x < rect[0] + rect[2] and rect[1] <= gz < rect[1] + rect[3]


def add(slug, x, gz, h=GROUND_H, angle=0.0, group="decor", note="", connection=None,
        tip=0.0, collision=VISUAL_ONLY):
    """摆一个组件实例。x / gz 为 **Godot 世界平面坐标**（+x 东、+z 南），h 为高度。

    angle = 绕 Z 轴的平面朝向（rad）；tip = 绕自身 X 轴的倾倒（rad，0 或 π/2 或 π）。
    ⛔ tip 与 angle 同时给是允许的（见模块头「欧拉序同序」说明），但从不同时用 ry+rz。

    collision = 逐件碰撞策略，见模块头「四次修正」第 12 条：
      · VISUAL_ONLY（默认）—— 运行时禁用组件自带碰撞；
      · BLOCKING —— 运行时按实测可视包络生成碰撞代理，玩家不可穿过。
    ⛔ 只允许上述两个值；拼错必须当场炸掉，否则会静默退化成「可穿过的实体 / 看不见的障碍」。
    """
    if collision not in (VISUAL_ONLY, BLOCKING):
        raise ValueError(f"unknown collision policy {collision!r} for slug {slug!r}")
    global instance_seq
    collection_name = component_names[slug]
    by = gz_to_by(gz)
    empty = bpy.data.objects.new(f"INST_{instance_seq:03}_{slug}", None)
    empty.instance_type = "COLLECTION"
    empty.instance_collection = bpy.data.collections[collection_name]
    empty.location = (float(x), by, float(h))
    empty.rotation_euler = (float(tip), 0.0, float(angle))
    empty.scale = (1.0, 1.0, 1.0)
    empty["component_slug"] = slug
    empty["component_collection"] = collection_name
    empty["layout_group"] = group
    empty["collision_policy"] = collision
    empty["source_blend"] = str(LIBRARY.relative_to(PROJECT)).replace("\\", "/")
    if note:
        empty["design_note"] = note
    if connection:
        empty["connection_id"] = connection
    instances.objects.link(empty)
    record = {
        "instance_id": empty.name,
        "component_slug": slug,
        "component_collection": collection_name,
        "group": group,
        "position_m": [round(float(x), 4), by, round(float(h), 4)],
        "rotation_x_deg": round(math.degrees(float(tip)), 4),
        "rotation_y_deg": round(math.degrees(angle), 4),
        "scale": [1.0, 1.0, 1.0],
        "enabled": True,
        "collision_policy": collision,
    }
    if note:
        record["design_note"] = note
    if connection:
        record["connection_id"] = connection
    placements.append(record)
    instance_seq += 1
    return empty


def wall_slug(index, door_index=None):
    if door_index is not None and index == door_index:
        return "room_doorwall"
    if index in WINDOW_INDEXES:
        return "room_window"
    return "room_wall"


# ── 1. 地砖：18×16 网格，扣 36 格中庭（= 30×30 建筑体足迹）与 18 格西侧楼梯口 ──
for row in range(16):
    gz = -32.5 + row * GRID
    for col in range(18):
        x = -47.5 + col * GRID
        if in_rect(x, gz, ATRIUM_RECT) or in_rect(x, gz, WEST_STAIR_RECT):
            continue
        add(
            "floor_full",
            x,
            gz,
            h=TILE_H,
            group="rooftop_base",
            note="100F 18x16地砖；已扣36格中庭与18格西侧楼梯口",
        )

# ── 2. 女儿墙 0.80m：贴运行时边界（中心线内缩半厚 0.25m），西侧留楼梯净空 ──
rect_x, rect_z, rect_w, rect_d = ROOFTOP_RECT
gz_south = rect_z + rect_d - PARAPET_INSET   # 44.75
gz_north = rect_z + PARAPET_INSET            # -34.75
x_east = rect_x + rect_w - PARAPET_INSET     # 39.75
x_west = rect_x + PARAPET_INSET              # -49.75
for col in range(17):
    x = -45.0 + col * GRID
    add("parapet", x, gz_south, h=GROUND_H, angle=0.0, group="rooftop_edge", note="南侧女儿墙，贴运行时边界")
    add("parapet", x, gz_north, h=GROUND_H, angle=math.pi, group="rooftop_edge", note="北侧女儿墙，贴运行时边界")
for row in range(15):
    gz = -30.0 + row * GRID
    add("parapet", x_east, gz, h=GROUND_H, angle=math.pi / 2, group="rooftop_edge", note="东侧女儿墙，贴运行时边界")
    add("parapet", x_west, gz, h=GROUND_H, angle=-math.pi / 2, group="rooftop_edge", note="西侧女儿墙，贴运行时边界")
for x, gz, angle in [
    (rect_x + 1.25, rect_z + rect_d - 1.25, 0.0),
    (rect_x + rect_w - 1.25, rect_z + rect_d - 1.25, math.pi / 2),
    (rect_x + rect_w - 1.25, rect_z + 1.25, math.pi),
    (rect_x + 1.25, rect_z + 1.25, -math.pi / 2),
]:
    add("parapet_outer", x, gz, h=GROUND_H, angle=angle, group="rooftop_edge", note="天台外围转角")

# ── 3. 房屋围护：6×6 = 30×30，同心于 Base100UpperShell，东墙门段对齐结构门洞 ──
cx, cz = SHELL_CENTER
gz_shell_south = cz + SHELL_HALF   # 20
gz_shell_north = cz - SHELL_HALF   # -10
for i in range(6):
    x = cx - SHELL_HALF + GRID * (i + 0.5)          # -12.5 … 12.5
    gz_side = gz_shell_north + GRID * (i + 0.5)     # -7.5 … 17.5
    slug = wall_slug(i)
    add(slug, x, gz_shell_south, h=SHELL_WALL_H, angle=0.0, group="shell_reference", note="房屋南立面（参照层：运行时由Base100UpperShell3D独占，不重放）")
    add(wall_slug(i), cx - (x - cx), gz_shell_north, h=SHELL_WALL_H, angle=math.pi, group="shell_reference", note="房屋北立面（参照层）")
    for side in (-1, 1):
        add(
            wall_slug(i, SHELL_DOOR_INDEX if side > 0 else None),
            cx + side * SHELL_HALF,
            gz_side,
            h=SHELL_WALL_H,
            angle=side * math.pi / 2,
            group="shell_reference",
            note="房屋东立面（参照层；门段对齐 Base100UpperShell3D 门洞）" if side > 0 else "房屋西立面（参照层）",
        )

# ── 4. 房屋封顶 6×6 = 36 格 @ 楼板底面 y=12（roof_* 原点=底面中心，厚 0.30） ──
for row in range(6):
    for col in range(6):
        x = cx - SHELL_HALF + GRID * (col + 0.5)
        gz = cz - SHELL_HALF + GRID * (row + 0.5)
        if col in (0, 5) and row in (0, 5):
            slug = "roof_corner"
            angle = {(0, 5): 0.0, (5, 5): math.pi / 2, (5, 0): math.pi, (0, 0): -math.pi / 2}[(col, row)]
        elif col in (0, 5) or row in (0, 5):
            slug = "roof_edge"
            angle = 0.0 if row == 5 else math.pi if row == 0 else math.pi / 2 if col == 5 else -math.pi / 2
        else:
            slug = "roof_full"
            angle = 0.0
        add(slug, x, gz, h=SHELL_ROOF_H, angle=angle, group="shell_reference", note="房屋30m封顶（参照层，6×6网格）")

# ── 5. 墙挂空调：贴建筑外皮，避开门洞与楼梯口 ──
# ⚠️ 组件是「立式」做的：顶面出风风扇 + 前面（局部 −Y）进风格栅。挂到墙上必须绕自身 X 轴
# 倾倒 90°（tip=π/2），顶面风扇才朝外 —— 业主 2026-09-21 实机报「空调机在墙上的状态需要
# 90 度旋转，让风扇朝外」。倾倒后：原「高度」变成离墙进深、原「进深」变成竖向高度，
# 故实例原点 = 机背（贴墙外皮内 0.05m），h = 原来的底高 + 竖向半高。
x_shell_east = cx + SHELL_HALF           # 15.0（墙中心线）
x_shell_west = cx - SHELL_HALF           # -15.0
gz_shell_south_face = gz_shell_south + WALL_HALF_THICKNESS   # 20.15（南墙外皮）
gz_shell_north_face = gz_shell_north - WALL_HALF_THICKNESS   # -10.15（北墙外皮）
x_shell_east_face = x_shell_east + WALL_HALF_THICKNESS       # 15.15（东墙外皮）
x_shell_west_face = x_shell_west - WALL_HALF_THICKNESS       # -15.15（西墙外皮）
HVAC_SMALL_TIP = math.pi / 2             # 绕自身 X 轴倾倒 90° ⇒ 顶部风扇朝外
add("hvac_small", -5.0, gz_shell_south_face - WALL_MOUNT_EMBED,
    h=5.2 + HVAC_SMALL_HALF_DEPTH, tip=HVAC_SMALL_TIP, group="hvac_wall",
    note="南墙挂式空调（绕X轴倾倒90°，顶面风扇朝外；机背贴南墙外皮）")
add("hvac_small", 0.5, gz_shell_south_face - WALL_MOUNT_EMBED,
    h=5.2 + HVAC_SMALL_HALF_DEPTH, tip=HVAC_SMALL_TIP, group="hvac_wall",
    note="南墙挂式空调（绕X轴倾倒90°，顶面风扇朝外；机背贴南墙外皮）")
add("hvac_small", x_shell_east_face - WALL_MOUNT_EMBED, 7.0,
    h=4.9 + HVAC_SMALL_HALF_DEPTH, angle=math.pi / 2, tip=HVAC_SMALL_TIP, group="hvac_wall",
    note="东墙挂式空调（绕X轴倾倒90°，顶面风扇朝东）")
add("hvac_small", x_shell_west_face + WALL_MOUNT_EMBED, 4.0,
    h=4.9 + HVAC_SMALL_HALF_DEPTH, angle=-math.pi / 2, tip=HVAC_SMALL_TIP, group="hvac_wall",
    note="西墙挂式空调（绕X轴倾倒90°，顶面风扇朝西）")
# 通风口不倾倒（它没有顶面风扇，只有前面格栅），但要贴墙：旧版 `+1.28` 比半进深 0.5825
# 多出 0.7m ⇒ 后背离墙皮 0.63m，同一类「在墙上的状态」缺陷，一并修正。
add("hvac_vent", -7.4, gz_shell_south_face - WALL_MOUNT_EMBED + HVAC_VENT_HALF_DEPTH,
    h=8.0, group="hvac_wall", note="南墙辅助通风口（机背贴南墙外皮）")
add("hvac_vent", x_shell_east_face - WALL_MOUNT_EMBED + HVAC_VENT_HALF_DEPTH, 12.0,
    h=7.8, angle=math.pi / 2, group="hvac_wall", note="东墙辅助通风口（机背贴东墙外皮）")

# ── 6. 花圃与植物：背贴建筑外皮一圈，不挡门洞与楼梯口 ──
# ⚠️ 花箱 / 大盆栽 / 小盆栽三件登记为 **BLOCKING**（业主 2026-09-21「花盆和花圃没有阻挡」）
# —— 都是落地陈设，玩家不该穿过去。其余装饰维持 VISUAL_ONLY。
# ⚠️ 贴墙基准（业主 2026-09-21「花盆和花圃靠墙太远了，要挨着墙放，不然还有个空虚」）：
# 旧版整圈绿化压在同一条「离墙中心线 2.15m」的环线上（离外皮 2.00m），而三件的半进深
# 只有 0.55~0.87m ⇒ 每件背后空出 1.14~1.45m 的可见地砖带。现改为**逐件按自身半进深贴
# 外皮**：件心到墙中心线 = SHELL_WALL_T/2 − WALL_MOUNT_EMBED + half_depth，即「背面埋进
# 外皮内 0.05m」（与墙挂空调同口径，避免与墙皮共面 z-fighting）。三件进深不等 ⇒ 背面
# 齐平、正面自然错落 —— 花坛贴墙本该如此。
# ⚠️ 朝向：三件 catalog 的 front_direction = −Y（正面朝局部 −Y）。绕 Z 转 yaw 后 local −Y
# 指向：0 ⇒ 南、π ⇒ 北、+π/2 ⇒ 东、−π/2 ⇒ 西。旧版西侧花圃写成 +π/2（正面朝墙里），
# 与同墙藤蔓的 −π/2 矛盾，本次一并修正。
FLOWERBOX_HALF_DEPTH = 0.5925        # 长条花箱 catalog bounds_size[1] 1.185 / 2
PLANT_LARGE_HALF_DEPTH = 0.8727377   # 大盆栽 1.745475 / 2
PLANT_SMALL_HALF_DEPTH = 0.5473868   # 小盆栽 1.094774 / 2
YAW_SOUTH, YAW_NORTH = 0.0, math.pi
YAW_EAST, YAW_WEST = math.pi / 2, -math.pi / 2


def wall_flush_pairs(half_depth):
    """贴墙坐标组 (南 gz, 北 gz, 东 x, 西 x)：件心离墙中心线 = 半厚 − 埋入 + 半进深。"""
    offset = WALL_HALF_THICKNESS - WALL_MOUNT_EMBED + half_depth
    return (gz_shell_south + offset, gz_shell_north - offset,
            x_shell_east + offset, x_shell_west - offset)


box_south, box_north, box_east, box_west = wall_flush_pairs(FLOWERBOX_HALF_DEPTH)
for x in (-9.0, -1.0, 7.0):
    add("flowerbox", x, box_south, h=GROUND_H, angle=YAW_SOUTH, group="greenery",
        collision=BLOCKING, note="南侧连续花圃（阻挡；背贴南墙外皮）")
for x in (-9.0, -1.0, 7.0):
    add("flowerbox", x, box_north, h=GROUND_H, angle=YAW_NORTH, group="greenery",
        collision=BLOCKING, note="北侧连续花圃（阻挡；背贴北墙外皮）")
add("flowerbox", box_west, -2.0, h=GROUND_H, angle=YAW_WEST, group="greenery",
    collision=BLOCKING, note="西侧花圃（阻挡；背贴西墙外皮，正面朝西）")
add("flowerbox", box_east, 12.0, h=GROUND_H, angle=YAW_EAST, group="greenery",
    collision=BLOCKING, note="东侧花圃（阻挡；背贴东墙外皮）")

pl_south, pl_north, pl_east, pl_west = wall_flush_pairs(PLANT_LARGE_HALF_DEPTH)
for x in (-15.5, 4.7):
    add("plant_large", x, pl_south, h=GROUND_H, angle=YAW_SOUTH, group="greenery",
        collision=BLOCKING, note="南侧大盆栽（阻挡；背贴南墙外皮）")
    add("plant_large", x, pl_north, h=GROUND_H, angle=YAW_NORTH, group="greenery",
        collision=BLOCKING, note="北侧大盆栽（阻挡；背贴北墙外皮）")
add("plant_large", pl_east, -6.2, h=GROUND_H, angle=YAW_EAST, group="greenery",
    collision=BLOCKING, note="东侧大盆栽（阻挡；背贴东墙外皮；让开基地东门）")
add("plant_large", pl_west, 7.0, h=GROUND_H, angle=YAW_WEST, group="greenery",
    collision=BLOCKING, note="西侧大盆栽（阻挡；背贴西墙外皮）")

ps_south, ps_north, ps_east, ps_west = wall_flush_pairs(PLANT_SMALL_HALF_DEPTH)
for x in (-12.8, 1.4):
    add("plant_small", x, ps_south, h=GROUND_H, angle=YAW_SOUTH, group="greenery",
        collision=BLOCKING, note="南侧小盆栽（阻挡；背贴南墙外皮）")
    add("plant_small", x, ps_north, h=GROUND_H, angle=YAW_NORTH, group="greenery",
        collision=BLOCKING, note="北侧小盆栽（阻挡；背贴北墙外皮）")
add("plant_small", ps_east, 2.0, h=GROUND_H, angle=YAW_EAST, group="greenery",
    collision=BLOCKING, note="东侧小盆栽（阻挡；背贴东墙外皮）")
add("plant_small", ps_west, 0.0, h=GROUND_H, angle=YAW_WEST, group="greenery",
    collision=BLOCKING, note="西侧小盆栽（阻挡；背贴西墙外皮）")

# ── 7. 墙面藤蔓：纯枝叶，不复刻墙体几何 ──
# 藤蔓件 4.256×0.820×3.802m、原点在**底面**，运行时禁非单位缩放（重放时实例 scale
# 非 1 会直接 blockers++）⇒ 想「延展高一点」只能**叠一件**上去，不能 scale。
# 策略：每个基座恒 h=GROUND_H **落地**（底部不留缝），再在部分基座上叠一层上层藤蔓，
# 叠高值 2.0 / 2.4 / 2.6 / 3.2 / 3.6 五档错开 ⇒ 顶部落在 5.80~7.40m，形成高低错落
# （业主 2026-09-21：「藤蔓可以有的延展高一点。有的可以高一些，高低错落」）。
IVY_COMPONENT_H = 3.8022   # 藤蔓件自身高度（catalog bounds_max.z）
for x in (-11.0, -3.0, 5.0):
    add("ivy", x, gz_shell_south + 0.22, h=GROUND_H, group="ivy", note="南墙藤蔓基座（落地）")
for x in (-11.0, -3.0, 5.0):
    add("ivy", x, gz_shell_north - 0.22, h=GROUND_H, angle=math.pi, group="ivy", note="北墙藤蔓基座（落地）")
# 东墙原基座 gz=−5.0（叶面 gz∈[−7.13,−2.87]）与基地东门净空 gz∈[−3.6,−1.4] 相交 ⇒ 北移。
for gz in (-8.5, 3.0, 11.0):
    add("ivy", x_shell_east + 0.22, gz, h=GROUND_H, angle=math.pi / 2, group="ivy",
        note="东墙藤蔓基座（落地；原 gz=−5.0 已北移让开基地东门）")
for gz in (-6.0, 8.0):
    add("ivy", x_shell_west - 0.22, gz, h=GROUND_H, angle=-math.pi / 2, group="ivy", note="西墙藤蔓基座（落地）")
for upper_x, upper_gz, upper_angle, lift, side in [
    (x_shell_east + 0.22, 11.0, math.pi / 2, 3.6, "东"),
    (x_shell_west - 0.22, 8.0, -math.pi / 2, 2.4, "西"),
    (-11.0, gz_shell_south + 0.22, 0.0, 2.0, "南"),
    (5.0, gz_shell_south + 0.22, 0.0, 3.2, "南"),
    (-3.0, gz_shell_north - 0.22, math.pi, 2.6, "北"),
]:
    add("ivy", upper_x, upper_gz, h=GROUND_H + lift, angle=upper_angle, group="ivy",
        note="%s墙上层藤蔓：叠高 %.1fm ⇒ 顶高 %.2fm" % (side, lift, GROUND_H + lift + IVY_COMPONENT_H))

# ── 8. 闭环水管：每边 2.5m 一个插座（30m 边长 ⇒ 12 段）+ 四角弯管 ──
pipe_h = 10.65
pipe_south = gz_shell_south + 0.42   # 20.42
pipe_north = gz_shell_north - 0.42   # -10.42
pipe_east = x_shell_east + 0.42      # 15.42
pipe_west = x_shell_west - 0.42      # -15.42
PIPE_RUN = 12
PIPE_PITCH = 2.5
for i in range(PIPE_RUN):
    add("pipe_straight", -13.75 + i * PIPE_PITCH, pipe_south, h=pipe_h, group="pipe_loop", note="南墙连续水管", connection="PIPE_LOOP_SOUTH")
for i in range(PIPE_RUN):
    add("pipe_straight", pipe_east, -8.75 + i * PIPE_PITCH, h=pipe_h, angle=math.pi / 2, group="pipe_loop", note="东墙连续水管", connection="PIPE_LOOP_EAST")
for i in range(PIPE_RUN):
    add("pipe_straight", 13.75 - i * PIPE_PITCH, pipe_north, h=pipe_h, angle=math.pi, group="pipe_loop", note="北墙连续水管", connection="PIPE_LOOP_NORTH")
for i in range(PIPE_RUN):
    add("pipe_straight", pipe_west, 18.75 - i * PIPE_PITCH, h=pipe_h, angle=-math.pi / 2, group="pipe_loop", note="西墙连续水管", connection="PIPE_LOOP_WEST")
for x, gz, angle in [
    (x_shell_east + 0.15, gz_shell_north - 0.15, 0.0),
    (x_shell_east + 0.15, gz_shell_south + 0.15, math.pi / 2),
    (x_shell_west - 0.15, gz_shell_south + 0.15, math.pi),
    (x_shell_west - 0.15, gz_shell_north - 0.15, -math.pi / 2),
]:
    add("pipe_elbow", x, gz, h=pipe_h, angle=angle, group="pipe_loop", note="水管四角转接", connection="PIPE_LOOP_CORNER")
for x in (-7.5, 2.5):
    add("pipe_tee", x, pipe_south, h=pipe_h, group="pipe_loop", note="南墙花圃灌溉分支", connection="PIPE_LOOP_BRANCH")
# 立管（落水管）：每处两段 ⇒ 0~9.89m 连续，管底落到承重面 y=0。
# 下段**倒装**（tip=180°，原点在底 ⇒ 倒过来后原点变成顶）：包络落在 0~4.945m，
# 鹅颈从顶端转到贴地 0.095m，读作立管底部的泄水口；上段正装：包络 4.945~9.89m，
# 鹅颈在顶 9.795m，与 10.65m 环管之间余 0.76m（环管本体与支架轨遮住）。
# ⚠️ 两段的实例 h **都是 4.945**：倒装件把几何绕自身原点翻到下方，原点必须落在上端。
# 业主 2026-09-21：「水管可以接下来一些，接到地板」。
# yaw 按各自墙面给（旧版一律 0 ⇒ 东西墙的鹅颈朝墙里，与环管走向垂直）。
# (x, gz, yaw) —— 与同侧的 pipe_loop 走向一致，鹅颈才顺着环管。
RISE_RUNS = [
    (-7.5, pipe_south, 0.0, "南"),
    (2.5, pipe_south, 0.0, "南"),
    (pipe_east, 5.5, math.pi / 2, "东"),
    (pipe_west, 4.0, -math.pi / 2, "西"),
]
for x, gz, yaw, side in RISE_RUNS:
    add("pipe_riser", x, gz, h=PIPE_RISER_COMPONENT_H, angle=yaw, tip=PIPE_RISER_LOWER_TIP,
        group="pipe_risers", connection="PIPE_RISER",
        note="%s墙立管下段（倒装180°：包络 0~4.945m，鹅颈转到贴地泄水口，管底落承重面 y=0）" % side)
    add("pipe_riser", x, gz, h=PIPE_RISER_COMPONENT_H, angle=yaw,
        group="pipe_risers", connection="PIPE_RISER",
        note="%s墙立管上段（正装：包络 4.945~9.89m，顶端鹅颈朝环管走向）" % side)
    add("pipe_bracket", x, gz, h=PIPE_BRACKET_LOW_H, angle=yaw,
        group="pipe_risers", connection="PIPE_RISER",
        note="%s墙立管低位支架" % side)
    add("pipe_bracket", x, gz, h=PIPE_BRACKET_HIGH_H, angle=yaw,
        group="pipe_risers", connection="PIPE_RISER",
        note="%s墙立管高位支架" % side)

# ── 9. 女儿墙（栏杆）挂藤：业主 2026-09-21 要求「我有栏杆的藤蔓组件，适当加进来」──
# 女儿墙挂藤件 5.004×0.814×2.009m、原点在底面，与 5m 女儿墙直段同宽 ⇒ 直接落在女儿墙
# 中心线上：叶面两侧各外扩 0.157m，顶高出 0.80m 压顶 1.2m（垂下来）。
# 运行时女儿墙是一条**完整闭合圈**（TowerFloorStage3D 的 outer_doorway_wall_count 恒为 0，
# 注释明写「天台外墙已连成整圈」），故四边任一段都能贴；四角让给 parapet_outer 转角件
# （ROOFTOP_CORNER_ARM_M = 2.5），挂藤取段心、两端各留一段即可。
for x in (-25.0, -5.0, 15.0):
    add("parapet_ivy", x, gz_south, h=GROUND_H, angle=0.0, group="parapet_ivy",
        note="南侧女儿墙挂藤（贴栏杆中心线）")
for x in (-25.0, -5.0, 15.0):
    add("parapet_ivy", x, gz_north, h=GROUND_H, angle=0.0, group="parapet_ivy",
        note="北侧女儿墙挂藤（贴栏杆中心线）")
for parapet_x, parapet_gz in ((x_east, 10.0), (x_west, 10.0)):
    add("parapet_ivy", parapet_x, parapet_gz, h=GROUND_H, angle=math.pi / 2, group="parapet_ivy",
        note="东/西侧女儿墙挂藤（贴栏杆中心线）")

# Display setup. These objects are not part of the layout manifest.
def track(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

# 展示用相机/灯光按 Blender 平面坐标摆放：世界中心 Godot (0, 5) ⇒ Blender (0, -5)。
SCENE_CENTER = (SHELL_CENTER[0], gz_to_by(SHELL_CENTER[1]))
world = bpy.data.worlds.new("100F天台_展示世界")
world.use_nodes = True
world_nodes = world.node_tree.nodes
world_nodes.clear()
out_node = world_nodes.new("ShaderNodeOutputWorld")
bg_node = world_nodes.new("ShaderNodeBackground")
bg_node.inputs["Color"].default_value = (0.16, 0.21, 0.28, 1)
bg_node.inputs["Strength"].default_value = 0.55
world.node_tree.links.new(bg_node.outputs["Background"], out_node.inputs["Surface"])
scene.world = world
for name, loc, energy, size, color in [
    ("主柔光", (-35, 45, 75), 50000, 42, (1.0, 0.92, 0.80)),
    ("冷色补光", (45, -20, 45), 28000, 32, (0.72, 0.84, 1.0)),
]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    ob = bpy.data.objects.new(name, data)
    helpers.objects.link(ob)
    ob.location = loc
    track(ob, (SCENE_CENTER[0], SCENE_CENTER[1], 4))
cam_data = bpy.data.cameras.new("100F天台_装饰总览相机")
cam = bpy.data.objects.new("100F天台_装饰总览相机", cam_data)
helpers.objects.link(cam)
cam.location = (72, 92, 72)
track(cam, (SCENE_CENTER[0], SCENE_CENTER[1], 3))
cam_data.type = "ORTHO"
cam_data.ortho_scale = 112
scene.camera = cam
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1800
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 60
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 0.65

scene["asset_id"] = "ENV-ROOFTOP-100F-DECORATED-LAYOUT"
scene["layout_version"] = "v001"
scene["component_source_blend"] = str(LIBRARY.relative_to(PROJECT)).replace("\\", "/")
scene["room_owned_geometry"] = False
scene["instance_mode"] = "COLLECTION_INSTANCE"
# 混合策略：逐件字段为准（见 "collision_policy" 逐件记录），此处只留一句总述。
scene["collision_policy"] = "per_instance:visual_only(default)+blocking(greenery)"
scene["design_summary"] = "100F天台：30×30房屋围护（对齐Base100UpperShell）、墙挂空调、房屋周边花圃、墙面藤蔓、闭环水管"
scene["planar_contract"] = "world.x=bx; world.z=-by; rotation.y=rotation_z_deg"

slug_counts = {}
collision_counts = {VISUAL_ONLY: 0, BLOCKING: 0}
for record in placements:
    slug_counts[record["component_slug"]] = slug_counts.get(record["component_slug"], 0) + 1
    collision_counts[record["collision_policy"]] = collision_counts.get(record["collision_policy"], 0) + 1

# ⛔ 自检：BLOCKING 白名单与实际 blocking 实例必须**双向一致** ——
# 少了=漏挡（可穿过的实体），多了=越权（未登记原因就挡人）。任一侧不一致当场炸掉。
blocking_slugs_actual = sorted({r["component_slug"] for r in placements
                                if r["collision_policy"] == BLOCKING})
if blocking_slugs_actual != sorted(BLOCKING_SLUGS):
    raise AssertionError(
        "BLOCKING_SLUGS 与实际不符：declared=%s actual=%s"
        % (sorted(BLOCKING_SLUGS), blocking_slugs_actual)
    )

manifest = {
    "schema": "shellstrom2.rooftop.decorated_layout",
    "schema_version": 1,
    "layout_id": "ENV-ROOFTOP-100F-DECORATED-LAYOUT",
    "layout_version": "v001",
    "floor": "100F",
    "block_id": "rooftop",
    "source_blend": str(OUT_BLEND.relative_to(PROJECT)).replace("\\", "/"),
    "component_library": str(LIBRARY.relative_to(PROJECT)).replace("\\", "/"),
    "dimensions_m": [90.0, 80.0],
    "world_rect_m": [-50.0, -35.0, 90.0, 80.0],
    "coordinate_contract": {
        "up_axis": "+Z",
        "horizontal_axes": ["+X", "+Y"],
        "rotation_axis": "+Z",
        "units": "meters",
        "position_m_semantics": "Blender (bx, by, bz) with bx=+x, by=-gz, bz=height",
        "godot_planar_contract": "world.x = bx; world.z = -by + planar_z_shift (planar_z_shift = 0); rotation.y = rotation_z_deg",
        "world_rect_m_semantics": "Godot ROOFTOP_WORLD_RECT (x, z, w, d) —— 判据口径，不是 Blender 口径",
    },
    "base_shell_alignment": {
        "structure_owner": "Base100UpperShell3D",
        "structure_prefab": "res://assets/art/environments/base_facility_3d/runtime/env_base100_upper_shell_30x30_h12/env_base100_upper_shell_30x30_h12_root_top3d.tscn",
        "center_m": [0.0, 5.0],
        "footprint_m": [30.0, 30.0],
        "wall_center_offset_m": 15.0,
        "wall_height_m": 11.9,
        "roof_slab_bottom_y_m": 12.0,
        "door_gz_m": -2.5,
        "note": "房屋围护是这栋结构体的可视层：6×6 网格、同心、东墙门段与结构门洞同位。",
    },
    # ⛔ 参照层：结构本体（env_base100_upper_shell_30x30_h12）自带 24 块墙 + 36 格封顶（2026-09-20 装配），
    # 本布局若把这 60 件也重放，就会与结构本体逐面 z-fighting。因此 shell_reference 组只进 Blender 源
    # （供渲染与外形校核），TowerFloorStage3D.ROOFTOP_LAYOUT_REPLAY_GROUPS 不含它。
    "shell_reference_note": (
        "group=shell_reference（24 墙 + 36 封顶）仅作 Blender 侧参照；运行时房屋围护由 "
        "Base100UpperShell3D / env_base100_upper_shell_30x30_h12_root_top3d.tscn 独占，不重放。"
    ),
    "instances": placements,
    "design_intent": {
        "house_wall_runs": slug_counts.get("room_wall", 0) + slug_counts.get("room_window", 0) + slug_counts.get("room_doorwall", 0),
        "house_roof_cells": slug_counts.get("roof_full", 0) + slug_counts.get("roof_edge", 0) + slug_counts.get("roof_corner", 0),
        "hvac_wall_mounts": slug_counts.get("hvac_small", 0),
        "hvac_vents": slug_counts.get("hvac_vent", 0),
        "flowerboxes": slug_counts.get("flowerbox", 0),
        "large_plants": slug_counts.get("plant_large", 0),
        "small_plants": slug_counts.get("plant_small", 0),
        "ivy_patches": slug_counts.get("ivy", 0),
        "parapet_ivy_patches": slug_counts.get("parapet_ivy", 0),
        "ground_datum_m": GROUND_H,
        "layout_tile_height_m": TILE_H,
        "east_door_clear_gz_m": [EAST_DOOR_BLOCK_GZ[0], EAST_DOOR_BLOCK_GZ[1]],
        "pipe_loop_straights": slug_counts.get("pipe_straight", 0),
        "pipe_loop_elbows": slug_counts.get("pipe_elbow", 0),
        "pipe_branch_tees": slug_counts.get("pipe_tee", 0),
        "pipe_risers": slug_counts.get("pipe_riser", 0),
        "pipe_brackets": slug_counts.get("pipe_bracket", 0),
        # 立管落地（业主 2026-09-21「水管接到地板」）：每处两段、同在 h=4.945，
        # 下段倒装 ⇒ 包络 0~4.945m（管底落在承重面），上段正装 ⇒ 包络 4.945~9.89m。
        "pipe_riser_component_h_m": PIPE_RISER_COMPONENT_H,
        "pipe_riser_grounded_runs": slug_counts.get("pipe_riser", 0) // 2,
        "pipe_riser_stack_top_m": round(GROUND_H + 2 * PIPE_RISER_COMPONENT_H, 4),
        "pipe_loop_bottom_m": pipe_h,
        "pipe_riser_ring_residual_m": round(pipe_h - (GROUND_H + 2 * PIPE_RISER_COMPONENT_H), 4),
        # 墙挂件（4 空调 + 2 通风口）绕自身 X 轴倾倒 90° / 贴墙外皮。
        "hvac_wall_mount_tip_deg": round(math.degrees(HVAC_SMALL_TIP), 4),
        "hvac_wall_mount_embed_m": WALL_MOUNT_EMBED,
        "rotation_axes": ["x", "z"],
        "rotation_euler_contract": "Blender rotation_euler=(rx,0,rz)（XYZ 序 ⇒ Rz@Rx）= Godot rotation=(rx,rz,0)（YXZ 序 ⇒ Ry@Rx）；仅当 ry 分量为 0 时同序可逐值搬运。",
        # 逐件碰撞策略（四次修正）：blocking 只给「实体陈设」（花箱 / 盆栽）。
        "collision_policy": "per_instance",
        "blocking_slugs": sorted(BLOCKING_SLUGS),
        "blocking_collision_count": collision_counts[BLOCKING],
        "visual_only_collision_count": collision_counts[VISUAL_ONLY],
        "door_clearance_kept": True,
        "stair_clearance_kept": True,
    },
    "validation": {
        "room_owned_geometry": False,
        "collection_instance_only": True,
        "non_unit_scale_count": 0,
        "missing_components": [],
        "visual_only_collision_count": collision_counts[VISUAL_ONLY],
        "blocking_collision_count": collision_counts[BLOCKING],
        "component_library_modified": False,
        "pipe_socket_spacing_m": 2.5,
        "pipe_diameter_m": 0.3,
        "ground_datum_m": GROUND_H,
        "layout_tile_height_m": TILE_H,
        "east_door_clearance_kept": True,
        "pipe_riser_grounded_count": slug_counts.get("pipe_riser", 0) // 2,
        "wall_mount_tip_deg": round(math.degrees(HVAC_SMALL_TIP), 4),
        "wall_mount_tipped_count": sum(1 for r in placements
                                       if abs(r["rotation_x_deg"] - math.degrees(HVAC_SMALL_TIP)) < 1e-6),
        "wall_mount_snug": True,
    },
}

bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND), compress=True)
OUT_MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("ROOFTOP_DECOR_LAYOUT_V001_OK instances=%d blend=%s manifest=%s" % (len(placements), OUT_BLEND, OUT_MANIFEST), flush=True)
