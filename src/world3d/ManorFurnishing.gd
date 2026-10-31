extends RefCounted
## 远征03 公馆陈设配方：给每类房间定主题（大厅/卧室/书房……），并按主题摆家具。
##
## ## 为什么主题挂在「空间原型」上，而不是 room_id
##
## 复用键是 `<模板>_<签名>_<原型指纹>`，同一份烘焙文件会被**多间房共用**
## （`combat_25x25` 的「逼仄空厅」一份文件服务 n02/n04/n05/n06/fireplace）。
## 主题若挂在 room_id 上，同一份文件就没法给每间不同的布置；挂在原型上则自然成立：
## 「这类房间是什么性格」由原型回答，而原型是 `(room_type, 短边)` 的纯函数、跨种子恒定。
##
## ## 尺寸口径（2026-10-31 业主反馈后重定）
##
## 素材里的家具是**真实家具尺寸**（边桌 1.34m、沙发 3.13m）—— 实测 prefab 实例的
## AABB 与 `metadata/bounds_size_m` 比值**全为 1.00**，**导入没有缩放过**。
## 但远征03 的房间是 25×25 ~ 50×40 m（EGT 玩法尺度，比篮球场还大），
## 真实尺寸的家具摆进去只占很小一块，俯视几乎看不见。
##
## 业主裁定：「至少放大三倍」。所以：
##   · **占地面积统一 ×3**（x / z）；
##   · 高度**压到墙高以内**：护墙 2.8m，家具最高 2.45m，否则书柜/衣柜会从墙顶戳出去
##     （无天花板，3× 的书柜是 6.5m，会明显高出墙面）；
##   · 高度压缩比单独算，不连带缩小占地面积 —— 俯视主要读的是轮廓。
##
## ## 坐标与朝向
##
## 房间局部坐标，原点在房间中心：`+x` 向东、`+z` 向南。
## 组件 `forward_axis = "+Z"`（正面朝 +Z），所以贴北墙 yaw 0、南墙 180、西墙 90、东墙 270。
##
## ## 硬约束
##
## 1. **不挡门**：同侧 |偏移 − 门位| 小于「半门宽 + 半家具宽 + 0.35」即跳过；
## 2. **不重叠**：贴地件与桌面件除外（它们本来就该被压/叠）；
## 3. **不出墙**：偏移钳到「半墙长 − 墙半厚 − 半家具宽 − 0.05」。

const MANOR := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"
const GRID := 5.0
const WALL_HALF_THICK := 0.25
const DOOR_HALF_WIDTH := 1.1
const DOOR_MARGIN := 0.35

## 占地面积放大倍数（业主：至少三倍）。
##
## ## 为什么最终没用 3
##
## 3× 的占地实测没有依据、只有坏处（数据见 `_exp03_char_vs_furniture_probe`）：
##
##   沙发   3.13m → **9.39m**（角色胶囊直径才 0.68m，等于 13.8 个角色并排）
##   床     2.04×2.13 → **6.12×6.39m**
##   接待台 5.58m → **16.74m**
##
## 角色模型实测高 **2.53m**、占地直径 **0.68m**；一张 6 米长的床、9 米宽的沙发
## 摆进去就是巨人家具。1.8× 已经让沙发明显大于角色（5.6m 宽 = 8 个角色），
## 俯视读得出来，又不至于失真。
const FOOTPRINT_SCALE := 1.8
## 家具高度上限。
##
## 2.60 而不是 2.45：书柜目标高 = 1.02 × 角色高 = 2.58m，压到 2.45 会让它**低于**
## 原比例（2.17m 的书柜理应是最高的家具），层级又塌回去。护墙 2.8m，2.60 仍留 0.2m 余量。
const MAX_HEIGHT := 2.60
## 挂墙件的顶边上限：墙高 2.8m，留 0.1m 缝隙。
const WALL_TOP_LIMIT := 2.70

## 角色模型实测高（米）—— 所有家具高度都以它为标尺，不用绝对米数拍脑袋。
## 见 `tools/_exp03_char_vs_furniture_probe.gd` 的实测输出。
const CHARACTER_HEIGHT := 2.53

## 目标身高 = **角色高的多少倍**，按件给定。
##
## ## 为什么必须逐件给，不能统一一个缩放
##
## 第一版把所有高度封顶到 2.45m，结果扶手椅 / 沙发 / 床 / 边柜 / 盆栽**全都 2.45m**
## （都是角色的 0.97 倍）—— 高度层级被压平，俯视只剩一片同高的「板子」，
## 认不出是什么家具。而书柜(2.17) / 衣柜(2.53) 反而被**压矮**到比原比例还低。
##
## 现在按类别给「该多高」，各自反算缩放比：
##   最矮  茶几 0.45 —— 俯身才够着
##   中间  扶手椅/沙发 0.72、边柜 0.62、床 0.55
##   最高  书柜/衣柜 1.02 —— 房间里最高的家具，靠它压住墙面
const TARGET_HEIGHT_RATIO := {
	# 坐具
	"armchair": 0.72, "sofa": 0.72, "bench": 0.62, "office_chair": 0.72,
	# 桌类
	"console": 0.62, "coffee_table": 0.45, "side_table": 0.58, "nightstand": 0.55,
	"vanity": 0.72, "reception_desk": 0.70,
	# 高大件（房间里最高的东西）
	"bookcase": 1.02, "wardrobe": 1.02,
	# 卧具
	"bed": 0.55,
	# 绿植与陈设
	"plant_compact": 0.62, "plant_large": 0.85, "flower_arrangement": 0.48,
	"candelabra": 0.40, "table_lamp": 0.46, "desk_documents": 0.03,
	"luggage_cart": 0.68,
	# 卫浴
	"bathtub": 0.35, "toilet": 0.36,
}
## 「被人挪过」的随手摆放：一部分家具偏转 10~15 度。
## 只作用于落地件；挂墙件与贴地件保持正。用**确定性**伪随机（种子取主题+序号），
## 同一份烘焙文件每次生成结果一致，不会来回抖。
const TILT_MIN := 10.0
const TILT_MAX := 15.0
## 每 N 件里挑 1 件偏转，避免整屋都歪。
const TILT_EVERY := 3

