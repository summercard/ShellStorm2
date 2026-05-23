extends Node2D

# PlayerVisuals.gd — 玩家视觉表现
# 负责：受伤/治疗闪烁、闪避残影、闪避护盾圈

@onready var tween: Tween = null

var base_modulate: Color = Color(0.85, 0.85, 0.95, 1.0)

# 残影系统
var _ghost_container: Node2D
var _ghost_interval: float = 0.04   # 每隔多少秒生成一个残影
var _ghost_timer: float = 0.0
var _is_dashing: bool = false

# 残影配置
const GHOST_COUNT: int = 5           # 残影数量
const GHOST_LIFETIME: float = 0.25   # 单个残影存活时间（秒）
const GHOST_ALPHA: float = 0.45      # 残影起始透明度

func _ready() -> void:
	base_modulate = Color(0.85, 0.85, 0.95, 1.0)
	_setup_ghost_container()
	_setup_dash_signals()

## 残影容器节点
func _setup_ghost_container() -> void:
	_ghost_container = Node2D.new()
	_ghost_container.name = "GhostContainer"
	_ghost_container.z_index = -1
	var world_parent: Node = get_parent()
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		world_parent = tree.current_scene
	world_parent.add_child.call_deferred(_ghost_container)

## 监听 Player 闪避信号
func _setup_dash_signals() -> void:
	var player: Node = get_parent()
	if player and player.has_signal("dash_started"):
		player.dash_started.connect(_on_dash_started)
	if player and player.has_signal("dash_ended"):
		player.dash_ended.connect(_on_dash_ended)

func _on_dash_started() -> void:
	_is_dashing = true
	_ghost_timer = 0.0

func _on_dash_ended() -> void:
	_is_dashing = false

## 每帧更新残影生成
func _process(delta: float) -> void:
	if _is_dashing:
		_ghost_timer += delta
		if _ghost_timer >= _ghost_interval:
			_ghost_timer = 0.0
			_spawn_ghost()

## 生成闪避残影（复制当前玩家外观）
func _spawn_ghost() -> void:
	var player: Node = get_parent()
	if not player:
		return
	
	# 优先复制程序 emoji；没有 emoji 时再退回 ColorRect 占位形状。
	var source: CanvasItem = player.get_node_or_null("Body/Emoji") as CanvasItem
	if source == null:
		source = player.get_node_or_null("Body/Shape") as CanvasItem
	if source == null:
		return

	var ghost: CanvasItem = source.duplicate() as CanvasItem
	if ghost == null:
		return
	ghost.name = "GhostVisual"
	ghost.modulate = Color(1.0, 1.0, 1.0, GHOST_ALPHA)
	ghost.z_index = player.z_index - 1
	
	_ghost_container.add_child(ghost)
	ghost.global_position = source.global_position
	
	# 残影动画：快速淡出
	var t := ghost.create_tween()
	t.set_parallel(true)
	t.tween_property(ghost, "modulate:a", 0.0, GHOST_LIFETIME).set_trans(Tween.TRANS_QUAD)
	t.chain().tween_callback(ghost.queue_free)
	
	# 控制残影总数量
	_prune_ghosts()

## 清理多余残影
func _prune_ghosts() -> void:
	var children := _ghost_container.get_children()
	if children.size() > GHOST_COUNT:
		var to_remove: Array = children.slice(0, children.size() - GHOST_COUNT)
		for g in to_remove:
			if is_instance_valid(g):
				g.queue_free()

## 受伤闪烁
func flash_damage() -> void:
	if tween and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate", Color.RED, 0.05)
	tween.chain().tween_property(self, "modulate", base_modulate, 0.05)

## 治疗闪烁
func flash_heal() -> void:
	if tween and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate", Color.GREEN, 0.05)
	tween.chain().tween_property(self, "modulate", base_modulate, 0.05)
