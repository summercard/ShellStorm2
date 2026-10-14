class_name GameText
extends RefCounted

## 武器构建链路本地化模块（独立模块，2026-10-14 建立）
##
## 设计约定：
##  - 只做「内部稳定 ID → 本地化文本」的纯查表，不依赖任何 autoload、玩法类或场景。
##    调用方无需知道语言是否切换过，直接调静态方法即可。
##  - 所有键都是稳定标识：节点名（GunBody_Pistol）、槽位键（MUZZLE）、属性键（damage）、
##    枚举键（GUN_BODY）、稀有度 ID（common）、位置标签、标签（rifle）与 UI 语义键。
##  - 未知键一律回退到原始键本身，绝不返回空串 —— UI 宁可显示内部 ID，也不能空白。
##  - 回退链：当前语言包 → 默认语言包（zh_CN）→ 原始键。
##    「英文预留」位就是靠这条链：en 包条目留空时回退到中文；填表即生效。
##  - 文本长度随语言变化，调用方必须用容器/预留列宽排版，禁止依赖固定像素位移。

## 默认语言（实装语言）
const DEFAULT_LOCALE := "zh_CN"

## 语言登记顺序；新增语言 = 加 id + 建 pack 脚本 + 在此登记
const LOCALE_ORDER := ["zh_CN", "en"]

## 语言包缓存（id -> DATA 字典）
static var _packs: Dictionary = {}

## 当前语言
static var _locale: String = DEFAULT_LOCALE


# ==========================================================================
# 语言切换
# ==========================================================================

static func get_locale() -> String:
	return _locale


static func is_known_locale(locale_id: String) -> bool:
	return locale_id in LOCALE_ORDER


## 切换语言。未知 id 返回 false 且不改变当前语言；同 id 幂等成功。
static func set_locale(locale_id: String) -> bool:
	if not is_known_locale(locale_id):
		push_warning("[GameText] Unknown locale: %s" % locale_id)
		return false
	if locale_id == _locale:
		return true
	_locale = locale_id
	return true


## 语言元数据：{id, label, ready, code}
static func locale_meta(locale_id: String = "") -> Dictionary:
	var id := locale_id if not locale_id.is_empty() else _locale
	var meta: Dictionary = _pack(id).get("meta", {})
	var result := {
		"id": id,
		"label": str(meta.get("label", id)),
		"ready": bool(meta.get("ready", false)),
		"code": str(meta.get("code", id)),
	}
	return result


## 全部已登记语言（含未实装的预留位），按登记顺序
static func all_locales() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in LOCALE_ORDER:
		result.append(locale_meta(id))
	return result


## 仅已实装、可供玩家选择的语言
static func ready_locales() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for meta in all_locales():
		if bool(meta.get("ready", false)):
			result.append(meta)
	return result


# ==========================================================================
# 通用查询
# ==========================================================================

## UI 语义键查询；args 为格式化参数（模板含 %s/%d 时使用）
static func text(key: String, args: Array = []) -> String:
	return _format(_lookup("ui", key), args)


## 节点类型枚举键：GUN_BODY / BULLET / ATTACHMENT
static func node_type_key_name(type_key: String) -> String:
	return _lookup("node_type", type_key)


## 槽位键：MOUNT / MUZZLE / MAGAZINE / BULLET / SCOPE / STOCK / TACTICAL / MUTATOR
static func slot_key_name(slot_key: String) -> String:
	return _lookup("slot", slot_key)


## 属性键：damage / fire_rate / spread / crit_damage_multiplier ...
static func stat_key(key: String) -> String:
	return _lookup("stat", key)


## 属性值（枚举型，如 weapon_kind = melee/ranged）
static func stat_value(value: String) -> String:
	return _lookup("stat_value", value)


## 稀有度 ID → 显示名；未登记的保持旧行为（大写原文），不返回空白
static func rarity_name(rarity_id: String) -> String:
	if rarity_id.is_empty():
		return ""
	var key := rarity_id.to_lower()
	var hit := _lookup("rarity", key)
	return hit if hit != key else rarity_id.to_upper()


## 所有权位置标签（已装备 / 主武器 / 副武器 / 背包 / 地面 / 商店 / 保险柜）
static func location_name(location_id: String) -> String:
	if location_id.is_empty():
		return ""
	return _lookup("location", location_id)


## 装配节点名 → 显示名；支持前缀规则（命运构筑动态节点），未知则回退原文
static func node_name(raw_name: String) -> String:
	if raw_name.is_empty():
		return ""
	var hit := _lookup("node", raw_name)
	if hit != raw_name:
		return hit
	return _apply_prefix("node_prefix", raw_name, false)


## 内容标签 → 显示名；支持前缀规则（supports_ / attachment_slot_ / Fate.）
static func tag_name(raw_tag: String) -> String:
	if raw_tag.is_empty():
		return ""
	var hit := _lookup("tag", raw_tag)
	if hit != raw_tag:
		return hit
	return _apply_prefix("tag_prefix", raw_tag, true)


## 装配路径：节点数组 → "A / B / C"
static func node_path_text(nodes: Array) -> String:
	var parts: Array[String] = []
	for node in nodes:
		if node == null:
			continue
		var raw := str(node.get("node_name")) if node is Dictionary else str(node.node_name)
		parts.append(node_name(raw))
	return " / ".join(parts)


# ==========================================================================
# 内部
# ==========================================================================

static func _pack(locale_id: String) -> Dictionary:
	if _packs.has(locale_id):
		return _packs[locale_id]
	var data: Dictionary = {}
	match locale_id:
		"zh_CN":
			data = GameTextPackZhCN.DATA
		"en":
			data = GameTextPackEn.DATA
	_packs[locale_id] = data
	return data


static func _section(section: String, locale_id: String = "") -> Dictionary:
	var id := locale_id if not locale_id.is_empty() else _locale
	var value: Variant = _pack(id).get(section, {})
	return value if value is Dictionary else {}


static func _lookup(section: String, key: String) -> String:
	var current := _section(section)
	if current.has(key):
		return str(current[key])
	if _locale != DEFAULT_LOCALE:
		var base := _section(section, DEFAULT_LOCALE)
		if base.has(key):
			return str(base[key])
	return key


## 前缀规则：命中后把剩余部分递归再查一次（用于 FateAttachment_xxx / supports_scope）
static func _apply_prefix(section: String, raw: String, recursive_tail: bool) -> String:
	var table := _section(section)
	for prefix in table.keys():
		var prefix_text := str(prefix)
		if prefix_text.is_empty() or not raw.begins_with(prefix_text):
			continue
		var tail := raw.substr(prefix_text.length())
		var tail_text := tail
		if recursive_tail:
			tail_text = tag_name(tail)
		elif tail != raw:
			var hit := _lookup("node", tail)
			tail_text = hit if hit != tail else tail
		return str(table[prefix]) + tail_text
	return raw


static func _format(template: String, args: Array) -> String:
	if args.is_empty() or not ("%" in template):
		return template
	return template % args
