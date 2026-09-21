class_name NarrativeAdapter3D
extends RefCounted
## 剧情系统与场景之间的**唯一耦合点**。剧情的每一条 cue 都经这里转发。
##
## 纪律（机器可查，见 08 文档 §5.4 与 §11）：
##   · 本文件**不得出现任何节点路径字面量**（`get_node("...")` / `"../Player3D"` 之类）。
##     目标一律靠**分组**（`player_3d`）与**反射式鸭子类型**（`has_method` / `has_signal` /
##     `get()` / `call()`）取得。验收脚本用正则扫 src/narrative/** 命中即红。
##   · 换场景只改本文件，剧本 JSON 一字不动。
##   · 本文件**不实现任何表现**：动画归角色系统、特效归 VfxPool、文字归 DialogueUI。
##
## 每条的返回： {"ok": bool, "degraded": bool, "reason": String, "restore": Callable}
##   · ok=false 且 degraded=true  → 该条跳过并告警，**时间轴照走**（08 文档 §5.3）
##   · restore 非空 → 交导演登记进占用清单，收口时无条件归还（08 文档 §6.1）

## 相机从「接管前位姿」到「叙事位姿」的过渡由本类逐帧推算。
## 关键：**不硬编码任何相机高度/构图常量** —— 接管瞬间抓一次真实位姿当基准，
## 叙事只改「距离」「绕枢轴的方位」「俯角」与「枢轴点」，相对构图完全继承，
## 这样叙事镜头与玩法镜头永远同一套构图语言。
## 枢轴默认 = 玩家（焦点钉在主角身上）。要「脱开主角、整台机位平移过去拍别处」，
## 给 camera.focus / camera.pan 写 `pivot: last_spawn|room_center` 或 `pivot_m: [x,y,z]`。
## ⚠ 俯角必须**显式**给 `elevation_deg` 才会变 —— 只改距离的运镜只是沿同一条轴滑动，
## 观感是"推近拉远"，不是"镜头从上往下压"（实测差异极大，见 08 文档 §5.2）。
const CAMERA_MIN_DISTANCE_M := 2.0

var _tree: SceneTree = null
var _dungeon: Node = null
var _room_index: Dictionary = {}
var _room_index_scene: Node = null

# —— 相机接管状态 ——
var _camera_override_active := false
var _camera: Camera3D = null
var _camera_rest_basis := Basis.IDENTITY
var _camera_rest_offset := Vector3.ZERO
var _camera_rest_global := Transform3D.IDENTITY
var _camera_channel := {}          # 距离通道 {from, to, t, duration}
var _camera_yaw_channel := {}      # 方位通道（度）{from, to, t, duration}
var _camera_elev_channel := {}     # 仰角通道（度）{from, to, t, duration}
var _camera_rest_elevation_deg := 0.0  # 接管前那套俯角（度），elevation_deg 的缺省值

# —— 运镜枢轴（2026-09-21）：默认钉在玩家身上，可脱开去拍别处 ——
var _camera_pivot_channel := {}   # 枢轴通道（Vector3）{from, to, t, duration, value}
var _camera_pivot_mode := "player"  # player / last_spawn / room_center / point
var _camera_pivot_point := Vector3.ZERO  # mode=point（pivot_m）时的显式坐标
var _camera_pivot_room_id := ""  # mode=room_center 时用哪个房间
var _has_last_spawn := false      # 是否已经有过 scene.spawn
var _last_spawn_origin := Vector3.ZERO  # 最近一次剧情刷怪的队列中心

# —— 逐帧持续生效的接管项（朝向） ——
var _facing_active := false
var _facing_channel := {}          # {from, to, t, duration}
var _facing_yaw := 0.0
var _facing_base_yaw := 0.0        # 本条 face 序列的基准朝向（进入序列时抓一次，见 _actor_face）

# —— 逐帧持续生效的接管项（叙事姿态的相位过渡：起身 / 倒地）——
var _pose_active := false
var _pose_clip := ""
var _pose_channel := {}            # {from, to, t, duration, value}（相位 0..1）

# —— 输入独占 ——
## 演出期间玩家输入由导演持权。Dungeon3D 每帧都会 _sync_player_input_lock()
## 重算一次 input_locked，它必须问这里（is_player_input_locked），
## 否则"角色停住"会被逐帧顶掉，且运行时毫无报错。
var _player_input_taken := false


func bind(tree: SceneTree) -> void:
	_tree = tree


## 导演每帧调用：推进相机与朝向的过渡并落到场景上。
func tick(delta: float) -> void:
	if _camera_override_active:
		_advance_channel(_camera_channel, delta)
		_advance_channel(_camera_yaw_channel, delta)
		_advance_channel(_camera_elev_channel, delta)
		var pivot_done := _advance_vector_channel(_camera_pivot_channel, delta)
		# 枢轴平滑落回玩家后清空通道 ⇒ 焦点重新「实时跟随玩家」，与接管前一字不差
		# （否则会钉在那一刻的玩家位置快照上）。
		if pivot_done and _camera_pivot_mode == "player":
			_camera_pivot_channel = {}
		_apply_camera_pose()
	if _facing_active:
		_advance_channel(_facing_channel, delta)
		_apply_facing()
	if _pose_active:
		var pose_finished := _advance_channel(_pose_channel, delta)
		_apply_pose()
		if pose_finished:
			_end_pose_transition()


