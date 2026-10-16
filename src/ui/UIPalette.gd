class_name UIPalette
## UIPalette — 集中所有 UI 颜色 token
## 用途：统一全屏 UI 颜色基调（深色科幻/废土），改一处全屏联动
## 所有常量均为 0~1 范围的 RGBA Color

extends RefCounted


# ========== 背景层级 (5 档深色) ==========
## 弹窗背板 / 模态层（最深）
const BG_DEEPEST := Color(0.006, 0.018, 0.026, 0.50)
## 主面板
const BG_DARK := Color(0.012, 0.038, 0.052, 0.50)
## 子容器 / 分组
const BG_MID := Color(0.020, 0.072, 0.090, 0.50)
## 格子 / 槽位
const BG_SLOT := Color(0.010, 0.030, 0.038, 0.50)
## 格子悬停高亮
const BG_SLOT_HOVER := Color(0.025, 0.145, 0.175, 0.50)

# ========== 连续棋盘与拖拽反馈 ==========
const GRID_EMPTY := Color(0.018, 0.060, 0.086, 0.72)
const GRID_OCCUPIED := Color(0.075, 0.130, 0.190, 0.92)
const GRID_PREVIEW_VALID := Color(0.25, 0.95, 0.72, 0.30)
const GRID_PREVIEW_INVALID := Color(1.0, 0.22, 0.28, 0.30)
const GRID_PREVIEW_SOURCE := Color(0.95, 0.72, 0.18, 0.30)
const GRID_FOCUS := Color(0.38, 0.84, 1.0, 1.0)


# ========== 主界面战术设计语言 ==========
const NEON_CYAN := Color(0.20, 0.90, 1.0, 1.0)
const NEON_CYAN_DIM := Color(0.08, 0.48, 0.58, 0.88)
const NEON_MINT := Color(0.24, 0.92, 0.74, 1.0)
const SOUL_GOLD := Color(1.0, 0.72, 0.16, 1.0)
const DANGER_RED := Color(0.96, 0.08, 0.14, 1.0)
const DIVIDER := Color(0.12, 0.40, 0.48, 0.66)


# ========== 边框 / 描边 (4 档) ==========
## 微妙边框（分割线、默认边框）
const BORDER_SUBTLE := Color(0.08, 0.34, 0.42, 0.72)
## 普通边框
const BORDER_NORMAL := Color(0.12, 0.66, 0.76, 0.90)
## 强调边框（hover/焦点时使用）
const BORDER_ACCENT := NEON_CYAN_DIM
## 焦点边框（高亮、活跃）
const BORDER_FOCUS := NEON_CYAN


# ========== 状态色 (HP / Ammo) ==========
## HP 高 (>0.6) — 绿
const HP_HIGH := Color(0.22, 0.90, 0.60, 1.0)
## HP 中 (0.3~0.6) — 黄
const HP_MID := Color(0.95, 0.80, 0.30, 1.0)
## HP 低 (<0.3) — 红
const HP_LOW := DANGER_RED

## 弹药充足
const AMMO_OK := Color(0.55, 0.70, 0.95, 1.0)
## 弹药偏低
const AMMO_LOW := Color(0.95, 0.55, 0.30, 1.0)
## 弹药空
const AMMO_EMPTY := Color(0.95, 0.30, 0.30, 1.0)


# ========== 文字色 ==========
## 主文字
const TEXT_PRIMARY := Color(0.88, 0.95, 0.98, 1.0)
## 次级文字
const TEXT_SECONDARY := Color(0.54, 0.72, 0.78, 1.0)
## 禁用文字
const TEXT_DISABLED := Color(0.45, 0.50, 0.60, 1.0)
## 金色文字（标题、稀有物品）
const TEXT_GOLD := SOUL_GOLD


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

# Inventory reference palette: soft navy surfaces and quiet neutral outlines.
const INVENTORY_PANEL := Color(0.075, 0.13, 0.20, 0.92)
const INVENTORY_SLOT := Color(0.055, 0.10, 0.16, 0.70)
const INVENTORY_OUTLINE := Color(0.62, 0.68, 0.73, 0.62)
const INVENTORY_ACTION := Color(0.73, 0.91, 0.98)
const INVENTORY_SELECTED := Color(1.0, 0.62, 0.20)

