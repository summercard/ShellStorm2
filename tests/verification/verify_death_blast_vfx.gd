extends Node
## 专项验收：胖子僵尸死亡自爆特效（FX01-17 `VFX-DEATH-BLAST-3D`）
## ＋ 自爆地面持续伤害场（FX01-18 `VFX-BLAST-ZONE-3D` 视觉 + `DeathBlastZone3D` 玩法）。
##
## 业主口径（2026-10-14）：「胖子僵尸被打死后自爆没有特效，需要增加一个，
## 并且在地上留一个持续伤害的范围效果，持续3秒」。
##
## 两层验收（规范 docs/v0.1/14.6_特效系统与制作规范.md §6）：
##   A. 机制层：两个 Prefab 的资产契约 / 灯光真源 / 无碰撞体 / 尺寸线性 / 地面平铺；
##   B. 端到端接线层：`Enemy3D._spawn_ground_blast_zone()` 真的把场地生成到树里、落在怪脚下，
##      且场地真的按周期命中「同房 + 半径内」的敌对怪与玩家。
## 每类断言都配对照（未绑 follow / 单侧方向 / 故意倾斜 / 异房 stub）；末尾有防假绿哨兵。

const BLAST_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_death_blast_root_top3d.tscn")
const BLAST_SOURCE_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/mega_explosion_blue/vfx_mega_explosion_blue_source_top3d.tscn")
const ZONE_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_blast_zone_root_top3d.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")

const BLAST_ASSET_ID := "VFX-DEATH-BLAST-3D"
const ZONE_ASSET_ID := "VFX-BLAST-ZONE-3D"
## 两个资产各自定档（2026-10-14 v002 重做：FX01-17 换了造型语言 ⇒ 升版；FX01-18 未动）
const EXPECTED_BLAST_VERSION := "v007"
const EXPECTED_ZONE_VERSION := "v002"

const EXPECTED_BLAST_SOURCE := "MegaExplosionBlue"
const EXPECTED_LIBRARY_LAYERS := ["ChargeupDust", "ChargeupGlow", "ChargeupRays", "ChargeupShell", "EndGlow", "EndNova", "EndShell", "EndSparks", "EndSpikes", "MegaExplosionBlue"]
const EXPECTED_LIGHT_NAME_ZONE := "ZoneLight"
const EXPECTED_ZONE_LIGHT_RANGE_PER_SIZE := 4.5

const ZONE_DEFAULT_SECONDS := 3.0
const ZONE_NODE_MIN := 10
const EXPECTED_PULSE_RINGS := 3
const EXPECTED_EMBERS := 6

## 尺寸线性：size 1.0 与 0.8 的同一子节点 scale 比值 = 1.25
const SIZE_A := 1.0
const SIZE_B := 0.8
const SIZE_RATIO := 1.25
const SIZE_RATIO_TOLERANCE := 0.02

## 有伤害规格时，实际半径优先于表现尺寸参数。
const BLAST_SIZE_FOR_5M := 2.0

const ZONE_RADIUS := 5.0
const ZONE_DURATION := 3.0
const ZONE_DAMAGE_PER_TICK := 24
const ZONE_TICK_INTERVAL := 0.5
const ZONE_ROOM := "room_02"
const ZONE_ROOM_FOREIGN := "room_09"
## duration 3.0 / interval 0.5、首跳排在 0.5 ⇒ 恰好 6 跳
const EXPECTED_ZONE_TICKS := 6

const MIN_SAMPLES := 12

var _failures: Array[String] = []
var _samples := 0
var _steps: Array[Callable] = []
var _step_index := 0


# ---------------------------------------------------------------- 被结算的假目标
## 敌对怪 stub：只实现场地需要的 `take_damage` 契约。
class StubEnemy extends Node3D:
	var hits: Array[int] = []

	func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO) -> void:
		hits.append(amount)


## 玩家 stub：场地会先 `notify_attacked_by(来源)` 再结算伤害。
class StubPlayer extends Node3D:
	var hits: Array[int] = []
	var attributed: Array[Node3D] = []

	func notify_attacked_by(source: Node3D) -> void:
		attributed.append(source)

	func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO) -> void:
		hits.append(amount)