## 与 _advance_channel 同构，但值是 Vector3 —— 枢轴要能做空间位移，不能只 lerpf。
func _advance_vector_channel(channel: Dictionary, delta: float) -> bool:
	if channel.is_empty():
		return false
	var duration := float(channel.get("duration", 0.0))
	var elapsed := float(channel.get("t", 0.0)) + delta
	channel["t"] = elapsed
	var to: Vector3 = channel.get("to", Vector3.ZERO)
	if duration <= 0.0:
		channel["value"] = to
		return true
	var weight := clampf(elapsed / duration, 0.0, 1.0)
	var from: Vector3 = channel.get("from", Vector3.ZERO)
	channel["value"] = from.lerp(to, weight)
	return weight >= 1.0


func _advance_channel(channel: Dictionary, delta: float) -> bool:
	if channel.is_empty():
		return false
	var duration := float(channel.get("duration", 0.0))
	var elapsed := float(channel.get("t", 0.0)) + delta
	channel["t"] = elapsed
	if duration <= 0.0:
		channel["value"] = float(channel.get("to", 0.0))
		return true
	var weight := clampf(elapsed / duration, 0.0, 1.0)
	channel["value"] = lerpf(float(channel.get("from", 0.0)), float(channel.get("to", 0.0)), weight)
	return weight >= 1.0


# =========================================================================
# 目标解析（全部反射式，无路径字面量）
# =========================================================================

func player_node() -> Node3D:
	if _tree == null:
		return null
	return _tree.get_first_node_in_group("player_3d") as Node3D


func dungeon_node() -> Node:
	if _tree == null:
		return null
	if _dungeon != null and is_instance_valid(_dungeon):
		return _dungeon
	var scene := _tree.current_scene
	if scene != null and scene.has_signal("room_entered"):
		_dungeon = scene
	return _dungeon


## 房间索引：按 `room_id` 属性在场景树里反射式收集，按场景根缓存。
## 用遍历而不是路径字面量 —— 楼层/房间是运行时生成的，路径本来就不稳定。
func room_node(room_id: String) -> Node3D:
	if room_id.is_empty():
		return null
	var scene := _tree.current_scene if _tree != null else null
	if scene == null:
		return null
	if _room_index_scene != scene:
		_room_index_scene = scene
		_room_index = {}
		_collect_rooms(scene)
	return _room_index.get(room_id, null) as Node3D


func _collect_rooms(node: Node) -> void:
	var room_id_value: Variant = node.get("room_id")
	if room_id_value is String and not (room_id_value as String).is_empty() and node is Node3D:
		if node.has_method("contains_world_position"):
			_room_index[room_id_value as String] = node
	for child in node.get_children():
		_collect_rooms(child)


## 在房间子树里找第一个满足判定的节点（门、灯开关都是房间的可选成员）。
func _find_in_room(room: Node, method_name: String) -> Node:
	if room == null:
		return null
	if room.has_method(method_name):
		return room
	for child in room.get_children():
		if child.has_method(method_name):
			return child
	return null


func _all_in_room(room: Node, method_name: String) -> Array:
	var found: Array = []
	if room == null:
		return found
	if room.has_method(method_name):
		found.append(room)
	for child in room.get_children():
		if child.has_method(method_name):
			found.append(child)
	return found


# =========================================================================
# 指令派发
# =========================================================================

## 适配器自己的告警口。与导演的 _warn 同义：**只用于错用/接线缺口**
## （例如 camera.pivot 写错），不影响时间轴照走；正常路径一声不响。
func _warn(message: String) -> void:
	push_warning("[NarrativeAdapter3D] %s" % message)


static func _ok() -> Dictionary:
	return {"ok": true, "degraded": false, "reason": "", "restore": Callable()}


static func _degraded(reason: String) -> Dictionary:
	return {"ok": false, "degraded": true, "reason": reason, "restore": Callable()}


static func _failed(reason: String) -> Dictionary:
	return {"ok": false, "degraded": false, "reason": reason, "restore": Callable()}


static func _done(restore: Callable) -> Dictionary:
	return {"ok": true, "degraded": false, "reason": "", "restore": restore}


## 派发一条指令。`verb` = 『域.动作』。
func call_instruction(verb: String, params: Dictionary) -> Dictionary:
	var parts := verb.split(".", false, 1)
	if parts.size() != 2:
		return _failed("指令『%s』不是『域.动作』形式。" % verb)
	return dispatch(parts[0], parts[1], params)


func dispatch(domain: String, action: String, params: Dictionary) -> Dictionary:
	match domain:
		"player":
			return _player_instruction(action, params)
		"camera":
			return _camera_instruction(action, params)
		"actor":
			return _actor_instruction(action, params)
		"fx":
			return _fx_instruction(action, params)
		"ui":
			return _ui_instruction(action, params)
		"scene":
			return _scene_instruction(action, params)
		"grant":
			return _grant_instruction(action, params)
	return _failed("未知指令域『%s』。" % domain)


# -------------------------------------------------------------------------
# player
# -------------------------------------------------------------------------

func _player_instruction(action: String, params: Dictionary) -> Dictionary:
	match action:
		"lock_input":
			return _player_lock_input(params)
		"combat":
			return _player_combat(params)
		"invulnerable":
			return _player_invulnerable(params)
		"teleport":
			return _player_teleport(params)
	return _degraded("player.%s 尚未接通（见 08 文档 §5.2 指令表）。" % action)


func _player_lock_input(params: Dictionary) -> Dictionary:
	var player := player_node()
	if player == null:
		return _degraded("player.lock_input：找不到玩家（分组 player_3d）。")
	if not player.has_method("set_input_locked"):
		return _degraded("player.lock_input：玩家没有 set_input_locked()。")
	var locked := bool(params.get("locked", true))
	if locked:
		# 只登记「叙事持有输入」，**不记录接管前的值**：开场页 / 背包 / 模态各自也会改
		# input_locked，把它们的中间态当成"原值"存下来，归还时就变成替它们做决定。
		# 实测反例：开场页 present() 先锁 → 剧情记下 before=true → 收口把玩家永久锁死，
		# 键盘与开枪全废、鼠标仍能转向，且运行时零报错。
		_player_input_taken = true
		player.call("set_input_locked", true)
	else:
		_release_player_input()
	return _done(Callable(self, "_release_player_input"))


