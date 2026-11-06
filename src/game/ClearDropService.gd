extends RefCounted
## 清房掉落纯服务（2026-11-06）。
##
## 只有一个问题：**这一间清完了掉什么**。不建节点、不碰钱包、不碰奖励发放 ——
## 落地面（`RewardSink`）与宝箱实例都留在 `Dungeon3D` / `DungeonRoom3D`。
##
## 掷骰口径：`ratio = hash(run_seed|room_id|用途)` 的稳定哈希，**不用运行时 RNG**。
## 同 seed 同房间恒得同一个结果 ⇒ 读档、流送卸载重建、重进房间都不会让
## 「这间房掉不掉箱子」发生改变。运行时 RNG 会让同一间房读档前后换结果，
## 那种不可复现的掉落无法验收，也无法解释给玩家。
##
## 本服务不认识任何关卡 ID：配置由关卡计划的 `clear_drops` 段下发，
## 未配置 ⇒ `is_configured() == false` ⇒ 调用方逐字走原路径（钥匙时代的行为不变）。

const SCHEMA := "shellstorm2.battle.clear_drops"
## 宝箱品质档（与 `TreasureChest3D.QUALITY_COLORS` 同序）。只用于「最低品质」过滤，
## 不认识的字串不会让掷骰崩掉，只会被当成「没有下限」。
const QUALITY_ORDER: Array[String] = ["common", "uncommon", "rare", "epic"]

var _configured := false
var _chest_chance := 0.0
var _boss_chest_count := 0
var _boss_min_quality := ""
var _chest: Dictionary = {}
var _fallback_pool: Array = []


## 配置整段 `clear_drops`。返回 `{ok, errors}`，与其余关卡段配置同形 ——
## 配置失败**不清空旧配置**以外的任何状态，调用方只需看 `ok` 决定是否报错。
func configure(config: Dictionary) -> Dictionary:
	_configured = false
	_chest_chance = 0.0
	_boss_chest_count = 0
	_boss_min_quality = ""
	_chest = {}
	_fallback_pool = []
	if config.is_empty():
		return {"ok": true, "errors": []}
	var errors: Array[String] = []
	if str(config.get("schema", "")) != SCHEMA:
		errors.append("clear_drops.schema 不符：%s" % str(config.get("schema", "")))
	var content := config.get("content_room", {}) as Dictionary
	_chest_chance = clampf(float(content.get("chest_chance", 0.0)), 0.0, 1.0)
	var boss := config.get("boss", {}) as Dictionary
	_boss_chest_count = maxi(0, int(boss.get("chest_count", 0)))
	_boss_min_quality = str(boss.get("min_quality", ""))
	_chest = (config.get("chest", {}) as Dictionary).duplicate(true)
	if _chest.is_empty():
		errors.append("clear_drops.chest 段缺失：宝箱无处取参数")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	_fallback_pool = (config.get("fallback_pool", []) as Array).duplicate(true)
	_configured = true
	return {"ok": true, "errors": []}


func is_configured() -> bool:
	return _configured


## 本关是否可能掉宝箱（HUD / 探针的可读真源，避免它们各写一套概率判断）。
func chest_chance() -> float:
	return _chest_chance


## 掷一次清房掉落。`room_kind`：`content`（清房）/ `boss`（首领阵亡）。
##
## 返回 `{kind, chest?, item?, roll, chance, room_id}`：
##   · `kind == "chest"` —— `chest` 可直接喂 `TreasureChest3D.configure()`；
##   · `kind == "item"`  —— `item = {item_id, count}`，走正常地面掉落通道；
##   · `kind == "none"`  —— 本房什么都不掉（配置为 0 概率或池为空）。
## 配置未生效 / 房号为空的返回值是**空字典**，调用方必须据此直接返回。
func roll_room_drop(room_id: String, room_kind: String, run_seed: int) -> Dictionary:
	if not _configured or room_id.is_empty():
		return {}
	if room_kind == "boss":
		# Boss 箱是**保底**：不走概率，`chest_count <= 0` 才是关掉它的开关。
		if _boss_chest_count <= 0:
			return {"kind": "none", "roll": 1.0, "chance": 1.0, "room_id": room_id}
		return {
			"kind": "chest",
			"chest": _build_chest(room_id, run_seed, _boss_min_quality),
			"roll": 1.0,
			"chance": 1.0,
			"room_id": room_id,
		}
	var roll := _stable_ratio("%d|%s|clear_drop" % [run_seed, room_id])
	if roll < _chest_chance:
		return {
			"kind": "chest",
			"chest": _build_chest(room_id, run_seed, ""),
			"roll": roll,
			"chance": _chest_chance,
			"room_id": room_id,
		}
	var item := _roll_fallback_item(room_id, run_seed)
	if item.is_empty():
		return {"kind": "none", "roll": roll, "chance": _chest_chance, "room_id": room_id}
	return {
		"kind": "item",
		"item": item,
		"roll": roll,
		"chance": _chest_chance,
		"room_id": room_id,
	}


