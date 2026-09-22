class_name TowerFloorStage3D
extends Node3D
## 塔楼三层（100F 天台 / 99F 基地 / 98F 战斗层）共用同一块平面壳体（见 TOWER_SHELL_*）。
## 远征单层关卡与 use_standard_map 仍按各自口径（内容外框 / 250 标准图）。
## 重复地砖和外墙使用 Blender 导入 Mesh + MultiMesh；承重碰撞独立于渲染。

const GRID_UNIT := 5.0
const GRID_COUNT := 50
const MAP_SIZE := GRID_UNIT * GRID_COUNT
const MAP_HALF := MAP_SIZE * 0.5
# ── 塔楼壳体平面：98F / 99F / 100F 三层统一共用 ───────────────────────────
# 沿革：原 16×16（80×80，以 99F 基地中心 (0,5) 居中）
#   → 2026-09-19 向西扩 2 格得 18×16（90×80，为 100→99 西侧楼梯留栏杆净空）
#   → 2026-09-22 向东再扩 2 格得 20×16（100×80）。
# 本次口径（业主：「所有楼层都和 100 层面积一致」）：三层同矩形。原先
# 「99F 楼板 250×250 / 外墙 160×160、普通层 250×250」的三套口径自本次起作废。
# 为什么必须扩到 100m 而不是维持 90m：east 楼梯井（99↔98）外廓是**固定世界常量**
# x∈[35,50]（_stair_hole_world_rect），90m 窗口（东界 x=40）装不下它，井壁会伸到
# 楼板之外；100m 则两个在用井（west x[-45,-30]、east x[35,50]）全部落在壳体内。
# ⚠️ 名字里的 ROOFTOP 是历史沿革（这套值最早只服务天台），语义已是**全塔壳体**；
#    新代码请用 TOWER_SHELL_* 别名，ROOFTOP_* 保留只为不破坏既有引用。
const TOWER_SHELL_GRID_DIMENSIONS := Vector2i(20, 16)
const TOWER_SHELL_MAP_DIMENSIONS := Vector2(100.0, 80.0)
const TOWER_SHELL_GRID_COUNT := TOWER_SHELL_GRID_DIMENSIONS.x
const TOWER_SHELL_MAP_SIZE := TOWER_SHELL_MAP_DIMENSIONS.x
const TOWER_SHELL_WORLD_RECT := Rect2(-50.0, -35.0, 100.0, 80.0)
const ROOFTOP_GRID_DIMENSIONS := TOWER_SHELL_GRID_DIMENSIONS
const ROOFTOP_MAP_DIMENSIONS := TOWER_SHELL_MAP_DIMENSIONS
const ROOFTOP_GRID_COUNT := TOWER_SHELL_GRID_COUNT
const ROOFTOP_MAP_SIZE := TOWER_SHELL_MAP_SIZE
const ROOFTOP_WORLD_RECT := TOWER_SHELL_WORLD_RECT
# 99F 旧「楼板 250 / 外墙 160」双口径已停用（2026-09-22 三层统一后不再有任何消费者，
# 见 git 历史里的 FACILITY_OUTER_GRID_COUNT / FACILITY_OUTER_WORLD_RECT）。
# 100F 天台女儿墙高度（含压顶总高）= 0.80m —— 2026-09-20 业主口径。
# 沿革：v002 参考组件库的真尺寸是 1.80m（再往前是 0.75m，用 1.5m 几何乘 0.5 纵向
# 缩放凑出来的，没有设计依据，而且让「看得见的墙」与「挡人的墙」长期分离）。
# 业主看过 1.80m 的实机效果后要求「改成 0.8 米的」并去掉中段的密集竖杠，于是女儿墙
# 源件按「方案A 平整墙板」重建为总高 0.80m
# （assets/art/environments/tower_zones/rooftop/source/author_env_rooftop_parapet_v003.py）。
# 「视觉包络 = 碰撞高度」这条不变量继续保持。
# ⚠️ 玩家没有跳跃、也没有台阶攀爬（Player3D 只有重力 + move_and_slide），因此 0.80m
# 与 1.80m 的阻挡效果等价：都是「走不出去」，不存在能被跨过去的低墙副作用。
# 0.80m 只影响视觉高度、相机越过墙顶的视线，以及子弹射线在 0.80m 以上不再被边界拦下。
const ROOFTOP_PARAPET_HEIGHT := 0.8
# 天台女儿墙组件厚度（参考组件库 v002 的 bounds_size.z = 0.50m）。
# 与普通层 WALL_THICKNESS(0.30m) 不同，因此边界内缩口径必须按层类型取。
const ROOFTOP_PARAPET_THICKNESS := 0.5
# 天台四角转角件的包络边长（2.5m×2.5m）。每条边两端各让出这么多，
# 于是 100−5=95m 正好 19 个整格、80−5=75m 正好 15 个整格，格子不错位。
const ROOFTOP_CORNER_ARM_M := 2.5
# 楼梯口占位矮墙（prp_tower_wall_parapet_door_5m）的基础几何高度，
# 用来把它的纵向缩放换算到与女儿墙同高。
const ROOFTOP_PARAPET_DOOR_BASE_HEIGHT := 1.5
const PROTECTED_FLOOR_PATCH_SIDE_M := 50.0
const PROTECTED_FLOOR_PATCH_TILES_PER_SIDE := int(PROTECTED_FLOOR_PATCH_SIDE_M / GRID_UNIT)
const FLOOR_THICKNESS := 0.30
const WALL_THICKNESS := 0.30
const FLOOR_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_floor_tile_5m.tscn"
)
const POLISHED_FLOOR_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_descent_3d/runtime/floor_tile_5m/env_tower_floor_tile_5m_root_top3d.tscn"
)
# 100F 天台正式地砖（天台参考组件库 v002 / ENV-ROOFTOP-REF-FLOOR-FULL 的 5m 件）。
# ⚠️ 与上面两件旧砖的**原点契约不同**：本件是「底面中心」（几何 Y=0..0.30），
# 旧件是「几何中心」（Y≈-0.15..+0.15）。因此摆放偏移不能再用固定
# -FLOOR_THICKNESS*0.5，必须按模块 AABB 求「可视顶面对齐承重面 Y=0」的偏移
# （见 _floor_visual_origin_y）。98F 与天台历史上共用抛光砖，本次只有天台换件。
const ROOFTOP_FLOOR_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_floor_5m.tscn"
)
const WALL_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn"
)
const BASE99_CORNER_L_VISUAL: PackedScene = preload(
	"res://assets/art/environments/base_facility_3d/components/env_base99_corner_l_5m/env_base99_corner_l_5m_visual_top3d.glb"
)
const PARAPET_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_parapet_5m.tscn"
)
const ROOFTOP_CORNER_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_parapet_outer_2p5m.tscn"
)
const PARAPET_DOOR_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_door_5m.tscn"
)
# 99F 基地层的外墙立面（= 从天台边缘往下看到的那圈「塔身外墙」）。
#
# 沿革（2026-09-22 业主口径）：这圈立面**原本由 100F 天台**在女儿墙正下方补出来
# （参考拼装 reference_assembly.json 把 facade_* 摆在 z=-12.00，即「低一整层」），
# 用来填「从天台边缘往下看是一段 12m 空洞」。三层壳体统一成 100×80 后，99F 自己的
# 普通外墙（prp_tower_wall_solid_5m）与这圈立面落到同一圈轮廓、同一竖向层带 ——
# 实测 62 槽中 58 槽沿轴同位、两面共面（z-fighting 闪面）。业主裁定：立面改由 99F
# 自己提供（同一套 facade_* 资源），天台那圈**整圈删掉**。
#
# 因此底面基准从「天台 stage 的 -12.0」改成**本层楼面 y=0**：世界坐标仍是同一段
# y[-12, -0.1]（99F stage 在 y=-12），只是参照系换成 99F 自己。
# 顶面 11.90m 落在上层楼板下方 0.10m —— 与 TowerGeometry3D 的
# WALL_VISUAL_HEIGHT_M(11.90) / WALL_VISUAL_TOP_CLEARANCE_M(0.10) 同一口径。
const FACADE_OUTER_BOTTOM_Y := 0.0
# 立面模块厚度（参考组件库 v002 facade_* 的 bounds_size.z = 0.30m）。
# 与女儿墙(0.50m)不同，所以中心线内缩量按自己的厚度取（0.15m）；
# 恰好等于普通层 WALL_THICKNESS(0.30m) —— 99F 边界碰撞盒厚本来就是 0.30m，
# 于是立面件的包络**正好落在原有边界碰撞体里**，不产生「看得见的墙 / 挡人的墙」错位。
const FACADE_OUTER_THICKNESS := 0.30
# 立面「实墙 : 窗墙」节奏：每 3 个 5m 槽位「实 / 窗 / 窗」，侧内自最小坐标端起算。
# 与参考拼装同相位（参考侧 10 槽正好 4 实 6 窗，两端都落在实墙上）。
const FACADE_OUTER_SOLID_EVERY := 3
# 立面件资源。⚠️ AssetID 家族名里的 rooftop 是历史沿革（这套件最早只服务天台），
# 现在由 99F 消费 —— 见 _uses_facade_outer_modules()。
const FACADE_OUTER_SOLID_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_facade_solid_5m.tscn"
)
const FACADE_OUTER_WINDOW_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_facade_window_5m.tscn"
)
# 100F 天台 Blender 布局重放：只接入房屋与装饰层；地砖、女儿墙、外立面和碰撞
# 继续由本脚本的程序化壳体拥有，避免重复承重和重复边界碰撞。
const ROOFTOP_DECOR_LAYOUT_PATH := "res://assets/art/environments/tower_zones/rooftop/source/layouts/100f_decorated_v001/rooftop_100f_decorated_layout_v001.json"
const ROOFTOP_ROOM_WALL_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_room_wall_5x12.tscn"
)
const ROOFTOP_ROOM_WINDOW_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_room_window_5x12.tscn"
)
const ROOFTOP_ROOM_DOORWALL_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_room_doorwall_5x12.tscn"
)
const ROOFTOP_ROOF_FULL_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_roof_full_5m.tscn"
)
const ROOFTOP_ROOF_EDGE_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_roof_edge_5m.tscn"
)
const ROOFTOP_ROOF_CORNER_SCENE: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_rooftop_roof_corner_5m.tscn"
)
const ROOFTOP_DECOR_SCENES := {
	"hvac_small": preload("res://assets/art/environments/tower_zones/rooftop/runtime/hvac_small.tscn"),
	"hvac_vent": preload("res://assets/art/environments/tower_zones/rooftop/runtime/hvac_vent.tscn"),
	"pipe_straight": preload("res://assets/art/environments/tower_zones/rooftop/runtime/pipe_straight.tscn"),
	"pipe_elbow": preload("res://assets/art/environments/tower_zones/rooftop/runtime/pipe_elbow.tscn"),
	"pipe_tee": preload("res://assets/art/environments/tower_zones/rooftop/runtime/pipe_tee.tscn"),
	"pipe_riser": preload("res://assets/art/environments/tower_zones/rooftop/runtime/pipe_riser.tscn"),
	"pipe_bracket": preload("res://assets/art/environments/tower_zones/rooftop/runtime/pipe_bracket.tscn"),
	"ivy": preload("res://assets/art/environments/tower_zones/rooftop/runtime/ivy.tscn"),
	"parapet_ivy": preload("res://assets/art/environments/tower_zones/rooftop/runtime/parapet_ivy.tscn"),
	"flowerbox": preload("res://assets/art/environments/tower_zones/rooftop/runtime/flowerbox.tscn"),
	"plant_large": preload("res://assets/art/environments/tower_zones/rooftop/runtime/plant_large.tscn"),
	"plant_small": preload("res://assets/art/environments/tower_zones/rooftop/runtime/plant_small.tscn"),
}
# ⚠️ 只重放装饰组。房屋围护（布局源的 house_shell / house_roof，现已改名 shell_reference）
# **不在**此列：Base100UpperShell3D 的 prefab（env_base100_upper_shell_30x30_h12）自
# 2026-09-20 起已自带 24 块墙 + 36 格封顶，若把这 60 件也重放，会在同一世界坐标上逐面
# z-fighting。布局源里它们只作 Blender 侧参照。
const ROOFTOP_LAYOUT_REPLAY_GROUPS := ["hvac_wall", "greenery", "ivy", "parapet_ivy", "pipe_loop", "pipe_risers"]
# 逐件碰撞策略（2026-09-21 四次修正；业主实机报「花盆和花圃没有阻挡」）。
# 布局 JSON 的 collision_policy 是**唯一真源**，词表与
# assets/art/environments/tower_zones/rooftop/source/author_rooftop_decorated_layout_v001.py 一致：
#   visual_only —— 装饰默认：禁用组件自带碰撞（本文件旧行为，逐件无条件禁用）；
#   blocking    —— 实体陈设（花箱 / 大盆栽 / 小盆栽）：禁用组件自带碰撞后，按**实测可视包络**
#                  生成一个 BoxShape3D 代理，玩家不可穿过。
# ⛔ 代理尺寸一律由实测包络推出（TowerGeometry3D.resolve_visual_bounds），不得写死常量 ——
#    否则美术改件后碰撞会与实体脱节。
const ROOFTOP_COLLISION_VISUAL_ONLY := "visual_only"
const ROOFTOP_COLLISION_BLOCKING := "blocking"
# 挡玩家用的世界静态层：与家具（RoomFurniture3D）/ 墙体 / 边界碰撞同层，
# 玩家 scenes/Player3D.tscn 的 collision_mask 含该层。
const ROOFTOP_COLLISION_BLOCKING_LAYER := 1
# 天台女儿墙破损变体（A=崩顶 / B=贯穿 / C=塌脚）。三件与 intact 件同包络
# （5.00×1.80×0.50）、同原点（底面中心），且端头带 |x|>=2.05m 与 intact 件逐位相同
# （已在 GLB 字节层证明：source/verify_env_rooftop_parapet_damage_bands.py），
# 因此可沿任一边、任意顺序与原件 / 彼此对接，接头无缝、槽位相位不变。
const PARAPET_DAMAGE_SCENES := [
	preload("res://assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_a_5m.tscn"),
	preload("res://assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_b_5m.tscn"),
	preload("res://assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_c_5m.tscn"),
]
const PARAPET_DAMAGE_KEYS := ["dmg_a", "dmg_b", "dmg_c"]
# 每段直段受损的概率（用户口径「约 1/4 随机」）；三档均分这 1/4。
const ROOFTOP_PARAPET_DAMAGE_CHANCE := 0.25
# 破损排布默认种子。固定值 ⇒ 每次进天台看到的破损分布一致（可复现、可门禁）；
# 想要每局不同，在 add_child()（即 _ready）之前调用 set_outer_damage_seed()。
const ROOFTOP_PARAPET_DAMAGE_SEED := 20260919
const FLOOR_TILE_MATERIAL_LIGHT: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_override_top3d_v001.tres"
)
const FLOOR_TILE_MATERIAL_DARK: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_dark_top3d_v001.tres"
)
# v0.1 v2 拼接交替材质（A/B 微差异版）
const FLOOR_TILE_MATERIAL_A: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_warm_a_v001.tres"
)
const FLOOR_TILE_MATERIAL_B: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_warm_b_v001.tres"
)
const WALL_DOOR_GAP_HALF_WIDTH := 5.0
const BASE_99_100_ATRIUM_WORLD_RECT := Rect2(-15.0, -10.0, 30.0, 30.0)
const BASE_99_100_ATRIUM_TILE_COUNT := 36

