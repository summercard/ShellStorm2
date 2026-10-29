class_name MonsterInjector
extends RefCounted
## 怪物注入器 — 根据房间类型和层级生成怪物配置

## 怪物基础类型配置
##
## 带 `_strong` 后缀的三个是「普通怪变种（-强化怪）」，倍率定义见 `MonsterVariants`。
## 它们的 `hp_base` / `damage_base` / `speed` **逐值照抄原怪**，倍率不在这里乘：
## 倍率由 `Enemy3D.PROFILES` 的派生层（`_profile_for`）作用**一次**。
## 若此处也乘一遍，Enemy3D 的「原怪基线 → 实际值」比例还原会把倍率算两遍
## （实测会把 ×2 放大成 ×4）。`name` 与 `MonsterVariants.display_name_of()` 必须一致，
## 由 `verify_strong_variant_monsters` 断言钉住。
const BASE_ENEMY_TYPES := {
	"fat_zombie03": {"name": "胖子僵尸", "hp_base": 100, "damage_base": 8, "speed": 20.5714286},
	"melee_chaser": { "name": "小僵尸", "hp_base": 25, "damage_base": 5, "speed": 80 },
	"ranged_caster": { "name": "孢子射手", "hp_base": 15, "damage_base": 8, "speed": 50 },
	"summoner": { "name": "蜂巢怪", "hp_base": 30, "damage_base": 0, "speed": 40 },
	"exploder": { "name": "炸弹果", "hp_base": 10, "damage_base": 15, "speed": 70 },
	"ambusher": { "name": "地刺虫", "hp_base": 18, "damage_base": 7, "speed": 90 },
	"boss": { "name": "准首领", "hp_base": 100, "damage_base": 12, "speed": 42 },
	"melee_chaser_strong": { "name": "小僵尸-强化怪", "hp_base": 25, "damage_base": 5, "speed": 80 },
	"fat_zombie03_strong": { "name": "胖子僵尸-强化怪", "hp_base": 100, "damage_base": 8, "speed": 20.5714286 },
	"ranged_caster_strong": { "name": "保安僵尸-强化怪", "hp_base": 15, "damage_base": 8, "speed": 50 },
	# —— 远征03：《挺进地牢》第一层复刻怪（2026-10-29）——
	# `hp_base` = **进场血量** = EGT 血量 × 10。系数 10 来自「保持击杀发数」：
	# EGT Bullet Kin 15 血 / 初始手枪约 6 伤 ≈ 3 发；本工程初始步枪 50 伤/发 ⇒ 150 血同样 3 发。
	# 故与原作**严格等比**（6.67 倍差就是 6.67 倍），不再做幂律压缩。依据见 `怪物设计.md §T0.2`。
	# `damage_base` = 命中玩家的伤害 = 玩家 100 血的 **1/6 = 17**（对应原作「半颗心」），爆炸类 26。
	# 原始 EGT 血量记在 `egt_hp` 键里，**只作追溯**，不参与任何计算 —— 避免两份血量被当成两个真源。
	# `speed` 单位是 px/s（`Enemy3D` 里 ÷24 转 m/s 再 ×0.7），即「目标 m/s ÷ 0.7 × 24」。
	"egt_bullet_kin": { "name": "子弹小子", "hp_base": 150, "damage_base": 17, "speed": 69, "egt_hp": 15 },
	"egt_bandana_kin": { "name": "头巾小子", "hp_base": 150, "damage_base": 17, "speed": 69, "egt_hp": 15 },
	"egt_veteran_kin": { "name": "老兵小子", "hp_base": 150, "damage_base": 17, "speed": 89, "egt_hp": 15 },
	"egt_red_shotgun": { "name": "红霰弹枪小子", "hp_base": 300, "damage_base": 17, "speed": 69, "egt_hp": 30 },
	"egt_blue_shotgun": { "name": "蓝霰弹枪小子", "hp_base": 400, "damage_base": 17, "speed": 69, "egt_hp": 40 },
	"egt_blobulon": { "name": "布洛布", "hp_base": 200, "damage_base": 17, "speed": 75, "egt_hp": 20 },
	"egt_blobuloid": { "name": "布洛布幼体", "hp_base": 100, "damage_base": 17, "speed": 82, "egt_hp": 10 },
	"egt_blobulin": { "name": "布洛布微体", "hp_base": 10, "damage_base": 17, "speed": 117, "egt_hp": 1 },
	"egt_pinhead": { "name": "保险销头", "hp_base": 130, "damage_base": 17, "speed": 82, "egt_hp": 13 },
	"egt_nitra": { "name": "硝酸怪", "hp_base": 100, "damage_base": 17, "speed": 82, "egt_hp": 10 },
	"egt_bullat": { "name": "子弹榴弹", "hp_base": 10, "damage_base": 17, "speed": 82, "egt_hp": 1 },
	"egt_gunsinger": { "name": "枪歌者", "hp_base": 150, "damage_base": 0, "speed": 34, "egt_hp": 15 },
	# —— 第二批 21 只（2026-10-29）：口径与上面完全一致 ——
	# `hp_base` = 幂律换算后的 3D 基线；`speed` = 目标 m/s ÷ 0.7 × 24（px/s）。
	"egt_cardinal": { "name": "红衣主教", "hp_base": 225, "damage_base": 17, "speed": 69, "egt_hp": 22.5 },
	"egt_hollowpoint": { "name": "空尖弹", "hp_base": 250, "damage_base": 17, "speed": 62, "egt_hp": 25 },
	"egt_veteran_shotgun": { "name": "老兵霰弹枪小子", "hp_base": 338, "damage_base": 17, "speed": 69, "egt_hp": 33.8 },
	"egt_king_bullat": { "name": "子弹榴弹王", "hp_base": 260, "damage_base": 17, "speed": 21, "egt_hp": 26 },
	"egt_chancebulon": { "name": "骰子布洛布", "hp_base": 500, "damage_base": 17, "speed": 82, "egt_hp": 50 },
	"egt_bookllet": { "name": "书怪", "hp_base": 250, "damage_base": 17, "speed": 55, "egt_hp": 25 },
	"egt_blue_bookllet": { "name": "蓝书怪", "hp_base": 250, "damage_base": 17, "speed": 55, "egt_hp": 25 },
	"egt_green_bookllet": { "name": "绿书怪", "hp_base": 250, "damage_base": 17, "speed": 55, "egt_hp": 25 },
	"egt_gunjurer": { "name": "学徒枪法师", "hp_base": 188, "damage_base": 17, "speed": 51, "egt_hp": 18.8 },
	"egt_gigi": { "name": "吉吉", "hp_base": 120, "damage_base": 17, "speed": 123, "egt_hp": 12 },
	"egt_shotgat": { "name": "霰弹榴弹", "hp_base": 20, "damage_base": 17, "speed": 82, "egt_hp": 2 },
	"egt_grenat": { "name": "榴弹子", "hp_base": 30, "damage_base": 17, "speed": 82, "egt_hp": 3 },
	"egt_spirat": { "name": "螺旋转弹", "hp_base": 50, "damage_base": 17, "speed": 82, "egt_hp": 5 },
	"egt_keybullet_kin": { "name": "钥匙小子", "hp_base": 150, "damage_base": 17, "speed": 103, "egt_hp": 15 },
	"egt_chance_kin": { "name": "运气小子", "hp_base": 150, "damage_base": 17, "speed": 103, "egt_hp": 15 },
	"egt_confirmed": { "name": "已确认者", "hp_base": 450, "damage_base": 17, "speed": 75, "egt_hp": 45 },
	"egt_mimic": { "name": "拟态怪", "hp_base": 1000, "damage_base": 17, "speed": 75, "egt_hp": 100 },
	"egt_gun_fairy": { "name": "枪精灵", "hp_base": 150, "damage_base": 17, "speed": 103, "egt_hp": 15 },
	"egt_gripmaster": { "name": "抓握大师", "hp_base": 300, "damage_base": 0, "speed": 69, "egt_hp": 30 },
	"egt_gun_nut": { "name": "枪坚果", "hp_base": 1000, "damage_base": 17, "speed": 62, "egt_hp": 100 },
	"egt_chain_gunner": { "name": "链枪手", "hp_base": 900, "damage_base": 17, "speed": 72, "egt_hp": 90 },
}

