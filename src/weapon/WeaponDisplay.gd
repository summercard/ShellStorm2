extends Node2D
class_name WeaponDisplay

# WeaponDisplay.gd — 武器视觉表现层
# 挂在 Player/WeaponAnchor 下，根据 WeaponAssemblyTree 动态显示对应枪械
# 支持：枪械多边形外形、枪口火焰动画、后坐力动画、瞄准旋转

## 枪型 → 多边形顶点映射（本地坐标，枪头朝右 → rotation=0）
## 格式：[p1, p2, ...] 组成 Polygon2D polygon，按顺时针/逆时针均可
static var GUN_SHAPES: Dictionary = {
	# 手枪 — 短小精悍
	"GunBody_Pistol": {
		"polygon": PackedVector2Array([
			Vector2(-6, -4),  # 左后
			Vector2(14, -4),  # 右前上
			Vector2(18, -2),  # 枪口上沿
			Vector2(18, 2),   # 枪口下沿
			Vector2(14, 4),    # 右前下
			Vector2(-6, 4),   # 左后
		]),
		"color": Color(0.55, 0.57, 0.62, 1.0),   # 冷灰金属
		"width": 8.0,
	},
	# 步枪 — 标准突击步枪外形
	"GunBody_Rifle": {
		"polygon": PackedVector2Array([
			Vector2(-10, -5),
			Vector2(16, -4),
			Vector2(22, -3),
			Vector2(24, 0),
			Vector2(22, 3),
			Vector2(16, 4),
			Vector2(-10, 5),
		]),
		"color": Color(0.38, 0.42, 0.38, 1.0),   # 军绿
		"width": 10.0,
	},
	# 霰弹枪 — 粗短，枪管宽
	"GunBody_Shotgun": {
		"polygon": PackedVector2Array([
			Vector2(-8, -6),
			Vector2(8, -5),
			Vector2(20, -4),
			Vector2(24, 0),
			Vector2(20, 4),
			Vector2(8, 5),
			Vector2(-8, 6),
		]),
		"color": Color(0.45, 0.35, 0.22, 1.0),   # 铜棕
		"width": 12.0,
	},
	# 冲锋枪 — 小型全自动
	"GunBody_SMG": {
		"polygon": PackedVector2Array([
			Vector2(-7, -4),
			Vector2(10, -4),
			Vector2(16, -2),
			Vector2(18, 0),
			Vector2(16, 2),
			Vector2(10, 4),
			Vector2(-7, 4),
		]),
		"color": Color(0.30, 0.30, 0.32, 1.0),   # 深灰
		"width": 8.0,
	},
	# 狙击枪 — 细长
	"GunBody_Sniper": {
		"polygon": PackedVector2Array([
			Vector2(-12, -4),
			Vector2(22, -3),
			Vector2(30, -1),
			Vector2(32, 0),
			Vector2(30, 1),
			Vector2(22, 3),
			Vector2(-12, 4),
		]),
		"color": Color(0.22, 0.25, 0.28, 1.0),   # 深海灰
		"width": 8.0,
	},
	# 榴弹发射器 — 粗厚
	"GunBody_Launcher": {
		"polygon": PackedVector2Array([
			Vector2(-10, -7),
			Vector2(6, -7),
			Vector2(14, -5),
			Vector2(18, 0),
			Vector2(14, 5),
			Vector2(6, 7),
			Vector2(-10, 7),
		]),
		"color": Color(0.50, 0.42, 0.18, 1.0),   # 暗金
		"width": 14.0,
	},
	# 机枪 — 粗长，弹链可见
	"GunBody_Machinegun": {
		"polygon": PackedVector2Array([
			Vector2(-12, -6),
			Vector2(14, -5),
			Vector2(22, -3),
			Vector2(26, 0),
			Vector2(22, 3),
			Vector2(14, 5),
			Vector2(-12, 6),
		]),
		"color": Color(0.28, 0.28, 0.25, 1.0),   # 深橄榄
		"width": 12.0,
	},
	# 蓄力萝卜炮 — 特殊炮管形态
	"GunBody_Charge": {
		"polygon": PackedVector2Array([
			Vector2(-8, -6),
			Vector2(4, -6),
			Vector2(12, -4),
			Vector2(18, -2),
			Vector2(20, 0),
			Vector2(18, 2),
			Vector2(12, 4),
			Vector2(4, 6),
			Vector2(-8, 6),
		]),
		"color": Color(0.60, 0.30, 0.60, 1.0),   # 紫色（蓄力风格）
		"width": 12.0,
	},
}