## 演出是否正在独占玩家输入。被 Dungeon3D 的锁同步查询（08 文档 §5.5）。
func is_player_input_locked() -> bool:
	return _player_input_taken


## 朝向是否由叙事接管（actor.face 生效期间）。Player3D 的鼠标瞄准必须问这里让位。
func is_actor_facing_overridden() -> bool:
	return _facing_active


## 归还入口：交回独占权，再请游戏侧**重新裁决**一次 —— 模态 / 背包 / 开场页各自的
## 需求都要重新算进去。绝不写回快照值：写回快照 = 替别的系统做决定。
func _release_player_input() -> void:
	_player_input_taken = false
	var dungeon := dungeon_node()
	if dungeon != null and dungeon.has_method("refresh_player_input_lock"):
		dungeon.call("refresh_player_input_lock")
		return
	var player := player_node()
	if player != null and player.has_method("set_input_locked"):
		player.call("set_input_locked", false)


func _player_combat(params: Dictionary) -> Dictionary:
	var player := player_node()
	if player == null:
		return _degraded("player.combat：找不到玩家。")
	var enabled := bool(params.get("enabled", false))
	var before := bool(player.get("combat_enabled"))
	if not player.has_method("set_combat_enabled"):
		return _degraded("player.combat：玩家没有 set_combat_enabled()。")
	player.call("set_combat_enabled", enabled)
	return _done(Callable(self, "_player_combat").bind({"enabled": before}))


func _player_invulnerable(params: Dictionary) -> Dictionary:
	var player := player_node()
	if player == null:
		return _degraded("player.invulnerable：找不到玩家。")
	# Player3D 已有 is_invincible 开关（take_damage 首行即 `if current_hp <= 0 or is_invincible: return`），
	# 因此这一条不需要给玩家系统加新接口，只需占用 + 归还。
	var enabled := bool(params.get("enabled", true))
	var before := bool(player.get("is_invincible"))
	player.set("is_invincible", enabled)
	return _done(Callable(self, "_player_invulnerable").bind({"enabled": before}))


func _player_teleport(params: Dictionary) -> Dictionary:
	var player := player_node()
	if player == null:
		return _degraded("player.teleport：找不到玩家。")
	var point: Variant = params.get("point", null)
	if point is Array and (point as Array).size() == 3:
		var coordinates: Array = point
		point = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
	var at_room := str(params.get("at_room", ""))
	if not (point is Vector3) and at_room.is_empty():
		return _failed("player.teleport 需要 point 或 at_room。")
	var origin := Vector3.ZERO
	if point is Vector3:
		origin = point
	else:
		var room := room_node(at_room)
		if room == null:
			return _degraded("player.teleport：房间『%s』不存在。" % at_room)
		origin = room.global_position
	var before := player.global_position
	player.global_position = origin
	return _done(Callable(self, "_teleport_restore").bind({"point": before}))


func _teleport_restore(argument: Dictionary) -> void:
	var player := player_node()
	if player != null:
		player.global_position = argument.get("point", Vector3.ZERO)


# -------------------------------------------------------------------------
# camera
# -------------------------------------------------------------------------

func is_camera_override_active() -> bool:
	return _camera_override_active


func _camera_instruction(action: String, params: Dictionary) -> Dictionary:
	match action:
		"focus":
			return _camera_focus(params)
		"pan":
			return _camera_pan(params)
		"restore":
			return _camera_restore(params)
	return _degraded("camera.%s 尚未接通（见 08 文档 §5.2 指令表）。" % action)


func _ensure_camera_override() -> bool:
	if _camera_override_active:
		return _camera != null and is_instance_valid(_camera)
	var player := player_node()
	if player == null:
		return false
	var camera_value: Variant = player.get("camera")
	if not (camera_value is Camera3D) or not is_instance_valid(camera_value):
		return false
	var camera := camera_value as Camera3D
	if not camera.is_inside_tree():
		return false
	_camera = camera
	_camera_rest_global = camera.global_transform
	_camera_rest_basis = camera.global_basis
	_camera_rest_offset = camera.global_position - player.global_position
	# 接管前那套俯角：elevation_deg 不给时沿用它，保证「只改距离」的老行为一字不变。
	_camera_rest_elevation_deg = rad_to_deg(
		atan2(
			_camera_rest_offset.y,
			Vector2(_camera_rest_offset.x, _camera_rest_offset.z).length()
		)
	)
	_camera_pivot_channel = {}
	_camera_pivot_mode = "player"
	_camera_override_active = true
	return true


func _camera_focus(params: Dictionary) -> Dictionary:
	if not _ensure_camera_override():
		return _degraded("camera.focus：拿不到玩家相机，本镜头的运镜被跳过。")
	var target_distance := maxf(CAMERA_MIN_DISTANCE_M, float(params.get("distance", _camera_rest_offset.length())))
	var duration := maxf(0.0, float(params.get("duration", 0.6)))
	_apply_camera_pivot_params(params, duration)
	_camera_channel = {
		"from": _camera_distance(), "to": target_distance, "t": 0.0, "duration": duration,
		"value": _camera_distance(),
	}
	# 仰角通道：**显式给 elevation_deg 才建** —— 这是「镜头从上往下压」的唯一正确做法。
	# 只改 distance 不改仰角，镜头只会沿同一条轴滑动，看上去只是拉近拉远、不叫俯冲。
	if params.has("elevation_deg"):
		_camera_elev_channel = {
			"from": _camera_elev_deg(),
			"to": float(params.get("elevation_deg", _camera_rest_elevation_deg)),
			"t": 0.0, "duration": duration, "value": _camera_elev_deg(),
		}
	# 登记归还：收口时必须把相机位姿还原并放权给玩法镜头，否则玩家永久被钉在叙事机位上。
	return _done(Callable(self, "release_camera_override"))