func _ready() -> void:
	# ⚠ 分步执行（不写成 _ready 里一长串同步调用）：
	# 本仓 GDScript 的运行期报错会**中断当前函数**；若全部用例串在 `_ready` 里，
	# 中途一处报错就会跳过 `_report()` ⇒ headless 场景永远挂着（本仓验收的经典假死）。
	# 改成每帧推进一步：单步报错只影响那一帧，后续步骤与收尾报告照常执行。
	_steps = [
		_check_blast_prefab,
		_check_zone_prefab,
		_check_ground_flatness,
		_check_size_linearity,
		_check_zone_damage_selection,
		_check_enemy_caller_wiring,
		_check_collision_free,
	]
	_step_index = 0
	set_process(true)


func _process(_delta: float) -> void:
	if _step_index < _steps.size():
		var step: Callable = _steps[_step_index]
		_step_index += 1
		print("DEATH_BLAST_VFX_STEP %d/%d %s" % [_step_index, _steps.size(), step.get_method()])
		step.call()
		return
	set_process(false)
	_report()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _count_collision_nodes(node: Node) -> int:
	var total := 0
	if node is CollisionObject3D or node is CollisionShape3D:
		total += 1
	for child in node.get_children():
		total += _count_collision_nodes(child)
	return total


## 递归找树里第一个 DeathBlastZone3D（端到端用例用）。
func _find_zone(node: Node) -> DeathBlastZone3D:
	if node is DeathBlastZone3D:
		return node as DeathBlastZone3D
	for child in node.get_children():
		var found := _find_zone(child)
		if found != null:
			return found
	return null


## 该节点是否绑定了「地面平铺」的场件（薄片 / 定环 / 脉冲环）。
func _ground_plane_children(effect: Node3D) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in effect.get_children():
		if child is Node3D and child.name in ["Field", "Edge", "Pulse0", "Pulse1", "Pulse2"]:
			result.append(child as Node3D)
	return result