## 组件尺寸 `(宽, 高, 深)`，单位米 —— 取自各 prefab 的 `metadata/bounds_size_m`
## （`_exp03_furniture_scale_probe` 实测 AABB 与之一致，比值 1.00）。
const SIZES := {
	"armchair": Vector3(1.23, 1.09, 1.05),
	"bath_screen": Vector3(1.19, 1.4, 0.12),
	"bathtub": Vector3(1.7, 0.8, 0.84),
	"bed": Vector3(2.04, 1.25, 2.13),
	"bench": Vector3(1.5, 0.57, 0.45),
	"bookcase": Vector3(1.34, 2.17, 0.50),
	"candelabra": Vector3(0.56, 0.64, 0.32),
	"coffee_table": Vector3(2.03, 0.50, 2.03),
	"console": Vector3(1.34, 0.85, 0.49),
	"desk_documents": Vector3(0.40, 0.05, 0.28),
	"entrance_mat": Vector3(3.0, 0.024, 1.50),
	"flower_arrangement": Vector3(0.50, 1.17, 0.59),
	"luggage_cart": Vector3(1.05, 1.67, 0.65),
	"mirror": Vector3(0.95, 0.95, 0.07),
	"nightstand": Vector3(0.6, 0.61, 0.59),
	"office_chair": Vector3(0.75, 1.09, 0.795),
	"painting": Vector3(1.46, 0.96, 0.15),
	"plant_compact": Vector3(0.97, 1.38, 1.0),
	"plant_large": Vector3(1.54, 1.61, 1.51),
	"reception_desk": Vector3(5.58, 1.27, 1.32),
	"rug_bedroom": Vector3(3.0, 0.053, 4.0),
	"rug_lounge": Vector3(8.0, 0.053, 10.0),
	"rug_runner": Vector3(2.4, 0.053, 5.0),
	"side_table": Vector3(0.63, 0.64, 0.63),
	"sofa": Vector3(3.13, 1.09, 1.0),
	"table_lamp": Vector3(0.38, 0.70, 0.38),
	"toilet": Vector3(0.42, 0.81, 0.63),
	"towel_rail": Vector3(0.68, 0.62, 0.25),
	"vanity": Vector3(2.04, 1.18, 0.67),
	"wall_grille": Vector3(2.6, 1.2, 0.17),
	"wall_lamp": Vector3(0.38, 0.72, 0.54),
	"wardrobe": Vector3(1.84, 2.53, 0.69),
}

## 桌面高度 —— 台灯/文件要摆在这些面上。**存原始高度**，取值时乘该件的高度缩放。
const SURFACE_Y := {
	"console": 0.85, "side_table": 0.64, "coffee_table": 0.50,
	"nightstand": 0.61, "reception_desk": 1.27, "vanity": 1.18,
}

## 挂墙件：贴墙但悬空，`y` 是底边离地高度（不随 FOOTPRINT_SCALE 变）。
const WALL_MOUNT_Y := {
	"painting": 0.75, "mirror": 0.55, "wall_lamp": 0.95,
	"wall_grille": 0.30, "towel_rail": 0.95,
}

## 不加碰撞的件：贴地件（地毯，能走过去）、挂墙件（在高处）、桌面小件（撞不到）。
## 其余落地家具**一律加碰撞**（业主：「组件也没有阻挡」）。
const NO_COLLISION := [
	"rug_lounge", "rug_runner", "rug_bedroom", "entrance_mat",
	"painting", "mirror", "wall_lamp", "wall_grille", "towel_rail",
	"table_lamp", "desk_documents", "candelabra", "flower_arrangement",
]

