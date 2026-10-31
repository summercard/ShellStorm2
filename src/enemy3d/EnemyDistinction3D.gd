extends RefCounted
## 远征03 复刻怪的**逐只可辨识标识**（2026-10-31）。
##
## ## 这张表要解决的问题
##
## 33 只复刻怪共用 **3 个带骨骼 GLB**（小僵尸 / 保安僵尸 / 胖子）+ **2 类程序化外壳**
## （炸弹果壳 / 召唤师壳）。只靠 `COLORS` / `FORMAL_MODEL_TINT` 染色的话，
## 子弹族 5 只、霰弹族 3 只、逃逸族 6 只，在 5~10 m 交战距离上是**同一个剪影** ——
## 玩家分不出「三连发」和「100% 预判」该用不同躲法，这是可读性硬伤。
##
## 所以每只怪额外挂一件**程序化标识件**（护目镜 / 头巾 / 角 / 光环 / 冠 / 肩甲 / 背罐 / 背刺 / 斗篷 …）。
## 标识件只表达"这是哪一只"，不参与任何玩法判定（无碰撞、无受击）。
##
## ## 三条硬规矩
##
## 1. **同族内标识必须不同**：`verify_design()` 按族分组断言形状+数量+颜色不撞。
## 2. **标识只加不减**：不隐藏任何原有部件。卸载 = 表里删掉那一行。
## 3. **材质与网格必须缓存**：颜色只建一次材质并 `Keeper.pin()`，
##    否则刷怪那一帧会因为新材质变体付 100 ms 级管线重建（见 `MaterialPipelineKeeper` 与
##    2026-10-31 的材质变体实测记录）。
##
## ## 坐标系（血泪教训，改之前先读 `ANCHORS` 头注）
##
## 锚点一律**按模型实测**：不许用身高百分比、不许挂骨骼、不许用 `get_aabb()` ——
## 这三种做法各错过一次，各把零件送出体表几十厘米。

const Keeper := preload("res://src/enemy3d/MaterialPipelineKeeper.gd")

## 怪种 → 族。唯一用途是"同族内不许撞标识"这条断言，以及给策划看编成分布。
const FAMILY := {
	"egt_bullet_kin": "bullet", "egt_bandana_kin": "bullet", "egt_veteran_kin": "bullet",
	"egt_cardinal": "bullet", "egt_hollowpoint": "bullet",
	"egt_red_shotgun": "shotgun", "egt_blue_shotgun": "shotgun", "egt_veteran_shotgun": "shotgun",
	"egt_pinhead": "explosive", "egt_nitra": "explosive", "egt_king_bullat": "explosive",
	"egt_grenat": "explosive",
	"egt_blobulon": "split", "egt_blobuloid": "split", "egt_blobulin": "split",
	"egt_chancebulon": "split",
	"egt_bookllet": "book", "egt_blue_bookllet": "book", "egt_green_bookllet": "book",
	"egt_gunjurer": "arcane", "egt_gigi": "arcane", "egt_gunsinger": "arcane",
	"egt_bullat": "rush", "egt_shotgat": "rush", "egt_spirat": "rush",
	"egt_keybullet_kin": "escape", "egt_chance_kin": "escape", "egt_confirmed": "escape",
	"egt_mimic": "escape", "egt_gun_fairy": "escape", "egt_gripmaster": "escape",
	"egt_gun_nut": "heavy", "egt_chain_gunner": "heavy",
}

