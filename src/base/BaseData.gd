class_name BaseData
extends Resource

const SAVE_VERSION := "1.0"

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
		"five_tier_weapon_made": five_tier_weapon_made
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
	return data

func record_run(success: bool, kills: int) -> void:
	total_runs += 1
	total_kills += kills
	if success:
		successful_extractions += 1