const THEMES := {
	# ── 王座厅：Boss 房，2000㎡，外木内石。中央石台，家具沿边做「观礼席」 ──
	"throne_hall": {
		"label": "王座厅",
		"items": [
			{"p": "rug_lounge", "cx": 0.0, "cz": 0.0, "flat": true, "y": 0.002},
			{"p": "reception_desk", "wall": "north", "at": 0.0},
			{"p": "candelabra", "wall": "north", "at": -7.0},
			{"p": "candelabra", "wall": "north", "at": 7.0},
			{"p": "console", "wall": "west", "at": -8.0},
			{"p": "candelabra", "wall": "west", "at": -8.0, "surface": "console"},
			{"p": "console", "wall": "west", "at": 0.0},
			{"p": "candelabra", "wall": "west", "at": 0.0, "surface": "console"},
			{"p": "console", "wall": "east", "at": -8.0},
			{"p": "candelabra", "wall": "east", "at": -8.0, "surface": "console"},
			{"p": "console", "wall": "east", "at": 0.0},
			{"p": "candelabra", "wall": "east", "at": 0.0, "surface": "console"},
			{"p": "bench", "wall": "south", "at": -8.0},
			{"p": "bench", "wall": "south", "at": 8.0},
			{"p": "plant_large", "wall": "west", "at": 8.5},
			{"p": "plant_large", "wall": "east", "at": 8.5},
			{"p": "painting", "wall": "south", "at": 0.0},
			{"p": "wall_lamp", "wall": "west", "at": 5.0},
			{"p": "wall_lamp", "wall": "east", "at": 5.0},
		],
	},
	# ── 门厅大堂：枢纽，通窗最亮，唯一「可以停下」的地方 ──
	"grand_lobby": {
		"label": "门厅大堂",
		"items": [
			{"p": "rug_lounge", "cx": 0.0, "cz": 0.0, "flat": true, "y": 0.002},
			{"p": "reception_desk", "cx": 0.0, "cz": -4.0, "yaw": 180.0},
			{"p": "candelabra", "near": "reception_desk", "side": "left", "gap": 0.2, "along": -0.6, "surface": "reception_desk"},
			{"p": "candelabra", "near": "reception_desk", "side": "right", "gap": 0.2, "along": -0.6, "surface": "reception_desk"},
			# 西侧待客角：沙发贴墙，茶几在正前方，扶手椅分列两侧。
			# **写成「关系」而不是坐标** —— 沙发被门位挤开时，茶几和椅子会跟着走。
			{"p": "sofa", "wall": "west", "at": 0.0},
			{"p": "coffee_table", "near": "sofa", "gap": 0.8},
			{"p": "flower_arrangement", "near": "coffee_table", "gap": 0.0, "surface": "coffee_table"},
			{"p": "armchair", "near": "sofa", "side": "left", "gap": 1.0},
			{"p": "armchair", "near": "sofa", "side": "right", "gap": 1.0},
			{"p": "side_table", "near": "sofa", "side": "right", "gap": 4.6},
			# 东侧待客角（第二张沙发覆盖 placed["sofa"]，下面的 near 指向东侧那张）
			{"p": "sofa", "wall": "east", "at": 0.0},
			{"p": "coffee_table", "near": "sofa", "gap": 0.8},
			{"p": "flower_arrangement", "near": "coffee_table", "gap": 0.0, "surface": "coffee_table"},
			{"p": "armchair", "near": "sofa", "side": "left", "gap": 1.0},
			{"p": "armchair", "near": "sofa", "side": "right", "gap": 1.0},
			{"p": "side_table", "near": "sofa", "side": "right", "gap": 4.6},
			# 中轴：接待台到南门之间摆一组长凳 + 盆栽，避免 13m 全空
			{"p": "bench", "cx": -6.0, "cz": 9.0},
			{"p": "bench", "cx": 6.0, "cz": 9.0},
			{"p": "plant_large", "cx": -13.0, "cz": 13.5},
			{"p": "plant_large", "cx": 13.0, "cz": 13.5},
			{"p": "wall_lamp", "wall": "north", "at": -10.0},
			{"p": "wall_lamp", "wall": "north", "at": 10.0},
			{"p": "painting", "wall": "south", "at": -9.0},
			{"p": "painting", "wall": "south", "at": 9.0},
			{"p": "plant_large", "wall": "west", "at": -11.0},
			{"p": "plant_large", "wall": "east", "at": -11.0},
			{"p": "plant_compact", "wall": "south", "at": -15.0},
			{"p": "plant_compact", "wall": "south", "at": 15.0},
		],
	},
	# ── 宴会长廊：45×40，两对长窗。中轴铺毯，两侧列席 ──
	"banquet_gallery": {
		"label": "宴会长廊",
		"items": [
			{"p": "rug_runner", "cx": 0.0, "cz": -6.0, "flat": true, "y": 0.002},
			{"p": "rug_runner", "cx": 0.0, "cz": 0.0, "flat": true, "y": 0.002},
			{"p": "rug_runner", "cx": 0.0, "cz": 6.0, "flat": true, "y": 0.002},
			{"p": "console", "wall": "west", "at": -11.0},
			{"p": "candelabra", "wall": "west", "at": -11.0, "surface": "console"},
			{"p": "console", "wall": "west", "at": -4.0},
			{"p": "candelabra", "wall": "west", "at": -4.0, "surface": "console"},
			{"p": "console", "wall": "west", "at": 3.0},
			{"p": "candelabra", "wall": "west", "at": 3.0, "surface": "console"},
			{"p": "console", "wall": "west", "at": 10.0},
			{"p": "console", "wall": "east", "at": -11.0},
			{"p": "candelabra", "wall": "east", "at": -11.0, "surface": "console"},
			{"p": "console", "wall": "east", "at": -4.0},
			{"p": "candelabra", "wall": "east", "at": -4.0, "surface": "console"},
			{"p": "console", "wall": "east", "at": 3.0},
			{"p": "candelabra", "wall": "east", "at": 3.0, "surface": "console"},
			{"p": "console", "wall": "east", "at": 10.0},
			{"p": "bench", "wall": "north", "at": -13.0},
			{"p": "bench", "wall": "north", "at": 13.0},
			{"p": "plant_large", "wall": "north", "at": -17.0},
			{"p": "plant_large", "wall": "north", "at": 17.0},
			{"p": "wall_lamp", "wall": "south", "at": -12.0},
			{"p": "wall_lamp", "wall": "south", "at": 12.0},
		],
	},
	# ── 客厅：中庭回廊，成对高窗，有光斑 ──
	"drawing_room": {
		"label": "客厅",
		"items": [
			{"p": "rug_bedroom", "cx": 0.0, "cz": 0.0, "flat": true, "y": 0.002},
			{"p": "sofa", "wall": "north", "at": 0.0},
			{"p": "coffee_table", "cx": 0.0, "cz": -6.0},
			{"p": "armchair", "wall": "west", "at": -4.0, "yaw": 90.0},
			{"p": "armchair", "wall": "east", "at": -4.0, "yaw": 270.0},
			{"p": "side_table", "cx": -7.0, "cz": -10.0},
			{"p": "side_table", "cx": 7.0, "cz": -10.0},
			{"p": "table_lamp", "cx": -7.0, "cz": -10.0, "surface": "side_table"},
			{"p": "table_lamp", "cx": 7.0, "cz": -10.0, "surface": "side_table"},
			{"p": "console", "wall": "south", "at": -8.0},
			{"p": "flower_arrangement", "wall": "south", "at": -8.0, "surface": "console"},
			{"p": "console", "wall": "south", "at": 8.0},
			{"p": "flower_arrangement", "wall": "south", "at": 8.0, "surface": "console"},
			{"p": "painting", "wall": "south", "at": 0.0},
			{"p": "plant_compact", "wall": "west", "at": 6.0},
			{"p": "plant_compact", "wall": "east", "at": 6.0},
			{"p": "wall_lamp", "wall": "north", "at": -7.0},
			{"p": "wall_lamp", "wall": "north", "at": 7.0},
		],
	},
	# ── 仆役杂物间：25×25 最暗最小 ──
	"servant_clutter": {
		"label": "仆役杂物间",
		"items": [
			{"p": "bench", "wall": "north", "at": -5.0},
			{"p": "luggage_cart", "wall": "east", "at": -5.0},
			{"p": "luggage_cart", "wall": "east", "at": 3.0},
			{"p": "console", "wall": "south", "at": 5.0},
			{"p": "candelabra", "wall": "south", "at": 5.0, "surface": "console"},
			{"p": "plant_compact", "wall": "west", "at": 4.0},
			{"p": "bookcase", "wall": "west", "at": -5.0},
			{"p": "painting", "wall": "north", "at": 5.0},
		],
	},
	# ── 卧室：更衣前厅（升级点）。床是绝对主角 ──
	"bedroom": {
		"label": "卧室",
		"items": [
			{"p": "bed", "wall": "north", "at": 0.0},
			{"p": "nightstand", "wall": "north", "at": -5.0},
			{"p": "nightstand", "wall": "north", "at": 5.0},
			{"p": "table_lamp", "wall": "north", "at": -5.0, "surface": "nightstand"},
			{"p": "table_lamp", "wall": "north", "at": 5.0, "surface": "nightstand"},
			{"p": "rug_bedroom", "cx": 0.0, "cz": 5.0, "flat": true, "y": 0.002},
			{"p": "wardrobe", "wall": "west", "at": 6.0},
			{"p": "mirror", "wall": "east", "at": -6.0},
			{"p": "bench", "wall": "south", "at": -7.0},
			{"p": "plant_compact", "wall": "east", "at": 7.0},
			{"p": "painting", "wall": "south", "at": 6.0},
		],
	},
	# ── 收藏室：陈列室，单向采光把光压在北面 ──
	"cabinet_room": {
		"label": "收藏室",
		"items": [
			{"p": "rug_bedroom", "cx": 0.0, "cz": 0.0, "flat": true, "y": 0.002},
			{"p": "console", "wall": "south", "at": -8.0},
			{"p": "candelabra", "wall": "south", "at": -8.0, "surface": "console"},
			{"p": "console", "wall": "south", "at": 0.0},
			{"p": "candelabra", "wall": "south", "at": 0.0, "surface": "console"},
			{"p": "console", "wall": "south", "at": 8.0},
			{"p": "candelabra", "wall": "south", "at": 8.0, "surface": "console"},
			{"p": "bookcase", "wall": "west", "at": -6.0},
			{"p": "bookcase", "wall": "west", "at": 2.0},
			{"p": "painting", "wall": "west", "at": 9.0},
			{"p": "painting", "wall": "east", "at": 0.0},
			{"p": "plant_compact", "wall": "east", "at": 9.0},
		],
	},
	# ── 商铺：柜台 + 货架，中央留交易位 ──
	"shopfront": {
		"label": "商铺",
		"items": [
			{"p": "rug_runner", "cx": 0.0, "cz": 7.0, "flat": true, "y": 0.002},
			{"p": "reception_desk", "cx": 0.0, "cz": -7.0, "yaw": 180.0},
			{"p": "candelabra", "cx": -5.0, "cz": -7.0, "surface": "reception_desk"},
			{"p": "candelabra", "cx": 5.0, "cz": -7.0, "surface": "reception_desk"},
			{"p": "bookcase", "wall": "west", "at": -7.0},
			{"p": "bookcase", "wall": "west", "at": 1.0},
			{"p": "bookcase", "wall": "east", "at": -3.0},
			{"p": "bookcase", "wall": "east", "at": 5.0},
			{"p": "luggage_cart", "wall": "east", "at": 12.0},
			{"p": "wall_lamp", "wall": "north", "at": -9.0},
			{"p": "wall_lamp", "wall": "north", "at": 9.0},
			{"p": "plant_compact", "wall": "west", "at": 12.0},
		],
	},
	# ── 厨房：操作台贴墙，中央过道 ──
	"kitchen": {
		"label": "厨房",
		"items": [
			{"p": "console", "wall": "north", "at": -7.0},
			{"p": "candelabra", "wall": "north", "at": -7.0, "surface": "console"},
			{"p": "console", "wall": "north", "at": 7.0},
			{"p": "candelabra", "wall": "north", "at": 7.0, "surface": "console"},
			{"p": "vanity", "wall": "west", "at": -6.0},
			{"p": "console", "wall": "west", "at": 4.0},
			{"p": "console", "wall": "east", "at": -6.0},
			{"p": "bench", "wall": "south", "at": -7.0},
			{"p": "bench", "wall": "south", "at": 7.0},
			{"p": "towel_rail", "wall": "east", "at": 6.0},
			{"p": "plant_compact", "wall": "east", "at": 12.0},
		],
	},
	# ── 储藏室：最密，靠「堆满」读出用途 ──
	"storage_room": {
		"label": "储藏室",
		"items": [
			{"p": "bookcase", "wall": "north", "at": -12.0},
			{"p": "bookcase", "wall": "north", "at": -5.0},
			{"p": "bookcase", "wall": "north", "at": 2.0},
			{"p": "bookcase", "wall": "north", "at": 9.0},
			{"p": "bookcase", "wall": "west", "at": -8.0},
			{"p": "bookcase", "wall": "west", "at": 0.0},
			{"p": "bookcase", "wall": "west", "at": 8.0},
			{"p": "wardrobe", "wall": "east", "at": -6.0},
			{"p": "wardrobe", "wall": "east", "at": 4.0},
			{"p": "luggage_cart", "wall": "south", "at": -7.0},
			{"p": "luggage_cart", "wall": "south", "at": 7.0},
			{"p": "console", "wall": "east", "at": 12.0},
		],
	},
	# ── 书房：陷阱厅，最暗。书架 + 书桌，像有人刚离开 ──
	"study": {
		"label": "书房",
		"items": [
			{"p": "bookcase", "wall": "north", "at": -9.0},
			{"p": "bookcase", "wall": "north", "at": -2.0},
			{"p": "bookcase", "wall": "north", "at": 5.0},
			{"p": "rug_bedroom", "cx": 0.0, "cz": 3.0, "flat": true, "y": 0.002},
			{"p": "console", "wall": "west", "at": 2.0},
			{"p": "office_chair", "cx": -7.0, "cz": 2.0, "yaw": 90.0},
			{"p": "table_lamp", "wall": "west", "at": 2.0, "surface": "console"},
			{"p": "desk_documents", "wall": "west", "at": 1.0, "surface": "console"},
			{"p": "console", "wall": "east", "at": -6.0},
			{"p": "table_lamp", "wall": "east", "at": -6.0, "surface": "console"},
			{"p": "painting", "wall": "east", "at": 4.0},
			{"p": "plant_compact", "wall": "east", "at": 10.0},
		],
	},
	# ── 门房：撤离舱，出口厅，家具有指示性 ──
	"gatehouse": {
		"label": "门房",
		"items": [
			{"p": "reception_desk", "cx": 0.0, "cz": -7.0, "yaw": 180.0},
			{"p": "candelabra", "cx": -5.0, "cz": -7.0, "surface": "reception_desk"},
			{"p": "bench", "wall": "west", "at": -5.0},
			{"p": "bench", "wall": "west", "at": 3.0},
			{"p": "luggage_cart", "wall": "east", "at": -5.0},
			{"p": "plant_compact", "wall": "east", "at": 6.0},
			{"p": "painting", "wall": "south", "at": 0.0},
		],
	},
	# ── 玄关：楼梯厅，15×15 最小 ──
	"entrance_hall": {
		"label": "玄关",
		"items": [
			{"p": "entrance_mat", "wall": "south", "at": 0.0, "flat": true, "y": 0.002},
			{"p": "console", "wall": "west", "at": 0.0},
			{"p": "mirror", "wall": "west", "at": 0.0},
			{"p": "plant_compact", "wall": "east", "at": -4.0},
			{"p": "candelabra", "wall": "east", "at": 4.0},
			{"p": "painting", "wall": "north", "at": 0.0},
		],
	},
}

