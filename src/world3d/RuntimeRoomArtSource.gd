@tool
extends RefCounted
## Shared identity for a generated room and its editable local-space art scene.
const SCHEMA := "shellstorm2.runtime_room_art.v1"

## 公馆壳体配方（原型表 + 逐格摆位）。复用键与运行时建壳都从这里取，
## 保证「烘焙器算的」与「游戏里建的」是同一套结果。
const MANOR_PLAN := preload("res://src/world3d/ManorShellPlan.gd")

static func supports(room: Node3D) -> bool:
	if bool(room.get("tower_module_shell")) or str(room.get("static_layout_scene_path")).is_empty():
		return false
	for port in room.get("connection_ports"):
		if port is Dictionary and port.has("door_width_m"):
			return true
	return false

## 签名 = **美术复用键**，决定"这一份美术能套到哪些房间上"。
##
## ## 2026-10-31 语义变更：从"整房几何指纹"改成"模板复用键"
##
## 业主原话：「这个场景工坊的意义就是复用美术进行拼装房间，当然算同一个可复用的」。
## 旧签名含 `ports`（每个端口的 side/lane/door_width/target）与 `doors`，于是
## **同一个模板只要门位差 5m 就算另一个房间** —— 美术做一次，只有那一局能用。
## 这与工坊的存在意义直接相悖。
##
## 新签名只留四件事：`template_id` / `size` / `type` / `safe_corner`。
## 门位与门向**刻意不进签名**：墙和门是**玩法几何**（决定通不通、往哪通），
## 必须跟当前局算；美术层只承载"这间房长什么样"。
##
## 配套硬约束（缺一不可，见 `DungeonRoom3D._strip_art_layer_geometry()`）：
## **加载美术层时必须剥掉墙 / 门墙 / 过梁 / 地板 / 角柱** —— 它们是几何层的产物，
## 留着就会按烘焙那一局的门位错位。剥完之后壳体由程序化分支按本局 ports 重建，
## 美术层只剩装饰、陈设、灯、材质。
##
## 历史教训（必须保留）：2026-10-31 早先移除了 `size_class` —— 它完全由 `size`
## 推导却单独进了 hash，10-29 那条"flow 房间按真实尺寸取档"的改动把 25×25 从
## `tower_cell` 改判成 `medium`，签名当场漂移，而失配是**静默**的，没人发现。
##
## 判据：**一个字段如果改推导规则就会变、或者每局都会变，它不属于签名。**
static func describe(room: Node3D) -> Dictionary:
	var dimensions: Vector2 = room.call("get_dimensions")
	var type_id := str(room.get("room_type"))
	var geometry := {
		"schema": SCHEMA,
		"size": [dimensions.x, dimensions.y],
		"type": type_id,
		"safe_corner": bool(room.get("safe_room_corner_l")),
	}
	# 文件名前缀：优先用模板 id，拿不到就按「房型_尺寸」拼一个。
	#
	# **模板 id 不进签名**：它只影响文件名，不影响"能不能复用"。这样即使某天上游
	# 开始（或停止）下发 template_id，复用键也不会跟着漂 —— 已经踩过一次
	# `size_class` 的坑，不再让"可选的元数据"参与 hash。
	var template_id := str(room.get("template_id"))
	if template_id.is_empty():
		template_id = "%s_%dx%d" % [
			type_id.to_lower() if not type_id.is_empty() else "room",
			int(round(dimensions.x)), int(round(dimensions.y)),
		]
	# 空间原型：由 `(room_type, 短边尺寸)` 纯函数算出，**跨种子稳定**。
	# 2026-10-31 起它取代门位成为复用键的第二个维度 —— 门位每局都变，
	# 拿它做键等于"美术只对烘那一刻的那一局有效"（实测跨 5 种子命中 1.4/17）。
	var style := MANOR_PLAN.style_for(room, dimensions)
	return {
		"signature": JSON.stringify(geometry, "", true).sha256_text(),
		"geometry": geometry,
		"room_id": str(room.get("room_id")),
		"template_id": template_id,
		"portal_fingerprint": _portal_fingerprint(room),
		# 只在诊断/日志里用；**不进文件名**（见 `art_path()`）。
		"style": style,
		"style_label": MANOR_PLAN.style_label(style),
		"style_fingerprint": MANOR_PLAN.style_fingerprint(style),
		"size_m": [dimensions.x, dimensions.y],
	}


