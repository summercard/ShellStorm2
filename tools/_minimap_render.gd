extends SceneTree

## 开发期真实渲染：把 EGT 式小地图画出来存 PNG，供人工目视核对。
##   godot --path <project> --script res://tools/_minimap_render.gd
## 输出：outputs/verification/egt_minimap_corner.png / _full.png
##
## 用 SubViewport 而不是窗口 —— 窗口尺寸在 headless/窗口模式下不可靠
## （2026-10-28 实测：window_set_size 后仍然只渲染 210×174，图被裁掉一大半）。
##
## 不进验收套件 —— 它只负责"看得见"，断言在 verify_tactical_inventory_minimap_flow 里。

const VIEW_SIZE := Vector2i(400, 310)
# 真机面板尺寸：设计盒 458×346 × `HUD_UI_SCALE`(0.80)。出图必须照这个来，
# 否则看不出"满层会不会溢出面板"这类问题。
const REAL_PANEL := Vector2(458.0, 346.0) * 0.80
const OUT_DIR := "res://outputs/verification"

var _vp: SubViewport
var _panel: Control
var _full: Control
var _frames := 0
var _stage := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_vp = SubViewport.new()
	_vp.size = VIEW_SIZE
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	root.add_child(_vp)

	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.055, 0.075)
	bg.size = Vector2(VIEW_SIZE)
	_vp.add_child(bg)

	var script = load("res://src/ui/DungeonMinimap3D.gd")
	var records := _synthetic_floor()

	_panel = script.new()
	_vp.add_child(_panel)
	_panel.position = Vector2(10, 10)
	_panel.size = REAL_PANEL
	_panel.configure(records, {})
	for id in ["room_01", "room_02", "room_03", "room_05"]:
		_panel.reveal_room(id)
	_panel.mark_room_cleared("room_01")
	_panel.mark_room_cleared("room_02")
	_panel.set_current_room("room_03")
	var enemies: Array[Vector3] = [Vector3(58, 0, 6), Vector3(64, 0, -4)]
	_panel.set_enemy_positions(enemies)
	_panel.set_player_state(Vector3(70, 0, 0), Vector3(1, 0, 0))

	_full = script.new()
	_vp.add_child(_full)
	_full.position = Vector2(0, 0)
	_full.size = Vector2(VIEW_SIZE)
	_full.set_full_map_mode(true)
	_full.visible = false
	_full.copy_state_from(_panel)

	print("viewport=", _vp.size, " panel=", _panel.size,
		" scale=", _panel._map_scale(), " bounds=", _panel._floor_bounds_world())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 8:
		_save("egt_minimap_corner.png")
		_panel.visible = false
		_full.visible = true
		return false
	if _frames == 16:
		_save("egt_minimap_full.png")
		return true
	return false


func _save(name: String) -> void:
	var img := _vp.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + "/" + name)
	img.save_png(path)
	print("saved ", path, " ", img.get_size())


func _room(id: String, type_id: String, center: Vector2, w: float, h: float, doors: Array, targets: Dictionary) -> Dictionary:
	return {
		"id": id, "type": type_id, "size": "medium",
		"position": Vector3(center.x, 0.0, center.y),
		"doors": doors, "door_targets": targets,
		"main": true, "parent": "", "index": 0, "vertical_level": 0,
		"custom_dimensions": Vector2(w, h),
		"door_endpoint_owners": {},
	}


## 合成一层：入口 → 宝箱 → 战斗(带支线商店/撤离) → Boss，
## 横向 35m 步长，与 expedition_01 同构，用来一次看全四种图标。
func _synthetic_floor() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var step := 35.0
	result.append(_room("room_01", "SAFE", Vector2(0, 0), 15, 15, ["east"], {"east": "room_02"}))
	result.append(_room("room_02", "STORAGE", Vector2(step, 0), 25, 25, ["west", "east"],
		{"west": "room_01", "east": "room_03"}))
	result.append(_room("room_03", "COMBAT", Vector2(step * 2, 0), 25, 25, ["west", "east", "south"],
		{"west": "room_02", "east": "room_04", "south": "room_05"}))
	result.append(_room("room_04", "BOSS", Vector2(step * 3, 0), 25, 25, ["west"], {"west": "room_03"}))
	result.append(_room("room_05", "SHOP", Vector2(step * 2, step), 25, 25, ["north", "east"],
		{"north": "room_03", "east": "room_06"}))
	result.append(_room("room_06", "EXTRACTION", Vector2(step * 3, step), 25, 25, ["west"], {"west": "room_05"}))
	return result
