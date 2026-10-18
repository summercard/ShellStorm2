extends StaticBody3D
class_name SecretDoor3D

## 传送支线的隐藏门（支线秘密房间设计 §4.1 / §4.2）。
##
## 结构改成**两层**，与美术资产一一对应：
##
##   SecretDoor3D                  ← 本节点（StaticBody3D，只持有木板层碰撞）
##   ├─ DoorLeaf                   ← 常驻：门框 + 门腔 + 单扇半掩门 + 腔内自发光
##   ├─ Boards                     ← 可拆：5 横板 + 2 斜撑 + 19 钉
##   └─ BoardsShape                ← 木板层碰撞；打掉时只关这一层
##
## 为什么是两层而不是一块板：
##   原实现是一块不透明板，破开后整体消失 —— 破完只剩空气，玩家不知道自己
##   刚打掉了什么。改成「木板钉在门上」之后，破板 = 露出后面那扇本该在的门，
##   里面还有光透出来。这样谜题读得懂：**有人把门钉死了，但门后有人/有东西**。
##
## 为什么脚本挂在 StaticBody3D 上而不是父节点：
##   `Projectile3D._hit_target()` 与近战扇区查询拿到的 collider 是**碰撞体节点本身**，
##   它们直接对 collider 调 `take_damage()`。脚本挂在父节点会收不到伤害。
##
## 坐标系：两件资产共用装配系，原点在**地面、门洞中心**，Y=0 是房间侧墙面
##   （Blender +Y → Godot -Z）。木板朝 -Z 凸向房间，门腔朝 +Z 凹进墙里。
##   因此挂载时把节点放在位点的**地面点**，并让 -Z 对齐位点的 outward 法线。
##
## 交互：木板**一直在**（不等清房才出现，清房只决定能不能打）。破板后走到门口，
##   出现与「搜索容器」同一个白点与「(e) 进入暗门」按键牌，**按 E 才瞬移**。

signal broken(site_id: String)
## 锁定状态下的受击反馈。设计 §5.2：未清房时「打上去有金属声、不掉血」——
## 需要一个信号让上层播音效，而不是让玩家以为「这面墙只是硬」。
signal hit_locked(site_id: String)
## 玩家在门前按下 E（`PlayerInteractionController3D`）时发出。
##
## 为什么不由门自己改坐标：瞬移要考虑清速度、落点房间的进入流程、加载点重建，
## 那是 `SecretBranch3D` 的事。门只负责「谁在什么时候请求了传送」。
signal teleport_requested(site_id: String, player: Node3D)

enum State { SEALED, BROKEN }

const DOOR_LEAF_SCENE := preload(
	"res://assets/art/environments/tower_zones/expedition/runtime/common_components/secret_door_leaf/secret_door_leaf_root_top3d.tscn"
)
const BOARDS_SCENE := preload(
	"res://assets/art/environments/tower_zones/expedition/runtime/common_components/secret_door_boards/secret_door_boards_root_top3d.tscn"
)

## 洞口净宽（m）。与 office_room/door_wall 门洞一致。
const OPENING_W_M := 2.2
## 洞口净高（m）。
const OPENING_H_M := 2.5
## 木板层碰撞厚度（m）。木板本体 0.139 起于 Y=0，碰撞取略厚以吞掉斜撑与钉子。
const BOARDS_COLLISION_D_M := 0.16
## 破碎后延迟多久关闭碰撞（秒）。给一次命中反馈的时间，不做破碎物理。
const BREAK_COLLISION_DELAY_S := 0.08
## 交互距离（m）。与 `InteractionDot3D.APPROACH_NEAR_DISTANCE_M` 同值 ——
## 「站到能按 E 的距离」正是圆点长到满尺寸的那一圈，两者不能各写一个数。
const INTERACT_RANGE_M := 2.6
## 交互圆点锚点（门节点局部系）。抬到门洞中部、往房间侧（-Z）挪 0.35m，
## 让白点落在门扇前而不是埋进墙里。与门框 2.5m 净高对齐。
##
## 不会被门叶挡住：门叶是往**门腔里**（+Z，墙内）开 45° 的（见
## `tools/blender/build_secret_door_v001.py` 的 LEAF_OPEN_DEG），房间侧看到的是
## 「门往墙里敞着」，圆点站在它前面。
const DOT_ANCHOR_LOCAL := Vector3(0.0, 1.5, -0.35)

## 位点身份：与关卡数据 `secret_site.site_id` 同值，用于存档与诊断。
var site_id := ""
## 配对序号：同一 pair_id 的 entry / exit 属于同一条支线。
var pair_id := -1
## "entry" / "exit" / "extraction" / "return"（`return` = 常开返程门）
var role := ""
## 木板层受击提亮用的基准色，取木板色系。仅在程序化兜底路径使用。
var panel_color := Color(0.28, 0.17, 0.08)