## 门位指纹：四个侧面上「哪一面、偏移多少」的有序摘要，**只进文件名，不进签名**。
##
## ## 为什么结构层必须按门位分文件
##
## 复用键（`describe()` 的 geometry）**刻意不含门位** —— 那是为了「美术做一次，所有局生效」。
## 但墙与地板是**结构件**：门墙模块（`manor_wall_door`）的洞口是固定的 2.2m 居中，
## 只能摆在「本局门位所在的那一格」。实测同一复用键下有 5 间房门位各不相同：
##
##   combat_25x25_38083aa33b1a ← n02(east@-5,north@0,south@0) / n04(north@5,west@0)
##                                n05(east@-5,north@-5) / n06(north@0,south@0)
##                                fireplace(west@0)
##
## 若这 5 间共用一份含门墙的场景，4 间的门会被实心护墙堵死。所以**结构层按门位分文件**：
## 文件名 = `<template>_<签名前12>_<门位指纹前6>`。同门位仍可复用（跨种子有机会命中）。
##
## ## 代价（写进文档）
##
## 装饰层与结构层在同一份场景里，所以装饰也随之按门位分文件 —— 跨门位不再复用。
## 要让装饰独立复用，得把结构层与装饰层拆成两份文件分别匹配，那是另一套机制。
static func _portal_fingerprint(room: Node3D) -> String:
	var parts: Array[String] = []
	for value in room.get("connection_ports"):
		var port := value as Dictionary
		# 只用 side + lane：门宽与门高在远征03 恒为 2.2 / 2.8，不构成区分度。
		parts.append("%s@%.2f" % [str(port.get("side", "")), float(port.get("lane_m", 0.0))])
	parts.sort()
	if parts.is_empty():
		return ""
	return ",".join(parts).sha256_text().substr(0, 6)

## 美术文件名 = `<template_id>_<签名前12>_<原型指纹6>.tscn`。
##
## 前缀用**模板 id** 而不是 room_id：工坊里一眼能看出"这是 std_25x25 的美术"，
## 也不会因为每局房间 id 不同（注入房 `secret_room_inj1`、走廊 `cr00_entry_n01`）
## 而散成一堆只差前缀的重复文件。
##
## ## 2026-10-31 变更：第三段从「门位指纹」换成「原型指纹」
##
## 旧文件名是 `<template>_<签名前12>_<门位指纹前6>`。门位是几何求交的产物
## （`TowerDescent3D._shared_door_lane()`），**每局都不同** —— 于是同一份美术
## 隔一局就认不出来。实测跨 5 个种子，按门位命中只有 **1.4/17**；
## 业主那局（种子 3893044740）17 间房只有 3 间加载了公馆美术，其余是白盒。
##
## 换成原型指纹后实测命中 **15.8/17**：原型是 `(room_type, 短边)` 的纯函数，
## 跨种子恒定。墙体与地砖改由 `ManorShellPlan` 在运行时按**本局门位**生成，
## 所以美术做一次，所有局都生效。
static func art_path(base_static_path: String, descriptor: Dictionary) -> String:
	if base_static_path.is_empty() or descriptor.is_empty():
		return ""
	var template_id := str(descriptor.get("template_id", descriptor.get("room_id", "")))
	template_id = template_id.validate_filename()
	if template_id.is_empty():
		return ""
	var stem := "%s_%s" % [template_id, str(descriptor["signature"]).substr(0, 12)]
	var fingerprint := str(descriptor.get("style_fingerprint", ""))
	if not fingerprint.is_empty():
		stem = "%s_%s" % [stem, fingerprint]
	return base_static_path.get_base_dir().path_join("runtime_rooms/%s.tscn" % stem)

