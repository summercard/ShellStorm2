extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.combat_enabled = true
	player.set_physics_process(false)
	add_child(player)
	player.set_physics_process(false)
	await get_tree().process_frame
	player.set_process(false)
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.weapon.set_process(false)
	if not player.equip_weapon("bp_pistol", "mod_bullet_standard"):
		failures.append("Could not equip pistol for the sidearm reload verification")
	await get_tree().process_frame
	player.weapon.set_process(false)

	# 本场景原先自摆一台「TowerDescent3D 同姿态」的相机，用来判换弹环有没有正对镜头 /
	# 有没有压在角色轮廓上。2026-10-08 世界空间换弹环退役后这两条判据一起下线，
	# 相机也随之删掉（留着就是一个"声明了却没人用"的局部变量）。

	var progress_samples: Array[float] = []
	var ended_results: Array[bool] = []
	player.reload_progress_changed.connect(func(progress: float, _remaining: float): progress_samples.append(progress))
	player.reload_ended.connect(func(completed: bool): ended_results.append(completed))

	player.avatar.call("_process", 0.2)
	var base_avatar := player.avatar.get_component_snapshot()
	var base_right_grip_distance := float(base_avatar.get("hand_r_to_socket_global_distance", 999.0))
	var magazine_size := player.weapon.magazine_size
	player.weapon.current_ammo = maxi(0, magazine_size - 4)
	if not player.weapon.request_reload():
		failures.append("A non-full 3D weapon cannot enter reload")
	player.avatar.call("_process", 0.05)
	var state_snapshot := player.get_state_machine_snapshot()
	var reload_snapshot := player.get_reload_snapshot()
	var avatar_snapshot := player.avatar.get_component_snapshot()
	if not bool((state_snapshot.get("overlays", {}) as Dictionary).get("reloading", false)):
		failures.append("Reload is not exposed as a state-machine overlay")
	# 顶层状态数不写死：真源是 Player3D._build_state_machine() 的 register() 调用数。
	# 这条断言原本写死 8，而 seated / climbing 加入后实际是 10 ⇒ 变成一条**陈旧红项**，
	# 与「换弹表现」完全无关却挡住了这条链路。改成从源码数出来：既不放过「换弹新增了
	# 顶层状态」，也不会因为别的模块加状态而误报。
	if str(state_snapshot.get("current", "")) != "idle" or int(
		(state_snapshot.get("states", []) as Array).size()
	) != _registered_top_level_state_count():
		failures.append(
			"Reload replaced or expanded the top-level player states (current=%s states=%d expected=%d)"
			% [
				str(state_snapshot.get("current", "")),
				int((state_snapshot.get("states", []) as Array).size()),
				_registered_top_level_state_count(),
			]
		)
	# —— 2026-10-08（第五轮，0.2-PLAYER-001 追记五）：换弹环**离开世界空间** ——
	# 主人要求把换弹提示圈换到右下角 HUD 武器图标上（实现是 `src/ui/HudReloadRing.gd`，
	# 由 `Dungeon3D` 建在 `ReferenceCombatHUD` 下；几何/位置/图标弹跳的验收在
	# `verify_reference_hud_fate_visual`）。角色身上这一套世界空间环因此**退役**：
	# prefab 里的 `ReloadProgress3D/Track|Fill` 节点不删（资产层不动），但由
	# `PlayerAvatar3D.RELOAD_RING_IN_WORLD = false` 按住，永不显示、永不重建网格。
	#
	# 本段保留的是一条**反向钉子**，不是"顺手把旧断言删掉"：世界环一旦又被打开，
	# 角色身上会重新亮起一圈、和 HUD 图标上那圈同时存在 —— 而"HUD 环一切正常"
	# 这一点完全挡不住它（HUD 侧判据全绿）。必须由这里挡。
	if bool(avatar_snapshot.get("reload_ring_in_world", true)):
		failures.append("世界空间换弹环的开关被打开了（换弹环现在只归 HUD 武器图标）")
	if bool(avatar_snapshot.get("reload_bar_visible", false)):
		failures.append("世界空间换弹环已退役，却在换弹时仍被显示")
	if _arc_triangle_count(player.avatar) != 0:
		failures.append(
			"退役的世界换弹环仍在重建网格（%d 个三角面）" % _arc_triangle_count(player.avatar)
		)
	# 退役后上面那些世界环的读数（下方锚点 / 正对镜头 / 横向让位 / 离地 / 压在角色之上）
	# 已成常量值，不再作为契约；它们仍在 `get_component_snapshot()` 里留着，
	# 供开关改回 true 时恢复判据 —— 那时的判据文本见 git 历史与本条 CHANGELOG 追记。

	var machine := player.get("_state_machine") as StateMachine
	machine.transition_to("moving")
	player.velocity = Vector3(4.0, 0.0, 0.0)
	var reload_duration := float(reload_snapshot.get("duration", player.weapon.reload_time))
	var ammo_before_blocked_fire := player.weapon.current_ammo
	if player.weapon.try_fire(Vector3.FORWARD, player) or player.weapon.current_ammo != ammo_before_blocked_fire:
		failures.append("Reloading weapon can still fire")
	player.weapon.call("_process", reload_duration * 0.5)
	player.avatar.call("_process", 0.2)
	state_snapshot = player.get_state_machine_snapshot()
	reload_snapshot = player.get_reload_snapshot()
	avatar_snapshot = player.avatar.get_component_snapshot()
	var mid_progress := float(reload_snapshot.get("progress", 0.0))
	if str(state_snapshot.get("current", "")) != "moving" or not bool((state_snapshot.get("overlays", {}) as Dictionary).get("reloading", false)):
		failures.append("Reload overlay does not coexist with moving")
	if mid_progress < 0.48 or mid_progress > 0.52:
		failures.append("Reload progress is not driven by the real weapon timer: %.3f" % mid_progress)
	# 半程这一采样点也要确认世界环**一个三角面都没重建**：只看换弹开始时那一次，
	# 会放过"开局不建、换弹中途才建"这种形态（而它同样是两圈同时在画面上）。
	if _arc_triangle_count(player.avatar) != 0:
		failures.append(
			"退役的世界换弹环在换弹进行中被重建了（%d 个三角面）" % _arc_triangle_count(player.avatar)
		)
	if (
		(avatar_snapshot.get("reload_offset", Vector3.ZERO) as Vector3).length() > 0.001
		or (avatar_snapshot.get("reload_rotation", Vector3.ZERO) as Vector3).length() > 0.001
		or str(avatar_snapshot.get("missing_authored_action", "")) != ""
		or str(avatar_snapshot.get("authored_overlay_clip", "")) != "sidearm_reload"
		or absf(float(avatar_snapshot.get("authored_overlay_progress", -1.0)) - mid_progress) > 0.001
	):
		failures.append("Reload did not sample the authored sidearm overlay from the gameplay progress")
	var mid_right_grip_distance := float(avatar_snapshot.get("hand_r_to_socket_global_distance", 999.0))
	if (
		str(avatar_snapshot.get("weapon_pose_state", "")) != "sidearm_reload"
		or int(avatar_snapshot.get("active_grip_hand_count", 0)) != 1
		or mid_right_grip_distance > 0.189
		or absf(mid_right_grip_distance - base_right_grip_distance) > 0.0615
	):
		failures.append(
			"Reload animation detached the pistol's single right grip from the weapon "
			+ "(base=%.4f mid=%.4f state=%s class=%s)" % [
				base_right_grip_distance,
				mid_right_grip_distance,
				str(avatar_snapshot.get("weapon_pose_state", "")),
				str(avatar_snapshot.get("weapon_class", "")),
			]
		)

	# 推到接近满进度（≈0.99）：世界环退役后这里没有"弧有没有合拢成整圈"可验了
	# —— 那一条随世界环一起下线，圆环的合拢改在 HUD 环上验（`verify_reference_hud_fate_visual`）。
	player.weapon.call("_process", reload_duration * 0.49)
	player.avatar.call("_process", 0.2)

	player.weapon.call("_process", reload_duration)
	player.avatar.call("_process", 0.2)
	state_snapshot = player.get_state_machine_snapshot()
	avatar_snapshot = player.avatar.get_component_snapshot()
	if bool((state_snapshot.get("overlays", {}) as Dictionary).get("reloading", true)):
		failures.append("Completed reload left the state-machine overlay active")
	if bool(avatar_snapshot.get("reload_bar_visible", true)):
		failures.append("Completed reload left the retired world-space ring visible")
	if player.weapon.current_ammo != magazine_size:
		failures.append("Completed reload did not refill the magazine")
	if ended_results != [true]:
		failures.append("Normal reload did not emit exactly one completed lifecycle event")
	if progress_samples.is_empty() or progress_samples.front() != 0.0 or progress_samples.back() != 1.0:
		failures.append("Reload progress lifecycle does not run from zero to one")
	else:
		for index in range(1, progress_samples.size()):
			if progress_samples[index] + 0.0001 < progress_samples[index - 1]:
				failures.append("Reload progress regressed before normal completion")
				break

	progress_samples.clear()
	player.weapon.current_ammo = maxi(0, magazine_size - 2)
	player.weapon.request_reload()
	player.weapon.call("_process", reload_duration * 0.25)
	if not player.refill_ammo():
		failures.append("Instant ammo refill failed during reload")
	player.avatar.call("_process", 0.2)
	if player.is_reloading() or bool(player.avatar.get_component_snapshot().get("reload_bar_visible", true)):
		failures.append("Ammo refill did not cancel the reload overlay and ring")
	if ended_results != [true, false]:
		failures.append("Cancelled reload did not publish a distinct incomplete lifecycle event")

	player.weapon.current_ammo = maxi(0, magazine_size - 3)
	player.weapon.request_reload()
	if not player.equip_weapon("bp_shotgun", "mod_bullet_standard"):
		failures.append("Cannot swap gun body during reload acceptance")
	player.avatar.call("_process", 0.2)
	var swapped_weapon := player.get_weapon_snapshot()
	if (
		player.is_reloading()
		or str(swapped_weapon.get("gun_id", "")) != "bp_shotgun"
		or int(swapped_weapon.get("current_ammo", 0)) != int(swapped_weapon.get("magazine_size", -1))
		or bool(player.avatar.get_component_snapshot().get("reload_bar_visible", true))
	):
		failures.append("Weapon swap did not atomically cancel old reload state and initialize the new gun")
	if ended_results != [true, false, false]:
		failures.append("Weapon swap did not close the previous reload lifecycle exactly once")

	player.weapon.current_ammo = maxi(0, player.weapon.magazine_size - 1)
	player.weapon.request_reload()
	player.take_damage(player.max_hp + 1)
	player.avatar.call("_process", 0.2)
	if (
		player.get_state_machine_state() != "dead"
		or player.is_reloading()
		or bool(player.avatar.get_component_snapshot().get("reload_bar_visible", true))
	):
		failures.append("Death did not cancel reload and hide the under-character ring")
	if ended_results != [true, false, false, false]:
		failures.append("Death did not close the reload lifecycle exactly once")

	player.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("3D_RELOAD_STATE_FLOW_OK: reload overlay, real timer, weapon-class grip animation, world-space ring stays retired (no mesh rebuild, never visible), completion and cancellation pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## 「顶层玩家状态」的期望值 —— 从 Player3D._build_state_machine() 的源码里数 register()，
## 而不是写死一个数字。写死的那一版在 seated / climbing 加入后就成了陈旧红项。
func _registered_top_level_state_count() -> int:
	var source := FileAccess.get_file_as_string("res://src/player3d/Player3D.gd")
	var count := 0
	for line in source.split("\n"):
		if line.strip_edges().begins_with("_state_machine.register("):
			count += 1
	return count


## —— 换弹环的几何复核（退役期）——
## 世界空间换弹环已退役（`PlayerAvatar3D.RELOAD_RING_IN_WORLD = false`），
## 本段只剩一条**反向钉子**：`Fill` 的网格永远不许被重建（三角面数恒为 0）。
## 原先还有四个助手 —— `_arc_radii_mesh`（弧带内外半径）、
## `_ring_camera_alignment`（环面是否正对镜头）、`_ring_anchor_scale`
## （mesh 半径 × 锚点缩放 = 世界半径）、`_ring_clearance_from_character`
## （相机平面里判环有没有压在角色轮廓上）—— 世界环退役后它们没有可测对象，
## 随环一起下线；判据的由来与推导留在 `PlayerAvatar3D` 的 `RELOAD_RING_*`
## 常量注释与 `docs/v0.2/PLAN.md` 的 `0.2-PLAYER-001` 追记里，开关改回 true 时照那里恢复。

## Fill 的三角面数。空网格（进度 0）返回 0。
##
## ⚠️ 必须走 `as ArrayMesh` 拿类型**再判空**，不能写成 `fill.mesh == null` 后直接
## `(fill.mesh as ArrayMesh).get_surface_count()` —— 退役期节点上的 mesh 是 prefab 里
## 那个 `QuadMesh`（`MeshReloadFill`），它非空、却 cast 不成 ArrayMesh，第三种写法会
## 在 null 上调方法、把引擎错误写进日志（验收门禁 `check_verification_log.py` 因此判红）。
func _arc_triangle_count(avatar: PlayerAvatar3D) -> int:
	var fill := _reload_ring_fill(avatar)
	if fill == null:
		return 0
	var mesh := fill.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var indices: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	return indices.size() / 3


func _reload_ring_fill(avatar: PlayerAvatar3D) -> MeshInstance3D:
	return avatar.get_node_or_null("ReloadProgress3D/Fill") as MeshInstance3D