var floor_index := 0
var floor_kind := "combat"
# 单层关卡（远征）虽然 floor_index==0，但绝不继承「天台」窄轮廓：
# 必须使用标准 250×250 网格，否则 x>40 / z<-35 的房间会既没有承重楼面、
# 也没有外圈墙，玩家会直接掉出关卡。
var force_standard_map := false
## 独立单层关卡（远征）的实际内容外框。非空时楼面与外墙都按该矩形生成，
## 不再套用塔楼整块 250×250 网格 —— 否则远处空地上会立着一圈没有内容的墙。
var content_world_rect := Rect2()
var _has_content_bounds := false
## 外墙可视纵向缩放实测值。正常层与远征都是 1.0，只有 100F 天台女儿墙是 0.5。
## 写入快照供门禁断言「可视高度 == 碰撞高度」，防止再次出现看不见的挡墙。
var _outer_visual_scale_y := 1.0
var stair_hole_sides: Array[String] = []
# 房间自带正式地砖的区域（当前仅入口安全房 3×3 格）。只从通用可视地砖里挖掉，
# 承重碰撞不受影响，仍由 _build_support() 用 _hole_rects() 铺满整个房间地面。
var additional_visual_holes: Array[Rect2] = []
## —— 承重保底：授权房间足迹 ——
## 楼梯井洞口的平面矩形是**固定塔楼常量**（_stair_hole_world_rect），按「楼梯出口房的墙
## 落在 5m 核心边」的标准塔楼模式定的。授权布局的房间足迹由摆位源给，可能与固定洞口
## 错开：区块00 的办公室西墙在 x=−40，西侧洞口却从 x=−45 伸到 x=−30 ⇒ 洞口多伸进房间
## 10m，那 10m 没有 FloorSupport，房中央实测一路掉到 97F（y=−29.97 → −36.0）。
## 而楼梯资产本身是贴合房间界面摆的（实测 Stair_98_97 落在 x[−49.5,−40.5]，在房间以西）。
## 所以洞要按「房间足迹」先削一刀：足迹内必须保留承重。
## 标准塔楼里两者不相交 ⇒ 削完与原矩形逐值相同（回归零影响）。
## 写入时机：TowerDescent3D._rebuild_floor_stage 必须在 add_child 之前 set() ——
## _build_support() 在 stage 自己的 _ready() 里跑。
var support_keep_out_rects: Array[Rect2] = []
# 上述洞实际从通用可视地砖里移除了多少格（已扣除与楼梯洞重叠的部分）。
var _additional_visual_hole_tile_count := 0
var _floor_visual_light: MultiMeshInstance3D
var _floor_visual_dark: MultiMeshInstance3D
var _protected_floor_visual_light: MultiMeshInstance3D
var _protected_floor_visual_dark: MultiMeshInstance3D
var _outer_visual: MultiMeshInstance3D
## 破损直段的批次节点（每档一个 MultiMesh）。intact 直段仍在 _outer_visual。
var _outer_damage_visual: Array[MultiMeshInstance3D] = []
## 外立面（= 99F 那圈塔身外墙）的两个批次（实墙 / 窗墙）。只有 99F 非空。
var _outer_facade_solid_visual: MultiMeshInstance3D
var _outer_facade_window_visual: MultiMeshInstance3D
## 立面实测件数（按计划值写入，批次实例数由 _outer_facade_batch_counts 对账）。
var _outer_facade_solid_count := 0
var _outer_facade_window_count := 0
## 立面全部槽位变换（实墙 + 窗墙，同序）。与女儿墙的槽位表同一用途：
## 「整圈覆盖到哪 / 有没有角缝」的唯一真源，探针按它算覆盖，不必回读 MultiMesh
## （后者在 --headless 的 dummy 渲染器下恒为单位阵）。
var _outer_facade_slot_transforms: Array[Transform3D] = []
## 与 _outer_facade_slot_transforms 逐下标对应的档位表（"solid" / "window"）。
var _outer_facade_slot_kinds: Array = []
## 楼梯口占位矮墙（ParapetDoorWall_*）实测件数。天台封口后恒为 0；
## 普通层若有楼梯口门洞则等于被跳过的直段数。
var _outer_doorway_wall_count := 0
## 直段槽位总数（intact + 破损；不含四角转角件与西侧门洞补位墙）。
var _outer_straight_slot_count := 0
## 各档直段件数，键为 intact / dmg_a / dmg_b / dmg_c。
var _outer_damage_counts := {"intact": 0, "dmg_a": 0, "dmg_b": 0, "dmg_c": 0}
## 破损排布种子（写快照供门禁断言，也可在 _ready 前用 set_outer_damage_seed 覆盖）。
var _outer_damage_seed := ROOFTOP_PARAPET_DAMAGE_SEED
## 全部直段槽位变换（intact + 破损）。破损只换外观、不挪槽位，因此这是「直段共几段、
## 每条边覆盖到哪」的唯一真源：门禁与对齐探针按它核对，不必关心某槽位当前用哪一档。
var _outer_straight_slot_transforms: Array[Transform3D] = []
## 与 _outer_straight_slot_transforms 逐下标对应的档位表（"intact" / "dmg_a" / …）。
## 与槽位表同源同序，且不经过 RenderingServer，所以 --headless 下也能读到。
var _outer_slot_kinds: Array = []
var _base99_outer_corner_visuals: Array[Node3D] = []
var _rooftop_outer_corner_visuals: Array[Node3D] = []
var _support_root: StaticBody3D
# 100F 正式装饰布局根。地砖/女儿墙/外立面等结构壳体继续由本类拥有；
# 房屋与装饰组件由 Blender 布局清单重放到该根节点。
var _rooftop_art_instance: Node3D
var _rooftop_art_blocker_count := 0
var _rooftop_art_instance_count := 0
## 重放时按 collision_policy 生成的挡玩家碰撞代理数（blocking 件）。
## 供验收读取：探针据此断言「绿化 20 件都挡人、其余 100 件都不挡」。
var _rooftop_blocking_collision_count := 0
var _shell_visible := true
var _floor_visible := true
var _outer_visible := true
var _tile_count := 0
var _support_rect_count := 0
var _protected_floor_patch_enabled := false
var _protected_floor_patch_grid_center := Vector2i(-1, -1)
var _protected_floor_patch_tile_count := 0
## 场景路径 → 资产侧声明的 preserve_authored_palette。按场景缓存（跨实例共享），
## 让天台地砖 / 抛光砖 / 旧占位砖各只实例化探测一次，而不是共用一个全局布尔。
static var _palette_preserve_cache := {}


func configure(
	index: int,
	kind: String,
	holes: Array[String],
	extra_visual_holes: Array[Rect2] = [],
	use_standard_map: bool = false,
	content_bounds: Rect2 = Rect2()
) -> void:
	floor_index = index
	floor_kind = kind
	force_standard_map = use_standard_map
	content_world_rect = content_bounds
	_has_content_bounds = content_bounds.size.x > 0.0 and content_bounds.size.y > 0.0
	stair_hole_sides.assign(holes)
	additional_visual_holes.assign(extra_visual_holes)


func _ready() -> void:
	name = "Floor_%d" % (100 - floor_index)
	set_meta("floor_index", floor_index)
	set_meta("floor_number", 100 - floor_index)
	set_meta(
		"block_id",
		"expedition"
		if force_standard_map
		else "rooftop"
		if floor_index == 0
		else "base"
		if floor_index == 1
		else "battle"
	)
	add_to_group("tower_floor_stage_3d")
	_build_floor()
	_build_outer_shell()
	_build_support()
	if _uses_rooftop_profile():
		_build_rooftop_authored_layout()


