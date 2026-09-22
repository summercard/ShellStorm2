class_name DungeonRoom3D
extends Node3D
## 3D 房间构造器：房型、大小、门、家具、搜索点、服务点和灯具都通过配置组合。
## 几何全部由 prefab .tscn 提供；脚本只做"找 prefab → 实例化 → 设位置/缩放/材质"。

signal player_entered(room: DungeonRoom3D)
signal prop_searched(room: DungeonRoom3D, loot: Dictionary)
signal service_activated(room: DungeonRoom3D, station: ServiceStation3D)
## 灯开关被玩家切换后上行一层。与 player_entered / service_activated 同一模式：
## 房间不自己决定"开灯后要发生什么"，只负责把事实告诉上层。
signal light_toggled(room: DungeonRoom3D, is_on: bool)

const LIGHT_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_wasteland_light_root_top3d.tscn")
const LIGHT_SWITCH_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_light_switch_root_top3d.tscn")
const FURNITURE_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_furniture_root_top3d.tscn")
const SEARCH_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_search_container_root_top3d.tscn")
const SERVICE_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_service_station_root_top3d.tscn")
const HAZARD_SCENE: PackedScene = preload("res://assets/art/vfx/environment_3d/vfx_hazard_field_root_top3d.tscn")
const DOOR_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_door_3d.tscn")
const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")

# —— 5m 塔楼模块 prefab（A 节）
const TOWER_WALL_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn"
)
const TOWER_DOOR_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn"
)
# 5m 段门扇（门板）视觉：塔楼 A 套正式美术，与门墙共用 forward_axis=+Z。
# 由战局通用组件库的「door_5m_通用包」派生而来，脚本与清单见
# tower_descent_3d/source/door_leaf_5m/。战斗房与入口安全房共用它。
# 门扇在厚度轴上镜面对称，故 A 套（+Z）与旧 B 套（-Z）互换外观不变。
const TOWER_DOOR_LEAF_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_door_leaf_5m.tscn"
)
const TOWER_PARAPET_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_5m.tscn"
)
const TOWER_PARAPET_DOOR_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_wall_parapet_door_5m.tscn"
)
# 4 拐角模块
const TOWER_CORNER_L_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_corner_l_5m.tscn"
)
const BASE99_CORNER_L_PREFAB: PackedScene = preload(
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/env_base99_corner_l_5m_collision_top3d.tscn"
)
const TOWER_CORNER_T_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_corner_t_5m.tscn"
)
const TOWER_CORNER_X_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_corner_x_5m.tscn"
)
const TOWER_CORNER_L_PARAPET_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_corner_l_parapet_5m.tscn"
)
const TOWER_FLOOR_TILE_PREFAB: PackedScene = preload(
	"res://assets/art/props/dungeon_3d/prp_tower_floor_tile_5m.tscn"
)
# 基地99层专属普通墙视觉。该PackedScene/GLB不持有碰撞、门或交互逻辑；
# 结构碰撞继续由本脚本的0.30m代理负责，避免美术替换影响玩法。
const BASE99_WALL_PLAIN_PREFAB: PackedScene = preload(
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_plain_5x12/env_base99_wall_plain_5x12_root_top3d.tscn"
)
const BASE99_FLOOR_PLAIN_PREFAB: PackedScene = preload(
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_floor_plain_5m/env_base99_floor_plain_5m_root_top3d.tscn"
)
const BASE99_FLOOR_RIVET_PREFAB: PackedScene = preload(
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_floor_rivet_5m/env_base99_floor_rivet_5m_root_top3d.tscn"
)
const BASE99_WALL_DOOR_PREFAB: PackedScene = preload(
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_door_5x12/env_base99_wall_door_5x12_root_top3d.tscn"
)
const BASE99_DOOR_LIFT_PREFAB: PackedScene = preload(
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_root_top3d.tscn"
)
# —— 入口安全房（STAIR_LOBBY）v007 正式美术。
# v007 是「单一方位」布局：南墙与东墙中段各开 2.2×2.5 门洞，其余 10 段为 5m 实墙，
# 地面为 3×3 格棋盘地砖。运行时按本层实际门向把整房旋转 0/90/180/270°，
# 于是任意楼层的安全房都共用同一套资产，无需按方位分版本。
# 墙/地/门三类构件复用战局区块通用组件库 v004（自带碰撞、自带色盘），
# 房间设施由房间包按各自 metadata 的 room_placement_position 摆位。
# 2026-09-20：按需求移除 `central_terminal_island`（中央四屏终端岛）与
# `west_glass_office`（西北玻璃办公室）两件，包数 17 → 15。两件的资产文件、
# manifest 与台账行仍留在库里（可随时恢复），只是不再被运行时消费 ——
# 与 door_5m 退场同口径。
const SAFE_ROOM_RUNTIME_ROOT := "res://assets/art/environments/tower_zones/battle/runtime/"
const SAFE_ROOM_ART_VERSION := "v007"
const SAFE_ROOM_ART_ASSET_ID := "ENV-BATTLE-L01-SAFE-ENTRY"
const SAFE_ROOM_PACKAGE_IDS: Array[String] = [
	"floor_base",
	"overhead_services",
	"debris_papers",
	"north_server_00",
	"north_server_01",
	"north_server_02",
	"north_server_03",
	"north_server_04",
	"north_server_05",
	"north_broken_core",
	"north_nexus_sign",
	"east_repair_bay",
	"east_robot_arm",
	"office_planter",
	"maintenance_chair",
]
const SAFE_ROOM_WALL_STANDARD_PREFAB: PackedScene = preload(
	"res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn"
)
const SAFE_ROOM_WALL_DOOR_PREFAB: PackedScene = preload(
	"res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_door_5m/wall_door_5m_root_top3d.tscn"
)
# 安全房门扇原走 B 套「door_5m_root_top3d.tscn / ENV-BATTLE-COMMON-DOOR-5M」。
# 那个包的 GLB 实测只是一个 13 三角形占位方块（单材质、无面板细节），
# 并非 door_5m_通用包 v006 的真实美术（5352 顶点 / 4 个色盘角色）。
# 2026-09-19：门扇统一改为塔楼 A 套正式美术 TOWER_DOOR_LEAF_PREFAB，
# 该常量随之退场。B 套那两个文件仍留在战局通用组件库里（属库的账面资产，
# 不由本脚本消费），不再被运行时引用。
const SAFE_ROOM_FLOOR_TILE_C01_PREFAB: PackedScene = preload(
	"res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d.tscn"
)
const SAFE_ROOM_FLOOR_TILE_C02_PREFAB: PackedScene = preload(
	"res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c02_root_top3d.tscn"
)
# —— 授权布局壳体的组件 ID 契约（2026-09-20）——
# 摆位源（Blender 侧 layout.json）用组件 ID 说话，运行时用 PackedScene 说话；
# 两侧靠这张表对齐。ID 取自战局通用组件库 v007 的台账名，不另起名。
# 任一侧改名而另一侧没跟上 → _authored_component_prefab() 返回 null 并报错，
# 不会静默换成别的组件。
const WALL_COMPONENT_ASSET_ID := "ENV-BATTLE-COMMON-WALL-STANDARD-5M"
const DOOR_WALL_COMPONENT_ASSET_ID := "ENV-BATTLE-COMMON-WALL-DOOR-5M"
const FLOOR_TILE_C01_COMPONENT_ID := "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01"
const FLOOR_TILE_C02_COMPONENT_ID := "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02"
const CORNER_L_COMPONENT_ID := "ENV-TOWER-CORNER-L-5M"
# v007 墙槽位表，逐项源自 source/room_instances/entry_safe_room/v007/qa/slot_table.json。
# 每项 = [房间局部 x_m, 房间局部 z_m, Godot rotation.y_deg, 是否门墙, 原生方位]。
# 坐标换算按 Blender Z-up → Godot Y-up：(bx, by, bz) → (bx, bz, -by)，
# 绕 Blender +Z 的角与绕 Godot +Y 的角同号，因此 rotation_z_deg 可直接沿用。
# 组件 forward_axis = -Z（朝房内那面即 -Z），槽位角度正好让装甲壁板朝向房内。
const SAFE_ROOM_WALL_SLOTS: Array = [
	[-5.0, -7.5, 180.0, false, "north"],
	[0.0, -7.5, 180.0, false, "north"],
	[5.0, -7.5, 180.0, false, "north"],
	[-5.0, 7.5, 0.0, false, "south"],
	[0.0, 7.5, 0.0, true, "south"],
	[5.0, 7.5, 0.0, false, "south"],
	[7.5, 5.0, 90.0, false, "east"],
	[7.5, 0.0, 90.0, true, "east"],
	[7.5, -5.0, 90.0, false, "east"],
	[-7.5, 5.0, -90.0, false, "west"],
	[-7.5, 0.0, -90.0, false, "west"],
	[-7.5, -5.0, -90.0, false, "west"],
]
# 原生门轴墙：南（+Z）与东（+X）。旋转解析以这两个方向为基准集合。
const SAFE_ROOM_DOOR_SIDES: Array[String] = ["south", "east"]
# v007 行走面在授权文件里是 Blender z=0.30（结构板顶 0.26 + 0.04 砖面），
# 运行时行走面是 Y=0，因此房间包整体下沉 0.30 对齐；墙体件以底面中心为原点，
# 直接坐在 Y=0 即可与塔楼自身墙体（0..11.9）同高同缝。
# 地砖不下沉固定值，改读每个组件自己的 snap_to_walk_plane_offset_m（c01 −0.056 / c02 −0.081）。
const SAFE_ROOM_WALK_LIFT_M := 0.30
const SAFE_ROOM_FLOOR_GRID_M := 5.0
# 四角 L 型墙角（仅远征入口安全房开启，见 safe_room_corner_l）。
# 直接引用塔楼 A 套 prp_corner_l_5m.tscn —— 它的正式美术就是「通用房通用墙组件」两份
# 刚性拼成的 L（来源 tower_zones/battle/source/common_components/v007 的
# ROOT_wall_standard_5m_通用组件），与安全房其余直墙同源、同色盘（01/02/04 角色）。
# 它比两条 0.30m 直墙正交端接多包 0.15m：可视包络 5.15×11.9×5.15 正好补上四角
# 外侧那道 0.15×0.15 的竖直缺口。两条臂各沿边覆盖 5m ⇒ 开启后每条边只保留中段槽位。
# 顺序是「整房旋转一步」的置换环：NW→SW→SE→NE→NW（对应 rotation.y += 90°），
# 所以按世界角位直接摆放等价于「原生四角 + art_root 整房旋转」。
const SAFE_ROOM_CORNER_IDS: Array[String] = ["NW", "SW", "SE", "NE"]
# 安全房沿用塔楼房间的边界约定：组件原点坐在 ±dimensions/2（= 5m 网格线）上，
# 墙厚向房间外侧展开。授权美术（v007 README）把外墙皮写在 7.5 / 中线 7.35，
# 运行时统一按塔楼口径把墙件原点落在 7.5，使门洞、走廊起点与楼板 5m 网格三者同线。
# —— 房间壳体原子件 prefab（B 节）
const FLOOR_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_floor.tscn")
const FLOOR_INSET_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_floor_inset.tscn")
const FLOOR_SEAM_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_floor_seam_strip.tscn")
const WALL_SEGMENT_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_wall_segment.tscn")
const WALL_DOOR_SEGMENT_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_wall_door_segment.tscn")
const DOOR_LINTEL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_door_lintel.tscn")
const CORNER_POST_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_corner_post.tscn")
const PARTITION_VERTICAL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_floor_partition_vertical.tscn")
const PARTITION_HORIZONTAL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_floor_partition_horizontal.tscn")
# —— 楼顶/楼梯厅装饰 prefab（C 节）
const ROOFTOP_FACADE_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_facade.tscn")
const ROOFTOP_FACADE_BAND_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_facade_band.tscn")
const ROOFTOP_RAIL_LOWER_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_railing_lower.tscn")
const ROOFTOP_RAIL_UPPER_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_railing_upper.tscn")
const ROOFTOP_RAIL_POST_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_rail_post.tscn")
const ROOFTOP_STAIR_FRAME_POST_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_stair_frame_post.tscn")
const ROOFTOP_STAIR_FRAME_LINTEL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_stair_frame_lintel.tscn")
const ROOFTOP_DESCENT_MARKER_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_rooftop_descent_marker.tscn")
const STAIR_LOBBY_ROUTE_GUIDE_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_stair_lobby_route_guide.tscn")
const STAIR_LOBBY_THRESHOLD_GUIDE_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_stair_lobby_threshold_guide.tscn")
const ACCESS_STEP_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_access_step.tscn")
const VERTICAL_ACCESS_LABEL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_room_vertical_access_marker_label.tscn")
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
const WALL_SOLID_MATERIAL_A: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_wall_solid_a_v001.tres"
)
const WALL_SOLID_MATERIAL_B: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_tower_wall_solid_b_v001.tres"
)
# —— 基地专属材质（FACILITY 房间使用，不影响战斗房 / 屋顶 / 楼梯厅）。
# 棋盘 A 格 = 深褐主色、B 格 = 亮深褐；墙 = 尘深蓝；装饰带 trim 与地板同色系。
const FACILITY_FLOOR_TILE_A: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_facility_floor_tile_a_v001.tres"
)
const FACILITY_FLOOR_TILE_B: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_facility_floor_tile_b_v001.tres"
)
const FACILITY_WALL_MATERIAL: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_facility_wall_v001.tres"
)
const FACILITY_TRIM_MATERIAL: StandardMaterial3D = preload(
	"res://assets/art/environments/tower_descent_3d/components/mat_facility_trim_v001.tres"
)
# 99层两种正式地板都以底面为原点，0.30m是共同的结构板顶面。铆钉板
# AABB到0.395m，是因为铁皮压条和铆钉高出结构板；这些细节只负责表现，
# 不能拿整个AABB最高点对齐，也不能生成额外阻挡。两种地板只按共同结构面
# 对齐，承重碰撞继续完全由TowerFloorStage的统一平面负责。
const BASE99_FLOOR_STRUCTURAL_TOP_Y_M := TOWER_GEOMETRY.FLOOR_THICKNESS_M
# 可视结构板顶面必须与TowerFloorStage的承重面Y=0重合。通用地砖会在基地
# 30x30m范围内让出可视网格，因此不再需要用抬高地板避开共面闪烁。
const BASE99_FLOOR_TARGET_SURFACE_Y_M := 0.0
const ROOFTOP_FACADE_HEIGHT := 6.0
# 基地东侧阁楼门的外梯在接近墙面时仍处于上升坡面。99层普通墙的结构
# 碰撞若完整顶到9m，角色胶囊会在门槛前先撞上墙体上沿。仅在上层门洞净宽
# 内降低这段下层墙碰撞；门洞两侧继续保持完整9m阻挡，门扇仍由RoomDoor3D负责。
const BASE_ROOFTOP_TRANSIT_DIRECTION := "east"
const BASE_ROOFTOP_TRANSIT_CENTER_ALONG_M := -7.5
const BASE_ROOFTOP_TRANSIT_COLLISION_TOP_M := 8.45
# 99F基地的墙面开关成对：西墙门（→100F天台）与东墙门（→98F）各一个，
# 均落在「门洞一侧第一个5m墙段」内、从门洞边缘再向外取1/3网格（1.667m）。
# 西墙取门洞北侧段、东墙取门洞南侧段——两侧关于房间中心镜像对称，
# 于是两个开关离各自门洞的距离完全相同（业主 2026-09-21 指定）。
const FACILITY_SWITCH_SIDES: Array[String] = ["west", "east"]
const FACILITY_SWITCH_WALL_INSET_M := 0.34
static var _tower_solid_wall_mesh: Mesh
static var _tower_solid_wall_preserves_palette := false
# 资产声明的装配方式。实墙实际走 MultiMesh 批渲染（节点树被丢弃），若资产仍
# 声明 per_instance_prefab 就是「声明与实际不符」——由 _assert_wall_instantiation()
# 当场报错，避免后人按声明去改装配代码。
static var _tower_solid_wall_declared_instantiation := ""
# 装配基准 Y 偏移改为读资产声明的 origin_contract，不再从网格 AABB 反算。
# 见 TowerGeometry3D.origin_offset_y()：美术换件时基准不随装饰件（门框等）漂移。
static var _tower_solid_wall_origin_offset_y := 0.0
static var _base99_solid_wall_origin_offset_y := 0.0
static var _tower_floor_tile_mesh: Mesh
static var _base99_solid_wall_mesh: Mesh
static var _base99_floor_plain_mesh: Mesh
static var _base99_floor_rivet_mesh: Mesh

const ROOM_DIMENSIONS := {
	# 约按 2D RoomData 的 0.034 m/px 映射，保留四档真实战斗尺度。
	"small": Vector2(22.0, 18.0),
	"medium": Vector2(32.0, 26.0),
	"large": Vector2(44.0, 34.0),
	"arena": Vector2(56.0, 42.0),
	# v0.1 塔楼入口使用固定真实尺度；不改变既有四档房间契约。
	"floor": Vector2(65.0, 65.0),
	"rooftop": Vector2(65.0, 65.0),
	"tower_cell": Vector2(15.0, 15.0),
}

const STREAM_DATA_ONLY := 0
const STREAM_SHELL_READY := 1
const STREAM_ACTIVE := 2
const STREAM_PREFETCHING := 3
const STREAM_HIBERNATING := 4
const STREAM_STATE_NAMES := {
	STREAM_DATA_ONLY: "DATA_ONLY",
	STREAM_SHELL_READY: "SHELL_READY",
	STREAM_ACTIVE: "ACTIVE",
	STREAM_PREFETCHING: "PREFETCHING",
	STREAM_HIBERNATING: "HIBERNATING",
}

# 房间归属只在角色中心真正跨过墙体内沿后成立。读档恢复、交互距离、
# 预加载和门洞防夹各自拥有独立容差，禁止复用到这个实时归属合同。
const ROOM_OWNERSHIP_BOUNDARY_INSET_M := 0.08
const ROOM_OWNERSHIP_MIN_LOCAL_Y_M := -0.40
const ROOM_OWNERSHIP_MAX_LOCAL_Y_M := 2.50
# 刷怪落点的「超量退让」参数，供 spawn_point_for_index 使用。
# 环形点位只够 size_class 决定的那几个（布局房 = 4），而设计源允许一波 24 / 单房 64，
# 超出部分按层退让：每层转一个固定角 + 缩一档半径，直到半径触底靠角度区分。
const SPAWN_POINT_LAYER_ANGLE_STEP := 0.37
const SPAWN_POINT_LAYER_RADIUS_STEP := 0.17
const SPAWN_POINT_MIN_RADIUS_SCALE := 0.12