static func matching_path(room: Node3D, base_static_path: String) -> String:
	if not supports(room):
		return ""
	var descriptor := describe(room)
	var path := art_path(base_static_path, descriptor)
	if path.is_empty():
		return ""
	if ResourceLoader.exists(path, "PackedScene"):
		var packed := load(path) as PackedScene
		if packed != null:
			var state := packed.get_state()
			for index in range(state.get_node_property_count(0)):
				if str(state.get_node_property_name(0, index)) == "metadata/runtime_room_signature":
					if str(state.get_node_property_value(0, index)) == str(descriptor["signature"]):
						return path
	# ── 没命中：先查这件事是不是"过期"，再决定要不要出声 ────────────────────
	#
	# **失配默认是正常的**（这个房间还没人烘焙过），所以这里不报警 —— 否则每局
	# 28 个房间各刷一条，真问题会被淹掉。但"同 room_id 的烘焙文件存在、只是签名对不上"
	# 完全是另一回事：那说明美术做过这一间，代码改动或布局变化让它**悄悄失效**了。
	# 那种情况必须留下痕迹，2026-10-29 的 `size_class` 漂移就是靠静默失配藏了一个月的。
	var stale := stale_siblings(descriptor, base_static_path)
	if not stale.is_empty():
	# 同一房间的 `_expedition_static_layout_path()` 一局里会被问好几次（壳体重建、
	# 门扇同步、探针各问一遍）。不去重就是同一条警告刷三倍，噪音盖过信息。
		var warn_key := "%s|%s" % [
			str(descriptor.get("template_id", descriptor["room_id"])),
			str(descriptor["signature"]),
		]
		if not _stale_warned.has(warn_key):
			_stale_warned[warn_key] = true
			push_warning(
				"[RuntimeRoomArtSource] 模板 %s 有 %d 份烘焙美术因复用键不符被跳过（不会被加载，但会进包体）：%s —— 当前键 %s。请重跑场景工坊「读取关卡 → 保存」重建，或删除过期文件。"
				% [
					str(descriptor.get("template_id", descriptor["room_id"])),
					stale.size(), ", ".join(stale),
					str(descriptor["signature"]).substr(0, 12),
				]
			)
	return ""


## 已告警过的 `template_id|signature`。只用于去重，没有别的语义。
static var _stale_warned: Dictionary = {}


## `runtime_rooms/<template_id>_*.tscn` 里所有**签名与当前复用键不符**的文件名（不含目录）。
## 只看文件名，不 load —— 这条路径会在每次建房时走，不能有磁盘 IO 放大。
static func stale_siblings(descriptor: Dictionary, base_static_path: String) -> Array[String]:
	var result: Array[String] = []
	if base_static_path.is_empty() or descriptor.is_empty():
		return result
	var template_id := str(descriptor.get("template_id", descriptor.get("room_id", "")))
	template_id = template_id.validate_filename()
	if template_id.is_empty():
		return result
	var want := art_path(base_static_path, descriptor).get_file()
	var folder := base_static_path.get_base_dir().path_join("runtime_rooms")
	if not DirAccess.dir_exists_absolute(folder):
		return result
	for file_name in DirAccess.get_files_at(folder):
		if not file_name.begins_with(template_id + "_") or not file_name.ends_with(".tscn"):
			continue
		if file_name != want:
			result.append(file_name)
	result.sort()
	return result


