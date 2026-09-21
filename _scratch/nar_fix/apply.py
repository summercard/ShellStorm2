import io, os, sys

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"

def patch(rel, edits):
    path = os.path.join(ROOT, rel)
    raw = open(path, "rb").read().decode("utf-8")
    text = raw.replace("\r\n", "\n")
    for name, old, new in edits:
        n = text.count(old)
        if n != 1:
            raise SystemExit("ANCHOR FAIL %s :: %s count=%d" % (rel, name, n))
        text = text.replace(old, new, 1)
    out = text.replace("\n", "\r\n").encode("utf-8")
    open(path, "wb").write(out)
    print("patched %-52s CR=%d LF=%d" % (rel, out.count(b"\r"), out.count(b"\n")))


# ===================== NarrativeAdapter3D.gd =====================
patch("src/narrative/NarrativeAdapter3D.gd", [
("cam-elev-vars",
"""var _camera_channel := {}          # 距离通道 {from, to, t, duration}
var _camera_yaw_channel := {}      # 方位通道（度）{from, to, t, duration}
""",
"""var _camera_channel := {}          # 距离通道 {from, to, t, duration}
var _camera_yaw_channel := {}      # 方位通道（度）{from, to, t, duration}
var _camera_elev_channel := {}     # 仰角通道（度）{from, to, t, duration}
var _camera_rest_elevation_deg := 0.0  # 接管前那套俯角（度），elevation_deg 的缺省值
"""),

("facing-base-var",
"""var _facing_active := false
var _facing_channel := {}          # {from, to, t, duration}
var _facing_yaw := 0.0
""",
"""var _facing_active := false
var _facing_channel := {}          # {from, to, t, duration}
var _facing_yaw := 0.0
var _facing_base_yaw := 0.0        # 本条 face 序列的基准朝向（进入序列时抓一次，见 _actor_face）
"""),

("tick",
"""	if _camera_override_active:
		_advance_channel(_camera_channel, delta)
		_advance_channel(_camera_yaw_channel, delta)
		_apply_camera_pose()
	if _facing_active:
		_advance_channel(_facing_channel, delta)
		_apply_facing()
	if _pose_active:
		_advance_channel(_pose_channel, delta)
		_apply_pose()
""",
"""	if _camera_override_active:
		_advance_channel(_camera_channel, delta)
		_advance_channel(_camera_yaw_channel, delta)
		_advance_channel(_camera_elev_channel, delta)
		_apply_camera_pose()
	if _facing_active:
		_advance_channel(_facing_channel, delta)
		_apply_facing()
	if _pose_active:
		var pose_finished := _advance_channel(_pose_channel, delta)
		_apply_pose()
		if pose_finished:
			_end_pose_transition()
"""),

("ensure-camera-elev",
"""	_camera = camera
	_camera_rest_global = camera.global_transform
	_camera_rest_basis = camera.global_basis
	_camera_rest_offset = camera.global_position - player.global_position
	_camera_override_active = true
""",
"""	_camera = camera
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
	_camera_override_active = true
"""),

("focus-elev-channel",
"""	# 登记归还：收口时必须把相机位姿还原并放权给玩法镜头，否则玩家永久被钉在叙事机位上。
	return _done(Callable(self, "release_camera_override"))
""",
"""	# 仰角通道：**显式给 elevation_deg 才建** —— 这是「镜头从上往下压」的唯一正确做法。
	# 只改 distance 不改仰角，镜头只会沿同一条轴滑动，看上去只是拉近拉远、不叫俯冲。
	if params.has("elevation_deg"):
		_camera_elev_channel = {
			"from": _camera_elev_deg(),
			"to": float(params.get("elevation_deg", _camera_rest_elevation_deg)),
			"t": 0.0, "duration": duration, "value": _camera_elev_deg(),
		}
	# 登记归还：收口时必须把相机位姿还原并放权给玩法镜头，否则玩家永久被钉在叙事机位上。
	return _done(Callable(self, "release_camera_override"))
"""),

("restore-elev",
"""	var duration := maxf(0.0, float(params.get("duration", 0.6)))
	_camera_channel = {
		"from": _camera_distance(), "to": _camera_rest_offset.length(),
		"t": 0.0, "duration": duration, "value": _camera_distance(),
	}
	_camera_yaw_channel = {
		"from": _camera_yaw_deg(), "to": 0.0, "t": 0.0, "duration": duration,
		"value": _camera_yaw_deg(),
	}
	return _done(Callable(self, "release_camera_override"))
""",
"""	var duration := maxf(0.0, float(params.get("duration", 0.6)))
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
"""),

("elev-getter",
"""func _camera_yaw_deg() -> float:
	if _camera_yaw_channel.is_empty():
		return 0.0
	return float(_camera_yaw_channel.get("value", 0.0))
""",
"""func _camera_yaw_deg() -> float:
	if _camera_yaw_channel.is_empty():
		return 0.0
	return float(_camera_yaw_channel.get("value", 0.0))


## 当前俯角（度）。没有仰角通道时 = 接管前那套俯角。
func _camera_elev_deg() -> float:
	if _camera_elev_channel.is_empty():
		return _camera_rest_elevation_deg
	return float(_camera_elev_channel.get("value", _camera_rest_elevation_deg))
"""),

("apply-camera-pose",
"""func _apply_camera_pose() -> void:
	if _camera == null or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return
	var player := player_node()
	if player == null:
		return
	var orbit := Basis(Vector3.UP, deg_to_rad(_camera_yaw_deg()))
	var offset := orbit * _camera_rest_offset
	if offset.length_squared() <= 0.000001:
		return
	# 距离沿「接管前的方位」缩放，俯角与焦点构图完全继承玩法镜头。
	var distance := maxf(CAMERA_MIN_DISTANCE_M, _camera_distance())
	_camera.global_transform = Transform3D(
		orbit * _camera_rest_basis,
		player.global_position + offset.normalized() * distance
	)
""",
"""func _apply_camera_pose() -> void:
	if _camera == null or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return
	var player := player_node()
	if player == null:
		return
	if _camera_rest_offset.length_squared() <= 0.000001:
		return
	# 相机绕玩家做**刚体轨道**：先把「接管前那条 玩家→相机 轴」绕水平轴抬/压到目标俯角，
	# 再绕玩家竖轴转方位角。位置与朝向同步旋转，所以焦点始终钉在玩家身上，
	# 俯角变化 = 镜头真的从上方压下来，而不是沿同一条轴滑动。
	var pivot := _camera_elevation_pivot()
	var orbit := Basis(Vector3.UP, deg_to_rad(_camera_yaw_deg()))
	var offset := orbit * pivot * _camera_rest_offset
	if offset.length_squared() <= 0.000001:
		return
	var distance := maxf(CAMERA_MIN_DISTANCE_M, _camera_distance())
	_camera.global_transform = Transform3D(
		orbit * pivot * _camera_rest_basis,
		player.global_position + offset.normalized() * distance
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
"""),

("release-clears-elev",
"""	_camera_override_active = false
	_camera = null
	_camera_channel = {}
	_camera_yaw_channel = {}
""",
"""	_camera_override_active = false
	_camera = null
	_camera_channel = {}
	_camera_yaw_channel = {}
	_camera_elev_channel = {}
"""),

("input-hold",
"""	var locked := bool(params.get("locked", true))
	var before := bool(player.get("input_locked"))
	if before != locked:
		player.call("set_input_locked", locked)
	if locked:
		_player_input_taken = true
	# 归还 = 还原为**接管前的原始值**（不是硬编"解锁"），并交回独占权。
	return _done(Callable(self, "_release_player_input").bind(before))


## 演出是否正在独占玩家输入。被 Dungeon3D 每帧的锁同步查询（08 文档 §5.5）。
func is_player_input_locked() -> bool:
	return _player_input_taken


## 归还入口：先交回独占权，再还原为接管前的原值。
func _release_player_input(before: bool) -> void:
	_player_input_taken = false
	var player := player_node()
	if player != null and player.has_method("set_input_locked"):
		player.call("set_input_locked", before)
""",
"""	var locked := bool(params.get("locked", true))
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
"""),

("face-base",
"""	var before_yaw := float(actor.get("aim_yaw"))
	var duration := maxf(0.0, float(params.get("duration", 0.35)))
	# relative=true：以**接管前的当前朝向**为基准偏转（「左右张望」用这个），
	# 否则 yaw_deg 是绝对方位 —— 角色出生朝向不同也不该让「左看」变成「右看」。
	var target_yaw := deg_to_rad(float(params.get("yaw_deg", 0.0)))
	if bool(params.get("relative", false)):
		target_yaw += before_yaw
""",
"""	var before_yaw := float(actor.get("aim_yaw"))
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
"""),

("end-pose-transition",
"""func _apply_pose() -> void:
	var actor := player_node()
	if actor == null:
		return
	var avatar: Variant = actor.get("avatar")
	if avatar is Object and (avatar as Object).has_method("set_narrative_pose"):
		(avatar as Object).call(
			"set_narrative_pose", _pose_clip, float(_pose_channel.get("value", 0.0)), true
		)
""",
"""func _apply_pose() -> void:
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
"""),
])


