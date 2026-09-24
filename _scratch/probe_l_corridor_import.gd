extends SceneTree

const TARGETS := [
	"res://assets/art/environments/tower_zones/expedition/source/room_types/l_corridor/v001/L型走廊种类_数据连廊_45x35m_v001.blend",
	"res://assets/art/environments/tower_zones/expedition/source/room_types/l_corridor/v002/L型走廊种类_数据连廊_45x35m_v002.blend",
	"res://assets/art/environments/tower_zones/expedition/source/room_types/l_corridor/v003/L型走廊种类_数据连廊_45x40m_v003.blend",
]

const OLD_PATHS := [
	"res://assets/art/environments/tower_zones/battle/source/room_types/l_corridor/v003/l_corridor_room_type_v003.blend",
]


func _initialize() -> void:
	for t in TARGETS:
		var ps := ResourceLoader.load(t, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if ps == null:
			print("LOAD_FAIL\t", t)
			continue
		var st := ps.get_state()
		print("LOAD_OK\t", t.get_file(), "\tnodes=", st.get_node_count(), "\troot=", st.get_node_name(0))
	for t in OLD_PATHS:
		var ok := ResourceLoader.exists(t)
		print("OLD_PATH_EXISTS\t", ok, "\t", t)
	print("TOKEN_LCORRIDOR_LOAD_PROBE_DONE")
	quit()
