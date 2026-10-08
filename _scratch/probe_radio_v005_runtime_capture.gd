extends Node
const OUTPUT_DIR := "I:/工作项目/shellstrom2/ShellStorm2/outputs/base99_radio_v005"
const OLD_GLB := "res://outputs/base99_radio_v005/before_v004_visual.glb"
const CAMERA_STATE_PATH := OUTPUT_DIR + "/runtime_camera_state.json"
var tower: TowerDescent3D
var radio: Base99Radio3D
var player_camera: Camera3D
var probe_camera: Camera3D
var camera_state: Dictionary = {}

func _ready() -> void:
 print("RUNTIME_CAPTURE_V005_START")
 var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
 tower = packed.instantiate() as TowerDescent3D
 tower.test_mode = true
 tower.run_seed_override = 990199
 add_child(tower)
 await _settle()
 var rooms := tower.get("_room_by_id") as Dictionary
 var facility := rooms.get("facility") as DungeonRoom3D
 if facility == null:
  push_error("facility missing")
  get_tree().quit(1)
  return
 tower.player.global_position = facility.to_global(Vector3(0.0, 5.05, 0.0))
 tower.call("_refresh_physical_location_authority", true)
 await _settle()
 radio = tower.find_child("99F床边桌独立收音机", true, false) as Base99Radio3D
 if radio == null:
  push_error("radio missing")
  get_tree().quit(1)
  return
 tower.player.global_position = radio.global_position + Vector3(0.0, -0.90, 1.10)
 tower.player.velocity = Vector3.ZERO
 tower.call("_refresh_physical_location_authority", true)
 await _settle()
 player_camera = tower.player.camera
 player_camera.current = true
 await _settle()
 _record_camera("normal_player")
 var frozen_player_transform := player_camera.global_transform
 player_camera.set_process(false)
 player_camera.set_physics_process(false)
 player_camera.global_transform = frozen_player_transform
 var old_player_visual := _load_old_visual()
 if old_player_visual != null:
  radio.get_node("Visual").hide()
  radio.add_child(old_player_visual)
  await _settle()
  await _capture(player_camera, "runtime_before_v004_player.png")
  var old_lamp := old_player_visual.find_child("StatusLight", true, false) as MeshInstance3D
  if old_lamp != null:
   for surface in old_lamp.mesh.get_surface_count():
    var material := old_lamp.get_active_material(surface) as BaseMaterial3D
    material.uv1_offset += Vector3(0.1, 0.3, 0.0)
   await _capture(player_camera, "runtime_before_v004_green_player.png")
  old_player_visual.free()
  radio.get_node("Visual").show()
  await _settle()
 radio.set_radio_state("off")
 await _capture(player_camera, "runtime_after_off_player.png")
 radio.set_radio_state("a")
 await _settle()
 await _capture(player_camera, "runtime_after_a_player.png")
 radio.set_radio_state("b")
 await _settle()
 await _capture(player_camera, "runtime_after_b_player.png")
 radio.set_radio_state("off")
 probe_camera = Camera3D.new()
 probe_camera.name = "RadioV005CloseupCamera"
 probe_camera.fov = 55.0
 tower.add_child(probe_camera)
 probe_camera.current = true
 var target := radio.global_position + Vector3(0.0, 0.32, 0.0)
 var native_offset := player_camera.global_basis.z.normalized()
 await _capture_at(probe_camera, target, native_offset * 3.0, "runtime_after_off_closeup.png")
 radio.set_radio_state("a")
 await _settle()
 await _capture_at(probe_camera, target, native_offset * 3.0, "runtime_after_a_closeup.png")
 var old_visual := _load_old_visual()
 if old_visual != null:
  radio.get_node("Visual").hide()
  radio.add_child(old_visual)
  await _settle()
  await _capture_at(probe_camera, target, native_offset * 3.0, "runtime_before_v004_closeup.png")
  old_visual.free()
  radio.get_node("Visual").show()
 probe_camera.fov = player_camera.fov
 var attic_target := target + Vector3(1.2, -0.35, 2.0)
 var old_attic_visual := _load_old_visual()
 if old_attic_visual != null:
  radio.get_node("Visual").hide()
  radio.add_child(old_attic_visual)
  await _capture_at(probe_camera, attic_target, native_offset * 10.0, "runtime_before_v004_attic_off.png")
  var old_attic_lamp := old_attic_visual.find_child("StatusLight", true, false) as MeshInstance3D
  for surface in old_attic_lamp.mesh.get_surface_count():
   (old_attic_lamp.get_active_material(surface) as BaseMaterial3D).uv1_offset += Vector3(0.1, 0.3, 0.0)
  await _capture_at(probe_camera, attic_target, native_offset * 10.0, "runtime_before_v004_attic_green.png")
  old_attic_visual.free()
  radio.get_node("Visual").show()
 for state_name in ["off", "a", "b"]:
  radio.set_radio_state(state_name)
  await _capture_at(probe_camera, attic_target, native_offset * 10.0, "attic_%s.png" % state_name)
 print("RUNTIME_CAPTURE_V005_OK")
 tower.free()
 await get_tree().process_frame
 get_tree().quit(0)

