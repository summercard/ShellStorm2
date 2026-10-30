extends Node
## 战斗高度面探针（2026-10-30）：**怪物的碰撞柱是否落在玩家子弹那条水平带里**。
##
## 业主报单（第二次）：「这只怪物无法打中人，玩家子弹也打不中。特别是释放技能瞬间移动后。」
## 上一轮把「双向都打不中」判给了「瞬移出房」（`2026-10-30_expedition03_blink_out_of_room.md`），
## 那确实是一个真 bug，但**它不是这个症状的唯一来源**，而且修完症状仍在 ——
## 说明还有第二个、更基础的病灶没被量到。
##
## 本轮换一条判据：不问「它在哪」，问「它和玩家在不在同一个**高度**上」。
##
## ## 为什么"高度"是这套战斗的硬约束
## 本作的射击是**纯水平**的：
##   · 玩家瞄准 `Player3D._update_aim_from_mouse()`：`flat_direction.y = 0.0`
##     —— 鼠标射线只用来在水平面上选方向，**朝向没有俯仰**；
##   · 敌方齐射 `Enemy3D._tick_pending_volleys()`：`direction.y = 0.0`；
##   · 双方子弹都以 `move_and_collide` 直线推进，**没有重力、没有下坠**。
## ⇒ 子弹永远是一条**固定高度的水平线**。玩家打得到的一切、怪打得到玩家的一切，
##   都必须和这条线在同一个高度上。
##
## 而 `hover` 怪（空尖弹 / 三色书怪 / 枪法师 / 枪精灵 / 抓握大师）被 `_pin_hover_height()`
## 抬到 `出生点 + 1.6m`，玩家胶囊只有 **0~1.5m** —— 于是这些怪**整只都在玩家头顶之上**，
## 双向零重叠。这不是"难打"，是**在数学上永远打不中**。
##
## ## 本探针量什么
##   ① 玩家胶囊带（从场景读，不写死）
##   ② 玩家枪口高度（从真实 `weapon._muzzle` 读，不写死）
##   ③ 每只 `egt_*` 怪的**世界碰撞柱 y 区间**（从真实 `CollisionShape3D` 的全局变换算）
##   ④ 在枪口高度上从 6m 外打一条**真实物理射线**（走真实碰撞层），看它打不打得到
##   ⑤ 敌方子弹的出生高度是否落在玩家胶囊带内（"它能不能打中你"）
##
## 用法：godot --headless --path . --scene res://tools/_egt_combat_plane_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const SEED_VALUE := 77003244
## 玩家胶囊带的兜底值（读不到玩家时使用）。与 `scenes/Player3D.tscn` 的
## `VirtualCollisionCapsule`（position.y=0.75 / height=1.5）同源。
const PLAYER_BAND_FALLBACK := Vector2(0.0, 1.5)
## 枪口高度的兜底值（读不到武器时使用）。
const MUZZLE_FALLBACK_M := 0.95
## 玩家子弹高度带：枪口上下各这么多米都算"这一枪可能打到"。
## 0.18 ≈ 子弹视觉半径 + 碰撞球半径，属于"擦边"范围。
const MUZZLE_BAND_M := 0.18
## 判定"打得中"的最低重叠高度（米）。取 0.35 —— 比玩家胶囊半径 0.34 略大，
## 保证整颗子弹的横截面都在怪身上，而不是擦个边。
const MIN_OVERLAP_M := 0.35
## 判定"它打得中你"的最低重叠（米）。同上。
const MIN_RECEIVE_OVERLAP_M := 0.30
## 刻意留在枪口带**之上**的怪（豁免，不是漏做）。
##
## `egt_gripmaster` 声明了 `invulnerable_while_others_alive`（房里还有别人时无敌）
## 和 `die_when_others_dead`（清场后自己死）—— 它**按设计不需要被玩家打到**。
## 它悬在 2.2m 是"在玩家头顶盘旋"的形态语言，压到 0.22m 就不叫抓握大师了。
## 但 4.2m（改前）高过房间墙顶，那是真的错：这里同时断言它**低于墙顶**。
const HIGH_HOVER_BY_DESIGN := ["egt_gripmaster"]
## 远征03 房间墙高（米），与 `DungeonRoom3D` 的 `wall_height` 非塔楼分支同值。
## 悬停高于它 ⇒ 俯视相机会越过墙顶看到怪飘在屋外。
const ROOM_WALL_TOP_M := 2.8

