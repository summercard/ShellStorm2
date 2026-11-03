extends Node3D
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	for asset_id: StringName in [VfxPool3D.FX01_SPECIAL_FIRE, VfxPool3D.FX01_SPECIAL_OIL, VfxPool3D.FX01_SPECIAL_BLAST]:
		print("ASSET_BEGIN ", asset_id)
		var effect := VfxPool3D.create_unpooled(asset_id)
		add_child(effect)
		effect.activate(Vector3.ZERO, Color.WHITE, 1.0, {"duration": 0.2})
		await get_tree().process_frame
		await get_tree().process_frame
		effect.finish()
		await get_tree().process_frame
		print("ASSET_END ", asset_id)
	for definition: Dictionary in SpecialItemCatalog.definitions():
		print("MODEL_BEGIN ", definition.id)
		var model := ItemModelFactory3D.create_model(definition)
		add_child(model)
		await get_tree().process_frame
		model.queue_free()
		await get_tree().process_frame
		print("MODEL_END ", definition.id)
		var icon := preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn").instantiate() as ItemModelIcon3D
		add_child(icon)
		icon.configure(definition)
		await get_tree().process_frame
		await get_tree().process_frame
		icon.queue_free()
		await get_tree().process_frame
		print("ICON_END ", definition.id)
	print("SPECIAL_ITEM_ASSETS_OK")
	get_tree().quit()