func _load_old_visual() -> Node3D:
 var document := GLTFDocument.new()
 var state := GLTFState.new()
 if document.append_from_file(OLD_GLB, state) != OK:
  return null
 var root := document.generate_scene(state)
 _bind_old_palette(root)
 return root as Node3D

func _bind_old_palette(root: Node) -> void:
 if root is MeshInstance3D:
  var mesh := root as MeshInstance3D
  if mesh.mesh != null:
   for surface in mesh.mesh.get_surface_count():
    var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
    if material == null:
     continue
    material.albedo_texture = load("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
    material.emission_texture = material.albedo_texture
    material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    material.texture_repeat = false
    if str(mesh.name) == "StatusLight":
     var arrays := mesh.mesh.surface_get_arrays(surface)
     var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
     var center := Vector2.ZERO
     for uv in uvs:
      center += uv
     center /= float(uvs.size())
     var cell_center := (center * 10.0).floor() / 10.0 + Vector2(0.05, 0.05)
     material.uv1_offset = Vector3(0.45 - cell_center.x, 0.15 - cell_center.y, 0.0)
     material.albedo_color = Color.WHITE
     material.emission_enabled = true
     material.emission = Color.WHITE
     material.emission_energy_multiplier = 1.5
 for child in root.get_children():
  _bind_old_palette(child)

func _record_camera(label: String) -> void:
 camera_state[label] = {
  "position": [player_camera.global_position.x, player_camera.global_position.y, player_camera.global_position.z],
  "rotation": [player_camera.global_rotation.x, player_camera.global_rotation.y, player_camera.global_rotation.z],
  "fov": player_camera.fov,
  "player_position": [tower.player.global_position.x, tower.player.global_position.y, tower.player.global_position.z],
  "radio_position": [radio.global_position.x, radio.global_position.y, radio.global_position.z]
 }
 FileAccess.open(CAMERA_STATE_PATH, FileAccess.WRITE).store_string(JSON.stringify(camera_state, "  "))

func _capture(camera: Camera3D, filename: String) -> void:
 await _settle()
 var image := get_viewport().get_texture().get_image()
 if image == null:
  push_error("null viewport image: " + filename)
  return
 var err := image.save_png(OUTPUT_DIR + "/" + filename)
 var light := radio.status_light as MeshInstance3D
 if not radio.get_node("Visual").visible:
  for node in radio.get_children():
   if node != radio.get_node("Visual"):
    var candidate := node.find_child("StatusLight", true, false) as MeshInstance3D
    if candidate != null:
     light = candidate
 var triangles: Array = []
 if light != null:
  for surface in light.mesh.get_surface_count():
   var arrays := light.mesh.surface_get_arrays(surface)
   var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
   var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
   for index in range(0, indices.size(), 3):
    var triangle: Array = []
    for corner in 3:
     var screen := camera.unproject_position(light.global_transform * vertices[indices[index + corner]])
     triangle.append([screen.x, screen.y])
    triangles.append(triangle)
 camera_state[filename] = {
  "camera_position": [camera.global_position.x, camera.global_position.y, camera.global_position.z],
  "camera_rotation": [camera.global_rotation.x, camera.global_rotation.y, camera.global_rotation.z],
  "fov": camera.fov,
  "light_path": str(light.get_path()) if light != null else "",
  "screen_triangles": triangles
 }
 FileAccess.open(CAMERA_STATE_PATH, FileAccess.WRITE).store_string(JSON.stringify(camera_state, "  "))
 print("CAPTURE %s err=%s size=%s" % [filename, err, image.get_size()])

func _capture_at(camera: Camera3D, target: Vector3, offset: Vector3, filename: String) -> void:
 camera.global_position = target + offset
 camera.look_at(target, Vector3.UP)
 await _capture(camera, filename)

func _settle() -> void:
 for i in 8:
  await get_tree().process_frame
  await get_tree().physics_frame
 await get_tree().create_timer(0.25).timeout