## 原型（`style_label`）→ 主题 id。**「房间叫什么都由这里定」的唯一清单。**
const THEME_BY_STYLE := {
	"王座间/blind/wood_ring": "throne_hall",
	"大堂/clerestory/stone_ring": "grand_lobby",
	"大回廊/double_pair/full": "banquet_gallery",
	"中庭回廊/pair/full": "drawing_room",
	"逼仄空厅/blind/full": "servant_clutter",
	"更衣前厅/pair/full": "bedroom",
	"陈列室/single_side/full": "cabinet_room",
	"铺面/pair/full": "shopfront",
	"操作间/pair/stone_ring": "kitchen",
	"储藏间/blind/full": "storage_room",
	"陷阱厅/blind/full": "study",
	"撤离舱/blind/full": "gatehouse",
	"楼梯厅/blind/full": "entrance_hall",
}


static func theme_for_style(style: Dictionary) -> String:
	return str(THEME_BY_STYLE.get(_style_key(style), ""))


static func _style_key(style: Dictionary) -> String:
	return "%s/%s/%s" % [
		str(style.get("note", "")), str(style.get("windows", "")), str(style.get("floor", "")),
	]


static func has_theme(theme_id: String) -> bool:
	return THEMES.has(theme_id)


## 逐件的**占地**缩放覆盖 —— 只影响 x/z，高度仍走下面的封顶逻辑。
##
## 两类件不能跟着 ×3：
##   · **地毯**本来就按「房间尺度的软装」做的（lounge 就 8×10m），再乘 3 是 24×30m，
##     45×40 的大堂里它会把整个中庭铺成一块纯色，压掉地砖分区（石沿廊 + 木中庭）
##     这个刻意做的视觉层次 —— 实测第一版远看只剩一张大红毯；
##   · **接待台**原始就 5.58m 宽，×3 是 16.7m，把同轴的茶几/扶手椅全挤掉
##     （实测大堂第一版只剩两张扶手椅，沙发和茶几全被重叠检测丢弃）。
const SCALE_FOOTPRINT := {
	"rug_lounge": 1.4,
	"rug_bedroom": 1.6,
	"rug_runner": 2.0,
	"entrance_mat": 2.0,
	"desk_documents": 2.0,
	"reception_desk": 1.5,
}