## 怪种 → 标识件。`shape` 见 `_build()`，`anchor` 见 `ANCHORS`，`count` 只对成组形状有效。
## 颜色刻意不跟身体同色：标识件要在暗光下也能被认出来。
const DESIGN := {
	# —— 子弹族（5，保安僵尸，全部持枪）——
	"egt_bullet_kin": {"shape": "visor", "anchor": "face", "color": Color(0.42, 1.00, 1.00), "size": 1.0},
	"egt_bandana_kin": {"shape": "band", "anchor": "head_mid", "color": Color(0.36, 0.62, 1.00), "size": 1.0},
	"egt_veteran_kin": {"shape": "shoulder", "anchor": "shoulder", "color": Color(1.00, 0.62, 0.28), "size": 1.0},
	"egt_cardinal": {"shape": "halo", "anchor": "head_top", "color": Color(1.00, 0.52, 0.62), "size": 1.0},
	"egt_hollowpoint": {"shape": "horns", "anchor": "head_mid", "color": Color(0.84, 0.62, 1.00), "size": 1.0},
	# —— 霰弹族（3）——
	"egt_red_shotgun": {"shape": "band", "anchor": "head_mid", "color": Color(1.00, 0.34, 0.34), "size": 1.1},
	"egt_blue_shotgun": {"shape": "tanks", "anchor": "back", "color": Color(0.50, 0.68, 1.00), "size": 1.1},
	"egt_veteran_shotgun": {"shape": "crown", "anchor": "head_top", "color": Color(1.00, 0.82, 0.28), "size": 1.0, "count": 5},
	# —— 爆炸族（4，炸弹果程序壳，本身带两个罐）——
	"egt_pinhead": {"shape": "fuse", "anchor": "head_top", "color": Color(1.00, 0.74, 0.20), "size": 1.0},
	"egt_nitra": {"shape": "spikes", "anchor": "back", "color": Color(0.78, 0.92, 0.30), "size": 1.0, "count": 4},
	"egt_king_bullat": {"shape": "crown", "anchor": "head_top", "color": Color(1.00, 0.86, 0.36), "size": 1.25, "count": 6},
	"egt_grenat": {"shape": "horns", "anchor": "head_mid", "color": Color(1.00, 0.44, 0.16), "size": 0.9},
	# —— 分裂族（4，小僵尸）——
	# 三阶刻意用**同一形状不同数量**：它们本来就是同一只怪炸开的，不该长得像三个物种，
	# 但要有"母体 / 幼体 / 微体"的读法（鼓包 2 / 1 / 0）。
	"egt_blobulon": {"shape": "bulge", "anchor": "belly", "color": Color(1.00, 0.52, 0.42), "size": 1.15, "count": 2},
	"egt_blobuloid": {"shape": "bulge", "anchor": "belly", "color": Color(1.00, 0.60, 0.48), "size": 0.95, "count": 1},
	"egt_blobulin": {"shape": "bulge", "anchor": "belly", "color": Color(1.00, 0.70, 0.56), "size": 0.7, "count": 0},
	"egt_chancebulon": {"shape": "panels", "anchor": "chest", "color": Color(1.00, 0.90, 0.62), "size": 1.0, "count": 3},
	# —— 书怪族（3，召唤师壳，本身带冠 + 4 轨道球）——
	"egt_bookllet": {"shape": "halo", "anchor": "head_top", "color": Color(0.94, 0.92, 0.82), "size": 1.0},
	"egt_blue_bookllet": {"shape": "spikes", "anchor": "back", "color": Color(0.50, 0.72, 1.00), "size": 0.9, "count": 3},
	"egt_green_bookllet": {"shape": "panels", "anchor": "chest", "color": Color(0.56, 0.92, 0.52), "size": 1.1, "count": 4},
	# —— 法术族（3）——
	"egt_gunjurer": {"shape": "horns", "anchor": "head_mid", "color": Color(0.80, 0.58, 1.00), "size": 1.0},
	"egt_gigi": {"shape": "bulge", "anchor": "belly", "color": Color(1.00, 0.86, 0.46), "size": 1.0, "count": 1},
	"egt_gunsinger": {"shape": "halo", "anchor": "head_top", "color": Color(0.72, 0.42, 1.00), "size": 1.15},
	# —— 冲撞族（3，炸弹果壳）——
	# 全族共用一个"前冲尖刺"，读法统一 = "这只会撞你"；靠尖刺数量（1/2/3）分级。
	"egt_bullat": {"shape": "ram", "anchor": "chest", "color": Color(0.98, 0.86, 0.24), "size": 1.0, "count": 1},
	"egt_shotgat": {"shape": "ram", "anchor": "chest", "color": Color(0.44, 0.80, 0.64), "size": 1.05, "count": 2},
	"egt_spirat": {"shape": "ram", "anchor": "chest", "color": Color(0.38, 0.88, 0.88), "size": 1.1, "count": 3},
	# —— 逃逸族（6，基底本来就混，标识是它们的**主要**辨认手段）——
	"egt_keybullet_kin": {"shape": "key", "anchor": "back", "color": Color(1.00, 0.88, 0.30), "size": 1.0},
	"egt_chance_kin": {"shape": "panels", "anchor": "chest", "color": Color(0.44, 0.90, 0.94), "size": 0.95, "count": 2},
	"egt_confirmed": {"shape": "cloak", "anchor": "back", "color": Color(0.62, 0.40, 0.80), "size": 1.0},
	"egt_mimic": {"shape": "tanks", "anchor": "back", "color": Color(0.92, 0.72, 0.36), "size": 1.15},
	"egt_gun_fairy": {"shape": "halo", "anchor": "head_top", "color": Color(1.00, 0.96, 0.66), "size": 0.9},
	"egt_gripmaster": {"shape": "spikes", "anchor": "back", "color": Color(0.60, 0.52, 1.00), "size": 1.1, "count": 5},
	# —— 重型（2，胖子）——
	"egt_gun_nut": {"shape": "shoulder", "anchor": "shoulder", "color": Color(1.00, 0.84, 0.52), "size": 1.3},
	"egt_chain_gunner": {"shape": "tanks", "anchor": "back", "color": Color(0.72, 0.80, 1.00), "size": 1.25},
}