# ---------------------------------------------------------------- A1 自爆爆炸 Prefab
func _check_blast_prefab() -> void:
	var blast := BLAST_SCENE.instantiate() as VfxEffectBase3D
	if blast == null:
		_failures.append("死亡自爆 Prefab 根节点不是 VfxEffectBase3D")
		return
	add_child(blast)
	blast.activate(Vector3(3.0, -12.0, -4.0), Color(0.55, 0.85, 0.45), BLAST_SIZE_FOR_5M, {"floor_y": -12.65, "blast_visual_radius_m": 5.0, "blast_warning_sec": 1.0})
	_samples += 1

	_expect(blast.get_meta("asset_id") == BLAST_ASSET_ID and blast.get_meta("asset_version") == EXPECTED_BLAST_VERSION,
		"死亡自爆资产身份不正确")
	var library := blast.get_node("LibraryBurst") as Node3D
	var audio := library.get_node("UnityAudioSource") as AudioStreamPlayer
	var source: Dictionary = library.call("debug_exact")
	_expect(blast.get_child_count() == 1, "不得叠加旧飞溅、地贴、灯或冲击波")
	var layer_names: Array = source.layers.keys()
	layer_names.sort()
	_expect(layer_names == EXPECTED_LIBRARY_LAYERS, "原版十个粒子层必须完整：%s" % str(layer_names))
	_expect(library.visible and source.source_id == EXPECTED_BLAST_SOURCE and source.running and source.audio_play_calls == 1,
		"原版开始时应启动一次自带音效")
	_expect(is_equal_approx(library.global_position.y, -12.65) and library.scale.is_equal_approx(Vector3.ONE * (5.0 / 9.0)),
		"原版等比缩放，光核外径须对应 5m 半径")
	var sparks: Dictionary = library.get_node("EndSparks").get("source")
	_expect(sparks.trails.enabled and int(sparks.main.max_particles) == 1000 and is_equal_approx(float(sparks.main.start_delay.constant), 1.75),
		"不得关掉原版拖尾、缩减预算上限或跳过蓄力时间")
	var glow := library.get_node("EndGlow/UnityVfxDrawParticles") as MultiMeshInstance3D
	var glow_material := glow.material_override as ShaderMaterial
	var raw := BLAST_SOURCE_SCENE.instantiate() as Node3D
	raw.set("auto_play", false)
	add_child(raw)
	var raw_glow := raw.get_node("EndGlow/UnityVfxDrawParticles") as MultiMeshInstance3D
	var raw_material := raw_glow.material_override as ShaderMaterial
	_expect(not raw_material.shader.code.contains("blast_center_radius"), "原版素材不得被实例染色污染")
	raw.free()
	var palette: Color = glow_material.get_shader_parameter("blast_core")
	_expect(palette.g > palette.r and palette.r > palette.b, "新版爆破必须是黄绿色")
	var adapted_draws := 0
	for node in library.find_children("*", "GeometryInstance3D", true, false):
		var mat := (node as GeometryInstance3D).material_override as ShaderMaterial
		if mat == null:
			continue
		adapted_draws += 1
		var bounds: Vector4 = mat.get_shader_parameter("blast_center_radius")
		_expect(bounds.is_equal_approx(Vector4(3.0, -12.65, -4.0, 5.0)) and mat.shader.code.contains("if (r >= 1.0) { discard; }"),
			"每个粒子和拖尾绘制件都必须裁到同一个世界空间半径")
	_expect(adapted_draws >= layer_names.size(), "粒子材质验证不完整")
	blast.call("sync_charge", 1.74)
	var charge: Dictionary = library.call("debug_exact")
	_expect(int(charge.layers.EndSparks.live) == 0 and int(charge.layers.ChargeupShell.live) > 0,
		"预警未结束前只有蓄力，不能提前爆开")
	blast.call("detonate")
	var impact: Dictionary = library.call("debug_exact")
	_expect(int(impact.layers.EndSparks.live) > 48, "结算同帧必须出生爆发粒子")
	for _i in 12:
		library.call("advance_exact", 1.0 / 60.0)
	var ribbon := library.get_node_or_null("EndSparks/UnityVfxDrawRibbon") as MeshInstance3D
	_expect(ribbon != null and ribbon.visible, "保留原版的可见拖尾")
	if ribbon != null:
		var rim := ribbon.material_override as ShaderMaterial
		var rim_bounds: Vector4 = rim.get_shader_parameter("blast_center_radius")
		_expect(is_equal_approx(rim_bounds.w, 5.0) and rim.shader.code.contains("if (r >= 1.0) { discard; }"), "懒创建的拖尾也须受半径裁切")
	var explosion: Dictionary = library.call("debug_exact")
	_expect(int(explosion.layers.EndGlow.drawn) > 0 and int(explosion.layers.EndSparks.live) > 48,
		"原版在 1.75s 后完整爆发，不受旧火花上限约束")

	blast.retired.connect(func(_effect: VfxEffectBase3D) -> void: pass)
	for _step in 360:
		library.call("advance_exact", 1.0 / 60.0)
		audio.stop() # 手动步进的无头验收不等待真实音频时钟。
		blast.call("_process", 1.0 / 60.0)
		if not blast.visible:
			break
	_expect(not blast.visible and not library.visible and not library.is_physics_processing(), "源时间线完毕后须回收")
	blast.activate(Vector3(3.0, -12.0, -4.0), Color.WHITE, 2.0, {"floor_y": -12.65, "blast_visual_radius_m": 3.0, "blast_warning_sec": 1.0})
	var reused: Dictionary = library.call("debug_exact")
	_expect(library.visible and not library.is_physics_processing() and reused.audio_play_calls == 2 and float(reused.elapsed) < 0.02,
		"复借须从预警起点重播，仅由预警时钟推进")
	var reused_bounds: Vector4 = glow_material.get_shader_parameter("blast_center_radius")
	_expect(is_equal_approx(reused_bounds.w, 3.0), "复借不能沿用旧半径")
	blast.finish()
	blast.activate(Vector3.ZERO, Color.WHITE, 0.0008, {"prewarm": true})
	var warmed: Dictionary = library.call("debug_exact")
	_expect(not warmed.running and not audio.playing and warmed.audio_play_calls == 2, "预热不能播放原版音频或粒子")

	blast.free()