# ========== 「棱镜线框」Prism Wireframe 视觉规范 Token ==========
# 2026-10-16 业主否决鸭科夫深蓝圆角胶囊风，改按新参考图重塑：
# 设计语言 = 明亮低多边形 + 全白细线几何。UI **不画实心卡片**，只用 1px 白线、
# 四角括号选框、方角箭头钮、白底黑字方键帽与黑白高对比主行动钮；
# 排版为「弱标签(大写+字距) / 强数值(近白+字距)」两级。

## 全屏压暗底色（保留 3D 实景可见，参考图即"无遮罩感"）
const PRISM_DIM := Color(0.031, 0.055, 0.086, 0.58)
## 面板极淡底：几乎不遮挡实景（HUD 卡片 alpha 契约 <= 0.50）
const PRISM_SURFACE := Color(0.055, 0.086, 0.129, 0.42)
## 模态面板底：稍实一点以承载密集设置项，仍是深蓝透明而非实心卡片
const PRISM_SURFACE_SOLID := Color(0.043, 0.071, 0.110, 0.72)
## 主体线（四角括号 / 分隔线 / 键帽轮廓）
const PRISM_LINE := Color(1.0, 1.0, 1.0, 0.86)
## 次级线（分隔线、未选中框）
const PRISM_LINE_SOFT := Color(1.0, 1.0, 1.0, 0.34)
## 极弱线（底衬网格、静态框）
const PRISM_LINE_FAINT := Color(1.0, 1.0, 1.0, 0.14)
## 主文字（近白，对应参考图 HIDDEN TEMPLE / CONTINUE）
const PRISM_TEXT := Color(0.949, 0.965, 0.984, 1.0)
## 弱标签（钢蓝，对应参考图 ARENA / THEME / GAME MODE）
const PRISM_LABEL := Color(0.545, 0.643, 0.784, 1.0)
## 最弱说明文字
const PRISM_TEXT_FAINT := Color(0.404, 0.482, 0.600, 1.0)
## 深色墨水（实心近白按钮上的文字，等价参考图黑底白字的反相）
const PRISM_INK := Color(0.043, 0.071, 0.110, 1.0)
## 天蓝强调（取自参考图背景蓝；仅用于焦点、选中与进度）
const PRISM_ACCENT := Color(0.310, 0.659, 1.0, 1.0)
## 史诗紫：**稀有度专用**的第二强调色。
## 棱镜调色板原本只有"天蓝强调"一个冷色槽，但稀有度（普通/稀有/史诗/传说/秘法）
## 是必须可区分的**语义色**，蓝与紫挤进同一槽会让背包与图鉴失去分级可读性，
## 故单独开一槽（仍属语义色，不作装饰铺陈；一屏内仍受"彩色面数 ≤ 2"约束）。
const PRISM_EPIC := Color(0.720, 0.545, 1.0, 1.0)
## 平红危险（纯平色，无辉光无渐变）
const PRISM_DANGER := Color(1.0, 0.420, 0.353, 1.0)
## 琥珀警示
const PRISM_WARN := Color(1.0, 0.741, 0.290, 1.0)
## 成功/安全绿（平色）
const PRISM_OK := Color(0.376, 0.878, 0.588, 1.0)
## 生命条平红（HUD 探针契约：r > 0.75 且 g < 0.25）
const PRISM_HP_RED := Color(0.925, 0.196, 0.227, 1.0)
## 生命条底槽（深灰蓝，非深红，保持线框冷感）
const PRISM_HP_BG := Color(0.086, 0.106, 0.137, 0.72)
## 实体白方键帽底色与深色键帽字
const PRISM_KEYCAP_BG := Color(0.949, 0.965, 0.984, 1.0)
const PRISM_KEYCAP_TEXT := Color(0.043, 0.071, 0.110, 1.0)
## 实心主行动钮（近白）三态
const PRISM_PRIMARY_BG := Color(0.949, 0.965, 0.984, 1.0)
const PRISM_PRIMARY_BG_HOVER := Color(1.0, 1.0, 1.0, 1.0)
const PRISM_PRIMARY_BG_PRESS := Color(0.780, 0.816, 0.867, 1.0)

