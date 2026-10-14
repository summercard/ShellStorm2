class_name DeathBlastZone3D
extends Node3D
## 胖子僵尸死亡自爆留在地面的**持续伤害场**（玩法层，业主 2026-10-14：
## 「在地上留一个持续伤害的范围效果，持续3秒」）。
##
## ⚠ 与视觉 Prefab 的分工（14.6 §1 / §3）：
##   - 本节点只做**结算**：按 `tick_interval` 周期性对半径内的**敌对怪 + 玩家**结算伤害；
##   - 视觉是 `VFX-BLAST-ZONE-3D`（FX01-18），由本节点持有为**子实例**，
##     **刻意不进 `VfxPool3D`** —— 它的生命周期归本节点所有，池化会变成双宿主争抢归还
##     （与 FX01-16 头顶吼叫图标、FX03-03 收音机音符同一口径）。
##
## 选区口径与 `Enemy3D._damage_allies_in_blast` / `_damage_players_in_blast` **完全一致**：
##   - 敌对怪：`GameplaySpatialRegistry3D.query_radius(..., KIND_ENEMY, [room_id])`（同房过滤，
##     门关着时跨房的怪不该被牵连）；
##   - 玩家：`get_tree().get_nodes_in_group("player_3d")` + 3D 球距离。
##
## 首次结算**不在 t=0** —— 死亡瞬间已经结算过一次爆炸伤害（180），
## 第一跳排在 `tick_interval`，避免「爆炸 + 场地」在同一帧双倍命中。
##
## 参数全部来自关卡级 `monster_rules.death_explosion.<kind>.zone`；缺段 / `enabled=false`
## ⇒ 调用方根本不生成本节点，故未配置的关卡（塔楼等）逐行为 0，不引入任何全局状态。

const ZONE_VFX_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_blast_zone_root_top3d.tscn")
const ZONE_VFX_ASSET_ID := "VFX-BLAST-ZONE-3D"

const DEFAULT_DURATION_SEC := 3.0
const DEFAULT_TICK_INTERVAL_SEC := 0.5
const DEFAULT_RADIUS_M := 5.0
const MIN_DURATION_SEC := 0.1
## 跳次边界容差：`_next_tick` 恰好等于 `zone_duration` 时的那一跳**算数**
## （3.0s / 0.5s ⇒ 6 跳：0.5…3.0），浮点误差不该把它丢掉。
const TICK_EPSILON := 0.0001
const FALLBACK_COLOR := Color(1.0, 0.52, 0.18, 1.0)

var zone_radius: float = DEFAULT_RADIUS_M
var zone_duration: float = DEFAULT_DURATION_SEC
var damage_per_tick: int = 0
var tick_interval: float = DEFAULT_TICK_INTERVAL_SEC

var _room_id: String = ""
var _color: Color = FALLBACK_COLOR
var _source_ref: WeakRef = null

var _elapsed: float = 0.0
var _next_tick: float = 0.0
var _active: bool = false
var _ticks_applied: int = 0
var _enemy_hits: int = 0
var _player_hits: int = 0

var _visual: VfxEffectBase3D = null


## 建场：只存参数，不碰场景树（真正的构建在 `activate_zone()`）。
func configure(config: Dictionary) -> void:
	zone_radius = maxf(0.1, float(config.get("radius", DEFAULT_RADIUS_M)))
	zone_duration = maxf(MIN_DURATION_SEC, float(config.get("duration", DEFAULT_DURATION_SEC)))
	damage_per_tick = maxi(0, int(config.get("damage_per_tick", 0)))
	tick_interval = maxf(0.05, float(config.get("tick_interval", DEFAULT_TICK_INTERVAL_SEC)))
	_room_id = str(config.get("room_id", ""))
	var tint: Variant = config.get("color")
	_color = (tint as Color) if tint is Color else FALLBACK_COLOR
	var source: Variant = config.get("source")
	if source is Node3D and is_instance_valid(source):
		_source_ref = weakref(source)
	_next_tick = tick_interval


## 静态工厂：`Enemy3D` 走这条路径生成场地。
##
## 顺序有讲究 —— 先 `configure` → `add_child`（父变换生效）→ 设 `global_position`
## → `activate_zone()` 建视觉。视觉在 `activate()` 里会被设成**世界坐标**，
## 所以必须等本节点落位之后再建，否则视觉会被钉在世界原点（相对本节点错位）。
static func spawn(parent: Node, config: Dictionary) -> DeathBlastZone3D:
	if parent == null or not is_instance_valid(parent):
		return null
	var zone := DeathBlastZone3D.new()
	zone.name = "DeathBlastZone3D"
	zone.configure(config)
	parent.add_child(zone)
	var origin: Variant = config.get("origin")
	if origin is Vector3:
		zone.global_position = origin as Vector3
	zone.activate_zone()
	return zone