# ---------------------------------------------------------------- A2 地面伤害场 Prefab
func _check_zone_prefab() -> void:
	var zone := ZONE_SCENE.instantiate() as VfxEffectBase3D
	if zone == null:
		_failures.append("地面伤害场 Prefab 根节点不是 VfxEffectBase3D")
		return
	add_child(zone)
	zone.activate(Vector3(-2.0, 0.0, 6.0), Color(0.55, 0.85, 0.45), ZONE_RADIUS, {})
	_samples += 1

	var snapshot: Dictionary = zone.call("get_presentation_snapshot")
	_expect(String(snapshot.get("asset_id", "")) == ZONE_ASSET_ID,
		"地面伤害场 AssetID 不正确：%s" % snapshot.get("asset_id", ""))
	_expect(String(snapshot.get("asset_version", "")) == EXPECTED_ZONE_VERSION,
		"地面伤害场版本不是 %s：%s" % [EXPECTED_ZONE_VERSION, snapshot.get("asset_version", "")])
	_expect(is_equal_approx(float(snapshot.get("lifetime", 0.0)), ZONE_DEFAULT_SECONDS),
		"地面伤害场默认寿命应为 %.1fs：%.3f" % [ZONE_DEFAULT_SECONDS, float(snapshot.get("lifetime", 0.0))])
	_expect(int(snapshot.get("node_count", 0)) >= ZONE_NODE_MIN,
		"地面伤害场子节点过少，几何未构建：%d" % int(snapshot.get("node_count", 0)))
	_expect(int(snapshot.get("pulse_ring_count", 0)) == EXPECTED_PULSE_RINGS,
		"脉冲环数量应为 %d：%d" % [EXPECTED_PULSE_RINGS, int(snapshot.get("pulse_ring_count", 0))])
	_expect(int(snapshot.get("ember_count", 0)) == EXPECTED_EMBERS,
		"上升余烬数量应为 %d：%d" % [EXPECTED_EMBERS, int(snapshot.get("ember_count", 0))])
	_expect(is_equal_approx(float(snapshot.get("zone_radius", 0.0)), ZONE_RADIUS),
		"场地半径应等于调用方传入的 size %.1f：%.3f" % [ZONE_RADIUS, float(snapshot.get("zone_radius", 0.0))])

	# 持续时长可由 context.zone_seconds 覆盖（必须与玩法节点一致）
	var custom := ZONE_SCENE.instantiate() as VfxEffectBase3D
	add_child(custom)
	custom.activate(Vector3.ZERO, Color.WHITE, ZONE_RADIUS, {"zone_seconds": 7.5})
	_samples += 1
	_expect(is_equal_approx(float((custom.call("get_presentation_snapshot") as Dictionary).get("lifetime", 0.0)), 7.5),
		"地面伤害场未消费 context.zone_seconds：%.3f"
		% float((custom.call("get_presentation_snapshot") as Dictionary).get("lifetime", 0.0)))
	custom.free()

	_expect(bool(snapshot.get("has_zone_light", false)), "地面伤害场缺少 OmniLight3D")
	_expect(String(snapshot.get("light_name", "")) == EXPECTED_LIGHT_NAME_ZONE,
		"场地灯节点名不是 %s：%s" % [EXPECTED_LIGHT_NAME_ZONE, snapshot.get("light_name", "")])
	_expect(not bool(snapshot.get("light_shadows", true)), "场地灯不应投射阴影")
	var birth_energy := float(snapshot.get("light_energy", 0.0))
	var light_range := float(snapshot.get("light_range", 0.0))
	var expected_range := EXPECTED_ZONE_LIGHT_RANGE_PER_SIZE * ZONE_RADIUS
	_expect(absf(light_range - expected_range) < 0.001,
		"场地灯范围应为 %.1fm（4.5 × size %.1f）：%.3f" % [expected_range, ZONE_RADIUS, light_range])
	var lifetime := float(snapshot.get("lifetime", 0.0))
	# 场地有淡入包络（淡入段内从 0 涨起）⇒ t=0 灯能量**应当**为 0，这不是缺陷；
	# 真正要守的是三条：淡入后真的亮着 / 寿命末端收干净 / 显式回收归零（防复借长明）。
	_expect(is_zero_approx(birth_energy), "场地灯在 t=0 应为 0（淡入起点）：%.3f" % birth_energy)
	zone.call("_on_tick", 0.35, lifetime)
	var lit_energy := float((zone.call("get_presentation_snapshot") as Dictionary).get("light_energy", 0.0))
	_expect(lit_energy > 0.0, "淡入结束后场地灯仍未亮起：%.3f" % lit_energy)
	zone.call("_on_tick", lifetime, lifetime)
	var end_energy := float((zone.call("get_presentation_snapshot") as Dictionary).get("light_energy", 1.0))
	_expect(end_energy < 0.01, "寿命末端场地灯未收干净：%.4f" % end_energy)
	zone.call("_on_lifetime_expired")
	var retired_energy := float((zone.call("get_presentation_snapshot") as Dictionary).get("light_energy", 1.0))
	_expect(is_zero_approx(retired_energy), "回收后场地灯能量必须归零（否则复借会长明）：%.4f" % retired_energy)

	zone.free()