# ===================== NarrativeDirector3D.gd =====================
patch("src/narrative/NarrativeDirector3D.gd", [
("bind-gameplay-started",
"""	if node.has_signal("run_completed") and not node.run_completed.is_connected(_on_dungeon_run_completed):
		node.run_completed.connect(_on_dungeon_run_completed)
""",
"""	if node.has_signal("run_completed") and not node.run_completed.is_connected(_on_dungeon_run_completed):
		node.run_completed.connect(_on_dungeon_run_completed)
	if node.has_signal("gameplay_started") and not node.gameplay_started.is_connected(_on_dungeon_gameplay_started):
		node.gameplay_started.connect(_on_dungeon_gameplay_started)
"""),

("gameplay-started-handler",
"""func _evaluate_event(event_name: String, room_id: String) -> void:
""",
"""## 玩法正式开始（开场页动画播完 / 没有开场页时 = 本帧末）。
## 开场类剧情必须挂这一发，不能挂 room_entered —— room_entered 在场景 `_ready` 里就发了，
## 那一刻开场页还在接管相机与输入，剧情会在菜单背后空跑、并与开场页互相顶：
## 相机被钉在近景、输入锁被开场页还原、玩家的鼠标还能把剧本摆好的朝向顶掉。
func _on_dungeon_gameplay_started(room_id: String) -> void:
	_evaluate_event("gameplay_started", room_id)


func _evaluate_event(event_name: String, room_id: String) -> void:
"""),

("facing-override-query",
"""func is_player_input_locked() -> bool:
	return _adapter.is_player_input_locked()
""",
"""func is_player_input_locked() -> bool:
	return _adapter.is_player_input_locked()


## 叙事是否正在接管演员朝向（actor.face 生效期间）。Player3D 的鼠标瞄准必须问这里让位，
## 否则玩家一晃鼠标就把剧本摆好的"左右张望"顶掉（运行时零报错，只表现为中间错乱）。
func is_actor_facing_overridden() -> bool:
	return _adapter.is_actor_facing_overridden()
"""),
])