## 每个**借用模型**的语义锚点（模型本地米，脚底为原点，朝 −Z）。
##
## ## 这组数怎么来的（2026-10-31，`tools/_egt_anchor_probe` 逐层扫网格顶点）
##
## | 模型 | 顶点 | 实高 | 头占 | 脸的 z | 备注 |
## |---|---|---|---|---|---|
## | 保安僵尸 `ranged_caster` | 16468 | 1.857 | 上 40% | −0.47 | 手里有枪，横向被撑到 ±1.4 |
## | 小僵尸 `melee_chaser` | 853 | 1.894 | 上 50% | −0.48 | 头极大，肚子在 0.35h |
## | 胖子 `fat_zombie03` | 1513 | 3.143 | 上 15% | −0.48 | 肚子前凸到 z=−1.02 |
##
## ## 三种做法都试错过，各自把零件送出体表
## ① **不能用身高百分比**：小僵尸的头占一半、胖子只占 15%，同一比例必然错一头一身
##    （那版把布洛布的肚子鼓包装到了脸颊两侧）。
## ② **不能挂骨骼**：`Head` 骨在 y≈0.85（胸口位置），网格的头在 1.1+ —— 骨空间与网格不同源。
## ③ **不能用 `MeshInstance3D.get_aabb()`**：那是**绑定姿势**的盒子（保安僵尸给 1.399），
##    比真实形态矮 30%，照它摆会把护目镜顶到帽檐外。
##    ⇒ 只能用顶点（或本表这样由顶点实测出来的常量）。
const ANCHORS := {
	## 保安僵尸。头在 y 1.08~1.86（帽子在 1.55 以上），脸的表面 z≈−0.42~−0.48，
	## 头横截面中心 x≈+0.03、半宽 0.37。手臂把 y 0.46~0.93 撑到 x=−1.45（那是枪），
	## 所以横向尺寸只能用**躯干层**（y 0.31~0.46）的 ±0.27，不能用整体 AABB。
	"ranged_caster": {
		"head_top": Vector3(0.03, 1.78, -0.24),
		"head_mid": Vector3(0.03, 1.42, -0.38),
		"face": Vector3(0.03, 1.34, -0.42),
		"shoulder": Vector3(0.0, 1.02, -0.12),
		"chest": Vector3(0.0, 0.86, -0.26),
		"belly": Vector3(0.0, 0.60, -0.22),
		"back": Vector3(0.0, 0.88, 0.20),
		"head_half": Vector2(0.36, 0.001),
		"body_half": Vector2(0.26, 0.001),
		"shoulder_x": Vector2(0.30, 0.001),
	},
	## 小僵尸。头极大：y 0.95~1.89（近一半身高），脸表面 z≈−0.48 在 y 1.42~1.58，
	## 头半宽 0.47~0.51。躯干在 y 0.47~0.79、半宽 0.30（y 0.63~0.95 的 ±0.62 是手臂）。
	"melee_chaser": {
		"head_top": Vector3(0.0, 1.82, -0.26),
		"head_mid": Vector3(0.0, 1.36, -0.40),
		"face": Vector3(0.0, 1.30, -0.44),
		"shoulder": Vector3(0.0, 0.98, -0.14),
		"chest": Vector3(0.0, 0.82, -0.26),
		"belly": Vector3(0.0, 0.64, -0.28),
		"back": Vector3(0.0, 0.82, 0.16),
		"head_half": Vector2(0.46, 0.001),
		"body_half": Vector2(0.30, 0.001),
		"shoulder_x": Vector2(0.34, 0.001),
	},
	## 胖子。身体极宽（y 1.05~1.83 到 ±1.16，y 2.10~2.62 的 ±2.62 是手臂），
	## 头只在 y 2.62~3.14、半宽 0.39，脸表面 z≈−0.47。肚子前凸到 z=−1.02（y 1.31~1.57）。
	## ⇒ 横向一律取肚子那层的 ±1.10，那是它真正的体宽；头另外一套。
	"fat_zombie03": {
		"head_top": Vector3(0.0, 3.08, -0.32),
		"head_mid": Vector3(0.0, 2.76, -0.40),
		"face": Vector3(0.0, 2.70, -0.44),
		"shoulder": Vector3(0.0, 2.30, -0.30),
		"chest": Vector3(0.0, 1.95, -0.88),
		"belly": Vector3(0.0, 1.45, -0.98),
		"back": Vector3(0.0, 1.60, 0.62),
		"head_half": Vector2(0.38, 0.001),
		"body_half": Vector2(1.05, 0.001),
		"shoulder_x": Vector2(0.62, 0.001),
	},
	## 程序化外壳兜底（炸弹果 / 召唤师 / 默认）。这几个没有 GLB，
	## 锚点按 `body_size` 由 `program_anchors()` 现算，本组只在参数缺失时兜底。
	"__program__": {
		"head_top": Vector3(0.0, 1.28, -0.08),
		"head_mid": Vector3(0.0, 1.00, -0.18),
		"face": Vector3(0.0, 0.94, -0.30),
		"shoulder": Vector3(0.0, 0.82, -0.08),
		"chest": Vector3(0.0, 0.70, -0.20),
		"belly": Vector3(0.0, 0.50, -0.18),
		"back": Vector3(0.0, 0.70, 0.20),
		"head_half": Vector2(0.30, 0.001),
		"body_half": Vector2(0.34, 0.001),
		"shoulder_x": Vector2(0.32, 0.001),
	},
}