# ---------------------------------------------------------------- A3 地面平铺朝向
func _check_ground_flatness() -> void:
	var zone := ZONE_SCENE.instantiate() as VfxEffectBase3D
	if zone == null:
		_failures.append("地面伤害场 Prefab 根节点不是 VfxEffectBase3D（平铺用例）")
		return
	add_child(zone)
	zone.activate(Vector3(1.0, 0.0, 1.0), Color.WHITE, ZONE_RADIUS, {})
	_samples += 1
	var flat_dot := float((zone.call("get_presentation_snapshot") as Dictionary).get("ground_plane_dot_min", -1.0))
	_expect(flat_dot > 0.999,
		"地面平面件未平铺（与世界 UP 的最小点积 %.4f）" % flat_dot)
	# 平面件确实存在（避免「没有件 ⇒ 循环不跑 ⇒ 恰好 1.0」的假绿）
	_expect(_ground_plane_children(zone).size() >= 5,
		"地面平面件数量过少：%d" % _ground_plane_children(zone).size())

	# 对照：故意把一个平地倾斜 90°，同一判据必须塌掉
	var tilted := ZONE_SCENE.instantiate() as VfxEffectBase3D
	add_child(tilted)
	tilted.activate(Vector3.ZERO, Color.WHITE, ZONE_RADIUS, {})
	_samples += 1
	tilted.rotation.x = PI * 0.5
	tilted.call("_on_tick", 0.0, float((tilted.call("get_presentation_snapshot") as Dictionary).get("lifetime", 3.0)))
	var tilted_dot := float((tilted.call("get_presentation_snapshot") as Dictionary).get("ground_plane_dot_min", 1.0))
	_expect(tilted_dot < 0.5,
		"对照失效：倾斜 90° 后平铺判据仍成立（dot=%.4f）" % tilted_dot)

	tilted.free()
	zone.free()


# ---------------------------------------------------------------- A4 尺寸线性
func _check_size_linearity() -> void:
	var blast_a := BLAST_SCENE.instantiate() as VfxEffectBase3D
	var blast_b := BLAST_SCENE.instantiate() as VfxEffectBase3D
	if blast_a == null or blast_b == null:
		_failures.append("死亡自爆 Prefab 实例化失败（尺寸用例）")
		return
	add_child(blast_a)
	add_child(blast_b)
	blast_a.activate(Vector3.ZERO, Color.WHITE, SIZE_A, {})
	blast_b.activate(Vector3.ZERO, Color.WHITE, SIZE_B, {})
	_samples += 1
	var core_a := (blast_a.get_node("LibraryBurst") as Node3D).scale
	var core_b := (blast_b.get_node("LibraryBurst") as Node3D).scale
	_expect(core_a.is_equal_approx(Vector3.ONE * (5.0 / 9.0)) and core_b.is_equal_approx(core_a),
		"无范围规格时默认5m，不随无关 size 参数变化")
	blast_a.free()
	blast_b.free()

	var zone_a := ZONE_SCENE.instantiate() as VfxEffectBase3D
	var zone_b := ZONE_SCENE.instantiate() as VfxEffectBase3D
	if zone_a == null or zone_b == null:
		_failures.append("地面伤害场 Prefab 实例化失败（尺寸用例）")
		return
	add_child(zone_a)
	add_child(zone_b)
	zone_a.activate(Vector3.ZERO, Color.WHITE, SIZE_A, {})
	zone_b.activate(Vector3.ZERO, Color.WHITE, SIZE_B, {})
	_samples += 1
	var field_a := float((zone_a.call("get_presentation_snapshot") as Dictionary).get("field_scale_x", 0.0))
	var field_b := float((zone_b.call("get_presentation_snapshot") as Dictionary).get("field_scale_x", 0.0))
	zone_a.free()
	zone_b.free()
	if field_b <= 0.0:
		_failures.append("尺寸用例：地面场 size %.1f 之下的底面 scale 未测到" % SIZE_B)
	else:
		var field_ratio := field_a / field_b
		_expect(absf(field_ratio - SIZE_RATIO) <= SIZE_RATIO_TOLERANCE,
			"地面场未随 size 线性（比值 %.4f，期望 %.3f）" % [field_ratio, SIZE_RATIO])