const ENEMY_PRESENTATION := {
	"fat_zombie03": {"emoji": "尸", "color": Color(0.38, 0.43, 0.26), "ai_type": "chase"},
	"melee_chaser": { "emoji": "尸", "color": Color(0.95, 0.28, 0.24, 1.0), "ai_type": "chase" },
	"ranged_caster": { "emoji": "🍄", "color": Color(0.62, 0.35, 1.0, 1.0), "ai_type": "ranged" },
	"summoner": { "emoji": "🐝", "color": Color(0.95, 0.70, 0.16, 1.0), "ai_type": "summoner" },
	"exploder": { "emoji": "💣", "color": Color(1.0, 0.58, 0.14, 1.0), "ai_type": "bomber" },
	"ambusher": { "emoji": "🦂", "color": Color(0.78, 0.28, 0.88, 1.0), "ai_type": "trapper" },
	"boss": { "emoji": "👹", "color": Color(1.0, 0.12, 0.08, 1.0), "ai_type": "chase" },
	# 强化怪表现照抄原怪：业主 2026-10-16 裁定「只放大 1.5 倍」作为唯一区分手段，
	# 不做换色/发光。emoji 与 color 是掉落与诊断用的，仍沿用原怪以免出现第四套配色。
	"melee_chaser_strong": { "emoji": "尸", "color": Color(0.95, 0.28, 0.24, 1.0), "ai_type": "chase" },
	"fat_zombie03_strong": {"emoji": "尸", "color": Color(0.38, 0.43, 0.26), "ai_type": "chase"},
	"ranged_caster_strong": { "emoji": "🍄", "color": Color(0.62, 0.35, 1.0, 1.0), "ai_type": "ranged" },
	# —— 远征03：EGT 第一层复刻怪（2026-10-29）——
	# `ai_type` 是**表现层标签**（掉落/诊断用）；真正决定行为的是 `Enemy3D.PROFILES` 的行。
	# 五个远程共用 `ranged`（只差 `volley` 规格），三只布洛布共用 `chase`，
	# 三只爆炸系共用 `bomber` —— 符合 [AI 设计 §3.1]「参数能表达的差异不新建策略」。
	"egt_bullet_kin": { "emoji": "🔸", "color": Color(0.55, 0.72, 0.95, 1.0), "ai_type": "ranged" },
	"egt_bandana_kin": { "emoji": "🔹", "color": Color(0.36, 0.62, 0.98, 1.0), "ai_type": "ranged" },
	"egt_veteran_kin": { "emoji": "🔶", "color": Color(0.98, 0.60, 0.28, 1.0), "ai_type": "ranged" },
	"egt_red_shotgun": { "emoji": "🔻", "color": Color(0.92, 0.26, 0.26, 1.0), "ai_type": "ranged" },
	"egt_blue_shotgun": { "emoji": "🔷", "color": Color(0.32, 0.52, 0.96, 1.0), "ai_type": "ranged" },
	"egt_blobulon": { "emoji": "🟢", "color": Color(0.46, 0.86, 0.42, 1.0), "ai_type": "chase" },
	"egt_blobuloid": { "emoji": "🟡", "color": Color(0.82, 0.88, 0.40, 1.0), "ai_type": "chase" },
	"egt_blobulin": { "emoji": "⚪", "color": Color(0.90, 0.94, 0.88, 1.0), "ai_type": "chase" },
	"egt_pinhead": { "emoji": "💣", "color": Color(1.0, 0.58, 0.14, 1.0), "ai_type": "bomber" },
	"egt_nitra": { "emoji": "🧨", "color": Color(1.0, 0.42, 0.12, 1.0), "ai_type": "bomber" },
	"egt_bullat": { "emoji": "🟠", "color": Color(1.0, 0.70, 0.20, 1.0), "ai_type": "bomber" },
	"egt_gunsinger": { "emoji": "🎵", "color": Color(0.86, 0.52, 0.96, 1.0), "ai_type": "summoner" },
	# —— 第二批 21 只（2026-10-29）：`ai_type` 仍只是表现层标签，
	# 真正的行为由 `Enemy3D.PROFILES[kind].attack_style` 决定（图纸与运行时同源）——
	"egt_cardinal": { "emoji": "🟥", "color": Color(0.86, 0.30, 0.42, 1.0), "ai_type": "ranged" },
	"egt_hollowpoint": { "emoji": "🟪", "color": Color(0.66, 0.42, 0.92, 1.0), "ai_type": "ranged" },
	"egt_veteran_shotgun": { "emoji": "🟨", "color": Color(0.94, 0.72, 0.10, 1.0), "ai_type": "ranged" },
	"egt_king_bullat": { "emoji": "👑", "color": Color(0.62, 0.42, 0.78, 1.0), "ai_type": "ranged" },
	"egt_chancebulon": { "emoji": "🎲", "color": Color(0.86, 0.72, 0.30, 1.0), "ai_type": "chase" },
	"egt_bookllet": { "emoji": "📖", "color": Color(0.90, 0.88, 0.80, 1.0), "ai_type": "ranged" },
	"egt_blue_bookllet": { "emoji": "📘", "color": Color(0.44, 0.66, 0.98, 1.0), "ai_type": "ranged" },
	"egt_green_bookllet": { "emoji": "📗", "color": Color(0.52, 0.88, 0.48, 1.0), "ai_type": "ranged" },
	"egt_gunjurer": { "emoji": "🔯", "color": Color(0.72, 0.52, 1.0, 1.0), "ai_type": "ranged" },
	"egt_gigi": { "emoji": "🥚", "color": Color(0.96, 0.82, 0.42, 1.0), "ai_type": "ranged" },
	"egt_shotgat": { "emoji": "🟩", "color": Color(0.42, 0.78, 0.62, 1.0), "ai_type": "bomber" },
	"egt_grenat": { "emoji": "🟧", "color": Color(0.90, 0.34, 0.12, 1.0), "ai_type": "bomber" },
	"egt_spirat": { "emoji": "🌀", "color": Color(0.36, 0.86, 0.86, 1.0), "ai_type": "bomber" },
	"egt_keybullet_kin": { "emoji": "🔑", "color": Color(0.98, 0.84, 0.24, 1.0), "ai_type": "chase" },
	"egt_chance_kin": { "emoji": "🎰", "color": Color(0.40, 0.86, 0.90, 1.0), "ai_type": "chase" },
	"egt_confirmed": { "emoji": "🕯", "color": Color(0.56, 0.36, 0.72, 1.0), "ai_type": "ranged" },
	"egt_mimic": { "emoji": "🎁", "color": Color(0.70, 0.52, 0.26, 1.0), "ai_type": "ranged" },
	"egt_gun_fairy": { "emoji": "🧚", "color": Color(0.98, 0.90, 0.60, 1.0), "ai_type": "ranged" },
	"egt_gripmaster": { "emoji": "🖐", "color": Color(0.54, 0.48, 0.92, 1.0), "ai_type": "summoner" },
	"egt_gun_nut": { "emoji": "🗡", "color": Color(0.66, 0.50, 0.28, 1.0), "ai_type": "ranged" },
	"egt_chain_gunner": { "emoji": "⛓", "color": Color(0.62, 0.68, 0.80, 1.0), "ai_type": "ranged" },
}

## 精英词缀配置
const ELITE_MODIFIERS := {
	"巨大化": { "hp_mult": 2.0, "scale_mult": 1.5, "speed_mult": 0.8 },
	"分裂": { "on_death_spawn": 3, "spawn_type": "minion" },
	"反弹": { "reflect_chance": 0.3, "reflect_damage_mult": 0.5 },
	"寄生": { "on_death_attach_to": "nearest_enemy", "stat_mult": 1.3 },
	"抢枪": { "steal_weapon": true, "duration_sec": 10 },
	"吞弹": { "absorb_bullets": true, "convert_to_attack": true },
}

