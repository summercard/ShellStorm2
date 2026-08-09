extends Node

const EXPECTED_MAIN_SCENE := "res://scenes/TowerDescent3D.tscn"

const REQUIRED_PATHS := [
	"res://scenes/TowerDescent3D.tscn",
	"res://src/player3d/Player3D.gd",
	"res://src/combat3d/WeaponModel3D.gd",
	"res://src/world3d/Dungeon3D.gd",
	"res://src/weapons/WeaponAssemblyTree.gd",
]

const RETIRED_FILES := [
	"res://scenes/Main.tscn",
	"res://scenes/Player.tscn",
	"res://scenes/Enemy.tscn",
	"res://scenes/Bullet.tscn",
	"res://scenes/BaseWorld.tscn",
	"res://scenes/TrainingRange.tscn",
	"res://src/weapons/WeaponCore.gd",
	"res://src/weapons/WeaponPresets.gd",
]

const RETIRED_DIRECTORIES := [
	"res://src/player",
	"res://src/enemy",
	"res://src/bullet",
	"res://src/training",
	"res://src/components",
	"res://src/weapon",
	"res://src/items",
	"res://scenes/levels",
	"res://assets/art/characters/player/chr_player_capsule01",
]


func _ready() -> void:
	var failures: Array[String] = []
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene != EXPECTED_MAIN_SCENE:
		failures.append("Main scene is not the formal 3D entry: %s" % main_scene)
	for path in REQUIRED_PATHS:
		if not FileAccess.file_exists(path):
			failures.append("Required 3D/shared file is missing: %s" % path)
	for path in RETIRED_FILES:
		if FileAccess.file_exists(path):
			failures.append("Retired 2D file returned: %s" % path)
	for path in RETIRED_DIRECTORIES:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			failures.append("Retired 2D directory returned: %s" % path)
	if failures.is_empty():
		print("3D_ONLY_PROJECT_STRUCTURE_OK: formal entry and shared runtime remain; retired 2D roots are absent")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
