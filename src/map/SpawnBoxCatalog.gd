class_name SpawnBoxCatalog
extends RefCounted
## 触发盒资产目录：稳定 `box_id` → 盒子文件路径的**唯一真源**。
##
## 与 NarrativeCatalog / MusicCatalog / BossContentCatalog 同规格：代码只持有
## id → 路径，盒子本体在 `data/spawn_boxes/<box_id>.json`。逻辑侧只认 box_id，
## 不出现任何出怪清单字面量。规则见 `docs/v0.1/design/触发器刷怪设计.md` §3.1。
##
## 为什么盒子不进 .gd：出怪清单是**嵌套有序**结构（每条 type/count/delay 各异），
## 写成 GDScript 字面量既难读也无法被校验器逐值比对；且业主口径要求
## 「盒子本身是一个独立的文件，可以用来调用」—— 一个盒子一个文件，独立维护。
##
## 分层：本目录只负责**资产层**（盒子是什么）。
## 「哪个房间放哪个盒子」在房表 `spawn_placements`（放置层），
## 「第几波调用哪几个盒子」在 `encounter.stages`（调用层）。

const ROOT := "res://data/spawn_boxes/"
const SCHEMA := "shellstorm2.battle.spawn_box"
const SCHEMA_VERSION := 1

## 盒子最小边长（米）。业主 2026-09-26 口径：盒是「小型单位」，最小 2×2 m。
## 与 `DungeonRoom3D.SPAWN_BOX_MIN_SIZE_M` 同值；运行时对**逐实例覆盖尺寸**再夹一次。
const MIN_SIZE_M := 2.0
## 盒心离房墙默认内缩圈数（1 圈 = 5 m）。业主口径「往里挪一圈到 2 圈」。
## 盒子可在 `placement_policy.wall_recess_tiles` 覆盖（0 = 允许贴墙）。
const DEFAULT_WALL_RECESS_TILES := 1

## 盒子出怪清单允许的 type：普通怪 6 种（MonsterInjector.BASE_ENEMY_TYPES 去 boss）
## 外加 `elite` / `boss` —— 后两者是**身份指派**（内容），编成（数量/时机）仍由盒子给。
## 三个 `_strong`（-强化怪）也允许点名：它们平时由 15% 概率自动升级产出
## （见 `MonsterInjector._roll_strong_kind`），但允许盒子直接摆，
## 好让「这一房固定放一只强化胖子」这种编排写得出来。
##
## `egt_*` 12 种（远征03 复刻怪，2026-10-29）同样允许点名。
## 为什么必须显式列进白名单、不能靠"以 egt_ 开头就放过"：
## 本表是**唯一**的出怪类型闸门（`LevelPlanValidator` 与加载器都读它）。
## 用前缀通配会把拼写错误（`egt_bullet_kin_typo`）一起放过去，
## 而运行时该 type 不在 `MonsterInjector.BASE_ENEMY_TYPES` 里 ⇒ 盒子整条失效、
## 房间变成空房，且**不会报错** —— 这正是本文件反复警告的"静默失效"。
const ALLOWED_BOX_TYPES: Array[String] = [
	"fat_zombie03",
	"melee_chaser", "ranged_caster", "summoner",
	"exploder", "ambusher",
	"fat_zombie03_strong", "melee_chaser_strong", "ranged_caster_strong",
	"elite", "boss",
	# —— 远征03 复刻怪（逐只列出，不用前缀通配）——
	"egt_bullet_kin", "egt_bandana_kin", "egt_veteran_kin",
	"egt_red_shotgun", "egt_blue_shotgun",
	"egt_blobulon", "egt_blobuloid", "egt_blobulin",
	"egt_pinhead", "egt_nitra", "egt_bullat",
	"egt_gunsinger",
	# —— 第二批 21 只（2026-10-29）：33 种非 Boss 敌人全部可被盒子点名 ——
	"egt_cardinal", "egt_hollowpoint", "egt_veteran_shotgun", "egt_king_bullat",
	"egt_chancebulon", "egt_bookllet", "egt_blue_bookllet", "egt_green_bookllet",
	"egt_gunjurer", "egt_gigi", "egt_shotgat", "egt_grenat", "egt_spirat",
	"egt_keybullet_kin", "egt_chance_kin", "egt_confirmed", "egt_mimic",
	"egt_gun_fairy", "egt_gripmaster", "egt_gun_nut", "egt_chain_gunner",
]

