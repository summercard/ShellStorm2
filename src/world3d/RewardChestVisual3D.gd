class_name RewardChestVisual3D
extends Node3D
## 宝箱正式 Blender 视觉包装。
## 只提供稳定视觉句柄与品质换色，不参与奖励、交互或动画状态机。
## TreasureChest3D 继续拥有 land/open 的运行时节奏，避免与旧 tween 同时抢属性。

const PALETTE: Texture2D = preload("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")

@export var visual_root_path: NodePath = NodePath("ImportedModel/ChestVisual")
@export var lid_pivot_path: NodePath = NodePath("ImportedModel/ChestVisual/LidPivot")
@export var glow_path: NodePath = NodePath("ImportedModel/ChestVisual/ChestGlow")

var visual_root: Node3D
var lid_pivot: Node3D
var glow: MeshInstance3D
var glow_material: StandardMaterial3D
var body_material: StandardMaterial3D
var trim_material: StandardMaterial3D


func _ready() -> void:
	refresh_handles()


func refresh_handles() -> void:
	var model := get_node_or_null("ImportedModel")
	if model == null:
		return
	visual_root = _find_named_node(model, "ChestVisual")
	if visual_root == null:
		visual_root = model as Node3D
	lid_pivot = _find_named_node(model, "LidPivot")
	glow = _find_named_node(model, "ChestGlow") as MeshInstance3D
	body_material = null
	trim_material = null
	glow_material = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for index in range(mesh.mesh.get_surface_count()):
			var source_material := mesh.get_surface_override_material(index) as StandardMaterial3D
			if source_material == null:
				source_material = mesh.mesh.surface_get_material(index) as StandardMaterial3D
			var material := _make_runtime_material(source_material)
			if material == null:
				continue
			mesh.set_surface_override_material(index, material)
			var role := String(material.resource_name)
			if role.begins_with("02_") and body_material == null:
				body_material = material
			elif role.begins_with("01_") and trim_material == null:
				trim_material = material
			if mesh == glow and glow_material == null:
				glow_material = material


func _make_runtime_material(source: StandardMaterial3D) -> StandardMaterial3D:
	if source == null:
		return null
	var material := source.duplicate() as StandardMaterial3D
	if material == null:
		return null
	# GLB 按规范不内嵌图片；导入后显式重新绑定唯一公共色盘，恢复 Blender 的 PaletteUV 采样。
	material.albedo_texture = PALETTE
	material.albedo_color = Color.WHITE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.resource_local_to_scene = true
	return material


func _find_named_node(root: Node, target_name: String) -> Node3D:
	if (root.name == target_name or root.name.begins_with(target_name + "_")) and root is Node3D:
		return root as Node3D
	for child in root.get_children():
		var found := _find_named_node(child, target_name)
		if found != null:
			return found
	return null


func set_quality_accent(accent: Color) -> void:
	if trim_material != null:
		trim_material.emission_enabled = true
		trim_material.emission = accent
		trim_material.emission_energy_multiplier = 0.75
	if glow_material != null:
		glow_material.emission_enabled = true
		glow_material.emission = accent.lightened(0.25)
		glow_material.emission_energy_multiplier = 3.2


func set_opened_visual_state(accent: Color, glow_energy: float) -> void:
	if glow != null:
		glow.visible = true
	if glow_material != null:
		glow_material.emission_enabled = true
		glow_material.emission = accent.lightened(0.25)
		glow_material.emission_energy_multiplier = glow_energy


func set_visual_visible(enabled: bool) -> void:
	if visual_root != null:
		visual_root.visible = enabled
