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

	# 本场景默认没有相机，环的朝向分支会走「无相机 ⇒ 保留 prefab 朝向」那条，
	# 于是「正对镜头」这条判据在验收里压根走不到。这里按 TowerDescent3D 的
	# CAMERA_*（位置 = 玩家 + (0, 10.719009, 4.037671)，注视点 = 玩家 + (0, 0.45, -0.75)）
	# 摆一台真相机 —— 整条相机链的倾角、以及「环离地」都按这套数算。
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.0, 10.719009, 4.037671)
	camera.look_at(Vector3(0.0, 0.45, -0.75), Vector3.UP)
	camera.make_current()

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
	# 2026-10-04：换弹表现由「头顶横向条」改为「角色下方圆环」（0.2-PLAYER-001）。
	# 进度不再走 fill.scale.x，而是按角度裁切圆弧 —— 判据换成 reload_ring_progress。
	if not bool(avatar_snapshot.get("reload_bar_visible", false)) or float(avatar_snapshot.get("reload_ring_progress", -1.0)) != 0.0:
		failures.append("角色脚下换弹环在进度 0 时没有显示成空环")
	# 2026-10-05：口径由「平铺地面」改成「正对镜头 + 画在角色之上」。
	# 锚点仍在角色下方、仍在 VisualRoot 之外（不随瞄准朝向立起来）。
	if (
		not bool(avatar_snapshot.get("reload_bar_outside_visual_root", false))
		or not bool(avatar_snapshot.get("reload_bar_below_character", false))
	):
		failures.append("换弹环没有挂在角色下方的独立锚点上（会随瞄准朝向立起来 / 挂回头顶）")
	# 环面必须正对镜头：相机基的 +Z 指向观察者，环网格正面法线也是 +Z ⇒ 点积 = 1。
	# ⚠️ 判据的量级要说清楚：本作相机离竖直只有 29.42°
	# （相机在玩家系 (0, 10.269009, 4.787671)、注视点 (0, 0.45, -0.75)，
	# 相机→焦点 = (0, -9.819009, -5.537671)，atan(5.537671/9.819009)），
	# 所以「平铺地面」（法线朝上）也有 cos(29.42°) ≈ 0.871 ——
	# 这条断言区分的是 1.000 / 0.871，不是 1 / 0。
	# 阈值取 0.999：容得下浮点误差，容不下那 29.42° 的倾角。
	var ring_alignment := _ring_camera_alignment(player.avatar, camera)
	if ring_alignment < 0.999:
		failures.append(
			"换弹环没有正对镜头（环面法线与相机视轴点积 %.4f；平铺地面时约 0.871）" % ring_alignment
		)
	# 快照里那份对齐度必须与实测对得上，否则它就是个没人维护的摆设。
	var reported_alignment := float(avatar_snapshot.get("reload_ring_camera_alignment", -1.0))
	if absf(reported_alignment - ring_alignment) > 0.001:
		failures.append(
			"快照里的换弹环朝向与实测不一致（快照 %.4f / 实测 %.4f）" % [reported_alignment, ring_alignment]
		)
	# 2026-10-08：环要「贴到角色右边、别压人」。方向和大小**都要**验 ——
	# 只验大小会放过「让到了角色左边」，只验方向会放过「让得太远/太近」。
	var lateral_world := avatar_snapshot.get("reload_ring_lateral_offset_world", Vector3.ZERO) as Vector3
	var expected_lateral := (
		float(avatar_snapshot.get("reload_ring_lateral_offset_m", 0.0))
		* float(avatar_snapshot.get("runtime_scale_multiplier", 1.0))
	)
	if absf(lateral_world.length() - expected_lateral) > 0.01:
		failures.append(
			"换弹环的横向让位量对不上标定值（实测 %.4f m，期望 %.4f m = 设计值 × 体型倍率）"
			% [lateral_world.length(), expected_lateral]
		)
	var camera_right := camera.global_transform.basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	if lateral_world.length() > 0.001 and lateral_world.normalized().dot(camera_right) < 0.999:
		failures.append(
			"换弹环没有让到角色的屏幕右侧（让位方向与相机基 +X 点积 %.4f）"
			% lateral_world.normalized().dot(camera_right)
		)
	# 「别压人」的**可测代理**：在相机平面里判环与角色轮廓有没有相交（见下面对该
	# 判据的说明）。带 headless 也测得了，因为 AABB 不需要渲染；环居中时环心投影 ≈ 0，
	# 这条必然为负 —— 它就是那次返工的钉子。
	# 真实观感（线宽、颜色、有没有真的"贴边站"）由 preview_reload_ring 出图兜底，
	# 那台探针不参与自动验收。
	var ring_clearance := _ring_clearance_from_character(
		player.avatar, camera, float(avatar_snapshot.get("reload_ring_outer_radius_m", 0.0))
		* float(avatar_snapshot.get("runtime_scale_multiplier", 1.0))
	)
	if ring_clearance < 0.0:
		failures.append(
			"换弹环压在角色身上（在相机平面里与角色轮廓相交 %.4f m）" % -ring_clearance
		)
	# 「层级还是在角色上方」：环心在角色下半身，不关深度测试就会被腿切掉半圈。
	if not bool(avatar_snapshot.get("reload_ring_draws_over_character", false)):
		failures.append("换弹环没有画在角色之上（深度测试没关）—— 上半圈会被腿切掉")
	# 进度 0 时圆弧必须是**空网格**：不是「缩小到看不见」，是压根没有三角面。
	if _arc_triangle_count(player.avatar) != 0:
		failures.append("进度 0 时换弹环还画着圆弧（%d 个三角面）" % _arc_triangle_count(player.avatar))
	# 填充不能与底轨共面：两个共面半透明面深度相等、排序不稳定，画面上会闪。
	# 原横条就是靠 Fill 前压 0.012 解决的，换成环之后这条同样得留着。
	var track_node := player.avatar.get_node_or_null("ReloadProgress3D/Track") as MeshInstance3D
	if (
		track_node == null
		or _reload_ring_fill(player.avatar) == null
		or _reload_ring_fill(player.avatar).position.z - track_node.position.z < 0.005
	):
		failures.append("换弹环的填充与底轨共面（没有前压）—— 半透明面会闪")

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
	if absf(float(avatar_snapshot.get("reload_ring_progress", 0.0)) - mid_progress) > 0.01:
		failures.append("角色脚下换弹环的圆弧没有跟上武器换弹进度")
	# 圆弧要真的「扫」出来：半程的三角面数应约等于分段数的一半，内外半径等于标定值
	# （世界外半径 = mesh 半径 × 锚点缩放）。只看 reload_ring_progress 挡不住
	# 「进度对了、网格没重建」这种静默失效。
	var mid_triangles := _arc_triangle_count(player.avatar)
	var mid_radii := _arc_radii_mesh(player.avatar)
	if mid_triangles < 60 or mid_triangles > 68:
		failures.append("半程圆弧的三角面数不对（%d，期望约 64 = 64 段的一半 × 2）" % mid_triangles)
	if mid_radii.x <= 0.0 or mid_radii.y <= mid_radii.x:
		failures.append("半程圆弧不是环带（内外半径 %.4f / %.4f）" % [mid_radii.x, mid_radii.y])
	else:
		# 世界半径 = 设计半径（角色母版尺寸）× 角色运行时体型倍率：
		# 环必须**跟着角色缩放**，不能在角色被调大调小时脱钩。
		var mid_outer_world := mid_radii.y * _ring_anchor_scale(player.avatar)
		var expected_outer := (
			float(avatar_snapshot.get("reload_ring_outer_radius_m", 0.0))
			* float(avatar_snapshot.get("runtime_scale_multiplier", 1.0))
		)
		if absf(mid_outer_world - expected_outer) > 0.01:
			failures.append(
				"换弹环没有随角色缩放（世界外半径实测 %.4f m，期望 %.4f m = 设计值 × 体型倍率）"
				% [mid_outer_world, expected_outer]
			)
		# 环还必须整个**离地**：正对镜头时环面离水平就是相机倾角，竖直方向铺开
		# r × |sin(倾角)| = r × 法线水平分量长度。最低点 ≤ 0 就是插进地板 ——
		# 画面上会重新读成「地上画的圈」，那正是 2026-10-05 被否掉的一版。
		var ring_node := player.avatar.get_node_or_null("ReloadProgress3D") as Node3D
		var ring_normal := ring_node.global_transform.basis.z.normalized()
		var ring_lowest_m := (
			ring_node.global_position.y
			- mid_outer_world * Vector2(ring_normal.x, ring_normal.z).length()
		)
		if ring_lowest_m <= 0.0:
			failures.append("换弹环下半圈插进了地板（最低点 %.4f m）" % ring_lowest_m)
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

	# 弧要能合拢成整圈：再推 49% ⇒ 总进度 ≈ 0.99，三角面数应贴近满段数。
	player.weapon.call("_process", reload_duration * 0.49)
	player.avatar.call("_process", 0.2)
	var full_triangles := _arc_triangle_count(player.avatar)
	if full_triangles < 126 or full_triangles > 130:
		failures.append("接近满进度时换弹环没有合拢成整圈（%d 个三角面，期望 128）" % full_triangles)

	player.weapon.call("_process", reload_duration)
	player.avatar.call("_process", 0.2)
	state_snapshot = player.get_state_machine_snapshot()
	avatar_snapshot = player.avatar.get_component_snapshot()
	if bool((state_snapshot.get("overlays", {}) as Dictionary).get("reloading", true)):
		failures.append("Completed reload left the state-machine overlay active")
	if bool(avatar_snapshot.get("reload_bar_visible", true)):
		failures.append("Completed reload left the under-character ring visible")
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
		print("3D_RELOAD_STATE_FLOW_OK: reload overlay, real timer, weapon-class grip animation, camera-facing ring offset to the right of the character (clear of its silhouette), completion and cancellation pass")
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