# ---------------------------------------------------------------- B 玩法：选区 + 周期
func _check_zone_damage_selection() -> void:
	var origin := Vector3(100.0, 0.0, 100.0)
	var near_same := _spawn_stub(StubEnemy.new(), origin + Vector3(2.0, 0.0, 0.0), ZONE_ROOM)
	var far_same := _spawn_stub(StubEnemy.new(), origin + Vector3(0.0, 0.0, 6.0), ZONE_ROOM)
	var near_foreign := _spawn_stub(StubEnemy.new(), origin + Vector3(0.0, 0.0, 2.0), ZONE_ROOM_FOREIGN)
	var player_near := StubPlayer.new()
	add_child(player_near)
	player_near.add_to_group("player_3d")
	player_near.global_position = origin + Vector3(3.0, 0.0, 0.0)
	var player_far := StubPlayer.new()
	add_child(player_far)
	player_far.add_to_group("player_3d")
	player_far.global_position = origin + Vector3(0.0, 0.0, 11.0)

	# 场地会拿「伤害来源」向玩家交代仇恨（`notify_attacked_by`）——给一个真实来源节点来验它，
	# 否则 `_source_ref` 为空、这条契约就测不到（并非「不调用」）。
	var source := Node3D.new()
	source.name = "BlastSourceStub"
	add_child(source)

	var zone := DeathBlastZone3D.new()
	zone.name = "ZoneSelectionProbe"
	zone.configure({
		"origin": origin,
		"radius": ZONE_RADIUS,
		"duration": ZONE_DURATION,
		"damage_per_tick": ZONE_DAMAGE_PER_TICK,
		"tick_interval": ZONE_TICK_INTERVAL,
		"room_id": ZONE_ROOM,
		"source": source,
	})
	add_child(zone)
	zone.global_position = origin
	zone.activate_zone()
	# 关掉引擎自己驱动的 `_process`：本用例必须**手动步进**，否则帧数与断言值都不确定。
	zone.set_process(false)
	_samples += 1

	# 视觉是子实例（刻意不进 VfxPool3D），且尺寸/时长与场地一致
	var zone_snapshot: Dictionary = zone.get_zone_snapshot()
	_expect(bool(zone_snapshot.get("has_visual", false)), "场地未持有视觉子实例")
	var visual := zone.get_node_or_null("VfxBlastZone3D") as VfxEffectBase3D
	_expect(visual != null, "场地视觉子节点缺失或类型不对")
	if visual != null:
		var visual_snapshot: Dictionary = visual.call("get_presentation_snapshot")
		_expect(String(visual_snapshot.get("asset_id", "")) == ZONE_ASSET_ID,
			"场地视觉 AssetID 不正确：%s" % visual_snapshot.get("asset_id", ""))
		_expect(is_equal_approx(float(visual_snapshot.get("lifetime", 0.0)), ZONE_DURATION),
			"场地视觉寿命应与持续时长一致 %.1fs：%.3f"
			% [ZONE_DURATION, float(visual_snapshot.get("lifetime", 0.0))])

	# 首跳不在 t=0（死亡当帧已结算过一次 180 爆炸，不能同帧双倍命中）
	zone.call("_process", 0.1)
	var pre_snapshot: Dictionary = zone.get_zone_snapshot()
	_expect(int(pre_snapshot.get("ticks_applied", -1)) == 0,
		"首跳错误地发生在 t=0（%d 跳已结算）" % int(pre_snapshot.get("ticks_applied", -1)))
	_expect(near_same.hits.is_empty(), "t=0.1 就命中了同房敌人（首跳应排在 tick_interval）")

	# 第一跳
	zone.call("_process", ZONE_TICK_INTERVAL)
	_expect(near_same.hits.size() == 1 and near_same.hits[0] == ZONE_DAMAGE_PER_TICK,
		"同房 2m 敌人未被命中或伤害不对：%s" % str(near_same.hits))
	_expect(far_same.hits.is_empty(), "6m（超半径）敌人不该被命中：%s" % str(far_same.hits))
	_expect(near_foreign.hits.is_empty(), "跨房 2m 敌人不该被命中（同房过滤）：%s" % str(near_foreign.hits))
	_expect(player_near.hits.size() == 1 and player_near.hits[0] == ZONE_DAMAGE_PER_TICK,
		"半径内玩家未被命中或伤害不对：%s" % str(player_near.hits))
	_expect(player_far.hits.is_empty(), "11m（超半径）玩家不该被命中：%s" % str(player_far.hits))
	_expect(player_near.attributed.size() == 1,
		"场地未向玩家交代仇恨来源（notify_attacked_by 调用 %d 次）" % player_near.attributed.size())

	# 对照：把「跨房那只」改成同房 ⇒ 同一判据下它必须被打到，
	# 证明上一步的 0 是**同房过滤**造成的，不是距离/别的原因。
	GameplaySpatialRegistry3D.register_node(near_foreign, GameplaySpatialRegistry3D.KIND_ENEMY, ZONE_ROOM)
	zone.call("_process", ZONE_TICK_INTERVAL)
	_expect(near_foreign.hits.size() == 1,
		"对照失效：改成同房后仍未被命中（%s）" % str(near_foreign.hits))

	# 到点必须收场
	zone.call("_process", ZONE_DURATION)
	var end_snapshot: Dictionary = zone.get_zone_snapshot()
	_expect(not bool(end_snapshot.get("active", true)), "场地到点仍未停表")
	_expect(not bool(end_snapshot.get("has_visual", true)), "场地到点仍未撤视觉")
	_expect(int(end_snapshot.get("ticks_applied", 0)) == EXPECTED_ZONE_TICKS,
		"场地跳数应为 %d（3.0s / 0.5s，首跳排在 0.5）：%d"
		% [EXPECTED_ZONE_TICKS, int(end_snapshot.get("ticks_applied", 0))])

	for stub in [near_same, far_same, near_foreign, player_near, player_far]:
		GameplaySpatialRegistry3D.unregister_node(stub)
		stub.free()
	source.free()