## 颜色 → 材质。颜色最多几十种，全部 `pin()` 住 ⇒ 复用零重建。
static var _material_cache: Dictionary = {}
## 形状 → 基础网格。同样的理由：网格只建一次。
static var _mesh_cache: Dictionary = {}


static func has_design(kind: String) -> bool:
	return DESIGN.has(kind)


static func family_of(kind: String) -> String:
	return str(FAMILY.get(kind, ""))


## 按**实际借用的模型**取锚点表。`asset_kind` 是 `EnemyAvatar3D.resolve_asset_kind()` 的结果。
static func anchors_for(asset_kind: String) -> Dictionary:
	return (ANCHORS.get(asset_kind, ANCHORS["__program__"]) as Dictionary).duplicate()


## 给一只怪挂标识件的**容器**（此时不建零件）。
##
## 分两步是因为锚点要由调用方选好（有 GLB 走 `anchors_for()`，程序化外壳走
## `program_anchors()`），而容器本身可以立刻建 —— 这样"有没有挂上"当帧就能被验收读到。
static func apply(host: Node3D, kind: String) -> Node3D:
	if host == null or not DESIGN.has(kind):
		return null
	var holder := Node3D.new()
	holder.name = "Distinction3D"
	host.add_child(holder)
	return holder


## 建零件。`anchors` 来自 `anchors_for()` / `program_anchors()`，坐标是 host 本地米。
static func build(holder: Node3D, kind: String, anchors: Dictionary, body_color: Color) -> void:
	if holder == null or not DESIGN.has(kind) or anchors.is_empty():
		return
	for child in holder.get_children():
		child.queue_free()
	var spec: Dictionary = DESIGN[kind]
	var anchor_name := str(spec.get("anchor", "chest"))
	var origin: Vector3 = anchors.get(anchor_name, anchors.get("chest", Vector3(0, 0.8, 0)))
	_build(
		holder,
		str(spec.get("shape", "")),
		spec.get("color", Color.WHITE) as Color,
		float(spec.get("size", 1.0)),
		int(spec.get("count", 1)),
		origin,
		anchors,
		body_color
	)


## 程序化外壳（炸弹果 / 召唤师 / 默认）的锚点：由 `EnemyAvatar3D._rebuild()` 的
## `body_size` 现算。这几只没有 GLB，壳是一颗胶囊 + 若干附肢，尺寸就是玩法口径，
## 所以直接按比例推，不用实测。
##
## 比例来自 `_rebuild()` 的构建顺序：壳心在 `0.54 × body.y`、核心球在 `0.75 × body.y`。
static func program_anchors(body_size: Vector3) -> Dictionary:
	var h := body_size.y
	var r := body_size.x * 0.5
	return {
		# 抬高到 1.18h：召唤师壳自带的 `Crown` 固定在 y=1.72，
		# 而壳高只有 ~1.5 ⇒ 光环摆在 0.98h 会被冠挡在里面（实测看不见）。
		"head_top": Vector3(0.0, h * 1.18, -0.06 * h),
		"head_mid": Vector3(0.0, h * 0.80, -0.16 * h),
		"face": Vector3(0.0, h * 0.74, -0.34 * h),
		"shoulder": Vector3(0.0, h * 0.62, -0.04 * h),
		"chest": Vector3(0.0, h * 0.52, -0.26 * h),
		"belly": Vector3(0.0, h * 0.36, -0.24 * h),
		"back": Vector3(0.0, h * 0.52, 0.26 * h),
		"head_half": Vector2(r * 0.62, 0.001),
		"body_half": Vector2(r * 0.80, 0.001),
	}


## 实测模型在 `host` 本地空间里的真实形态尺寸（用**顶点**，不是 `get_aabb()`）。
static func measure(host: Node3D) -> Dictionary:
	if host == null:
		return {}
	var inv := host.global_transform.affine_inverse()
	var min_y := INF
	var max_y := -INF
	var count := 0
	for node in host.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.visible or mesh.mesh == null or _inside_ignored(mesh, host):
			continue
		var xf := inv * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xf * v
				min_y = minf(min_y, p.y)
				max_y = maxf(max_y, p.y)
				count += 1
	if count == 0:
		return {}
	return {"min_y": min_y, "max_y": max_y, "height": max_y - min_y, "vertex_count": count}


static func _inside_ignored(node: Node, host: Node) -> bool:
	var current := node
	while current != null and current != host:
		if current.name == "Distinction3D" or current.name == "StateVFX":
			return true
		current = current.get_parent()
	return false


