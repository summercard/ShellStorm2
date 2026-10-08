extends Node
const DIR := "res://assets/art/vfx/environment_3d/radio_music_notes"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var root := Node3D.new()
	root.name = "VfxRadioMusicNotes3D"
	root.set_script(load("res://src/vfx/VfxRadioMusicNotes3D.gd"))
	root.set("lifetime", 0.0)
	root.visible = false
	root.set_meta("asset_id", "VFX-RADIO-MUSIC-NOTES-3D")
	root.set_meta("asset_version", "v001")
	root.set_meta("lifecycle", "radio_owned_continuous_attachment_no_pool")
	root.set_meta("visual_budget", "5 frozen QuadMesh slots / 10 triangles; 2.5 births/s; 1.8s; rise 1.1m")
	var textures: Array[Texture2D] = []
	for kind in 3:
		var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		for y in 256:
			for x in 256:
				var p := Vector2(float(x) / 256.0, float(y) / 256.0)
				if _inside_note(p, kind):
					image.set_pixel(x, y, Color.WHITE)
		image.generate_mipmaps()
		var texture := ImageTexture.create_from_image(image)
		var path := DIR + "/radio_note_%s.tres" % ["quarter", "eighth", "double_eighth"][kind]
		assert(ResourceSaver.save(texture, path) == OK)
		textures.append(load(path))
	for index in 5:
		var note := MeshInstance3D.new()
		note.name = "Note%d" % index
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.46, 0.52)
		note.mesh = mesh
		note.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		note.visible = false
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = textures[index % 3]
		mat.albedo_color = Color(0.38, 0.76, 0.64, 0) if index % 2 == 0 else Color(0.86, 0.63, 0.29, 0)
		mat.resource_local_to_scene = true
		note.material_override = mat
		root.add_child(note)
		note.owner = root
	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(ResourceSaver.save(packed, DIR + "/vfx_radio_music_notes_root_top3d.tscn") == OK)
	root.free()
	print("RADIO_NOTES_RESOURCE_BUILD_OK: Godot ImageTexture + QuadMesh; no font dependency")
	get_tree().quit()

func _inside_note(p: Vector2, kind: int) -> bool:
	if kind == 2:
		return _head(p, Vector2(0.27, 0.75)) or _head(p, Vector2(0.66, 0.69)) or _rect(p, 0.34, 0.20, 0.40, 0.74) or _rect(p, 0.73, 0.13, 0.79, 0.68) or Geometry2D.is_point_in_polygon(p, PackedVector2Array([Vector2(0.34, 0.20), Vector2(0.79, 0.13), Vector2(0.79, 0.25), Vector2(0.34, 0.32)]))
	var body := _head(p, Vector2(0.38, 0.75)) or _rect(p, 0.45, 0.14, 0.51, 0.75)
	if kind == 1:
		body = body or Geometry2D.is_point_in_polygon(p, PackedVector2Array([Vector2(0.49, 0.14), Vector2(0.62, 0.23), Vector2(0.73, 0.36), Vector2(0.73, 0.48), Vector2(0.65, 0.56), Vector2(0.67, 0.42), Vector2(0.60, 0.34), Vector2(0.49, 0.30)]))
	return body

func _head(p: Vector2, center: Vector2) -> bool:
	var q := p - center
	return pow((q.x + q.y * 0.35) / 0.115, 2) + pow(q.y / 0.078, 2) <= 1.0

func _rect(p: Vector2, x0: float, y0: float, x1: float, y1: float) -> bool:
	return p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1
