class_name AimAssist3D
extends RefCounted
## 虚拟摇杆瞄准辅助（磁吸）。
##
## 为什么需要：摇杆是**绝对角度**输入，但物理行程有限（Xbox 全周约 30mm），
## 边缘处 1mm 抖动 ≈ 3~4°，手腕微动就是几度误差 —— 这是摇杆的天花板，
## 靠调死区/平滑治不了本。顶视角射击的通行解是「磁吸 + 摩擦 + 子弹磁力」，
## 本模块做最有效的一层：把准星朝视野内**已照亮**的敌人轻轻拉一把，
## 让「大致对准」变成「真的对准」。
##
## 与 `aim_direction` 的关系：它同时是面朝向 + 弹道方向 + 准星位置（三用）
## ⇒ 本模块偏移的是三者**共同的真源**，一改全改；这也意味着吸附精度
## 直接等于命中精度，所以下面三条硬约束必须守住：
##
## 1. **绝不吸附看不见的敌人**。本项目敌人只有处于人工光 / 阳光时才可见
##    （`EnemyIllumination3D.STATE_*`），吸附黑暗中的敌人等于给玩家透视外挂。
##    过滤器放在调用方（`Player3D._collect_aim_assist_candidates`），
##    本模块只吃已完成「存活 + 已照亮」过滤的候选 —— 纯函数，便于逐值断言。
## 2. **偏转有硬上限**（`DEFAULT_MAX_ANGLE_DEG`）。辅助只做「最后几度的对齐」，
##    绝不让准星从玩家指的方向被拽走；打哪边始终由玩家决定。
## 3. **无状态、不读全局**：候选由调用方收集。headless 下可直接喂合成候选。

## 吸附锥半角（度）：敌人与准星的夹角超过它就不再产生吸引力。
const DEFAULT_CONE_DEG := 20.0
## 单帧最大偏转角（度）：权重再高也只偏这么多，这是「不抢控制」的兑现方式。
const DEFAULT_MAX_ANGLE_DEG := 8.0
## 距离权重的作用区间（米）：近于此距离权重拉满、远于彼距离权重归零。
## 近处更好打、也更需要稳住准星；远距离留给玩家自己瞄，避免「隔着半张图被吸走」。
const DEFAULT_NEAR_RANGE := 4.0
const DEFAULT_FAR_RANGE := 26.0
## 辅助总强度（0 = 完全关闭、1 = 常规定档）。验收用 0 / 1 做反向对照。
const DEFAULT_STRENGTH := 1.0
## 候选预筛：扫描半径（米）与预筛锥半角（度）。预筛锥比吸附锥（20°）稍宽，
## 避免「差一点点没进候选」；真正的权重与偏转上限仍由 solve 决定。
const DEFAULT_SCAN_RANGE := 26.0
const DEFAULT_SCAN_CONE_DEG := 30.0

## 候选字典的字段名（调用方与本模块共用的契约）。
const KEY_DIRECTION := "direction"
const KEY_DISTANCE := "distance"


## 单个敌人能否成为吸附候选（纯函数）。
##
## 调用方（Player3D）负责取数，本函数负责判定 —— 这样「**黑暗中的敌人不可被
## 吸附**」这条最不能破的约束可以在 headless 下逐值断言，不必造真实敌人实例。
##
## 四条准入：
## 1. 必须存活：尸体不该再吸准星。
## 2. **必须已照亮**：本项目敌人只有处于人工光 / 阳光时才看得见，吸附黑暗中的
##    敌人等于给玩家透视外挂。这是本模块存在的前提，不是可调项。
## 3. 距离在扫描半径内：避免隔着半张图被吸走。
## 4. 夹角在预筛锥内：粗筛掉明显不在瞄准方向上的目标。
static func is_eligible(
	alive: bool,
	illumination_state: String,
	distance: float,
	angle_deg: float,
	scan_range: float = DEFAULT_SCAN_RANGE,
	scan_cone_deg: float = DEFAULT_SCAN_CONE_DEG
) -> bool:
	if not alive:
		return false
	if illumination_state == EnemyIllumination3D.STATE_DARKNESS:
		return false
	if distance <= 0.0001 or distance > scan_range:
		return false
	return angle_deg <= scan_cone_deg


## 求解：把 `aim_dir` 朝候选敌人方向轻轻拉一把。
##
## `candidates` 每项形如 `{"direction": Vector3(水平、未必需归一), "distance": float}`，
## 由调用方收集且**已完成可见性与存活过滤**。
## 返回水平单位向量；无候选 / 无有效方向 / 强度为 0 时，返回 `aim_dir` 的水平归一化。
static func solve(aim_dir: Vector3, candidates: Array[Dictionary], options: Dictionary = {}) -> Vector3:
	var flat_aim := Vector2(aim_dir.x, aim_dir.z)
	if flat_aim.length_squared() <= 0.000001:
		return aim_dir
	flat_aim = flat_aim.normalized()
	var fallback := Vector3(flat_aim.x, 0.0, flat_aim.y)
	var strength := float(options.get("strength", DEFAULT_STRENGTH))
	if strength <= 0.0 or candidates.is_empty():
		return fallback
	var cone_rad := deg_to_rad(float(options.get("cone_deg", DEFAULT_CONE_DEG)))
	var near_range := float(options.get("near_range", DEFAULT_NEAR_RANGE))
	var far_range := float(options.get("far_range", DEFAULT_FAR_RANGE))
	var best_direction := Vector2.ZERO
	var best_weight := 0.0
	for candidate in candidates:
		# 显式标注类型：本项目把「变量类型由 Variant 推断」当硬 Parse Error，
		# 而 Dictionary.get() 返回 Variant，用 := 接会整脚本编译失败。
		var raw_direction: Variant = candidate.get(KEY_DIRECTION)
		if not (raw_direction is Vector3):
			continue
		var target: Vector3 = raw_direction as Vector3
		var target_2d := Vector2(target.x, target.z)
		if target_2d.length_squared() <= 0.000001:
			continue
		target_2d = target_2d.normalized()
		var angle := absf(flat_aim.angle_to(target_2d))
		if angle > cone_rad:
			continue
		var distance := float(candidate.get(KEY_DISTANCE, near_range))
		var weight := _weight(angle, cone_rad, distance, near_range, far_range)
		if weight > best_weight:
			best_weight = weight
			best_direction = target_2d
	if best_weight <= 0.0 or best_direction == Vector2.ZERO:
		return fallback
	var limit := (
		deg_to_rad(float(options.get("max_angle_deg", DEFAULT_MAX_ANGLE_DEG)))
		* strength
		* best_weight
	)
	var delta := clampf(flat_aim.angle_to(best_direction), -limit, limit)
	var rotated := flat_aim.rotated(delta)
	return Vector3(rotated.x, 0.0, rotated.y)


## 单个候选的吸引权重（0~1）。
##
## 角度项**取平方**：正对轴心的目标远强于锥边缘的目标，避免「两个敌人都沾
## 一点」导致准星在二者之间来回跳 —— 那种抖动正是玩家口中「不精确」的来源。
static func _weight(
	angle: float,
	cone_rad: float,
	distance: float,
	near_range: float,
	far_range: float
) -> float:
	var angle_factor := 1.0 - angle / maxf(0.0001, cone_rad)
	var span := maxf(0.0001, far_range - near_range)
	var distance_factor := clampf(1.0 - (distance - near_range) / span, 0.0, 1.0)
	return clampf(angle_factor * angle_factor * distance_factor, 0.0, 1.0)
