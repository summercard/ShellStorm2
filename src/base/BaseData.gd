class_name BaseData
extends Resource

const SAVE_VERSION := "1.2"

var total_runs: int = 0
var successful_extractions: int = 0
var total_kills: int = 0

# 建筑解锁状态
var workshop_unlocked: bool = false
var greenhouse_unlocked: bool = false
var scrapyard_unlocked: bool = false
var divination_unlocked: bool = false
var vault_unlocked: bool = false
var blackmarket_unlocked: bool = false
var archive_unlocked: bool = false

# 建筑等级
var workshop_level: int = 0
var greenhouse_level: int = 0
var scrapyard_level: int = 0
var divination_level: int = 0
var vault_level: int = 0
var blackmarket_level: int = 0
var archive_level: int = 0

# 解锁进度
var blueprint_progress: float = 0.0  # 0.0-1.0
var bullet_variant_progress: float = 0.0
var boss_defeated: bool = false
var zero_load_extraction: bool = false
var five_tier_weapon_made: bool = false

# 蓝图解锁Tier（枪身/子弹/配件各有一个Tier，影响局内掉落池）
var blueprint_gunbody_tier: int = 0
var blueprint_bullet_tier: int = 0
var blueprint_attachment_tier: int = 0

# 玩家累计资源点数（用于蓝图解锁消费）
var extraction_points: int = 0

# 保险柜物品数据（跨局持久化，格式：[{item, insured_at}, ...]）
var vault_items: Array = []

# 下一局预选命运卡片（格式：{card_id, card_name, card_type, card_rarity, description, tags, effect, visual}）
var pending_fate_card: Dictionary = {}

# 下一局从保险柜带入的物品（启动任务时从 vault_items 转移到局内背包）
var pending_loadout_items: Array = []

# 撤离后待存入仓库的战利品（返回大厅后显示，可一键存入或逐个存入）
var extraction_loot: Array = []

func _to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"total_runs": total_runs,
		"successful_extractions": successful_extractions,
		"total_kills": total_kills,
		"workshop_unlocked": workshop_unlocked,
		"greenhouse_unlocked": greenhouse_unlocked,
		"scrapyard_unlocked": scrapyard_unlocked,
		"divination_unlocked": divination_unlocked,
		"vault_unlocked": vault_unlocked,
		"blackmarket_unlocked": blackmarket_unlocked,
		"archive_unlocked": archive_unlocked,
		"workshop_level": workshop_level,
		"greenhouse_level": greenhouse_level,
		"scrapyard_level": scrapyard_level,
		"divination_level": divination_level,
		"vault_level": vault_level,
		"blackmarket_level": blackmarket_level,
		"archive_level": archive_level,
		"blueprint_progress": blueprint_progress,
		"bullet_variant_progress": bullet_variant_progress,
		"boss_defeated": boss_defeated,
		"zero_load_extraction": zero_load_extraction,
		"five_tier_weapon_made": five_tier_weapon_made,
		"blueprint_gunbody_tier": blueprint_gunbody_tier,
		"blueprint_bullet_tier": blueprint_bullet_tier,
		"blueprint_attachment_tier": blueprint_attachment_tier,
		"extraction_points": extraction_points,
		"vault_items": vault_items,
		"pending_fate_card": pending_fate_card,
		"pending_loadout_items": pending_loadout_items,
		"extraction_loot": extraction_loot,
	}

static func from_dict(d: Dictionary) -> BaseData:
	var data := BaseData.new()
	if d.has("total_runs"): data.total_runs = d["total_runs"]
	if d.has("successful_extractions"): data.successful_extractions = d["successful_extractions"]
	if d.has("total_kills"): data.total_kills = d["total_kills"]
	if d.has("workshop_unlocked"): data.workshop_unlocked = d["workshop_unlocked"]
	if d.has("greenhouse_unlocked"): data.greenhouse_unlocked = d["greenhouse_unlocked"]
	if d.has("scrapyard_unlocked"): data.scrapyard_unlocked = d["scrapyard_unlocked"]
	if d.has("divination_unlocked"): data.divination_unlocked = d["divination_unlocked"]
	if d.has("vault_unlocked"): data.vault_unlocked = d["vault_unlocked"]
	if d.has("blackmarket_unlocked"): data.blackmarket_unlocked = d["blackmarket_unlocked"]
	if d.has("archive_unlocked"): data.archive_unlocked = d["archive_unlocked"]
	if d.has("workshop_level"): data.workshop_level = d["workshop_level"]
	if d.has("greenhouse_level"): data.greenhouse_level = d["greenhouse_level"]
	if d.has("scrapyard_level"): data.scrapyard_level = d["scrapyard_level"]
	if d.has("divination_level"): data.divination_level = d["divination_level"]
	if d.has("vault_level"): data.vault_level = d["vault_level"]
	if d.has("blackmarket_level"): data.blackmarket_level = d["blackmarket_level"]
	if d.has("archive_level"): data.archive_level = d["archive_level"]
	if d.has("blueprint_progress"): data.blueprint_progress = d["blueprint_progress"]
	if d.has("bullet_variant_progress"): data.bullet_variant_progress = d["bullet_variant_progress"]
	if d.has("boss_defeated"): data.boss_defeated = d["boss_defeated"]
	if d.has("zero_load_extraction"): data.zero_load_extraction = d["zero_load_extraction"]
	if d.has("five_tier_weapon_made"): data.five_tier_weapon_made = d["five_tier_weapon_made"]
	if d.has("blueprint_gunbody_tier"): data.blueprint_gunbody_tier = d["blueprint_gunbody_tier"]
	if d.has("blueprint_bullet_tier"): data.blueprint_bullet_tier = d["blueprint_bullet_tier"]
	if d.has("blueprint_attachment_tier"): data.blueprint_attachment_tier = d["blueprint_attachment_tier"]
	if d.has("extraction_points"): data.extraction_points = d["extraction_points"]
	if d.has("vault_items") and d["vault_items"] is Array: data.vault_items = Array(d["vault_items"])
	if d.has("pending_fate_card"): data.pending_fate_card = d["pending_fate_card"]
	if d.has("pending_loadout_items") and d["pending_loadout_items"] is Array: data.pending_loadout_items = Array(d["pending_loadout_items"])
	if d.has("extraction_loot") and d["extraction_loot"] is Array: data.extraction_loot = Array(d["extraction_loot"])
	return data

func record_run(success: bool, kills: int) -> void:
	total_runs += 1
	total_kills += kills
	if success:
		successful_extractions += 1