## box_id → 相对 res:// 的盒子路径。新增盒子必须同时登记在本表，
## 否则 `has_id()` 为假、加载器直接拒绝（不静默兜底）。
## 通用盒一律**小型单位**（业主 2026-09-26 口径）：盒面 2~4 m、一盒出 1~4 只，
## 一房摆 3~5 盒以形成多个刷怪点。
## 当前共 **29 个 box_id = 7 个塔楼通用盒（5 小 + 2 大盒例外） + 22 个远征03 EGT 敌群盒**。
##
## 塔楼通用盒（远征01/02 与塔楼用）：
##   小盒 `box_corner_ambush` / `box_center_elite` / `box_corridor_column` /
##        `box_wall_arc` / `box_room_spread`，
##   大盒例外两个 `box_boss_arena` / `box_bridge_center`。
## 远征03 EGT 敌群盒（`box_egt_*`，2026-10-29）：8 个，每个是一个手作族群小队，
##   只给远征03 用 —— 该关**不再**走 `monster_rules.enemy_pool` 的房型公式。
##
## ⚠ **大盒例外目前有两个**（业主逐次点名，均须在 `触发器刷怪设计.md` §3.1.1 留档）：
##   · `box_boss_arena`（8×8 m，出 4 只）—— Boss 需要更大活动面；
##   · `box_bridge_center`（10×14 m，出 16 只，2026-09-29）—— 桥房「桥心压制」专用，
##     业主要求单盒一次压制 16 只（胖子僵尸×4 + 小僵尸×8 + 警察×4）。
##     尺寸 10 m 是**桥宽下限**：桥心可走面只有 2 格（10 m）宽，再宽就压进柱子；
##     桥心砖心恒在 `x=±2.5`，故盒心必离桥轴对称 2.5 m（判据 G 的必然结果，无解）。
const ENTRIES := {
	# 角落包夹：3×3 m，近战×2（共 2 只）。
	"box_corner_ambush": ROOT + "box_corner_ambush.json",
	# 精英点：4×4 m，精英×1 → 0.5s 近战×1。
	"box_center_elite": ROOT + "box_center_elite.json",
	# 窄长纵列：2×4 m，近战×2 → 1.5s 胖子僵尸×1。
	"box_corridor_column": ROOT + "box_corridor_column.json",
	# 贴墙远程小队：4×2 m，远程×1~2。
	"box_wall_arc": ROOT + "box_wall_arc.json",
	# 混编主盒：4×4 m，近战×2 → 1s 爆×1（共 3 只）。
	"box_room_spread": ROOT + "box_room_spread.json",
	# Boss 台：8×8 m（大盒①），Boss×1 → 1.5s 精英×2 → 3s 召唤者×1。
	"box_boss_arena": ROOT + "box_boss_arena.json",
	# 桥心压制：10×14 m（大盒②，桥房专属），小僵尸×8 → 1s 胖子僵尸×4 → 2s 警察×4（共 16 只）。
	"box_bridge_center": ROOT + "box_bridge_center.json",
	# =========================================================================
	# 远征03 · EGT 敌群盒（2026-10-29）
	#
	# 与上面 7 个「塔楼通用盒」的区别：这 8 个盒子是**照《挺进地牢》第一层的
	# 房间编成**做的手作敌群单元 —— 每个盒子 = 一个族群搭配好的小队，
	# 而不是"按房型公式算 N 只"。依据见
	# `docs/v0.1/reference/挺进地牢/第一层怪物数据表.md` 与 `怪物设计.md §T5`。
	#
	# 只给远征03 用：`monster_rules` 的 `enemy_pool` 已从该关移除，
	# 逐房编成写在 `level_plan.json` 的 `spawn_roster`。
	# =========================================================================
	# 子弹族·巡逻双人（单发×2）—— 最基础一组
	"box_egt_kin_patrol": ROOT + "box_egt_kin_patrol.json",
	# 子弹族·三变种同场（单发/三连发/预判）—— 视觉区分体系的验收点
	"box_egt_kin_trio": ROOT + "box_egt_kin_trio.json",
	# 霰弹族·前压（红霰弹 + 单发掩护）
	"box_egt_shotgun_lead": ROOT + "box_egt_shotgun_lead.json",
	# 霰弹族·双霰压场（蓝霰弹 + 红霰弹）—— 本关最重远程组合
	"box_egt_shotgun_heavy": ROOT + "box_egt_shotgun_heavy.json",
	# 分裂族·裂解群（母体 + 幼体，死亡会继续裂）
	"box_egt_blob_cluster": ROOT + "box_egt_blob_cluster.json",
	# 爆炸族·两种引爆（走近自爆 + 死亡留场）
	"box_egt_bomb_pair": ROOT + "box_egt_bomb_pair.json",
	# 一次性冲撞·突进线（子弹榴弹×2 + 预判远程）
	"box_egt_rush_line": ROOT + "box_egt_rush_line.json",
	# 辅助族·护卫班（枪歌者 + 护卫×2）—— 先杀辅助
	"box_egt_support_cell": ROOT + "box_egt_support_cell.json",
	# =========================================================================
	# 远征03 · EGT 敌群盒 第二批 14 个（2026-10-29）
	#
	# 第一批 8 个只覆盖了 12 种怪（6 族各 1~2 只）。第二批把剩余 21 种也编成敌群盒，
	# 于是**33 种非 Boss 敌人全部有落地编成**，不再是"表里有、关卡里见不到"。
	# 命名规则不变：一个盒子 = 一个族群搭配好的小队，不是"按公式算 N 只"。
	# =========================================================================
	# 子弹族·红衣主教护卫（追踪弹簇 + 预判）
	"box_egt_cardinal_guard": ROOT + "box_egt_cardinal_guard.json",
	# 子弹族·空尖弹连射线（高射速 + 周期瞬移）
	"box_egt_hollow_line": ROOT + "box_egt_hollow_line.json",
	# 霰弹族·老兵压场（V 型 + 必定全向喷）
	"box_egt_shotgun_vet": ROOT + "box_egt_shotgun_vet.json",
	# 爆炸族·子弹榴弹王（全向弹跳弹 + 死亡产两种子代）
	"box_egt_king_bullat": ROOT + "box_egt_king_bullat.json",
	# 分裂族·骰子布洛布（随机招式 + 有几率自杀）
	"box_egt_chance_blob": ROOT + "box_egt_chance_blob.json",
	# 书怪族·三色同排（同血 25，只换弹形）
	"box_egt_book_row": ROOT + "box_egt_book_row.json",
	# 法术族·枪法师 + 吉吉
	"box_egt_jurer_pair": ROOT + "box_egt_jurer_pair.json",
	# 冲撞族·三连冲（三种附加弹）
	"box_egt_rush_squad": ROOT + "box_egt_rush_squad.json",
	# 触发族·逃跑双人（11s 不打就传送消失）
	"box_egt_escape_pair": ROOT + "box_egt_escape_pair.json",
	# 触发族·已确认者小队（蛇形追踪 + 枪精灵骚扰）
	"box_egt_confirmed_cell": ROOT + "box_egt_confirmed_cell.json",
	# 触发族·拟态怪陷阱（靠近才现形）
	"box_egt_mimic_trap": ROOT + "box_egt_mimic_trap.json",
	# 触发族·抓握大师 + 护卫（场上还有人就无敌）
	"box_egt_grip_pair": ROOT + "box_egt_grip_pair.json",
	# 重型族·双重型（枪坚果 + 链枪手，小 Boss 级）
	"box_egt_heavy_pair": ROOT + "box_egt_heavy_pair.json",
	# 重型族·枪坚果护卫
	"box_egt_nut_guard": ROOT + "box_egt_nut_guard.json",
}

