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
	# 2026-10-04：换弹表现由「头顶横向条」改为「角色脚下平铺圆环」（0.2-PLAYER-001）。
	# 进度不再走 fill.scale.x，而是按角度裁切圆弧 —— 判据换成 reload_ring_progress。
	if not bool(avatar_snapshot.get("reload_bar_visible", false)) or float(avatar_snapshot.get("reload_ring_progress", -1.0)) != 0.0:
		failures.append("角色脚下换弹环在进度 0 时没有显示成空环")
	if (
		not bool(avatar_snapshot.get("reload_bar_outside_visual_root", false))
		or not bool(avatar_snapshot.get("reload_ring_ground_flat", false))
		or not bool(avatar_snapshot.get("reload_bar_below_character", false))
	):
		failures.append("换弹环没有平铺在角色脚下的独立锚点上（会随瞄准朝向立起来 / 挂回头顶）")
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
	if (
		(avatar_snapshot.get("reload_offset", Vector3.ZERO) as Vector3).length() > 0.001
		or (avatar_snapshot.get("reload_rotation", Vector3.ZERO) as Vector3).length() > 0.001
		or str(avatar_snapshot.get("missing_authored_action", "")) != "single_hand_reload"
	):
		failures.append("Reload did not keep the base Blender clip and expose the registered shared single_hand_reload gap")
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
		print("3D_RELOAD_STATE_FLOW_OK: reload overlay, real timer, weapon-class grip animation, under-character ring progress, completion and cancellation pass")
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


## 锚点（ReloadProgress3D）当前的总缩放：mesh 半径 × 它 = 世界半径。
func _ring_anchor_scale(avatar: PlayerAvatar3D) -> float:
	var anchor := avatar.get_node_or_null("ReloadProgress3D") as Node3D
	if anchor == null:
		return 0.0
	return anchor.global_transform.basis.get_scale().x