var room_id := "room_00"
var room_type := "COMBAT"
var size_class := "medium"
var doors: Array[String] = []
var door_targets: Dictionary = {}
var door_policies: Dictionary = {}
var theme: DungeonTheme3D
var room_seed := 1
var is_main_path := true
var visited := false
var cleared := false
var enemy_spawn_points: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _floor_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _detail_built := false
var _shell_built := false
var _detail_root: Node3D
var _building_detail := false
var _pending_detail_runtime_state: Dictionary = {}
var _stream_state := -1
var _stream_transition_count := 0
var _last_stream_transition_msec := 0
var _door_nodes: Dictionary = {}
var _central_light: WastelandLight3D
var _room_lights: Array[WastelandLight3D] = []
var _light_switch: RoomLightSwitch3D
# 99F基地的常驻开关全集（西墙→100F、东墙→98F）。其他房型本数组为空，
# 只走 _light_switch 单开关路径。见 FACILITY_SWITCH_SIDES 与
# _ensure_facility_permanent_lighting()。
var _light_switches: Array[RoomLightSwitch3D] = []
var custom_dimensions := Vector2.ZERO
var tower_module_shell := false
var open_wall_directions: Array[String] = []
## 设计源给出的房间级刷怪计划（波次 / 每波数量 / 怪物组成）。
## 空字典 = 该房走全局刷怪公式；非空时由 Dungeon3D._spawn_room_enemies 全量接管。
var enemy_spawn_plan: Dictionary = {}
## 设计源给出的房间级统一掉落计划（04 §22.7）：键 = trigger（clear / search / kill），
## 值 = 槽位引用（`{spec_id}` / `{entries}` / `{pool_id}`）。空字典 = 本房不覆盖，
## 由 RewardService.resolve_dispatch 的覆盖链逐级回退（关卡 → 怪物表 → 全局默认）。
## **只承载不解释**：本类不解析规格、不抽表 —— 抽表只有 RewardService 一处。
var reward_plan: Dictionary = {}
## 入口安全房四角是否补 L 型墙角（默认关：塔楼安全房保持 12 段直墙口径）。
## 只由「远征关卡」的房间记录置真，见 TowerDescent3D._build_expedition_records()。
var safe_room_corner_l := false
## —— 授权布局壳体（2026-09-20，区块00「主人的办公室」）——
## 置真时本房**不生成任何程序化壳体**（4 墙 + 角柱 + 地板 + 天花 + 安全房 v007 整房），
## 壳体全部由外部摆位源给出的 5m 组件实例清单拼出；本脚本只负责
##   ① 按清单实例化组件（墙/门墙/地砖/L 角件），② 在门槽处把实墙顶替成门墙，
##   ③ 仍然生成本房自己的 RoomDoor3D 通行门（门的开合/碰撞归它，不归组件）。
## 清单里的 `door_leaf_preview` 是编辑器预览件，运行时**必须跳过**，
## 否则会和 RoomDoor3D 的门扇重叠。
var authored_layout_shell := false
## 授权壳体实例清单（**房间局部坐标**，见 Block00MasterOfficeLayout3D.room_shell_instances）。
## 每项 = { name, component_id, slot_role, corner_id, position: Vector3, rotation_y_deg: float }。
var authored_layout_instances: Array = []
var authored_layout_asset_id := ""
var authored_layout_version := ""
var authored_layout_room_id := ""
## 和平区（区块00「主人的办公室」等叙事固定关卡）：本房所属区域**不刷怪、门只做普通开关**
## （无清房 / 无钥匙 / 无命运卡），门扇沿用 99F 基地的滑升门。开关声明在
## `Block00MasterOfficeLayout3D.PEACEFUL_ZONE`，一路透传到 Dungeon3D 的三个消费点：
## `_spawn_room_enemies()`（不刷怪）、`_door_policies_for_record()`（门策略全放行）、
## `_build_door()`（基地门扇）。默认 false = 未声明的区域行为一字不变。
var authored_layout_peaceful := false
## 本房**初始灯就亮**（不经玩家按开关、不播启动序列）。给「开局第一间房」用 ——
## 玩家一睁眼不该是黑的。默认 false = 老行为（只有 STAIR_LOBBY / BOSS 默认亮）。
var authored_room_light_on := false


func configure(config: Dictionary) -> void:
	room_id = str(config.get("room_id", room_id))
	room_type = str(config.get("room_type", room_type)).to_upper()
	size_class = str(config.get("size_class", size_class))
	doors.assign(config.get("doors", []))
	door_targets = (config.get("door_targets", {}) as Dictionary).duplicate(true)
	door_policies = (config.get("door_policies", {}) as Dictionary).duplicate(true)
	theme = config.get("theme", theme) as DungeonTheme3D
	room_seed = int(config.get("seed", room_seed))
	is_main_path = bool(config.get("is_main_path", is_main_path))
	custom_dimensions = config.get("custom_dimensions", custom_dimensions) as Vector2
	tower_module_shell = bool(config.get("tower_module_shell", tower_module_shell))
	open_wall_directions.assign(config.get("open_wall_directions", []))
	enemy_spawn_plan = (config.get("enemy_spawn_plan", enemy_spawn_plan) as Dictionary).duplicate(true)
	reward_plan = (config.get("reward_plan", reward_plan) as Dictionary).duplicate(true)
	safe_room_corner_l = bool(config.get("safe_room_corner_l", safe_room_corner_l))
	authored_layout_shell = bool(config.get("authored_layout_shell", authored_layout_shell))
	authored_layout_instances = (config.get("authored_layout_instances", []) as Array).duplicate(true)
	authored_layout_asset_id = str(config.get("authored_layout_asset_id", authored_layout_asset_id))
	authored_layout_version = str(config.get("authored_layout_version", authored_layout_version))
	authored_layout_room_id = str(config.get("authored_layout_room_id", authored_layout_room_id))
	authored_layout_peaceful = bool(config.get("authored_layout_peaceful", authored_layout_peaceful))
	authored_room_light_on = bool(config.get("authored_room_light_on", authored_room_light_on))


func _ready() -> void:
	_rng.seed = room_seed
	if theme == null:
		theme = load("res://assets/art/environments/dungeon_3d/env_iron_frontier_kit_top3d_v001.tres") as DungeonTheme3D
	add_to_group("dungeon_room_3d")
	_build_spawn_points()
	set_stream_state(0)


func get_dimensions() -> Vector2:
	if custom_dimensions.x > 0.0 and custom_dimensions.y > 0.0:
		return custom_dimensions
	return ROOM_DIMENSIONS.get(size_class, ROOM_DIMENSIONS["medium"])


func is_room_light_on() -> bool:
	return _light_switch != null and _light_switch.is_light_on()


func get_room_snapshot() -> Dictionary:
	return {
		"room_id": room_id, "room_type": room_type, "size_class": size_class,
		"dimensions": get_dimensions(), "doors": doors.duplicate(), "visited": visited,
		"cleared": cleared, "is_main_path": is_main_path,
		"authored_layout_shell": authored_layout_shell,
		"authored_layout_peaceful": authored_layout_peaceful,
		"shell_built": _shell_built, "detail_built": _detail_built, "stream_state": _stream_state,
		"stream_state_name": get_stream_state_name(),
		"stream_transition_count": _stream_transition_count,
		"furniture_count": get_tree().get_nodes_in_group("room_prop_3d").filter(func(node): return is_ancestor_of(node)).size(),
		"light_count": get_tree().get_nodes_in_group("wasteland_light_3d").filter(func(node): return is_ancestor_of(node)).size(),
		"central_light": _central_light != null,
		"room_light_on": is_room_light_on(),
		"light_switch": _light_switch != null,
		"controlled_light_count": _room_lights.size(),
		"shadow_capable_light_count": _count_shadow_capable_lights(),
		"active_shadow_light_count": _count_active_shadow_lights(),
		"room_light_cull_mask": GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER,
		"base_grid_dimensions": Vector2i(6, 6) if room_type == "FACILITY" else Vector2i.ZERO,
		"base_grid_tile_count": 36 if room_type == "FACILITY" else 0,
		"base_grid_tile_count_light": 18 if room_type == "FACILITY" else 0,
		"base_grid_tile_count_dark": 18 if room_type == "FACILITY" else 0,
		"base_grid_checkerboard_pattern": room_type == "FACILITY",
		"base99_floor_plain_instance_count": _sum_int_meta_for_asset_floor(
			self, "ENV-BASE99-FLOOR-PLAIN-5M", "instance_count", 99
		),
		"base99_floor_rivet_instance_count": _sum_int_meta_for_asset_floor(
			self, "ENV-BASE99-FLOOR-RIVET-5M", "instance_count", 99
		),
		"tower_wall_module_count": (
			_count_nodes_with_meta(self, "asset_id", "ENV-TOWER-WALL-SOLID-5M")
			+ _count_nodes_with_meta_floor(
				self, "asset_id", "ENV-BASE99-WALL-PLAIN-5X12", 99
			)
		),
		"base99_wall_plain_module_count": _count_nodes_with_meta_floor(
			self, "asset_id", "ENV-BASE99-WALL-PLAIN-5X12", 99
		),
		"base99_wall_plain_instance_count": _sum_int_meta_for_asset_floor(
			self, "ENV-BASE99-WALL-PLAIN-5X12", "segment_count", 99
		),
		"base99_wall_window_instance_count": _sum_int_meta_for_asset_floor(
			self, "ENV-BASE99-WALL-WINDOW-5X12", "segment_count", 99
		),
		"base99_wall_door_module_count": _count_nodes_with_meta_floor(
			self, "asset_id", "ENV-BASE99-WALL-DOOR-5X12", 99
		),
		"base100_upper_shell_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-BASE100-UPPER-SHELL-30X30-H12"
		),
		"base100_wall_plain_instance_count": _sum_int_meta_for_asset_floor(
			self, "ENV-BASE99-WALL-PLAIN-5X12", "segment_count", 100
		),
		"base100_wall_window_instance_count": _sum_int_meta_for_asset_floor(
			self, "ENV-BASE99-WALL-WINDOW-5X12", "segment_count", 100
		),
		"base100_wall_door_instance_count": _sum_int_meta_for_asset_floor(
			self, "ENV-BASE99-WALL-DOOR-5X12", "segment_count", 100
		),
		"base100_roof_tile_count": _sum_int_meta_for_asset(
			self, "ENV-BASE100-UPPER-SHELL-30X30-H12", "roof_tile_count"
		),
		# 2026-09-20：东西南三面外墙与 24m 封顶改由天台参考组件库 v002 承接。
		# 这三面墙不再计入 base100_wall_plain_instance_count（base99 plain 只剩北面 2 块），
		# 所以必须单独计数，否则「墙确实换成 v002」这件事没有任何断言看得见。
		"base100_rooftop_room_wall_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-ROOFTOP-REF-ROOM-WALL"
		),
		"base100_rooftop_roof_corner_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-ROOFTOP-REF-ROOF-CORNER"
		),
		"base100_rooftop_roof_edge_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-ROOFTOP-REF-ROOF-EDGE"
		),
		"base100_rooftop_roof_full_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-ROOFTOP-REF-ROOF-FULL"
		),
		"base100_structure_collision_count": _count_nodes_with_meta(
			self, "base100_upper_shell_collision", true
		),
		"base99_door_lift_count": _count_nodes_with_meta(
			self, "visual_asset_id", "ENV-BASE99-DOOR-LIFT-22X25"
		),
		"base99_mezzanine_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-BASE99-MEZZANINE-20X10-Z5"
		),
		"base99_stair_l_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-BASE99-STAIR-L-Z5"
		),
		"base99_stair_exterior_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-BASE99-STAIR-EXTERIOR-H4"
		),
		"base99_camera_stair_slab_count": _count_nodes_with_meta(
			self, "camera_stair_slab", true
		),
		# 入口安全房 v007：墙体/门墙/地砖来自战局区块通用组件库 v004，
		# 房间设施来自 17 个房间包。四组计数用于确认正式美术确实装配到位。
		"safe_room_art_version": str(get_meta("safe_room_art_version", "")),
		"safe_room_orientation_steps": int(get_meta("safe_room_orientation_steps", 0)),
		"safe_room_wall_module_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-BATTLE-COMMON-WALL-STANDARD-5M"
		),
		"safe_room_door_wall_module_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-BATTLE-COMMON-WALL-DOOR-5M"
		),
		# 四角 L 型墙角（远征入口安全房专有）：live 计数按 asset_id 数节点，
		# 不是读建造时自报的 meta —— 否则「声明了但一件没落地」看不出红。
		"safe_room_corner_l": bool(get_meta("safe_room_corner_l", false)),
		"safe_room_corner_module_count": _count_nodes_with_meta(
			self, "asset_id", "ENV-TOWER-CORNER-L-5M"
		),
		"safe_room_wall_expected_count": int(get_meta("safe_room_wall_expected_count", -1)),
		"safe_room_floor_tile_count": (
			_count_nodes_with_meta(self, "asset_id", "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01")
			+ _count_nodes_with_meta(self, "asset_id", "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02")
		),
		"safe_room_package_count": int(get_meta("safe_room_package_count", 0)),
		"tower_door_wall_module_count": (
			_count_nodes_with_meta(self, "asset_id", "ENV-TOWER-WALL-DOOR-5M")
			+ _count_nodes_with_meta_floor(
				self, "asset_id", "ENV-BASE99-WALL-DOOR-5X12", 99
			)
		),
		"tower_corner_module_count": _count_nodes_with_meta(self, "asset_id", "ENV-TOWER-CORNER-L-5M"),
		"wall_material_variant_a_count": _count_nodes_with_meta(self, "material_variant", "A"),
		"wall_material_variant_b_count": _count_nodes_with_meta(self, "material_variant", "B"),
		"tower_module_shell": tower_module_shell,
		"open_wall_directions": open_wall_directions.duplicate(),
		"wall_height": TOWER_GEOMETRY.FLOOR_HEIGHT_M if tower_module_shell else 2.8,
		"support_collision_persistent": _has_enabled_support_collision(),
		"service_station_count": _get_service_stations().size(),
		"event_objective_ready": get_service_station("event") != null,
		"door_snapshots": _get_door_snapshots(),
		"is_3d": true,
	}


## 正式运行时 O(1) 读取。完整 get_room_snapshot() 会扫描节点组和递归统计
## 组件，只允许验收/调试低频调用，禁止在 _process/_physics_process 中使用。
func get_stream_state() -> int:
	return _stream_state


func is_streamed() -> bool:
	return _stream_state in [STREAM_SHELL_READY, STREAM_ACTIVE, STREAM_PREFETCHING]


func get_stream_state_name() -> String:
	return str(STREAM_STATE_NAMES.get(_stream_state, "DATA_ONLY"))


func ensure_detail_built() -> void:
	if _detail_built:
		return
	_detail_built = true
	_detail_root = Node3D.new()
	_detail_root.name = "RuntimeDetail"
	add_child(_detail_root)
	_building_detail = true
	_build_content()
	_building_detail = false
	_apply_pending_detail_runtime_state()
	_set_room_light_runtime_state(self)


func ensure_shell_built() -> void:
	if _shell_built:
		return
	_shell_built = true
	_build_shell()
	_build_trigger()
	# FACILITY（99F基地）的中央顶灯与墙面开关是壳体级常驻节点：
	# 随壳体一次性建好，不走 RuntimeDetail 的进出重建「出现流程」。
	_ensure_facility_permanent_lighting()
	_keep_structural_physics_active(self)


func set_stream_state(state: int) -> void:
	var next_state := clampi(state, STREAM_DATA_ONLY, STREAM_HIBERNATING)
	if next_state == _stream_state:
		return
	_stream_state = next_state
	_stream_transition_count += 1
	_last_stream_transition_msec = Time.get_ticks_msec()
	var presentation_ready := _stream_state in [STREAM_SHELL_READY, STREAM_ACTIVE, STREAM_PREFETCHING]
	if presentation_ready:
		ensure_shell_built()
		if _stream_state == STREAM_ACTIVE:
			ensure_detail_built()
		elif _stream_state == STREAM_PREFETCHING:
			call_deferred("set_stream_state", STREAM_SHELL_READY)
	elif _stream_state == STREAM_DATA_ONLY:
		_unload_runtime_detail()
	# 壳体永久可见，DATA_ONLY/HIBERNATING 只卸载或停用高成本运行时细节。
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT if presentation_ready else Node.PROCESS_MODE_DISABLED
	# 墙、门框和楼板碰撞与视觉壳体保持一致，避免受光、通行和掉落规则分叉。
	# RuntimeDetail 在 DATA_ONLY 中已被释放，因此不会保留家具/交互碰撞。
	_set_collision_enabled(self, true, true)
	if presentation_ready:
		for value in _door_nodes.values():
			var door := value as RoomDoor3D
			if door != null:
				door.set_open(door.is_open, true)
	_set_room_light_runtime_state(self)


func apply_runtime_detail_state(state: Dictionary) -> void:
	_pending_detail_runtime_state = state.duplicate(true)
	if _detail_built:
		_apply_pending_detail_runtime_state()


func _apply_pending_detail_runtime_state() -> void:
	if _pending_detail_runtime_state.is_empty() or not _detail_built:
		return
		# 默认值必须跟着房间声明走：写死 false 会把「初始灯亮」在重建时顶掉。
	var wanted_light_on := bool(
		_pending_detail_runtime_state.get("room_light_on", authored_room_light_on)
	)
	if _light_switch != null and _light_switch.is_light_on() != wanted_light_on:
		_light_switch.set_light_on(wanted_light_on)
	var container_states := _pending_detail_runtime_state.get("containers", {}) as Dictionary
	for value in get_tree().get_nodes_in_group("room_prop_3d"):
		if value is RoomFurniture3D and _detail_root != null and _detail_root.is_ancestor_of(value):
			var prop := value as RoomFurniture3D
			if container_states.has(prop.prop_id):
				prop.restore_searched_state(bool(container_states[prop.prop_id]))


func _unload_runtime_detail() -> void:
	if _detail_root != null and is_instance_valid(_detail_root):
		remove_child(_detail_root)
		_detail_root.queue_free()
	_detail_root = null
	_detail_built = false
	# FACILITY 的顶灯与开关是壳体级常驻节点（不走出现流程），detail 卸载不回收；
	# _room_lights 保留常驻灯登记，供阴影计数与快照读取。
	if room_type != "FACILITY":
		_central_light = null
		_light_switch = null
		_room_lights.clear()


func _add_runtime_detail_child(node: Node) -> void:
	if _building_detail and _detail_root != null:
		_detail_root.add_child(node)
	else:
		add_child(node)