## 解析结果缓存：同一 box_id 每局只读一次盘。
static var _cache: Dictionary = {}


static func has_id(box_id: String) -> bool:
	return ENTRIES.has(box_id)


static func path_for(box_id: String) -> String:
	return str(ENTRIES.get(box_id, ""))


static func all_ids() -> Array:
	var ids: Array = ENTRIES.keys()
	ids.sort()
	return ids


## 读盘 + 规范化。返回 {} = box_id 未登记、文件缺失或 schema 不符（**不静默兜底**）。
## 结构：`{box_id, shape, size_m: Vector2, spawns: Array[Dictionary],
##          min_spacing_m: float, wall_recess_tiles: int, prefer_edge: bool(废弃)}`；
## `spawns[]` 逐条 `{type, count_min, count_max, delay_sec}`。
## ⚠ `prefer_edge` 自 2026-09-26 **废弃**（业主口径：盒内一律随机撒点、不贴边），
## 仍从 JSON 读出仅为兼容旧资产，运行时不再使用。
static func load_box(box_id: String) -> Dictionary:
	if _cache.has(box_id):
		return (_cache[box_id] as Dictionary).duplicate(true)
	var path := path_for(box_id)
	if path.is_empty():
		return {}
	var raw := _read_json(path)
	if raw.is_empty():
		return {}
	var errors := validate_box(raw, path)
	if not errors.is_empty():
		for message in errors:
			push_error("[SpawnBoxCatalog] %s" % message)
		return {}
	var box := _normalize(raw, box_id)
	_cache[box_id] = box.duplicate(true)
	return box


