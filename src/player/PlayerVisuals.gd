extends Node2D

@onready var body_sprite: Sprite2D = $BodySprite
@onready var tween: Tween

var base_modulate: Color = Color.WHITE

func _ready() -> void:
	base_modulate = Color(0.85, 0.85, 0.95, 1.0)

func flash_damage() -> void:
	if tween and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.tween_property(self, "modulate", Color.RED, 0.1)
	tween.tween_property(self, "modulate", base_modulate, 0.1)

func flash_heal() -> void:
	if tween and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.tween_property(self, "modulate", Color.GREEN, 0.1)
	tween.tween_property(self, "modulate", base_modulate, 0.1)

func set_weapon_equipped(weapon_id: String) -> void:
	# Load and display weapon sprite based on weapon_id
	pass