func _spawn_stub(stub: Node3D, position: Vector3, room: String) -> Node3D:
	add_child(stub)
	stub.global_position = position
	GameplaySpatialRegistry3D.register_node(stub, GameplaySpatialRegistry3D.KIND_ENEMY, room)
	return stub


# ---------------------------------------------------------------- B2 端到端接线
## 走真实调用方：`Enemy3D` 从 `enemy_data.death_explosion.zone` 生成本地场地。
func _check_enemy_caller_wiring() -> void:
	if ENEMY_SCENE == null:
		_failures.append("敌人场景未加载，端到端接线用例未执行")
		return
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	if enemy == null:
		_failures.append("敌人生成场景根节点不是 Enemy3D，端到端接线用例未执行")
		return
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(11.0, 0.0, -7.0)
	enemy.room_id = ZONE_ROOM
	enemy.configure_from_enemy_data({
		"enemy_type": "fat_zombie03",
		"loot_table": "",
		"floor": 0,
		"death_explosion": {
			"enabled": true,
			"damage": 180,
			"radius_m": ZONE_RADIUS,
			"sfx_radius_m": 0.0,
			"zone": {
				"enabled": true,
				"duration_sec": ZONE_DURATION,
				"damage_per_tick": ZONE_DAMAGE_PER_TICK,
				"tick_interval_sec": ZONE_TICK_INTERVAL,
			},
		},
	})
	enemy.room_id = ZONE_ROOM
	var inside := StubPlayer.new()
	var outside := StubPlayer.new()
	for target in [inside, outside]:
		add_child(target)
		target.add_to_group("player_3d")
	inside.global_position = enemy.global_position + Vector3.RIGHT * 4.99
	outside.global_position = enemy.global_position + Vector3.RIGHT * 5.01
	var pool := get_node("/root/VfxPool") as VfxPool3D
	var before_blast := pool.active_count(VfxPool3D.FX01_DEATH_BLAST)
	enemy.call("_detonate_death_explosion")
	_expect(inside.hits == [180] and outside.hits.is_empty(), "瞬爆伤害边界须仍在 5m")
	inside.free()
	outside.free()
	var bucket: Array = pool._active.get(VfxPool3D.FX01_DEATH_BLAST, [])
	_expect(bucket.size() == before_blast + 1, "关卡自爆必须借出新的瞬爆实例")
	if bucket.size() == before_blast + 1:
		var effect := bucket.back() as VfxEffectBase3D
		var library := effect.get_node("LibraryBurst") as Node3D
		_expect(library.scale.is_equal_approx(Vector3.ONE * (5.0 / 9.0)), "实际触发受玩法半径约束")
		_expect(library.global_position.is_equal_approx(enemy.global_position), "实际触发以怪脚下为原点")
		effect.finish()
	_samples += 1

	var zone := _find_zone(self)
	_expect(zone != null, "端到端失效：Enemy3D 未把地面场地生成到场景里")
	if zone != null:
		# 同上：本用例只验「接线是否真的发生」，不接受引擎自动步进带来的不确定性。
		zone.set_process(false)
		var snapshot: Dictionary = zone.get_zone_snapshot()
		_expect(bool(snapshot.get("active", false)), "端到端生成的场地未激活")
		_expect(is_equal_approx(float(snapshot.get("radius", 0.0)), ZONE_RADIUS),
			"端到端场地半径不对：%.3f" % float(snapshot.get("radius", 0.0)))
		_expect(is_equal_approx(float(snapshot.get("duration", 0.0)), ZONE_DURATION),
			"端到端场地时长不对：%.3f" % float(snapshot.get("duration", 0.0)))
		_expect(int(snapshot.get("damage_per_tick", 0)) == ZONE_DAMAGE_PER_TICK,
			"端到端场地每跳伤害不对：%d" % int(snapshot.get("damage_per_tick", 0)))
		_expect(is_equal_approx(float(snapshot.get("tick_interval", 0.0)), ZONE_TICK_INTERVAL),
			"端到端场地结算间隔不对：%.3f" % float(snapshot.get("tick_interval", 0.0)))
		_expect(String(snapshot.get("room_id", "")) == ZONE_ROOM,
			"端到端场地未继承怪物房间：%s" % snapshot.get("room_id", ""))
		# 场地要落在怪脚下（地面高度），不是浮在腰上
		var drift := zone.global_position.distance_to(enemy.global_position)
		_expect(drift < 0.001, "场地未落在怪物脚下：偏差 %.4f m" % drift)
		_expect(zone.global_position.distance_to(Vector3.ZERO) > 1.0,
			"场地位置恰好在世界原点，用例可能没真正测到落点")
		zone.queue_free()

	# 对照：同一只怪、`zone.enabled = false` ⇒ 不得生成任何场地
	var before := _count_zone_nodes(self)
	var enemy_b := ENEMY_SCENE.instantiate() as Enemy3D
	add_child(enemy_b)
	enemy_b.set_physics_process(false)
	enemy_b.global_position = Vector3(21.0, 0.0, -9.0)
	enemy_b.configure_from_enemy_data({
		"enemy_type": "fat_zombie03",
		"loot_table": "",
		"floor": 0,
		"death_explosion": {
			"enabled": true,
			"damage": 180,
			"radius_m": ZONE_RADIUS,
			"sfx_radius_m": 0.0,
			"zone": {
				"enabled": false,
				"duration_sec": ZONE_DURATION,
				"damage_per_tick": ZONE_DAMAGE_PER_TICK,
				"tick_interval_sec": ZONE_TICK_INTERVAL,
			},
		},
	})
	enemy_b.room_id = ZONE_ROOM
	enemy_b.call("_spawn_ground_blast_zone", ZONE_RADIUS)
	_samples += 1
	_expect(_count_zone_nodes(self) == before,
		"对照失效：zone.enabled=false 仍生成了场地（%d -> %d）"
		% [before, _count_zone_nodes(self)])

	enemy_b.queue_free()
	enemy.queue_free()


func _count_zone_nodes(node: Node) -> int:
	var total := 0
	if node is DeathBlastZone3D:
		total += 1
	for child in node.get_children():
		total += _count_zone_nodes(child)
	return total


# ---------------------------------------------------------------- A5 无碰撞体
func _check_collision_free() -> void:
	for entry in [[BLAST_SCENE, BLAST_ASSET_ID], [ZONE_SCENE, ZONE_ASSET_ID]]:
		var packed: PackedScene = entry[0]
		var asset_id := String(entry[1])
		if packed == null:
			_failures.append("%s 场景未加载（无碰撞体用例）" % asset_id)
			continue
		var effect := packed.instantiate()
		var collisions := _count_collision_nodes(effect)
		_expect(collisions == 0, "%s 内出现碰撞体 %d 个（特效必须纯视觉）" % [asset_id, collisions])
		effect.free()
		_samples += 1


func _report() -> void:
	if _samples < MIN_SAMPLES:
		_failures.append("防假绿哨兵：实际样本数 %d 少于预期 %d，验收未真正执行" % [_samples, MIN_SAMPLES])
	if _failures.is_empty():
		print("DEATH_BLAST_VFX_OK: fx01-17 blast + fx01-18 zone pass (samples=%d)" % _samples)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
