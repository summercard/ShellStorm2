extends Node2D
class_name VisionDarknessLayer

# VisionDarknessLayer — 视野遮挡层（动态2D光照系统）
# 挂载在 Main 节点下，作为全局暗色叠加层
# 玩家持有 Light2D，照亮周围区域；墙壁上的 LightOccluder2D 产生实时阴影
# 无需外部资源，纯程序生成

@export var darkness_color: Color = Color(0.03, 0.02, 0.04, 0.88)
@export var player_light_energy: float = 1.0

@onready var _canvas_modulate: CanvasModulate = $Darkness
@onready var _player_light: Light2D = $PlayerLight
@onready var _player: Node2D = get_node_or_null("/root/Main/Player")

var _light_radius: float = 280.0

func _ready() -> void:
	# 基础暗色层
	_canvas_modulate.color = darkness_color
	# 玩家光源：圆形渐变光
	_player_light.texture = _make_light_texture()

func _process(delta: float) -> void:
	# 让光源跟随玩家
	if _player and is_instance_valid(_player):
		_player_light.global_position = _player.global_position
	else:
		var main: Node = get_tree().root.find_child("Main", true, false)
		if main:
			_player = main.find_child("Player", true, false)
			if _player:
				_player_light.global_position = _player.global_position
	
	# 光源呼吸脉动（微妙）
	if _player_light:
		var pulse := 0.88 + 0.12 * sin(Time.get_ticks_msec() * 0.002)
		_player_light.energy = player_light_energy * pulse

## 生成圆形柔光纹理（程序化，无外部文件）
func _make_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.set_offset(0, 0.0)
	gradient.set_offset(1, 1.0)
	
	var tex := GradientTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.origin_aligned = true
	return tex