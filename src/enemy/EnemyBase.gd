extends CharacterBody2D

signal hp_changed(current: int, maximum: int)
signal enemy_died()  # 敌人死亡信号

@export var max_hp: int = 30
@export var speed: float = 80.0
@export var damage: int = 10

var current_hp: int = 30
var player_ref: Node2D = null

@onready var shape: ColorRect = $Shape
@onready var hp_bar: ProgressBar = $HPBar

func _ready() -> void:
	current_hp = max_hp
	_add_to_group()

func _physics_process(delta: float) -> void:
	_chase_player(delta)

func _add_to_group() -> void:
	add_to_group("enemy")

func _chase_player(delta: float) -> void:
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player")
		return

	var direction = (player_ref.global_position - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

func take_damage(amount: int) -> void:
	current_hp -= amount
	_update_hp_bar()
	flash_damage()

	if current_hp <= 0:
		die()

func _update_hp_bar() -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp

func flash_damage() -> void:
	if shape:
		var original = shape.color
		shape.color = Color.WHITE
		await get_tree().create_timer(0.05).timeout
		if shape:
			shape.color = original

func die() -> void:
	enemy_died.emit()
	queue_free()