class_name MonsterVariants
extends RefCounted
## 普通怪变种（「-强化怪」）的**唯一定义源**。
##
## 业主口径（2026-10-16）：
##   小僵尸-强化怪   体型 ×1.5、生命 ×2、攻击 ×2
##   胖子僵尸-强化怪 体型 ×1.5、生命 ×2、攻击 ×2、自爆范围 ×1.5
##   保安僵尸-强化怪 体型 ×1.5、生命 ×1.5、弹速 ×1.3、射程 ×2（子弹伤害不变）
## 换算口径为**乘法**：写「×2」就是 ×2，不是 ×3。
##
## ## 为什么单独成文件
## 「强化怪」要同时被 12 处查表认识（PROFILES / 体型表 / 血量基线 / 外观表 / 血条表 /
## 编成表 …），而每一处的判据都是
##     `kind if TABLE.has(kind) else "melee_chaser"`
## —— **写错名字不会报错，只会静默变回小僵尸**。把变种关系收进这一个文件，
## 其余各处只许引用 `variant_id` 与 `base_of()`，是为了让「漏登记」这件事
## 能在 `verify_strong_variant_monsters` 里被逐表断言抓到，而不是等到玩家看见一只小僵尸。
##
## ## 只存倍率，绝不存绝对数值
## 变种的一切绝对数值（生命 / 伤害 / 射程 / 自爆半径）都由**原怪的最终值**实时派生
## （见 `MonsterInjector._apply_strong_variant`）。以后把小僵尸 350 调成 400，
## 强化怪自动变 800 —— 不存在「两份数值各自漂移」的可能。
## 唯一的例外是 `scale_mult`：体型是变种自己的身份，不跟随原怪改动。
##
## 本文件只提供**纯计算**：不持有节点、不读场景树、不认识 Enemy3D 实例。


## 变种 ID 的后缀。新增变种必须沿用它，验收按它扫描。
const VARIANT_SUFFIX := "_strong"

## 中文显示名的后缀（正式名称 = 原怪名 + 此后缀）。
const DISPLAY_SUFFIX := "-强化怪"


## 基类 → 变种规格。
##
## `key` 必须是有正式美术的普通怪；`variant_id` 由 `_make_variant_id(key)` 派生，
## 写在这里是为了让「变种叫什么」一眼可读，不靠字符串拼接去猜。
const VARIANTS := {
	"melee_chaser": {
		"variant_id": "melee_chaser_strong",
		"display_name": "小僵尸" + DISPLAY_SUFFIX,
		"hp_mult": 2.0,
		"damage_mult": 2.0,
		"scale_mult": 1.5,
		"attack_range_mult": 1.5,
	},
	"fat_zombie03": {
		"variant_id": "fat_zombie03_strong",
		"display_name": "胖子僵尸" + DISPLAY_SUFFIX,
		"hp_mult": 2.0,
		"damage_mult": 2.0,
		"scale_mult": 1.5,
		"attack_range_mult": 1.5,
		# 自爆半径倍率。只在原怪**本身已配置自爆**时生效 ——
		# 没有自爆的原怪不会因为变种凭空长出爆炸（见 _apply_strong_variant 的守卫）。
		"death_explosion_radius_mult": 1.5,
	},
	"ranged_caster": {
		"variant_id": "ranged_caster_strong",
		"display_name": "保安僵尸" + DISPLAY_SUFFIX,
		"hp_mult": 1.5,
		# 业主只指定了 hp / 体型 / 弹速 / 射程，子弹伤害**明确保持不变**。
		"damage_mult": 1.0,
		"scale_mult": 1.5,
		"attack_range_mult": 1.5,
		"projectile_speed_mult": 1.3,
		"projectile_range_mult": 2.0,
	},
}


## 派生变种 ID。规范 = 基类 ID + 后缀。
static func _make_variant_id(base_kind: String) -> String:
	return base_kind + VARIANT_SUFFIX


## 该 kind 是不是强化怪。
static func is_variant(kind: String) -> bool:
	return base_of(kind) != ""


## 取强化怪的**基类**；不是强化怪返回空串。
##
## 反查靠规格表而不是切后缀：光看 `"melee_chaser_strong"` 切出
## `"melee_chaser"` 看着也对，但一旦将来出现名字里本来带 `_strong` 的原怪就会误判。
static func base_of(kind: String) -> String:
	for base_kind in VARIANTS:
		if str(VARIANTS[base_kind]["variant_id"]) == kind:
			return str(base_kind)
	return ""


## 取基类对应的**变种 ID**；该基类没有变种返回空串。
static func variant_of(base_kind: String) -> String:
	if not VARIANTS.has(base_kind):
		return ""
	return str(VARIANTS[base_kind]["variant_id"])


## 取某 kind 的变种规格（强化怪返回自己的规格，普通怪返回 `{}`）。
static func spec_for(kind: String) -> Dictionary:
	var base_kind := base_of(kind)
	if base_kind.is_empty():
		return {}
	return (VARIANTS[base_kind] as Dictionary).duplicate(true)


## 取某个**基类**的变种规格（普通怪返回自己的规格，强化怪返回 `{}`）。
## 与 `spec_for` 互为镜像，调用方按手上拿到的是哪种 ID 选一个用，避免各自写分支。
static func spec_for_base(base_kind: String) -> Dictionary:
	if not VARIANTS.has(base_kind):
		return {}
	return (VARIANTS[base_kind] as Dictionary).duplicate(true)


## 取某个基类的倍率，缺失时给 1.0（= 不变）。
##
## 调用方一律走这里，不要自己 `spec.get("hp_mult", 2.0)` 写默认值 ——
## 默认值只该有一份，写两处就会漂。
static func multiplier(base_kind: String, key: String) -> float:
	if not VARIANTS.has(base_kind):
		return 1.0
	return float((VARIANTS[base_kind] as Dictionary).get(key, 1.0))


## 取某 kind 的中文显示名；不是强化怪返回空串（调用方继续用原怪名）。
static func display_name_of(kind: String) -> String:
	var base_kind := base_of(kind)
	if base_kind.is_empty():
		return ""
	return str(VARIANTS[base_kind]["display_name"])


## 所有变种 ID（验收按它逐表扫描）。
static func all_variant_ids() -> Array[String]:
	var ids: Array[String] = []
	for base_kind in VARIANTS:
		if not VARIANTS.has(base_kind):
			continue
		ids.append(str((VARIANTS[base_kind] as Dictionary)["variant_id"]))
	ids.sort()
	return ids


## 所有基类 ID（有强化版的普通怪）。
static func all_base_kinds() -> Array[String]:
	var kinds: Array[String] = []
	for base_kind in VARIANTS:
		kinds.append(str(base_kind))
	kinds.sort()
	return kinds