## 层级难度缩放
## 注意：floor参数是实际楼层（1-4），不是 floor_level 进度层级
## 第一关：教学难度，怪物弱，种类少
## 第二关：正式挑战开始，怪物变强，种类增加，体型明显增大
## 第三关及以上：硬核，怪物强，密度高
const FLOOR_SCALING := {
	1: { "hp_mult": 1.0, "damage_mult": 1.0, "loot_mult": 1.0 },
	2: { "hp_mult": 1.4, "damage_mult": 1.2, "loot_mult": 1.3 },  # 第二关：显著提升（hp 1.2→1.4, dmg 1.15→1.2）
	3: { "hp_mult": 1.5, "damage_mult": 1.3, "loot_mult": 1.5 },
	4: { "hp_mult": 1.8, "damage_mult": 1.5, "loot_mult": 1.8 },
	5: { "hp_mult": 2.2, "damage_mult": 1.8, "loot_mult": 2.2 },
}

## 强化怪升级的默认概率（`monster_rules.strong_variant.chance` 缺省时用）。
## 业主 2026-10-16 定「每只怪约 15% 是强化版」。
const DEFAULT_STRONG_VARIANT_CHANCE := 0.15

## —— 传送支线（子图）固定编成 ——
## 业主 2026-10-18 定：**子图每一间固定 5 只强化怪 + 2 只普通怪**，
## 不给额外掉落加成（要收益就把它们打死，走常规击杀掉落）。
##
## 为什么写死数量而不走公式：子图是可选的高风险房间，玩家进去之前应当能预期
## 「这一间有多硬」。数量随楼层/进度漂移，会让「5 + 2」这条口径变成一句空话。
const SECRET_BRANCH_STRONG_COUNT := 5
const SECRET_BRANCH_NORMAL_COUNT := 2
## 强化怪只从**已有正式变种**里取（`MonsterVariants.VARIANTS` 的三个 id）。
const SECRET_BRANCH_STRONG_KINDS := [
	"melee_chaser_strong",
	"fat_zombie03_strong",
	"ranged_caster_strong",
]
## 普通怪只取**有强化版的那三类**：同一种怪的两个档摆在一起，玩家一眼能看出差别
## （强化怪体型 ×1.5），不会把「蜂巢怪」误当成强化怪的同类。
const SECRET_BRANCH_NORMAL_KINDS := ["melee_chaser", "fat_zombie03", "ranged_caster"]

var _rng: RandomNumberGenerator
## 强化怪升级专用随机流。**必须与 `_rng` 分开**：`_rng` 被 boss / elite / 公式路径共用，
## 若把升级的掷骰混进去，既有固定种子的抽取结果会整体位移，破坏已验收的可复现性。
var _strong_rng: RandomNumberGenerator
var _theme_profile: Resource = null
## 关卡级怪物规则（`level_plan.json` 顶层 `monster_rules`）。空字典 = 未配置
## ⇒ 数值与 AI 全部走原常量，未配置的关卡行为逐字不变。唯一写入口是
## `set_level_rules`（由 `Dungeon3D._setup_run_modules` 在装配时调）。
var _level_rules: Dictionary = {}

func _init():
	_rng = RandomNumberGenerator.new()
	_rng.seed = Time.get_ticks_msec()
	_strong_rng = RandomNumberGenerator.new()
	_strong_rng.seed = _rng.seed

func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value
	# 从主种子派生（异或一个固定常量）而不是复用它：两条流由此互相独立，
	# 但「同一个 run_seed ⇒ 同一份强化怪分布」这条可复现性仍然成立。
	_strong_rng.seed = seed_value ^ 0x5D1C3B79


func set_theme_profile(profile: Resource) -> void:
	_theme_profile = profile


## 装载关卡级怪物规则。整段深拷贝，调用方后续改动不会渗回。
func set_level_rules(rules: Dictionary) -> void:
	_level_rules = rules.duplicate(true)


## 取某怪种的**关卡级绝对数值覆盖**（`monster_rules.stats.per_kind.<kind>`）。
##
## 覆盖的是**最终值**：`hp` 即最终 `max_hp`、`damage` 即最终接触伤害、
## `speed` 即最终米/秒。不走楼层缩放与主题倍率 —— 写 350 就是 350，
## 免得「改了没生效」还要反推比例。返回 `{}` = 本怪无覆盖。
func _stat_override(kind: String) -> Dictionary:
	var per_kind: Dictionary = (
		(_level_rules.get("stats", {}) as Dictionary).get("per_kind", {}) as Dictionary
	)
	if MonsterVariants.is_variant(kind):
		# 强化怪的数值**从原怪那一行实时派生**，绝不要求关卡再抄一份强化怪的数。
		# 于是把 `per_kind.melee_chaser.hp` 从 350 调成 400，强化怪自动变 800。
		return _derive_stat_override(MonsterVariants.base_of(kind), per_kind)
	var entry: Variant = per_kind.get(kind, null)
	if not (entry is Dictionary):
		return {}
	var src := entry as Dictionary
	var out: Dictionary = {}
	if src.has("hp"):
		out["override_max_hp"] = maxi(1, int(src["hp"]))
	if src.has("damage"):
		out["override_damage"] = maxi(0, int(src["damage"]))
	if src.has("speed"):
		out["override_speed"] = maxf(0.05, float(src["speed"]))
	return out


## 强化怪的关卡级绝对数值 = **原怪的绝对数值 × 变种倍率**。
##
## 速度不乘倍率：业主 2026-10-16 只要求生命 / 攻击 / 体型 / 自爆范围 / 弹道，
## 强化怪跑得和原怪一样快。
func _derive_stat_override(base_kind: String, per_kind: Dictionary) -> Dictionary:
	var entry: Variant = per_kind.get(base_kind, null)
	if not (entry is Dictionary):
		return {}
	var src := entry as Dictionary
	var out: Dictionary = {}
	if src.has("hp"):
		out["override_max_hp"] = maxi(1, int(round(
			float(src["hp"]) * MonsterVariants.multiplier(base_kind, "hp_mult")
		)))
	if src.has("damage"):
		out["override_damage"] = maxi(0, int(round(
			float(src["damage"]) * MonsterVariants.multiplier(base_kind, "damage_mult")
		)))
	if src.has("speed"):
		out["override_speed"] = maxf(0.05, float(src["speed"]))
	return out


## 把关卡级 AI 手感参数塞进怪物配置（`monster_rules.ai` 原样带上）。
## 缺省（无本段或本段为空）不写这个键 ⇒ `Enemy3D` / `MonsterAIManager`
## 一律回退各自常量，塔楼与其余关卡不受影响。
func _ai_overrides() -> Dictionary:
	var ai: Dictionary = _level_rules.get("ai", {}) as Dictionary
	if ai.is_empty():
		return {}
	return {"monster_ai": ai.duplicate(true)}


## 强化怪升级概率（读 `monster_rules.strong_variant`）。
##
## 返回 `0.0` = 本关不启用强化怪。此时 `_roll_strong_kind` **一次随机数都不掷**，
## 所以未配置本段的关卡，随机流与改动前逐字一致（项目的「未配置 ⇒ 行为不变」铁律）。
func _strong_variant_chance() -> float:
	var section: Variant = _level_rules.get("strong_variant", null)
	if not (section is Dictionary):
		return 0.0
	var cfg := section as Dictionary
	if not bool(cfg.get("enabled", true)):
		return 0.0
	return clampf(float(cfg.get("chance", DEFAULT_STRONG_VARIANT_CHANCE)), 0.0, 1.0)


## 按关卡概率把普通怪升级成它的**强化版**（`MonsterVariants`）。
##
## 实现刻意放在 `_generate_basic_enemy` 的出口，而不是各个刷怪池里：
## 远征01 由**刷怪盒**驱动（`spawn_placements` 优先级最高），做在池子里根本不会生效；
## 做在出口上，则刷怪盒 / 设计源 / 房型公式三条编成来源自动全部覆盖。
##
## 未配置 / 该怪没有强化版 / 没抽中 —— 三种情况都原样返回 `kind`。
func _roll_strong_kind(kind: String) -> String:
	var chance := _strong_variant_chance()
	if chance <= 0.0:
		return kind
	var variant_id := MonsterVariants.variant_of(kind)
	if variant_id.is_empty():
		return kind
	if _strong_rng.randf() >= chance:
		return kind
	return variant_id


