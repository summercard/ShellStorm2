extends Node
const PATH := "res://assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn"
func _ready() -> void:
 var r := (load(PATH) as PackedScene).instantiate()
 add_child(r)
 await get_tree().process_frame
 print("ROOT ", r.name, " scale=", r.scale, " version=", r.get_meta("asset_version"), " faces=", r.get_meta("model_faces"), " tris=", r.get_meta("model_triangles"))
 for n in r.find_children("*", "MeshInstance3D", true, false):
  var m:=n as MeshInstance3D
  print("MESH ", m.get_path(), " aabb=", m.get_aabb(), " surfaces=", m.mesh.get_surface_count())
  for s in m.mesh.get_surface_count(): print("SURF ", s, " idx=", m.mesh.surface_get_array_index_len(s), " mat=", m.get_active_material(s).resource_name)
 print("STATUS ", r.status_light, " aabb=", (r.status_light as MeshInstance3D).get_aabb() if r.status_light is MeshInstance3D else "notmesh")
 get_tree().quit(0)