## 默认外形（未知的枪型兜底）
static var DEFAULT_SHAPE: Dictionary = {
	"polygon": PackedVector2Array([
		Vector2(-8, -4),
		Vector2(12, -4),
		Vector2(16, 0),
		Vector2(12, 4),
		Vector2(-8, 4),
	]),
	"color": Color(0.5, 0.5, 0.5, 1.0),
	"width": 8.0,
}

## 枪口火焰粒子
const MUZZLE_PARTICLES: Dictionary = {
	"pistol":    { "count": 4,  "lifetime": 0.08, "spread": 0.2,  "radius": 12, "color": Color(1.0, 0.85, 0.3, 1.0) },
	"rifle":     { "count": 6,  "lifetime": 0.10, "spread": 0.15, "radius": 16, "color": Color(1.0, 0.80, 0.2, 1.0) },
	"shotgun":   { "count": 10, "lifetime": 0.12, "spread": 0.35, "radius": 18, "color": Color(1.0, 0.70, 0.2, 1.0) },
	"smg":       { "count": 5,  "lifetime": 0.07, "spread": 0.25, "radius": 12, "color": Color(1.0, 0.90, 0.3, 1.0) },
	"sniper":    { "count": 6,  "lifetime": 0.14, "spread": 0.05, "radius": 20, "color": Color(1.0, 0.95, 0.6, 1.0) },
	"launcher":  { "count": 14, "lifetime": 0.18, "spread": 0.30, "radius": 22, "color": Color(1.0, 0.60, 0.1, 1.0) },
	"auto":      { "count": 7,  "lifetime": 0.08, "spread": 0.20, "radius": 14, "color": Color(1.0, 0.75, 0.2, 1.0) },
	"charge":    { "count": 12, "lifetime": 0.20, "spread": 0.25, "radius": 24, "color": Color(0.8, 0.4, 1.0, 1.0) },
}

## 节点引用
var _body: Polygon2D
var _muzzle: Polygon2D       # 枪口火焰（不激活时 invisible）
var _eyes: Node2D            # 命运眼睛（eyes sprite 容器）
var _legs: Node2D            # 命运脚（legs sprite 容器）
var _recoil_tween: Tween = null
var _muzzle_tween: Tween = null
var _parent_player: CharacterBody2D = null
var _weapon_tree: WeaponAssemblyTree = null

## 当前枪型名
var _current_gun_name: String = ""

## 动画状态
var _is_recoiling: bool = false
var _is_muzzle_flashing: bool = false

func _ready() -> void:
	_setup_nodes()
	# 延迟获取 weapon_tree（等待 Player 初始化完成）
	await get_tree().create_timer(0.05).timeout
	_refresh_weapon_from_player()

## 初始化枪身和枪口火焰多边形节点
func _setup_nodes() -> void:
	_body = Polygon2D.new()
	_body.name = "GunBody"
	_body.z_index = 1
	add_child(_body)

	_muzzle = Polygon2D.new()
	_muzzle.name = "MuzzleFlash"
	_muzzle.visible = false
	_muzzle.z_index = 2
	add_child(_muzzle)

	_eyes = Node2D.new()
	_eyes.name = "FateEyes"
	_eyes.z_index = 3
	add_child(_eyes)

	_legs = Node2D.new()
	_legs.name = "FateLegs"
	_legs.z_index = 3
	add_child(_legs)

## 连接 weapon_tree 的 tree_changed 信号，命运卡片改造武器树后枪械视觉能刷新
func _refresh_weapon_from_player() -> void:
	_parent_player = get_parent().get_parent() as CharacterBody2D
	if _parent_player and _parent_player.has_method("get_weapon_tree"):
		_weapon_tree = _parent_player.get_weapon_tree()
		if _weapon_tree:
			# 先断开旧的（防止重复连接）
			if _weapon_tree.tree_changed.is_connected(_on_tree_changed_by_fate):
				_weapon_tree.tree_changed.disconnect(_on_tree_changed_by_fate)
			_weapon_tree.tree_changed.connect(_on_tree_changed_by_fate)
			# weapon_fired 信号
			if not _weapon_tree.weapon_fired.is_connected(_on_weapon_fired):
				_weapon_tree.weapon_fired.connect(_on_weapon_fired)
			# 初始刷新
			if _weapon_tree.get_root():
				var root_name: String = _weapon_tree.get_root().node_name
				_current_gun_name = root_name
				var shape: Dictionary = GUN_SHAPES.get(root_name, DEFAULT_SHAPE)
				_apply_shape(shape)
				_refresh_fate_visual()

