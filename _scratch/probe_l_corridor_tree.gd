extends SceneTree

const TARGET := "res://assets/art/environments/tower_zones/expedition/source/room_types/l_corridor/v003/L型走廊种类_数据连廊_45x40m_v003.blend"


func _initialize() -> void:
	var ps := ResourceLoader.load(TARGET, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		print("LOAD_FAIL")
		quit()
		return
	var st := ps.get_state()
	var n := st.get_node_count()
	print("node_count=", n)
	var seen := {}
	var top: Array[String] = []
	for i in range(n):
		var path := String(st.get_node_path(i))
		var depth := path.split("/").size()
		if depth <= 2:
			if not seen.has(path):
				seen[path] = true
				top.append(path)
	print("--- depth<=2 nodes (%d) ---" % top.size())
	for p in top:
		print("  ", p)
	print("TOKEN_LCORRIDOR_TREE_PROBE_DONE")
	quit()