var _failures: Array[String] = []
var _rows: Array[Dictionary] = []


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _ready() -> void:
	print("=== EGT_COMBAT_PLANE_PROBE 战斗高度面 ===")
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		print("EGT_COMBAT_PLANE_PROBE_FAIL 场景不是 TowerDescent3D")
		get_tree().quit(1)
		return
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	for _frame in 16:
		await get_tree().process_frame

	var room := _pick_hostile_room(tower)
	if room == null:
		print("EGT_COMBAT_PLANE_PROBE_FAIL 找不到战斗房")
		get_tree().quit(1)
		return

	var player := tower.player
	var player_band := PLAYER_BAND_FALLBACK
	var player_base_y := 0.0
	if player != null:
		var capsule := player.get_node_or_null("VirtualCollisionCapsule") as CollisionShape3D
		if capsule != null and capsule.shape is CapsuleShape3D:
			var shape := capsule.shape as CapsuleShape3D
			var half := shape.height * 0.5
			player_band = Vector2(capsule.position.y - half, capsule.position.y + half)
		player_base_y = player.global_position.y
	var muzzle_h := _measure_muzzle_height(player)
	print("玩家胶囊带 y = [%.2f, %.2f]（相对自身脚底），枪口高度 = %.2f m"
		% [player_band.x, player_band.y, muzzle_h])
	print("玩家子弹高度带 = [%.2f, %.2f]（枪口 ± %.2f）"
		% [muzzle_h - MUZZLE_BAND_M, muzzle_h + MUZZLE_BAND_M, MUZZLE_BAND_M])

	# 把玩家挪到角落，避免射线先撞到玩家自己（上一轮探针踩过的假绿）。
	_clear_player_out_of_way(player, room)

	var injector := preload("res://src/map/MonsterInjector.gd").new()
	var kinds: Array[String] = []
	for kind in Enemy3D.PROFILES.keys():
		if str(kind).begins_with("egt_"):
			kinds.append(str(kind))
	kinds.sort()
	print("\n共 %d 只 egt 怪" % kinds.size())

	for kind in kinds:
		var data := injector.generate_box_enemy(kind, 1, 1)
		if data.is_empty():
			continue
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		if enemy == null:
			continue
		enemy.room_id = room.room_id
		tower.get_node("ActiveEnemies").add_child(enemy)
		enemy.configure_from_enemy_data(data)
		var spawn := room.global_transform * Vector3(0.0, 0.0, 0.0)
		enemy.global_position = spawn
		enemy._home_position = spawn
		enemy._home_initialized = true
		enemy.set_room_bounds(room.global_transform, room.get_dimensions() * 0.5)
		enemy.set_runtime_active(true, true)
		# 悬停是**逐帧 lerp** 的（`_pin_hover_height`，每帧走 1/6），而且只在
		# `_commit_motion` 被调用的帧才推进 —— 等固定帧数量到的是"收敛到一半"的中间值，
		# 两次跑出来的数还不一样（实测 bookllet 一次 1.60、一次 0.83）。
		# 这里直接按真实函数、用足够大的 delta 把它推到稳态，再量。
		# ⚠ 只对**声明了 hover / grab** 的怪推：`_pin_hover_height` 本身没有门，
		#    对地面怪直接调会把它也抬到 1.6m —— 第一版就是这么把 33 只全测成浮空的。
		if enemy._active_profile.get("hover", false) or enemy._active_profile.has("grab"):
			for _snap in 12:
				enemy._pin_hover_height(0.5)
		for _frame in 3:
			await get_tree().physics_frame

		var band := _enemy_world_band(enemy)
		var body_overlap := _overlap(band, player_band)
		# 浮空怪的贴地吸附必须是 0：悬停高度 0.22m < `floor_snap_length` 0.32m，
		# 不关的话每次 `move_and_slide` 都会把它按回地面（"浮空"静默消失）。
		var hovers := bool(enemy._active_profile.get("hover", false)) or enemy._active_profile.has("grab")
		_check(
			(enemy.floor_snap_length <= 0.001) if hovers else (absf(enemy.floor_snap_length - 0.32) < 0.001),
			"%s 的 floor_snap_length=%.2f 不对（浮空怪必须 0、地面怪必须 0.32），悬停会被吸回地面"
			% [kind, enemy.floor_snap_length]
		)
		var receive := _enemy_projectile_origin_y(enemy)
		# ⚠ 这里要判的是**点是否落在玩家胶囊带里**，不是"区间重叠"。
		# 第一版把它写成 `_overlap(Vector2(y,y), band)` —— 零长度区间的重叠恒为 0，
		# 于是 33 只全部假红。判据和被测对象必须同一个形状（点是点、区间是区间）。
		var receive_inside := receive >= player_band.x and receive <= player_band.y

		var ray_hit := _ray_hits_at(enemy, muzzle_h, player_base_y)
		print(
			"  %-24s 世界 y=[%6.2f,%6.2f] 高 %4.2fm  与玩家带重叠 %5.2fm  枪口线 %s  弹道起点 y=%5.2f%s"
			% [
				kind, band.x, band.y, band.y - band.x, body_overlap,
				"命中 ✓" if ray_hit else "打空 ✗", receive,
				"" if receive_inside else "（在玩家带之外 ✗）",
			]
		)
		_rows.append({
			"kind": kind,
			"band": band,
			"overlap": body_overlap,
			"ray": ray_hit,
			"origin_y": receive,
			"receive_inside": receive_inside,
		})
		if HIGH_HOVER_BY_DESIGN.has(kind):
			# 豁免：它按设计不可被攻击。但仍要**低于墙顶**，否则玩家会看到它飘在屋外。
			_check(
				band.x <= ROOM_WALL_TOP_M,
				"%s 悬停脚底 %.2fm 高过房间墙顶 %.2fm —— 俯视相机会看到它飘在墙外"
				% [kind, band.x, ROOM_WALL_TOP_M]
			)
			enemy.queue_free()
			await get_tree().process_frame
			continue
		_check(
			body_overlap >= MIN_OVERLAP_M,
			"%s 碰撞柱 y=[%.2f,%.2f] 与玩家胶囊带 [%.2f,%.2f] 只重叠 %.2fm（< %.2fm）—— 玩家子弹永远打不中它"
			% [kind, band.x, band.y, player_band.x, player_band.y, body_overlap, MIN_OVERLAP_M]
		)
		_check(
			ray_hit,
			"%s 在玩家真实枪口高度 %.2fm 上打不中 —— 瞄准它也会从脚下/头顶穿过" % [kind, muzzle_h]
		)
		if receive >= 0.0:
			_check(
				receive_inside,
				"%s 的弹道起点 y=%.2f 在玩家胶囊带 [%.2f,%.2f] 之外 —— 它打不中你"
				% [kind, receive, player_band.x, player_band.y]
			)
		enemy.queue_free()
		await get_tree().process_frame

	_summarize()
	_finish()