## 该件的实际缩放。
##
## 水平走 `SCALE_FOOTPRINT`（默认 ×1.8）；高度**按 `TARGET_HEIGHT_RATIO` 反算** ——
## 也就是说"这件家具该到角色身高的几成"，而不是"原始米数乘几倍"。
## 两条约束兜底：不越 `MAX_HEIGHT`（落地件）、不越 `WALL_TOP_LIMIT`（挂墙件）。
static func scale_for(slug: String) -> Vector3:
	var base: Vector3 = SIZES.get(slug, Vector3.ONE)
	var fs := float(SCALE_FOOTPRINT.get(slug, FOOTPRINT_SCALE))
	if base.y <= 0.0:
		return Vector3(fs, fs, fs)
	# 优先用「目标身高比」；没登记的件退回水平倍率
	var hs := fs
	if TARGET_HEIGHT_RATIO.has(slug):
		hs = (float(TARGET_HEIGHT_RATIO[slug]) * CHARACTER_HEIGHT) / base.y
	# 兜底：不许戳出墙
	var ceiling := MAX_HEIGHT
	if WALL_MOUNT_Y.has(slug):
		ceiling = WALL_TOP_LIMIT - float(WALL_MOUNT_Y[slug])
	hs = minf(hs, ceiling / base.y if base.y > 0.0 else hs)
	return Vector3(fs, hs, fs)