var state: int = State.SEALED
var max_hp := 60
var hp := 60
## 锁定：存在但打不动（入口房未清 / 撤离门未达阈值时就锁着）。
## 锁定只影响 `take_damage`，不影响显示 —— 木板照样看得见，玩家知道「这里有东西」，
## 但打不开。这是设计 §5.2 要的：线索给到，门不给。
var _locked := false

var _door_leaf: Node3D = null
var _boards: Node3D = null
var _shape: CollisionShape3D = null
var _fallback_mesh: MeshInstance3D = null
var _broken_emitted := false
var _hit_count := 0
## 传送落点（世界坐标）与提示动词。由 `SecretBranch3D` 装配时下发：
## 入口门 → 子图首间、出口门 → 子图末间、末端门/撤离返程门 → 上一站。
var _teleport_target := Vector3.ZERO
var _teleport_verb := ""
var _has_teleport := false


func _ready() -> void:
	# 交互圆点由 `PlayerInteractionController3D` 按组统一创建与驱动，
	# 门只实现候选/聚焦/执行三件套，不自己读 E 键。
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)


## 由 `SecretBranch3D` 在装配时调用。`hp_value` 按已清房数算，见设计 §4.1：
## `HP = 60 + 20 × 已清内容房数`。
func configure(site: Dictionary, hp_value: int) -> void:
	site_id = str(site.get("site_id", ""))
	pair_id = int(site.get("pair_id", -1))
	role = str(site.get("role", ""))
	max_hp = maxi(1, hp_value)
	hp = max_hp
	_build_visual(true)
	_build_collision()


## 无木板的「常开门」：子图末端的返程门、撤离房的返程门用它。
##
## 这两处不是谜题，是**路**：玩家已经在一间空房里，不该再让他打掉 60+ 血的板才能出去。
## 复用同一件门叶资产，是为了让「通到哪里」看起来一致 —— 主图那边是钉死的门，
## 子图这边是开着的同一扇门。
func configure_portal(site: Dictionary, verb: String, target: Vector3) -> void:
	site_id = str(site.get("site_id", ""))
	pair_id = int(site.get("pair_id", -1))
	role = str(site.get("role", ""))
	_build_visual(false)
	state = State.BROKEN
	_locked = false
	# 没有木板层就没有可挡的东西；门洞本身由房间墙件负责（这里只是墙面上的一扇门）。
	collision_layer = 0
	collision_mask = 0
	# 常开门没有「刚被打破」这件事，别在读档重放时补发一次 broken。
	_broken_emitted = true
	set_teleport_target(target, verb)


## 门叶常驻、木板可拆。两者缺任一个都退回程序化单板，避免关卡因资产缺失开不了。
## `with_boards = false` 时只建门叶（常开门，见 `configure_portal`）。
func _build_visual(with_boards: bool = true) -> void:
	if _door_leaf != null or _fallback_mesh != null:
		return
	if DOOR_LEAF_SCENE != null and BOARDS_SCENE != null:
		_door_leaf = DOOR_LEAF_SCENE.instantiate() as Node3D
		_door_leaf.name = "DoorLeaf"
		add_child(_door_leaf)
		if with_boards:
			_boards = BOARDS_SCENE.instantiate() as Node3D
			_boards.name = "Boards"
			add_child(_boards)
		return
	# 资产缺失：只有谜题门才需要一块兜底板；常开门没有板要挡，直接留空。
	if with_boards:
		_build_fallback_panel()


func _build_fallback_panel() -> void:
	_fallback_mesh = MeshInstance3D.new()
	_fallback_mesh.name = "Panel"
	var box := BoxMesh.new()
	box.size = Vector3(OPENING_W_M, OPENING_H_M, BOARDS_COLLISION_D_M)
	_fallback_mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = panel_color
	material.roughness = 0.85
	material.metallic = 0.0
	_fallback_mesh.material_override = material
	_fallback_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# 程序化板从墙面往房间侧凸出半厚，与资产装配系对齐。
	_fallback_mesh.position = Vector3(0.0, OPENING_H_M * 0.5, -BOARDS_COLLISION_D_M * 0.5)
	add_child(_fallback_mesh)


