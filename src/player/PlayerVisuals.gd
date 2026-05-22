extends Node2D

# PlayerVisuals - 挂载在 Player/Body 节点上
# 负责玩家视觉表现（颜色闪烁等）

@onready var tween: Tween = null

var base_modulate: Color = Color(0.85, 0.85, 0.95, 1.0)

func _ready() -> void:
	base_modulate = Color(0.85, 0.85, 0.95, 1.0)

func flash_damage() -> void:
	if tween and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.tween_property(self, "modulate", Color.RED, 0.05)
	tween.chain().tween_property(self, "modulate", base_modulate, 0.05)

func flash_heal() -> void:
	if tween and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.tween_property(self, "modulate", Color.GREEN, 0.05)
	tween.chain().tween_property(self, "modulate", base_modulate, 0.05)