# ── 结构件判定：哪一件是「玩法几何」，哪一件是「美术」 ─────────────────────────
#
# ## 为什么要有这一层，而不是在每个调用点各写一份名单
#
# 2026-10-31 之前，同一件事在**三个地方各写了一遍**，而且三份还不一样：
#   · `DungeonRoom3D.ART_LAYER_GEOMETRY_PREFIXES` —— 5 个精确文件名；
#   · `tools/scene_builder/capture_runtime.gd::_wall_height()` —— 认名字里含 `wall`；
#   · `tools/scene_builder/test_runtime_source.gd::_shell_bounds()` —— 4 个 contains。
# 后果：换正式美术资产时，只要新 prefab 名字不在那几条里，它就会被当成**装饰**
# 留在美术层 —— 墙跟着美术走、门位一变就错位，表现是「图上有门、走过去撞墙」。
# 而三份名单只要漏改一处，判据还会互相矛盾。
#
# ## 现在的判据（按优先序，任一条命中即结构件）
#
# 1. **程序化壳体自带 prefab**：`props/dungeon_3d/` + 名字族（`prp_room_floor` 等）。
#    这些是引擎自己铺地板/墙/门楣/角柱用的，永远不是装饰。
# 2. **组件目录的 `slot_role`**：`shell_component_catalog.json` 里登记为
#    `solid_wall` / `door_wall` / `door_leaf_preview` / `floor` / `floor_tile` /
#    `corner_l` 的，一律算结构件。
#    **这是"以后加资产不用改代码"的那条路**：新墙登记进目录（本来就要登记，
#    否则工坊里刷不出来）并带上正确 role，就自动被剥，不需要碰任何 .gd。
# 3. **名字族前缀**：给第 2 条兜底 —— 目录里有些结构件登记成了
#    `room_type_component`（`floor_base` / `ceiling_deck_5m`），靠 role 抓不到。
#    按族匹配（`floor_base` 命中 `floor_base_5m`），不是逐件枚举。
#
# 都不命中 ⇒ **当装饰保留**。默认保留而不是默认剥离：剥错了会缺东西且难查，
# 留错了最多是位置略歪，能在工坊里一眼看见。

## 组件目录 —— 与 `scene_builder/scene_index.gd` 读的是同一份，不另立真源。
const COMPONENT_CATALOG := (
	"res://assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json"
)

## 结构件的**角色标签**。不只回答"是不是结构"，还回答"是哪一类结构"。
##
## 为什么要分：`capture_runtime._wall_height()` 要量的是**墙**高，
## 而一角柱（2.9m）或一块门楣也在结构集合里 —— 混在一起量出来就不是墙高。
## 早先它靠「名字里含 wall」绕开这件事，那正是随资产改名就失效的那种判据。
const TAG_WALL := "wall"
const TAG_FLOOR := "floor"
const TAG_CORNER := "corner"
const TAG_TRIM := "trim"
const TAG_DOOR := "door"

## 结构件的名字族 → 角色。**加同族新资产不用改代码**，加新族才加一行。
const STRUCTURE_FAMILIES := {
	# 程序化白盒壳体（引擎自己铺的，永远不是装饰）
	"prp_room_wall": TAG_WALL,
	"prp_room_floor": TAG_FLOOR,
	"prp_room_corner": TAG_CORNER,
	"prp_room_door_lintel": TAG_TRIM,
	# 塔楼 / 远征共用结构
	"wall_standard": TAG_WALL, "wall_door": TAG_WALL, "wall_solid": TAG_WALL,
	"wall_skin": TAG_WALL, "wall_collapse": TAG_WALL, "wall_5m": TAG_WALL,
	"wall_t": TAG_WALL, "wall_x": TAG_WALL, "door_wall": TAG_WALL,
	"door_5m": TAG_DOOR,
	"floor_base": TAG_FLOOR, "floor_tile": TAG_FLOOR,
	"base_floor_base": TAG_FLOOR, "ceiling_deck": TAG_TRIM,
	# 复古公馆套件（已登记的结构件）
	"manor_wall_standard": TAG_WALL, "manor_wall_window": TAG_WALL,
	"manor_wall_door": TAG_WALL,
	"manor_floor_wood": TAG_FLOOR, "manor_floor_stone": TAG_FLOOR,
	"manor_floor_bath": TAG_FLOOR,
}

