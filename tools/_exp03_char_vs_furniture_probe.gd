extends Node
## 角色 vs 家具 体型对比：判断「家具到底该多大」。
##
## 业主问「对比一下我的角色看一下目前的数据」。这个问题必须用**角色**当标尺，
## 不能凭米数感觉 —— 1.5m 的角色和 2.45m 的扶手椅摆在一起，一眼就知道不合理。
##
## 量三组数：
##   ① 角色：碰撞胶囊 + 模型实际 AABB
##   ② 家具**原始**尺寸（美术素材真实尺寸）
##   ③ 家具**当前**尺寸（占地 ×3 + 高度封顶 2.45）
##
## 并算出每件相对角色的**身高比**与**占地比**。经验判据（俯视类游戏）：
##   椅子/边桌  身高 0.4~0.7 角色高
##   桌/柜台    0.5~0.9
##   沙发        0.6~0.8
##   书架/衣柜   1.2~1.8
## 低于 0.35 就是「看不清」，高于 2.0 就是「道具比人还高，荒谬」。
##
## 只读。

const FURNISH := preload("res://src/world3d/ManorFurnishing.gd")
const PLAYER_SCENE := "res://scenes/Player3D.tscn"
const AVATAR := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v021/runtime/chr_bunny01_root_v021.tscn"

## 只看玩家真正会注意到的主件，避免刷屏。
const MAIN := [
	"armchair", "sofa", "bench", "console", "side_table", "coffee_table",
	"nightstand", "bed", "bookcase", "wardrobe", "vanity", "reception_desk",
	"plant_compact", "plant_large", "candelabra", "table_lamp", "luggage_cart",
	"rug_bedroom",
]


func _ready() -> void:
	var player_h := _measure_player()
	print("PLAYER 碰撞胶囊高=1.50m 半径=0.34m")
	print("PLAYER 模型实测高=%.3fm" % player_h)
	print("")
	print("%-16s %-16s %-16s %-14s %-14s %s"
		% ["家具", "原始(W,H,D)", "当前(W,H,D)", "高/角色", "占地/角色", "判定"])
	# 角色占地按胶囊直径算（0.68m）
	var player_w := 0.68
	for slug in MAIN:
		var base: Vector3 = FURNISH.SIZES.get(slug, Vector3.ZERO)
		if base == Vector3.ZERO:
			continue
		var s: Vector3 = FURNISH.scale_for(slug)
		var cur := Vector3(base.x * s.x, base.y * s.y, base.z * s.z)
		var hr := cur.y / player_h
		var wr := maxf(cur.x, cur.z) / player_w
		print("%-16s %-16s %-16s %-14s %-14s %s"
			% [slug,
				"(%.2f,%.2f,%.2f)" % [base.x, base.y, base.z],
				"(%.2f,%.2f,%.2f)" % [cur.x, cur.y, cur.z],
				"%.2fx" % hr,
				"%.2fx" % wr,
				_verdict(slug, hr)])
	get_tree().quit(0)


func _verdict(slug: String, hr: float) -> String:
	var lo := 0.35
	var hi := 2.0
	match slug:
		"bookcase", "wardrobe":
			# 目标就是「刚好高过角色一点点」= 1.02×。给 0.95~1.15 的窗口。
			lo = 0.95
			hi = 1.15
		"sofa", "bench":
			lo = 0.5
			hi = 0.9
		"bed":
			lo = 0.35
			hi = 0.8
		"reception_desk", "vanity", "console", "coffee_table":
			lo = 0.4
			hi = 0.95
		"rug_bedroom":
			return "贴地件，不看高度"
	if hr < lo:
		return "⚠ 偏矮（看不清）"
	if hr > hi:
		return "⚠ 偏高（比人还高）"
	return "✓ 合理"


func _measure_player() -> float:
	var packed := load(PLAYER_SCENE) as PackedScene
	var total_h := 1.5
	if packed == null:
		return total_h
	var root := packed.instantiate() as Node3D
	if root != null:
		add_child(root)
		root.force_update_transform()
		# 找胶囊碰撞（这是玩家真正的体积）
		for node in root.find_children("*", "CollisionShape3D", true, false):
			var cs := node as CollisionShape3D
			if cs.shape is CapsuleShape3D:
				print("PLAYER 胶囊: r=%.2f h=%.2f" % [
					(cs.shape as CapsuleShape3D).radius,
					(cs.shape as CapsuleShape3D).height])
		root.queue_free()
	# 模型实际高度
	var avatar := load(AVATAR) as PackedScene
	if avatar != null:
		var a := avatar.instantiate() as Node3D
		if a != null:
			add_child(a)
			a.force_update_transform()
			var box := AABB()
			var first := true
			for node in a.find_children("*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				if mi.mesh == null:
					continue
				mi.force_update_transform()
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				box = b if first else box.merge(b)
				first = false
			if not first:
				total_h = box.size.y
			a.queue_free()
	return total_h