func _build_rooftop_authored_layout() -> void:
	_rooftop_art_blocker_count = 0
	_rooftop_art_instance_count = 0
	var file := FileAccess.open(ROOFTOP_DECOR_LAYOUT_PATH, FileAccess.READ)
	if file == null:
		_rooftop_art_blocker_count = 1
		push_error("Rooftop decorated layout missing: %s" % ROOFTOP_DECOR_LAYOUT_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_rooftop_art_blocker_count = 1
		push_error("Rooftop decorated layout is not a JSON object")
		return
	var layout := parsed as Dictionary
	var schema_ok := str(layout.get("schema", "")) == "shellstrom2.rooftop.decorated_layout"
	var version_ok := is_equal_approx(float(layout.get("schema_version", -1)), 1.0)
	var identity_ok := str(layout.get("floor", "")) == "100F" and str(layout.get("block_id", "")) == "rooftop"
	var dimensions := layout.get("dimensions_m", []) as Array
	var dimensions_ok := dimensions.size() == 2 and is_equal_approx(float(dimensions[0]), ROOFTOP_MAP_DIMENSIONS.x) and is_equal_approx(float(dimensions[1]), ROOFTOP_MAP_DIMENSIONS.y)
	var world_rect := layout.get("world_rect_m", []) as Array
	var rect_ok := false
	if world_rect.size() == 4:
		var authored_rect := Rect2(float(world_rect[0]), float(world_rect[1]), float(world_rect[2]), float(world_rect[3]))
		rect_ok = is_equal_approx(authored_rect.position.x, ROOFTOP_WORLD_RECT.position.x) and is_equal_approx(authored_rect.position.y, ROOFTOP_WORLD_RECT.position.y) and is_equal_approx(authored_rect.size.x, ROOFTOP_WORLD_RECT.size.x) and is_equal_approx(authored_rect.size.y, ROOFTOP_WORLD_RECT.size.y)
	_rooftop_art_blocker_count = int(not schema_ok) + int(not version_ok) + int(not identity_ok) + int(not dimensions_ok) + int(not rect_ok)
	if _rooftop_art_blocker_count > 0:
		push_error("Rooftop decorated layout contract failed blockers=%d schema_ok=%s version_ok=%s identity_ok=%s dimensions_ok=%s rect_ok=%s" % [
			_rooftop_art_blocker_count,
			str(str(layout.get("schema", "")) == "shellstrom2.rooftop.decorated_layout"),
			str(is_equal_approx(float(layout.get("schema_version", -1)), 1.0)),
			str(str(layout.get("floor", "")) == "100F" and str(layout.get("block_id", "")) == "rooftop"),
			str(dimensions.size() == 2 and is_equal_approx(float(dimensions[0]), ROOFTOP_MAP_DIMENSIONS.x) and is_equal_approx(float(dimensions[1]), ROOFTOP_MAP_DIMENSIONS.y)),
			str(world_rect.size() == 4 and is_equal_approx(float(world_rect[0]), ROOFTOP_WORLD_RECT.position.x) and is_equal_approx(float(world_rect[1]), ROOFTOP_WORLD_RECT.position.y) and is_equal_approx(float(world_rect[2]), ROOFTOP_WORLD_RECT.size.x) and is_equal_approx(float(world_rect[3]), ROOFTOP_WORLD_RECT.size.y)),
		])
		return
	var candidate := Node3D.new()
	candidate.name = "FormalRooftopFacilities"
	candidate.set_meta("layout_id", str(layout.get("layout_id", "")))
	candidate.set_meta("version", str(layout.get("layout_version", "")))
	candidate.set_meta("source_layout", ROOFTOP_DECOR_LAYOUT_PATH)
	candidate.set_meta("independent_blocker_count", 0)
	# ⚠️ 布局整体**不再是纯视觉**：绿化 20 件登记为 blocking，由本类生成挡玩家碰撞代理。
	# 真源是逐件 collision_policy（见下方重放循环），这里只留总述与计数。
	candidate.set_meta("visual_only", false)
	candidate.set_meta("collision_policy", "per_instance")
	_rooftop_blocking_collision_count = 0
	var instances := layout.get("instances", []) as Array
	for item_variant in instances:
		if not (item_variant is Dictionary):
			_rooftop_art_blocker_count += 1
			continue
		var item := item_variant as Dictionary
		if not bool(item.get("enabled", false)):
			continue
		var group := str(item.get("group", ""))
		if group not in ROOFTOP_LAYOUT_REPLAY_GROUPS:
			continue
		var slug := str(item.get("component_slug", ""))
		var scene := _rooftop_scene_for_slug(slug)
		if scene == null:
			_rooftop_art_blocker_count += 1
			push_error("Rooftop layout component has no runtime scene: %s" % slug)
			continue
		var scale_values := item.get("scale", []) as Array
		if scale_values.size() != 3 or not is_equal_approx(float(scale_values[0]), 1.0) or not is_equal_approx(float(scale_values[1]), 1.0) or not is_equal_approx(float(scale_values[2]), 1.0):
			_rooftop_art_blocker_count += 1
			push_error("Rooftop layout component has non-unit scale: %s" % str(item.get("instance_id", slug)))
			continue
		var instance := scene.instantiate() as Node3D
		if instance == null:
			_rooftop_art_blocker_count += 1
			push_error("Rooftop layout scene instantiate failed: %s" % slug)
			continue
		instance.name = str(item.get("instance_id", "Rooftop_%s_%d" % [slug, _rooftop_art_instance_count]))
		var position_values := item.get("position_m", []) as Array
		if position_values.size() != 3:
			instance.free()
			_rooftop_art_blocker_count += 1
			continue
		# 坐标契约（全项目统一，勿改）：Blender Z-up X=东 / Y=北，Godot 平面 +z = 南；
		# 布局源按 Godot 世界平面口径书写、写入 Blender 时只做 by = -gz 一步换算
		# （见 source/author_rooftop_decorated_layout_v001.py 的坐标契约段），
		# 于是这里用 (x, h, -by) 还原。⛔ 改成 (x, h, +by) 会让整份布局南北镜像、
		# 北侧整体溢出天台 10m —— 2026-09-21 业主实机报的就是这个症状。
		instance.position = Vector3(float(position_values[0]), float(position_values[2]), -float(position_values[1]))
		instance.rotation.y = deg_to_rad(float(item.get("rotation_y_deg", 0.0)))
		# 绕**自身 X 轴**的倾倒（墙挂空调：组件是立式做的，顶面出风风扇；挂到墙上必须倾倒
		# 90° 风扇才朝外 —— 业主 2026-09-21「空调机在墙上的状态需要 90 度旋转，让风扇朝外」）。
		# 立管下段也用这个分量做 180° 倒装（原点在底 ⇒ 翻过来后包络落到地面以上，管底贴 y=0）。
		# ⚠️ 欧拉序：Blender 默认 XYZ、Godot 默认 YXZ。布局源写 (rx, 0, rz)、这里写
		# rotation=(rx, ry, 0) ⇒ Blender 的 Rz@Rx 与 Godot 的 Ry@Rx **同序**，角度可逐值搬运。
		# ⛔ 若哪天布局源同时给出 ry 与 rz（即 rotation_y_deg 与「绕 Z 的 tip」并存），
		# Rx/Rz 的先后会反过来，这套搬运就失效 —— 布局源侧的契约写在
		# source/author_rooftop_decorated_layout_v001.py 的 rotation_euler_contract 里。
		instance.rotation.x = deg_to_rad(float(item.get("rotation_x_deg", 0.0)))
		# 防再犯：换算后的平面位置必须落在天台矩形内。布局源里没有这条断言之前，
		# 少一步换算不会有任何报错，只会在实机上静默错位。
		if not ROOFTOP_WORLD_RECT.has_point(Vector2(instance.position.x, instance.position.z)):
			_rooftop_art_blocker_count += 1
			push_error(
				"Rooftop layout instance outside rooftop rect: %s at %s"
				% [str(item.get("instance_id", slug)), str(instance.position)]
			)
			instance.free()
			continue
		instance.set_meta("layout_instance_id", str(item.get("instance_id", "")))
		instance.set_meta("component_slug", slug)
		instance.set_meta("layout_group", group)
		var policy := str(item.get("collision_policy", ROOFTOP_COLLISION_VISUAL_ONLY))
		instance.set_meta("collision_policy", policy)
		instance.set_meta("design_note", str(item.get("design_note", "")))
		if _apply_rooftop_collision_policy(instance, slug, policy):
			_rooftop_blocking_collision_count += 1
		candidate.add_child(instance)
		_rooftop_art_instance_count += 1
	if _rooftop_art_blocker_count > 0:
		candidate.free()
		push_error("Rooftop decorated layout replay blocked=%d" % _rooftop_art_blocker_count)
		return
	candidate.set_meta("instance_count", _rooftop_art_instance_count)
	candidate.set_meta("blocking_collision_count", _rooftop_blocking_collision_count)
	add_child(candidate)
	_rooftop_art_instance = candidate


func _rooftop_scene_for_slug(slug: String) -> PackedScene:
	match slug:
		"room_wall":
			return ROOFTOP_ROOM_WALL_SCENE
		"room_window":
			return ROOFTOP_ROOM_WINDOW_SCENE
		"room_doorwall":
			return ROOFTOP_ROOM_DOORWALL_SCENE
		"roof_full":
			return ROOFTOP_ROOF_FULL_SCENE
		"roof_edge":
			return ROOFTOP_ROOF_EDGE_SCENE
		"roof_corner":
			return ROOFTOP_ROOF_CORNER_SCENE
		_:
			return ROOFTOP_DECOR_SCENES.get(slug) as PackedScene


func _disable_rooftop_visual_collision(root: Node) -> void:
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = true
	if root is CollisionObject3D:
		(root as CollisionObject3D).collision_layer = 0
		(root as CollisionObject3D).collision_mask = 0
	for child in root.get_children():
		_disable_rooftop_visual_collision(child)


## 施放逐件碰撞策略（2026-09-21 四次修正；业主实机报「花盆和花圃没有阻挡」）。
## 返回 true 表示该件生成了挡玩家碰撞代理（blocking）。
##
## ⛔ 组件自带碰撞**一律先禁用**：运行时不信任组件 prefab 的碰撞（它们声明为 visual_only），
##    这样 blocking 件也**恰好只有一个**代理形状，验收计数才有确定口径。
## ⛔ 代理尺寸**不写死**：由实测可视包络（TowerGeometry3D.resolve_visual_bounds）推出 ——
##    美术换件 / 改尺寸后碰撞自动跟随，不会与实体脱节。
func _apply_rooftop_collision_policy(instance: Node3D, slug: String, policy: String) -> bool:
	_disable_rooftop_visual_collision(instance)
	if policy == ROOFTOP_COLLISION_VISUAL_ONLY:
		return false
	if policy != ROOFTOP_COLLISION_BLOCKING:
		# 未知策略按「不挡人」处理并报错 —— 既不静默生成障碍，也不静默漏挡。
		push_error("Rooftop layout unknown collision_policy %s on slug %s" % [policy, slug])
		return false
	var bounds := TowerGeometry3D.resolve_visual_bounds(instance)
	# 退化包络（空心 / 未加载网格）不生成零尺寸代理，否则引擎会报形状错误。
	if bounds.size.x <= 0.001 or bounds.size.y <= 0.001 or bounds.size.z <= 0.001:
		push_error("Rooftop blocking instance has degenerate visual bounds: %s size=%s" % [slug, str(bounds.size)])
		return false
	var body := StaticBody3D.new()
	body.name = "BlockingCollision"
	body.collision_layer = ROOFTOP_COLLISION_BLOCKING_LAYER
	body.collision_mask = 0
	# 与外墙 / 立面环碰撞同款：显式 ALWAYS，避免从被流送停用的父节点继承物理停用状态
	# （见 _install_rooftop_outer_boundary_collision 的同款说明）。
	body.process_mode = Node.PROCESS_MODE_ALWAYS
	body.set_meta("layout_collision_policy", policy)
	body.set_meta("component_slug", slug)
	var shape := CollisionShape3D.new()
	shape.name = "BlockingBox"
	var box := BoxShape3D.new()
	box.size = bounds.size
	shape.shape = box
	# 代理挂在实例根下 ⇒ 自带实例的 position/rotation，局部中心即包络中心。
	shape.position = bounds.get_center()
	body.add_child(shape)
	instance.add_child(body)
	return true


func set_shell_visible(show_shell: bool) -> void:
	set_render_state(show_shell, show_shell)


func set_render_state(_show_floor: bool, _show_outer: bool) -> void:
	# 结构壳体永久驻留：任何流送调用都不得隐藏楼板或塔楼外圈墙。
	var show_floor := true
	var show_outer := true
	_floor_visible = true
	_outer_visible = true
	_shell_visible = true
	if _floor_visual_light != null:
		_floor_visual_light.visible = show_floor
	if _floor_visual_dark != null:
		_floor_visual_dark.visible = show_floor
	if _outer_visual != null:
		_outer_visual.visible = show_outer
	# 破损批次与 intact 批次同属外墙壳体，必须同开同关：只关一批会让破损位置
	# 出现「整段消失」的空洞观感（碰撞还在，视觉上却像缺口）。
	for damage_visual in _outer_damage_visual:
		damage_visual.visible = show_outer
	# 外立面（= 99F 那圈塔身外墙）同样属于永久结构壳体：它同时是「从天台边缘往下
	# 看到的那层墙」，被任何流送调用关掉都会让「天台下是空的」问题重现。
	for facade_visual in [_outer_facade_solid_visual, _outer_facade_window_visual]:
		if facade_visual != null:
			facade_visual.visible = show_outer
	for corner_visual in _base99_outer_corner_visuals:
		corner_visual.visible = show_outer
	for corner_visual in _rooftop_outer_corner_visuals:
		corner_visual.visible = show_outer
	if _rooftop_art_instance != null:
		_rooftop_art_instance.visible = true
	_apply_protected_floor_patch_visibility()


## 兼容旧存档/测试入口。完整楼板已永久显示，局部补丁必须保持关闭，
## 避免同位置重复渲染引发闪烁、阴影偏差或额外 draw call。
func set_protected_floor_patch(_center_world_position: Vector3, _enabled: bool) -> void:
	_protected_floor_patch_enabled = false
	_apply_protected_floor_patch_visibility()


func is_shell_visible() -> bool:
	return _shell_visible


## 覆盖破损排布种子。必须在 add_child()（即 _ready 里的 _build_outer_shell）之前调用，
## 之后再改只影响快照字段、不重排已摆好的外墙。
func set_outer_damage_seed(value: int) -> void:
	_outer_damage_seed = value


## 直段槽位总数（intact + 破损；不含四角转角件与门洞补位墙）。
func get_outer_straight_slot_count() -> int:
	return _outer_straight_slot_count


## 全部直段槽位变换（intact + 破损）。破损只换外观、不挪槽位，故这是槽位真源。
func get_outer_straight_slot_transforms() -> Array[Transform3D]:
	return _outer_straight_slot_transforms.duplicate()


## 与 get_outer_straight_slot_transforms() 逐下标对应的档位表（"intact" / "dmg_a" / …）。
## 门禁与探针用它回答「第 i 个槽位用的是哪一档」，不依赖 MultiMesh 实例变换回读
## （后者在 --headless 的 dummy 渲染器下恒为单位阵）。
func get_outer_slot_kinds() -> Array:
	return _outer_slot_kinds.duplicate()


## 各档直段件数（计划值）。
func get_outer_damage_counts() -> Dictionary:
	return _outer_damage_counts.duplicate()


## 立面环全部槽位变换（实墙 + 窗墙，同序）。与 get_outer_straight_slot_transforms()
## 同一用途：探针/门禁按它核对「整圈是否满铺、角上是否留缝」。
func get_outer_facade_slot_transforms() -> Array[Transform3D]:
	return _outer_facade_slot_transforms.duplicate()


## 与 get_outer_facade_slot_transforms() 逐下标对应的档位表（"solid" / "window"）。
func get_outer_facade_slot_kinds() -> Array:
	return _outer_facade_slot_kinds.duplicate()


## 各批次 MultiMesh 的实测实例数。与 get_outer_damage_counts() 对账，
## 防止「计划说换了 15 段、实际只摆了 3 段」这类静默漂移。
func _outer_damage_batch_counts() -> Dictionary:
	var counts := {"intact": 0, "dmg_a": 0, "dmg_b": 0, "dmg_c": 0}
	if _outer_visual != null and _outer_visual.multimesh != null:
		counts["intact"] = _outer_visual.multimesh.instance_count
	for index in range(_outer_damage_visual.size()):
		var visual := _outer_damage_visual[index]
		if visual != null and visual.multimesh != null:
			counts[str(PARAPET_DAMAGE_KEYS[index])] = visual.multimesh.instance_count
	return counts


## 外立面两个批次的实测实例数。与计划值（_outer_facade_*_count）对账，
## 防「计划说 62 件、实际只摆了 4 件」这类静默漂移 —— 与破损档同一套对账口径。
func _outer_facade_batch_counts() -> Dictionary:
	var counts := {"solid": 0, "window": 0}
	if _outer_facade_solid_visual != null and _outer_facade_solid_visual.multimesh != null:
		counts["solid"] = _outer_facade_solid_visual.multimesh.instance_count
	if _outer_facade_window_visual != null and _outer_facade_window_visual.multimesh != null:
		counts["window"] = _outer_facade_window_visual.multimesh.instance_count
	return counts


func get_snapshot() -> Dictionary:
	return {
		"floor_index": floor_index,
		"floor_kind": floor_kind,
		"map_size": _floor_map_size(),
		"grid_count": _floor_grid_count(),
		"map_dimensions": _floor_map_dimensions(),
		"grid_dimensions": _floor_grid_dimensions(),
		"floor_world_rect": _floor_world_rect(),
		"grid_unit": GRID_UNIT,
		"tile_count": _tile_count,
		"tile_count_light": _floor_visual_light.multimesh.instance_count if _floor_visual_light != null and _floor_visual_light.multimesh != null else 0,
		"tile_count_dark": _floor_visual_dark.multimesh.instance_count if _floor_visual_dark != null and _floor_visual_dark.multimesh != null else 0,
		"outer_map_size": _outer_map_size(),
		"outer_grid_count": _outer_grid_count(),
		"outer_map_dimensions": _outer_map_dimensions(),
		"outer_grid_dimensions": _outer_grid_dimensions(),
		"outer_world_rect": _outer_world_rect(),
		"outer_module_count": 2 * (_outer_grid_dimensions().x + _outer_grid_dimensions().y),
		# 周长格数是几何事实；天台两端让位给转角件后，实体直段比它少「每边一段」。
		"outer_segment_count": _outer_segment_total(),
		"outer_corner_count": 4 if _uses_rooftop_parapet_modules() else 0,
		"outer_wall_height": _outer_wall_height(),
		"outer_wall_thickness": _outer_wall_thickness(),
		# 直段槽位真源与破损排布。槽位总数恒为「整圈直段数 - 门洞补位墙件数」；
		# 破损只把其中一部分槽位的可视件换成破损变体，不改槽位数、不改碰撞。
		# outer_damage_counts 是计划值，outer_damage_batch_counts 是各批次 MultiMesh
		# 的实测实例数 —— 两者不一致说明「计划与摆放」已经漂移，门禁据此对账。
		"outer_straight_slot_count": _outer_straight_slot_count,
		# 楼梯口占位矮墙（系统的 ParapetDoorWall_*）。天台外墙已连成整圈，恒为 0。
		"outer_doorway_wall_count": _outer_doorway_wall_count,
		# 外立面（= 99F 那圈塔身外墙的可视件）。99F 非 0，100F 天台与其余层为 0。
		"outer_facade_owned": _uses_facade_outer_modules(),
		"outer_facade_solid_count": _outer_facade_solid_count,
		"outer_facade_window_count": _outer_facade_window_count,
		"outer_facade_batch_counts": _outer_facade_batch_counts(),
		"outer_facade_module_count": (
			_outer_facade_solid_count + _outer_facade_window_count
		),
		"outer_facade_slot_count": _outer_facade_slot_transforms.size(),
		# 立面件的竖直口径：底面贴**本层楼面**（FACADE_OUTER_BOTTOM_Y = 0），顶面
		# = 本层楼面 + 11.90m（见两个批次网格的 AABB）。世界标高由本 stage 的
		# position.y 决定 —— 塔楼里 99F 在 y=-12，于是立面世界区间 y[-12, -0.1]，
		# 与旧「天台立面环低一整层」逐值相同，只是参照系从天台换成了 99F。
		"outer_facade_bottom_y": (
			FACADE_OUTER_BOTTOM_Y if _uses_facade_outer_modules() else 0.0
		),
		"outer_facade_thickness": (
			FACADE_OUTER_THICKNESS if _uses_facade_outer_modules() else 0.0
		),
		"outer_damage_seed": _outer_damage_seed,
		"outer_damage_counts": _outer_damage_counts.duplicate(),
		"outer_damage_batch_counts": _outer_damage_batch_counts(),
		"support_rect_count": _support_rect_count,
		"stair_hole_sides": stair_hole_sides.duplicate(),
		"additional_visual_hole_count": additional_visual_holes.size(),
		"additional_visual_hole_tile_count": _additional_visual_hole_tile_count,
		"shell_visible": _shell_visible,
		"floor_visible": _floor_visible,
		"outer_visible": _outer_visible,
		"protected_floor_patch_enabled": _protected_floor_patch_enabled,
		"protected_floor_patch_visible": (
			_protected_floor_patch_enabled and not _floor_visible
		),
		"protected_floor_patch_grid_center": _protected_floor_patch_grid_center,
		"protected_floor_patch_tile_count": _protected_floor_patch_tile_count,
		"protected_floor_patch_side_m": PROTECTED_FLOOR_PATCH_SIDE_M,
		"protected_floor_patch_tiles_per_side": PROTECTED_FLOOR_PATCH_TILES_PER_SIDE,
		"protected_floor_patch_casts_shadow": (
			_protected_floor_visual_light != null
			and _protected_floor_visual_dark != null
			and _protected_floor_visual_light.cast_shadow
				== GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			and _protected_floor_visual_dark.cast_shadow
				== GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		),
		"support_collision_persistent": (
			_support_root != null
			and _support_root.process_mode == Node.PROCESS_MODE_ALWAYS
			and _enabled_collision_shape_count(_support_root) > 0
		),
		"support_process_mode_always": (
			_support_root != null
			and _support_root.process_mode == Node.PROCESS_MODE_ALWAYS
		),
		"uses_imported_floor_mesh": _floor_visual_light != null and _floor_visual_light.multimesh != null,
		"uses_imported_outer_mesh": _outer_visual != null and _outer_visual.multimesh != null,
		"uses_formal_rooftop_art": _rooftop_art_instance != null,
		"formal_rooftop_art_version": (
			str(_rooftop_art_instance.get_meta("version", ""))
			if _rooftop_art_instance != null else ""
		),
			"formal_rooftop_art_blocker_count": _rooftop_art_blocker_count,
		# 逐件碰撞策略的实测结果（业主「花盆和花圃没有阻挡」）：blocking 件数，
		# 以及它们在 FormalRooftopFacilities 子树里实际生成的启用碰撞形状数（应相等）。
		"rooftop_blocking_collision_count": _rooftop_blocking_collision_count,
		"rooftop_blocking_shape_count": (
			_enabled_collision_shape_count(_rooftop_art_instance)
			if _rooftop_art_instance != null else 0
		),
		"checkerboard_pattern": true,
		"force_standard_map": force_standard_map,
		"has_content_bounds": _has_content_bounds,
		"content_world_rect": content_world_rect if _has_content_bounds else Rect2(),
		"outer_visual_scale_y": _outer_visual_scale_y,
		"base_99_100_atrium_enabled": _uses_rooftop_profile(),
		"base_99_100_atrium_tile_count": BASE_99_100_ATRIUM_TILE_COUNT if _uses_rooftop_profile() else 0,
		"base_99_100_atrium_world_rect": BASE_99_100_ATRIUM_WORLD_RECT if _uses_rooftop_profile() else Rect2(),
	}


func _floor_grid_count() -> int:
	return _floor_grid_dimensions().x


## 只有「真正的 100F 天台」才使用窄轮廓；远征单层关卡强制走标准 250×250 网格。
## ⚠️ 本判据自 2026-09-22 起**只**决定「天台专属渲染」（正式地砖 / 女儿墙组件 / 装饰
## 布局 / 基地上空开口），**不再**决定壳体平面尺寸 —— 壳体已由 _uses_tower_shell_rect()
## 统管三层。
func _uses_rooftop_profile() -> bool:
	return floor_index == 0 and not force_standard_map


## 是否使用「塔楼统一壳体平面」（98F / 99F / 100F 同矩形，见 TOWER_SHELL_*）。
##
## `configure()` 的第 5 参 use_standard_map 落成 force_standard_map：塔楼三层传 false、
## 远征单层关卡传 true。所以这条判据等价于「是不是塔楼」——远征仍按内容外框/250 标准图，
## 与本次改动前逐值一致（改动前天台走 ROOFTOP_WORLD_RECT、99F 走 250/160、其余走 250）。
func _uses_tower_shell_rect() -> bool:
	return not force_standard_map


func _floor_grid_dimensions() -> Vector2i:
	if _uses_tower_shell_rect():
		return TOWER_SHELL_GRID_DIMENSIONS
	if _has_content_bounds:
		return Vector2i(
			int(round(content_world_rect.size.x / GRID_UNIT)),
			int(round(content_world_rect.size.y / GRID_UNIT))
		)
	return Vector2i(GRID_COUNT, GRID_COUNT)


func _floor_map_size() -> float:
	return _floor_map_dimensions().x


func _floor_map_dimensions() -> Vector2:
	return _floor_world_rect().size


func _floor_world_rect() -> Rect2:
	if _uses_tower_shell_rect():
		return TOWER_SHELL_WORLD_RECT
	if _has_content_bounds:
		return content_world_rect
	return Rect2(-MAP_HALF, -MAP_HALF, MAP_SIZE, MAP_SIZE)


func _outer_grid_count() -> int:
	return _outer_grid_dimensions().x


func _outer_grid_dimensions() -> Vector2i:
	if _uses_tower_shell_rect():
		return TOWER_SHELL_GRID_DIMENSIONS
	if _has_content_bounds:
		# 独立单层关卡：外墙贴着内容外框走，不套塔楼的整块 250×250。
		return _floor_grid_dimensions()
	return Vector2i(GRID_COUNT, GRID_COUNT)


func _outer_map_size() -> float:
	return _outer_map_dimensions().x


func _outer_map_dimensions() -> Vector2:
	return _outer_world_rect().size


func _outer_world_rect() -> Rect2:
	if _uses_tower_shell_rect():
		return TOWER_SHELL_WORLD_RECT
	if _has_content_bounds:
		return content_world_rect
	return Rect2(-MAP_HALF, -MAP_HALF, MAP_SIZE, MAP_SIZE)


func _outer_wall_height() -> float:
	return (
		ROOFTOP_PARAPET_HEIGHT if _uses_rooftop_profile() else TowerGeometry3D.WALL_LOGICAL_HEIGHT_M
	)


## 是否使用天台参考组件库 v002 的女儿墙模块（0.50m 厚 + 四角 2.5m 转角件）。
## 判据刻意与 _build_outer_shell 里 PARAPET_SCENE 的选择口径一致（floor_kind），
## 这样「用哪套模块」和「按几米内缩边界」永远同步。远征层 kind 是 combat，不含在内。
func _uses_rooftop_parapet_modules() -> bool:
	return floor_kind == "rooftop"


## 外墙直段是否改用「立面组件库」（prp_rooftop_facade_solid / window_5m）。
##
## 2026-09-22 业主口径：99F 外墙改成与天台原本那圈外立面**同一套资源**，同时把
## 天台那圈整圈删掉 —— 三层壳体统一成 100×80 后，两套墙落到同一圈轮廓、同一竖向
## 层带，四面共面（实测 99F 62 槽中 58 槽与天台立面环同位，见 FACADE_OUTER_* 注释）。
##
## 判据 = 塔楼壳体口径下的基地层。远征单层关卡 kind 是 combat（且 floor_index==0），
## 不参与；98F 战斗层用 prp_tower_wall_solid_5m、100F 天台用女儿墙 + 2.5m 转角件，
## 两者各用自己那套，都不走立面件。
func _uses_facade_outer_modules() -> bool:
	return floor_kind == "facility" and _uses_tower_shell_rect()


## 外墙模块厚度：天台 0.50m（组件库 v002），其余层沿用 0.30m。
func _outer_wall_thickness() -> float:
	return ROOFTOP_PARAPET_THICKNESS if _uses_rooftop_parapet_modules() else WALL_THICKNESS


## 外墙中心线相对包络矩形的内缩量（= 模块厚度的一半）。
func _outer_wall_inset() -> float:
	return _outer_wall_thickness() * 0.5


## 一条边上的直段数量。天台两端各让出转角件长度，因此比格数少一段。
func _outer_segment_count(side_length_in_grids: int) -> int:
	if _uses_rooftop_parapet_modules():
		return side_length_in_grids - 1
	return side_length_in_grids


## 整圈直段总数（不含转角件）。
func _outer_segment_total() -> int:
	var dimensions := _outer_grid_dimensions()
	return 2 * (
		_outer_segment_count(dimensions.x) + _outer_segment_count(dimensions.y)
	)


## 外墙直段沿边方向的中心坐标。天台从让位区之后起算，其余层从矩形起点起算。
func _outer_segment_along(rect_start: float, index: int) -> float:
	if _uses_rooftop_parapet_modules():
		return rect_start + ROOFTOP_CORNER_ARM_M + GRID_UNIT * (float(index) + 0.5)
	return rect_start + GRID_UNIT * (float(index) + 0.5)


func _enabled_collision_shape_count(root: Node) -> int:
	var count := 0
	if root is CollisionShape3D and not (root as CollisionShape3D).disabled:
		count += 1
	for child in root.get_children():
		count += _enabled_collision_shape_count(child)
	return count


func _build_floor() -> void:
	# 100F 天台换用天台参考组件库 v002 的正式地砖（ENV-ROOFTOP-REF-FLOOR-FULL）。
	# 98F 与天台历史上共用「抛光地砖」，天台换件后 98F 保持原样不动。
	var uses_rooftop_floor := _uses_rooftop_profile()
	var polished := floor_index in [0, 2] and not uses_rooftop_floor
	var floor_scene := (
		ROOFTOP_FLOOR_SCENE
		if uses_rooftop_floor
		else POLISHED_FLOOR_SCENE
		if polished
		else FLOOR_SCENE
	)
	var mesh := _mesh_from_scene(floor_scene)
	if mesh == null:
		push_error("Tower floor module GLB has no MeshInstance3D")
		return
	# 正式地砖 GLB 自带双表面 PaletteUV；只有旧占位地砖才需要暖色 A/B 主题材质。
	var uses_authored_palette := polished or _scene_preserves_authored_palette(floor_scene)
	# 可视顶面必须与承重面 Y=0 重合。天台正式地砖是「底面中心」原点（顶面在 AABB
	# 顶端），要下沉整板厚；旧砖/抛光砖是「几何中心」原点，下沉半板厚即可。
	# 两条口径分开写，避免无谓改动旧层的槽位相位。
	var floor_visual_y := -FLOOR_THICKNESS * 0.5
	if uses_rooftop_floor:
		floor_visual_y = _floor_visual_origin_y(mesh)
	# 国际象棋棋盘式地砖：按 (x_index + z_index) % 2 分流到浅/深两套 MultiMesh。
	var light_transforms: Array[Transform3D] = []
	var dark_transforms: Array[Transform3D] = []
	var base_holes := _base_visual_hole_rects()
	var extra_holes := _additional_visual_hole_rects()
	var grid_dimensions := _floor_grid_dimensions()
	var floor_rect := _floor_world_rect()
	_additional_visual_hole_tile_count = 0
	for z_index in range(grid_dimensions.y):
		for x_index in range(grid_dimensions.x):
			var point := Vector2i(x_index, z_index)
			if _point_in_hole_rects(base_holes, point):
				continue
			if _point_in_hole_rects(extra_holes, point):
				# 房间自带正式地砖顶掉通用砖：只减少可视覆盖，承重碰撞不受影响。
				_additional_visual_hole_tile_count += 1
				continue
			var x := floor_rect.position.x + GRID_UNIT * (float(x_index) + 0.5)
			var z := floor_rect.position.y + GRID_UNIT * (float(z_index) + 0.5)
			var transform := Transform3D(
				Basis.IDENTITY,
				Vector3(x, floor_visual_y, z)
			)
			if (x_index + z_index) % 2 == 0:
				light_transforms.append(transform)
			else:
				dark_transforms.append(transform)
	_floor_visual_light = _create_floor_multimesh(
		"ImportedFloorTileGrid5M_A", mesh, light_transforms, null if uses_authored_palette else FLOOR_TILE_MATERIAL_A
	)
	add_child(_floor_visual_light)
	_floor_visual_dark = _create_floor_multimesh(
		"ImportedFloorTileGrid5M_B", mesh, dark_transforms, null if uses_authored_palette else FLOOR_TILE_MATERIAL_B
	)
	add_child(_floor_visual_dark)
	var empty_transforms: Array[Transform3D] = []
	_protected_floor_visual_light = _create_floor_multimesh(
		"ProtectedFloorPatch5M_A", mesh, empty_transforms, null if uses_authored_palette else FLOOR_TILE_MATERIAL_A
	)
	_protected_floor_visual_light.visible = false
	add_child(_protected_floor_visual_light)
	_protected_floor_visual_dark = _create_floor_multimesh(
		"ProtectedFloorPatch5M_B", mesh, empty_transforms, null if uses_authored_palette else FLOOR_TILE_MATERIAL_B
	)
	_protected_floor_visual_dark.visible = false
	add_child(_protected_floor_visual_dark)
	_tile_count = light_transforms.size() + dark_transforms.size()


## 地砖可视件的摆放 Y：把模块的**可视顶面**对齐承重面 Y=0。
##   底面中心原点（天台正式地砖，AABB Y=0..0.30）→ 顶面在 AABB 顶端，下沉整板厚；
##   几何中心原点（旧占位砖 / 抛光砖，AABB Y≈-0.15..+0.15）→ 顶面在 +0.15，
## ⚠️ 旧占位砖/抛光砖**刻意不走本函数**：它们走上面的固定 -FLOOR_THICKNESS*0.5。
##   原因：ENV-TOWER-FLOOR-TILE-5M 自 v003 起走反共面阶梯，装饰件顶面抬到 +0.1540，
##   AABB.end.y 比行走面锚点 +0.1500 高 4mm。若把这两类旧件也接到本函数，
##   整层地砖会整体下沉 4mm（不再只差 0.5mm）。要改口径必须同时改锚点契约。
## 之所以做成函数：换地砖件时不必再人肉去改一个魔数。
func _floor_visual_origin_y(mesh: Mesh) -> float:
	if mesh == null:
		return -FLOOR_THICKNESS * 0.5
	return -mesh.get_aabb().end.y


## 模块 Prefab 由资产侧声明是否保留自带材质（preserve_authored_palette）。
## 按场景路径缓存，避免每层重复实例化 Prefab；不同地砖件各有各的声明，
## 不再共用一个全局布尔（天台砖与抛光砖的声明是不同的）。
func _scene_preserves_authored_palette(scene: PackedScene) -> bool:
	if scene == null:
		return false
	var key := scene.resource_path
	if _palette_preserve_cache.has(key):
		return bool(_palette_preserve_cache[key])
	var probe := scene.instantiate()
	var preserved := bool(probe.get_meta("preserve_authored_palette", false))
	probe.free()
	_palette_preserve_cache[key] = preserved
	return preserved


func _rebuild_protected_floor_patch(grid_center: Vector2i) -> void:
	_protected_floor_patch_grid_center = grid_center
	var light_transforms: Array[Transform3D] = []
	var dark_transforms: Array[Transform3D] = []
	var holes := _floor_visual_hole_rects()
	var patch_start_offset := -int(PROTECTED_FLOOR_PATCH_TILES_PER_SIDE / 2)
	var patch_end_offset := patch_start_offset + PROTECTED_FLOOR_PATCH_TILES_PER_SIDE
	var grid_dimensions := _floor_grid_dimensions()
	var floor_rect := _floor_world_rect()
	for z_index in range(grid_center.y + patch_start_offset, grid_center.y + patch_end_offset):
		if z_index < 0 or z_index >= grid_dimensions.y:
			continue
		for x_index in range(grid_center.x + patch_start_offset, grid_center.x + patch_end_offset):
			if x_index < 0 or x_index >= grid_dimensions.x:
				continue
			var point := Vector2i(x_index, z_index)
			var skipped := false
			for hole in holes:
				if (hole as Rect2i).has_point(point):
					skipped = true
					break
			if skipped:
				continue
			var transform := Transform3D(
				Basis.IDENTITY,
				Vector3(
					floor_rect.position.x + GRID_UNIT * (float(x_index) + 0.5),
					-FLOOR_THICKNESS * 0.5,
					floor_rect.position.y + GRID_UNIT * (float(z_index) + 0.5)
				)
			)
			if (x_index + z_index) % 2 == 0:
				light_transforms.append(transform)
			else:
				dark_transforms.append(transform)
	_update_floor_multimesh_transforms(_protected_floor_visual_light, light_transforms)
	_update_floor_multimesh_transforms(_protected_floor_visual_dark, dark_transforms)
	_protected_floor_patch_tile_count = light_transforms.size() + dark_transforms.size()


func _update_floor_multimesh_transforms(
	visual: MultiMeshInstance3D, transforms: Array[Transform3D]
) -> void:
	if visual == null or visual.multimesh == null:
		return
	visual.multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		visual.multimesh.set_instance_transform(index, transforms[index])


func _apply_protected_floor_patch_visibility() -> void:
	var patch_visible := _protected_floor_patch_enabled and not _floor_visible
	if _protected_floor_visual_light != null:
		_protected_floor_visual_light.visible = patch_visible
	if _protected_floor_visual_dark != null:
		_protected_floor_visual_dark.visible = patch_visible


func _create_floor_multimesh(
	node_name: String, mesh: Mesh, transforms: Array[Transform3D], material: StandardMaterial3D
) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var visual := MultiMeshInstance3D.new()
	visual.name = node_name
	visual.multimesh = multimesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visual.material_override = material
	return visual


func _build_outer_shell() -> void:
	# 99F 的直段改走参考组件库 v002 的外立面件（实墙 / 窗墙两档交替），
	# 与女儿墙/普通墙分开取网格 —— 见 _uses_facade_outer_modules()。
	var uses_facade := _uses_facade_outer_modules()
	var module_scene := PARAPET_SCENE if floor_kind == "rooftop" else WALL_SCENE
	var mesh := _mesh_from_scene(module_scene)
	if mesh == null:
		push_error("Tower outer-wall module GLB has no MeshInstance3D")
		return
	var facade_solid_mesh: Mesh = null
	var facade_window_mesh: Mesh = null
	if uses_facade:
		facade_solid_mesh = _mesh_from_scene(FACADE_OUTER_SOLID_SCENE)
		facade_window_mesh = _mesh_from_scene(FACADE_OUTER_WINDOW_SCENE)
		if facade_solid_mesh == null or facade_window_mesh == null:
			push_error("Outer facade module GLB has no MeshInstance3D")
			return
	# 「用哪套模块」与「按几米内缩边界」是跨函数的隐形契约：模块厚度换了而内缩
	# 口径没跟着换，墙就会与楼板边缘错台。留一条会失败的断言盯住这对判据。
	assert(
		_uses_rooftop_parapet_modules() == (floor_kind == "rooftop"),
		"天台女儿墙模块判据与 PARAPET_SCENE 选择口径漂移"
	)
	# 楼梯口门洞：跳过门洞位置的实墙模块，碰撞盒也留缺口。
	# 楼顶额外在缺口处摆放带门墙预制体（5m 宽组件含 2m 宽门洞），可通行。
	var transforms: Array[Transform3D] = []
	# 与 transforms 逐下标对应的「侧内网格序号」。99F 立面件的「实/窗/窗」节奏按它取相位
	# （侧内自最小坐标端起算，与参考拼装同一口径），所以四角让位、东侧门洞缺口都只是
	# 少摆几件，不会把后面的节奏挤偏。
	var slot_grid_indices: Array[int] = []
	var outer_grid_dimensions := _outer_grid_dimensions()
	var outer_rect := _outer_world_rect()
	var outer_max := outer_rect.end
	var wall_height := _outer_wall_height()
	var wall_inset := _outer_wall_inset()
	var segment_count_x := _outer_segment_count(outer_grid_dimensions.x)
	var segment_count_y := _outer_segment_count(outer_grid_dimensions.y)
	# 直接取真实摆放用的缩放值回填快照字段，避免与 _outer_visual_transform 各写一份。
	_outer_visual_scale_y = _outer_visual_transform(
		Basis.IDENTITY, Vector3.ZERO
	).basis.get_scale().y
	# 普通墙与女儿墙的正式 GLB 均以底面中心为原点；按包围盒底面贴合楼面
	# （旧占位 BoxMesh 以几何中心为原点，同一表达式也能得出原中心高度）。
	# 天台女儿墙为真尺寸 1.80m，不再有历史上的 0.5 纵向缩放补偿。
	var visual_wall_center_y := -mesh.get_aabb().position.y
	# 立面件与普通墙是同一套包络与原点契约（5.00×11.90×0.30，底面中心，默认 +Z），
	# 所以两者可以逐槽位互换、槽位表完全不用改；Y 仍各按自己的 AABB 求，
	# 任一件日后改包络也不会让整环上下错缝。
	var facade_solid_y := visual_wall_center_y
	var facade_window_y := visual_wall_center_y
	if uses_facade:
		facade_solid_y = -facade_solid_mesh.get_aabb().position.y
		facade_window_y = -facade_window_mesh.get_aabb().position.y
	var north_boundary := outer_rect.position.y + wall_inset
	var south_boundary := outer_max.y - wall_inset
	var west_boundary := outer_rect.position.x + wall_inset
	var east_boundary := outer_max.x - wall_inset
	var door_transforms: Dictionary = {"north": [], "south": [], "west": [], "east": []}
	for index in range(segment_count_x):
		var offset_x := _outer_segment_along(outer_rect.position.x, index)
		var is_outer_corner_segment := floor_index == 1 and index in [0, segment_count_x - 1]
		if _is_in_wall_door_gap("north", index):
			door_transforms["north"].append(Transform3D(Basis.IDENTITY, Vector3(offset_x, 0.0, north_boundary)))
		elif not is_outer_corner_segment:
			transforms.append(_outer_visual_transform(Basis.IDENTITY, Vector3(offset_x, visual_wall_center_y, north_boundary)))
			slot_grid_indices.append(index)
		if _is_in_wall_door_gap("south", index):
			door_transforms["south"].append(Transform3D(Basis(Vector3.UP, PI), Vector3(offset_x, 0.0, south_boundary)))
		elif not is_outer_corner_segment:
			transforms.append(_outer_visual_transform(Basis(Vector3.UP, PI), Vector3(offset_x, visual_wall_center_y, south_boundary)))
			slot_grid_indices.append(index)
	for index in range(segment_count_y):
		var offset_z := _outer_segment_along(outer_rect.position.y, index)
		var is_outer_corner_segment := floor_index == 1 and index in [0, segment_count_y - 1]
		if _is_in_wall_door_gap("west", index):
			door_transforms["west"].append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(west_boundary, 0.0, offset_z)))
		elif not is_outer_corner_segment:
			transforms.append(_outer_visual_transform(Basis(Vector3.UP, PI * 0.5), Vector3(west_boundary, visual_wall_center_y, offset_z)))
			slot_grid_indices.append(index)
		if _is_in_wall_door_gap("east", index):
			door_transforms["east"].append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(east_boundary, 0.0, offset_z)))
		elif not is_outer_corner_segment:
			transforms.append(_outer_visual_transform(Basis(Vector3.UP, -PI * 0.5), Vector3(east_boundary, visual_wall_center_y, offset_z)))
			slot_grid_indices.append(index)
	# 99F：直段改走参考组件库 v002 的外立面件 —— 按「侧内网格序号 % 3」的节奏分流成
	# 实墙 / 窗墙两批（与天台参考拼装同相位）。立面件与普通墙包络逐值相同，所以槽位表
	# 不变，只是换件 + 换竖向基准；四角 L 件与东侧门洞缺口照旧由上面的循环让位。
	var facade_solid_transforms: Array[Transform3D] = []
	var facade_window_transforms: Array[Transform3D] = []
	if uses_facade:
		for slot_index in range(transforms.size()):
			var facade_slot := transforms[slot_index]
			var use_solid_slot := (
				int(slot_grid_indices[slot_index]) % FACADE_OUTER_SOLID_EVERY == 0
			)
			facade_slot.origin.y = facade_solid_y if use_solid_slot else facade_window_y
			transforms[slot_index] = facade_slot
			_outer_facade_slot_transforms.append(facade_slot)
			if use_solid_slot:
				facade_solid_transforms.append(facade_slot)
				_outer_facade_slot_kinds.append("solid")
			else:
				facade_window_transforms.append(facade_slot)
				_outer_facade_slot_kinds.append("window")
		_outer_facade_solid_count = facade_solid_transforms.size()
		_outer_facade_window_count = facade_window_transforms.size()
	# 先把直段槽位表钉死，再决定每个槽位用哪一档可视件：破损只换外观、不增删槽位，
	# 所以「直段共几段 / 每条边覆盖到哪」与破损比例完全解耦（这也是四个角的让位区、
	# 西侧门洞缺口的宽度能保持不变的原因）。
	_outer_straight_slot_transforms = transforms.duplicate()
	_outer_straight_slot_count = transforms.size()
	var batches := split_outer_parapet_damage(
		transforms, _outer_damage_seed, _uses_rooftop_parapet_modules()
	)
	var planned_counts: Dictionary = batches["counts"]
	_outer_damage_counts = planned_counts
	# 与槽位表逐下标对应的档位表，供门禁/探针在 --headless 下也能读到「哪槽用哪档」。
	var planned_kinds: Array = batches["kinds"]
	_outer_slot_kinds = planned_kinds
	var intact_transforms: Array = batches["intact"]
	if uses_facade:
		# 直段已整批交给立面批次渲染；普通墙批留空（节点仍建，供 uses_imported_outer_mesh
		# 与 set_render_state 沿用既有口径），否则两套墙会在同槽位共面闪面。
		intact_transforms = []
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = intact_transforms.size()
	for index in range(intact_transforms.size()):
		multimesh.set_instance_transform(index, intact_transforms[index] as Transform3D)
	_outer_visual = MultiMeshInstance3D.new()
	_outer_visual.name = "ImportedOuter%sGrid5M" % (
		"Parapet" if floor_kind == "rooftop" else "Wall"
	)
	_outer_visual.multimesh = multimesh
	_outer_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_outer_visual)
	if uses_facade:
		_build_outer_facade_visuals(
			facade_solid_mesh,
			facade_window_mesh,
			facade_solid_transforms,
			facade_window_transforms
		)
	var variant_batches: Array = batches["variants"]
	_install_outer_damage_visuals(variant_batches, mesh)
	if floor_index == 1:
		_install_base99_outer_corner_visuals(
			west_boundary, east_boundary, north_boundary, south_boundary
		)
	# 天台：四角换成 2.5m 转角件，替掉原来两根直段在角上交叉的旧画法。
	if _uses_rooftop_parapet_modules():
		_install_rooftop_outer_corner_visuals(outer_rect)
	# ⚠️ 2026-09-22 业主裁定：原「天台在女儿墙正下方补一整圈外立面」的画法**整圈删除**。
	# 三层壳体统一成 100×80 后，那圈立面与 99F 自己那圈外墙落到同一轮廓、同一竖向层带
	# （实测 99F 62 槽中 58 槽沿轴同位），四面共面 —— 就是 z-fighting 闪面的根因。
	# 现在立面由 99F 自己提供（见 uses_facade 分支），天台只保留女儿墙 + 2.5m 转角件。

	# 楼顶：在每个缺口位置摆带门墙预制体（替代被跳过的实墙模块）。
	# 件数 = 被跳过的直段数，两者共同决定缺口宽度；节点名带序号，避免同名靠
	# Godot 自动去重，门禁才能靠名字稳定取到。
	# ⚠️ 天台已不挖外墙门洞（见 _wall_side_has_door_gap），所以这里件数恒为 0；
	# 保留代码是为了普通层将来仍可能有的楼梯口门洞。
	if _uses_rooftop_parapet_modules():
		var door_scale_y := ROOFTOP_PARAPET_HEIGHT / ROOFTOP_PARAPET_DOOR_BASE_HEIGHT
		var door_index := 0
		for side in door_transforms.keys():
			for door_transform in (door_transforms[side] as Array):
				var door_instance := PARAPET_DOOR_PREFAB.instantiate() as Node3D
				if door_instance == null:
					continue
				door_instance.name = "ParapetDoorWall_%s_%02d" % [side.capitalize(), door_index]
				door_instance.transform = door_transform
				door_instance.scale = Vector3(1.0, door_scale_y, 1.0)
				add_child(door_instance)
				door_index += 1
		_outer_doorway_wall_count = door_index

	# 每一边使用独立碰撞体，避免一个共享 body 让摄像机无法判断命中方向。
	for side in ["north", "south", "west", "east"]:
		var body := StaticBody3D.new()
		body.name = "OuterBoundaryCollision_%s" % side.capitalize()
		# 远层 stage 会停用脚本处理，但永久结构碰撞必须继续服务移动、子弹和
		# 受光射线。显式 ALWAYS 可避免从禁用父节点继承物理停用状态。
		body.process_mode = Node.PROCESS_MODE_ALWAYS
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("camera_lower_wall", side == "south")
		add_child(body)
		_add_wall_collision(body, side, wall_height)