## 构建视觉并开始计时。可重复调用（第二次起只重置计时，不重复建视觉）。
func activate_zone() -> void:
	if damage_per_tick <= 0 or tick_interval <= 0.0:
		# 没伤害的场地没有存在意义 —— 不留空节点
		queue_free()
		return
	if _visual == null:
		_build_visual()
	_elapsed = 0.0
	_next_tick = tick_interval
	_active = true
	set_process(true)


func _build_visual() -> void:
	if ZONE_VFX_SCENE == null:
		return
	_visual = ZONE_VFX_SCENE.instantiate() as VfxEffectBase3D
	if _visual == null:
		return
	add_child(_visual)
	# 视觉随本节点（子实例）⇒ 传本节点的世界坐标，其 local 会被归一为 0，
	# 之后本节点若被移动/销毁，视觉跟着走。
	_visual.activate(global_position, _color, zone_radius, {"zone_seconds": zone_duration})


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	# ⚠ 跳次必须**夹在持续时长之内**（`_next_tick <= zone_duration`）。
	# 只写 `while _elapsed >= _next_tick` 会在「一帧跨过末尾」时把**场外时间**也拿去结算 ——
	# 一次卡帧（或测试里一步推进 3 秒）就能让场地多打好几跳伤害。
	while _elapsed >= _next_tick and _next_tick <= zone_duration + TICK_EPSILON:
		_apply_tick()
		_next_tick += tick_interval
	if _elapsed >= zone_duration:
		finish()


## 单跳结算：敌对怪（空间注册表 + 同房过滤）与玩家（player_3d 组）。
func _apply_tick() -> void:
	_ticks_applied += 1
	_damage_enemies()
	_damage_players()


func _damage_enemies() -> void:
	if GameplaySpatialRegistry3D == null:
		return
	var room_filter: Array[String] = []
	if not _room_id.is_empty():
		room_filter.append(_room_id)
	for value in GameplaySpatialRegistry3D.query_radius(
		global_position, zone_radius, [GameplaySpatialRegistry3D.KIND_ENEMY], room_filter
	):
		var target := value as Node3D
		if target == null or target == self or not is_instance_valid(target):
			continue
		if not target.has_method("take_damage"):
			continue
		var offset := target.global_position - global_position
		var direction := offset.normalized() if offset.length_squared() > 0.01 else Vector3.UP
		# 已死的怪由 `Enemy3D.take_damage` 首行自行挡掉，这里不重复判。
		target.call("take_damage", damage_per_tick, false, direction)
		_enemy_hits += 1


func _damage_players() -> void:
	for player in get_tree().get_nodes_in_group("player_3d"):
		var body := player as Node3D
		if body == null or not is_instance_valid(body):
			continue
		var offset := body.global_position - global_position
		if offset.length() > zone_radius:
			continue
		var source := _source_node()
		if source != null and body.has_method("notify_attacked_by"):
			body.call("notify_attacked_by", source)
		if body.has_method("take_damage"):
			body.call("take_damage", damage_per_tick, false, offset.normalized())
			_player_hits += 1


## 收场：停表 + 撤视觉 + 自释放（本节点拥有视觉，故一次性带走）。
func finish() -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	if is_instance_valid(_visual):
		_visual.visible = false
		_visual.process_mode = Node.PROCESS_MODE_DISABLED
		_visual.queue_free()
	_visual = null
	queue_free()


func is_active_zone() -> bool:
	return _active


func _source_node() -> Node3D:
	if _source_ref == null:
		return null
	var node := _source_ref.get_ref() as Node3D
	return node if (node != null and is_instance_valid(node)) else null


## 供验收 / 巡检读取的场地快照。
func get_zone_snapshot() -> Dictionary:
	return {
		"asset_id": ZONE_VFX_ASSET_ID,
		"radius": zone_radius,
		"duration": zone_duration,
		"damage_per_tick": damage_per_tick,
		"tick_interval": tick_interval,
		"room_id": _room_id,
		"active": _active,
		"elapsed": _elapsed,
		"ticks_applied": _ticks_applied,
		"enemy_hits": _enemy_hits,
		"player_hits": _player_hits,
		"has_visual": is_instance_valid(_visual),
	}