func _camera_pan(params: Dictionary) -> Dictionary:
	if not _ensure_camera_override():
		return _degraded("camera.pan：拿不到玩家相机，本镜头的运镜被跳过。")
	var target_yaw := float(params.get("yaw_deg", 0.0))
	var duration := maxf(0.0, float(params.get("duration", 0.6)))
	_apply_camera_pivot_params(params, duration)
	_camera_yaw_channel = {
		"from": _camera_yaw_deg(), "to": target_yaw, "t": 0.0, "duration": duration,
		"value": _camera_yaw_deg(),
	}
	# 平移默认只绕竖轴甩（老行为一字不变）。**要俯冲就得另给 elevation_deg** ——
	# 与 camera.focus 同一套仰角通道，只是不改距离。
	# 缺席时通道保持为空 = 俯角沿用接管前那套，所以老剧本不会被动到。
	if params.has("elevation_deg"):
		_camera_elev_channel = {
			"from": _camera_elev_deg(),
			"to": float(params.get("elevation_deg", _camera_rest_elevation_deg)),
			"t": 0.0, "duration": duration, "value": _camera_elev_deg(),
		}
	# 同上：运镜也是一种占用，必须登记归还。
	return _done(Callable(self, "release_camera_override"))


func _camera_restore(params: Dictionary) -> Dictionary:
	if not _camera_override_active:
		return _ok()
	var duration := maxf(0.0, float(params.get("duration", 0.6)))
	# 回镜必须把**枢轴**也带回玩家：否则机位会绕着一个远处的点收镜，最后再「跳」回玩家。
	var restore_player := player_node()
	if restore_player != null:
		var pivot_from := _current_camera_pivot(restore_player)
		_camera_pivot_mode = "player"
		_camera_pivot_channel = {
			"from": pivot_from, "to": restore_player.global_position, "t": 0.0,
			"duration": duration, "value": pivot_from,
		}
	_camera_channel = {
		"from": _camera_distance(), "to": _camera_rest_offset.length(),
		"t": 0.0, "duration": duration, "value": _camera_distance(),
	}
	_camera_yaw_channel = {
		"from": _camera_yaw_deg(), "to": 0.0, "t": 0.0, "duration": duration,
		"value": _camera_yaw_deg(),
	}
	# 回镜必须连俯角一起回，否则收口瞬间会从叙事俯角"跳"回玩法俯角。
	_camera_elev_channel = {
		"from": _camera_elev_deg(), "to": _camera_rest_elevation_deg,
		"t": 0.0, "duration": duration, "value": _camera_elev_deg(),
	}
	return _done(Callable(self, "release_camera_override"))


func _camera_distance() -> float:
	if _camera_channel.is_empty():
		return _camera_rest_offset.length()
	return float(_camera_channel.get("value", _camera_rest_offset.length()))


func _camera_yaw_deg() -> float:
	if _camera_yaw_channel.is_empty():
		return 0.0
	return float(_camera_yaw_channel.get("value", 0.0))


## 当前俯角（度）。没有仰角通道时 = 接管前那套俯角。
func _camera_elev_deg() -> float:
	if _camera_elev_channel.is_empty():
		return _camera_rest_elevation_deg
	return float(_camera_elev_channel.get("value", _camera_rest_elevation_deg))


## 从 cue 里读枢轴声明。三个字段都没给 ⇒ 沿用当前枢轴（默认玩家）。
##   `pivot`："player"（默认）/ "last_spawn" / "room_center"
##   `room_id`：仅 "room_center" 用
##   `pivot_m`：[x, y, z] 显式世界坐标（最优先，压过 pivot）
func _apply_camera_pivot_params(params: Dictionary, duration: float) -> void:
	var player := player_node()
	if player == null:
		return
	if params.has("pivot_m"):
		var raw: Variant = params.get("pivot_m")
		if raw is Array and (raw as Array).size() == 3:
			_camera_pivot_point = Vector3(
				float((raw as Array)[0]), float((raw as Array)[1]), float((raw as Array)[2])
			)
			_camera_pivot_mode = "point"
			_start_camera_pivot_move(player, duration)
		else:
			_warn("camera.pivot_m 必须是 [x, y, z] 三个数，本镜头枢轴未变。")
		return
	if not params.has("pivot"):
		return
	var mode := str(params.get("pivot", "player"))
	if mode not in ["player", "last_spawn", "room_center"]:
		_warn(
			"camera.pivot『%s』未知（可选 player / last_spawn / room_center，或直接用 pivot_m），本镜头退回玩家。"
			% mode
		)
		mode = "player"
	_camera_pivot_mode = mode
	if mode == "room_center":
		_camera_pivot_room_id = str(params.get("room_id", ""))
	_start_camera_pivot_move(player, duration)


## 把枢轴从当前位置平滑移到「当前声明」解析出的目标点。
func _start_camera_pivot_move(player: Node3D, duration: float) -> void:
	var from := _current_camera_pivot(player)
	var target := _resolve_camera_pivot(player)
	_camera_pivot_channel = {
		"from": from, "to": target, "t": 0.0,
		"duration": maxf(0.0, duration), "value": from,
	}