## 放大后的占地尺寸（x, z）。按该件自己的缩放算，贴地件不会被统一乘 3。
static func footprint(slug: String) -> Vector2:
	var base: Vector3 = SIZES.get(slug, Vector3.ONE)
	var s := scale_for(slug)
	return Vector2(base.x * s.x, base.z * s.z)


## 放大后的高度。
static func height_of(slug: String) -> float:
	var base: Vector3 = SIZES.get(slug, Vector3.ONE)
	return base.y * scale_for(slug).y


## 相对摆放：把一件家具钉在另一件的**正前方 / 左右侧**。
##
## ## 为什么需要它
##
## 绝对坐标（`cx`/`cz`）摆不出"沙发组"：沙发贴墙放大后中心离开原点 18m，
## 而茶几按 `cx=-9` 摆就离了 9 米 —— 实测第一版大堂里家具全是散点，
## 读不出"这里是待客区"。
##
## 用 `near` 后写的是**关系**而不是坐标：「茶几在沙发正前方 0.5m」，
## 沙发被门位挤到哪儿，茶几就跟到哪儿。这才是布置，不是散点。
##
## ## 语法（主题条目的字段）
##
##   `near`   锚点件的 slug（同名件取**最近一次放置**的那件）
##   `side`   `front`（默认）/ `left` / `right`
##   `gap`    与锚点之间的额外间隙
##   `along`  沿锚点左右方向的偏移
static func _place_near(
	item: Dictionary, fp: Vector2, placed: Dictionary, occupied: Array
) -> Dictionary:
	var anchor_slug := str(item.get("near", ""))
	if not placed.has(anchor_slug):
		return {"ok": false}
	var anchor: Dictionary = placed[anchor_slug]
	var anchor_pos: Vector3 = anchor["pos"]
	var anchor_yaw := float(anchor["yaw"])
	var anchor_fp := anchor["fp"] as Vector2
	var yaw_rad := deg_to_rad(anchor_yaw)
	# Godot 绕 Y 旋转：局部 +Z → (sin, 0, cos)，局部 +X → (cos, 0, -sin)
	var forward := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))
	var right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
	var side := str(item.get("side", "front"))
	var gap := float(item.get("gap", 0.4))
	var along := float(item.get("along", 0.0))
	var offset := Vector3.ZERO
	match side:
		"left":
			offset = right * -(anchor_fp.x * 0.5 + fp.x * 0.5 + gap) + forward * along
		"right":
			offset = right * (anchor_fp.x * 0.5 + fp.x * 0.5 + gap) + forward * along
		_:
			offset = forward * (anchor_fp.y * 0.5 + fp.y * 0.5 + gap) + right * along
	var pos := anchor_pos + offset
	pos.y = anchor_pos.y
	var hx := fp.x * 0.5
	var hz := fp.y * 0.5
	if _quarter_turned(anchor_yaw):
		hx = fp.y * 0.5
		hz = fp.x * 0.5
	if _overlaps(pos, hx, hz, occupied):
		return {"ok": false}
	return {"ok": true, "pos": pos, "yaw": anchor_yaw, "hx": hx, "hz": hz}


## 门洞前的净空深度（米）：门位轴向向内这段距离内不放带碰撞的家具。
##
## ## 为什么光「沿墙避让」不够
##
## 沿墙避让只保证家具**沿墙方向**不盖住门洞，但门是**穿过墙**的通道：
## 家具如果落在门的轴线正前方（比如一张长凳摆在门内侧 1m 处），
## 玩家推开门照样被家具挡住。实测 `probe_expedition03_playable` 报了
## 2/25 条门洞被 `CollisionBody` 封死（exit→fireplace_room_inj2、cr05→n03）。
##
## 所以额外判一条：家具的世界 AABB 不得与「门洞通道盒」相交。
## 通道盒 = 门位为心、沿墙 2.2m 宽、从墙面往里 `DOOR_CLEAR_DEPTH` 的矩形。
const DOOR_CLEAR_DEPTH := 2.6
## 沿墙搜索空位的步长（米）。0.6m ≈ 半个门宽，够密。
const SLIDE_STEP := 0.6


## 该位置是否会挡住门洞通道。
static func _blocks_doorway(
	pos: Vector3, hx: float, hz: float, door_boxes: Array
) -> bool:
	for box_value in door_boxes:
		var box := box_value as Dictionary
		var dx: float = absf(pos.x - float(box["x"]))
		var dz: float = absf(pos.z - float(box["z"]))
		if dx < hx + float(box["hx"]) and dz < hz + float(box["hz"]):
			return true
	return false


