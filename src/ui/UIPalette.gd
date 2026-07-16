class_name UIPalette
## UIPalette — 集中所有 UI 颜色 token
## 用途：统一全屏 UI 颜色基调（深色科幻/废土），改一处全屏联动
## 所有常量均为 0~1 范围的 RGBA Color

extends RefCounted


# ========== 背景层级 (5 档深色) ==========
## 弹窗背板 / 模态层（最深）
const BG_DEEPEST := Color(0.025, 0.030, 0.045, 0.96)
## 主面板
const BG_DARK := Color(0.055, 0.065, 0.085, 0.92)
## 子容器 / 分组
const BG_MID := Color(0.085, 0.095, 0.125, 0.92)
## 格子 / 槽位
const BG_SLOT := Color(0.12, 0.14, 0.18, 0.90)
## 格子悬停高亮
const BG_SLOT_HOVER := Color(0.20, 0.25, 0.35, 0.90)


# ========== 边框 / 描边 (4 档) ==========
## 微妙边框（分割线、默认边框）
const BORDER_SUBTLE := Color(0.30, 0.33, 0.40, 0.60)
## 普通边框
const BORDER_NORMAL := Color(0.42, 0.50, 0.62, 0.85)
## 强调边框（hover/焦点时使用）
const BORDER_ACCENT := Color(0.36, 0.44, 0.58, 0.90)
## 焦点边框（高亮、活跃）
const BORDER_FOCUS := Color(0.55, 0.70, 0.95, 0.95)


# ========== 状态色 (HP / Ammo) ==========
## HP 高 (>0.6) — 绿
const HP_HIGH := Color(0.30, 0.85, 0.45, 1.0)
## HP 中 (0.3~0.6) — 黄
const HP_MID := Color(0.95, 0.80, 0.30, 1.0)
## HP 低 (<0.3) — 红
const HP_LOW := Color(0.95, 0.30, 0.30, 1.0)

## 弹药充足
const AMMO_OK := Color(0.55, 0.70, 0.95, 1.0)
## 弹药偏低
const AMMO_LOW := Color(0.95, 0.55, 0.30, 1.0)
## 弹药空
const AMMO_EMPTY := Color(0.95, 0.30, 0.30, 1.0)


# ========== 文字色 ==========
## 主文字
const TEXT_PRIMARY := Color(0.92, 0.95, 1.00, 1.0)
## 次级文字
const TEXT_SECONDARY := Color(0.65, 0.70, 0.80, 1.0)
## 禁用文字
const TEXT_DISABLED := Color(0.45, 0.50, 0.60, 1.0)
## 金色文字（标题、稀有物品）
const TEXT_GOLD := Color(1.0, 0.85, 0.30, 1.0)


# ========== 物品类型边框色 ==========
## FateCard — 紫
const ITEM_FATE_CARD := Color(0.6, 0.4, 0.8, 1.0)
## Weapon / GunBody — 金
const ITEM_WEAPON := Color(0.96, 0.62, 0.04, 1.0)
## Bullet — 蓝
const ITEM_BULLET := Color(0.29, 0.62, 1.0, 1.0)
## 默认 — 灰
const ITEM_DEFAULT := Color(0.5, 0.5, 0.5, 1.0)


# ========== 状态反馈色 ==========
## 可购买 / 库存充足 — 绿
const STATUS_OK := Color(0.4, 0.9, 0.4, 0.7)
## 不可购买 / 库存满 — 红
const STATUS_NO := Color(0.9, 0.3, 0.3, 0.6)


# ========== 工具：按物品类型取边框色 ==========
static func item_border_color(item_type: String) -> Color:
	match item_type:
		"FateCard":
			return ITEM_FATE_CARD
		"Weapon", "GunBody":
			return ITEM_WEAPON
		"Bullet":
			return ITEM_BULLET
		_:
			return ITEM_DEFAULT


# ========== 工具：按 HP 比例取颜色 ==========
static func hp_color_for_ratio(ratio: float) -> Color:
	if ratio > 0.6:
		return HP_HIGH
	elif ratio > 0.3:
		return HP_MID
	else:
		return HP_LOW