## weapon_tree 树结构变化时回调（命运卡片改造武器后触发）
func _on_tree_changed_by_fate() -> void:
	if _weapon_tree and _weapon_tree.get_root():
		_refresh_fate_visual()

## 从 weapon_tree 读取命运卡片视觉标签（fate_scale / eyes / legs），应用到对应节点
## 在 _update_gun_display 后调用，或在 tree_changed 信号触发时调用
func _refresh_fate_visual() -> void:
	if _weapon_tree == null or _body == null:
		return

	# 重置所有命运视觉
	_body.scale = Vector2.ONE
	_clear_fate_children(_eyes)
	_clear_fate_children(_legs)

	# 遍历 weapon_tree 节点读取命运标签
	var root: AssemblyNode = _weapon_tree.get_root()
	if root == null:
		return

	# fate_scale（"变大了"等效果）：可能设置在 gun body 根节点，也可能在 bullet 子节点
	var rstats: Dictionary = root.get_base_stats()
	var rscale: float = float(rstats.get("fate_scale", 1.0))
	if rscale > 1.0:
		_body.scale = Vector2(rscale, rscale)

	# 遍历根节点的槽位（MOUNT/MUZZLE/MAGAZINE/BULLET），找 BULLET 类型节点
	for slot_type in AssemblyNode.SlotType.keys():
		var slot_child: AssemblyNode = root.slots[AssemblyNode.SlotType.get(slot_type)]
		if slot_child != null and slot_child.node_type == AssemblyNode.NodeType.BULLET:
			var bstats: Dictionary = slot_child.get_base_stats()
			var scale: float = float(bstats.get("fate_scale", 1.0))
			if scale > 1.0:
				_body.scale = Vector2(scale, scale)

	# 眼睛视觉（"加眼睛"卡片）
	if rstats.get("visual_has_eyes", false):
		var eye_count: int = int(rstats.get("visual_eyes", 2))
		_spawn_eyes(eye_count)
	for slot_type in AssemblyNode.SlotType.keys():
		var slot_child: AssemblyNode = root.slots[AssemblyNode.SlotType.get(slot_type)]
		if slot_child != null and slot_child.node_type == AssemblyNode.NodeType.BULLET:
			var bstats: Dictionary = slot_child.get_base_stats()
			if bstats.get("visual_has_eyes", false):
				var eye_count: int = int(bstats.get("visual_eyes", 2))
				_spawn_eyes(eye_count)

	# 脚视觉（"加脚"卡片）
	if rstats.get("visual_has_legs", false):
		var leg_count: int = int(rstats.get("visual_leg_count", 4))
		_spawn_legs(leg_count)
	for slot_type in AssemblyNode.SlotType.keys():
		var slot_child: AssemblyNode = root.slots[AssemblyNode.SlotType.get(slot_type)]
		if slot_child != null and slot_child.node_type == AssemblyNode.NodeType.BULLET:
			var bstats: Dictionary = slot_child.get_base_stats()
			if bstats.get("visual_has_legs", false):
				var leg_count: int = int(bstats.get("visual_leg_count", 4))
				_spawn_legs(leg_count)

## 生成眼睛子节点（CircleShape2D 小球）
func _spawn_eyes(count: int) -> void:
	for i in range(count):
		var eye: ColorRect = ColorRect.new()
		eye.name = "Eye_%d" % i
		eye.color = Color(1.0, 1.0, 0.2, 1.0)  # 黄色小圆点
		eye.size = Vector2(4, 4)
		# 眼睛分布在枪身中段
		var x_pos: float = -4.0 + i * 4.0
		eye.position = Vector2(x_pos, -6.0)
		_eyes.add_child(eye)

## 生成脚子节点（ColorRect 小矩形）
func _spawn_legs(count: int) -> void:
	for i in range(count):
		var leg: ColorRect = ColorRect.new()
		leg.name = "Leg_%d" % i
		leg.color = Color(0.6, 0.3, 0.1, 1.0)  # 棕色小脚
		leg.size = Vector2(3, 5)
		# 脚分布在枪身尾部
		var angle: float = (float(i) / float(count)) * TAU
		var radius: float = 8.0
		leg.position = Vector2(cos(angle) * radius - 8.0, sin(angle) * radius + 4.0)
		_legs.add_child(leg)

## 清理命运子节点容器
func _clear_fate_children(container: Node2D) -> void:
	for ch in container.get_children():
		ch.queue_free()