## 当前枢轴世界坐标：有通道走通道值，否则按声明实时解析。
func _current_camera_pivot(player: Node3D) -> Vector3:
	if not _camera_pivot_channel.is_empty():
		# 显式定型：Dictionary.get 返回 Variant，直接 return 会撞「警告即错误」。
		var value: Vector3 = _camera_pivot_channel.get("value", player.global_position)
		return value
	return _resolve_camera_pivot(player)


## 按 `_camera_pivot_mode` 解析枢轴目标点。拿不到就**告警并退回玩家**（不静默）。
func _resolve_camera_pivot(player: Node3D) -> Vector3:
	match _camera_pivot_mode:
		"point":
			return _camera_pivot_point
		"last_spawn":
			if _has_last_spawn:
				return _last_spawn_origin
			_warn("camera.pivot=last_spawn，但本段还没有 scene.spawn，退回玩家。")
		"room_center":
			var room := room_node(_camera_pivot_room_id)
			if room != null:
				# 房间节点原点即房间中心（DungeonRoom3D 的 ±dimensions/2 约定）。
				return room.global_position
			_warn("camera.pivot=room_center，但找不到房间『%s』，退回玩家。" % _camera_pivot_room_id)
	return player.global_position


func _apply_camera_pose() -> void:
	if _camera == null or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return
	var player := player_node()
	if player == null:
		return
	if _camera_rest_offset.length_squared() <= 0.000001:
		return
	# 相机绕**枢轴**做刚体轨道：先把「接管前那条 枢轴→相机 轴」绕水平轴抬/压到目标俯角，
	# 再绕枢轴竖轴转方位角。位置与朝向同步旋转，所以焦点恒在枢轴上 ——
	# 枢轴默认 = 玩家（焦点钉在主角身上，老行为一字不变）；显式给 pivot 时枢轴移到别处，
	# 整台相机就「平移过去」并对准新焦点。
	# 俯角变化 = 镜头真的从上方压下来，而不是沿同一条轴滑动。
	var elev_pivot := _camera_elevation_pivot()
	var orbit := Basis(Vector3.UP, deg_to_rad(_camera_yaw_deg()))
	var offset := orbit * elev_pivot * _camera_rest_offset
	if offset.length_squared() <= 0.000001:
		return
	var distance := maxf(CAMERA_MIN_DISTANCE_M, _camera_distance())
	var center := _current_camera_pivot(player)
	_camera.global_transform = Transform3D(
		orbit * elev_pivot * _camera_rest_basis,
		center + offset.normalized() * distance
	)


## 「接管前俯角 → 目标俯角」的旋转。没有仰角需求时是单位阵（= 老行为）。
func _camera_elevation_pivot() -> Basis:
	var horizontal := Vector3(_camera_rest_offset.x, 0.0, _camera_rest_offset.z)
	if horizontal.length_squared() <= 0.000001:
		return Basis.IDENTITY
	var delta := deg_to_rad(_camera_elev_deg() - _camera_rest_elevation_deg)
	if absf(delta) <= 0.000001:
		return Basis.IDENTITY
	return Basis(horizontal.normalized().cross(Vector3.UP).normalized(), delta)


## 归还相机：先还原到接管前的精确位姿，再放权给玩法镜头。
func release_camera_override() -> void:
	if _camera != null and is_instance_valid(_camera) and _camera.is_inside_tree():
		_camera.global_transform = _camera_rest_global
	_camera_override_active = false
	_camera = null
	_camera_channel = {}
	_camera_yaw_channel = {}
	_camera_elev_channel = {}
	_camera_pivot_channel = {}
	_camera_pivot_mode = "player"
	_camera_pivot_point = Vector3.ZERO
	_camera_pivot_room_id = ""


# -------------------------------------------------------------------------
# actor
# -------------------------------------------------------------------------

func _actor_instruction(action: String, params: Dictionary) -> Dictionary:
	match action:
		"say":
			return _actor_say(params)
		"face":
			return _actor_face(params)
		"show":
			return _actor_visibility(params, true)
		"hide":
			return _actor_visibility(params, false)
		"pose":
			return _actor_pose(params)
	return _degraded("actor.%s 尚未接通（见 08 文档 §5.2 指令表）。" % action)


func _resolve_actor(params: Dictionary) -> Node3D:
	var who := str(params.get("who", "player"))
	if who == "player" or who.is_empty():
		return player_node()
	return null


func _actor_say(params: Dictionary) -> Dictionary:
	var actor := _resolve_actor(params)
	if actor == null:
		return _degraded("actor.say：演员『%s』当前不可用。" % str(params.get("who", "player")))
	var text := str(params.get("text", ""))
	if text.strip_edges().is_empty():
		return _failed("actor.say 缺少 text。")
	var hold := float(params.get("hold", -1.0))
	# 头顶气泡是角色系统自己的能力（CharacterBark3D），剧情只投喂文本。
	var dungeon := dungeon_node()
	if dungeon != null and dungeon.has_method("narrative_player_bark"):
		var bark: Variant = dungeon.call("narrative_player_bark")
		if bark != null and (bark as Object).has_method("say_text"):
			(bark as Object).call("say_text", text, hold)
			return _ok()
	var attached: Variant = CharacterBark3D.attach_to(actor)
	if attached != null and (attached as Object).has_method("say_text"):
		(attached as Object).call("say_text", text, hold)
		return _ok()
	return _degraded("actor.say：气泡挂载点不可用，本句被跳过。")