## `albedo` 决定受光时是什么颜色，`emission` 决定暗处是什么颜色。两者刻意分开，
## 理由见 `resolve_emission()`。缓存键取两者组合。
static func _material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var key := "%s|%s" % [albedo.to_html(), emission.to_html()]
	var cached: Variant = _material_cache.get(key)
	if cached != null:
		return cached as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.45
	material.metallic = 0.15
	# 自发光只在**建材质时**打开一次（它是变体开关，翻它要重建管线）。
	# 标识件必须"在暗处也能被认出来"，这正是它存在的理由，所以这里值得付一次。
	material.emission_enabled = true
	material.emission = emission
	# ⚠ 强度 0.85 会把**形体信息抹平**：自发光是叠加在 albedo 之上的，
	# 满亮度时圆柱侧投影只剩一块均匀色块，加上光照也读不出圆（2026-10-31 实测：
	# 链枪手背后两根 0.235 m 直径的罐被看成两块 0.47 m 宽的平板）。
	# 0.30 是"暗处能看见、亮处还留着明暗"的折中 —— 与 `HitFlashMaterial3D`
	# 记录的教训同类：自发光是**补充**，不能当主光用。
	material.emission_energy_multiplier = 0.30
	Keeper.pin(material)
	_material_cache[key] = material
	return material


static func _mesh(kind: String) -> Mesh:
	var cached: Variant = _mesh_cache.get(kind)
	if cached != null:
		return cached as Mesh
	var mesh: Mesh
	match kind:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radial_segments = 12
			sphere.rings = 6
			# 出厂球半径 1、高 2 ⇒ 归一到"直径 1"，`scale` 才能直接当米用。
			sphere.radius = 0.5
			sphere.height = 1.0
			mesh = sphere
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.radial_segments = 8
			cone.height = 1.0
			mesh = cone
		"tube":
			var tube := CylinderMesh.new()
			tube.top_radius = 0.5
			tube.bottom_radius = 0.5
			# 10 段在正交侧光下会被读成平板（2026-10-31 实测：链枪手背后两根罐像两块挡板）。
			# 20 段 + 略微软化的法线才像圆柱，成本可以忽略（每个形状只建一次）。
			tube.radial_segments = 20
			tube.height = 1.0
			mesh = tube
		"torus":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.42
			torus.outer_radius = 0.5
			torus.rings = 16
			torus.ring_segments = 6
			mesh = torus
		_:
			mesh = BoxMesh.new()
	_mesh_cache[kind] = mesh
	return mesh