## 99F基地（FACILITY）的中央顶灯与墙面开关不走 RuntimeDetail「出现流程」：
## 随壳体一次性建好、常驻在场（业主 2026-09-21 指定）。
## 进出房间只重建家具/可搜容器等细节；灯与开关不销毁、不换实例，
## 开关状态连续性仍由 apply_runtime_detail_state("room_light_on") 兜底。
## 美术灯控（Art 的设备青色发光）依赖 _install_facilities 装入的 Art 节点，
## 其绑定时机保持在 detail 构建期（_bind_facility_presentation_light_control）。
func _ensure_facility_permanent_lighting() -> void:
	if room_type != "FACILITY" or size_class == "rooftop":
		return
	_prune_facility_switches()
	var light_valid := _central_light != null and is_instance_valid(_central_light)
	var switches_valid := _light_switches.size() == FACILITY_SWITCH_SIDES.size()
	if light_valid and switches_valid:
		return
	if not light_valid:
		# 99F基地只保留一盏中央玩法顶灯。Compatibility默认每个Mesh最多
		# 接收8盏OmniLight；28m范围覆盖30×30m主体区。
		_central_light = _create_room_light(
			"FacilityCeilingLight_Main",
			Vector3.ZERO,
			theme.fixture_energy * 3.00,
			maxf(theme.fixture_range * 3.30, 28.0),
			room_seed,
			true
		)
		# 基地用接近中性的冷白主光保留真实色盘，青色由设备发光承担。
		_central_light.configure(
			Color(0.84, 0.90, 1.0), _central_light.energy,
			_central_light.light_range, room_seed, true, false, "ceiling"
		)
		# 壳体期不在 detail 构建流程中，_add_runtime_detail_child 兜底直挂房间根。
		if not _room_lights.has(_central_light):
			_room_lights.append(_central_light)
	if not switches_valid:
		_build_facility_light_switches()
	elif not light_valid:
		# 顶灯被重建过：常驻开关仍持有旧灯句柄，必须重新指向当前灯组，
		# 否则开关会控制一个已释放的灯对象。
		for light_switch in _light_switches:
			light_switch.configure_group(_room_lights, true)
		_bind_light_switch_signal()


## 建齐基地成对开关（西墙→100F、东墙→98F），全部直挂房间根、不走出现流程。
## 两个开关共享同一组受控灯，并以 link_switch 互相并联（启动序列互锁 +
## 指示灯/提示文字同步），避免同一盏灯上出现两个各自为政的开关。
func _build_facility_light_switches() -> void:
	for existing in _light_switches:
		if existing != null and is_instance_valid(existing):
			existing.queue_free()
	_light_switches.clear()
	for side in FACILITY_SWITCH_SIDES:
		var light_switch := LIGHT_SWITCH_SCENE.instantiate() as RoomLightSwitch3D
		if light_switch == null:
			push_error("基地墙面灯开关 Prefab 实例化失败：%s" % side)
			continue
		light_switch.name = (
			"RoomLightSwitch3D" if side == "west" else "RoomLightSwitch3D_East"
		)
		_place_facility_light_switch(light_switch, get_dimensions(), side)
		light_switch.configure_group(_room_lights, true)
		add_child(light_switch)
		_light_switches.append(light_switch)
	for index in range(_light_switches.size()):
		for other_index in range(index + 1, _light_switches.size()):
			_light_switches[index].link_switch(_light_switches[other_index])
	_light_switch = _light_switches[0] if not _light_switches.is_empty() else null
	_bind_light_switch_signal()


func _prune_facility_switches() -> void:
	for index in range(_light_switches.size() - 1, -1, -1):
		var light_switch := _light_switches[index]
		if light_switch == null or not is_instance_valid(light_switch):
			_light_switches.remove_at(index)


## 基地开关落位：贴门洞一侧的第一个 5m 墙段，从门洞边缘再向外取 1/3 网格。
## west 取门洞北侧段、east 取门洞南侧段 ⇒ 两侧关于房间中心镜像、离门距离相同。
## 朝向沿用通用落位口径：local −Z（面板正面）朝房间内。
func _place_facility_light_switch(
	light_switch: RoomLightSwitch3D, dimensions: Vector2, side: String
) -> void:
	var wall_unit := TOWER_GEOMETRY.GRID_UNIT_M
	var door := get_door_node(side)
	# 门缺失时退回「墙中心段」的同一口径，保证仍落在合法墙段内。
	var door_along := door.position.z if door != null else -wall_unit * 0.5
	var half_unit := wall_unit * 0.5
	var third_unit := wall_unit / 3.0
	if side == "east":
		light_switch.position = Vector3(
			dimensions.x * 0.5 - FACILITY_SWITCH_WALL_INSET_M,
			0.0,
			door_along + half_unit + third_unit
		)
		light_switch.rotation.y = PI * 0.5
		light_switch.set_meta("facility_entry_switch_clearance_m", half_unit)
		light_switch.set_meta("facility_entry_direction", "east_entry_south_first_wall")
		return
	light_switch.position = Vector3(
		-dimensions.x * 0.5 + FACILITY_SWITCH_WALL_INSET_M,
		0.0,
		door_along - half_unit - third_unit
	)
	light_switch.rotation.y = -PI * 0.5
	light_switch.set_meta("facility_entry_switch_clearance_m", half_unit)
	light_switch.set_meta("facility_entry_direction", "west_entry_north_first_wall")


func _bind_facility_presentation_light_control(starts_on: bool) -> void:
	if room_type != "FACILITY":
		return
	var art_layout := get_node_or_null("Art")
	if art_layout == null or not art_layout.has_method("set_presentation_lighting_enabled"):
		push_warning("基地美术自发光灯控未就绪")
		return
	# 成对开关都要能播完整启动序列，也都要能把关灯状态转给美术自发光；
	# set_presentation_lighting_enabled 幂等，重复连接同一 Callable 由判重挡住。
	var presentation_callback := Callable(
		art_layout, "set_presentation_lighting_enabled"
	)
	for light_switch in _all_room_light_switches():
		if not light_switch.light_toggled.is_connected(presentation_callback):
			light_switch.light_toggled.connect(presentation_callback)
		# 总启动时长约五秒；第4.5秒中央顶灯先亮，剩余小灯继续完成启动。
		light_switch.configure_turn_on_presentation(art_layout, 5.0)
	art_layout.call("set_presentation_lighting_enabled", starts_on)


## 本房全部墙面开关。FACILITY 返回成对常驻开关；其他房型沿用单开关。
func _all_room_light_switches() -> Array[RoomLightSwitch3D]:
	var result: Array[RoomLightSwitch3D] = []
	if room_type == "FACILITY":
		_prune_facility_switches()
		for light_switch in _light_switches:
			result.append(light_switch)
		return result
	if _light_switch != null and is_instance_valid(_light_switch):
		result.append(_light_switch)
	return result



## 通用灯开关订阅（不限 FACILITY 房）。非基地房型的开关是 RuntimeDetail 子节点，
## 进出房间会重建；基地开关是壳体级常驻（见 _ensure_facility_permanent_lighting）。
## 两种情况都走本函数订阅，且对成对开关逐一订阅。
func _bind_light_switch_signal() -> void:
	for light_switch in _all_room_light_switches():
		if not light_switch.light_toggled.is_connected(_on_light_switch_toggled):
			light_switch.light_toggled.connect(_on_light_switch_toggled)


func _on_light_switch_toggled(is_on: bool) -> void:
	light_toggled.emit(self, is_on)


func _set_room_light_runtime_state(root: Node) -> void:
	for child in root.get_children():
		if child is WastelandLight3D:
			(child as WastelandLight3D).set_runtime_active(
				_stream_state in [STREAM_SHELL_READY, STREAM_ACTIVE],
				_stream_state == STREAM_ACTIVE,
				_stream_state == STREAM_ACTIVE
			)
		else:
			_set_room_light_runtime_state(child)


func set_door_open(direction: String, opened: bool, immediate := false) -> void:
	if not _shell_built and _stream_state > 0:
		ensure_shell_built()
	var door := _door_nodes.get(direction) as RoomDoor3D
	if door != null:
		door.set_open(opened, immediate)


func contains_world_position(
	world_position: Vector3,
	min_local_y := ROOM_OWNERSHIP_MIN_LOCAL_Y_M,
	max_local_y := ROOM_OWNERSHIP_MAX_LOCAL_Y_M
) -> bool:
	var local_position := to_local(world_position) if is_inside_tree() else world_position - position
	var dimensions := get_dimensions()
	var half_x := maxf(0.0, dimensions.x * 0.5 - ROOM_OWNERSHIP_BOUNDARY_INSET_M)
	var half_z := maxf(0.0, dimensions.y * 0.5 - ROOM_OWNERSHIP_BOUNDARY_INSET_M)
	return (
		absf(local_position.x) < half_x
		and absf(local_position.z) < half_z
		and local_position.y >= min_local_y
		and local_position.y <= max_local_y
	)