## 碰撞只覆盖木板层。门叶（门框）在 2.2m 洞口之外，不参与碰撞 ——
## 洞口本身的可通行性由房间墙件保证，木板是唯一的额外阻挡。
func _build_collision() -> void:
	if _shape != null:
		return
	_shape = CollisionShape3D.new()
	_shape.name = "BoardsShape"
	var box := BoxShape3D.new()
	box.size = Vector3(OPENING_W_M, OPENING_H_M, BOARDS_COLLISION_D_M)
	_shape.shape = box
	_shape.position = Vector3(0.0, OPENING_H_M * 0.5, -BOARDS_COLLISION_D_M * 0.5)
	add_child(_shape)
	# 木板是静态阻挡，玩家与子弹都会被它挡住；破开后关闭这一层。
	collision_layer = 1
	collision_mask = 0


## 子弹与近战共用的受击入口（`Projectile3D._hit_target` 走这里）。
## 签名必须与 `Enemy3D.take_damage` 兼容：多出的参数一律忽略。
func take_damage(damage: int, _critical: bool = false, _direction: Vector3 = Vector3.ZERO, _knockback: float = 0.0) -> void:
	if state != State.SEALED or damage <= 0:
		return
	if _locked:
		# 锁定态：不掉血、不破，只发一次「打不动」的信号。
		# 不在这里做提亮 —— 提亮会让玩家以为快打穿了，而它其实一点没掉。
		hit_locked.emit(site_id)
		return
	_hit_count += 1
	hp = maxi(0, hp - damage)
	_flash()
	if hp <= 0:
		_break_open()


## 锁定/解锁。锁定态木板仍可见，但打不动。
func set_locked(value: bool) -> void:
	if state == State.BROKEN:
		_locked = false
		return
	_locked = value


func is_locked() -> bool:
	return _locked


## 破板：只拆木板层。门叶留在原地 —— 这正是「打掉木板露出门」的表达。
func _break_open() -> void:
	if state == State.BROKEN:
		return
	state = State.BROKEN
	var visual: Node3D = _boards if _boards != null else _fallback_mesh
	if visual != null:
		var tween := create_tween()
		tween.tween_property(visual, "scale", Vector3(1.04, 1.04, 1.0), 0.06)
		tween.tween_property(visual, "scale", Vector3(0.01, 0.01, 1.0), 0.10)
		tween.tween_callback(func() -> void:
			if is_instance_valid(visual):
				visual.visible = false
		)
	# 碰撞立刻失效：破开后玩家应当马上能走过去，不等动画。
	if _shape != null:
		_shape.set_deferred("disabled", true)
	collision_layer = 0
	_emit_broken_once()


func _emit_broken_once() -> void:
	if _broken_emitted:
		return
	_broken_emitted = true
	broken.emit(site_id)


## 受击反馈：木板短暂提亮，说明「这层能打」。门叶不参与反馈 —— 打的是钉子板。
func _flash() -> void:
	var material := _flashable_board_material()
	if material == null:
		return
	var base := material.albedo_color
	material.albedo_color = base.lerp(Color(1.0, 0.86, 0.62), 0.45)
	var tween := create_tween()
	tween.tween_property(material, "albedo_color", base, 0.12)


## 取木板层"木板主体"那个表面的可改色材质。
##
## 不能用 `material_override`：那是**整件覆盖**，会把钉子所在的金属表面一起
## 换成木板的哑光材质 —— 第一次实现就踩了这个坑，打一下钉子就变成木头。
## 正确做法是复制 mesh，把每个 surface 的材质各自复制一份，只把索引 0
## （木板主体）那份交出去改色；钉子保留原来的金属材质。
func _flashable_board_material() -> BaseMaterial3D:
	var host: Node = _boards if _boards != null else _fallback_mesh
	if host == null:
		return null
	var mesh_instance := _find_first_mesh_instance(host)
	if mesh_instance == null or mesh_instance.mesh == null:
		return null
	if mesh_instance.get_meta("flash_ready", false):
		return mesh_instance.mesh.surface_get_material(0) as BaseMaterial3D
	var mesh := mesh_instance.mesh.duplicate() as Mesh
	if mesh == null:
		return null
	for surface_index in range(mesh.get_surface_count()):
		var source := mesh.surface_get_material(surface_index)
		if source != null:
			mesh.surface_set_material(surface_index, source.duplicate())
	mesh_instance.mesh = mesh
	mesh_instance.set_meta("flash_ready", true)
	return mesh.surface_get_material(0) as BaseMaterial3D


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null


## 存档：存「破没破」与「锁没锁」，不存血量 —— 血量为中间态，恢复到破碎或完好即可。
## 锁定状态必须存：否则读档后入口木板会在入口房还没清的时候就变成可破。
func export_state() -> Dictionary:
	return {
		"site_id": site_id,
		"pair_id": pair_id,
		"role": role,
		"broken": state == State.BROKEN,
		"locked": _locked,
	}