## 纯函数：把直段槽位按「带种子的随机排布」分成 intact + 三档破损。
##
## 做成 static 是为了让门禁能直接对「排布算法」做可复现性对照（同种子必同结果、
## 换种子必换结果、非天台层必整批完好），而不必再建一个完整 stage —— 建 stage 会
## 连带铺满整层地砖与外墙，代价远大于算一次分布。
##
## 只有天台参与破损（enabled=false 时整批走 intact）：三件破损变体是女儿墙专用件，
## 普通层用 `prp_tower_wall_solid_5m`，与它们无关。
## 掷骰顺序 = 槽位顺序，且「是否受损」与「哪一档」是顺序依赖的两次掷骰（未受损时
## 只消耗一个随机数）；改动顺序会换排布，门禁的固定期望值随之失效。
static func split_outer_parapet_damage(
	transforms: Array, seed_value: int, enabled: bool
) -> Dictionary:
	var intact: Array = []
	var variants: Array = [[], [], []]  # 与 PARAPET_DAMAGE_KEYS 同序
	var counts := {"intact": 0, "dmg_a": 0, "dmg_b": 0, "dmg_c": 0}
	# 与 transforms 逐下标对应的档位表（"intact"/"dmg_a"/…）。它让门禁与探针不必从
	# MultiMesh 回读实例变换就能知道「哪个槽位用了哪一档」——MultiMesh 的实例变换
	# 存在 RenderingServer 侧，dummy 渲染器（--headless）下一律回读成单位阵。
	var kinds: Array = []
	if not enabled:
		intact = transforms.duplicate()
		counts["intact"] = transforms.size()
		for _index in range(transforms.size()):
			kinds.append("intact")
		return {"intact": intact, "variants": variants, "counts": counts, "kinds": kinds}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for transform in transforms:
		# 先掷「是否受损」再掷「哪一档」：总受损率 = 0.25，三档各约 1/12。
		if rng.randf() < ROOFTOP_PARAPET_DAMAGE_CHANCE:
			var slot := rng.randi_range(0, PARAPET_DAMAGE_KEYS.size() - 1)
			var key := str(PARAPET_DAMAGE_KEYS[slot])
			variants[slot].append(transform)
			counts[key] = int(counts[key]) + 1
			kinds.append(key)
		else:
			intact.append(transform)
			counts["intact"] = int(counts["intact"]) + 1
			kinds.append("intact")
	return {"intact": intact, "variants": variants, "counts": counts, "kinds": kinds}