## 死亡自爆规格（`monster_rules.death_explosion.<kind>`）。
## 返回 `{}` = 本怪不自爆（缺省）。非法/零伤害一律当「不自爆」处理，绝不产出半个规格。
##
## 伤害是**绝对固定值**，不走 `contact_damage` —— 那条随楼层缩放与主题倍率会漂，
## 自爆要的是策划能一眼对上的数（业主 2026-10-14：胖子僵尸 180）。
func _death_explosion_for(kind: String) -> Dictionary:
	var table: Dictionary = _level_rules.get("death_explosion", {}) as Dictionary
	var radius_mult := 1.0
	var entry: Variant = table.get(kind, null)
	if not (entry is Dictionary):
		# 强化怪不自带一行 ⇒ 从原怪那一行派生，只把**半径**乘变种倍率。
		# 原怪本身不自爆时 entry 仍不是字典 ⇒ 下面直接返回空：
		# 变种不会凭空长出一场爆炸。
		var base_kind := MonsterVariants.base_of(kind)
		if base_kind.is_empty():
			return {}
		entry = table.get(base_kind, null)
		if not (entry is Dictionary):
			return {}
		radius_mult = MonsterVariants.multiplier(base_kind, "death_explosion_radius_mult")
	var src := entry as Dictionary
	if not bool(src.get("enabled", true)):
		return {}
	var damage := int(src.get("damage", 0))
	if damage <= 0:
		return {}
	var spec := {
		"damage": damage,
		"radius_m": maxf(0.5, float(src.get("radius_m", 5.0)) * radius_mult),
		"sfx_radius_m": maxf(0.0, float(src.get("sfx_radius_m", 20.0))),
	}
	# ⚠ 2026-10-16 修：此处原先**丢弃了 zone 段**，而 `Enemy3D._spawn_ground_blast_zone()`
	# 正是靠它才会生成地面持续伤害场 ⇒ 关卡配置里写的 zone 从来没有生效过（静默失效）。
	# 现在原样透传；`zone.radius_m` 缺省仍沿用爆炸半径，也就是已乘过倍率的那个值。
	var zone: Variant = src.get("zone", null)
	if zone is Dictionary and not (zone as Dictionary).is_empty():
		spec["zone"] = (zone as Dictionary).duplicate(true)
	return spec


## 把「关卡级死亡自爆」挂进怪物配置。无配置不写键 ⇒ 塔楼等关卡照旧不自爆。
func _death_explosion_overrides(kind: String) -> Dictionary:
	var spec := _death_explosion_for(kind)
	if spec.is_empty():
		return {}
	return {"death_explosion": spec}

## 根据配置生成怪物列表
func generate_enemies(config: Dictionary) -> Array[Dictionary]:
	var enemies: Array[Dictionary] = []
	var enemy_type: String = config.get("type", "random")
	var floor_level: int = config.get("floor_level", RoomData.FloorLevel.SHALLOW)
	var floor: int = config.get("floor", 1)
	
	match enemy_type:
		"fat_zombie03":
			for _index in range(maxi(1, int(config.get("count", 1)))):
				enemies.append(_generate_basic_enemy(enemy_type, floor, floor_level))
		"random":
			enemies = _generate_random_enemies(floor, floor_level)
		"elite":
			var elite := _generate_elite(floor, floor_level, config)
			if not elite.is_empty():
				enemies.append(elite)
		"boss":
			var boss := _generate_boss(floor, floor_level, config)
			if not boss.is_empty():
				enemies.append(boss)
		"minion":
			enemies = _generate_minion_pack(floor, floor_level)
		"guard":
			enemies.append(_generate_guard(floor, floor_level))
		"ambush":
			enemies = _generate_ambush_pack(floor, floor_level, int(config.get("count", 2)))
		_:
			enemies.append(_generate_basic_enemy(_get_theme_fallback_enemy(), floor, floor_level))
	
	return enemies

## 触发盒路径：按**明确的怪种**生成一只（`docs/v0.1/design/触发器刷怪设计.md` §3.1）。
##
## 为什么不能用 `generate_enemies`：它走 `match enemy_type`，普通怪种（melee_chaser 等）
## 落到 `_:` 分支 → 生成的是**主题兜底怪**而不是点名的那个种类，盒子写什么都会失效。
## 本函数与 `build_waves_from_plan` 同口径：普通怪直取 `_generate_basic_enemy`，
## `elite` / `boss` 走各自装配端（它们是**身份指派**，不是编成）。
## 未知或非法 type 返回 {}（调用方跳过，绝不退化成别的东西）。
func generate_box_enemy(type_id: String, floor: int, floor_level: int, extra: Dictionary = {}) -> Dictionary:
	if type_id == "elite":
		return _generate_elite(floor, floor_level, extra)
	if type_id == "boss":
		return _generate_boss(floor, floor_level, extra)
	if is_authorable_enemy_type(type_id):
		return _generate_basic_enemy(type_id, floor, floor_level)
	return {}


## 死亡分裂的子代（远征03 布洛布三阶）。
##
## 与 `generate_box_enemy` 的唯一差别是 **`allow_strong = false`**：
## 分裂出来的子代必须**逐字是配置里写的那一只**。走默认出口的话，每只子代有
## `monster_rules.strong_variant.chance`（缺省 15%）的概率被升级成强化怪 ——
## 玩家会看到「打碎一个布洛布，掉出来两只体型 ×1.5 的强化变态」，
## 而原作的分裂链是**严格逐级递减**的（Blobulon → Blobuloid → Blobulin）。
## 关掉升级不是优化，是这条行为能否成立的前提。
func generate_split_child(child_kind: String, floor: int, floor_level: int) -> Dictionary:
	if not is_authorable_enemy_type(child_kind):
		return {}
	return _generate_basic_enemy(child_kind, floor, floor_level, false)

## 子图房间编成：**固定 5 只强化怪 + 2 只普通怪**，顺序「先强化、后普通」。
##
## `allow_strong = false` 是这条口径的关键：`_generate_basic_enemy` 的默认出口会按
## 关卡概率（`monster_rules.strong_variant`）把普通怪升级成强化怪。不关掉它，
## 那 2 只「普通怪」各有 15% 概率变成强化怪 —— 玩家数出来就是 6 强化 + 1 普通，
## 「每间 5 强化 + 2 普通」的承诺当场破功。强化怪一侧同样显式关掉：虽然
## `_roll_strong_kind` 对已是变种的 id 本来就原样透传，但关掉能让「这里是编程式
## 指定」写在调用点上，且不消耗强化怪的随机流。
##
## `seed_value` 只决定「三类强化怪从哪一类开始轮转」（5 只恒为 2/2/1 分布），
## 不改变数量、种类集合与档位 —— 同一间房重复调用得到同一份编成。
func build_secret_branch_encounter(
	floor: int, floor_level: int, seed_value: int
) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[Dictionary] = []
	var rotation := rng.randi_range(0, SECRET_BRANCH_STRONG_KINDS.size() - 1)
	for index in range(SECRET_BRANCH_STRONG_COUNT):
		var kind := str(
			SECRET_BRANCH_STRONG_KINDS[(rotation + index) % SECRET_BRANCH_STRONG_KINDS.size()]
		)
		out.append(_generate_basic_enemy(kind, floor, floor_level, false))
	for index in range(SECRET_BRANCH_NORMAL_COUNT):
		var kind := str(
			SECRET_BRANCH_NORMAL_KINDS[(rotation + index) % SECRET_BRANCH_NORMAL_KINDS.size()]
		)
		out.append(_generate_basic_enemy(kind, floor, floor_level, false))
	return out


