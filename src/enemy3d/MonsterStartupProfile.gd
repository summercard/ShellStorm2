class_name MonsterStartupProfile
extends RefCounted
## 怪物「启动过程」的数值与公式唯一真源。
##
## 设计原文：docs/v0.1/06A_怪物AI系统完整设计_评审稿.md §6.1.1「启动过程」。
## 表现资产：FX01-16 `VFX-MONSTER-ROAR-ICON-3D`（头顶吼叫图标）。
##
## 为什么单独成文件：这套公式同时出现在**设计文档**（给人读）与**运行时**
## （Enemy3D 的实现）两处。按项目纪律「跨文件契约必须有一条会失败的断言盯着」，
## 文档里的每个数字都在这里落成常量，由 tests/verification/verify_monster_startup_roar.gd
## 逐条断言；改公式必须同时改文档与本文件，否则验收红。
##
## 本文件只提供**纯计算**：不持有节点、不读场景树、不认识 Player3D / Enemy3D 实例。
## 尺寸公式的体型来源直接引用 `Enemy3D.HEALTH_BAR_SIZE_BY_KIND`，避免第二份体型表漂移。


# ── §6.1.2 时长 ────────────────────────────────────────────────────────────
## 启动过程总时长窗口（秒）。业主指定，硬约束。
const T_STARTUP_MIN := 0.30
const T_STARTUP_MAX := 0.60
## 转身基准角速度（度/秒）。转角越大、转身段越长，转速恒定。
const YAW_RATE_DEG_PER_SEC := 520.0
## 吼叫段最短时长（秒）。保证头顶图标出现后有可读的停留。
const T_ROAR_MIN := 0.16
## 随机抖动上限（秒）。让朝向相同的两只怪不同步启动。
const STARTUP_JITTER_MAX := 0.18
## 转身段最多占用启动窗口的比例。
const TURN_SHARE_MAX := 0.55


# ── §6.1.4 头顶图标 ────────────────────────────────────────────────────────
## 图标世界边长 / 头顶血条宽度。
const ICON_BAR_RATIO := 0.42
## 图标世界边长钳制区间（米）：下限保证小怪读得出，上限防止 Boss 失控。
const ICON_EDGE_MIN_M := 0.45
const ICON_EDGE_MAX_M := 1.20
## 图标底边与血条槽根之间的垂直间隙（米）。
## 图标底边与血条顶边之间的**间隙**，按图标世界边长的比例给（不是固定米数）。
##
## 为什么必须是比例而不是常量：图标内容在自身方框里的**垂直占比随贴图变**。
## 2026-10-14 把吼叫图标从「怪兽大嘴」换成「感叹号」后，感叹号的圆点正好落在方框底部
## （实测内容 bbox 占到 21/256 … 235/256），而大嘴图形底部下方还留着一段空白。
## 固定 0.12 m 的间隙在大嘴时代读起来很宽，换成感叹号后就直接贴住血条了
## （预览实测 elite/boss 档间隙 −1px，即重叠）。
##
## 按比例给 ⇒ 间隙 / 图标 = 0.30 恒定，**任何体型下观感一致**，
## 不会再因为换一张贴图就把间距吃掉。血条高度那一半仍由 bar_h/2 单独承担。
const ICON_BAR_GAP_RATIO := 0.30
## 启动结束后图标继续停留的尾巴（秒）——让「吼 → 打」的因果被读到。
const ICON_TAIL_SECONDS := 0.25
## 图标淡出时长（秒）。
const ICON_FADE_SECONDS := 0.18


# ── §6.1.3 重播与打断 ──────────────────────────────────────────────────────
## 脱战静默超过该秒数后，启动过程重新武装（下次获取目标会再播一次）。
const REARM_AFTER_SECONDS := 3.0


