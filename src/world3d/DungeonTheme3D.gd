class_name DungeonTheme3D
extends Resource
## 3D 关卡表现配置。玩法身份继续由 MapThemeProfile 持有，本资源只描述材质、灯光与空间气质。

@export var theme_id := "iron_frontier"
@export var display_name := "冷钢边境"
@export_multiline var fantasy := ""
@export_range(1, 9, 1) var difficulty_rank := 1

@export_group("Materials")
@export var floor_color := Color(0.12, 0.16, 0.18)
@export var wall_color := Color(0.16, 0.20, 0.22)
@export var trim_color := Color(0.28, 0.40, 0.46)
@export var accent_color := Color(0.32, 0.70, 0.92)
@export var hazard_color := Color(0.92, 0.40, 0.16)
@export var prop_color := Color(0.22, 0.25, 0.24)

@export_group("Lighting")
@export var ambient_color := Color(0.24, 0.32, 0.38)
@export var fog_color := Color(0.045, 0.065, 0.075)
@export var key_light_color := Color(0.56, 0.72, 0.84)
@export_range(0.001, 0.06, 0.001) var fog_density := 0.012
@export_range(0.2, 3.0, 0.05) var ambient_energy := 0.58
@export_range(1.0, 8.0, 0.1) var fixture_energy := 2.6
@export_range(3.0, 16.0, 0.5) var fixture_range := 8.0

@export_group("Content")
@export var enemy_pool: Array[String] = ["melee_chaser", "ranged_caster", "exploder"]
@export var room_sequence: Array[String] = ["COMBAT", "SCAVENGE", "COMBAT", "EVENT"]
@export var furniture_bias: Array[String] = ["crate", "locker", "desk"]


func get_snapshot() -> Dictionary:
	return {
		"theme_id": theme_id,
		"display_name": display_name,
		"difficulty_rank": difficulty_rank,
		"fog_density": fog_density,
		"enemy_pool": enemy_pool.duplicate(),
		"room_sequence": room_sequence.duplicate(),
		"is_3d": true,
	}
