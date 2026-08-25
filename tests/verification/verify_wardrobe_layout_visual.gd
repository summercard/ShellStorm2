extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const WARDROBE_SCENE: PackedScene = preload("res://scenes/ui/WardrobeMenu3D.tscn")
const PREVIEW_PATH := "res://outputs/verification/wardrobe_layout_3d_icons.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var gameplay_hud := CanvasLayer.new()
	gameplay_hud.name = "HUD"
	gameplay_hud.layer = 10
	add_child(gameplay_hud)
	var leak_probe := Label.new()
	leak_probe.text = "MAIN HUD MUST BE HIDDEN"
	leak_probe.position = Vector2(24, 96)
	leak_probe.add_theme_font_size_override("font_size", 28)
	gameplay_hud.add_child(leak_probe)

	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	player.set_physics_process(false)
	player.camera.current = true
	var wardrobe := WARDROBE_SCENE.instantiate() as WardrobeMenu3D
	wardrobe.set_player(player)
	add_child(wardrobe)
	await get_tree().process_frame
	wardrobe.select_slot("head")
	await get_tree().create_timer(0.5).timeout

	var snapshot := wardrobe.get_wardrobe_snapshot()
	_check(not gameplay_hud.visible, "试衣间打开后主HUD仍可见", failures)
	_check(bool(snapshot.get("category_buttons_on_left", false)), "分类按钮没有整合到左栏", failures)
	_check(not bool(snapshot.get("duplicate_right_categories", true)), "右栏仍存在重复分类按钮", failures)
	_check(float(snapshot.get("right_panel_width", 999.0)) <= 400.0, "右栏宽度没有缩减", failures)
	var icons := wardrobe.find_children("*", "ItemModelIcon3D", true, false)
	_check(icons.size() == CatalogOptionCount.head(), "头部选项3D图标数量不正确：%d" % icons.size(), failures)
	for value in icons:
		var icon := value as ItemModelIcon3D
		_check(int(icon.get_snapshot().get("mesh_count", 0)) > 0, "头部选项存在空3D预览", failures)

	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("试衣间布局预览为空")
	elif image.save_png(PREVIEW_PATH) != OK:
		failures.append("试衣间布局预览无法保存")

	wardrobe.request_close()
	_check(gameplay_hud.visible, "关闭试衣间后主HUD没有恢复", failures)
	player.queue_free()
	if failures.is_empty():
		print("WARDROBE_LAYOUT_VISUAL_OK: HUD hidden, left slot navigation, compact right panel and 3D icons pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


class CatalogOptionCount:
	static func head() -> int:
		return PlayerAvatar3D.CUSTOMIZATION_OPTIONS["head"].size()
