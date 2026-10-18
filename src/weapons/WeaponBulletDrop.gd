class_name WeaponBulletDrop
extends RefCounted
## 掉落枪械自带的**绑定弹药模块** —— 唯一真源。
##
## 业主口径（2026-10-18）：掉落武器会随机配置某个弹药模块，**并且不能拆卸**。
##
## ## 为什么"绑定"要落成一个字段
## 「不能拆」如果只写在 UI 里（灰掉按钮），`Player3D.install_bullet_module_to_weapon_slot`
## 仍然能被任何调用方绕过去（训练场、局内快捷装配、工作台各有独立入口）。
## 所以锁定必须是一条**随实例持久化**的数据：`WeaponInstance.bullet_module_locked`。
##
## ## 为什么随机在掉落时定，不在装配时定
## 弹药模块是这把枪的**身份**。若在读档/装备时随机，同一把枪每次读档会换弹种 ——
## 存档就成了投骰机。掉落那一刻定死、写进 `bullet_module_id` 与装配快照，
## 之后 `from_item` 只还原、不再掷骰。
##
## ## 与 `WeaponDropGrade` 的分工
## 品质（蓝/紫/金）决定**数值**，弹药模块决定**弹道行为**，两者独立掷骰、各自可复现。
## 同一把枪可以「金品质 + 黑洞弹」，也可以「蓝品质 + 标准弹」。

## 掷骰顺序。改顺序会改变同 seed 的落点 ⇒ 必须与 04 §22.14 同批改。
const ROLL_ORDER: Array[String] = [
	"mod_bullet_standard",
	"mod_bullet_sticky",
	"mod_bullet_bounce",
	"mod_bullet_piercing",
	"mod_bullet_explosive",
	"mod_bullet_balloon",
	"mod_bullet_homing",
	"mod_bullet_blackhole",
]

## 权重。总和必须为 100（`verify_weapon_drop_grade` 断言）。
##
## 配比理由（按稀有度阶梯，不做楼层偏置）：
##   标准弹 34% 当基调 —— 掉落枪大多还是"能用但要自己改造"的白板；
##   非常见 28%、稀有 29%、史诗 9% ⇒ 约 1/3 的枪自带特殊弹道，
##   拿到就是一次"这把枪跟别的不一样"的惊喜，但不至于泛滥到让特殊弹贬值。
## 刻意不按 Boss / 强化怪分档：弹药模块的稀有感应当来自**武器本身出得多不多**，
## 而不是再叠一层档位表 —— 层数越多越难解释、越难验收。
const ROLL_WEIGHTS: Dictionary = {
	"mod_bullet_standard": 34,
	"mod_bullet_sticky": 15,
	"mod_bullet_bounce": 13,
	"mod_bullet_piercing": 11,
	"mod_bullet_explosive": 10,
	"mod_bullet_balloon": 8,
	"mod_bullet_homing": 6,
	"mod_bullet_blackhole": 3,
}

## 兜底弹药模块。未知 / 空 / 已下架的 ID 一律回落到标准弹 ——
## 回落成"无弹药"会让枪打不出子弹，那是比配错弹严重得多的事故。
const FALLBACK_BULLET := "mod_bullet_standard"

## 近战武器没有弹药槽。
const MELEE_SUBTYPE := "melee_weapon"


## 按 0..1 的均匀抽样值选弹药模块。传 `rng.randf()`。
##
## 吃抽样值而不是自己掷：掉落必须与 `RewardService` 的确定性 rng 共用一条流，
## 才能保证「同 run_seed + 同一击杀事件 ⇒ 同一把枪、同一品质、同一弹种」。
static func roll(roll_value: float) -> String:
	var total := 0.0
	for bullet_id in ROLL_ORDER:
		total += float(ROLL_WEIGHTS[bullet_id])
	if total <= 0.0:
		return FALLBACK_BULLET
	var target := clampf(roll_value, 0.0, 0.999999) * total
	var cumulative := 0.0
	for bullet_id in ROLL_ORDER:
		cumulative += float(ROLL_WEIGHTS[bullet_id])
		if target < cumulative:
			return bullet_id
	return ROLL_ORDER[ROLL_ORDER.size() - 1]


static func is_valid(bullet_id: String) -> bool:
	return ROLL_WEIGHTS.has(bullet_id)


static func normalize(bullet_id: String) -> String:
	return bullet_id if is_valid(bullet_id) else FALLBACK_BULLET


## 该物品是不是近战武器（近战没有弹药槽，掉落时不配弹、也不锁）。
##
## 判据与 `AssemblyNode` / `WeaponModel3D` 同一口径：`subtype == melee_weapon` 或带 `melee` 标签。
## 用两条是因为物品表两条都写过（近战物品有 subtype，装配节点只有 tags）。
static func is_melee_weapon(item: Dictionary) -> bool:
	if str(item.get("subtype", "")) == MELEE_SUBTYPE:
		return true
	for tag in item.get("tags", []):
		if str(tag) == "melee":
			return true
	return false


## 全部候选弹药模块 ID（不含兜底逻辑），按掷骰顺序。
static func candidate_ids() -> Array[String]:
	var out: Array[String] = []
	for bullet_id in ROLL_ORDER:
		out.append(bullet_id)
	return out


## 一行摘要，供验收 / 工具打印判据。
static func summary_line() -> String:
	var total := 0.0
	for bullet_id in ROLL_ORDER:
		total += float(ROLL_WEIGHTS[bullet_id])
	var parts: Array[String] = []
	for bullet_id in ROLL_ORDER:
		parts.append("%s=%.0f%%" % [bullet_id, float(ROLL_WEIGHTS[bullet_id])])
	return "WEAPON_BULLET_DROP total=%.0f locked=on %s" % [total, " ".join(parts)]