## 校验一份盒子原始 JSON。返回错误码数组（空 = 合法）。校验器与自检共用。
static func validate_box(raw: Dictionary, source: String = "") -> Array[String]:
	var errors: Array[String] = []
	var where := source if not source.is_empty() else str(raw.get("box_id", "?"))
	if str(raw.get("schema", "")) != SCHEMA:
		errors.append("spawn_box_schema_mismatch:%s:%s" % [where, str(raw.get("schema", ""))])
	if int(raw.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("spawn_box_schema_version:%s:%d" % [where, int(raw.get("schema_version", 0))])
	var size := _vec3_field(raw.get("size_m", []))
	if size.x <= 0.0 or size.z <= 0.0:
		errors.append("spawn_box_size_non_positive:%s" % where)
	elif size.x < MIN_SIZE_M - 0.001 or size.z < MIN_SIZE_M - 0.001:
		errors.append(
			"spawn_box_size_below_minimum:%s:%.2f×%.2f<%.1f"
			% [where, size.x, size.z, MIN_SIZE_M]
		)
	var shape := str(raw.get("shape", "box"))
	if shape != "box" and shape != "cylinder":
		errors.append("spawn_box_shape_invalid:%s:%s" % [where, shape])
	var raw_spawns: Variant = raw.get("spawns", [])
	if not (raw_spawns is Array) or (raw_spawns as Array).is_empty():
		errors.append("spawn_box_spawns_empty:%s" % where)
		return errors
	for index in range((raw_spawns as Array).size()):
		var entry_value: Variant = (raw_spawns as Array)[index]
		if not (entry_value is Dictionary):
			errors.append("spawn_box_entry_not_object:%s:%d" % [where, index])
			continue
		var entry := entry_value as Dictionary
		var type_id := str(entry.get("type", ""))
		if not ALLOWED_BOX_TYPES.has(type_id):
			errors.append("spawn_box_entry_type_invalid:%s:%d:%s" % [where, index, type_id])
		var range_result := _count_range(entry.get("count", 0))
		if int(range_result.x) <= 0 or int(range_result.y) < int(range_result.x):
			errors.append(
				"spawn_box_entry_count_invalid:%s:%d:%s"
				% [where, index, str(entry.get("count", 0))]
			)
		if float(entry.get("delay_sec", 0.0)) < 0.0:
			errors.append("spawn_box_entry_delay_negative:%s:%d" % [where, index])
	var policy: Variant = raw.get("placement_policy", {})
	if not (policy is Dictionary):
		errors.append("spawn_box_policy_not_object:%s" % where)
	elif float((policy as Dictionary).get("min_spacing_m", 0.0)) < 0.0:
		errors.append("spawn_box_policy_spacing_negative:%s" % where)
	return errors


## 自检：登记的每条路径都必须真实存在。校验器与验收用，运行时不用。
static func missing_files() -> Array:
	var missing: Array = []
	for box_id: String in ENTRIES:
		var path := str(ENTRIES[box_id])
		if not FileAccess.file_exists(path):
			missing.append("%s -> %s" % [box_id, path])
	return missing


## 自检：目录下存在但未登记的盒子文件（漏登记 = 写死了却调不到）。
static func unregistered_files() -> Array:
	var orphans: Array = []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return orphans
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var box_id := file_name.trim_suffix(".json")
		if not ENTRIES.has(box_id):
			orphans.append(ROOT + file_name)
	orphans.sort()
	return orphans


## 清缓存。仅验收脚本用 —— 运行时缓存要跨房复用。
static func clear_cache() -> void:
	_cache.clear()


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[SpawnBoxCatalog] 盒子文件不存在：%s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SpawnBoxCatalog] 盒子文件打不开：%s" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("[SpawnBoxCatalog] 盒子 JSON 解析失败：%s" % path)
		return {}
	return parsed as Dictionary


