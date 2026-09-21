class_name NarrativeCatalog
extends RefCounted
## 剧本目录：稳定 `narrative_id` → 剧本文件路径的**唯一真源**。
##
## 与 MusicCatalog / EliteContentCatalog / BossContentCatalog / BarkCatalog 同规格，是本工程
## 既有的「内容目录」写法：代码只持有 id → 路径，剧本本体在 data/narrative/*.json。
## 逻辑侧只认 narrative_id，不出现任何剧本内容字面量。
##
## 为什么剧本不写进 .gd：时间轴是**嵌套有序**结构（每条 cue 的参数各异），写成 GDScript
## 字面量既难读也无法被校验器逐值比对。项目已有 JSON 内容先例（关卡布局清单、
## asset_manifest.json）。规则见 docs/v0.1/08_技术施工_剧情触发.md §3.2。

const ROOT := "res://data/narrative/"

## id → 相对 res:// 的剧本路径。新增剧本必须同时登记在本表，
## 否则 `has_id()` 为假、加载器直接拒绝（不静默兜底）。
const ENTRIES := {
	# 开场第一段：新游戏在 98F 主人的办公室（区块00 最深房间）醒来。
	"nar_tower_opening_01_wake": ROOT + "nar_tower_opening_01_wake.json",
	# 开场第二段：走进会议室（区块00 的下一间）时触发。
	"nar_tower_opening_02_zombies": ROOT + "nar_tower_opening_02_zombies.json",
}


static func has_id(narrative_id: String) -> bool:
	return ENTRIES.has(narrative_id)


static func path_for(narrative_id: String) -> String:
	return str(ENTRIES.get(narrative_id, ""))


## 供导演在启动时把**所有**数据驱动触发源登记进注册表。
static func all_ids() -> Array:
	var ids: Array = ENTRIES.keys()
	ids.sort()
	return ids


## 自检：登记的每条路径都必须真实存在。校验器与验收用，运行时不用。
static func missing_files() -> Array:
	var missing: Array = []
	for narrative_id: String in ENTRIES:
		var path := str(ENTRIES[narrative_id])
		if not FileAccess.file_exists(path):
			missing.append("%s -> %s" % [narrative_id, path])
	return missing