func get_nearest_door(player_position: Vector3, max_distance := 3.4) -> Dictionary:
	var nearest_distance := max_distance
	var nearest: RoomDoor3D = null
	for value in _door_nodes.values():
		var door := value as RoomDoor3D
		if door == null:
			continue
		var distance := player_position.distance_to(door.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = door
	if nearest == null:
		return {}
	return {
		"direction": nearest.direction,
		"target_room_id": nearest.target_room_id,
		"is_open": nearest.is_open,
		"distance": nearest_distance,
		"door": nearest,
	}


func hide_door_prompts() -> void:
	for value in _door_nodes.values():
		var door := value as RoomDoor3D
		if door != null:
			door.set_prompt_visible(false)


func get_door_node(direction: String) -> RoomDoor3D:
	return _door_nodes.get(direction) as RoomDoor3D


func get_service_station(type_id := "") -> ServiceStation3D:
	for station in _get_service_stations():
		if type_id.is_empty() or station.station_type == type_id:
			return station
	return null


func ensure_required_service_station() -> ServiceStation3D:
	if room_type not in ["MERCHANT", "UPGRADE", "EVENT"]:
		return null
	ensure_detail_built()
	var type_id := room_type.to_lower()
	var existing := get_service_station(type_id)
	if existing != null:
		return existing
	return _create_service_station(type_id, get_dimensions())


func _get_service_stations() -> Array[ServiceStation3D]:
	var result: Array[ServiceStation3D] = []
	for value in find_children("*", "ServiceStation3D", true, false):
		if value is ServiceStation3D:
			result.append(value as ServiceStation3D)
	return result


func _build_shell() -> void:
	var dimensions := get_dimensions()
	_floor_material = _material(theme.floor_color, 0.08, 0.90)
	_wall_material = _material(theme.wall_color, 0.62, 0.62)
	_trim_material = _material(theme.trim_color, 0.74, 0.38)
	# 基地走专属材质：地板用 FACILITY_FLOOR_TILE_A/B（由 _build_base_facility_shell
	# 单独覆盖），墙由 _get_wall_module_material 接管，trim 替换为深褐色装饰带。
	if room_type == "FACILITY":
		_trim_material = FACILITY_TRIM_MATERIAL
	if tower_module_shell:
		# 授权布局优先：壳体由外部 5m 组件清单接管，程序化塔楼模块一律不生成。
		# 顺序必须在 tower_module_shell 之前 —— 两个开关同时为真时（98F 区块00
		# 的房间记录两处都置真），走授权路径。
		if authored_layout_shell:
			_build_authored_layout_shell(dimensions)
			return
		_build_tower_module_shell(dimensions)
		return
	# Floor：1×1×1 prefab + scale = (dim.x, 0.36, dim.y)
	_spawn_prefab("Floor", FLOOR_PREFAB, Vector3(0, -0.18, 0), Vector3(dimensions.x, 0.36, dimensions.y), _floor_material)
	_spawn_prefab("FloorInset", FLOOR_INSET_PREFAB, Vector3(0, 0.012, 0), Vector3(dimensions.x * 0.80, 0.025, dimensions.y * 0.80), _material(theme.floor_color.lightened(0.055), 0.04, 0.94))
	for x in range(-int(dimensions.x * 0.4), int(dimensions.x * 0.4), 3):
		_spawn_prefab("FloorSeam", FLOOR_SEAM_PREFAB, Vector3(float(x), 0.03, 0), Vector3(0.025, 0.018, dimensions.y * 0.76), _trim_material)
	if size_class == "rooftop":
		_build_rooftop_shell(dimensions)
		return
	_build_wall("north", Vector3(0, 1.4, -dimensions.y * 0.5), dimensions.x, Vector3(1, 0, 0))
	_build_wall("south", Vector3(0, 1.4, dimensions.y * 0.5), dimensions.x, Vector3(1, 0, 0))
	_build_wall("west", Vector3(-dimensions.x * 0.5, 1.4, 0), dimensions.y, Vector3(0, 0, 1))
	_build_wall("east", Vector3(dimensions.x * 0.5, 1.4, 0), dimensions.y, Vector3(0, 0, 1))
	for direction in doors:
		_build_door(direction, str(door_targets.get(direction, "")), dimensions)
	for corner in [
		Vector3(-dimensions.x * 0.5, 1.45, -dimensions.y * 0.5),
		Vector3(dimensions.x * 0.5, 1.45, -dimensions.y * 0.5),
		Vector3(-dimensions.x * 0.5, 1.45, dimensions.y * 0.5),
		Vector3(dimensions.x * 0.5, 1.45, dimensions.y * 0.5),
	]:
		_spawn_prefab("CornerPost", CORNER_POST_PREFAB, corner, Vector3(0.42, 2.9, 0.42), _trim_material)
	if size_class == "floor":
		_build_floor_partitions(dimensions)


func _build_rooftop_shell(dimensions: Vector2) -> void:
	for direction in ["north", "south", "west", "east"]:
		_build_rooftop_exterior_wall(direction, dimensions)
		_build_rooftop_railing(direction, dimensions)
	for direction in doors:
		_build_door(direction, str(door_targets.get(direction, "")), dimensions)
	var access_direction := doors[0] if not doors.is_empty() else "west"
	var access_center := Vector3.ZERO
	match access_direction:
		"west":
			access_center = Vector3(-dimensions.x * 0.5, 1.45, 0)
		"east":
			access_center = Vector3(dimensions.x * 0.5, 1.45, 0)
		"north":
			access_center = Vector3(0, 1.45, -dimensions.y * 0.5)
		_:
			access_center = Vector3(0, 1.45, dimensions.y * 0.5)
	var frame_axis_x := access_direction in ["north", "south"]
	for side in [-1.0, 1.0]:
		var frame_half_width := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M * 0.5 + 0.22
		var post_offset := Vector3(side * frame_half_width, 0, 0) if frame_axis_x else Vector3(0, 0, side * frame_half_width)
		_spawn_prefab("RooftopStairFramePost", ROOFTOP_STAIR_FRAME_POST_PREFAB, access_center + post_offset, Vector3(0.34, 2.9, 0.34), _wall_material)
	var frame_span := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M + 0.78
	var lintel_size := Vector3(frame_span, 0.38, 0.34) if frame_axis_x else Vector3(0.34, 0.38, frame_span)
	_spawn_prefab("RooftopStairFrameLintel", ROOFTOP_STAIR_FRAME_LINTEL_PREFAB, access_center + Vector3(0, 1.24, 0), lintel_size, _wall_material)
	# 楼梯头顶部做缺口标识；真正通行口仍由公共 RoomDoor3D 阻挡与开启。
	var marker := ROOFTOP_DESCENT_MARKER_PREFAB.instantiate() as Node3D
	marker.name = "RooftopDescentMarker"
	marker.position = access_center + Vector3(0, 1.9, 0)
	var label3d := marker.get_node("RooftopDescentMarker") as Label3D
	if label3d != null:
		label3d.text = "下行楼梯"
		label3d.modulate = theme.accent_color.lightened(0.18)
	add_child(marker)


func _build_rooftop_exterior_wall(direction: String, dimensions: Vector2) -> void:
	var horizontal := direction in ["north", "south"]
	var length := dimensions.x if horizontal else dimensions.y
	var has_door := doors.has(direction)
	var facade_material := _material(theme.wall_color.lightened(0.14), 0.54, 0.68)
	var facade_band_material := _material(theme.trim_color.lightened(0.10), 0.70, 0.42)
	facade_material.emission_enabled = true
	facade_material.emission = theme.wall_color.lightened(0.24)
	facade_material.emission_energy_multiplier = 0.28
	facade_band_material.emission_enabled = true
	facade_band_material.emission = theme.trim_color.lightened(0.18)
	facade_band_material.emission_energy_multiplier = 0.46
	# 立面门洞贯穿本层高度，让上下两端都沿同一门轴进入楼梯间。
	var opening := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M if has_door else 0.0
	var segment_length := (length - opening) * 0.5 if has_door else length
	var centers: Array[float] = [0.0]
	if has_door:
		centers = [
			-(opening * 0.5 + segment_length * 0.5),
			opening * 0.5 + segment_length * 0.5,
		]
	for segment_index in range(centers.size()):
		var segment_center := float(centers[segment_index])
		var center := Vector3.ZERO
		if horizontal:
			center = Vector3(
				segment_center,
				-ROOFTOP_FACADE_HEIGHT * 0.5,
				-dimensions.y * 0.5 if direction == "north" else dimensions.y * 0.5
			)
		else:
			center = Vector3(
				-dimensions.x * 0.5 if direction == "west" else dimensions.x * 0.5,
				-ROOFTOP_FACADE_HEIGHT * 0.5,
				segment_center
			)
		var size := (
			Vector3(segment_length, ROOFTOP_FACADE_HEIGHT, 0.54)
			if horizontal
			else Vector3(0.54, ROOFTOP_FACADE_HEIGHT, segment_length)
		)
		# 立面是视觉楼体；屋顶边界、门和楼梯间各自承担真实碰撞，避免重复墙体卡人。
		_spawn_prefab("RooftopExteriorWall_%s" % direction, ROOFTOP_FACADE_PREFAB, center, size, facade_material)
		for band_y in [-0.72, -5.28]:
			var band_center := Vector3(center.x, band_y, center.z)
			var band_size := (
				Vector3(segment_length, 0.18, 0.62)
				if horizontal
				else Vector3(0.62, 0.18, segment_length)
			)
			_spawn_prefab("RooftopExteriorBand_%s" % direction, ROOFTOP_FACADE_BAND_PREFAB, band_center, band_size, facade_band_material)


func _build_rooftop_railing(direction: String, dimensions: Vector2) -> void:
	# v0.1：栏杆下梁底贴地板面 Y=0，上梁顶贴 post 顶 Y=1.32，消除“浮空”问问题。
	const RAIL_THICKNESS := 0.12
	const POST_HEIGHT := 1.32
	const RAIL_LOWER_CENTER_Y := RAIL_THICKNESS * 0.5      # 0.06，底边贴地板
	const RAIL_UPPER_CENTER_Y := POST_HEIGHT - RAIL_THICKNESS * 0.5  # 1.26，顶边贴 post 顶
	const POST_CENTER_Y := POST_HEIGHT * 0.5                # 0.66，底边贴地板
	var horizontal := direction in ["north", "south"]
	var length := dimensions.x if horizontal else dimensions.y
	var has_door := doors.has(direction)
	var opening := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M if has_door else 0.0
	var segment_length := (length - opening) * 0.5 if has_door else length
	var centers: Array[float] = [0.0]
	if has_door:
		centers = [
			-(opening * 0.5 + segment_length * 0.5),
			opening * 0.5 + segment_length * 0.5,
		]
	for segment_index in range(centers.size()):
		var segment_center := float(centers[segment_index])
		var center := Vector3.ZERO
		if horizontal:
			center = Vector3(segment_center, RAIL_LOWER_CENTER_Y, -dimensions.y * 0.5 if direction == "north" else dimensions.y * 0.5)
		else:
			center = Vector3(-dimensions.x * 0.5 if direction == "west" else dimensions.x * 0.5, RAIL_LOWER_CENTER_Y, segment_center)
		var rail_size := Vector3(segment_length, RAIL_THICKNESS, 0.18) if horizontal else Vector3(0.18, RAIL_THICKNESS, segment_length)
		_spawn_prefab("RooftopRailLower_%s_%02d" % [direction, segment_index], ROOFTOP_RAIL_LOWER_PREFAB, center, rail_size, _trim_material)
		var upper_center := center
		upper_center.y = RAIL_UPPER_CENTER_Y
		_spawn_prefab("RooftopRailUpper_%s_%02d" % [direction, segment_index], ROOFTOP_RAIL_UPPER_PREFAB, upper_center, rail_size, _trim_material)
		var post_count := maxi(2, int(segment_length / 4.0) + 1)
		for post_index in range(post_count):
			var ratio := float(post_index) / float(maxi(1, post_count - 1))
			var offset := lerpf(-segment_length * 0.5, segment_length * 0.5, ratio)
			var post_position := center
			if horizontal:
				post_position.x += offset
			else:
				post_position.z += offset
			post_position.y = POST_CENTER_Y
			_spawn_prefab("RooftopRailPost_%s_%02d_%02d" % [direction, segment_index, post_index], ROOFTOP_RAIL_POST_PREFAB, post_position, Vector3(0.16, POST_HEIGHT, 0.16), _trim_material)


func _build_tower_module_shell(dimensions: Vector2) -> void:
	if (
		room_type == "FACILITY"
		and is_equal_approx(dimensions.x, 30.0)
		and is_equal_approx(dimensions.y, 30.0)
	):
		_build_base_facility_shell(dimensions)
		return
	if room_type == "STAIR_LOBBY" and _can_build_safe_room_shell(dimensions):
		_build_safe_room_shell(dimensions)
		return
	# v0.1 v2：4 拐角 + 边墙拟合 + 门洞
	_build_tower_wall_v2(dimensions)


## 入口安全房只在 15×15m 塔楼格、且恰好两扇门时才走 v007 单一布局整房旋转。
## 任何非常规配置一律回退旧拼装，避免把门洞留在没有开门的那面墙上。
func _can_build_safe_room_shell(dimensions: Vector2) -> bool:
	if not is_equal_approx(dimensions.x, dimensions.y):
		return false
	if not is_equal_approx(dimensions.x, TOWER_GEOMETRY.COMBAT_STAIR_LOBBY_SIZE_M):
		return false
	if doors.size() != SAFE_ROOM_DOOR_SIDES.size():
		return false
	return _safe_room_rotation_steps() >= 0


## v007 正式美术：v004 通用墙/地/门 + 17 个房间包，整房按实际门向旋转。
## 碰撞策略沿用 v004 组件契约 collision_owner=self：墙与门墙自带的 0.30m 结构碰撞
## 就是玩法阻挡，本函数不再叠加旧的逐段 0.30m 代理，避免同位置两套静态碰撞。
## 地砖包与门扇包的内嵌碰撞则必须去掉：楼板承重由 TowerFloorStage3D._build_support()
## 统一持有，门扇通行由 RoomDoor3D 的升降碰撞持有（见组件自身的 runtime_collision_note）。
func _build_safe_room_shell(dimensions: Vector2) -> void:
	var rotation_steps := maxi(0, _safe_room_rotation_steps())
	var rotation_y := float(rotation_steps) * PI * 0.5
	var art_root := Node3D.new()
	art_root.name = "SafeRoomArtRoot"
	art_root.set_meta("asset_id", SAFE_ROOM_ART_ASSET_ID)
	art_root.set_meta("asset_version", SAFE_ROOM_ART_VERSION)
	art_root.set_meta("art_source", "entry_safe_room/%s" % SAFE_ROOM_ART_VERSION)
	art_root.set_meta("room_orientation_steps", rotation_steps)
	art_root.set_meta("authoring_note", "v007 单一方位；按本层门向整房旋转，不按方位分版本。")
	art_root.rotation.y = rotation_y
	add_child(art_root)
	# 四角补 L 型墙角（仅远征开启）。L 臂各沿边覆盖 5m，所以开启后每条边两端各 5m
	# 让位给 L 臂，直墙只留「沿边偏移 = 0」的中段槽位；门洞本来就在中段槽位上，不受影响。
	var use_corner_l := safe_room_corner_l and _safe_room_corner_layout_fits(dimensions)
	if safe_room_corner_l and not use_corner_l:
		push_warning("DungeonRoom3D: 安全房 %s 尺寸 %s 不满足四角 L 件布局，回退 12 段直墙" % [
			room_id, str(dimensions)
		])
	var wall_count := 0
	var expected_wall_count := 0
	for slot in SAFE_ROOM_WALL_SLOTS:
		if use_corner_l and not safe_room_slot_is_edge_middle(slot as Array):
			continue
		expected_wall_count += 1
		if _build_safe_room_wall_slot(art_root, slot as Array, rotation_y):
			wall_count += 1
	var corner_count := _spawn_safe_room_corners(dimensions) if use_corner_l else 0
	var tile_count := _build_safe_room_floor_tiles(art_root)
	var package_count := _build_safe_room_packages(art_root)
	# 门扇仍走通用 _build_door：v007 门洞切向中心就是 5m 网格中段（偏移 0），
	# 与 _build_door 读取的 tower_wall_door_offset_* 默认值一致，门扇正好落在门垛之间。
	for direction in doors:
		_build_door(direction, str(door_targets.get(direction, "")), dimensions)
	set_meta("safe_room_art_version", SAFE_ROOM_ART_VERSION)
	set_meta("safe_room_orientation_steps", rotation_steps)
	set_meta("safe_room_corner_l", use_corner_l)
	set_meta("safe_room_corner_module_count", corner_count)
	set_meta("safe_room_wall_module_count", wall_count)
	# 期望值随布局模式变化（12 段直墙 / 4 段中段），写进 meta 让验收按同一口径推导，
	# 不在验收脚本里硬编码 10 或 12。
	set_meta("safe_room_wall_expected_count", expected_wall_count)
	set_meta("safe_room_floor_tile_count", tile_count)
	set_meta("safe_room_package_count", package_count)
	if wall_count != expected_wall_count:
		push_warning("DungeonRoom3D: 安全房 %s 墙组件缺失 (%d/%d)" % [
			room_id, wall_count, expected_wall_count
		])
	if use_corner_l and corner_count != SAFE_ROOM_CORNER_IDS.size():
		push_warning("DungeonRoom3D: 安全房 %s 四角 L 件缺失 (%d/%d)" % [
			room_id, corner_count, SAFE_ROOM_CORNER_IDS.size()
		])


## 四角 L 件布局是否成立：每条边的槽位数与尺寸必须能拆成「L 臂 5m + 中段 5m + L 臂 5m」。
## 期望边长由清单推出（3 个 5m 槽位 = 15m），不硬编码 15；不成立时退回 12 段直墙，
## 让「四角补 L」这件事有一条会失败的保护，而不是静默错位。
func _safe_room_corner_layout_fits(dimensions: Vector2) -> bool:
	var grid := TOWER_GEOMETRY.GRID_UNIT_M
	var side_slots := 0
	for slot in SAFE_ROOM_WALL_SLOTS:
		if str((slot as Array)[4]) == "north":
			side_slots += 1
	if side_slots < 3:
		return false
	var side_length := grid * float(side_slots)
	return (
		is_equal_approx(dimensions.x, side_length)
		and is_equal_approx(dimensions.y, side_length)
	)


## 槽位是否落在边的中段（沿边偏移 = 0）。北/南槽位沿 X 铺，东/西槽位沿 Z 铺。
## 静态：验收脚本要按同一口径推导期望墙数，禁止各自复述一遍判据。
static func safe_room_slot_is_edge_middle(slot: Array) -> bool:
	if slot.size() < 5:
		return false
	var direction := str(slot[4])
	var along := float(slot[0]) if direction in ["north", "south"] else float(slot[1])
	return absf(along) < 0.001


## 四角 L 件开启后保留的中段槽位数（= 每条边 1 段，四条边共 4 段）。
static func safe_room_middle_slot_count() -> int:
	var count := 0
	for slot in SAFE_ROOM_WALL_SLOTS:
		if safe_room_slot_is_edge_middle(slot as Array):
			count += 1
	return count


## 按「世界角位」直接摆放四角 L 件。
## 与「原生四角 + art_root 整房旋转」等价：SAFE_ROOM_CORNER_IDS 是 90° 旋转的置换环，
## 且 _spawn_room_corner 的 rotation_y 与角位一一对应（SW 0° / SE 90° / NE 180° / NW −90°），
## 两者相加正好等于整房旋转角。这样摆可以让 _configure_corner_camera_collisions()
## 拿到世界朝向的角 id —— 镜头下压规则按世界南北墙判定，传原生 id 会转错向。
func _spawn_safe_room_corners(dimensions: Vector2) -> int:
	var half := dimensions * 0.5
	var placed := 0
	for corner_id in SAFE_ROOM_CORNER_IDS:
		_spawn_room_corner(_safe_room_corner_position(half, corner_id), corner_id)
		placed += 1
	return placed


func _safe_room_corner_position(half: Vector2, corner_id: String) -> Vector2:
	match corner_id:
		"NW":
			return Vector2(-half.x, -half.y)
		"NE":
			return Vector2(half.x, -half.y)
		"SW":
			return Vector2(-half.x, half.y)
		_:
			return Vector2(half.x, half.y)


## 解析整房旋转步数：把授权布局的门轴墙集合 {南, 东} 转到本层实际门向集合。
## 实测 98F→78F 只出现 {东,南}/{西,南}/{东,北}/{西,北} 四种相邻组合，
## 恰好对应 0/−1/+1/2 步（0°/270°/90°/180°）；无法匹配时返回 -1 并回退旧拼装。
func _safe_room_rotation_steps() -> int:
	for step in range(4):
		var angle := float(step) * PI * 0.5
		var rotated: Array[String] = []
		for native_direction in SAFE_ROOM_DOOR_SIDES:
			rotated.append(_rotated_direction(native_direction, angle))
		if _same_direction_set(rotated, doors):
			return step
	return -1


func _rotated_direction(direction: String, angle: float) -> String:
	var vector := Vector3.ZERO
	match direction:
		"north":
			vector = Vector3(0.0, 0.0, -1.0)
		"south":
			vector = Vector3(0.0, 0.0, 1.0)
		"east":
			vector = Vector3(1.0, 0.0, 0.0)
		"west":
			vector = Vector3(-1.0, 0.0, 0.0)
		_:
			return direction
	var rotated := vector.rotated(Vector3.UP, angle)
	if absf(rotated.x) >= absf(rotated.z):
		return "east" if rotated.x > 0.0 else "west"
	return "south" if rotated.z > 0.0 else "north"


func _same_direction_set(a: Array[String], b: Array) -> bool:
	if a.size() != b.size():
		return false
	for direction in a:
		if direction not in b:
			return false
	return true


## 一个 5m 墙槽位：门墙（含 2.2×2.5 门洞）或实墙，按槽位角度落在 ±7.5 边界网格线上。
func _build_safe_room_wall_slot(art_root: Node3D, slot: Array, rotation_y: float) -> bool:
	if slot.size() < 5:
		return false
	var uses_door := bool(slot[3])
	var native_direction := str(slot[4])
	var module := (
		SAFE_ROOM_WALL_DOOR_PREFAB if uses_door else SAFE_ROOM_WALL_STANDARD_PREFAB
	).instantiate() as Node3D
	if module == null:
		push_error("DungeonRoom3D: 安全房 v007 墙组件实例化失败 (%s)" % native_direction)
		return false
	module.name = "SafeRoomWall_%s_%s" % [
		native_direction.capitalize(),
		"Door" if uses_door else "Solid",
	]
	module.position = Vector3(float(slot[0]), 0.0, float(slot[1]))
	module.rotation.y = deg_to_rad(float(slot[2]))
	# tower_wall_direction 必须记“整房旋转之后”的世界朝向：TowerDescent3D 的镜头
	# 探针（_camera_wall_expectation）与塔楼网格验收都按世界朝向读这个 meta。
	# 授权文件里的原生方位另存 stair_lobby_native_direction，便于回溯 v007 布局。
	var world_direction := _rotated_direction(native_direction, rotation_y)
	module.set_meta("tower_wall_direction", world_direction)
	module.set_meta("stair_lobby_native_direction", native_direction)
	module.set_meta("grid_unit_m", TOWER_GEOMETRY.GRID_UNIT_M)
	# 摄像机下墙规则按“旋转之后”的实际世界朝向来标，房内看到的南北墙才正确。
	_set_camera_lower_wall_on_static_bodies(
		module,
		world_direction in ["north", "south"]
	)
	_set_geometry_shadow_casting(module, true)
	module.set_meta("shadow_policy", "cast_and_receive")
	art_root.add_child(module)
	if uses_door and world_direction in ["north", "south"]:
		# 南北向门洞开门后不能留实体碰撞，用 camera-only 门墙代理承接 TowerDescent3D
		# 的镜头探针，与旧塔楼拼装路径（_build_corner_aware_wall_run）同契约。
		# 挂在 art_root 下继承整房旋转，所以这里传的是槽位局部变换。
		_add_camera_only_door_wall_proxy(
			world_direction,
			module.position,
			module.rotation.y,
			0,
			art_root
		)
	return true


## 3×3 棋盘地砖：c01 = (row + col) 偶数的 5 块角/中心砖，c02 = 其余 4 块。
## 砖面顶面按每个组件自己的 snap_to_walk_plane_offset_m 落到 Y=0：c01 结构厚 0.056、
## c02 结构厚 0.081，两版厚度不同，不能共用一个硬编码偏移。
func _build_safe_room_floor_tiles(art_root: Node3D) -> int:
	var placed := 0
	for row in range(3):
		for column in range(3):
			var uses_c01 := (row + column) % 2 == 0
			var tile := (
				SAFE_ROOM_FLOOR_TILE_C01_PREFAB if uses_c01 else SAFE_ROOM_FLOOR_TILE_C02_PREFAB
			).instantiate() as Node3D
			if tile == null:
				push_error("DungeonRoom3D: 安全房 v007 地砖实例化失败 (r%02d_c%02d)" % [
					row + 1, column + 1
				])
				continue
			tile.name = "SafeRoomFloorTile_R%02d_C%02d" % [row + 1, column + 1]
			var snap_offset: float = tile.get_meta("snap_to_walk_plane_offset_m", 0.0)
			tile.position = Vector3(
				SAFE_ROOM_FLOOR_GRID_M * (float(column) - 1.0),
				snap_offset,
				SAFE_ROOM_FLOOR_GRID_M * (float(row) - 1.0)
			)
			tile.set_meta("walk_plane_snap_y", snap_offset)
			_disable_static_collision_descendants(tile)
			art_root.add_child(tile)
			placed += 1
	return placed


## 17 个房间包逐件实例化。摆位不在脚本里硬编码：每个包的 PackedScene 根节点都带
## room_placement_position 元数据（范式 B 契约），y 统一减去行走面高差即可落到 Y=0。
func _build_safe_room_packages(art_root: Node3D) -> int:
	var placed := 0
	for package_id in SAFE_ROOM_PACKAGE_IDS:
		# 路径恒定契约：运行资产不含版本号（版本事实在 metadata/asset_version 与台账）。
		var scene_path := "%sentry_safe_room/%s/%s_root_top3d.tscn" % [
			SAFE_ROOM_RUNTIME_ROOT,
			package_id,
			package_id,
		]
		if not ResourceLoader.exists(scene_path):
			push_warning("DungeonRoom3D: 安全房 v007 缺少房间包 %s" % scene_path)
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("DungeonRoom3D: 安全房 v007 房间包无法加载 %s" % scene_path)
			continue
		var package := packed.instantiate() as Node3D
		if package == null:
			push_error("DungeonRoom3D: 安全房 v007 房间包根节点必须是 Node3D: %s" % scene_path)
			continue
		package.name = "SafeRoomPackage_%s" % package_id
		var placement: Vector3 = package.get_meta("room_placement_position", Vector3.ZERO)
		package.position = Vector3(
			placement.x,
			placement.y - SAFE_ROOM_WALK_LIFT_M,
			placement.z
		)
		package.set_meta("room_package_id", package_id)
		art_root.add_child(package)
		placed += 1
	return placed


## 关掉一件美术包自带的静态碰撞。用于两类去重：地砖（楼板承重归 TowerFloorStage3D）
## 与门扇（通行归 RoomDoor3D 的升降碰撞）。只关碰撞层与形状，不删节点，便于运行时排查。
func _disable_static_collision_descendants(root: Node) -> void:
	for value in root.find_children("*", "StaticBody3D", true, false):
		var body := value as StaticBody3D
		if body == null:
			continue
		body.collision_layer = 0
		body.collision_mask = 0
		body.set_meta("collision_deduped_by", "DungeonRoom3D")
		for shape_value in body.find_children("*", "CollisionShape3D", true, false):
			var shape := shape_value as CollisionShape3D
			if shape != null:
				shape.disabled = true


## —— 授权布局壳体装配（2026-09-20，区块00 主人的办公室 98F）——
##
## 输入是外部摆位源逐房导出的 5m 组件实例清单（房间局部坐标）。本函数只做四件事：
##   ① 组件实例化（L 角件 / 实墙 / 门墙 / 地砖），位置与朝向一律取清单值，不重算；
##   ② **门槽顶替**：清单里坐在「门墙面上 + 沿墙偏移 = 门槽」的实墙，自动换成门墙。
##      门槽的唯一口径是 _plan_room_layout() 写进本节点的 tower_wall_door_offset_<side>，
##      不在清单里另存一份 —— 否则布线一改，门扇与门洞就会静默错位。
##   ③ 地砖关掉内嵌静态碰撞（承重归 TowerFloorStage3D._build_support()）；
##   ④ 仍然用 _build_door() 生成本房通行门（开合与升降碰撞归 RoomDoor3D）。
##
## 不生成的东西：4 面程序化墙、角柱、地板、天花、安全房 v007 整房、房间包。
func _build_authored_layout_shell(dimensions: Vector2) -> void:
	var art_root := Node3D.new()
	art_root.name = "AuthoredLayoutArtRoot"
	art_root.set_meta("asset_id", authored_layout_asset_id)
	art_root.set_meta("asset_version", authored_layout_version)
	art_root.set_meta("authored_room_id", authored_layout_room_id)
	art_root.set_meta("authored_layout_shell", true)
	art_root.set_meta("layout_instance_total", authored_layout_instances.size())
	add_child(art_root)

	var half := dimensions * 0.5
	var corner_count := 0
	var solid_count := 0
	var door_wall_count := 0
	var tile_count := 0
	var promoted: Array[String] = []
	var unresolved: Array[String] = []
	for value in authored_layout_instances:
		var instance := value as Dictionary
		var role := str(instance.get("slot_role", ""))
		var local_position := instance.get("position", Vector3.ZERO) as Vector3
		match role:
			"corner_l":
				# 复用塔楼正式角件路径（远征四角 L 件也是这条），
				# 它负责 tower_wall_corner / 镜头下压臂两条契约。
				_spawn_room_corner(
					Vector2(local_position.x, local_position.z),
					str(instance.get("corner_id", "SW"))
				)
				corner_count += 1
			"solid_wall", "door_wall":
				var door_side := _authored_wall_door_side(local_position, half)
				var uses_door := role == "door_wall" or not door_side.is_empty()
				if not _spawn_authored_layout_wall(art_root, instance, uses_door):
					unresolved.append(str(instance.get("name", "")))
					continue
				if uses_door:
					door_wall_count += 1
					if role == "solid_wall":
						promoted.append("%s@%s" % [str(instance.get("name", "")), door_side])
				else:
					solid_count += 1
			"floor_tile":
				if _spawn_authored_layout_floor_tile(art_root, instance):
					tile_count += 1
				else:
					unresolved.append(str(instance.get("name", "")))
			_:
				# door_leaf_preview 等编辑器预览件在导出层已被剔除；漏到这里只可能是
				# 摆位源加了新角色而没人接线 —— 报警而不是静默丢掉。
				push_warning(
					"DungeonRoom3D: 授权布局 %s 出现未接线的 slot_role=%s（实例 %s）"
					% [room_id, role, str(instance.get("name", ""))]
				)

	# 通行门：与程序化路径同一实现，门偏移读同一个 tower_wall_door_offset_* 口径。
	for direction in doors:
		_build_door(direction, str(door_targets.get(direction, "")), dimensions)

	# 每扇门都必须有一条门墙组件承接门洞；缺了就是「门开在实墙上」——
	# 这是几何/门槽校验都查不出的隐形契约，必须有一条会失败的断言盯住。
	#
	# 但授权布局（区块00）的房间之间是**相邻共墙**：摆位源的 lane 归属模型规定
	# 「同一 lane 全局只出一个实例」，一道共享墙只归声明它的那个房间。于是邻房那一侧
	# 的门墙不在本房子树里 —— 门洞由持有该墙的邻房提供。所以判据必须分两种，
	# 不能一律报错（否则共墙布局会稳定假红）：
	#   · 本房在该侧墙面上有墙件 ⇒ 必须是门墙；是实墙就是「门开在实墙上」，报错；
	#   · 本房该侧一件墙都没有 ⇒ 墙归邻房，本房不重复建门墙、不报错，
	#     只把「该门洞已委派给邻房」记成事实，交区块级探针全局核对覆盖。
	var door_wall_sides: Array[String] = []
	var wall_sides: Array[String] = []
	for value in art_root.find_children("*", "Node3D", true, false):
		var module := value as Node3D
		if module == null:
			continue
		var direction := str(module.get_meta("tower_wall_direction", ""))
		if direction.is_empty():
			continue
		if direction not in wall_sides:
			wall_sides.append(direction)
		if str(module.get_meta("asset_id", "")) == DOOR_WALL_COMPONENT_ASSET_ID:
			door_wall_sides.append(direction)
	var delegated_sides: Array[String] = []
	for direction in doors:
		if direction in door_wall_sides:
			continue
		if direction in wall_sides:
			push_error(
				"DungeonRoom3D: 授权布局 %s 的 %s 门没有对应门墙组件（清单里该槽位是实墙或缺失）"
				% [room_id, direction]
			)
		else:
			delegated_sides.append(direction)
	# 委派出去的门洞不建门扇面板：邻房已经建了一扇，两扇同面重叠会 z-fighting。
	# 只藏面板 —— 门节点、升降碰撞、交互提示全部保留，两侧都仍能按 E 开启；
	# 且一条边的两扇门由 _refresh_edge_visuals 同时开合，状态不会分叉。
	for direction in delegated_sides:
		var delegated_door := get_door_node(direction)
		if delegated_door == null:
			continue
		var panel := delegated_door.get_node_or_null("DoorPanel") as Node3D
		if panel != null:
			panel.visible = false
		delegated_door.set_meta("authored_shared_door_delegated", true)
		delegated_door.set_meta("authored_shared_door_owner_side", true)
	set_meta("authored_layout_door_wall_sides", door_wall_sides)
	set_meta("authored_layout_wall_sides", wall_sides)
	set_meta("authored_layout_delegated_door_sides", delegated_sides)

	set_meta("authored_layout_shell", true)
	set_meta("authored_layout_asset_id", authored_layout_asset_id)
	set_meta("authored_layout_version", authored_layout_version)
	set_meta("authored_layout_room_id", authored_layout_room_id)
	set_meta("authored_layout_corner_count", corner_count)
	set_meta("authored_layout_solid_wall_count", solid_count)
	set_meta("authored_layout_door_wall_count", door_wall_count)
	set_meta("authored_layout_floor_tile_count", tile_count)
	set_meta("authored_layout_promoted_walls", promoted)
	set_meta("authored_layout_unresolved_instances", unresolved)
	if not unresolved.is_empty():
		push_warning(
			"DungeonRoom3D: 授权布局 %s 有 %d 件组件无法解析，已跳过"
			% [room_id, unresolved.size()]
		)


## 授权墙件是否正好坐在本房某扇门的位置上（门槽唯一口径 = tower_wall_door_offset_<side>）。
## 返回命中的门向，未命中返回 ""。
func _authored_wall_door_side(local_position: Vector3, half: Vector2) -> String:
	const TOLERANCE := 0.01
	for side in doors:
		var along := float(get_meta("tower_wall_door_offset_%s" % side, 0.0))
		match side:
			"east":
				if is_equal_approx(local_position.x, half.x) and absf(local_position.z - along) <= TOLERANCE:
					return side
			"west":
				if is_equal_approx(local_position.x, -half.x) and absf(local_position.z - along) <= TOLERANCE:
					return side
			"north":
				if is_equal_approx(local_position.z, -half.y) and absf(local_position.x - along) <= TOLERANCE:
					return side
			"south":
				if is_equal_approx(local_position.z, half.y) and absf(local_position.x - along) <= TOLERANCE:
					return side
	return ""


## 摆位源组件 ID → 运行时 PackedScene。全部复用入口安全房 v007 已经在用的四个组件包，
## 不新建资产：摆位源引用的就是同一批 5m 通用组件。
static func _authored_component_prefab(component_id: String) -> PackedScene:
	match component_id:
		WALL_COMPONENT_ASSET_ID:
			return SAFE_ROOM_WALL_STANDARD_PREFAB
		DOOR_WALL_COMPONENT_ASSET_ID:
			return SAFE_ROOM_WALL_DOOR_PREFAB
		FLOOR_TILE_C01_COMPONENT_ID:
			return SAFE_ROOM_FLOOR_TILE_C01_PREFAB
		FLOOR_TILE_C02_COMPONENT_ID:
			return SAFE_ROOM_FLOOR_TILE_C02_PREFAB
		CORNER_L_COMPONENT_ID:
			return TOWER_CORNER_L_PREFAB
		_:
			return null


## 摆位源 rotation_z_deg → 世界门向。与摆位源 face_in_rotation_deg 互逆：
## 0°=南墙、180°=北墙、−90°=西墙、90°=东墙。塔楼网格验收按 tower_wall_direction
## 找门墙，方向标签错了会直接把「门开在实墙上」判成通过。
static func _authored_wall_direction(rotation_y_deg: float) -> String:
	var wrapped := fposmod(rotation_y_deg, 360.0)
	if is_zero_approx(wrapped):
		return "south"
	if is_equal_approx(wrapped, 180.0):
		return "north"
	if is_equal_approx(wrapped, 90.0):
		return "east"
	if is_equal_approx(wrapped, 270.0):
		return "west"
	return ""


func _spawn_authored_layout_wall(art_root: Node3D, instance: Dictionary, uses_door: bool) -> bool:
	var component_id := str(instance.get("component_id", ""))
	var prefab := (
		SAFE_ROOM_WALL_DOOR_PREFAB if uses_door
		else _authored_component_prefab(component_id)
	)
	if prefab == null:
		push_error(
			"DungeonRoom3D: 授权布局 %s 没有组件 %s 的 prefab 映射（实例 %s）"
			% [room_id, component_id, str(instance.get("name", ""))]
		)
		return false
	var module := prefab.instantiate() as Node3D
	if module == null:
		push_error("DungeonRoom3D: 授权墙组件实例化失败（%s）" % component_id)
		return false
	module.name = str(instance.get("name", "AuthoredWall"))
	var rotation_y_deg := float(instance.get("rotation_y_deg", 0.0))
	module.position = instance.get("position", Vector3.ZERO) as Vector3
	module.rotation.y = deg_to_rad(rotation_y_deg)
	var world_direction := _authored_wall_direction(rotation_y_deg)
	if world_direction.is_empty():
		push_error(
			"DungeonRoom3D: 授权墙 %s 的 rotation_z_deg=%s 不是四种墙向之一"
			% [module.name, str(rotation_y_deg)]
		)
	module.set_meta("tower_wall_direction", world_direction)
	module.set_meta("grid_unit_m", TOWER_GEOMETRY.GRID_UNIT_M)
	module.set_meta("authored_component_id", component_id)
	if uses_door:
		module.set_meta("authored_door_wall_promoted", component_id == WALL_COMPONENT_ASSET_ID)
	_set_camera_lower_wall_on_static_bodies(
		module, world_direction in ["north", "south"]
	)
	_set_geometry_shadow_casting(module, true)
	module.set_meta("shadow_policy", "cast_and_receive")
	art_root.add_child(module)
	if uses_door and world_direction in ["north", "south"]:
		# 南北向门洞开门后不能留实体碰撞：与安全房 v007 同契约，补 camera-only 代理。
		_add_camera_only_door_wall_proxy(
			world_direction, module.position, module.rotation.y, 0, art_root
		)
	return true


func _spawn_authored_layout_floor_tile(art_root: Node3D, instance: Dictionary) -> bool:
	var component_id := str(instance.get("component_id", ""))
	var prefab := _authored_component_prefab(component_id)
	if prefab == null:
		push_error(
			"DungeonRoom3D: 授权布局 %s 没有地砖组件 %s 的 prefab 映射（实例 %s）"
			% [room_id, component_id, str(instance.get("name", ""))]
		)
		return false
	var tile := prefab.instantiate() as Node3D
	if tile == null:
		push_error("DungeonRoom3D: 授权地砖实例化失败（%s）" % component_id)
		return false
	tile.name = str(instance.get("name", "AuthoredFloorTile"))
	# 砖面顶面按每个组件自己声明的 snap_to_walk_plane_offset_m 落到 Y=0
	#（c01/c02 结构厚不同，不能共用一个硬编码偏移）。
	var snap_offset := float(tile.get_meta("snap_to_walk_plane_offset_m", 0.0))
	var local_position := instance.get("position", Vector3.ZERO) as Vector3
	tile.position = Vector3(local_position.x, snap_offset, local_position.z)
	tile.rotation.y = deg_to_rad(float(instance.get("rotation_y_deg", 0.0)))
	tile.set_meta("walk_plane_snap_y", snap_offset)
	tile.set_meta("authored_component_id", component_id)
	# 承重归 TowerFloorStage3D._build_support()，这里必须把内嵌静态碰撞关掉。
	_disable_static_collision_descendants(tile)
	art_root.add_child(tile)
	return true


func _build_base_facility_shell(dimensions: Vector2) -> void:
	# V021完整地板表现由基地美术布局直接实例化。不能再生成旧普通/铆钉
	# MultiMesh视觉砖，否则会与Blender完整地板发生双重绘制；FloorSupport仍
	# 保持原30×30m承重与6×6×5m规格，碰撞坐标不变。
	# 99层外圈只使用普通墙和独立门墙；窗墙属于100层，不得混入本层。
	_build_tower_wall_v2(dimensions)


func _add_base_floor_grid(
	node_name: String,
	floor_mesh: Mesh,
	transforms: Array[Transform3D],
	asset_id: String
) -> void:
	var mesh_bounds := floor_mesh.get_aabb()
	var mesh_bottom_y := mesh_bounds.position.y
	var mesh_top_y := mesh_bounds.position.y + mesh_bounds.size.y
	# 不使用mesh_top_y：铆钉、压条等突出几何属于纯表现。若按AABB最高点
	# 对齐，会把整块铆钉地板下压并把原本可见的铁皮压进结构面。
	var visual_origin_y := (
		BASE99_FLOOR_TARGET_SURFACE_Y_M - BASE99_FLOOR_STRUCTURAL_TOP_Y_M
	)
	var decoration_top_y := visual_origin_y + mesh_top_y
	var floor_multimesh := MultiMesh.new()
	floor_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	floor_multimesh.mesh = floor_mesh
	floor_multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		var source_transform := transforms[index]
		var aligned_transform := Transform3D(
			source_transform.basis,
			Vector3(
				source_transform.origin.x,
				visual_origin_y,
				source_transform.origin.z
			)
		)
		floor_multimesh.set_instance_transform(index, aligned_transform)
	var floor_grid := MultiMeshInstance3D.new()
	floor_grid.name = node_name
	floor_grid.multimesh = floor_multimesh
	# 场景结构统一参与真实遮光；玩法阻挡仍由独立碰撞层负责。
	floor_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	floor_grid.set_meta("asset_id", asset_id)
	floor_grid.set_meta("grid_dimensions", Vector2i(6, 6))
	floor_grid.set_meta("instance_count", transforms.size())
	floor_grid.set_meta("floor_index", 99)
	floor_grid.set_meta("visual_mesh_bottom_y_m", mesh_bottom_y)
	floor_grid.set_meta("visual_mesh_top_y_m", mesh_top_y)
	floor_grid.set_meta("visual_structural_top_local_y_m", BASE99_FLOOR_STRUCTURAL_TOP_Y_M)
	floor_grid.set_meta("visual_origin_y_m", visual_origin_y)
	floor_grid.set_meta("visual_surface_y_m", BASE99_FLOOR_TARGET_SURFACE_Y_M)
	floor_grid.set_meta("visual_decoration_top_y_m", decoration_top_y)
	floor_grid.set_meta("collision_surface_y_m", 0.0)
	floor_grid.set_meta("collision_policy", "shared_flat_support_visual_protrusions_ignored")
	floor_grid.set_meta("shadow_policy", "cast_and_receive")
	add_child(floor_grid)


func _get_base99_floor_mesh(prefab: PackedScene, rivet: bool) -> Mesh:
	if rivet and _base99_floor_rivet_mesh != null:
		return _base99_floor_rivet_mesh
	if not rivet and _base99_floor_plain_mesh != null:
		return _base99_floor_plain_mesh
	var source := prefab.instantiate()
	var mesh := TOWER_GEOMETRY.resolve_visual_mesh(source)
	source.free()
	if rivet:
		_base99_floor_rivet_mesh = mesh
	else:
		_base99_floor_plain_mesh = mesh
	return mesh


func _get_tower_floor_tile_mesh() -> Mesh:
	if _tower_floor_tile_mesh != null:
		return _tower_floor_tile_mesh
	var source := TOWER_FLOOR_TILE_PREFAB.instantiate()
	_tower_floor_tile_mesh = TOWER_GEOMETRY.resolve_visual_mesh(source)
	source.free()
	return _tower_floor_tile_mesh


func _build_tower_wall_run(direction: String, dimensions: Vector2) -> void:
	var horizontal := direction in ["north", "south"]
	var length := dimensions.x if horizontal else dimensions.y
	var module_count := maxi(1, int(round(length / TOWER_GEOMETRY.GRID_UNIT_M)))
	var has_door := doors.has(direction)
	# 门模块位置：选择最接近沿墙中心的模块；6 段选择 2 或 3，哪个离 0 近选哪个。
	var door_index := 0
	if has_door:
		var candidate_a := int(floor((module_count - 1) / 2.0))
		var candidate_b := int(ceil((module_count - 1) / 2.0))
		var pos_a := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(candidate_a) + 0.5)
		var pos_b := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(candidate_b) + 0.5)
		door_index = candidate_a if absf(pos_a) <= absf(pos_b) else candidate_b
		var door_offset_along := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(door_index) + 0.5)
		set_meta("tower_wall_door_offset_%s" % direction, door_offset_along)
	var wall_offset := dimensions.y * 0.5 if horizontal else dimensions.x * 0.5
	var solid_transforms: Array[Transform3D] = []
	for module_index in range(module_count):
		var along := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(module_index) + 0.5)
		var module_position := Vector3.ZERO
		var rotation_y := 0.0
		match direction:
			"north":
				module_position = Vector3(along, 0.0, -wall_offset)
			"south":
				module_position = Vector3(along, 0.0, wall_offset)
				rotation_y = PI
			"west":
				module_position = Vector3(-wall_offset, 0.0, along)
				rotation_y = PI * 0.5
			_:
				module_position = Vector3(wall_offset, 0.0, along)
				rotation_y = -PI * 0.5
		var is_door_module := has_door and module_index == door_index
		if is_door_module:
			var module := TOWER_DOOR_PREFAB.instantiate() as Node3D
			module.name = "Imported_DoorWall5M_%s_I%02d" % [
				direction.capitalize(),
				module_index,
			]
			module.position = module_position
			module.rotation.y = rotation_y
			module.set_meta("asset_id", "ENV-TOWER-WALL-DOOR-5M")
			module.set_meta("grid_unit_m", TOWER_GEOMETRY.GRID_UNIT_M)
			module.set_meta("tower_wall_direction", direction)
			_set_camera_lower_wall_on_static_bodies(
				module, direction in ["north", "south"]
			)
			add_child(module)
			_add_tower_wall_collision(
				direction,
				module_position,
				rotation_y,
				true,
				module_index
			)
		else:
			solid_transforms.append(Transform3D(
				Basis(Vector3.UP, rotation_y),
				module_position
			))
	_spawn_solid_wall_visual_instances(direction, solid_transforms)
	_add_tower_solid_run_collision(
		direction,
		length,
		module_count,
		door_index,
		has_door,
		wall_offset
	)