## 为三个破损档各建一个 MultiMesh 批次（intact 批次仍由 _outer_visual 承担）。
##
## 关键断言：破损件的包络必须与 intact 件逐值相同。破损只许换外观 —— 一旦包络变了，
## 槽位相位与四角 2.5m 让位区就会错台，而「周长仍无缝 / 间隙为 0」这类覆盖判据是按
## 槽位算的，抓不到「槽位还在、里面的件变大了」这种坏法。
func _install_outer_damage_visuals(variant_batches: Array, intact_mesh: Mesh) -> void:
	_outer_damage_visual.clear()
	if not _uses_rooftop_parapet_modules():
		return
	var intact_aabb := intact_mesh.get_aabb()
	for variant in range(PARAPET_DAMAGE_SCENES.size()):
		var slot_transforms: Array = variant_batches[variant]
		var variant_mesh := _mesh_from_scene(PARAPET_DAMAGE_SCENES[variant] as PackedScene)
		if variant_mesh == null:
			push_error(
				"Rooftop parapet damage variant has no MeshInstance3D: %s"
				% PARAPET_DAMAGE_KEYS[variant]
			)
			continue
		assert(
			variant_mesh.get_aabb().is_equal_approx(intact_aabb),
			"女儿墙破损件 %s 的包络与 intact 件不同，槽位相位会错台" % PARAPET_DAMAGE_KEYS[variant]
		)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = variant_mesh
		multimesh.instance_count = slot_transforms.size()
		for index in range(slot_transforms.size()):
			multimesh.set_instance_transform(index, slot_transforms[index] as Transform3D)
		var visual := MultiMeshInstance3D.new()
		visual.name = "ImportedOuterParapet%sGrid5M" % str(
			PARAPET_DAMAGE_KEYS[variant]
		).to_pascal_case()
		visual.multimesh = multimesh
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(visual)
		_outer_damage_visual.append(visual)