## 宝箱配置。`chest_id` 与房号绑定 ⇒ 同一间房无论重建多少次都是同一只箱子，
## 房间账（`treasure_chests`）才不会因为 id 漂移而认不出「这只开过了」。
func _build_chest(room_id: String, run_seed: int, min_quality: String) -> Dictionary:
	var weights := (_chest.get("quality_weights", {}) as Dictionary)
	var quality := _roll_quality(weights, "%d|%s|chest_quality" % [run_seed, room_id], min_quality)
	var mimic_cfg := _chest.get("mimic", {}) as Dictionary
	var mimic_chance := clampf(float(mimic_cfg.get("chance", 0.0)), 0.0, 1.0)
	var mimic_salt := "%d|%s|chest_mimic" % [run_seed, room_id]
	return {
		"id": "drop_%s" % room_id,
		"quality": quality,
		"reward_pool_id": str(_chest.get("reward_pool_id", "loot_floor_1_2")),
		"drop_count": maxi(1, int(_chest.get("drop_count", 1))),
		# 0 = 开箱不自动发卡；命运卡改由**同一个购买界面**卖（与远征03 同口径）。
		"fate_card_per_open": maxi(0, int(_chest.get("fate_card_per_open", 0))),
		"mimic": _stable_ratio(mimic_salt) < mimic_chance,
		"mimic_monster_kind": str(mimic_cfg.get("monster_kind", "egt_mimic")),
	}


## 按权重掷品质。`min_quality` 非空时先按 `QUALITY_ORDER` 把低于下限的档整段剔除，
## 再在剩余档里归一 —— 这样 Boss 箱不会掷出一只「比清房箱还差」的宝箱。
## 剔除后为空则退回全表（宁可给出东西，也不让 Boss 掉一只不存在品质的箱子）。
func _roll_quality(weights: Dictionary, salt: String, min_quality: String) -> String:
	if weights.is_empty():
		return "common"
	var floor_index := QUALITY_ORDER.find(min_quality) if not min_quality.is_empty() else -1
	var entries: Array = []
	var total := 0.0
	for quality_value in weights.keys():
		var quality := str(quality_value)
		var weight := maxf(0.0, float(weights[quality_value]))
		if weight <= 0.0:
			continue
		var index := QUALITY_ORDER.find(quality)
		if floor_index >= 0 and index >= 0 and index < floor_index:
			continue
		entries.append({"quality": quality, "weight": weight})
		total += weight
	if entries.is_empty() or total <= 0.0:
		if floor_index < 0:
			return "common"
		return _roll_quality(weights, salt, "")
	# 稳定排序：权重降序、同权重按名字 —— 与 `FloorPlanGenerator._chest_quality_for_salt`
	# 同一个口径，两处掷同一份权重时必须给出同一个答案。
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if is_equal_approx(float(a["weight"]), float(b["weight"])):
				return str(a["quality"]) < str(b["quality"])
			return float(a["weight"]) > float(b["weight"])
	)
	var roll := _stable_ratio(salt) * total
	var accumulated := 0.0
	for entry_value in entries:
		var entry := entry_value as Dictionary
		accumulated += float(entry["weight"])
		if roll < accumulated:
			return str(entry["quality"])
	return str((entries.back() as Dictionary)["quality"])


## 兜底补给：从 `fallback_pool` 权重池抽一件。数量支持 `{min,max}` 区间，
## 用独立盐掷 —— 同一件物品的数量与「抽到谁」互不牵连。
func _roll_fallback_item(room_id: String, run_seed: int) -> Dictionary:
	if _fallback_pool.is_empty():
		return {}
	var entries: Array = []
	var total := 0.0
	for entry_value in _fallback_pool:
		var entry := entry_value as Dictionary
		var weight := maxf(0.0, float(entry.get("weight", 0.0)))
		if weight <= 0.0:
			continue
		entries.append(entry)
		total += weight
	if entries.is_empty() or total <= 0.0:
		return {}
	var roll := _stable_ratio("%d|%s|fallback_pick" % [run_seed, room_id]) * total
	var picked: Dictionary = entries.back()
	var accumulated := 0.0
	for entry_value in entries:
		var entry := entry_value as Dictionary
		accumulated += maxf(0.0, float(entry.get("weight", 0.0)))
		if roll < accumulated:
			picked = entry
			break
	var count_value: Variant = picked.get("count", 1)
	var count := 1
	if count_value is Dictionary:
		var minimum := int((count_value as Dictionary).get("min", 1))
		var maximum := maxi(minimum, int((count_value as Dictionary).get("max", minimum)))
		count = minimum + int(
			_stable_ratio("%d|%s|fallback_count" % [run_seed, room_id]) * float(maximum - minimum + 1)
		)
		count = clampi(count, minimum, maximum)
	else:
		count = maxi(1, int(count_value))
	return {"item_id": str(picked.get("item_id", "")), "count": count}


## 稳定哈希 → [0,1)。用 `absi(hash())` 而不是 `randf()`：Godot 的 `hash()` 对同一字符串
## 在同一构建里恒定，足以支撑「同 seed 同房同结果」，且不消耗主随机流。
static func _stable_ratio(salt: String) -> float:
	return float(absi(hash(salt)) % 1000003) / 1000003.0