func _build_tower_wall_multimesh(
	direction: String,
	transforms: Array[Transform3D]
) -> void:
	var mesh := _get_tower_solid_wall_mesh()
	if mesh == null or transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	# 通用墙视觉网格为11.9m高；按包围盒底面反算偏移，继续贴合原Y=0基准。
	var visual_floor_offset_y := -mesh.get_aabb().position.y
	for index in range(transforms.size()):
		var wall_transform := transforms[index]
		wall_transform.origin.y += visual_floor_offset_y
		multimesh.set_instance_transform(index, wall_transform)
	var visual := MultiMeshInstance3D.new()
	visual.name = "Imported_SolidWall5M_%s_Run" % direction.capitalize()
	visual.multimesh = multimesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visual.set_meta("asset_id", "ENV-TOWER-WALL-SOLID-5M")
	visual.set_meta("grid_unit_m", TOWER_GEOMETRY.GRID_UNIT_M)
	visual.set_meta("tower_wall_direction", direction)
	add_child(visual)


## v0.1 v2 拼接交替装饰：按偶/奇段分成A/B两个MultiMesh。
## 结构永久驻留后禁止再用“每5m一节点”；材质节奏、阴影和碰撞保持不变。
func _spawn_solid_wall_visual_instances(
	direction: String,
	transforms: Array[Transform3D],
	segment_indices: Array[int] = []
) -> void:
	var uses_base99_visual := room_type == "FACILITY"
	var mesh := _get_base99_solid_wall_mesh() if uses_base99_visual else _get_tower_solid_wall_mesh()
	if mesh == null or transforms.is_empty():
		return
	# 装配基准偏移来自资产声明的 origin_contract（bottom_center → 0）。
	# 旧实现是「-mesh.get_aabb().position.y」反算，注释里写着「通用旧墙以几何中心为
	# 原点、需抬高半层」——2026-09-19 实测证明该描述已过时：塔楼 v003 与基地墙的
	# 网格 AABB 底面都在 y=0，反算结果恒为 0。改用声明值后，美术若加装饰件
	# （门墙门框就下探 0.14m）也不会把整面墙顶高。
	var visual_floor_offset_y := (
		_base99_solid_wall_origin_offset_y
		if uses_base99_visual
		else _tower_solid_wall_origin_offset_y
	)
	var transforms_a: Array[Transform3D] = []
	var transforms_b: Array[Transform3D] = []
	for index in range(transforms.size()):
		var abs_segment_index := (
			segment_indices[index]
			if index < segment_indices.size()
			else index
		)
		var wall_transform := transforms[index]
		wall_transform.origin.y += visual_floor_offset_y
		if abs_segment_index % 2 == 0:
			transforms_a.append(wall_transform)
		else:
			transforms_b.append(wall_transform)
	var material_a: StandardMaterial3D = null
	var material_b: StandardMaterial3D = null
	# 塔楼正式 GLB 自带 PaletteUV（资产侧声明 preserve_authored_palette）；
	# 只有仍在使用主题材质的模块才做暖色 A/B 逐段交替覆盖，否则美术会被盖成单色。
	if not uses_base99_visual and not _tower_solid_wall_preserves_palette:
		material_a = _get_wall_module_material(0)
		material_b = _get_wall_module_material(1)
	var plain_asset_id := (
		"ENV-BASE99-WALL-PLAIN-5X12"
		if uses_base99_visual
		else "ENV-TOWER-WALL-SOLID-5M"
	)
	_add_wall_multimesh_variant(
		direction, "A", mesh, transforms_a, material_a, plain_asset_id
	)
	_add_wall_multimesh_variant(
		direction, "B", mesh, transforms_b, material_b, plain_asset_id
	)