func _install_base99_outer_corner_visuals(
	west_boundary: float, east_boundary: float, north_boundary: float, south_boundary: float
) -> void:
	# The facility stage is 160m wide. Its four visible perimeter corners used
	# to be formed by eight generic straight-wall MultiMesh segments. Replace
	# exactly those segments with the authored 5m L module; boundary collision
	# remains the continuous existing four-side contract below.
	var definitions := [
		{"name": "Base99OuterCorner_NW", "position": Vector3(west_boundary, 0.0, north_boundary), "rotation_y": -PI * 0.5},
		{"name": "Base99OuterCorner_NE", "position": Vector3(east_boundary, 0.0, north_boundary), "rotation_y": PI},
		{"name": "Base99OuterCorner_SW", "position": Vector3(west_boundary, 0.0, south_boundary), "rotation_y": 0.0},
		{"name": "Base99OuterCorner_SE", "position": Vector3(east_boundary, 0.0, south_boundary), "rotation_y": PI * 0.5},
	]
	for definition in definitions:
		var corner := BASE99_CORNER_L_VISUAL.instantiate() as Node3D
		if corner == null:
			push_error("Base99 outer corner GLB instance failed")
			continue
		corner.name = str(definition["name"])
		corner.position = definition["position"] as Vector3
		corner.rotation.y = float(definition["rotation_y"])
		corner.set_meta("asset_id", "ENV-TOWER-CORNER-L-5M")
		corner.set_meta("visual_only", true)
		corner.set_meta("collision_owner", "TowerFloorStage3D.OuterBoundaryCollision")
		add_child(corner)
		_base99_outer_corner_visuals.append(corner)