## 应用多边形形状
func _apply_shape(shape: Dictionary) -> void:
	if _body == null:
		return
	_body.polygon = shape.get("polygon", PackedVector2Array())
	_body.color = shape.get("color", Color.WHITE)
	# 轻微描边感：叠加一个稍暗的同样形状
	# （Godot Polygon2D 没有 stroke，用第二个 polygon 模拟）
	if shape.has("width"):
		var w: float = shape["width"]
		_body.scale = Vector2(1.0, 1.0)

## 每帧：跟随瞄准方向旋转 + 监听 weapon_tree 变化
func _process(delta: float) -> void:
	# 旋转跟随瞄准方向
	if _parent_player and _parent_player.has_method("get_aim_direction"):
		var aim_dir: Vector2 = _parent_player.get_aim_direction()
		if aim_dir.length_squared() > 0.001:
			rotation = aim_dir.angle()
	
	# 监听 weapon_tree 变化（如果枪型变了就刷新显示）
	if _weapon_tree and _weapon_tree.get_root():
		var root_name: String = _weapon_tree.get_root().node_name
		if root_name != _current_gun_name:
			_current_gun_name = root_name
			var shape: Dictionary = GUN_SHAPES.get(root_name, DEFAULT_SHAPE)
			_apply_shape(shape)
			_refresh_fate_visual()

## 武器射击回调 → 触发后坐力 + 枪口火焰
func _on_weapon_fired(_pos: Vector2, _dir: Vector2, _count: int) -> void:
	_trigger_recoil()
	_trigger_muzzle_flash()

## 后坐力：枪身向后一抖再弹回
func _trigger_recoil() -> void:
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_recoil_tween = create_tween()
	_recoil_tween.set_trans(Tween.TRANS_QUAD)
	# 后坐力：沿枪口反方向位移（世界坐标）
	var recoil_dir := Vector2.LEFT.rotated(rotation)
	var local_recoil := recoil_dir * -8.0
	_recoil_tween.tween_property(self, "position", local_recoil, 0.04)
	_recoil_tween.chain().tween_property(self, "position", Vector2.ZERO, 0.10)
	_is_recoiling = true
	_recoil_tween.chain().tween_callback(func(): _is_recoiling = false)

## 枪口火焰
func _trigger_muzzle_flash() -> void:
	if _muzzle_tween and _muzzle_tween.is_valid():
		_muzzle_tween.kill()
	_muzzle.visible = true
	# 枪口火焰应在枪管前端（local space X=10，在 WeaponAnchor 30px 偏移之后再向前 10px）
	# WeaponAnchor Marker2D 在 Player 30px 处，枪管终点约 X=30，枪口约 X=40
	# 但 Player.tscn 中 MuzzleFlash PointLight2D 在 Player 根部（非 WeaponAnchor 子节点），
	# 其 global_position = player.global_position + aim_dir * 38，两者保持一致需要 local X=10
	_muzzle.position = Vector2(10, 0)
	
	# 根据枪型选择不同火焰大小
	var muzzle_cfg: Dictionary = _get_muzzle_config()
	
	# 火焰形状：星形多边形
	var radius: float = muzzle_cfg.get("radius", 14.0)
	var pts: PackedVector2Array = _make_star_polygon(radius, muzzle_cfg.get("count", 6))
	_muzzle.polygon = pts
	_muzzle.color = muzzle_cfg.get("color", Color(1.0, 0.85, 0.3, 1.0))
	
	# 快速闪烁消失
	_muzzle_tween = create_tween()
	_muzzle_tween.set_parallel(true)
	_muzzle_tween.tween_property(_muzzle, "modulate:a", 0.0, muzzle_cfg.get("lifetime", 0.10))
	_muzzle_tween.chain().tween_callback(func():
		_muzzle.visible = false
		_muzzle.modulate.a = 1.0
	)

## 根据当前枪的 tags 匹配枪口配置
func _get_muzzle_config() -> Dictionary:
	if _weapon_tree == null or _weapon_tree.get_root() == null:
		return MUZZLE_PARTICLES.get("rifle", {})
	var tags: Array[String] = _weapon_tree.get_root().tags
	for tag in tags:
		if MUZZLE_PARTICLES.has(tag):
			return MUZZLE_PARTICLES[tag]
	# 回退到 rifle 默认
	return MUZZLE_PARTICLES.get("rifle", {})

## 生成星形多边形（用于枪口火焰）
func _make_star_polygon(radius: float, points: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var angle_step: float = TAU / float(points)
	for i in range(points):
		var angle: float = i * angle_step
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts

## 外部通知：武器切换（用于 Workshop / Workbench 换枪后强制刷新）
func refresh_weapon_display() -> void:
	_refresh_weapon_from_player()