## 把转角归一化到最短转向区间 [-180, 180]。
##
## 必须做这一步：359° 在几何上是「朝左差 1°」，不是「转身 359°」。不归一化就会
## 用 359/520 = 0.69s 去转一个其实只要 0.002s 的角度，转身段直接顶穿启动窗口。
static func normalize_delta_yaw(delta_yaw_deg: float) -> float:
	return fposmod(delta_yaw_deg + 180.0, 360.0) - 180.0


## 启动过程总时长。`delta_yaw_deg` = 当前朝向与玩家方向的夹角；`jitter` ∈ [0, STARTUP_JITTER_MAX]。
static func startup_seconds(delta_yaw_deg: float, jitter: float = 0.0) -> float:
	var base := turn_seconds(delta_yaw_deg) + T_ROAR_MIN
	var rolled := base + clampf(jitter, 0.0, STARTUP_JITTER_MAX)
	return clampf(rolled, T_STARTUP_MIN, T_STARTUP_MAX)


## 段 A（转身）时长。角速度恒定，与 T_STARTUP_MAX 无关。恒 ≤ 180/520 ≈ 0.346s。
static func turn_seconds(delta_yaw_deg: float) -> float:
	return absf(normalize_delta_yaw(delta_yaw_deg)) / YAW_RATE_DEG_PER_SEC


## 段 B（吼叫）时长 = 总时长 − 转身段。恒 ≥ T_ROAR_MIN。
static func roar_seconds(delta_yaw_deg: float, jitter: float = 0.0) -> float:
	return startup_seconds(delta_yaw_deg, jitter) - turn_seconds(delta_yaw_deg)


## 段 A 应使用的最小转速（度/秒）。由「转角必须在本段内转完」反推，
## 供 Enemy3D 设置转向速率；恒等于 YAW_RATE_DEG_PER_SEC 或更高（窗口被钳制时）。
static func turn_rate_deg_per_sec(delta_yaw_deg: float, jitter: float = 0.0) -> float:
	var t_turn := turn_seconds(delta_yaw_deg)
	if t_turn <= 0.0001:
		return YAW_RATE_DEG_PER_SEC
	var allowed := minf(TURN_SHARE_MAX * startup_seconds(delta_yaw_deg, jitter), t_turn)
	if allowed <= 0.0001:
		return YAW_RATE_DEG_PER_SEC
	return absf(normalize_delta_yaw(delta_yaw_deg)) / allowed


## 头顶图标世界边长（米）。按体型（= 头顶血条宽度）等比缩放。
static func icon_edge_m(health_bar_width_m: float) -> float:
	return clampf(health_bar_width_m * ICON_BAR_RATIO, ICON_EDGE_MIN_M, ICON_EDGE_MAX_M)


## 头顶图标相对「血条槽根」的垂直偏移（米）。图标坐在血条正上方，不遮挡血条。
##
## 展开即 `bar_h/2 + ICON_BAR_GAP_RATIO*edge + edge/2 = bar_h/2 + 0.80*edge`，
## 但刻意保留三段写法：三段的来源各不相同（血条自身半高 / 间隙 / 图标半高），
## 合成一个系数后就没法一眼看出哪一项该改。
static func icon_offset_y_m(health_bar_width_m: float, health_bar_height_m: float) -> float:
	var edge := icon_edge_m(health_bar_width_m)
	return health_bar_height_m * 0.5 + ICON_BAR_GAP_RATIO * edge + edge * 0.5


## 图标可见保持段（从显形到开始淡出）的秒数。
static func icon_hold_seconds(delta_yaw_deg: float, jitter: float = 0.0) -> float:
	return roar_seconds(delta_yaw_deg, jitter) + ICON_TAIL_SECONDS


## 图标 Prefab 的 lifetime = 保持段 + 淡出段。
static func icon_lifetime_seconds(delta_yaw_deg: float, jitter: float = 0.0) -> float:
	return icon_hold_seconds(delta_yaw_deg, jitter) + ICON_FADE_SECONDS


## 该怪物种类是否播放启动过程。Boss 走自己的激活流程，不重复播。
static func plays_startup(enemy_kind: String) -> bool:
	return enemy_kind != "boss"