func restore_state(snapshot: Dictionary) -> void:
	if bool(snapshot.get("broken", false)):
		open_silently()
		return
	_locked = bool(snapshot.get("locked", _locked))


## 静默打开：直接落到「木板已拆、门开着」，不播破板动画、不发受击反馈。
##
## 两处用它：① 读档恢复到破碎态；② 玩家从子图穿回主图时，出口侧那扇**同源的木板门**
## 必须一起打开 —— 人刚从这扇门穿出来，回头看它却还是钉死的，说不通。
func open_silently() -> void:
	if state == State.BROKEN:
		return
	state = State.BROKEN
	_locked = false
	if _shape != null:
		_shape.set_deferred("disabled", true)
	collision_layer = 0
	var visual: Node3D = _boards if _boards != null else _fallback_mesh
	if visual != null:
		visual.visible = false
	_emit_broken_once()


func is_broken() -> bool:
	return state == State.BROKEN


# ============================================================================
# 传送交互（按 E，不是踩上去就走）
# ----------------------------------------------------------------------------
# 业主 2026-10-18 定稿：**门板一直在，不用等清房才出现**；破板后走到门口，
# 出现与「搜索容器」同一个白点，站到能按 E 的距离按 E 才瞬移。
#
# 为什么改掉「踩进 Area3D 就传送」：
#   门装在墙面上，触发盒必然有一半探进房间 —— 玩家贴着墙走就会被吸走，
#   既不知道发生了什么，也没法拒绝。按 E 把「要不要过去」交回玩家，
#   提示也统一到全场唯一那套圆点上。
# ============================================================================

## 传送落点与提示动词（`verb` 形如「进入暗门」「返回主路」）。
## 动词只在这里存一份：圆点按键牌从 `prompt` 文案里抽（见
## `InteractionDot3D.extract_action_verb`），不另立动词表。
func set_teleport_target(target: Vector3, verb: String) -> void:
	_teleport_target = target
	_teleport_verb = verb
	_has_teleport = not verb.is_empty()


func get_teleport_target() -> Vector3:
	return _teleport_target


## 能不能传送：门开着 **且** 已经下发落点。木板还在时按 E 什么也不该发生 ——
## 圆点不显示、候选为空，玩家看到的就是一扇钉死的门。
func can_teleport() -> bool:
	return _has_teleport and state == State.BROKEN


## 交互协议（`PlayerInteractionController3D.PROVIDER_GROUP`）。
func get_interaction_candidate(player: Player3D) -> Dictionary:
	if not can_teleport() or player == null or not is_instance_valid(player):
		return {}
	if player.global_position.distance_to(global_position) > INTERACT_RANGE_M:
		return {}
	return {
		"available": true,
		"interaction_id": "secret_door:%s" % site_id,
		"position": get_interaction_dot_anchor(),
		# 低于撤离信标（100）、高于家具（10）：贴着门站定时，门优先。
		"priority": 90,
		"prompt": "[E] %s" % _teleport_verb,
	}


## 文字提示牌不建：本作的可交互物统一用圆点 + 按键牌，圆点下方会显示「(e) 进入暗门」。
func set_interaction_focus(_candidate: Dictionary, _focused: bool) -> void:
	pass


func get_interaction_dot_anchor() -> Vector3:
	return to_global(DOT_ANCHOR_LOCAL)


## 圆点只在门开了之后出现。木板完好时挂一个「按 E」的圆点等于骗人 ——
## 那扇门此刻打不开（设计 §5.2：锁定态木板照常显示，但打不动）。
func is_interaction_dot_visible() -> bool:
	return can_teleport()


func perform_interaction(player: Player3D, _candidate: Dictionary) -> bool:
	if not can_teleport() or player == null or not is_instance_valid(player):
		return false
	# 复检距离：候选是每帧算的，但按下 E 之前玩家可能已经走开了一步。
	if player.global_position.distance_to(global_position) > INTERACT_RANGE_M:
		return false
	teleport_requested.emit(site_id, player)
	return true


## 供验收与诊断：门叶是否常驻可见、木板层是否还在。
func debug_snapshot() -> Dictionary:
	return {
		"site_id": site_id,
		"state": state,
		"locked": _locked,
		"hp": hp,
		"max_hp": max_hp,
		"has_door_leaf": _door_leaf != null,
		"door_leaf_visible": _door_leaf != null and _door_leaf.visible,
		"has_boards": _boards != null,
		"boards_visible": (_boards != null and _boards.visible) if _boards != null
			else (_fallback_mesh != null and _fallback_mesh.visible),
		"collision_layer": collision_layer,
		"can_teleport": can_teleport(),
		"teleport_verb": _teleport_verb,
		"teleport_target": _teleport_target,
	}