## 选一间普通的战斗房（不要 BOSS / 不要 EVENT）。
func _pick_hostile_room(tower: TowerDescent3D) -> DungeonRoom3D:
	for value in tower._rooms:
		var candidate := value as DungeonRoom3D
		if candidate == null:
			continue
		if str(candidate.room_type) not in Dungeon3D.HOSTILE_ROOM_TYPES:
			continue
		if str(candidate.room_type) == "BOSS":
			continue
		return candidate
	return null


## 玩家枪口相对脚底的高度。读真实 `WeaponModel3D._muzzle`，不写死。
func _measure_muzzle_height(player: Player3D) -> float:
	if player == null:
		return MUZZLE_FALLBACK_M
	var weapon: Variant = player.weapon
	if weapon == null or not is_instance_valid(weapon):
		return MUZZLE_FALLBACK_M
	var muzzle: Variant = weapon._muzzle
	if muzzle == null or not is_instance_valid(muzzle):
		return MUZZLE_FALLBACK_M
	var delta: float = (muzzle as Node3D).global_position.y - player.global_position.y
	# 玩家原地站着（未举枪）时枪口可能藏在身侧；低于膝盖的一律当兜底值。
	if delta <= 0.2:
		return MUZZLE_FALLBACK_M
	return delta


## 把玩家挪到房间角落：射线从怪出发朝 +X，玩家在 -X 角，不会挡路。
func _clear_player_out_of_way(player: Player3D, room: DungeonRoom3D) -> void:
	if player == null:
		return
	var half := room.get_dimensions() * 0.5
	player.global_position = room.global_transform * Vector3(-half.x + 1.6, 0.0, -half.y + 1.6)