func _add_wall_multimesh_variant(
	direction: String,
	variant: String,
	mesh: Mesh,
	transforms: Array[Transform3D],
	material: StandardMaterial3D,
	asset_id: String
) -> void:
	if mesh == null or transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var visual := MultiMeshInstance3D.new()
	visual.name = "Imported_SolidWall5M_%s_Run_%s" % [direction.capitalize(), variant]
	visual.multimesh = multimesh
	# 基地正式GLB保留自身PaletteUV多表面材质；旧通用墙才使用主题材质覆盖。
	if material != null:
		visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visual.set_meta("asset_id", asset_id)
	visual.set_meta("grid_unit_m", TOWER_GEOMETRY.GRID_UNIT_M)
	visual.set_meta("logical_height_m", TOWER_GEOMETRY.WALL_LOGICAL_HEIGHT_M)
	visual.set_meta("visual_height_m", TOWER_GEOMETRY.WALL_VISUAL_HEIGHT_M)
	visual.set_meta("visual_top_clearance_m", TOWER_GEOMETRY.WALL_VISUAL_TOP_CLEARANCE_M)
	visual.set_meta("tower_wall_direction", direction)
	visual.set_meta("material_variant", variant)
	visual.set_meta("segment_count", transforms.size())
	visual.set_meta("floor_index", 99 if room_type == "FACILITY" else -1)
	visual.set_meta("visual_only", room_type == "FACILITY")
	visual.set_meta("collision_owner", "DungeonRoom3D")
	visual.set_meta(
		"shadow_policy",
		"cast_and_receive"
	)
	add_child(visual)


func _get_tower_solid_wall_mesh() -> Mesh:
	if _tower_solid_wall_mesh != null:
		return _tower_solid_wall_mesh
	var source := TOWER_WALL_PREFAB.instantiate()
	_tower_solid_wall_mesh = TOWER_GEOMETRY.resolve_visual_mesh(source)
	# 资产侧声明该模块自带调色板：运行时不得再用主题 A/B 材质覆盖。
	_tower_solid_wall_preserves_palette = bool(
		source.get_meta("preserve_authored_palette", false)
	)
	_tower_solid_wall_origin_offset_y = TOWER_GEOMETRY.origin_offset_y(source)
	_tower_solid_wall_declared_instantiation = str(
		source.get_meta("runtime_instantiation", "")
	)
	# 本函数有 mesh 缓存，每进程只走一次；断言放这里正好只报一次。
	# 实墙的装配路径是本文件的 _spawn_solid_wall_visual_instances → MultiMesh，
	# 资产必须声明 batched_multimesh。声明成 per_instance_prefab 说明有人
	# 按「逐 prefab 实例化」去过资产或读过契约卡，会得出错误结论。
	if _tower_solid_wall_declared_instantiation == "per_instance_prefab":
		push_error(
			"DungeonRoom3D: 塔楼实墙 prefab 声明 runtime_instantiation=per_instance_prefab，"
			+ "但运行时实际由 MultiMesh 批渲染承载（节点树被丢弃）。"
			+ "请把 prp_tower_wall_solid_5m.tscn 改为 batched_multimesh。"
		)
	source.free()
	return _tower_solid_wall_mesh


func _get_base99_solid_wall_mesh() -> Mesh:
	if _base99_solid_wall_mesh != null:
		return _base99_solid_wall_mesh
	var source := BASE99_WALL_PLAIN_PREFAB.instantiate()
	_base99_solid_wall_mesh = TOWER_GEOMETRY.resolve_visual_mesh(source)
	_base99_solid_wall_origin_offset_y = TOWER_GEOMETRY.origin_offset_y(source)
	source.free()
	return _base99_solid_wall_mesh


func _set_geometry_shadow_casting(root: Node, enabled: bool) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if enabled
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in root.get_children():
		_set_geometry_shadow_casting(child, enabled)


## v0.1 v2 模块化墙拼装：4 拐角 + 边墙 + 门洞
## 以门的世界坐标为锥点：拿到门 world pos → 拆为沿墙距离 → 取最近 5m 段作门洞。
## 拼装规则：
##   1. 4 拐角 L 形各布于房间四角原点，2.5m 双向覆盖
##   2. 4 边墙剔除两端 2.5m 后用 5m 单元填：门洞取距 door world pos 最近的 5m 段
##   3. 门洞剩余部分仍走 _build_door 独立挂门
func _build_tower_wall_v2(dimensions: Vector2) -> void:
	var wall_directions: Array[String] = ["north", "south", "west", "east"]
	if size_class == "rooftop":
		var access_direction := doors[0] if not doors.is_empty() else "west"
		wall_directions.assign([access_direction])
		if access_direction in ["west", "east"]:
			wall_directions.append("north")
			wall_directions.append("south")
		else:
			wall_directions.append("west")
			wall_directions.append("east")
	for open_direction in open_wall_directions:
		wall_directions.erase(open_direction)
	# 1. 拼 4 拐角 L 型（房间四角）
	if size_class != "rooftop":
		_spawn_room_corner(Vector2(-dimensions.x * 0.5, -dimensions.y * 0.5), "NW")
		_spawn_room_corner(Vector2(dimensions.x * 0.5, -dimensions.y * 0.5), "NE")
		_spawn_room_corner(Vector2(-dimensions.x * 0.5, dimensions.y * 0.5), "SW")
		_spawn_room_corner(Vector2(dimensions.x * 0.5, dimensions.y * 0.5), "SE")
	# 2. 每条边跳过两端 2.5m，用 5m 单元填。门洞位置由门 world pos 准动计算。
	# 天台边界由TowerFloorStage3D独立承担；start只保留楼梯口的5m门洞墙，
	# 不再生成65m核心区连续实墙。
	var include_solid_runs := size_class != "rooftop"
	for direction in wall_directions:
		_build_corner_aware_wall_run(direction, dimensions, include_solid_runs)
	# 3. 门洞仍走原 _build_door
	for direction in doors:
		_build_door(direction, str(door_targets.get(direction, "")), dimensions)


## 将房间门 world pos 折算为“沿墙距离”（沿该边从负端点量起的米数）
func _local_along_from_door_world(direction: String, door_world: Vector3, dimensions: Vector2) -> float:
	var horizontal := direction in ["north", "south"]
	var wall_offset := dimensions.y * 0.5 if horizontal else dimensions.x * 0.5
	var center := global_position
	var local := door_world - center
	# 沿墙轴的投影分量：n/s 门走 ±x，w/e 门走 ±z
	var along_local: float
	if horizontal:
		along_local = local.x
		if direction == "south":
			along_local = -along_local
	else:
		along_local = local.z
		if direction == "east":
			along_local = -along_local
	# local 中已含“沿墙距离 = 门 world 距房中心”在墙面投影后的位置
	# （world_x - center_x）与 wall_offset 无关，该偏移是横向墙厚
	return along_local


## 拼接一条边墙：剔除两端 5m（跨过拐角覆盖区）后用 5m 单元填
## 边墙与地砖严格对齐同 5m 网格：地砖 6×6 的房间，边墙 6 段总数中 2 端被拐角覆盖，中间 4 段拼接。
func _build_corner_aware_wall_run(
	direction: String, dimensions: Vector2, include_solid_runs := true
) -> void:
	var horizontal := direction in ["north", "south"]
	var length := dimensions.x if horizontal else dimensions.y
	var wall_offset := dimensions.y * 0.5 if horizontal else dimensions.x * 0.5
	# 门预留：直接读 _plan_room_layout 写入的 meta “tower_wall_door_offset_<dir>”
	var has_door := doors.has(direction)
	var door_index := -1
	if has_door:
		var door_offset_along := float(get_meta("tower_wall_door_offset_%s" % direction, 0.0))
		# 反推 door_index：6 段 30m 房，段中心 = -length/2 + 5*(index+0.5)
		var module_count_full := maxi(1, int(round(length / TOWER_GEOMETRY.GRID_UNIT_M)))
		for module_index in range(module_count_full):
			var segment_center := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(module_index) + 0.5)
			if absf(segment_center - door_offset_along) < 0.01:
				door_index = module_index
				break
	# 墙段范围：从段 1 开始（跳过段 0 拐角覆盖）到段 module_count-2 结束（跳过末段拐角）
	var module_count := maxi(1, int(round(length / TOWER_GEOMETRY.GRID_UNIT_M)))
	var start_index := 1
	var end_index := module_count - 2
	if end_index < start_index:
		return
	var middle_module_count := end_index - start_index + 1
	var solid_transforms: Array[Transform3D] = []
	var solid_segment_indices: Array[int] = []
	for module_index in range(start_index, end_index + 1):
		var along := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * (float(module_index) + 0.5)
		var is_door_module := has_door and module_index == door_index
		var module_position := Vector3.ZERO
		var rotation_y := 0.0
		match direction:
			"north":
				module_position = Vector3(along, 0.0, -wall_offset)
			"south":
				module_position = Vector3(along, 0.0, wall_offset)
				rotation_y = PI
			"west":
				module_position = Vector3(-wall_offset, 0.0, along)
				rotation_y = PI * 0.5
			_:
				module_position = Vector3(wall_offset, 0.0, along)
				rotation_y = -PI * 0.5
		if is_door_module:
			var uses_base99_door := room_type == "FACILITY"
			var module_scene := (
				BASE99_WALL_DOOR_PREFAB if uses_base99_door else TOWER_DOOR_PREFAB
			)
			var module := module_scene.instantiate() as Node3D
			module.name = "Imported_DoorWall5M_%s_I%02d" % [
				direction.capitalize(),
				module_index,
			]
			module.position = module_position
			module.rotation.y = rotation_y
			module.set_meta(
				"asset_id",
				"ENV-BASE99-WALL-DOOR-5X12"
				if uses_base99_door
				else "ENV-TOWER-WALL-DOOR-5M"
			)
			module.set_meta("grid_unit_m", TOWER_GEOMETRY.GRID_UNIT_M)
			module.set_meta("tower_wall_direction", direction)
			if uses_base99_door:
				_set_geometry_shadow_casting(module, true)
				module.set_meta("shadow_policy", "cast_and_receive")
				module.set_meta("floor_index", 99)
			else:
				_apply_module_material_variant(module, module_index)
			_set_camera_lower_wall_on_static_bodies(
				module, direction in ["north", "south"]
			)
			add_child(module)
			_add_tower_wall_collision(
				direction,
				module_position,
				rotation_y,
				true,
				module_index
			)
		elif include_solid_runs:
			solid_transforms.append(Transform3D(
				Basis(Vector3.UP, rotation_y),
				module_position
			))
			solid_segment_indices.append(module_index)
	if not include_solid_runs:
		return
	_spawn_solid_wall_visual_instances(
		direction,
		solid_transforms,
		solid_segment_indices
	)
	var collision_start := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * float(start_index)
	var collision_end := -length * 0.5 + TOWER_GEOMETRY.GRID_UNIT_M * float(end_index + 1)
	_add_corner_aware_solid_run_collision(
		direction,
		wall_offset,
		collision_start,
		collision_end,
		has_door,
		door_index
	)


## 拐角 L 拼装。从 4 个角位置以合适的 rotation 报入。
## corner_id: "NW" / "NE" / "SW" / "SE"
func _spawn_room_corner(corner_pos: Vector2, corner_id: String) -> void:
	# Base99 receives its authored Blender visual. Other tower room types retain
	# the generic corner asset and its existing material-variant behaviour.
	var corner_prefab := BASE99_CORNER_L_PREFAB if room_type == "FACILITY" else TOWER_CORNER_L_PREFAB
	var module := corner_prefab.instantiate() as Node3D
	module.name = "Imported_CornerL5M_%s" % corner_id
	module.position = Vector3(corner_pos.x, 0.0, corner_pos.y)
	# L 默认 long=+X, short=-Z
	# NW 角：需 long=+X(东), short=+Z(南) → rotation_y = -PI/2
	# NE 角：需 long=-X(西), short=+Z(南) → rotation_y = PI
	# SW 角：需 long=+X(东), short=-Z(北) → rotation_y = 0
	# SE 角：需 long=-X(西), short=-Z(北) → rotation_y = PI/2
	match corner_id:
		"NW": module.rotation.y = -PI * 0.5
		"NE": module.rotation.y = PI
		"SW": module.rotation.y = 0.0
		"SE": module.rotation.y = PI * 0.5
	module.set_meta("asset_id", "ENV-TOWER-CORNER-L-5M")
	module.set_meta("tower_wall_corner", corner_id)
	# 拐角两条墙臂使用独立碰撞：SW 的长臂、SE 的短臂才属于南墙。
	# 不能把整个 L 角标记为南墙，否则西/东侧臂也会错误推动摄像机。
	_configure_corner_camera_collisions(module, corner_id)
	var corner_variant_index := 0 if corner_id in ["NW", "SE"] else 1
	_apply_module_material_variant(module, corner_variant_index)
	# Base99's active art layout owns the Blender corner visual. Keep this room
	# module collision-only so its legacy visual cannot overlap the layout GLB.
	if room_type == "FACILITY":
		_set_corner_visual_visible(module, false)
	add_child(module)


func _get_wall_module_material(segment_index: int) -> StandardMaterial3D:
	# 基地走专属尘深蓝墙（不分 A/B 段交替，整墙统一色）。
	# 其他房间沿用塔楼暖色 A/B 段交替，保留模块拼接节奏。
	if room_type == "FACILITY":
		return FACILITY_WALL_MATERIAL
	return WALL_SOLID_MATERIAL_A if segment_index % 2 == 0 else WALL_SOLID_MATERIAL_B


func _apply_module_material_variant(module: Node, segment_index: int) -> void:
	var variant := "A" if segment_index % 2 == 0 else "B"
	var material := _get_wall_module_material(segment_index)
	module.set_meta("segment_index", segment_index)
	module.set_meta("material_variant", variant)
	if bool(module.get_meta("preserve_authored_palette", false)):
		return
	if module is MeshInstance3D:
		(module as MeshInstance3D).material_override = material
	for child in module.get_children():
		_apply_module_material_override(child, material)


func _apply_module_material_override(root: Node, material: Material) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = material
	for child in root.get_children():
		_apply_module_material_override(child, material)


func _set_corner_visual_visible(root: Node, is_visible: bool) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).visible = is_visible
	for child in root.get_children():
		_set_corner_visual_visible(child, is_visible)


func _count_nodes_with_meta(root: Node, key: String, value: Variant) -> int:
	var count := 1 if root.has_meta(key) and root.get_meta(key) == value else 0
	for child in root.get_children():
		count += _count_nodes_with_meta(child, key, value)
	return count


func _sum_int_meta_for_asset(root: Node, asset_id: String, key: String) -> int:
	var total := 0
	if root.get_meta("asset_id", "") == asset_id:
		total += int(root.get_meta(key, 0))
	for child in root.get_children():
		total += _sum_int_meta_for_asset(child, asset_id, key)
	return total


func _count_nodes_with_meta_floor(
	root: Node, key: String, value: Variant, floor_index: int
) -> int:
	var count := 0
	if (
		root.has_meta(key)
		and root.get_meta(key) == value
		and int(root.get_meta("floor_index", -1)) == floor_index
	):
		count = 1
	for child in root.get_children():
		count += _count_nodes_with_meta_floor(child, key, value, floor_index)
	return count


func _sum_int_meta_for_asset_floor(
	root: Node, asset_id: String, key: String, floor_index: int
) -> int:
	var total := 0
	if (
		root.get_meta("asset_id", "") == asset_id
		and int(root.get_meta("floor_index", -1)) == floor_index
	):
		total += int(root.get_meta(key, 0))
	for child in root.get_children():
		total += _sum_int_meta_for_asset_floor(child, asset_id, key, floor_index)
	return total


func _count_shadow_capable_lights() -> int:
	var count := 0
	for room_light in _room_lights:
		if room_light != null and room_light.cast_shadow:
			count += 1
	return count


func _count_active_shadow_lights() -> int:
	var count := 0
	for room_light in _room_lights:
		if room_light == null:
			continue
		var snapshot := room_light.get_snapshot()
		if bool(snapshot.get("shadow_enabled", false)):
			count += 1
	return count