## 组件目录的 `slot_role` → 角色。加新角色时才需要改这里（加名字不用）。
const CATALOG_ROLE_TAGS := {
	"solid_wall": TAG_WALL,
	"door_wall": TAG_WALL,
	"door_leaf_preview": TAG_DOOR,
	"floor": TAG_FLOOR,
	"floor_tile": TAG_FLOOR,
	"corner_l": TAG_CORNER,
}

## 程序化壳体的 prefab 库。只有这个目录下的 `prp_` 族按第 ① 条判。
const PROCEDURAL_SHELL_DIR := "res://assets/art/props/dungeon_3d/"

## 目录里登记为结构件的 slug → 角色（懒加载一次）。空 = 目录不可读，只靠名字族。
static var _structure_slugs: Dictionary = {}
static var _catalog_loaded := false


static func _ensure_catalog() -> void:
	if _catalog_loaded:
		return
	_catalog_loaded = true
	if not FileAccess.file_exists(COMPONENT_CATALOG):
		# 目录不在（导出时被 exclude，或换了工作区）不是错误：名字族兜底照常工作。
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COMPONENT_CATALOG))
	if not parsed is Dictionary:
		return
	for value in (parsed as Dictionary).get("components", []):
		var entry := value as Dictionary
		var tag := str(CATALOG_ROLE_TAGS.get(str(entry.get("slot_role", "")), ""))
		if tag.is_empty():
			continue
		var slug := str(entry.get("slug", ""))
		if not slug.is_empty() and not _structure_slugs.has(slug):
			_structure_slugs[slug] = tag


## prefab 名字 → 去套件后缀的 slug（`wall_door_5m_h3_root_top3d.tscn` → `wall_door_5m_h3`）。
static func prefab_slug(prefab_path: String) -> String:
	var stem := prefab_path.get_file().get_basename()
	for suffix in ["_root_top3d", "_top3d"]:
		if stem.ends_with(suffix):
			return stem.substr(0, stem.length() - suffix.length())
	return stem


## `slug` 是否属于某个名字族。**匹配在词边界上，不是裸前缀**。
##
## 三种情形，全部要求族名后是边界：
##   · `slug == family`
##   · `family + "_…"` —— `floor_base` → `floor_base_5m`
##   · `family + 数字…` —— `wall_x` → `wall_x670`
## 另外允许族名**出现在中间且前面是下划线**：资产命名带套件前缀
## （`env_manor_wall_standard`、`prp_room_wall_segment`）时，
## 族名不会在开头，但 `_` 之后必须是边界。
##
## 为什么不能裸 `contains`：`wall_t` 这种短族会吃掉 `wall_tapestry`，
## 而挂毯是装饰 —— 剥掉就是「沙发凭空消失」的那一类错。
static func _matches_family(slug: String, family: String) -> bool:
	var at := slug.find(family)
	while at >= 0:
		if at == 0 or slug[at - 1] == "_":
			var rest := slug.substr(at + family.length())
			if rest.is_empty() or rest.begins_with("_") or rest.substr(0, 1).is_valid_int():
				return true
		at = slug.find(family, at + 1)
	return false