## 加一件基元。`size` 是三轴**直径/长度**（米），网格已按 1 m 归一化。
static func _piece(
	parent: Node3D, mesh_kind: String, material: StandardMaterial3D,
	position: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _mesh(mesh_kind)
	node.material_override = material
	node.position = position
	node.scale = size
	node.rotation = rotation
	# 标识件不投影：它们贴在体表外侧，投影会在自己身上刷出假轮廓。
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


static func _build(
	holder: Node3D, shape: String, desired: Color, size: float, count: int,
	at: Vector3, anchors: Dictionary, body_color: Color
) -> void:
	var albedo := resolve_albedo(desired, body_color)
	var material := _material(albedo, resolve_emission(albedo))
	var head_half := (anchors.get("head_half", Vector2(0.34, 0)) as Vector2).x
	var body_half := (anchors.get("body_half", Vector2(0.3, 0)) as Vector2).x
	# 肩线半宽：胖子体宽是 ±1.16（整个肚子），肩关节只在 ±0.62 —— 两者必须分开，
	# 否则肩甲会被甩到身体外一米多（2026-10-31 实测）。
	var shoulder_half := (anchors.get("shoulder_x", Vector2(body_half, 0)) as Vector2).x
	# 「件」的基准半径：**取体宽与头宽里较小的那个，再封 0.42 上限**。
	#
	# 为什么不能直接用 `body_half`：胖子体宽半宽 1.05 m，是头的 2.7 倍。
	# 所有零件按 `body_half` 缩放的话，它们会跟着肚子一起变成巨型板子
	# （2026-10-31 实测：链枪手背后两块 0.9 m 宽的"挡板"、gun_nut 肩甲甩出体侧 1 m）。
	# 零件是"装备 / 装饰"，尺寸该跟人形比例，不该跟体宽 —— 体宽只影响**摆在哪**。
	var part := minf(minf(body_half, head_half), 0.42)
	var head_top: Vector3 = anchors.get("head_top", Vector3(0, 1.6, 0))
	var head_mid: Vector3 = anchors.get("head_mid", Vector3(0, 1.3, 0))
	match shape:
		# 护目镜：贴在脸上的横带（**不包住头** —— 包住会读成头盔）。
		"visor":
			_piece(
				holder, "box", material,
				Vector3(at.x, at.y, at.z - 0.03),
				Vector3(head_half * 1.30, 0.10, 0.09) * size
			)
		# 头巾：绕头一圈的薄环。
		"band":
			_piece(
				holder, "torus", material,
				Vector3(head_mid.x, head_mid.y + head_half * 0.30, head_mid.z),
				Vector3(head_half * 2.2, 0.18, head_half * 2.2) * size
			)
		# 双角：头顶两侧朝外上方的锥。
		"horns":
			for side in [-1.0, 1.0]:
				_piece(
					holder, "cone", material,
					Vector3(
						head_mid.x + side * head_half * 0.60,
						head_mid.y + head_half * 0.42,
						head_mid.z
					),
					Vector3(0.15, head_half * 0.85, 0.15) * size,
					Vector3(-0.22, 0, side * -0.40)
				)
		# 光环：头顶上方悬浮的环。悬空是刻意的 —— 贴头会与动画穿模。
		"halo":
			_piece(
				holder, "torus", material,
				Vector3(head_top.x, head_top.y + head_half * 0.26, head_top.z),
				Vector3(head_half * 1.8, 0.20, head_half * 1.8) * size,
				# 给 20° 俯仰：正前方看水平环只是一条线，读不出"环"。
				# 这个角度在俯视玩法视角下仍然是个近似的环，但正面也有厚度。
				Vector3(deg_to_rad(-20.0), 0, 0)
			)
		# 尖冠：头顶一圈朝上的锥（5 = 常规，6 = 王）。
		"crown":
			var crowns := maxi(3, count)
			for index in crowns:
				var angle := TAU * float(index) / float(crowns)
				_piece(
					holder, "cone", material,
					Vector3(
						head_top.x + cos(angle) * head_half * 0.68,
						head_top.y + head_half * 0.02,
						head_top.z + sin(angle) * head_half * 0.68
					),
					Vector3(0.09, head_half * 0.50, 0.09) * size
				)
		# 肩甲：肩线外侧两块压扁的球。
		#
		# ⚠ 横向**不能乘 `body_half`**：胖子体宽 ±1.16（那是它整个肚子），
		# 而肩关节只在 x≈±0.55。按体宽摆会把肩甲甩到身体外一米多（2026-10-31 实测）。
		# `shoulder` 锚点自己带 x（见 `ANCHORS`），这里只补一点点外扩。
		"shoulder":
			for side in [-1.0, 1.0]:
				_piece(
					holder, "sphere", material,
					Vector3(at.x + side * shoulder_half * 1.10, at.y, at.z),
					Vector3(shoulder_half * 0.72, shoulder_half * 0.42, shoulder_half * 0.80) * size
				)
		# 背罐：背后两根立筒（读作弹鼓 / 气罐）。
		#
		# ⚠ 直径必须**封顶**：胖子体宽 2.1 m，按体宽乘系数会做出直径 0.9 m 的罐，
		# 从背后看是两块挡板（2026-10-31 实测）。罐是"装备"，尺寸该按人形比例，
		# 不随体宽放大 —— 所以走 `part`（由 `min(body_half, 0.42)` 与头宽共同决定）。
		"tanks":
			# 两根罐的**间距**要大于罐径，否则从背后看会连成一整块（实测间距 0.80、
			# 罐径 0.475 ⇒ 只剩 0.32 的缝，画面读成"一块带竖缝的板"）。
			# 间距按罐径 ×1.5 + 半个身位，且不超出体宽。
			var tank_radius := part * 0.31
			var tank_gap := minf(tank_radius * 3.0, body_half * 0.85)
			for side in [-1.0, 1.0]:
				_piece(
					holder, "tube", material,
					# z 再往后让半个罐径：罐有一半埋在背里时，侧影只剩一条平板
					# （正交视图正对圆柱轴，看不见明暗过渡 —— 2026-10-31 实测）。
					Vector3(at.x + side * tank_gap, at.y + part * 0.45, at.z + part * 0.55 + tank_radius),
					Vector3(tank_radius * 2.0, part * 2.30, tank_radius * 2.0) * size
				)
		# 背刺：背后一排朝后上的锥。
		"spikes":
			var spike_count := maxi(2, count)
			for index in spike_count:
				var t := (float(index) / float(spike_count - 1)) - 0.5 if spike_count > 1 else 0.0
				_piece(
					holder, "cone", material,
					Vector3(at.x + t * body_half * 1.4, at.y + 0.12, at.z + body_half * 0.24),
					Vector3(part * 0.4, part * 1.9, part * 0.4) * size,
					Vector3(-0.85, 0, 0)
				)
		# 斗篷：身后一块薄板。做薄板而不是布料，避免与走路的腿穿插。
		"cloak":
			_piece(
				holder, "box", material,
				Vector3(at.x, at.y - body_half * 0.55, at.z + body_half * 0.32),
				Vector3(part * 4.4, part * 4.4, 0.07) * size
			)
		# 鼓包：腹部一团（或两团）球 —— 分裂体的"体积"读法。0 团 = 微体，什么都不加。
		"bulge":
			var bulges := clampi(count, 0, 2)
			if bulges == 0:
				return
			for index in bulges:
				var side := 0.0
				if bulges == 2:
					side = -0.62 if index == 0 else 0.62
				_piece(
					holder, "sphere", material,
					Vector3(at.x + side * body_half * 0.42, at.y, at.z - body_half * 0.20),
					Vector3(part * 1.85, part * 1.65, part * 1.35) * size
				)
		# 引线：头顶一根细锥。
		"fuse":
			_piece(
				holder, "cone", material,
				Vector3(head_top.x, head_top.y + 0.12, head_top.z),
				Vector3(0.08, 0.34, 0.08) * size
			)
		# 浮板：绕身一圈几块小方片（骰面 / 书页）。
		"panels":
			var panels := maxi(2, count)
			for index in panels:
				var angle := TAU * float(index) / float(panels)
				_piece(
					holder, "box", material,
					Vector3(
						at.x + cos(angle) * body_half * 1.60,
						at.y + sin(angle * 2.0) * body_half * 0.35,
						at.z + sin(angle) * body_half * 1.00
					),
					Vector3(part * 1.2, part * 1.2, 0.05) * size,
					Vector3(0, -angle, 0)
				)
		# 前冲尖：朝正前（−Z）的粗锥，可多根并排（数量 = 这一族的分级）。
		"ram":
			var rams := maxi(1, count)
			for index in rams:
				var spread := 0.0 if rams == 1 else (float(index) / float(rams - 1) - 0.5) * body_half * 1.5
				_piece(
					holder, "cone", material,
					Vector3(at.x + spread, at.y, at.z - body_half * 0.50),
					Vector3(part * 1.2, part * 2.6, part * 1.2) * size,
					Vector3(-PI * 0.5, 0, 0)
				)
		# 钥匙：背后竖着一块带齿的薄板（钥匙小子的身份，也是原作掉落物的预告）。
		"key":
			_piece(
				holder, "box", material,
				Vector3(at.x, at.y + body_half * 0.15, at.z + body_half * 0.30),
				Vector3(part * 0.5, part * 4.0, part * 0.5) * size
			)
			_piece(
				holder, "box", material,
				Vector3(at.x + body_half * 0.34, at.y - body_half * 0.62, at.z + body_half * 0.30),
				Vector3(part * 1.2, part * 0.5, part * 0.5) * size
			)
		_:
			pass


## 标识件相对身体色的**最小可辨距离**（RGB 欧氏距离，0~1.73）。
##
## ⚠ 这是 2026-10-31 实测补的：33 只里 **20 只**的标识件与身体色距离 < 0.35，
## 其中书怪三只只有 0.06~0.09 —— 渲染出来完全看不出有零件。
## 根因是 `COLORS` 的配色逻辑是"身体色 = 弹色 = 伤你的方式"，而标识件初版
## 又照抄了同一色系 ⇒ 同色叠加。
##
## 修法**不是**逐只手挑颜色（那只会在下次改 `COLORS` 时再烂一遍），
## 而是运行时算：`resolve_albedo()` 沿明度轴把颜色推到身体的对立面。
##
## 为什么必须有这条：书怪族借的是召唤师壳（`COLORS.egt_bookllet` 是米白），
## 而标识件也写米白 ⇒ 第一版渲染出来**根本看不出有零件**（2026-10-31 实测）。
## "同族不撞"只保证怪与怪之间有区别，保证不了"零件与自己的身体"有区别 ——
## 那是两条独立的轴。
const MIN_CONTRAST := 0.35

## 高对比调色板。人工挑过、彼此可辨、且都不会"像换了材质语言"的一组。
## `resolve_albedo()` 在色相内调整不够时才用，按"色相最接近原意图"挑选。
const PALETTE: Array[Color] = [
	Color(0.98, 0.78, 0.22),  # 琥珀
	Color(0.95, 0.36, 0.22),  # 砖红
	Color(0.42, 0.90, 0.55),  # 翠绿
	Color(0.35, 0.85, 0.95),  # 青
	Color(0.72, 0.50, 1.00),  # 紫
	Color(0.95, 0.96, 0.98),  # 冷白
	Color(0.10, 0.13, 0.20),  # 墨黑
]


## 标识件相对身体色的对比距离。`body_color` 来自 `EnemyAvatar3D.COLORS`
## （有 GLB 的那批实际观感是 `FORMAL_MODEL_TINT` 相乘后的结果，与 COLORS 同色相，
## 用 COLORS 判距离是够的 —— 要挡的是"几乎同色"，不是精确色差）。
static func contrast_with(kind: String, body_color: Color) -> float:
	var spec: Dictionary = DESIGN.get(kind, {})
	var mark := spec.get("color", Color.WHITE) as Color
	return Vector3(mark.r - body_color.r, mark.g - body_color.g, mark.b - body_color.b).length()


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## 沿**明度轴**把标识件颜色推到身体的对立面，直到拉开 `MIN_CONTRAST`。
##
## 为什么是明度轴而不是色相轴：色相必然与 `COLORS` 的语义（弹色）打架 ——
## 把 cyan 的子弹小子配成橙色零件，玩家会以为那是另一种弹。
## 明度则是纯"看得见/看不见"的维度，不含玩法语义，可以自由推。
##
## 兜底顺序：原色 → 明度翻转 → 冷白 → 冷黑。四级里必有能与任何身体拉开的。
static func resolve_albedo(desired: Color, body: Color) -> Color:
	if _distance(desired, body) >= MIN_CONTRAST:
		return desired
	# ⓞ **同色相就别谈了**：直接进调色板。
	#
	# 链枪手的身体是 `COLORS` 的浅蓝灰、标识件也写浅蓝 —— 两者**色相完全相同**。
	# 这时"提饱和度"只会得到一个荧光版的同一种蓝（实测 0.33/0.49/0.88），
	# 数学上刚好越过 0.35 的阈值，视觉上却像贴了两块 LED 灯牌。
	# 判据用 0.06（≈22°）：色相差到这个程度以内，提饱和永远只是在放大同一个色相。
	if _hue_gap(desired, body) < 0.06:
		return _from_palette(desired, body)
	# ① 原色相内调整：**只升饱和度，不碰明度**。
	#
	# 这一档存在的理由：大多数"撞色"只是饱和不够（灰蓝 vs 灰蓝），
	# 提饱和就够，观感还是"同一件装备换了涂料"。
	#
	# ⚠ 上限 0.75 不是 1.0：推到满会把灰蓝变成荧光蓝
	# （2026-10-31 实测：链枪手的蓝灰背罐变成两块亮蓝板）。
	for target_saturation in [0.50, 0.62, 0.75]:
		var saturated := Color.from_hsv(
			desired.h,
			maxf(desired.s, target_saturation),
			clampf(desired.v, 0.40, 0.88)
		)
		if _distance(saturated, body) >= MIN_CONTRAST:
			return saturated
	# ② 还不够 ⇒ 从**高对比调色板**里挑。
	#
	# 为什么是"挑"而不是"算"：前两版都试过继续算（明度反转 / 色相反转），
	# 结果分别产出荧光粉与土黄 —— 数学上合格、观感上像换了材质语言。
	# 定死一组人工挑过的颜色，再从里面选**色相最接近原意图**的那个，
	# 既保证能读出来，又不会跑出"这一族该有的感觉"。
	return _from_palette(desired, body)


## 色相差（0~0.5，环绕最短距离）。
static func _hue_gap(a: Color, b: Color) -> float:
	return absf(fposmod(a.h - b.h + 0.5, 1.0) - 0.5)


## 从 `PALETTE` 里挑一个：**离身体够远**且**色相离原意图最近**。
static func _from_palette(desired: Color, body: Color) -> Color:
	var best := Color(0.06, 0.09, 0.16)
	var best_score := INF
	for entry in PALETTE:
		var candidate: Color = entry
		var body_gap := _distance(candidate, body)
		if body_gap < MIN_CONTRAST:
			continue
		# 分数 = 色相偏差为主、身体距离做微弱加权，避免挑到"刚好及格但颜色很闷"的那个。
		var score := _hue_gap(candidate, desired) - (body_gap - MIN_CONTRAST) * 0.10
		if score < best_score:
			best_score = score
			best = candidate
	return best


## 自发光必须基于**求解后的 albedo**，不能基于原始色。
##
## 第一版取的是"原色相 + 低饱和 + 满亮度"，结果是**几乎纯白**：米白的书怪、
## 白色的光环、白色的身体三者叠在一起完全分不开（2026-10-31 实测图）。
## 自发光是**叠加**在 albedo 之上的，所以它会盖掉 albedo 好不容易拉开的明度差。
##
## 现在：色相与饱和度跟 albedo 走，只把明度拉满 ——
## 于是"为了拉开对比而变深的零件"在暗处会发成一颗**饱和的彩灯**（深蓝 → 亮蓝），
## 与浅色身体依然分得清，而且黑暗里照样看得见。
static func resolve_emission(albedo: Color) -> Color:
	return Color.from_hsv(albedo.h, clampf(maxf(albedo.s, 0.55), 0.0, 1.0), 1.0)


## 验收用：同族内不许撞标识；33 只必须全部有设计；锚点名必须存在。
## 返回 `{"ok": bool, "problems": [String], "families": {...}, "total": int}`。
static func verify_design() -> Dictionary:
	var problems: Array[String] = []
	var by_family: Dictionary = {}
	var family_count: Dictionary = {}
	var known_anchors: Dictionary = ANCHORS["__program__"]
	for kind in FAMILY.keys():
		if not DESIGN.has(kind):
			problems.append("%s 没有标识设计" % kind)
	for kind in DESIGN.keys():
		if not FAMILY.has(kind):
			problems.append("%s 有标识设计但没登记族" % kind)
			continue
		var family := family_of(kind)
		var spec: Dictionary = DESIGN[kind]
		var anchor_name := str(spec.get("anchor", ""))
		if not known_anchors.has(anchor_name):
			problems.append("%s 的锚点名 %s 不存在" % [kind, anchor_name])
		var signature := "%s/%d/%s" % [
			str(spec.get("shape", "")),
			int(spec.get("count", 1)),
			(spec.get("color", Color.WHITE) as Color).to_html(),
		]
		var bucket: Dictionary = by_family.get(family, {})
		if bucket.has(signature):
			problems.append("同族撞标识：%s 与 %s（%s）" % [bucket[signature], kind, signature])
		bucket[signature] = kind
		by_family[family] = bucket
		family_count[family] = int(family_count.get(family, 0)) + 1
	return {
		"ok": problems.is_empty(),
		"problems": problems,
		"families": family_count,
		"total": DESIGN.size(),
	}