## 拐角 L 拼装：中间段碰撞（跳过两端拐角 + 门洞 span）
func _add_corner_aware_solid_run_collision(
	direction: String,
	wall_offset: float,
	inner_start: float,
	inner_end: float,
	has_door: bool,
	door_index: int
) -> void:
	var body := StaticBody3D.new()
	body.name = "TowerWallCollision_%s_Run" % direction.capitalize()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("camera_lower_wall", direction in ["north", "south"])
	add_child(body)
	var inner_length := inner_end - inner_start
	if inner_length <= 0.0:
		return
	# 以 5m 网格从 inner_start 到 inner_end 划成连续段，门洞位置拆为左右两段
	var segments: Array[Vector2] = []
	segments.append(Vector2(inner_start, inner_end))
	if has_door:
		var door_offset_meta := "tower_wall_door_offset_%s" % direction
		if has_meta(door_offset_meta):
			var door_along := float(get_meta(door_offset_meta))
			var door_left := door_along - TOWER_GEOMETRY.GRID_UNIT_M * 0.5
			var door_right := door_along + TOWER_GEOMETRY.GRID_UNIT_M * 0.5
			var new_segments: Array[Vector2] = []
			for seg in segments:
				var seg_start: float = seg.x
				var seg_end: float = seg.y
				if door_left < seg_end and door_right > seg_start:
					if door_left > seg_start:
						new_segments.append(Vector2(seg_start, minf(door_left, seg_end)))
					if door_right < seg_end:
						new_segments.append(Vector2(maxf(door_right, seg_start), seg_end))
				else:
					new_segments.append(seg)
			segments = new_segments
	for seg in segments:
		var seg_start: float = seg.x
		var seg_end: float = seg.y
		if seg_end <= seg_start:
			continue
		_add_corner_aware_solid_segment_collision(
			body, direction, wall_offset, seg_start, seg_end
		)


func _add_corner_aware_solid_segment_collision(
	body: StaticBody3D,
	direction: String,
	wall_offset: float,
	seg_start: float,
	seg_end: float
) -> void:
	if room_type != "FACILITY" or direction != BASE_ROOFTOP_TRANSIT_DIRECTION:
		_add_wall_run_box_collision(
			body, direction, wall_offset, seg_start, seg_end,
			TOWER_GEOMETRY.FLOOR_HEIGHT_M
		)
		return
	var opening_half_width := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M * 0.5
	var opening_start := BASE_ROOFTOP_TRANSIT_CENTER_ALONG_M - opening_half_width
	var opening_end := BASE_ROOFTOP_TRANSIT_CENTER_ALONG_M + opening_half_width
	var overlap_start := maxf(seg_start, opening_start)
	var overlap_end := minf(seg_end, opening_end)
	if overlap_end <= overlap_start:
		_add_wall_run_box_collision(
			body, direction, wall_offset, seg_start, seg_end,
			TOWER_GEOMETRY.FLOOR_HEIGHT_M
		)
		return
	if seg_start < overlap_start:
		_add_wall_run_box_collision(
			body, direction, wall_offset, seg_start, overlap_start,
			TOWER_GEOMETRY.FLOOR_HEIGHT_M
		)
	_add_wall_run_box_collision(
		body, direction, wall_offset, overlap_start, overlap_end,
		BASE_ROOFTOP_TRANSIT_COLLISION_TOP_M
	)
	if overlap_end < seg_end:
		_add_wall_run_box_collision(
			body, direction, wall_offset, overlap_end, seg_end,
			TOWER_GEOMETRY.FLOOR_HEIGHT_M
		)


func _add_wall_run_box_collision(
	body: StaticBody3D,
	direction: String,
	wall_offset: float,
	seg_start: float,
	seg_end: float,
	height: float
) -> void:
	var run_length := seg_end - seg_start
	if run_length <= 0.0 or height <= 0.0:
		return
	var along := (seg_start + seg_end) * 0.5
	var position := Vector3.ZERO
	var size := Vector3.ZERO
	match direction:
		"north":
			position = Vector3(along, height * 0.5, -wall_offset)
			size = Vector3(run_length, height, 0.30)
		"south":
			position = Vector3(along, height * 0.5, wall_offset)
			size = Vector3(run_length, height, 0.30)
		"west":
			position = Vector3(-wall_offset, height * 0.5, along)
			size = Vector3(0.30, height, run_length)
		_:
			position = Vector3(wall_offset, height * 0.5, along)
			size = Vector3(0.30, height, run_length)
	_add_collision_shape(body, position, size)


func _add_tower_solid_run_collision(
	direction: String,
	length: float,
	module_count: int,
	door_index: int,
	has_door: bool,
	wall_offset: float
) -> void:
	# 5m 实心墙 prefab 自带 WallCollision，这里只用于门洞跨度的可视化标记。
	var body := StaticBody3D.new()
	body.name = "TowerWallCollision_%s_Run" % direction.capitalize()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var runs: Array[Vector2i] = []
	if not has_door:
		runs.append(Vector2i(0, module_count))
	else:
		if door_index > 0:
			runs.append(Vector2i(0, door_index))
		if door_index + 1 < module_count:
			runs.append(Vector2i(door_index + 1, module_count - door_index - 1))
	for run in runs:
		var run_length := float(run.y) * TOWER_GEOMETRY.GRID_UNIT_M
		var along := (
			-length * 0.5
			+ TOWER_GEOMETRY.GRID_UNIT_M * (float(run.x) + float(run.y) * 0.5)
		)
		var position := Vector3.ZERO
		var size := Vector3.ZERO
		match direction:
			"north":
				position = Vector3(along, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, -wall_offset)
				size = Vector3(run_length, TOWER_GEOMETRY.FLOOR_HEIGHT_M, 0.30)
			"south":
				position = Vector3(along, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, wall_offset)
				size = Vector3(run_length, TOWER_GEOMETRY.FLOOR_HEIGHT_M, 0.30)
			"west":
				position = Vector3(-wall_offset, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, along)
				size = Vector3(0.30, TOWER_GEOMETRY.FLOOR_HEIGHT_M, run_length)
			_:
				position = Vector3(wall_offset, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, along)
				size = Vector3(0.30, TOWER_GEOMETRY.FLOOR_HEIGHT_M, run_length)
		_add_collision_shape(body, position, size)


func _add_tower_wall_collision(
	direction: String,
	module_position: Vector3,
	rotation_y: float,
	is_door_module: bool,
	module_index: int
) -> void:
	# 5m 带门墙 prefab 自带 WallCollision；这里用 BoxShape3D 调整门洞两侧门柱+门楣的精确阻挡。
	var body := StaticBody3D.new()
	body.name = "TowerWallCollision_%s_I%02d" % [direction.capitalize(), module_index]
	body.position = module_position
	body.rotation.y = rotation_y
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("camera_lower_wall", direction in ["north", "south"])
	add_child(body)
	if not is_door_module:
		_add_collision_shape(
			body,
			Vector3(0.0, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, 0.0),
			Vector3(
				TOWER_GEOMETRY.GRID_UNIT_M,
				TOWER_GEOMETRY.FLOOR_HEIGHT_M,
				0.30
			)
		)
		return
	if direction in ["north", "south"]:
		_add_camera_only_door_wall_proxy(
			direction, body.position, body.rotation.y, module_index
		)
	var pillar_width := (
		TOWER_GEOMETRY.GRID_UNIT_M - TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M
	) * 0.5
	var pillar_center := (
		TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M * 0.5 + pillar_width * 0.5
	)
	for x in [-pillar_center, pillar_center]:
		_add_collision_shape(
			body,
			Vector3(x, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, 0.0),
			Vector3(pillar_width, TOWER_GEOMETRY.FLOOR_HEIGHT_M, 0.30)
		)
	_add_collision_shape(
		body,
		Vector3(
			0.0,
			TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M
			+ (TOWER_GEOMETRY.FLOOR_HEIGHT_M - TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M) * 0.5,
			0.0
		),
		Vector3(
			TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
			TOWER_GEOMETRY.FLOOR_HEIGHT_M - TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
			0.30
		)
	)


func _add_camera_only_door_wall_proxy(
	direction: String,
	module_position: Vector3,
	rotation_y: float,
	module_index: int,
	parent: Node = null
) -> void:
	# 门洞打开后不能放置世界层实体碰撞，否则会挡住角色与子弹。使用独立
	# camera-only层覆盖完整5m门墙，仅供TowerDescent3D的镜头探针命中。
	var proxy := StaticBody3D.new()
	proxy.name = "CameraOnlyDoorWall_%s_I%02d" % [
		direction.capitalize(),
		module_index,
	]
	proxy.position = module_position
	proxy.rotation.y = rotation_y
	proxy.collision_layer = GameDesignConfig.COLLISION_LAYER_CAMERA_ONLY
	proxy.collision_mask = 0
	proxy.set_meta("camera_lower_wall", true)
	proxy.set_meta("camera_only_door_wall", true)
	proxy.set_meta("tower_wall_direction", direction)
	(parent if parent != null else self).add_child(proxy)
	_add_collision_shape(
		proxy,
		Vector3(0.0, TOWER_GEOMETRY.FLOOR_HEIGHT_M * 0.5, 0.0),
		Vector3(
			TOWER_GEOMETRY.GRID_UNIT_M,
			TOWER_GEOMETRY.FLOOR_HEIGHT_M,
			0.08
		)
	)


