extends Node
## 家具「到底有多大」体检：把 prefab 实例化后量**真实世界尺寸**，与 metadata 声明对照。
##
## 业主报「组件也太小了，是导入的时候的问题吗」。必须先分清两种成因：
##   ① **导入缩放错**：GLB 带了 0.01 / 100 之类的外部缩放，实例出来比声明小/大几倍
##      ⇒ 修 prefab 或 GLB 根节点 scale；
##   ② **尺寸本身对，只是相对房间太小**：家具 1.3m 宽是真实家具尺寸，但房间 45×40m
##      ⇒ 改设计（放大 / 加密），不是修 bug。
##
## 判据：`实际 AABB` 对比 `metadata/bounds_size_m`。
##   比值 ≈ 1.0 ⇒ 导入没问题，是②；
##   比值 ≈ 0.01 / 100 ⇒ 是①，导入缩放错了。
##
## 只读。

const MANOR := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"

const SLUGS := [
	"armchair", "bench", "bookcase", "candelabra", "coffee_table", "console",
	"bed", "nightstand", "wardrobe", "sofa", "side_table", "table_lamp",
	"plant_compact", "plant_large", "rug_lounge", "rug_runner", "rug_bedroom",
	"reception_desk", "vanity", "bathtub", "toilet", "mirror", "painting",
	"wall_lamp", "luggage_cart", "office_chair", "entrance_mat", "flower_arrangement",
]


func _ready() -> void:
	print("SLUG                 声明尺寸(W,H,D)              实测 AABB 尺寸(W,H,D)         比值(x,y,z)  根scale")
	for slug in SLUGS:
		_measure(str(slug))
	get_tree().quit(0)


func _measure(slug: String) -> void:
	var path := "%s/manor_%s/env_manor_%s_root_top3d.tscn" % [MANOR, slug, slug]
	if not ResourceLoader.exists(path):
		print("%-20s 缺文件" % slug)
		return
	var root := (load(path) as PackedScene).instantiate() as Node3D
	add_child(root)
	# 强制刷新一次全局变换，否则刚 add_child 时 global_transform 可能还是单位阵
	root.force_update_transform()
	var declared := Vector3.ZERO
	var dv: Variant = root.get_meta("bounds_size_m", Vector3.ZERO)
	if dv is Vector3:
		declared = dv
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		mi.force_update_transform()
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		print("%-20s 没有网格" % slug)
		root.queue_free()
		return
	var actual := box.size
	var ratio := Vector3(
		actual.x / declared.x if declared.x != 0.0 else 0.0,
		actual.y / declared.y if declared.y != 0.0 else 0.0,
		actual.z / declared.z if declared.z != 0.0 else 0.0
	)
	# 收集 prefab 里所有非单位缩放，定位「是谁把尺寸改了」
	var scales: Array[String] = []
	for node in root.find_children("*", "Node3D", true, false):
		var n := node as Node3D
		if not n.scale.is_equal_approx(Vector3.ONE):
			scales.append("%s=%s" % [str(n.name), str(n.scale)])
	print("%-20s %-28s %-28s %-22s %s"
		% [slug,
			"(%.2f, %.2f, %.2f)" % [declared.x, declared.y, declared.z],
			"(%.2f, %.2f, %.2f)" % [actual.x, actual.y, actual.z],
			"(%.2f, %.2f, %.2f)" % [ratio.x, ratio.y, ratio.z],
			"" if scales.is_empty() else "缩放: " + ", ".join(scales)])
	root.queue_free()