## 天台四角安装 2.5m 转角件。
## 四角全是阳角（矩形轮廓无内凹），所以只用「女儿墙外角」这一件；
## 转角件包络 2.5×2.5，摆放位置就是「该角 2.5m 让位区的中心」，再按角旋转
## 90° 的整数倍：SW=0、SE=PI/2、NE=PI、NW=3PI/2（俯视逆时针）。
## 转角件自带的两条臂中心线分别在局部 x=-1.0 与 z=+1.0，这套放位正好让两条臂的
## 中心线落在对应边的 boundary 上，包络端点与相邻直段无缝相接。
## 碰撞仍是四边连续体，本函数只产生视觉节点。
func _install_rooftop_outer_corner_visuals(outer_rect: Rect2) -> void:
	var half := ROOFTOP_CORNER_ARM_M * 0.5
	var definitions := [
		{"name": "RooftopOuterCorner_SW", "position": Vector3(outer_rect.position.x + half, 0.0, outer_rect.end.y - half), "rotation_y": 0.0},
		{"name": "RooftopOuterCorner_SE", "position": Vector3(outer_rect.end.x - half, 0.0, outer_rect.end.y - half), "rotation_y": PI * 0.5},
		{"name": "RooftopOuterCorner_NE", "position": Vector3(outer_rect.end.x - half, 0.0, outer_rect.position.y + half), "rotation_y": PI},
		{"name": "RooftopOuterCorner_NW", "position": Vector3(outer_rect.position.x + half, 0.0, outer_rect.position.y + half), "rotation_y": PI * 1.5},
	]
	for definition in definitions:
		var corner := ROOFTOP_CORNER_PREFAB.instantiate() as Node3D
		if corner == null:
			push_error("Rooftop outer corner prefab instance failed")
			continue
		corner.name = str(definition["name"])
		corner.position = definition["position"] as Vector3
		corner.rotation.y = float(definition["rotation_y"])
		corner.set_meta("asset_id", "ENV-ROOFTOP-REF-PARAPET-OUTER")
		corner.set_meta("visual_only", true)
		corner.set_meta("collision_owner", "TowerFloorStage3D.OuterBoundaryCollision")
		add_child(corner)
		_rooftop_outer_corner_visuals.append(corner)


## 99F 外立面（= 从天台边缘往下看到的那圈「塔身外墙」）的两个批渲染件。
##
## 沿革（2026-09-22 业主口径）：这圈立面**原本由 100F 天台**在女儿墙正下方补出来
## （低一整层，见 reference_assembly.json 把 facade_* 摆在 z=-12.00）。三层壳体统一成
## 100×80 后，它与 99F 自己的普通外墙落到同一圈轮廓、同一竖向层带 —— 实测 99F 62 槽中
## 58 槽沿轴同位、四面共面（z-fighting 闪面）。业主裁定：立面改由 **99F 自己**提供
## （同一套 facade_* 资源），天台那圈**整圈删掉**。
##
## 实现口径：立面件（实墙 / 窗墙）与 prp_tower_wall_solid_5m **同包络同原点契约**
## （5.00 × 11.90 × 0.30，底面中心，默认 +Z），所以直接接过 99F 既有的直段槽位 ——
## 四角 L 件（Base99OuterCorner_*）与东侧门洞缺口照旧由 _build_outer_shell 的循环让位，
## 本函数只负责按档分流并批渲染。
##
## 两条隐形契约（与女儿墙一致）：
##   1. 中心线内缩量按模块厚度取（0.30m → 0.15m），外皮贴轮廓矩形；
##   2. 竖直定位按模块自己的 AABB 求（底面中心原点 ⇒ 位置 Y = 楼面 − AABB 底部），
##      顶面 11.90m 落在上层楼板下方 0.10m，与 TowerGeometry3D.WALL_VISUAL_HEIGHT_M
##      同一口径。
##
## ⚠️ 不再有独立的 FacadeBoundaryCollision_*：立面件包络正好落在 99F 既有的
## OuterBoundaryCollision_*（0.30m 厚、本层 y[-12,0]）里、世界同位，由后者接管碰撞。
func _build_outer_facade_visuals(
	solid_mesh: Mesh,
	window_mesh: Mesh,
	solid_transforms: Array[Transform3D],
	window_transforms: Array[Transform3D]
) -> void:
	# 与女儿墙同一套批渲染口径：Prefab 自带 PaletteUV，禁止材质覆盖。
	_outer_facade_solid_visual = _create_floor_multimesh(
		"ImportedOuterFacadeSolidGrid5M", solid_mesh, solid_transforms, null
	)
	add_child(_outer_facade_solid_visual)
	_outer_facade_window_visual = _create_floor_multimesh(
		"ImportedOuterFacadeWindowGrid5M", window_mesh, window_transforms, null
	)
	add_child(_outer_facade_window_visual)


func _outer_visual_transform(basis: Basis, position: Vector3) -> Transform3D:
	# 天台女儿墙已换成参考组件库 v002 的真尺寸 1.80m 模块，不再需要当年
	# 「1.50m 几何 × 0.5 纵向缩放凑 0.75m」的补偿；视觉包络即结构包络。
	# 保留本函数是为了让快照字段 _outer_visual_scale_y 与快照导出共用同一处真源，
	# 它现在对任何层都返回单位缩放（远征层历史上被误缩到半高，这里一并消掉）。
	return Transform3D(basis, position)


## 外墙该侧是否要留楼梯门洞。
##
## 天台例外：楼梯口（_stair_hole_world_rect）整体落在轮廓**内部**，西侧离外墙还有
## 5m 净距，所以「楼梯口 = 外墙门洞」这条旧假设对天台根本不成立。旧代码会在那 5m
## 处的西墙上挖掉 3 段实墙、塞进 3 件**系统占位矮墙**
## (prp_tower_wall_parapet_door_5m，每件带 2m 门洞) —— 从里看就是一段没连起来的
## 栏杆缺口（用户报的问题）。因此天台外墙必须连成整圈：不挖门洞、不放占位矮墙、
## 碰撞也不留缝。
##
## 判定做成「一侧一函数」是为了让**可视跳过**与**碰撞留缝**共用同一处真源 ——
## 这两处历史上就是分别写的（_is_in_wall_door_gap / _add_wall_collision），
## 一改一漏就会变成「看得见墙、却走得出去」的假封口。
func _wall_side_has_door_gap(side: String) -> bool:
	return side in stair_hole_sides and not _uses_rooftop_parapet_modules()