## 设计源覆盖：按关卡设计源给定的波次计划生成敌人。
## 外层每项 = 一波（**波次数钉死**），每波有两种写法，**互斥**：
##   ① 逐值固定：`{"monsters": [{"type": "melee_chaser", "count": 2}]}`
##   ② 半钉死：  `{"pool": ["melee_chaser","ambusher"], "kinds": {"min":1,"max":2},
##                "count": {"min":2,"max":4}}`
##      —— 从 pool 抽 `kinds` 种、总数量落 `count` 区间（每局按 `variant_seed` 抽）。
##
## 只覆盖**编成**（波次数 / 每波数量 / 怪物种类），不覆盖**数值**：每只怪仍走
## `_generate_basic_enemy`，因此主题倍率与楼层缩放照常生效，避免设计源与全局数值
## 出现两套真源。返回 Array[Array[Dictionary]]（每波一个配置数组）；
## 计划缺失或非法时返回空数组，由调用方回退全局公式 —— 绝不产出半截波次。
func build_waves_from_plan(
	plan: Dictionary, floor: int, floor_level: int, variant_seed: int = 0
) -> Array:
	var waves: Array = []
	if plan.is_empty():
		return waves
	var raw_waves: Variant = plan.get("waves", [])
	if not (raw_waves is Array) or (raw_waves as Array).is_empty():
		return waves
	# 「半钉死」波次的抽取源。**必须是本函数私有的 rng**：本实例的 `_rng` 被
	# boss / elite / 公式路径共用，若在此消耗，抽取结果会依赖「谁先调用」而无法复现。
	# 由调用方传入 `variant_seed`（Dungeon3D 传 run_seed + 房 id 派生）⇒ 同局同房恒定、
	# 不同局/不同房不同。固定写法（monsters）不使用它，故老关卡行为逐字不变。
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	for wave_value in (raw_waves as Array):
		if not (wave_value is Dictionary):
			return []
		var wave := wave_value as Dictionary
		var composition: Array = []
		if wave.has("pool"):
			composition = _roll_pool_wave(wave, rng)
			if composition.is_empty():
				return []
		else:
			var raw_monsters: Variant = wave.get("monsters", [])
			if not (raw_monsters is Array) or (raw_monsters as Array).is_empty():
				return []
			for monster_value in (raw_monsters as Array):
				if not (monster_value is Dictionary):
					return []
				var monster := monster_value as Dictionary
				var type_id := str(monster.get("type", ""))
				var count := int(monster.get("count", 0))
				if not is_authorable_enemy_type(type_id) or count <= 0:
					return []
				composition.append({ "type": type_id, "count": count })
		var batch: Array[Dictionary] = []
		for entry_value in composition:
			var entry := entry_value as Dictionary
			var entry_type := str(entry.get("type", ""))
			for _index in range(int(entry.get("count", 0))):
				batch.append(_generate_basic_enemy(entry_type, floor, floor_level))
		if batch.is_empty():
			return []
		waves.append(batch)
	return waves


## 「半钉死」波次：从 `pool` 里**无重复**抽 `kinds` 种怪，总数量落在 `count` 区间内。
## 波次数由 `waves` 数组长度**钉死**；种类与数量每局按 rng 抽（同 rng 恒定）。
## 返回 `Array[{type, count}]`；输入非法返回空数组（调用方按契约整份丢弃）。
##
## 分配口径：总数量尽量**均分**给抽中的种类，余数给靠前的种类（每种至少 1 只）。
## `count.min` 若不小于抽中的种类数，均分必然成立；校验器另在静态层要求
## `count.min >= kinds.max`，本处的 `maxi` 只是运行时的最后一道兜底。
func _roll_pool_wave(wave: Dictionary, rng: RandomNumberGenerator) -> Array:
	var raw_pool: Variant = wave.get("pool", [])
	if not (raw_pool is Array) or (raw_pool as Array).is_empty():
		return []
	var pool: Array[String] = []
	for type_value in (raw_pool as Array):
		var type_id := str(type_value)
		if not is_authorable_enemy_type(type_id):
			return []
		pool.append(type_id)
	var kinds_min := pool.size()
	var kinds_max := pool.size()
	var raw_kinds: Variant = wave.get("kinds", {})
	if raw_kinds is Dictionary:
		kinds_min = int((raw_kinds as Dictionary).get("min", pool.size()))
		kinds_max = int((raw_kinds as Dictionary).get("max", pool.size()))
	kinds_min = clampi(kinds_min, 1, pool.size())
	kinds_max = clampi(kinds_max, kinds_min, pool.size())
	var raw_count: Variant = wave.get("count", null)
	if not (raw_count is Dictionary):
		return []
	var count_data := raw_count as Dictionary
	var count_min := int(count_data.get("min", 0))
	var count_max := int(count_data.get("max", 0))
	if count_min <= 0 or count_max < count_min:
		return []
	# 抽种类：先洗牌 pool，再取前 kind_count 个（等价于无重复抽样）。
	var shuffled := pool.duplicate() as Array[String]
	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = held
	var kind_count := rng.randi_range(kinds_min, kinds_max)
	var total := maxi(rng.randi_range(count_min, count_max), kind_count)
	var base := int(total / kind_count)
	var remainder := total % kind_count
	var out: Array = []
	for index in range(kind_count):
		out.append({
			"type": shuffled[index],
			"count": base + (1 if index < remainder else 0),
		})
	return out


## 该怪物种类能否由设计源直接指定。Boss 不在内：Boss 房有自己的出场/结算路径，
## 走本通道会以普通外壳出场，绕过 Boss 逻辑，故设计源禁用。
## static：校验器需要在不构造实例的前提下复用同一判据（单一实现，禁止复刻）。
static func is_authorable_enemy_type(type_id: String) -> bool:
	return BASE_ENEMY_TYPES.has(type_id) and type_id != "boss"


## 生成随机敌人
func _generate_random_enemies(floor: int, floor_level: int) -> Array[Dictionary]:	# 怪物数量随楼层增加：每房 baseline 3-5 只（floor=1 -> 3, floor=2 -> 4, floor=4 -> 6）
	var count: int = 2 + floor
	var enemies: Array[Dictionary] = []
	
	var available_types: Array = _get_available_types_for_level(floor_level, floor)
	
	for i in range(count):
		var enemy_type: String = available_types[_rng.randi() % available_types.size()]
		enemies.append(_generate_basic_enemy(enemy_type, floor, floor_level))
	
	return enemies

## 获取指定层级可用的敌人类型（按楼层差异化）
## floor_level: RoomData.FloorLevel 进度层级（SHALLOW/MEDIUM/DEEP/ABYSS）
## floor: 实际楼层数字（1-4），影响同进度层级下的怪物池大小
func _get_available_types_for_level(floor_level: int, floor: int = 1) -> Array[String]:
	# 关卡级池子（`level_plan.json` 的 `monster_rules.enemy_pool`）。
	#
	# ⚠ **必须在主题池之前**。第一版写在主题池之后，结果远征03 里
	# `_theme_profile` 自己配了老三种（melee/ranged/exploder）⇒ 函数在主题那一步就
	# `return` 了，关卡池**一次都没被读到**。探针实测：8 只怪全是老三种、`egt_` 0 只，
	# 而 `monster_rules` 明明装载成功（pool=12）。这类"配了没生效"最难查，故记在此。
	#
	# 语义上也是关卡优先：主题是「同一套怪换皮」（视觉层），关卡池是
	# 「这一关就这些怪」（内容层）。内容层覆盖视觉层，与 `stats.per_kind` 绝对覆盖同向。
	# 远征01/02 未写本段 ⇒ 这里直接跳过，行为逐字不变。
	var level_pool: Array = _level_rules.get("enemy_pool", [])
	if not level_pool.is_empty():
		var level_result: Array[String] = []
		for enemy_type in level_pool:
			if is_authorable_enemy_type(str(enemy_type)):
				level_result.append(str(enemy_type))
		if not level_result.is_empty():
			return level_result
	if _theme_profile != null:
		var themed_pool: Array = _theme_profile.get_enemy_rule("enemy_pool", [])
		if not themed_pool.is_empty():
			var result: Array[String] = []
			for enemy_type in themed_pool:
				result.append(str(enemy_type))
			return result
	match floor_level:
		RoomData.FloorLevel.SHALLOW:
			# 第一层：3种基础怪物（新手熟悉）
			if floor <= 1:
				return ["melee_chaser", "ranged_caster", "exploder"]
			# 第二层及以上：SHALLOW也开放6种怪物池，丰富度提升
			else:
				return ["melee_chaser", "ranged_caster", "summoner", "fat_zombie03", "exploder", "ambusher"]
		RoomData.FloorLevel.MEDIUM:
			# 全部6种
			return ["melee_chaser", "ranged_caster", "summoner", "fat_zombie03", "exploder", "ambusher"]
		RoomData.FloorLevel.DEEP:
			# 全部6种，且怪物密度更高（波次更多）
			return ["melee_chaser", "ranged_caster", "summoner", "fat_zombie03", "exploder", "ambusher"]
		RoomData.FloorLevel.ABYSS:
			# 仅精英类型
			return ["summoner", "fat_zombie03", "ambusher"]
	return ["melee_chaser"]