func _actor_face(params: Dictionary) -> Dictionary:
	var actor := _resolve_actor(params)
	if actor == null:
		return _degraded("actor.face：演员不可用。")
	# 先解除输入锁定的朝向占用：朝向由 aim_yaw 与视觉根共同表达，
	# 与 MainEntryScreen3D 的既有无接管写法一致（存 _saved_aim_yaw → 写 → 还原）。
	var before_yaw := float(actor.get("aim_yaw"))
	var duration := maxf(0.0, float(params.get("duration", 0.35)))
	# 序列基准：一条 face 序列（`actor.facing` 占用期间）只认**进入序列那一刻**的朝向。
	# 若按"当前值"逐条累加，+32/−32 这种来回摆动会退化成单向漂移
	# （+32→0→+32→0，所谓"左右张望"实际只朝一边晃两下）。
	if not _facing_active:
		_facing_base_yaw = before_yaw
	# relative=true：以序列基准偏转（「左右张望」用这个），
	# 否则 yaw_deg 是绝对方位 —— 角色出生朝向不同也不该让「左看」变成「右看」。
	var target_yaw := deg_to_rad(float(params.get("yaw_deg", 0.0)))
	if bool(params.get("relative", false)):
		target_yaw += _facing_base_yaw
	_facing_active = true
	_facing_channel = {
		"from": before_yaw, "to": target_yaw,
		"t": 0.0, "duration": duration, "value": before_yaw,
	}
	return _done(Callable(self, "_restore_facing").bind({"yaw": before_yaw}))


func _apply_facing() -> void:
	var player := player_node()
	if player == null:
		return
	_facing_yaw = float(_facing_channel.get("value", _facing_yaw))
	player.set("aim_yaw", _facing_yaw)
	var avatar: Variant = player.get("avatar")
	if avatar is Node3D:
		var visual_root: Variant = (avatar as Node3D).get("visual_root")
		if visual_root is Node3D:
			(visual_root as Node3D).rotation.y = _facing_yaw


func _restore_facing(argument: Dictionary) -> void:
	_facing_active = false
	_facing_channel = {}
	_facing_yaw = float(argument.get("yaw", 0.0))
	var player := player_node()
	if player == null:
		return
	player.set("aim_yaw", _facing_yaw)
	var avatar: Variant = player.get("avatar")
	if avatar is Node3D:
		var visual_root: Variant = (avatar as Node3D).get("visual_root")
		if visual_root is Node3D:
			(visual_root as Node3D).rotation.y = _facing_yaw


func _actor_visibility(params: Dictionary, visible: bool) -> Dictionary:
	var actor := _resolve_actor(params)
	if actor == null:
		return _degraded("actor.show/hide：演员不可用。")
	var before := actor.visible
	actor.visible = visible
	return _done(Callable(self, "_restore_visibility").bind({"actor": actor, "visible": before}))


func _restore_visibility(argument: Dictionary) -> void:
	var actor: Variant = argument.get("actor")
	if actor is Node3D and is_instance_valid(actor):
		(actor as Node3D).visible = bool(argument.get("visible", true))


## 叙事姿态（趴 / 起身等）。动画归角色系统，剧情只点名要哪一段、停在第几成。
## 实现依赖的是角色自带的动作库数据，**不新增任何美术资产**。
func _actor_pose(params: Dictionary) -> Dictionary:
	var actor := _resolve_actor(params)
	if actor == null:
		return _degraded("actor.pose：演员不可用。")
	var avatar: Variant = actor.get("avatar")
	if not (avatar is Node3D) or not (avatar as Object).has_method("set_narrative_pose"):
		return _degraded("actor.pose：角色系统没有叙事姿态接入口。")
	var clip := str(params.get("clip", ""))
	if clip.is_empty():
		return _failed("actor.pose 缺少 clip。")
	var phase := float(params.get("phase", 0.0))
	var duration := maxf(0.0, float(params.get("duration", 0.0)))
	if duration > 0.0 and params.has("to_phase"):
		# 相位过渡：例「起身」= 把倒地剪辑的相位从 1.0 推到 0.0（倒放）。
		_pose_active = true
		_pose_clip = clip
		_pose_channel = {
			"from": phase, "to": float(params.get("to_phase", 1.0)),
			"t": 0.0, "duration": duration, "value": phase,
		}
		(avatar as Object).call("set_narrative_pose", clip, phase, true)
	else:
		_pose_active = false
		_pose_clip = clip
		_pose_channel = {}
		(avatar as Object).call(
			"set_narrative_pose", clip, phase, bool(params.get("frozen", true))
		)
	return _done(Callable(self, "_restore_pose").bind({"actor": actor}))


func _apply_pose() -> void:
	var actor := player_node()
	if actor == null:
		return
	var avatar: Variant = actor.get("avatar")
	if avatar is Object and (avatar as Object).has_method("set_narrative_pose"):
		(avatar as Object).call(
			"set_narrative_pose", _pose_clip, float(_pose_channel.get("value", 0.0)), true
		)


## 姿态过渡走完 = 角色已经站好/躺好，必须把动画交还给角色系统。
## 否则 pose_lock 会把角色永久钉在这段剪辑的这一帧上 —— 玩家看到的是
## "起身之后一直僵在死亡动画的第一帧、待机动画根本不会播"，
## 于是剧本里的"左右张望"只能是硬转身体，观感全错。
func _end_pose_transition() -> void:
	_pose_active = false
	_pose_clip = ""
	_pose_channel = {}
	var actor := player_node()
	if actor == null:
		return
	var avatar: Variant = actor.get("avatar")
	if avatar is Object and (avatar as Object).has_method("clear_narrative_pose"):
		(avatar as Object).call("clear_narrative_pose")


func _restore_pose(argument: Dictionary) -> void:
	_pose_active = false
	_pose_clip = ""
	_pose_channel = {}
	var actor: Variant = argument.get("actor")
	if actor is Node3D and is_instance_valid(actor):
		var avatar: Variant = (actor as Node3D).get("avatar")
		if avatar is Object and (avatar as Object).has_method("clear_narrative_pose"):
			(avatar as Object).call("clear_narrative_pose")