static func _normalize(raw: Dictionary, box_id: String) -> Dictionary:
	var size := _vec3_field(raw.get("size_m", []))
	# 约定 size_m = [width_x, height_y, depth_z]；盒面尺寸取 (x, z)，高度由房子层高决定。
	var spawns: Array[Dictionary] = []
	for entry_value in (raw.get("spawns", []) as Array):
		var entry := entry_value as Dictionary
		var range_result := _count_range(entry.get("count", 0))
		spawns.append({
			"type": str(entry.get("type", "")),
			"count_min": int(range_result.x),
			"count_max": int(range_result.y),
			"delay_sec": float(entry.get("delay_sec", 0.0)),
		})
	var policy: Dictionary = raw.get("placement_policy", {}) as Dictionary
	return {
		"box_id": box_id,
		"shape": str(raw.get("shape", "box")),
		"size_m": Vector2(size.x, size.z),
		"spawns": spawns,
		"min_spacing_m": float(policy.get("min_spacing_m", 0.0)),
		"wall_recess_tiles": int(policy.get("wall_recess_tiles", DEFAULT_WALL_RECESS_TILES)),
		# 废弃字段：保留只为兼容旧资产，运行时不再读取。
		"prefer_edge": bool(policy.get("prefer_edge", false)),
	}


## count 支持两种写法：正整数，或 `{min, max}`。返回 Vector2(min, max)。
static func _count_range(value: Variant) -> Vector2:
	if value is Dictionary:
		var dict := value as Dictionary
		return Vector2(float(dict.get("min", 0)), float(dict.get("max", 0)))
	if value is float or value is int:
		var fixed := float(value)
		return Vector2(fixed, fixed)
	return Vector2.ZERO


static func _vec3_field(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var array := value as Array
		return Vector3(float(array[0]), float(array[1]), float(array[2]))
	return Vector3.ZERO