## 生成基础敌人。
##
## `allow_strong = false` 供**精英**使用：精英在 `_generate_elite` 里还要叠自己的
## 「巨大化」等词缀，再被升级成强化怪会变成双重强化（血量乘两遍），
## 且精英的血条/名册契约都按原种走。精英是**身份指派**，不该被随机升级改写身份。
func _generate_basic_enemy(
	enemy_type: String, floor: int, floor_level: int, allow_strong: bool = true
) -> Dictionary:
	# 强化怪升级走**出口**而不是池子：刷怪盒 / 设计源 / 房型公式三条编成来源
	# 全部汇到这里，做在这里才不会漏掉刷怪盒（远征01 正是盒子驱动）。
	var resolved_type := _roll_strong_kind(enemy_type) if allow_strong else enemy_type
	var base: Dictionary = BASE_ENEMY_TYPES.get(resolved_type, BASE_ENEMY_TYPES["melee_chaser"])
	var scaling: Dictionary = FLOOR_SCALING.get(floor, FLOOR_SCALING[1])
	var presentation: Dictionary = ENEMY_PRESENTATION.get(resolved_type, ENEMY_PRESENTATION["melee_chaser"])
	
	var hp: float = base["hp_base"] * scaling["hp_mult"]
	var damage: float = base["damage_base"] * scaling["damage_mult"]
	var speed: float = base["speed"]
	if _theme_profile != null:
		hp *= float(_theme_profile.get_enemy_rule("hp_multiplier", 1.0))
		damage *= float(_theme_profile.get_enemy_rule("damage_multiplier", 1.0))
		speed *= float(_theme_profile.get_enemy_rule("speed_multiplier", 1.0))
	
	var result := {
		"enemy_type": resolved_type,
		"name": base["name"],
		"hp": int(hp),
		"max_hp": int(hp),
		"damage": int(damage),
		"speed": speed,
		"emoji": presentation.get("emoji", "🐗"),
		"color": presentation.get("color", Color(1.0, 0.25, 0.25, 1.0)),
		"ai_type": presentation.get("ai_type", "chase"),
		"floor": floor,
		"loot_table": _get_loot_table(floor_level),
		"xp_value": 10 + floor * 5
	}
	if _theme_profile != null:
		var prefix := str(_theme_profile.get_enemy_rule("name_prefix", ""))
		if not prefix.is_empty():
			result["name"] = "%s%s" % [prefix, result["name"]]
		result["theme_id"] = _theme_profile.theme_id
	# 关卡级覆盖放最后：绝对数值盖掉楼层缩放与主题倍率的乘积，AI 参数随配置下发。
	# 强化怪在这三处都走「从原怪派生」，所以策划只需要维护原怪那一行。
	result.merge(_stat_override(resolved_type), true)
	result.merge(_ai_overrides(), true)
	result.merge(_death_explosion_overrides(resolved_type), true)
	return result

## 生成精英敌人
func _generate_elite(floor: int, floor_level: int, request: Dictionary = {}) -> Dictionary:
	var encounter_id := str(request.get(
		"encounter_id", "legacy:%d:%d:%d" % [_rng.seed, floor, _rng.randi()]
	))
	var elite_snapshot: Dictionary = {}
	if EliteRosterService != null:
		elite_snapshot = EliteRosterService.select_and_reserve(
			int(request.get("seed", _rng.seed)),
			int(request.get("floor_number", floor)),
			encounter_id
		)
	if elite_snapshot.is_empty() or bool(elite_snapshot.get("success", true)) == false:
		return {}
	var base_type := str(elite_snapshot.get(
		"base_enemy_id", _get_theme_fallback_enemy("fat_zombie03")
	))
	# 无名王冠复用Boss轻量外观，但仍走精英结算而不是Boss路线解锁。
	# 精英禁用强化升级：精英是身份指派，且下面还要叠「巨大化」等词缀，
	# 再升级一次会变成双重强化（血量乘两遍）。
	var base: Dictionary = _generate_basic_enemy(base_type, floor, floor_level, false)
	base["is_elite"] = true
	base["hp"] = int(base["hp"] * 1.5)
	base["max_hp"] = base["hp"]
	base["damage"] = int(base["damage"] * 1.3)
	
	# 随机词缀
	var modifier_keys: Array = ELITE_MODIFIERS.keys()
	var selected_modifier: String = modifier_keys[_rng.randi() % modifier_keys.size()]
	var requested_modifier := str(elite_snapshot.get("modifier_id", ""))
	for localized_name in modifier_keys:
		if _map_modifier_to_english(str(localized_name)) == requested_modifier:
			selected_modifier = str(localized_name)
			break
	var mod_data: Dictionary = ELITE_MODIFIERS[selected_modifier]
	
	base["modifier"] = selected_modifier
	base["modifier_data"] = mod_data
	# 映射中文词缀到英文ID，供 EliteActiveSkillComponent.inject_elite_skills() 正确路由技能
	base["modifier_id_en"] = _map_modifier_to_english(selected_modifier)
	base["name"] = selected_modifier + base["name"]
	base["xp_value"] = 50 + floor * 20
	base["bounty_tier"] = floor
	# 精英怪使用专用掉落表（elite_floor_1 / elite_floor_2）
	# 这样 ItemRegistry 中配置的 elite_floor_* 权重才能生效
	base["loot_table"] = "elite_floor_1" if floor <= 2 else "elite_floor_2"
	if EliteRosterService != null and not elite_snapshot.is_empty():
		base = EliteRosterService.apply_archive_to_enemy_config(base, elite_snapshot)
	# 精英从基础怪派生，于是已经带着基础怪的关卡级覆盖；但覆盖的是**最终值**，
	# 而精英在 `Enemy3D` 里还会被绝对赋值 ⇒ 必须在此按精英倍率重算一遍，
	# 否则「1.5 倍血量」会被覆盖吃掉。
	var stat_override := _stat_override(base_type)
	if stat_override.has("override_max_hp"):
		stat_override["override_max_hp"] = maxi(
			1, int(round(float(stat_override["override_max_hp"]) * 1.5))
		)
	if stat_override.has("override_damage"):
		stat_override["override_damage"] = maxi(
			0, int(round(float(stat_override["override_damage"]) * 1.3))
		)
	base.merge(stat_override, true)
	base.merge(_ai_overrides(), true)
	base.merge(_death_explosion_overrides(base_type), true)
	return base