## 由门位算出「门洞通道盒」（xz 半尺寸，世界/房间局部一致 —— 房间不旋转）。
static func _door_boxes(
	connection_ports: Array, half_x: float, half_y: float
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value in connection_ports:
		var port := value as Dictionary
		var side := str(port.get("side", ""))
		var lane := float(port.get("lane_m", 0.0))
		# 通道盒：沿墙半宽 = 门半宽 + 余量；垂直墙半深 = 净空深度的一半，
		# 中心贴在内表面往里推半个深度。
		var along_half := DOOR_HALF_WIDTH + DOOR_MARGIN
		var depth_half := DOOR_CLEAR_DEPTH * 0.5
		match side:
			"north":
				out.append({"x": lane, "z": -half_y + WALL_HALF_THICK + depth_half,
					"hx": along_half, "hz": depth_half})
			"south":
				out.append({"x": lane, "z": half_y - WALL_HALF_THICK - depth_half,
					"hx": along_half, "hz": depth_half})
			"west":
				out.append({"x": -half_x + WALL_HALF_THICK + depth_half, "z": lane,
					"hx": depth_half, "hz": along_half})
			"east":
				out.append({"x": half_x - WALL_HALF_THICK - depth_half, "z": lane,
					"hx": depth_half, "hz": along_half})
	return out


## 沿墙找一个能放下的位置：从期望偏移出发，向两侧逐步试探。
##
## ## 为什么必须「滑」而不是「丢」
##
## 第一版撞门就整件跳过。结果 45×40 大堂的西墙上有个门，两张大沙发**直接消失**，
## 房间里只剩接待台和两张扶手椅 —— 而门位是每局几何求交算出来的，
## 换句话说「摆好的家具会随种子随机消失」。这不可接受。
##
## 改成：以期望位置为中心，按 `SLIDE_STEP` 向两侧找最近的可放点；
## 找到就放那儿（家具贴着门框挪开半步，正是「被人挪过」的自然感），
## 整面墙都放不下才放弃。
##
## 返回 `{ok, pos, yaw, along, hx, hz}`（`hx/hz` 是世界空间半尺寸，供占位登记）。
static func _place_on_wall(
	wall: String, along0: float, fp: Vector2, doors: Array,
	occupied: Array, half_x: float, half_y: float,
	door_boxes: Array = []
) -> Dictionary:
	var horizontal := wall in ["north", "south"]
	var half_along := fp.x * 0.5
	var half_depth := fp.y * 0.5
	# **沿墙方向的半长**（决定 along 能滑多远）与**垂直墙方向的半长**（决定墙面在哪）
	# 是两个不同的量，绝不能混用。
	#
	# 这里踩过一个只在非正方形房间才暴露的坑：早先 `inner` 也用了 `wall_half_len`
	# （沿墙那个），于是 40×30 房的 north 墙被当成在 z=±20 —— 沙发整排飞到墙外 5m，
	# 玩家从外面看得见、里面走不进去。25×25 房 x==y，混用也看不出来，
	# 所以这个 bug 躲了很久。
	var wall_half_len := half_x if horizontal else half_y      # 沿墙
	var wall_half_span := half_y if horizontal else half_x     # 垂直墙
	var inner := wall_half_span - WALL_HALF_THICK
	# 墙端留 0.05 缝隙
	var along_limit := wall_half_len - WALL_HALF_THICK - half_along - 0.05
	if along_limit < 0.0:
		return {"ok": false}
	# 世界空间半尺寸：贴东西墙时宽与深互换（yaw 90/270 把局部 X 转到世界 Z 上）
	var world_hx := half_along
	var world_hz := half_depth
	if not horizontal:
		world_hx = half_depth
		world_hz = half_along
	var base := clampf(along0, -along_limit, along_limit)
	# 候选偏移：0, +step, -step, +2step, -2step …（各方向最多跑满墙长）
	var candidates: Array[float] = [0.0]
	var steps := int(ceil(along_limit * 2.0 / SLIDE_STEP)) + 1
	for i in range(1, steps + 1):
		candidates.append(float(i) * SLIDE_STEP)
		candidates.append(-float(i) * SLIDE_STEP)
	for delta in candidates:
		var along := base + delta
		if absf(along) > along_limit:
			continue
		# ① 避门
		var blocked := false
		for lane_value in doors:
			if absf(along - float(lane_value)) < DOOR_HALF_WIDTH + half_along + DOOR_MARGIN:
				blocked = true
				break
		if blocked:
			continue
		# ② 避已占用的家具
		var pos := Vector3.ZERO
		var yaw := 0.0
		match wall:
			"north":
				pos = Vector3(along, 0.0, -inner + half_depth); yaw = 0.0
			"south":
				pos = Vector3(along, 0.0, inner - half_depth); yaw = 180.0
			"west":
				pos = Vector3(-inner + half_depth, 0.0, along); yaw = 90.0
			_:
				pos = Vector3(inner - half_depth, 0.0, along); yaw = 270.0
		if _overlaps(pos, world_hx, world_hz, occupied):
			continue
		# ③ 不挡门洞通道（沿墙避让管不到的「门前正前方」）
		if _blocks_doorway(pos, world_hx, world_hz, door_boxes):
			continue
		return {"ok": true, "pos": pos, "yaw": yaw, "along": along,
			"hx": world_hx, "hz": world_hz}
	return {"ok": false}


## 该 yaw 是否让占地的宽/深互换（即接近 90° 或 270°）。
##
## **不能用 `fmod(|yaw|,180) > 45`**：yaw=180 的接待台被随手倾斜成 165° 后，
## 上式得出 165>45 ⇒ 误判成"转了 90°"，宽深当场互换，占位盒变成 8.4m 宽的
## 假方块 —— 于是它被误判为挡住门洞（实测 `_fail` 直接点名 reception_desk）。
## 正确判据看 |sin| 与 |cos| 谁大。
static func _quarter_turned(yaw: float) -> bool:
	var r := deg_to_rad(yaw)
	return absf(sin(r)) > absf(cos(r))


## 房间中心型摆位的可用性检查（不滑位，中心件位置就是设计意图）。
static func _overlaps(pos: Vector3, hx: float, hz: float, occupied: Array) -> bool:
	for other in occupied:
		var dx: float = absf(pos.x - float(other["x"]))
		var dz: float = absf(pos.z - float(other["z"]))
		if dx < (hx + float(other["hx"])) * 0.92 and dz < (hz + float(other["hz"])) * 0.92:
			return true
	return false


## 生成摆位方案。返回 `[{prefab, slug, position, yaw, scale, height, collide, name, flat}]`。
##
## `connection_ports` 是**本局**的门位，用于避让。墙上的件撞门时会**沿墙滑开**，
## 所以同一份配方在不同种子下件数稳定，不会「随种子随机消失」。
static func layout(theme_id: String, dim: Vector2, connection_ports: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not THEMES.has(theme_id):
		return out
	var theme: Dictionary = THEMES[theme_id]
	var half_x := dim.x * 0.5
	var half_y := dim.y * 0.5
	var doors := {"north": [], "south": [], "west": [], "east": []}
	for value in connection_ports:
		var port := value as Dictionary
		var side := str(port.get("side", ""))
		if doors.has(side):
			(doors[side] as Array).append(float(port.get("lane_m", 0.0)))
	var occupied: Array[Dictionary] = []
	## 门洞通道盒：带碰撞的家具不得与它们相交（否则推开门也过不去）。
	var door_boxes := _door_boxes(connection_ports, half_x, half_y)
	## slug → {pos, yaw, fp}，供 `near` 相对摆放引用。
	var placed: Dictionary = {}
	var seq := 0
	for item_value in theme.get("items", []) as Array:
		var item := item_value as Dictionary
		var slug := str(item.get("p", ""))
		if not SIZES.has(slug):
			continue
		var fp := footprint(slug)
		var wall := str(item.get("wall", ""))
		var flat := bool(item.get("flat", false))
		var pos := Vector3.ZERO
		var yaw := 0.0
		var hx := fp.x * 0.5
		var hz := fp.y * 0.5
		if item.has("near"):
			# ── 相对摆放 ──
			var rel := _place_near(item, fp, placed, occupied)
			if not bool(rel.get("ok", false)):
				continue
			pos = rel["pos"] as Vector3
			yaw = float(rel["yaw"])
			hx = float(rel["hx"])
			hz = float(rel["hz"])
			if not flat and not _is_tabletop(slug) and not WALL_MOUNT_Y.has(slug):
				if _blocks_doorway(pos, hx, hz, door_boxes):
					continue
			if item.has("yaw"):
				yaw = float(item.get("yaw"))
		elif wall.is_empty():
			pos.x = float(item.get("cx", 0.0))
			pos.z = float(item.get("cz", 0.0))
			yaw = float(item.get("yaw", 0.0))
			if _quarter_turned(yaw):
				hx = fp.y * 0.5
				hz = fp.x * 0.5
			if not flat and not _is_tabletop(slug) and not WALL_MOUNT_Y.has(slug):
				if _overlaps(pos, hx, hz, occupied):
					continue
				if _blocks_doorway(pos, hx, hz, door_boxes):
					continue
		else:
			var placed_wall := _place_on_wall(
				wall, float(item.get("at", 0.0)), fp,
				doors.get(wall, []) as Array, occupied, half_x, half_y, door_boxes
			)
			if not bool(placed_wall.get("ok", false)):
				continue
			pos = placed_wall["pos"] as Vector3
			yaw = float(placed_wall["yaw"])
			hx = float(placed_wall["hx"])
			hz = float(placed_wall["hz"])
		if item.has("yaw") and not item.has("near"):
			yaw = float(item.get("yaw"))
		# ── 高度 ──
		#   `surface`：摆在某个桌面上 —— 用**那张桌子放大后的实际高度**，
		#             不是本件自己的原始尺寸再乘缩放（会算出 2.55m 这种离谱值，实测踩过）。
		#   挂墙件：`WALL_MOUNT_Y`，绝对值，不随放大变。
		#   贴地件：`y`（默认 2mm，压在地砖上避免 z-fighting）。
		var y := 0.0
		if item.has("surface"):
			y = height_of(str(item.get("surface", "")))
		elif flat:
			y = float(item.get("y", 0.002))
		else:
			y = float(WALL_MOUNT_Y.get(slug, 0.0))
		pos.y = y
		# ── 随手偏转：每 N 件挑 1 件歪 10~15°，像被人挪过 ──
		if not flat and not WALL_MOUNT_Y.has(slug) and not _is_tabletop(slug):
			if seq % TILT_EVERY == 0:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash("%s|%d|%s" % [theme_id, seq, slug])
				var magnitude := rng.randf_range(TILT_MIN, TILT_MAX)
				yaw += magnitude if rng.randf() < 0.5 else -magnitude
		if not flat and not _is_tabletop(slug) and not WALL_MOUNT_Y.has(slug):
			occupied.append({"x": pos.x, "z": pos.z, "hx": hx, "hz": hz})
		# 登记为锚点：后置的 `near` 件会引用**最近一次**放置的同名件。
		placed[slug] = {"pos": pos, "yaw": yaw, "fp": fp}
		seq += 1
		out.append({
			"prefab": "%s/manor_%s/env_manor_%s_root_top3d.tscn" % [MANOR, slug, slug],
			"slug": slug,
			"position": pos,
			"yaw": yaw,
			"scale": scale_for(slug),
			"height": height_of(slug),
			"collide": not (slug in NO_COLLISION),
			"name": "Furn_%02d_%s" % [seq, slug],
			"flat": flat,
		})
	return out


## 摆在桌面上的小件：与桌子重叠是设计意图，不参与占位登记。
static func _is_tabletop(slug: String) -> bool:
	return slug in ["table_lamp", "desk_documents", "candelabra", "flower_arrangement"]