# ===================== Dungeon3D.gd =====================
patch("src/world3d/Dungeon3D.gd", [
("refresh-input-lock",
"""func _narrative_holds_player_input() -> bool:
	return (
		NarrativeDirector != null
		and NarrativeDirector.has_method("is_player_input_locked")
		and bool(NarrativeDirector.is_player_input_locked())
	)
""",
"""func _narrative_holds_player_input() -> bool:
	return (
		NarrativeDirector != null
		and NarrativeDirector.has_method("is_player_input_locked")
		and bool(NarrativeDirector.is_player_input_locked())
	)


## 供叙事收口时要求重算（08 文档 §5.5）。归还独占权后必须再裁决一次 ——
## 本函数是事件驱动的（27 处调用），演出结束后没人再喊它，
## 玩家就会一直锁着：键盘与开枪全废、鼠标仍能转向，且运行时零报错。
func refresh_player_input_lock() -> void:
	_sync_player_input_lock()
"""),
])


# ===================== Player3D.gd =====================
patch("src/player3d/Player3D.gd", [
("aim-yield",
"""func _update_aim_from_mouse() -> void:
	if camera == null or not camera.is_inside_tree():
		return
""",
"""func _update_aim_from_mouse() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	# 叙事用 actor.face 接管朝向时鼠标瞄准必须让位：input_locked 不拦瞄准
	# （锁定期间仍可转向），所以玩家一晃鼠标就会把剧本刚摆好的"左右张望"顶掉，
	# 表现为中间画面/朝向错乱，且运行时零报错。
	if _narrative_holds_aim():
		return
"""),

("holds-aim-helper",
"""func _init_state_machine() -> void:
	_state_machine = StateMachine.new()
""",
"""## 叙事是否正在接管角色朝向（见 NarrativeDirector.is_actor_facing_overridden）。
func _narrative_holds_aim() -> bool:
	return (
		NarrativeDirector != null
		and NarrativeDirector.has_method("is_actor_facing_overridden")
		and bool(NarrativeDirector.is_actor_facing_overridden())
	)


func _init_state_machine() -> void:
	_state_machine = StateMachine.new()
"""),
])