## 生成Boss敌人。
## 返回 **空字典 = 本房不出 Boss**（名册里没有可用内容，或设计源写了不存在的 ID）。
## 调用方（`generate_enemies` 的 "boss" 分支 / `Dungeon3D._spawn_room_enemies`）
## 必须把空字典当作「合法空房」处理，不得当成生成失败。
func _generate_boss(floor: int, floor_level: int, request: Dictionary = {}) -> Dictionary:
	var scaling: Dictionary = FLOOR_SCALING.get(floor, FLOOR_SCALING[1])
	var hp: float = 200.0 * scaling["hp_mult"]
	
	# 第二关Boss体型按策划案要求为1.5x（v0.1规范）
	# 第三关1.6，第四关1.75，后续按+0.15递增
	var boss_scale: float = 1.0
	if floor >= 2:
		boss_scale = 1.5 + (floor - 2) * 0.15  # floor=2→1.5, floor=3→1.65, floor=4→1.8
	
	var result := {
		"enemy_type": "boss",
		"name": "Boss 第%d层" % [floor],
		"hp": int(hp * boss_scale),  # boss_scale 同步放大 HP（与 BossActor._apply_shape_scale 联动）
		"max_hp": int(hp * boss_scale),
		"damage": int(20.0 * scaling["damage_mult"]),
		"speed": 60,
		"emoji": ENEMY_PRESENTATION["boss"]["emoji"],
		"color": ENEMY_PRESENTATION["boss"]["color"],
		"scale": 1.5 * boss_scale,  # 视觉效果同步放大（与碰撞体 boss_scale 成比例）
		"boss_scale": boss_scale,   # BossActor 读取此字段并应用到碰撞体形状大小
		"ai_type": ENEMY_PRESENTATION["boss"]["ai_type"],
		"floor": floor,
		"is_boss": true,
		"phases": 2 + floor / 3,
		"loot_table": "boss_floor_%d" % [floor],
		"xp_value": 200 + floor * 50,
		"bounty_tier": floor + 1
	}
	if _theme_profile != null:
		result["hp"] = int(result["hp"] * float(_theme_profile.get_enemy_rule("hp_multiplier", 1.0)))
		result["max_hp"] = result["hp"]
		result["damage"] = int(result["damage"] * float(
			_theme_profile.get_enemy_rule("damage_multiplier", 1.0)
		))
		result["speed"] = float(result["speed"]) * float(
			_theme_profile.get_enemy_rule("speed_multiplier", 1.0)
		)
		result["name"] = str(_theme_profile.get_enemy_rule(
			"boss_name", "%s首领" % _theme_profile.display_name
		))
		result["theme_id"] = _theme_profile.theme_id
	# Boss 身份的唯一解析口径见 BossContentCatalog.resolve_profile：
	# 设计源指定的 boss_content_id 优先，其次按层指派（95/90/85）。
	# 名册条目同时决定目标名、正式模型、竞技场与阶段技能袋 —— 设计源只负责「指定哪一个」。
	var floor_number := int(request.get("floor_number", 95))
	var boss_profile := BossContentCatalog.resolve_profile(
		str(request.get("boss_content_id", "")), floor_number
	)
	if boss_profile.is_empty():
		return {}
	result["floor_number"] = int(boss_profile.get("floor_number", floor_number))
	result["boss_content_id"] = str(boss_profile["boss_content_id"])
	result["name"] = str(boss_profile["display_name"])
	result["presentation_asset_id"] = str(boss_profile["presentation_asset_id"])
	result["presentation_scene"] = str(boss_profile["presentation_scene"])
	result["arena_asset_id"] = str(boss_profile["arena_asset_id"])
	result["arena_scene"] = str(boss_profile["arena_scene"])
	result["boss_accent"] = boss_profile.get("accent", Color(1.0, 0.2, 0.035))
	result["boss_phase_skill_bags"] = (boss_profile["phase_skill_bags"] as Dictionary).duplicate(true)
	if str(boss_profile["boss_content_id"]) == "boss_monitor002":
		# Fixed monitor encounter baseline, independent of obsolete tower depth multipliers.
		result.merge({"hp":200,"max_hp":200,"damage":20,"speed":123.84,"boss_scale":1.0},true)
	# 关卡级覆盖必须放**最后**：盖掉上面那条显示器Boss 身份基线，写 32000 就是 32000。
	result.merge(_stat_override("boss"), true)
	result.merge(_ai_overrides(), true)
	result.merge(_death_explosion_overrides("boss"), true)
	return result

## 生成小怪群
func _generate_minion_pack(floor: int, floor_level: int) -> Array[Dictionary]:
	var count: int = 3 + floor
	var minions: Array[Dictionary] = []
	
	for i in range(count):
		var minion := _generate_basic_enemy(_get_theme_fallback_enemy("exploder"), floor, floor_level)
		minion["hp"] = int(minion["hp"] * 0.5)
		minion["max_hp"] = minion["hp"]
		minions.append(minion)
	
	return minions

## 生成守卫
func _generate_guard(floor: int, floor_level: int) -> Dictionary:
	var guard := _generate_basic_enemy(_get_theme_fallback_enemy("fat_zombie03"), floor, floor_level)
	guard["name"] = "商人护卫"
	guard["is_guard"] = true
	guard["xp_value"] = 15 + floor * 5
	return guard


func _generate_ambush_pack(floor: int, floor_level: int, count: int) -> Array[Dictionary]:
	var enemies: Array[Dictionary] = []
	var pool := _get_available_types_for_level(floor_level, floor)
	for i in range(maxi(1, count)):
		var enemy_type := pool[_rng.randi() % pool.size()]
		enemies.append(_generate_basic_enemy(enemy_type, floor, floor_level))
	return enemies


func _get_theme_fallback_enemy(default_enemy: String = "melee_chaser") -> String:
	if _theme_profile == null:
		return default_enemy
	var pool: Array = _theme_profile.get_enemy_rule("enemy_pool", [])
	if pool.is_empty():
		return default_enemy
	return str(pool[0])

## 获取掉落表名称
func _get_loot_table(floor_level: int) -> String:
	return get_loot_table_for_level(floor_level)


## 楼层深度 → 掉落池。唯一口径：`drop_spec_for` 与旧 `loot_table` 字段共用本函数，
## 不得在别处再写一份 match（那会让两处选池悄悄漂移）。
static func get_loot_table_for_level(floor_level: int) -> String:
	match floor_level:
		RoomData.FloorLevel.SHALLOW: return "loot_floor_1_2"
		RoomData.FloorLevel.MEDIUM: return "loot_floor_3_4"
		RoomData.FloorLevel.DEEP: return "loot_floor_5"
		RoomData.FloorLevel.ABYSS: return "loot_abyss"
	return "loot_common"


# ---------------------------------------------------------------------------
# 怪物表「掉落/进度」列的结构化投影（2026-09-22，REWARD-SERVICE 契约）
# ---------------------------------------------------------------------------
#
# 现状口径：该列在物品/怪物表里仍是自然语言，运行时散在 LootModule 的 26% / 34% / 金币公式里。
# 本段把它**逐值**投影成结构化规格（RewardSpec），供 RewardService 解析。
# **过渡期双写**：旧 `loot_table` 字段与旧 LootModule 分支保留不动（04 §22.11 第 2 步），
# 第 3 步切消费点、第 4 步删旧路径。数值逐值保持，不得在切换过程中改动。

## 普通怪：出 1 件非货币物品的概率。
const DROP_ITEM_CHANCE_NORMAL := 0.26
## 普通怪：备弹概率与数量区间。
## 【2026-09-27 数值调整】普通怪备弹由 3–8 上调为 30–50（主人指定）。概率 0.34 不变；
## 精英 / Boss 的 8–16 是另一组常量，不在本次调整范围内。远征01已配置怪的实际发数走
## `monster_drop_table`（作者表 CSV），本次两处同步改动，避免同关内出现两套备弹量。
const DROP_AMMO_CHANCE_NORMAL := 0.34
const DROP_AMMO_MIN_NORMAL := 30
const DROP_AMMO_MAX_NORMAL := 50
## 精英 / Boss：稳定单件 + 满额备弹。
const DROP_AMMO_MIN_ELITE := 8
const DROP_AMMO_MAX_ELITE := 16
## 金币产量：`round(base + per_floor × floor)`。精英/Boss 的附加金币在现有实现里是**总额**
## （Dungeon3D 见到已有货币就不再补基础金币），故此处直接给总额，不叠加。
const DROP_CURRENCY_BASE_NORMAL := 2
const DROP_CURRENCY_PER_FLOOR_NORMAL := 1
const DROP_CURRENCY_BASE_ELITE := 50
const DROP_CURRENCY_BASE_BOSS := 200
const DROP_CURRENCY_PER_FLOOR_ELITE_BOSS := 20

## 备弹物品 ID。与旧 LootModule 分支使用同一个物品，不得改成第二个 ID。
const DROP_AMMO_ITEM_ID := "item_ammo_pack"

const TIER_NORMAL := "normal"
const TIER_ELITE := "elite"
const TIER_BOSS := "boss"