func _add_collision_shape(body: StaticBody3D, local_position: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.position = local_position
	collision.shape = shape
	body.add_child(collision)


func _build_floor_partitions(dimensions: Vector2) -> void:
	var mirror := -1.0 if absi(room_seed) % 2 == 0 else 1.0
	if room_type == "FACILITY":
		# v0.1：30m基地中央必须保持通畅；设施全部沿墙摆放。
		return
	var partition_x := mirror * 4.8
	for z in [-8.0, 7.5]:
		_spawn_prefab(
			"FloorPartitionVertical",
			PARTITION_VERTICAL_PREFAB,
			Vector3(partition_x, 1.4, z),
			Vector3(0.28, 2.8, 8.0),
			_wall_material
		)
	var partition_z := mirror * 6.2
	for x in [-8.2, 8.2]:
		var horizontal_partition := _spawn_prefab(
			"FloorPartitionHorizontal",
			PARTITION_HORIZONTAL_PREFAB,
			Vector3(x, 1.4, partition_z),
			Vector3(8.0, 2.8, 0.28),
			_wall_material
		)
		# 内部横向隔墙没有north/south资产朝向；只要它位于角色与固定
		# 后方镜头之间，就应与外围南墙执行同一套抬升收镜逻辑。
		if horizontal_partition != null:
			horizontal_partition.set_meta("camera_lower_wall_component", true)
			_set_camera_lower_wall_on_static_bodies(horizontal_partition, true)


func _build_wall(direction: String, center: Vector3, length: float, axis: Vector3) -> void:
	var has_door := doors.has(direction)
	var thickness := 0.28
	var height := 2.8
	if not has_door:
		var size := Vector3(length, height, thickness) if axis.x > 0.0 else Vector3(thickness, height, length)
		var wall := _spawn_prefab(
			"Wall_%s" % direction,
			WALL_SEGMENT_PREFAB,
			center,
			size,
			_wall_material
		)
		if wall != null and direction in ["north", "south"]:
			_set_camera_lower_wall_on_static_bodies(wall, true)
		return
	var opening := TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M
	var segment_length := (length - opening) * 0.5
	for side in [-1.0, 1.0]:
		var offset: Vector3 = axis * float(side) * (opening * 0.5 + segment_length * 0.5)
		var segment_size := Vector3(segment_length, height, thickness) if axis.x > 0.0 else Vector3(thickness, height, segment_length)
		var wall_segment := _spawn_prefab(
			"Wall_%s" % direction,
			WALL_DOOR_SEGMENT_PREFAB,
			center + offset,
			segment_size,
			_wall_material
		)
		if wall_segment != null and direction in ["north", "south"]:
			_set_camera_lower_wall_on_static_bodies(wall_segment, true)
	var lintel_size := Vector3(opening, 0.45, thickness * 1.28) if axis.x > 0.0 else Vector3(thickness * 1.28, 0.45, opening)
	var lintel := _spawn_prefab(
		"DoorLintel_%s" % direction,
		DOOR_LINTEL_PREFAB,
		center + Vector3(0, 1.18, 0),
		lintel_size,
		_trim_material
	)
	if lintel != null and direction in ["north", "south"]:
		_set_camera_lower_wall_on_static_bodies(lintel, true)


func _build_door(direction: String, target_room_id: String, dimensions: Vector2) -> void:
	var door := DOOR_SCENE.instantiate() as RoomDoor3D
	if door == null:
		push_error("通用RoomDoor3D Prefab实例化失败")
		return
	# 门扇视觉二选一，两条都是正式美术，区别在语义而不是画质：
	#   FACILITY（99F 基地）/ 和平区（区块00）—— 滑升门，自带独立 logic_id 与状态灯，
	#   不随楼层主题换材质；
	#   其余（普通战斗房 / BOSS 房 / 入口安全房）—— 塔楼 A 套门扇，与门墙共用 +Z 约定。
	# 原先战斗房传 null 走程序化深色方块门板；2026-09-19 起统一换成正式门扇。
	door.configure(
		direction,
		target_room_id,
		theme.accent_color,
		BASE99_DOOR_LIFT_PREFAB
		if room_type == "FACILITY" or (room_id == "start" and target_room_id == "facility") or authored_layout_peaceful
		else TOWER_DOOR_LEAF_PREFAB
	)
	door.set_access_policy(door_policies.get(direction, {}) as Dictionary)
	door.set_meta("camera_lower_wall", direction in ["north", "south"])
	# A 套门扇声明 visual_only 且不自带碰撞，本段对它是空跑。
	# 保留为廉价保险：门扇包一旦又带上静态碰撞（B 套那个包就带），它不会随升降门
	# 逻辑启用/禁用，必须让位给 RoomDoor3D 自己的升降碰撞，否则门永远开不了。
	var door_leaf := door.get_node_or_null("DoorPanel/ImportedDoorVisual")
	if door_leaf != null:
		_disable_static_collision_descendants(door_leaf)
	# 与 _build_tower_wall_run 同步：门偏移到沿墙中心最近模块位置 (5m 网格偶数段是 ±2.5m)。
	var door_offset_along := float(get_meta("tower_wall_door_offset_%s" % direction, 0.0))
	# 门扇停在墙件原点上：安全房墙件与塔楼墙件同样以原点坐边界网格线，门墙
	# 门洞切向中心也是 0，门扇正好落在门垛之间，并和走廊起点同线。
	var face_x := dimensions.x * 0.5
	var face_z := dimensions.y * 0.5
	match direction:
		"north":
			door.position = Vector3(door_offset_along, 0, -face_z)
		"south":
			door.position = Vector3(door_offset_along, 0, face_z)
		"west":
			door.position = Vector3(-face_x, 0, door_offset_along)
			door.rotation.y = PI * 0.5
		"east":
			door.position = Vector3(face_x, 0, door_offset_along)
			door.rotation.y = PI * 0.5
	add_child(door)
	_door_nodes[direction] = door


func _set_camera_lower_wall_on_static_bodies(root: Node, enabled: bool) -> void:
	if root is StaticBody3D:
		(root as StaticBody3D).set_meta("camera_lower_wall", enabled)
	for child in root.get_children():
		_set_camera_lower_wall_on_static_bodies(child, enabled)


func _configure_corner_camera_collisions(module: Node, corner_id: String) -> void:
	for value in module.find_children("*", "StaticBody3D", true, false):
		var body := value as StaticBody3D
		var enabled := (
			(corner_id == "SW" and body.name == "WallCollisionLong")
			or (corner_id == "SE" and body.name == "WallCollisionShort")
			or (corner_id == "NW" and body.name == "WallCollisionShort")
			or (corner_id == "NE" and body.name == "WallCollisionLong")
		)
		body.set_meta("camera_lower_wall", enabled)


func _build_content() -> void:
	# 内容生成使用独立稳定种子，卸载再载入后家具类型与搜索点不漂移。
	_rng.seed = room_seed ^ 0x51A77E
	var dimensions := get_dimensions()
	_build_runtime_navigation_surface(dimensions)
	_room_lights.clear()
	if size_class == "rooftop":
		# 100F 天台是露天甲板：本房自带室外光照（TowerAtmosphere3D 的天光反弹 +
		# 太阳 + 城市背景），室内玩法顶灯与墙边开关都属于程序生成室内设施的残留。
		# 业主 2026-09-21 指出「天台为什么还会刷一个电灯开关」⇒ 顶灯与开关一并
		# 清除：_room_lights 留空、_central_light 保持 null、开关节点不实例化。
		# 下游读取点均已做保护（get_debug_snapshot 的两个布尔位、_apply_light_state、
		# _bind_facility_presentation_light_control 与 _bind_light_switch_signal）。
		pass
	elif room_type == "FACILITY":
		# 顶灯与开关已随壳体常驻（_ensure_facility_permanent_lighting）。
		# detail 重建只重新登记常驻灯并绑定美术灯控，不重建实例。
		if (
			_central_light != null
			and is_instance_valid(_central_light)
			and not _room_lights.has(_central_light)
		):
			_room_lights.append(_central_light)
	elif room_type == "BOSS" and minf(dimensions.x, dimensions.y) >= 64.0:
		# 90m终局竞技场不能依赖一盏超大范围点光源：四区灯具让中心与
		# 四周都保持可读，同时仍由同一个墙边开关统一控制。
		for light_index in range(4):
			var x_sign := -1.0 if light_index % 2 == 0 else 1.0
			var z_sign := -1.0 if light_index < 2 else 1.0
			var arena_light := _create_room_light(
				"ArenaCeilingLight_%02d" % (light_index + 1),
				Vector3(
					x_sign * dimensions.x * 0.24,
					0.0,
					z_sign * dimensions.y * 0.24
				),
				theme.fixture_energy * 2.40,
				maxf(
					theme.fixture_range * 1.72,
					minf(dimensions.x, dimensions.y) * 0.58
				),
				room_seed + light_index * 19,
				light_index == 0
			)
			_room_lights.append(arena_light)
		_central_light = _room_lights[0]
	else:
		_central_light = _create_room_light(
			"RoomCeilingLight",
			Vector3.ZERO,
			theme.fixture_energy * (
				2.20 if size_class in ["large", "arena", "floor"] else 1.85
			),
			maxf(
				theme.fixture_range * 1.72,
				minf(dimensions.x, dimensions.y) * 0.94
			),
			room_seed,
			true
		)
		_room_lights.append(_central_light)

	if size_class != "rooftop" and room_type == "FACILITY":
		# FACILITY 的开关已随壳体常驻；detail 重建只需把美术灯控
		# （Art 节点此时已由 _install_facilities 装入）重新绑回开关。
		_bind_facility_presentation_light_control(true)
		_bind_light_switch_signal()
	elif size_class != "rooftop":
		_light_switch = LIGHT_SWITCH_SCENE.instantiate() as RoomLightSwitch3D
		_light_switch.name = "RoomLightSwitch3D"
		_place_light_switch(_light_switch, dimensions)
		# 房间声明的「初始灯亮」优先（开局第一间房），其次才是按房型的默认。
		var starts_on := authored_room_light_on or room_type in ["STAIR_LOBBY", "BOSS"]
		_light_switch.configure_group(_room_lights, starts_on)
		_add_runtime_detail_child(_light_switch)
		_bind_light_switch_signal()
	# 安全房原先还有程序画的地面标线 `_build_stair_lobby_markings()`：
	# 正中一条 StairLobbyRouteGuide（13.00×0.035×1.20m）+ 两侧门内各一条
	# StairLobbyThresholdGuide（0.26×0.045×4.2m），都是青色自发光、离地几厘米。
	# 两批均已按需求整体移除，故这里不再调用。对应 prefab 常量与资产保留，
	# 需要时可原样恢复。
	if room_type == "BOSS":
		_build_boss_arena_dressing()

	var prop_count := (
		3 if size_class in ["small", "tower_cell"]
		else 5 if size_class == "medium"
		else 7 if size_class in ["large", "floor"]
		else 9
	)
	if size_class == "rooftop":
		# 用户要求清空屋顶设施，包含程序生成的家具和可搜容器。
		prop_count = 0
	if room_type == "FACILITY":
		prop_count = 0
	if room_type == "STAIR_LOBBY":
		prop_count = 0
	if room_type == "BOSS":
		# Boss 场地资产自身已提供可辨识掩体；不叠加随机家具破坏走位与主题构图。
		prop_count = 0
	if room_type in ["STORAGE", "SCAVENGE", "BASEMENT"]:
		prop_count += 2
	for index in range(prop_count):
		# 可搜完全随机：每个 prop 独立 50/50。FACILITY / STAIR_LOBBY 在 prop_count=0
		# 的分支里就已经退出，此处不再额外排除任何房间类型。
		var is_search := _rng.randf() < 0.5
		var prop := (SEARCH_SCENE if is_search else FURNITURE_SCENE).instantiate() as RoomFurniture3D
		var type_options: Array[String] = theme.furniture_bias.duplicate()
		if room_type == "STORAGE":
			type_options.append_array(["locker", "shelf", "archive"])
		elif room_type == "UPGRADE":
			type_options.append_array(["workbench", "generator", "console"])
		elif room_type == "TRAP":
			type_options.append_array(["tank", "vat"])
		var prop_type := type_options[_rng.randi_range(0, type_options.size() - 1)] if not type_options.is_empty() else "crate"
		var prop_size := _choose_prop_size(index)
		prop.configure({
			"id": "%s_prop_%02d" % [room_id, index], "type": prop_type, "size": prop_size,
			"searchable": is_search, "accent": theme.accent_color, "base_color": theme.prop_color,
			"loot_value": 4 + theme.difficulty_rank * 2 + (6 if prop_size == "large" else 0),
		})
		var side := -1.0 if index % 2 == 0 else 1.0
		var row := index / 2
		var row_count := int(ceil(float(prop_count) / 2.0))
		var row_ratio := 0.5 if row_count <= 1 else float(row) / float(row_count - 1)
		var x_factor := 0.18 if size_class in ["large", "arena"] and row % 3 == 2 else 0.34
		prop.position = Vector3(side * dimensions.x * x_factor, 0, lerpf(-dimensions.y * 0.28, dimensions.y * 0.28, row_ratio))
		prop.rotation.y = 0.12 * side + PI * (1.0 if side > 0.0 else 0.0)
		_add_runtime_detail_child(prop)
		if is_search:
			prop.searched.connect(_on_prop_searched)

	if room_type in ["MERCHANT", "UPGRADE", "EVENT"]:
		_create_service_station(room_type.to_lower(), dimensions)
	if room_type in ["STAIRS_DOWN", "STAIRS_UP"]:
		_build_vertical_access_marker(room_type)
	if room_type == "TRAP":
		var hazard := HAZARD_SCENE.instantiate() as HazardField3D
		hazard.configure(
			theme.hazard_color,
			3.2 if size_class in ["large", "arena"] else 2.6,
			6 + theme.difficulty_rank * 2
		)
		hazard.position = Vector3(0, 0.06, 0)
		_add_runtime_detail_child(hazard)


func _build_runtime_navigation_surface(dimensions: Vector2) -> void:
	# 每个 ACTIVE 房只保留一块轻量导航面；正式门/跨房授权仍由房间系统拥有。
	# 家具的短距避障交给 Enemy3D 射线兜底，避免运行时烘焙造成主线程尖峰。
	var inset := 1.45
	var half_x := maxf(1.0, dimensions.x * 0.5 - inset)
	var half_z := maxf(1.0, dimensions.y * 0.5 - inset)
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.vertices = PackedVector3Array([
		Vector3(-half_x, 0.08, -half_z),
		Vector3(half_x, 0.08, -half_z),
		Vector3(half_x, 0.08, half_z),
		Vector3(-half_x, 0.08, half_z),
	])
	navigation_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationRegion3D.new()
	region.name = "RuntimeNavigationRegion3D"
	region.use_edge_connections = false
	region.navigation_mesh = navigation_mesh
	_add_runtime_detail_child(region)


func _build_boss_arena_dressing() -> void:
	var arena_scene_path := str(get_meta("arena_scene", ""))
	var arena_asset_id := str(get_meta("arena_asset_id", ""))
	# 普通Dungeon3D仍允许使用无独立场地的通用Boss回退；只有已经声明正式
	# 场地资产ID却缺路径时才是内容错误。
	if arena_scene_path.is_empty() and arena_asset_id.is_empty():
		return
	if arena_scene_path.is_empty() or not ResourceLoader.exists(arena_scene_path):
		push_warning("DungeonRoom3D: Boss room %s has no valid arena scene: %s" % [room_id, arena_scene_path])
		return
	var packed := load(arena_scene_path) as PackedScene
	if packed == null:
		push_error("DungeonRoom3D: failed to load Boss arena scene %s" % arena_scene_path)
		return
	var arena := packed.instantiate() as Node3D
	if arena == null:
		push_error("DungeonRoom3D: Boss arena root must be Node3D: %s" % arena_scene_path)
		return
	arena.name = "BossArenaDressing"
	arena.set_meta("asset_id", str(get_meta("arena_asset_id", "")))
	arena.set_meta("high_detail_streamable", true)
	_add_runtime_detail_child(arena)

	# 美术掩体随高模场地装饰一同流式装卸，但碰撞与造型位置逐件对应，避免
	# 只看得到/撞不到或看不到/仍挡路。永久墙体碰撞不走这条高模流式路径。
	var asset_id := arena_asset_id
	var count := 8 if asset_id.ends_with("ARCHIVE-95") else 6 if asset_id.ends_with("FURNACE-90") else 5
	var radius := 7.8 if count != 5 else 6.5
	var phase_offset := 0.22 if count == 8 else 0.28 if count == 6 else 0.30
	var cover_size := Vector3(3.6, 1.3, 1.1) if count == 8 else Vector3(4.4, 1.5, 0.84) if count == 6 else Vector3(3.2, 1.4, 0.96)
	for index in range(count):
		var angle := TAU * float(index) / float(count) + phase_offset
		var body := StaticBody3D.new()
		body.name = "BossArenaCoverCollision_%02d" % index
		body.position = Vector3(cos(angle) * radius, cover_size.y * 0.5, sin(angle) * radius)
		body.rotation.y = -TAU * float(index) / float(count)
		body.set_meta("boss_arena_cover", true)
		_add_collision_shape(body, Vector3.ZERO, cover_size)
		_add_runtime_detail_child(body)


func _create_service_station(type_id: String, dimensions: Vector2) -> ServiceStation3D:
	var station := SERVICE_SCENE.instantiate() as ServiceStation3D
	if station == null:
		push_error("DungeonRoom3D: failed to instantiate required %s station in %s" % [type_id, room_id])
		return null
	var title: String = str({
		"merchant": "拾荒商终端",
		"upgrade": "武器改造台",
		"event": "异常信号终端",
	}.get(type_id, "废土终端"))
	station.configure(type_id, title, theme.accent_color)
	# 必做目标不能贴在镜头会裁切的北墙。事件终端放到房间中部安全区，
	# 同时避开出生点圆环和两侧家具，保证所有 30×25m 以上房型都可接近。
	var forward_offset := minf(4.5, dimensions.y * 0.18)
	station.position = Vector3(0, 0, -forward_offset)
	station.set_meta("required_room_objective", type_id == "event")
	_add_runtime_detail_child(station)
	station.activated.connect(_on_service_activated)
	return station


func _create_room_light(
	node_name: String,
	planar_position: Vector3,
	p_energy: float,
	p_range: float,
	seed: int,
	shadow: bool
) -> WastelandLight3D:
	var room_light := LIGHT_SCENE.instantiate() as WastelandLight3D
	room_light.name = node_name
	room_light.position = planar_position
	room_light.configure(
		theme.key_light_color,
		p_energy,
		p_range,
		seed,
		shadow,
		false,
		"ceiling",
	)
	if tower_module_shell:
		# 灯具自身的顶装高度是 2.72m；整体抬升后与 9m 天花板贴合。
		room_light.position.y = TOWER_GEOMETRY.FLOOR_HEIGHT_M - 2.72
	room_light.set_light_enabled(false)
	_add_runtime_detail_child(room_light)
	room_light.add_to_group("wasteland_light_3d")
	return room_light


func _place_light_switch(light_switch: RoomLightSwitch3D, dimensions: Vector2) -> void:
	if room_type == "FACILITY":
		# 基地开关放在西侧入口门北面紧邻的第一段5m墙上：
		# 从该墙段的南边向北取 1/3，保留门洞与开关的分离。
		var west_door := get_door_node("west")
		var west_door_along := west_door.position.z if west_door != null else -2.5
		var wall_unit := TOWER_GEOMETRY.GRID_UNIT_M
		var north_wall_south_edge := west_door_along - wall_unit * 0.5
		light_switch.position = Vector3(
			-dimensions.x * 0.5 + 0.34,
			0.0,
			north_wall_south_edge - wall_unit / 3.0,
		)
		light_switch.rotation.y = -PI * 0.5
		light_switch.set_meta("facility_entry_switch_clearance_m", wall_unit * 0.5)
		light_switch.set_meta("facility_entry_direction", "west_entry_north_first_wall")
		return
	var side: int = absi(room_seed) % 4
	var x_margin := minf(4.2, dimensions.x * 0.22)
	var z_margin := minf(4.2, dimensions.y * 0.22)
	match side:
		0:
			light_switch.position = Vector3(x_margin, 0, -dimensions.y * 0.5 + 0.34)
			light_switch.rotation.y = 0.0
		1:
			light_switch.position = Vector3(-x_margin, 0, dimensions.y * 0.5 - 0.34)
			light_switch.rotation.y = PI
		2:
			light_switch.position = Vector3(-dimensions.x * 0.5 + 0.34, 0, z_margin)
			light_switch.rotation.y = -PI * 0.5
		_:
			light_switch.position = Vector3(dimensions.x * 0.5 - 0.34, 0, -z_margin)
			light_switch.rotation.y = PI * 0.5


func _build_vertical_access_marker(type_id: String) -> void:
	var up := type_id != "STAIRS_DOWN"
	var step_material := _material(theme.trim_color.lightened(0.08), 0.68, 0.48)
	for index in range(6):
		var step_height := 0.12 + index * 0.13 if up else 0.77 - index * 0.13
		_spawn_prefab("AccessStep", ACCESS_STEP_PREFAB, Vector3(0, step_height * 0.5, -2.2 + index * 0.75), Vector3(3.0, step_height, 0.72), step_material)
	var label_instance := VERTICAL_ACCESS_LABEL_PREFAB.instantiate() as Node3D
	label_instance.name = "VerticalAccessMarkerLabel"
	label_instance.position = Vector3(0, 2.2, 0)
	var label3d := label_instance.get_node("VerticalAccessLabel") as Label3D
	if label3d != null:
		label3d.text = "电梯 / 垂直层" if type_id == "ELEVATOR" else "上层" if up else "地下层"
		label3d.modulate = theme.accent_color.lightened(0.18)
	_add_runtime_detail_child(label_instance)


func _choose_prop_size(index: int) -> String:
	if size_class == "small":
		return "small" if index % 3 != 0 else "medium"
	if size_class == "large":
		return ["small", "medium", "large"][index % 3]
	if size_class == "arena":
		return ["medium", "large", "small"][index % 3]
	return "medium" if index % 3 != 0 else "small"


func _build_trigger() -> void:
	var dimensions := get_dimensions()
	var area := Area3D.new()
	area.name = "RoomTrigger"
	area.collision_layer = 0
	area.collision_mask = 1
	add_child(area)
	var shape := BoxShape3D.new()
	var min_local_y := -1.0 if room_type == "FACILITY" else ROOM_OWNERSHIP_MIN_LOCAL_Y_M
	var max_local_y := (
		TOWER_GEOMETRY.FLOOR_HEIGHT_M + 0.8
		if room_type == "FACILITY"
		else ROOM_OWNERSHIP_MAX_LOCAL_Y_M
	)
	var trigger_height := max_local_y - min_local_y
	shape.size = Vector3(
		maxf(0.01, dimensions.x - ROOM_OWNERSHIP_BOUNDARY_INSET_M * 2.0),
		trigger_height,
		maxf(0.01, dimensions.y - ROOM_OWNERSHIP_BOUNDARY_INSET_M * 2.0)
	)
	var collision := CollisionShape3D.new()
	collision.position.y = (min_local_y + max_local_y) * 0.5
	collision.shape = shape
	area.add_child(collision)
	area.body_entered.connect(_on_room_body_entered)


func _build_spawn_points() -> void:
	var dimensions := get_dimensions()
	var count := (
		4 if size_class == "tower_cell"
		else 3 if size_class == "small"
		else 5 if size_class == "medium"
		else 7 if size_class == "large"
		else 9
	)
	for index in range(count):
		var angle := TAU * float(index) / float(count) + _rng.randf_range(-0.24, 0.24)
		enemy_spawn_points.append(global_position + Vector3(cos(angle) * dimensions.x * 0.23, 0.0, sin(angle) * dimensions.y * 0.23))


## 取第 index 个落点 —— 数量超过环形点位时**必须仍然互不重合**。
## 为什么必须有：布局房（`size_class == "tower_cell"`）只产出 4 个环形点，而设计源的房间级
## 刷怪计划允许一波最多 24 只、单房最多 64 只。若沿用 `index % points.size()` 取点，
## 超出的敌人会**逐只叠在同一坐标**，画面上看起来是「一只怪」而实际是一群 ——
## 数量上限就成了空话，且「填了 6 只」与「填了 4 只」看不出差别。
## 口径：环上点位算第 0 层；超出后逐层退让（每层转一个固定角并缩一档半径），
## 使任意 index 都有确定且互不重合的落点（半径触底后仍靠角度差区分）。
## 公式路径与设计源路径共用本函数（都经 `Dungeon3D._spawn_enemy_batch`），不另设第二套落点算法。
func spawn_point_for_index(index: int) -> Vector3:
	if enemy_spawn_points.is_empty():
		return global_position
	var point_count := enemy_spawn_points.size()
	var safe_index := maxi(0, index)
	var layer := safe_index / point_count
	var base := enemy_spawn_points[safe_index % point_count]
	if layer <= 0:
		return base
	var offset := base - global_position
	var planar := Vector3(offset.x, 0.0, offset.z)
	var angle_shift := SPAWN_POINT_LAYER_ANGLE_STEP * float(layer)
	var radius_scale := maxf(SPAWN_POINT_MIN_RADIUS_SCALE, 1.0 - SPAWN_POINT_LAYER_RADIUS_STEP * float(layer))
	return global_position + planar.rotated(Vector3.UP, angle_shift) * radius_scale


func _on_room_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_3d"):
		return
	call_deferred("_emit_player_entered_if_present", body)


func _emit_player_entered_if_present(body: Node3D) -> void:
	if body == null or not is_instance_valid(body) or not body.is_in_group("player_3d"):
		return
	var inside := (
		contains_world_position(body.global_position, -1.0, TOWER_GEOMETRY.FLOOR_HEIGHT_M + 0.8)
		if room_type == "FACILITY"
		else contains_world_position(body.global_position)
	)
	if not inside:
		return
	if not visited:
		visited = true
	player_entered.emit(self)


func _on_prop_searched(_prop: RoomFurniture3D, loot: Dictionary) -> void:
	var event := loot.duplicate(true)
	event["sound_position"] = _prop.global_position
	prop_searched.emit(self, event)


func _on_service_activated(station: ServiceStation3D) -> void:
	service_activated.emit(self, station)


# —— prefab 通用入口：实例化 + 设位置/缩放/材质
# 预制体内部 mesh/collision 已经是 1×1×1 或真实参考尺寸，scale 整体传递到子节点。
func _spawn_prefab(node_name: String, prefab: PackedScene, position: Vector3, scale_vec: Vector3, material: StandardMaterial3D) -> Node3D:
	if prefab == null:
		push_error("DungeonRoom3D: missing prefab for %s" % node_name)
		return null
	var instance := prefab.instantiate() as Node3D
	if instance == null:
		return null
	instance.name = node_name
	instance.position = position
	instance.scale = scale_vec
	_apply_material_override(instance, material)
	_add_runtime_detail_child(instance)
	return instance


func _apply_material_override(root: Node, material: StandardMaterial3D) -> void:
	if material == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material
		_apply_material_override(child, material)


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _set_collision_enabled(root: Node, enabled: bool, preserve_support := false) -> void:
	if root is CollisionShape3D:
		var collision := root as CollisionShape3D
		var is_support := collision.get_parent() != null and collision.get_parent().name == "FloorBody"
		collision.set_deferred("disabled", false if preserve_support and is_support else not enabled)
	for child in root.get_children():
		_set_collision_enabled(child, enabled, preserve_support)


func _keep_structural_physics_active(root: Node) -> void:
	# RuntimeDetail 由流送状态独立管理；这里只固定房间壳体的墙、门框、门和
	# 楼板碰撞。PROCESS_MODE_ALWAYS 使它们在房间父节点停用脚本时仍参与物理
	# 查询，保证渲染阴影、角色通行和怪物受光使用同一套几何。
	if root == _detail_root or root.name == "RuntimeDetail":
		return
	if root is PhysicsBody3D:
		(root as PhysicsBody3D).process_mode = Node.PROCESS_MODE_ALWAYS
	for child in root.get_children():
		_keep_structural_physics_active(child)


func _has_enabled_support_collision() -> bool:
	# FloorBody 可能嵌套在 prefab 根节点下，递归查找。
	return _find_floor_body_enabled(self)


func _find_floor_body_enabled(root: Node) -> bool:
	if root is StaticBody3D and root.name == "FloorBody":
		for child in root.get_children():
			if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
				return true
	for child in root.get_children():
		if _find_floor_body_enabled(child):
			return true
	return false


func _get_door_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in _door_nodes.values():
		var door := value as RoomDoor3D
		if door != null:
			result.append(door.get_snapshot())
	return result
