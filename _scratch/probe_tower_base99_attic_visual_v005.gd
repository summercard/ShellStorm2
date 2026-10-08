extends Node
const OUTPUT_DIR := "I:/工作项目/shellstrom2/ShellStorm2/outputs/base99_radio_v005"
func _ready() -> void:
 print("VISUAL_PROBE_START_V005")
 var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
 var tower := packed.instantiate() as TowerDescent3D; tower.test_mode=true; tower.run_seed_override=990199; add_child(tower)
 await _settle()
 var rooms := tower.get("_room_by_id") as Dictionary; var facility_room := rooms.get("facility") as DungeonRoom3D
 if facility_room==null:get_tree().quit(1);return
 tower.player.global_position=facility_room.to_global(Vector3(0.0,5.05,0.0));tower.call("_refresh_physical_location_authority",true);await _settle()
 var camera:=Camera3D.new();camera.name="ProbeNativeCameraV005";camera.fov=55.0;tower.add_child(camera);camera.current=true;await _settle()
 var radio:=tower.find_child("99F床边桌独立收音机",true,false) as Base99Radio3D
 if radio==null:get_tree().quit(1);return
 var target:=radio.global_position+Vector3(0.0,0.32,0.0);var native_offset:=tower.player.camera.global_basis.z.normalized()
 var old_path:="res://outputs/base99_radio_v005/before_v004_visual.glb";var document:=GLTFDocument.new();var gltf_state:=GLTFState.new()
 if FileAccess.file_exists(old_path) and document.append_from_file(old_path,gltf_state)==OK:
  var old_visual:=document.generate_scene(gltf_state);_bind_old_palette(old_visual);radio.add_child(old_visual);radio.get_node("Visual").hide();await _capture(camera,target,native_offset*3.0,"before_v004_closeup.png");await _capture(camera,target+Vector3(1.2,-0.35,2.0),native_offset*10.0,"before_v004_attic.png");old_visual.free();radio.get_node("Visual").show()
 for state in ["off","a","b"]:
  radio.set_radio_state(state);await _capture(camera,target,native_offset*3.0,"radio_%s_closeup.png"%state);await _capture(camera,target+Vector3(1.2,-0.35,2.0),native_offset*10.0,"attic_%s.png"%state);print("RADIO_VISUAL_STATE=%s snapshot=%s"%[state,radio.get_state_snapshot()])
 tower.free();await get_tree().process_frame;get_tree().quit(0)
func _bind_old_palette(root:Node)->void:
 if root is MeshInstance3D:
  var mesh:=root as MeshInstance3D
  for surface in mesh.mesh.get_surface_count():
   var material:=mesh.mesh.surface_get_material(surface) as BaseMaterial3D;material.albedo_texture=load("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png");material.emission_texture=material.albedo_texture;material.emission_operator=BaseMaterial3D.EMISSION_OP_MULTIPLY;material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST;material.texture_repeat=false
 for child in root.get_children():_bind_old_palette(child)
func _capture(camera:Camera3D,target:Vector3,offset:Vector3,filename:String)->void:
 camera.global_position=target+offset;camera.look_at(target,Vector3.UP);await _settle();var image:=get_viewport().get_texture().get_image();var error:=image.save_png(OUTPUT_DIR+"/"+filename);print("CAPTURE=%s err=%s size=%s"%[filename,error,image.get_size()])
func _settle()->void:
 for i in 8:await get_tree().process_frame;await get_tree().physics_frame
 await get_tree().create_timer(0.25).timeout