## 强化怪出枪概率（业主 2026-10-18：「强化怪 20-30% 概率掉落」）。
## 取区间中值 25%：低于 20% 会让「打强化怪有枪」这件事形不成预期，
## 高于 30% 则强化怪（15% 出现率）的枪产能会超过 Boss。
const STRONG_VARIANT_WEAPON_CHANCE := 0.25
## Boss 第 2 把枪的概率。业主口径「固定 1-2 把」⇒ 第 1 把必出、第 2 把 50%，
## 期望 1.5 把，落在 [1, 2] 闭区间内。
const BOSS_SECOND_WEAPON_CHANCE := 0.5
## Boss 非枪掉落件数（蓝图 / 模块 / 配件 / 背包 / 电池 / 信标）。
## 总件数 = 枪 1-2 + 其它 3 + 弹药 1 = **恒为 5-6 件**（业主 2026-10-18）。
##
## 这里能固定成 3 件，靠的是条目级 `merge_same_item=false`：
## 池内抽签是有放回的，同 id 重复若按旧语义「覆盖成一件」，实测总量会散到 3-7 件。
## 关掉合并后，抽到同名物品就是两件独立实物（Boss 的蓝图/模块本来就该给多份）。
const BOSS_OTHER_DROPS := 3


## 取某只怪在当前档位/层深下的结构化掉落规格（等价于怪物表该行的 `drop` 列）。
##
## 返回一份完整的 RewardSpec，可直接交给 `RewardService.resolve()`。
## `tier` 取 normal / elite / boss；`boss` 时按 `floor` 取 `boss_floor_%d` 池名
## （该名若未登记，RewardService 会**拒绝并报 UNKNOWN_POOL**，不静默返回空）。
static func drop_spec_for(
	monster_id: String, tier: String = TIER_NORMAL, floor_level: int = 0, floor: int = 1
) -> Dictionary:
	if not BASE_ENEMY_TYPES.has(monster_id):
		return {}
	var safe_floor := maxi(1, floor)
	var resolved_tier := tier
	if monster_id == "boss":
		resolved_tier = TIER_BOSS

	var pool_id := ""
	var item_chance := 0.0
	var ammo_chance := 0.0
	var ammo_min := 0
	var ammo_max := 0
	var currency_base := 0
	var currency_per_floor := 0

	match resolved_tier:
		TIER_BOSS:
			pool_id = "boss_floor_%d" % [safe_floor]
			item_chance = 1.0
			ammo_chance = 1.0
			ammo_min = DROP_AMMO_MIN_ELITE
			ammo_max = DROP_AMMO_MAX_ELITE
			currency_base = DROP_CURRENCY_BASE_BOSS
			currency_per_floor = DROP_CURRENCY_PER_FLOOR_ELITE_BOSS
		TIER_ELITE:
			pool_id = "elite_floor_1" if safe_floor <= 2 else "elite_floor_2"
			item_chance = 1.0
			ammo_chance = 1.0
			ammo_min = DROP_AMMO_MIN_ELITE
			ammo_max = DROP_AMMO_MAX_ELITE
			currency_base = DROP_CURRENCY_BASE_ELITE
			currency_per_floor = DROP_CURRENCY_PER_FLOOR_ELITE_BOSS
		_:
			pool_id = get_loot_table_for_level(floor_level)
			item_chance = DROP_ITEM_CHANCE_NORMAL
			ammo_chance = DROP_AMMO_CHANCE_NORMAL
			ammo_min = DROP_AMMO_MIN_NORMAL
			ammo_max = DROP_AMMO_MAX_NORMAL
			currency_base = DROP_CURRENCY_BASE_NORMAL
			currency_per_floor = DROP_CURRENCY_PER_FLOOR_NORMAL

	var entries: Array = []
	# ── Boss：1-2 把枪 + 3 件其它 + 1 包弹药 = 5-6 件（2026-10-18）──────────
	# 枪与非枪拆成两个池：混池抽 3 次无法保证「一定出枪」，而 Boss 的契约是枪必出。
	# 第 2 把用独立 entry 的 chance 表达「50% 再给一把」，不引入区间 draws
	# （draws 只接受整数，写 {"min":1,"max":2} 会被 int() 静默截成 1）。
	if resolved_tier == TIER_BOSS:
		var boss_weapon_pool := "boss_weapon_floor_%d" % [safe_floor]
		entries.append({
			"kind": "pool", "pool_id": boss_weapon_pool, "draws": 1,
			"chance": 1.0, "max_drops": 2, "merge_same_item": false,
		})
		entries.append({
			"kind": "pool", "pool_id": boss_weapon_pool, "draws": 1,
			"chance": BOSS_SECOND_WEAPON_CHANCE, "max_drops": 2, "merge_same_item": false,
		})
		entries.append({
			"kind": "pool", "pool_id": "boss_floor_%d" % [safe_floor],
			"draws": BOSS_OTHER_DROPS, "max_drops": BOSS_OTHER_DROPS,
			"merge_same_item": false,
		})
	elif item_chance > 0.0:
		entries.append({
			"kind": "pool", "pool_id": pool_id, "draws": 1, "chance": item_chance,
		})
	# ── 强化怪：25% 追加 1 把枪（业主 2026-10-18）────────────────────────────
	# 只认 `_strong` 变种。精英（ELITE 房）的 `is_elite` 是**身份指派**，不是强化怪，
	# 仍走 elite_floor_* 的「100% 抽 1 件」，不叠加这条通道。
	if MonsterVariants.is_variant(monster_id):
		var strong_pool := (
			"strong_weapon_floor_1" if safe_floor <= 2 else "strong_weapon_floor_2"
		)
		entries.append({
			"kind": "pool", "pool_id": strong_pool, "draws": 1,
			"chance": STRONG_VARIANT_WEAPON_CHANCE, "max_drops": 1,
		})
	if ammo_chance > 0.0:
		entries.append({
			"kind": "item", "item_id": DROP_AMMO_ITEM_ID,
			"count": { "min": ammo_min, "max": ammo_max },
			"chance": ammo_chance,
			# 旧行为：池已抽出同一物品时，以整包数量**覆盖**该件，而不是多出一件。
			"merge_same_item": true,
			# 备弹豁免关卡级空掉落：命中率是作者指定的数，不该被二次打折。
			"exempt_from_empty": true,
		})
	entries.append({
		"kind": "currency", "currency_id": "extraction_points",
		"amount": { "base": currency_base, "per_floor": currency_per_floor },
	})

	return {
		"spec_id": "monster:%s:%s:%d" % [monster_id, resolved_tier, safe_floor],
		"entries": entries,
	}


## 人类可读的掉落列文本（等价于旧自然语言，仅供工具/文档展示，不参与运行时判定）。
static func describe_drop_spec(monster_id: String, tier: String = TIER_NORMAL, floor_level: int = 0, floor: int = 1) -> String:
	var spec := drop_spec_for(monster_id, tier, floor_level, floor)
	if spec.is_empty():
		return ""
	var parts: Array[String] = []
	for entry in spec.get("entries", []):
		var e: Dictionary = entry
		match str(e.get("kind", "")):
			"pool":
				parts.append("loot_pool=%s; item_chance=%.2f" % [str(e.get("pool_id", "")), float(e.get("chance", 1.0))])
			"item":
				var rng: Dictionary = e.get("count", {})
				parts.append("ammo=%.2f:%d-%d" % [
					float(e.get("chance", 1.0)), int(rng.get("min", 0)), int(rng.get("max", 0)),
				])
			"currency":
				var amount: Dictionary = e.get("amount", {})
				parts.append("currency=base:%d+per_floor:%d" % [
					int(amount.get("base", 0)), int(amount.get("per_floor", 0)),
				])
	return "%s; tier=%s" % ["; ".join(parts), tier]

## 获取精英词缀描述
static func get_modifier_description(modifier: String) -> String:
	match modifier:
		"巨大化": return "体型增大，血量翻倍，移动变慢"
		"分裂": return "死亡时分裂成小怪"
		"反弹": return "周期性反弹子弹"
		"寄生": return "死亡后强化附近的怪物"
		"抢枪": return "短暂复制玩家的武器效果"
		"吞弹": return "吃掉投射物并转化为攻击"
	return ""

## 映射中文词缀ID到英文，供 EliteActiveSkillComponent.inject_elite_skills() 正确路由
static func _map_modifier_to_english(cn_id: String) -> String:
	match cn_id:
		"巨大化": return "Elite.Huge"
		"分裂": return "Elite.SpawnOnDeath"
		"反弹": return "Elite.Ricochet"
		"寄生": return "Elite.Parasite"
		"抢枪": return "Elite.WeaponParasite"
		"吞弹": return "Elite.BulletEater"
	return "Elite.Huge"