## —— 换弹环的几何复核 ——
## 光看 reload_ring_progress 挡不住「进度值对了、网格却没重建」这种静默失效
## （InteractionDot3D 就踩过绕序被剔除、scale 被 billboard 吃掉的同类坑）。
## 这里直接扫 Fill 的网格：三角面数证明弧在按进度扫，半径证明它是环带而不是圆盘。

## Fill 的三角面数。空网格（进度 0）返回 0。
func _arc_triangle_count(avatar: PlayerAvatar3D) -> int:
	var fill := _reload_ring_fill(avatar)
	if fill == null or fill.mesh == null or (fill.mesh as ArrayMesh).get_surface_count() == 0:
		return 0
	var indices: PackedInt32Array = (fill.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	return indices.size() / 3


## 圆弧网格的半径区间（mesh 局部；x = 内半径、y = 外半径）。空网格返回 (-1, -1)。
func _arc_radii_mesh(avatar: PlayerAvatar3D) -> Vector2:
	var fill := _reload_ring_fill(avatar)
	if fill == null or fill.mesh == null or (fill.mesh as ArrayMesh).get_surface_count() == 0:
		return Vector2(-1.0, -1.0)
	var vertices: PackedVector3Array = (fill.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lowest := 1.0e9
	var highest := 0.0
	for vertex in vertices:
		var radius := Vector2(vertex.x, vertex.y).length()
		lowest = minf(lowest, radius)
		highest = maxf(highest, radius)
	return Vector2(lowest, highest)


func _reload_ring_fill(avatar: PlayerAvatar3D) -> MeshInstance3D:
	return avatar.get_node_or_null("ReloadProgress3D/Fill") as MeshInstance3D


## 环面法线（网格正面 = 局部 +Z）与相机视轴的对齐度。
## 1 = 正对镜头；0 = 平铺在地面上（法线朝上）。这里自己算，不读快照 ——
## 读快照就成了「用被测对象证明被测对象」。
func _ring_camera_alignment(avatar: PlayerAvatar3D, camera: Camera3D) -> float:
	var ring := avatar.get_node_or_null("ReloadProgress3D") as Node3D
	if ring == null or camera == null:
		return -1.0
	var ring_normal := ring.global_transform.basis.z.normalized()
	var camera_normal := camera.global_transform.basis.z.normalized()
	return ring_normal.dot(camera_normal)


## 锚点（ReloadProgress3D）当前的总缩放：mesh 半径 × 它 = 世界半径。
func _ring_anchor_scale(avatar: PlayerAvatar3D) -> float:
	var anchor := avatar.get_node_or_null("ReloadProgress3D") as Node3D
	if anchor == null:
		return 0.0
	return anchor.global_transform.basis.get_scale().x


## 「环没压在角色身上」的余量（米，正数 = 让开了，≤ 0 表示压上了）。
##
## 判据走**相机平面**，不是单轴投影：
## 把角色**本体**（VisualRoot 下的网格，**排除手持武器** —— 枪管伸得比身体远得多）
## 每个网格的 AABB 八顶点投到相机的 (right, up) 两个基向量上，得到它在屏幕平面里的
## 2D 包围盒；再算环心到这个盒子的最近距离，与环世界半径比。
##
## ⚠️ 只投一条轴（right）是不够的 —— 第一版就这么写的，结果**误报**：
## 换弹那把枪横在角色右上，它的横向投影天然越线，纵向却离环很远，屏幕上压根没重叠。
## 2D 判定把"横越线但纵不搭界"这种情况正确放行了。
##
## 为什么要排除武器而不是靠 2D 判定：枪是**手持道具**，它会随换弹动画大幅摆动，
## 算进去这条断言就变成了"枪的动画有没有跑偏"，而不是"环有没有压人"。
func _ring_clearance_from_character(
	avatar: PlayerAvatar3D, camera: Camera3D, ring_radius_world: float
) -> float:
	var ring := avatar.get_node_or_null("ReloadProgress3D") as Node3D
	var visual := avatar.get_node_or_null("VisualRoot") as Node3D
	if ring == null or visual == null:
		return -999.0
	var basis := camera.global_transform.basis
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	var up := basis.y
	up.y = 0.0
	up = up.normalized()
	var ring_center := Vector2(ring.global_position.dot(right), ring.global_position.dot(up))
	var weapon_socket := avatar.get_node_or_null("VisualRoot/BunnyRig/WeaponSocket") as Node3D
	var closest := 999.0
	var found := false
	for entry in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := entry as MeshInstance3D
		if weapon_socket != null and weapon_socket.is_ancestor_of(mesh):
			continue
		# 必须滤掉**不可见**网格：bunny01 是叠在旧胶囊化身之上的，旧那套
		# Body/Head/Scarf/StateVFX 网格仍在树里、却全被藏起来（实测一次能列出 24 个）。
		# 不滤的话量到的是"隐藏的装饰环" —— LockRing / LowHealthRing / Scarf 领圈
		# 都是半径 0.5~0.67 m 的对称环，任何贴边的进度环都会被判成"压在角色身上"。
		if not mesh.is_visible_in_tree():
			continue
		found = true
		var box := mesh.get_aabb()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for index in range(8):
			var corner := mesh.global_transform * box.get_endpoint(index)
			var point := Vector2(corner.dot(right), corner.dot(up))
			lo = lo.min(point)
			hi = hi.max(point)
		closest = minf(closest, ring_center.distance_to(ring_center.clamp(lo, hi)))
	if not found:
		return -999.0
	return closest - ring_radius_world