# -------------------------------------------------------------------------
# fx
# -------------------------------------------------------------------------

func _fx_instruction(action: String, params: Dictionary) -> Dictionary:
	match action:
		"vfx":
			return _fx_vfx(params)
		"sfx":
			return _fx_sfx(params)
		"music":
			return _fx_music(params, "play")
		"music_push":
			return _fx_music(params, "push")
		"music_restore":
			return _fx_music_restore()
	return _degraded("fx.%s 尚未接通（见 08 文档 §5.2 指令表）。" % action)


func _fx_vfx(params: Dictionary) -> Dictionary:
	var asset_id := str(params.get("asset_id", ""))
	if asset_id.is_empty():
		return _failed("fx.vfx 缺少 asset_id。")
	var origin_value: Variant = _anchor_position(params)
	if origin_value == null:
		return _degraded("fx.vfx：锚点不可用，本例特效被跳过。")
	var origin: Vector3 = origin_value
	var color := Color.WHITE
	var color_value: Variant = params.get("color", null)
	if color_value is Array and (color_value as Array).size() >= 3:
		var channels: Array = color_value
		color = Color(float(channels[0]), float(channels[1]), float(channels[2]))
	VfxPool.acquire(asset_id, origin, color, float(params.get("size", 1.0)), params.get("context", {}))
	return _ok()


func _anchor_position(params: Dictionary) -> Variant:
	var actor := _resolve_actor(params)
	if actor == null:
		return null
	var anchor := str(params.get("anchor", "root"))
	var offset := Vector3(0.0, 0.0, 0.0)
	var offset_value: Variant = params.get("offset", null)
	if offset_value is Array and (offset_value as Array).size() == 3:
		var parts: Array = offset_value
		offset = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	match anchor:
		"head":
			var avatar: Variant = actor.get("avatar")
			if avatar is Node3D:
				var head: Variant = (avatar as Node3D).get("head")
				if head is Node3D:
					return (head as Node3D).global_position + offset
			return actor.global_position + Vector3.UP * 1.6 + offset
		"feet":
			return actor.global_position + offset
		_:
			return actor.global_position + Vector3.UP * 0.9 + offset


func _fx_sfx(params: Dictionary) -> Dictionary:
	var name := str(params.get("name", ""))
	if name.is_empty():
		return _failed("fx.sfx 缺少 name。")
	AudioManager.play_sfx(name, float(params.get("volume_db", 0.0)), float(params.get("pitch", 1.0)))
	return _ok()


func _fx_music(params: Dictionary, mode: String) -> Dictionary:
	var music_id := str(params.get("id", ""))
	if music_id.is_empty():
		return _failed("fx.music 缺少 id。")
	if mode == "push":
		MusicManager.push_and_play(music_id)
		return _done(Callable(self, "_music_restore_callable"))
	MusicManager.play(music_id)
	return _done(Callable(self, "_music_restore_callable"))


func _music_restore_callable() -> void:
	MusicManager.restore()


func _fx_music_restore() -> Dictionary:
	MusicManager.restore()
	return _ok()


# -------------------------------------------------------------------------
# ui
# -------------------------------------------------------------------------

func _ui_instruction(action: String, params: Dictionary) -> Dictionary:
	match action:
		"subtitle":
			var text := str(params.get("text", ""))
			if text.strip_edges().is_empty():
				return _failed("ui.subtitle 缺少 text。")
			DialogueUI.show_message(
				text,
				str(params.get("speaker", DialogueUI.SPEAKER_SYSTEM)),
				float(params.get("auto", 3.0))
			)
			return _ok()
		"hint":
			var hint := str(params.get("text", ""))
			if hint.strip_edges().is_empty():
				return _failed("ui.hint 缺少 text。")
			DialogueUI.announce(hint, float(params.get("auto", 3.0)))
			return _ok()
		"dialogue":
			var lines: Variant = params.get("lines", null)
			if not (lines is Array) or (lines as Array).is_empty():
				return _failed("ui.dialogue 缺少 lines。")
			DialogueUI.show_lines({
				"lines": lines,
				"interrupt": bool(params.get("interrupt", true)),
			})
			return _ok()
	return _degraded("ui.%s 尚未接通（见 08 文档 §5.2 指令表）。" % action)


# -------------------------------------------------------------------------
# scene
# -------------------------------------------------------------------------

func _scene_instruction(action: String, params: Dictionary) -> Dictionary:
	match action:
		"door":
			return _scene_door(params)
		"light":
			return _scene_light(params)
		"spawn":
			return _scene_spawn(params)
		"despawn":
			return _scene_despawn(params)
	return _degraded("scene.%s 尚未接通（见 08 文档 §5.2 指令表）。" % action)


func _scene_door(params: Dictionary) -> Dictionary:
	var room := room_node(str(params.get("room_id", "")))
	if room == null:
		return _degraded("scene.door：房间『%s』不存在。" % str(params.get("room_id", "")))
	var opened := bool(params.get("open", true))
	var doors := _all_in_room(room, "set_open")
	if doors.is_empty():
		return _degraded("scene.door：房间『%s』里没有可控制的门。" % str(params.get("room_id", "")))
	var before: Array = []
	for door: Node in doors:
		before.append({"door": door, "opened": bool(door.get("opened"))})
		door.call("set_open", opened, false)
	return _done(Callable(self, "_restore_doors").bind({"doors": before}))


func _restore_doors(argument: Dictionary) -> void:
	for entry: Dictionary in (argument.get("doors", []) as Array):
		var door: Variant = entry.get("door")
		if door is Object and is_instance_valid(door):
			(door as Object).call("set_open", bool(entry.get("opened", false)), true)


