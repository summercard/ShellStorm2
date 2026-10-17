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


# ── 眼睛绑点配方（2026-10-16）────────────────────────────────────────────────
#
# 强化怪要长一对**红色发光眼**，挂在 `Head` 骨上。但三个模型的骨骼有下列事实
# （全部由 `tools/probe_eye_*` 系列探针实测得出，不是推测）：
#
#   ① **没有 eye 骨**，只有 `Head`；每个模型是**单 surface、单材质、emission=off**，
#      所以「眼睛」在几何 / 材质 / 贴图上都没有可自动识别的特征；
#   ② 小僵尸与保安僵尸的 `Head` 骨 **pose 位于 y≈0.85（胸口）**，而网格的头在 y≈1.5
#      —— 骨空间与网格空间**不同源**（bind pose 的 y 是 −0.890）；胖子僵尸同源（y≈2.65）；
#   ③ 因此眼位必须用「模型总高比例 + 眼距半宽 + 相对头部最前点的前移」三件来描述，
#      再由 `EnemyAvatar3D` 在**运行时按模型自身顶点算**出骨空间局部偏移。
#
# **为什么存配方而不是存绝对坐标**：换成绝对坐标后，模型一旦重导 / 换版，眼睛会漂到脸外，
# 而且没人知道该改成多少。存配方则随模型自动重算 —— 这是本项目「单一真源」的一贯口径。
#
# 数值来源：`tools/probe_eye_confirm.tscn` / `probe_eye_xruler.tscn` 的实拍标定图
# （刻度线直接烧进像素，逐档目视比对）。**精度约 ±0.03 m**：这三只怪是低模
# （1545~2993 顶点），眼球在网格上只有几个面片，无法做到像素级对齐。
# 对「眼睛处的一团红光」这个表现目标，该精度足够；若要更准须改模型加眼骨。
##
## 基类 → 眼位配方。
const EYE_SOCKETS := {
	"melee_chaser": {
		# 2026-10-17：按原贴图两瞳中心射线命中蒙皮表面，再反算 Head 骨空间。
		# 两眼贴图并非关于模型根对称；直接跟骨，避免全身高度配方漂移。
		"bone_offsets": [Vector3(0.133553, 0.207281, 0.241197), Vector3(-0.166665, 0.203328, 0.249580)],
		# 下方比例只供旧标定工具取景；正式定位优先使用骨空间双眼锚点。
		# 眼睛高度 / 模型总高。
		"y_ratio": 0.550,
		# 单眼离中线距离（模型根空间 x，米）。
		"half_x": 0.160,
		# 相对「双眼窄带脸部最前 z」再往前多少（负 = 更靠近相机），保证眼球浮在脸外不陷进去。
		"front_offset": -0.015,
		# 眼球半径（米，模型根空间；根节点放大后世界尺寸按倍率走）。
		"radius": 0.040,
	},
	"ranged_caster": {
		# 注意：保安僵尸**戴着大檐帽**，比另两只怪的头型高得多，所以眼位比例明显更大。
		# 实测扫描图（`tools/probe_ranged_eye_scan.tscn`）显示眼睛落在 0.60~0.66 之间。
		"y_ratio": 0.630,
		"half_x": 0.155,
		"front_offset": -0.015,
		"radius": 0.040,
	},
	"fat_zombie03": {
		"y_ratio": 0.880,
		"half_x": 0.195,
		"front_offset": -0.015,
		"radius": 0.050,
	},
}

## 旧头部带探针参数，仅保留给历史标定工具；正式眼位改用双眼附近窄带。
const EYE_HEAD_BAND_FROM_TOP := 0.45
## 头部带内取 z 时的横向上限（米），用于排除手臂与肩部。
const EYE_HEAD_HALF_X_LIMIT := 0.45


## 三类僵尸普通版与强化版共用眼位配方（2026-10-17 用户修订）。
static func eye_socket_for(variant_kind: String) -> Dictionary:
	var base_kind := base_of(variant_kind)
	return eye_socket_for_base(base_kind if not base_kind.is_empty() else variant_kind)


## 按**基类**取眼位配方；该基类没有配方返回 `{}`。
static func eye_socket_for_base(base_kind: String) -> Dictionary:
	if not EYE_SOCKETS.has(base_kind):
		return {}
	return (EYE_SOCKETS[base_kind] as Dictionary).duplicate(true)


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