func _is_in_wall_door_gap(side: String, index: int) -> bool:
	if not _wall_side_has_door_gap(side):
		return false
	for hole_side in stair_hole_sides:
		if hole_side != side:
			continue
		var module_pos := _wall_module_position(side, index)
		var hole_center := _stair_hole_center(hole_side)
		var along_axis := module_pos.x if side in ["north", "south"] else module_pos.z
		var hole_along := hole_center.x if side in ["north", "south"] else hole_center.z
		return absf(along_axis - hole_along) <= WALL_DOOR_GAP_HALF_WIDTH
	return false


func _wall_module_position(side: String, index: int) -> Vector3:
	# 必须与 _build_outer_shell 共用 _outer_segment_along / _outer_wall_inset，
	# 否则门洞判定算的是旧排布，实墙却摆在新位置，楼梯口会错位。
	var outer_rect := _outer_world_rect()
	var outer_max := outer_rect.end
	var wall_inset := _outer_wall_inset()
	var offset_x := _outer_segment_along(outer_rect.position.x, index)
	var offset_z := _outer_segment_along(outer_rect.position.y, index)
	var north_boundary := outer_rect.position.y + wall_inset
	var south_boundary := outer_max.y - wall_inset
	var west_boundary := outer_rect.position.x + wall_inset
	var east_boundary := outer_max.x - wall_inset
	match side:
		"north":
			return Vector3(offset_x, 0.0, north_boundary)
		"south":
			return Vector3(offset_x, 0.0, south_boundary)
		"west":
			return Vector3(west_boundary, 0.0, offset_z)
		"east":
			return Vector3(east_boundary, 0.0, offset_z)
	return Vector3.ZERO


func _stair_hole_center(side: String) -> Vector3:
	# 外墙缺口、楼板视觉和承重碰撞必须引用同一个洞口矩形。
	var hole_rect := _stair_hole_world_rect(side)
	return Vector3(
		hole_rect.position.x + hole_rect.size.x * 0.5,
		0.0,
		hole_rect.position.y + hole_rect.size.y * 0.5
	)


func _add_wall_collision(body: StaticBody3D, side: String, height: float) -> void:
	# 碰撞厚度与内缩口径都跟着模块走：天台 0.50m / 其余层 0.30m。
	# 视觉模块换厚度而碰撞不换，玩家就会在外表面之内或之外撞到「空气」。
	var outer_rect := _outer_world_rect()
	var outer_max := outer_rect.end
	var wall_inset := _outer_wall_inset()
	var wall_thickness := _outer_wall_thickness()
	var north_boundary := outer_rect.position.y + wall_inset
	var south_boundary := outer_max.y - wall_inset
	var west_boundary := outer_rect.position.x + wall_inset
	var east_boundary := outer_max.x - wall_inset
	if not _wall_side_has_door_gap(side):
		match side:
			"north":
				_add_box_collision(body, Vector3(outer_rect.get_center().x, height * 0.5, north_boundary), Vector3(outer_rect.size.x, height, wall_thickness))
			"south":
				_add_box_collision(body, Vector3(outer_rect.get_center().x, height * 0.5, south_boundary), Vector3(outer_rect.size.x, height, wall_thickness))
			"west":
				_add_box_collision(body, Vector3(west_boundary, height * 0.5, outer_rect.get_center().y), Vector3(wall_thickness, height, outer_rect.size.y))
			"east":
				_add_box_collision(body, Vector3(east_boundary, height * 0.5, outer_rect.get_center().y), Vector3(wall_thickness, height, outer_rect.size.y))
		return
	var center := _stair_hole_center(side)
	var gap_start := 0.0
	var gap_end := 0.0
	var axis_pos := 0.0
	match side:
		"north":
			gap_start = clampf(center.x - WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.x, outer_max.x)
			gap_end = clampf(center.x + WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.x, outer_max.x)
			axis_pos = north_boundary
		"south":
			gap_start = clampf(center.x - WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.x, outer_max.x)
			gap_end = clampf(center.x + WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.x, outer_max.x)
			axis_pos = south_boundary
		"west":
			gap_start = clampf(center.z - WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.y, outer_max.y)
			gap_end = clampf(center.z + WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.y, outer_max.y)
			axis_pos = west_boundary
		"east":
			gap_start = clampf(center.z - WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.y, outer_max.y)
			gap_end = clampf(center.z + WALL_DOOR_GAP_HALF_WIDTH, outer_rect.position.y, outer_max.y)
			axis_pos = east_boundary
	match side:
		"north", "south":
			var left_size := gap_start - outer_rect.position.x
			var right_size := outer_max.x - gap_end
			if left_size > 0.01:
				_add_box_collision(
					body,
					Vector3(outer_rect.position.x + left_size * 0.5, height * 0.5, axis_pos),
					Vector3(left_size, height, wall_thickness)
				)
			if right_size > 0.01:
				_add_box_collision(
					body,
					Vector3(gap_end + right_size * 0.5, height * 0.5, axis_pos),
					Vector3(right_size, height, wall_thickness)
				)
		"west", "east":
			var left_size := gap_start - outer_rect.position.y
			var right_size := outer_max.y - gap_end
			if left_size > 0.01:
				_add_box_collision(
					body,
					Vector3(axis_pos, height * 0.5, outer_rect.position.y + left_size * 0.5),
					Vector3(wall_thickness, height, left_size)
				)
			if right_size > 0.01:
				_add_box_collision(
					body,
					Vector3(axis_pos, height * 0.5, gap_end + right_size * 0.5),
					Vector3(wall_thickness, height, right_size)
				)


func _add_box_collision(body: StaticBody3D, position: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.position = position
	collision.shape = shape
	body.add_child(collision)


func _build_support() -> void:
	_support_root = StaticBody3D.new()
	_support_root.name = "FloorSupport"
	# 楼板是跨层太阳遮挡体，不能随当前楼层的处理窗口退出物理空间。
	_support_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_support_root.collision_layer = 1
	_support_root.collision_mask = 0
	add_child(_support_root)
	var grid_dimensions := _floor_grid_dimensions()
	var floor_rect := _floor_world_rect()
	var rectangles: Array[Rect2i] = [Rect2i(Vector2i.ZERO, grid_dimensions)]
	for hole in _hole_rects():
		rectangles = _subtract_hole(rectangles, hole)
	for rect in rectangles:
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		var shape := BoxShape3D.new()
		shape.size = Vector3(
			float(rect.size.x) * GRID_UNIT,
			FLOOR_THICKNESS,
			float(rect.size.y) * GRID_UNIT
		)
		var collision := CollisionShape3D.new()
		collision.name = "SupportRect_%02d" % _support_rect_count
		collision.position = Vector3(
			floor_rect.position.x + (float(rect.position.x) + float(rect.size.x) * 0.5) * GRID_UNIT,
			-FLOOR_THICKNESS * 0.5,
			floor_rect.position.y + (float(rect.position.y) + float(rect.size.y) * 0.5) * GRID_UNIT
		)
		collision.shape = shape
		_support_root.add_child(collision)
		_support_rect_count += 1


func _hole_rects() -> Array[Rect2i]:
	var holes: Array[Rect2i] = []
	# 100层与99层基地打通：只从100层(stage 0)移除基地上方6×6地砖，
	# 99层自身的36块地面仍由基地房间保留。
	# 远征单层关卡没有「下方 99F 基地」，挖洞只会让入口安全房悬空。
	if _uses_rooftop_profile():
		holes.append(_world_rect_to_grid(BASE_99_100_ATRIUM_WORLD_RECT))
	for side in stair_hole_sides:
		holes.append_array(_stair_hole_grid_pieces(side))
	return holes


## 楼梯井洞口扣除「承重保底足迹」（support_keep_out_rects）后剩下的栅格矩形。
## 足迹压不到洞口时结果 == 原矩形（标准塔楼逐值不变）；压到时就只挖掉房外那一段。
func _stair_hole_grid_pieces(side: String) -> Array[Rect2i]:
	var pieces: Array[Rect2i] = [_world_rect_to_grid(_stair_hole_world_rect(side))]
	for keep_out in support_keep_out_rects:
		var keep := _world_rect_to_grid(keep_out)
		var remainder: Array[Rect2i] = []
		for piece in pieces:
			remainder.append_array(_subtract_hole([piece], keep))
		pieces = remainder
	var kept: Array[Rect2i] = []
	for piece in pieces:
		if piece.size.x > 0 and piece.size.y > 0:
			kept.append(piece)
	return kept


func _floor_visual_hole_rects() -> Array[Rect2i]:
	var holes := _base_visual_hole_rects()
	holes.append_array(_additional_visual_hole_rects())
	return holes


## 结构/通用美术本来就要留的洞：楼梯口，以及 99F 与 100F 的贯通中庭。
func _base_visual_hole_rects() -> Array[Rect2i]:
	var holes := _hole_rects()
	# 99F的承重面仍由完整FloorSupport负责；这里只从通用可视地砖中挖出
	# 基地地板区域，避免与两套正式基地地砖在Y=0处重叠闪烁。
	if floor_index == 1:
		holes.append(_world_rect_to_grid(BASE_99_100_ATRIUM_WORLD_RECT))
	return holes


## 房间自带的正式地砖（入口安全房 v007）与通用地砖都在 Y=0 共面，必须挖洞让位。
func _additional_visual_hole_rects() -> Array[Rect2i]:
	var holes: Array[Rect2i] = []
	for extra_rect in additional_visual_holes:
		holes.append(_world_rect_to_grid(extra_rect))
	return holes


func _point_in_hole_rects(holes: Array[Rect2i], point: Vector2i) -> bool:
	for hole in holes:
		if hole.has_point(point):
			return true
	return false


func _stair_hole_world_rect(side: String) -> Rect2:
	# 两条楼梯跑道的外廓按 5m 单元取整，边界全部落在整格线上。
	match side:
		"west":
			return Rect2(-45.0, 0.0, 15.0, 30.0)
		"east":
			return Rect2(35.0, -25.0, 15.0, 30.0)
		"north":
			return Rect2(-25.0, -45.0, 30.0, 15.0)
		"south":
			return Rect2(0.0, 35.0, 30.0, 15.0)
	return Rect2()


func _world_rect_to_grid(world_rect: Rect2) -> Rect2i:
	var floor_rect := _floor_world_rect()
	return Rect2i(
		int(round((world_rect.position.x - floor_rect.position.x) / GRID_UNIT)),
		int(round((world_rect.position.y - floor_rect.position.y) / GRID_UNIT)),
		int(round(world_rect.size.x / GRID_UNIT)),
		int(round(world_rect.size.y / GRID_UNIT))
	)


func _subtract_hole(rectangles: Array[Rect2i], hole: Rect2i) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for rect in rectangles:
		var overlap := rect.intersection(hole)
		if overlap.size.x <= 0 or overlap.size.y <= 0:
			result.append(rect)
			continue
		var rect_end := rect.end
		var overlap_end := overlap.end
		if overlap.position.x > rect.position.x:
			result.append(Rect2i(
				rect.position.x,
				rect.position.y,
				overlap.position.x - rect.position.x,
				rect.size.y
			))
		if overlap_end.x < rect_end.x:
			result.append(Rect2i(
				overlap_end.x,
				rect.position.y,
				rect_end.x - overlap_end.x,
				rect.size.y
			))
		if overlap.position.y > rect.position.y:
			result.append(Rect2i(
				overlap.position.x,
				rect.position.y,
				overlap.size.x,
				overlap.position.y - rect.position.y
			))
		if overlap_end.y < rect_end.y:
			result.append(Rect2i(
				overlap.position.x,
				overlap_end.y,
				overlap.size.x,
				rect_end.y - overlap_end.y
			))
	return result


## 从模块 Prefab 取「用于批渲染的单一 Mesh 资源」。
## 走 TowerGeometry3D 的唯一解析入口（按 metadata/visual_node_name 声明），
## 不再本地递归取第一个 MeshInstance3D —— 那个隐式约定在带门墙这类
## 「首个网格是被隐藏的门扇」的资产上会取错。
func _mesh_from_scene(scene: PackedScene) -> Mesh:
	if scene == null:
		return null
	var instance := scene.instantiate()
	var mesh := TowerGeometry3D.resolve_visual_mesh(instance)
	instance.free()
	return mesh