## 这一件 prefab 的结构角色；`""` = 它是**美术**（装饰 / 陈设 / 灯 / 材质）。
##
## 判据见本节开头的优先序。不可读 prefab（运行时 new 出来的节点、无 scene_file_path）
## 返回 `""` —— 那不是资产，是程序化产物，由它自己的父级决定去留。
static func structure_tag(prefab_path: String) -> String:
	if prefab_path.is_empty():
		return ""
	var slug := prefab_slug(prefab_path)
	if slug.is_empty():
		return ""
	# ① 程序化壳体的自带 prefab
	if prefab_path.contains(PROCEDURAL_SHELL_DIR):
		for family in STRUCTURE_FAMILIES.keys():
			if str(family).begins_with("prp_") and _matches_family(slug, str(family)):
				return str(STRUCTURE_FAMILIES[family])
	# ② 目录登记的结构件（新资产走这条，不用改代码）
	_ensure_catalog()
	for known in _structure_slugs.keys():
		if slug == str(known) or slug.begins_with(str(known) + "_"):
			return str(_structure_slugs[known])
	# ③ 名字族兜底
	for family in STRUCTURE_FAMILIES.keys():
		if _matches_family(slug, str(family)):
			return str(STRUCTURE_FAMILIES[family])
	return ""


## 这一件 prefab 是不是**玩法几何**（地板 / 墙 / 门墙 / 门楣 / 角柱 / 门扇预览）。
static func is_structure_prefab(prefab_path: String) -> bool:
	return not structure_tag(prefab_path).is_empty()


## 这一件 prefab 是不是**墙**（量墙高时只认这类，不能把角柱与门楣混进来）。
static func is_wall_prefab(prefab_path: String) -> bool:
	return structure_tag(prefab_path) == TAG_WALL


# ── 远征03 特例：允许留在美术层里的结构件 ──────────────────────────────────────
#
# ## 为什么需要这个例外
#
# 默认规则是「结构件一律剥掉，壳体由程序化按本局 ports 重建」，理由见本节开头。
# 但远征03 的美术方向是**用复古公馆模块拼装房间**（业主 2026-10-31：「结构要进美术层，
# 作为远征03的特例，然后……让这些资产都能在远征03使用拼装」）—— 护墙模块、门墙模块、
# 5m 地砖本身就是这套美术的一部分。剥掉它们，工坊里摆的东西会静默消失。
#
# ## 为什么这个例外是安全的
#
# ① **只放开指定名字族**，且**程序化壳体 `prp_room_*` 永远不放行** —— 后者是引擎自己铺的
#    白盒，留着必然与程序化重建重复。
# ② 只有美术层里**真的摆了**这些件，例外才起作用；没摆时行为与默认逐字一致。
# ③ 放行之后由 `DungeonRoom3D` 按**实际覆盖**决定要不要跳过程序化的地板/某面墙 ——
#    摆满就接管，摆不满就由程序化补齐，不会出现「一半墙是美术、一半是空白」。
#
# ## 代价（必须知道）
#
# 公馆墙模块是 5m 整数倍、按**保存那一局**的门位摆的。门位一变，墙不会自己挪。
# 这与默认规则要解决的问题是同一件事，只是远征03 选择由**美术作者**承担它：
# 装门的位置必须放 `manor_wall_door`，不能放实心护墙。

## 允许进美术层的结构件名字族前缀。目前只有复古公馆套件。
const ART_LAYER_STRUCTURE_ALLOWLIST: Array[String] = ["manor_"]


## 这一件结构件是否**允许留在美术层**（而不是被剥掉）。
##
## 程序化壳体 prefab 一律 `false`：它们由 `_build_shell` 每次重建，留着就是重复几何。
static func is_art_layer_structure(prefab_path: String) -> bool:
	if structure_tag(prefab_path).is_empty():
		return false
	if prefab_path.contains(PROCEDURAL_SHELL_DIR):
		return false
	var slug := prefab_slug(prefab_path)
	for value in ART_LAYER_STRUCTURE_ALLOWLIST:
		# 走 `_matches_family`（词边界）而不是裸前缀：套件导出的文件名带前缀，
		# 实际 slug 是 `env_manor_wall_standard`，`begins_with("manor_")` 匹配不到它。
		if _matches_family(slug, str(value).trim_suffix("_")):
			return true
	return false