## 敌人碰撞柱在世界坐标里的 y 区间。**从真实 `CollisionShape3D` 的全局变换算** ——
## 不用 `shape.height × scale.y` 复算：那只能验证"我理解的公式"，
## 验证不了"节点树里实际挂着的那个形状"（碰撞柱是子节点，会继承父 scale）。
func _enemy_world_band(enemy: Enemy3D) -> Vector2:
	var shape_node := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not (shape_node.shape is CylinderShape3D):
		return Vector2(enemy.global_position.y, enemy.global_position.y)
	var cylinder := shape_node.shape as CylinderShape3D
	var xform := shape_node.global_transform
	var half := cylinder.height * 0.5
	# 圆柱沿本地 Y 轴；取上下两个端面中心的中间值当 y 区间。
	var bottom := (xform * Vector3(0.0, -half, 0.0)).y
	var top := (xform * Vector3(0.0, half, 0.0)).y
	return Vector2(minf(bottom, top), maxf(bottom, top))


## 敌方子弹的出生高度（世界 y）。
## 齐射走 `_fire_projectile(..., origin = global_position)`，所以这里直接调那个函数取口径。
func _enemy_projectile_origin_y(enemy: Enemy3D) -> float:
	if enemy.has_method("egt_projectile_origin_y"):
		return float(enemy.call("egt_projectile_origin_y"))
	# 旧口径：origin = global_position（怪自己的脚底）。
	if enemy._active_profile.has("volley") or enemy._active_profile.has("orbit"):
		return enemy.global_position.y
	return -1.0


## 在玩家枪口高度上从 6m 外打一条真实物理射线（真实碰撞层 0xFFFFFFFF ⇒ 墙会挡）。
## **高度由玩家决定，不由怪决定** —— 上一轮探针就是拿怪自己的高度当射线高度，
## 于是"怪飘在 1.6m、射线也在 1.6m"，永远打得到，把 bug 测成了绿的。
func _ray_hits_at(enemy: Enemy3D, muzzle_h: float, player_base_y: float) -> bool:
	var aim_y := player_base_y + muzzle_h
	var to := Vector3(enemy.global_position.x, aim_y, enemy.global_position.z)
	var from := to + Vector3(6.0, 0.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	# ⚠ **不能 exclude 这只怪自己** —— 第一版排除了它，于是射线永远返回空，
	# 33 只全部报"打空"。那是最典型的假红（把被测目标也排除掉）。
	# 玩家已经被挪到房间角落（`_clear_player_out_of_way`），不需要排任何人。
	var hit := enemy.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Variant = hit.get("collider", null)
	return collider == enemy


## 两个 y 区间的重叠长度（不相交为 0）。
func _overlap(a: Vector2, b: Vector2) -> float:
	var lo := maxf(a.x, b.x)
	var hi := minf(a.y, b.y)
	return maxf(0.0, hi - lo)


func _summarize() -> void:
	if _rows.is_empty():
		return
	var hover_broken: Array[String] = []
	var receive_broken: Array[String] = []
	for row in _rows:
		if float(row["overlap"]) < MIN_OVERLAP_M:
			hover_broken.append("%s(重叠%.2fm)" % [row["kind"], row["overlap"]])
		if not bool(row["receive_inside"]) and float(row["origin_y"]) >= 0.0:
			receive_broken.append("%s(y=%.2f)" % [row["kind"], row["origin_y"]])
	print("\n—— 汇总 ——")
	print("打不中（碰撞柱在玩家子弹带之外）：%d 只 %s"
		% [hover_broken.size(), ", ".join(hover_broken)])
	print("打不到你（弹道起点在玩家胶囊外）：%d 只 %s"
		% [receive_broken.size(), ", ".join(receive_broken)])


func _finish() -> void:
	if _failures.is_empty():
		print("\nEGT_COMBAT_PLANE_PROBE_OK 全部 %d 只怪的碰撞柱都在玩家子弹带里，弹道起点也都在玩家胶囊内" % _rows.size())
		get_tree().quit(0)
		return
	print("\nEGT_COMBAT_PLANE_PROBE_FAIL 共 %d 项：" % _failures.size())
	for line in _failures:
		print("  - %s" % line)
	get_tree().quit(1)