# ===================== MainEntryScreen3D.gd =====================
patch("src/ui/main_entry/MainEntryScreen3D.gd", [
("process-yield",
"""	_set_player_presentation_facing()
	_camera.transform = _closeup_transform
	_camera.fov = CLOSEUP_FOV
""",
"""	# 叙事接管相机期间启动页不抢镜头：两个系统都写同一台 Camera3D，
	# 互不查询就会逐帧互相覆盖（运行时零报错，只表现为画面跳/抖）。
	if _narrative_holds_presentation():
		return
	_set_player_presentation_facing()
	_camera.transform = _closeup_transform
	_camera.fov = CLOSEUP_FOV
"""),

("finish-transition-yield",
"""	if _player != null and is_instance_valid(_player):
		_player.set_input_locked(_previous_input_locked)
		_player.aim_yaw = _saved_aim_yaw
		if _player.avatar != null and _player.avatar.visual_root != null:
			_player.avatar.visual_root.rotation = _saved_visual_root_rotation
""",
"""	if _player != null and is_instance_valid(_player) and not _narrative_holds_presentation():
		# 叙事持有输入/朝向时不得顶掉：写回 _previous_input_locked 会把剧情刚拿到的锁
		# 还原成"可操控"，写回 aim_yaw/rotation 会把剧情刚摆好的朝向抹掉。
		_player.set_input_locked(_previous_input_locked)
		_player.aim_yaw = _saved_aim_yaw
		if _player.avatar != null and _player.avatar.visual_root != null:
			_player.avatar.visual_root.rotation = _saved_visual_root_rotation
"""),

("holds-presentation-helper",
"""func is_camera_override_active() -> bool:
	return _presenting
""",
"""func is_camera_override_active() -> bool:
	return _presenting


## 叙事系统是否持有本帧的相机/输入。两个系统都要写同一台 Camera3D 与同一个
## input_locked，互不查询就会互相覆盖 —— 运行时零报错，只表现为画面错乱或
## 剧情期间玩家仍能操控。
func _narrative_holds_presentation() -> bool:
	if NarrativeDirector == null:
		return false
	var holds_camera := (
		NarrativeDirector.has_method("is_camera_override_active")
		and bool(NarrativeDirector.is_camera_override_active())
	)
	var holds_input := (
		NarrativeDirector.has_method("is_player_input_locked")
		and bool(NarrativeDirector.is_player_input_locked())
	)
	return holds_camera or holds_input
"""),
])


# ===================== TowerDescent3D.gd =====================
patch("src/world3d/TowerDescent3D.gd", [
("signal",
"""## 下方墙平滑抬升收拢、双端楼梯门、独立墙边电梯与全局固定环境光。

const FACILITY_SCENE: PackedScene = preload("res://assets/art/props/base_world_3d/prp_base_facility_root_top3d.tscn")
""",
"""## 下方墙平滑抬升收拢、双端楼梯门、独立墙边电梯与全局固定环境光。

## 玩法**正式开始**：开场页动画播完（玩家点了开始 / 跳过之后），
## 或没有开场页时 = 本帧末。开场类剧情挂这一发，不能挂 `room_entered` ——
## `room_entered` 在 `_ready` 里就发了，那时开场页还没接管完相机与输入。
signal gameplay_started(room_id: String)

const FACILITY_SCENE: PackedScene = preload("res://assets/art/props/base_world_3d/prp_base_facility_root_top3d.tscn")
"""),

("ready-call",
"""	_install_main_entry_screen()
	_announce_floor_arrival(_current_floor_number())
""",
"""	_install_main_entry_screen()
	_defer_gameplay_started()
	_announce_floor_arrival(_current_floor_number())
"""),

("emit-helpers",
"""func _entry_context_requests_main_entry() -> bool:
	return (
		str(_entry_context.get("kind", "")) == GameEntryFlow.KIND_MAIN_ENTRY
		and bool(_entry_context.get("show_main_entry", false))
	)
""",
"""func _entry_context_requests_main_entry() -> bool:
	return (
		str(_entry_context.get("kind", "")) == GameEntryFlow.KIND_MAIN_ENTRY
		and bool(_entry_context.get("show_main_entry", false))
	)


## 把 gameplay_started 排到「开场页真的把相机与输入交回来」之后。
## ⛔ 不能就在 _ready 里直接发：那一刻开场页的 present() 可能还没跑
## （它自己 call_deferred），剧情会抢在开场页前面拿到输入锁，随后被开场页
## 的 _finish_transition() 还原成"可操控"。
func _defer_gameplay_started() -> void:
	if _main_entry_screen != null and is_instance_valid(_main_entry_screen):
		if (
			_main_entry_screen.has_signal("transition_finished")
			and not _main_entry_screen.is_connected(
				"transition_finished", _on_entry_transition_finished
			)
		):
			_main_entry_screen.connect("transition_finished", _on_entry_transition_finished)
		return
	# test_mode / headless / 非冷启动：没有开场页，玩法从本帧末起就正式开始。
	call_deferred("_emit_gameplay_started")


func _on_entry_transition_finished() -> void:
	_emit_gameplay_started()


func _emit_gameplay_started() -> void:
	gameplay_started.emit(str(_current_room_id))
"""),
])

print("ALL PATCHED")