func _scene_light(params: Dictionary) -> Dictionary:
	var room := room_node(str(params.get("room_id", "")))
	if room == null:
		return _degraded("scene.light：房间『%s』不存在。" % str(params.get("room_id", "")))
	var switch_node := _find_in_room(room, "set_light_on")
	if switch_node == null:
		return _degraded("scene.light：房间『%s』里没有灯开关。" % str(params.get("room_id", "")))
	var before := bool(switch_node.get("light_on"))
	switch_node.call("set_light_on", bool(params.get("on", true)))
	return _done(Callable(self, "_restore_light").bind({"node": switch_node, "on": before}))


func _restore_light(argument: Dictionary) -> void:
	var node: Variant = argument.get("node")
	if node is Object and is_instance_valid(node):
		(node as Object).call("set_light_on", bool(argument.get("on", false)))


## 剧情刷怪。**正门**开在 Dungeon3D 上（`narrative_spawn_enemies`），
## 因为敌人生成要接 6 个信号、上 `$ActiveEnemies`、写存活账 —— 那是地牢系统的私事。
## 这里只负责把「左边/右边」翻译成玩家的左右侧弧形站位。
func _scene_spawn(params: Dictionary) -> Dictionary:
	var dungeon := dungeon_node()
	if dungeon == null:
		return _degraded("scene.spawn：找不到地牢场景根。")
	if not dungeon.has_method("narrative_spawn_enemies"):
		return _degraded("scene.spawn：地牢没有开放剧情刷怪正门。")
	var room_id := str(params.get("room_id", ""))
	var kind := str(params.get("kind", "melee_chaser"))
	var count := int(params.get("count", 1))
	if count <= 0:
		return _failed("scene.spawn 的 count 必须 > 0。")
	var side := str(params.get("side", "right"))
	# `forward_m` = 沿视线方向的**额外前推**（米）。不写则沿用旧的 distance*0.5。
	var layout := _spawn_layout(
		side, float(params.get("distance", 3.6)), params.get("forward_m", null)
	)
	var origin: Vector3 = layout["origin"]
	var axis: Vector3 = layout["axis"]
	var result: Variant = dungeon.call(
		"narrative_spawn_enemies", room_id, kind, count, origin, axis,
		float(params.get("spread", 1.5))
	)
	if result is int and int(result) > 0:
		# 记下队列中心：相机枢轴 `pivot: "last_spawn"` 用它（作者不用写坐标）。
		_has_last_spawn = true
		_last_spawn_origin = origin
		# 刷新出来的怪是**已发生的效果**，收口时不回滚（08 文档 §6.4）：
		# 玩家看完这句就要自己动手清场，怪在这里消失才是 bug。
		return _ok()
	return _degraded(
		"scene.spawn：在『%s』生成 %s 失败（返回 %s）。" % [room_id, kind, str(result)]
	)


## 玩家左右侧站位。返回 {"origin": 队列中心, "axis": 展开轴}。
## 用玩家朝向而不是房间朝向 —— 「画面的右边」在俯视角下就等于角色的右手边，
## 这样不需要为每个房间预写方位，房间换了构图也不会错。
## `forward_override`（= cue 的 `forward_m`）：沿视线额外前推的米数；null = 用旧的 distance*0.5。
func _spawn_layout(side: String, distance: float, forward_override: Variant = null) -> Dictionary:
	var player := player_node()
	if player == null:
		return {"origin": Vector3.ZERO, "axis": Vector3.RIGHT}
	var forward := -player.global_basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.000001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var lateral := right if side == "right" else -right
	# 前向分量：默认 distance*0.5（原行为）。触发通常发生在玩家**刚跨进门**那一刻，
	# 那时玩家还站在门口 ⇒ 默认值会把整条队列留在门口（实测最后一只几乎踩在门线上）。
	# 房间进深大、或想让怪「在房间里侧」时，用 cue 的 `forward_m` 显式前推。
	# ⚠️ 前推会同时拉大相机到队列的距离（运镜构图随之变化）——它是**作者的构图旋钮**。
	var forward_m := maxf(0.0, distance * 0.5)
	if forward_override != null:
		forward_m = maxf(0.0, float(forward_override))
	# 队列沿**视线方向**展开：镜头转向侧面看过去时，这条队形在画面里是横排。
	return {
		"origin": player.global_position + lateral * distance + forward * forward_m,
		"axis": forward,
	}


## 撤掉本房剧情生成的怪（玩家真的不需要看见它们了时才用）。
func _scene_despawn(params: Dictionary) -> Dictionary:
	var dungeon := dungeon_node()
	if dungeon == null or not dungeon.has_method("narrative_despawn_enemies"):
		return _degraded("scene.despawn：地牢没有开放剧情撤怪正门。")
	var room_id := str(params.get("room_id", ""))
	var removed: Variant = dungeon.call("narrative_despawn_enemies", room_id)
	if removed is int:
		return _ok()
	return _degraded("scene.despawn：房间『%s』撤怪失败。" % room_id)


# -------------------------------------------------------------------------
# grant
# -------------------------------------------------------------------------

func _grant_instruction(action: String, params: Dictionary) -> Dictionary:
	match action:
		"flag":
			# 本局内存态标记，由导演持有；适配器只回报"这是本系统自建的"。
			return _ok()
		"item":
			return _degraded(
				"grant.item 尚未接通：剧情还没有拿到背包的稳定入口（见 08 文档 §5.2）。"
			)
		"unlock":
			return _degraded("grant.unlock 尚未接通：依赖具体解锁项（见 08 文档 §5.2）。")
	return _degraded("grant.%s 尚未接通（见 08 文档 §5.2 指令表）。" % action)
