extends Node

## 远征03 怪物图鉴画像（2026-10-30）。
##
## 目的：给「远征03 怪物列表」出一份**逐只单张**的模型图 + 同一份数值清单，
## 供人工核对「这只怪长这样、数值是这个」。
##
##   godot --path <project> --scene res://tools/_egt_roster_portrait.tscn
##
## ⚠ 必须 `--scene` 而不是 `--script`：要实例化 `Enemy3D`，它依赖 autoload。
##
## ## 为什么固定正交尺寸、不按每只怪自适应
## 表里要能**横向比体型**。逐只 fit 到画面中心会让 10 血的 blobulin 和
## 1000 血的 gun_nut 一样大，那张表就变成"看不出谁大谁小"的假数据。
## 统一 `ORTHO_SIZE` + 固定机位 ⇒ 画面里的相对大小就是游戏里的相对大小。
##
## ## 为什么数值由 GDScript 导出、不让 Python 另抄一份
## hp / 体型 / 颜色 / 血条宽度的唯一真源是 `Enemy3D.PROFILES`、
## `Enemy3D.BODY_SCALE_BY_KIND`、`EnemyAvatar3D.COLORS`。Python 复制一份 =
## 第二个真源，改了一边就静默对不上。这里把**运行时真实值**原样写进 manifest。

const OUT_DIR := "res://outputs/expedition03_monster_roster"
const PORTRAIT_DIR := OUT_DIR + "/portraits"

## 画面尺寸。宽高比 1:1.1，给头顶留一点空。
const VIEW_W := 420
const VIEW_H := 460
## 正交可视高度（米）。取 3.0：能完整容下最高的 gunsinger（世界约 2.27m），
## 又让小怪不至于缩成一个点。**这一条决定了表里所有图的比例尺相同。**
const ORTHO_SIZE := 3.0
const CAM_Y := 1.15

## 远征03 实际会出现的怪（由 `spawn_roster` 的盒子反查，外加分裂子代 blobulin）。
## 顺序 = 表里的行序，按族排，族内按血量升序，方便横向对比。
const KINDS: Array[String] = [
	# 子弹族
	"egt_bullet_kin", "egt_bandana_kin", "egt_veteran_kin", "egt_cardinal", "egt_hollowpoint",
	# 霰弹枪族
	"egt_red_shotgun", "egt_veteran_shotgun", "egt_blue_shotgun",
	# 爆炸族
	"egt_pinhead", "egt_nitra", "egt_king_bullat",
	# 分裂族
	"egt_blobulin", "egt_blobuloid", "egt_blobulon", "egt_chancebulon",
	# 书怪族
	"egt_bookllet", "egt_blue_bookllet", "egt_green_bookllet",
	# 法术 / 辅助族
	"egt_gigi", "egt_gunjurer", "egt_gunsinger",
	# 一次性冲撞族
	"egt_bullat", "egt_shotgat", "egt_grenat", "egt_spirat",
	# 逃逸 / 触发族
	"egt_keybullet_kin", "egt_chance_kin", "egt_gun_fairy", "egt_confirmed", "egt_gripmaster",
	# 重型
	"egt_gun_nut", "egt_chain_gunner",
]

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _index := 0
var _frames := 0
var _current: Enemy3D
var _pending_shot := false
const SETTLE_FRAMES := 10

var _manifest: Array = []
var _injector: MonsterInjector


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PORTRAIT_DIR))

	# 关卡级绝对数值（`monster_rules.stats.per_kind`）只在这条链上下发，
	# 不设它 ⇒ `override_*` 不入场，读到的就是 PROFILES 基线（差 3 倍）。
	_injector = MonsterInjector.new()
	_injector.set_level_rules(_load_monster_rules())

	_vp = SubViewport.new()
	_vp.size = Vector2i(VIEW_W, VIEW_H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	add_child(_vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	# 与出图惯例一致的深蓝灰，浅色 UI 里贴上去不会出现"白底黑边"
	e.background_color = Color(0.055, 0.065, 0.085)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.60, 0.64, 0.74)
	e.ambient_light_energy = 1.1
	env.environment = e
	_vp.add_child(env)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	key.rotation_degrees = Vector3(-36, -30, 0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(-14, 152, 0)
	_vp.add_child(fill)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = ORTHO_SIZE
	_cam.position = Vector3(0.0, CAM_Y, 12.0)
	_cam.rotation_degrees = Vector3.ZERO
	_vp.add_child(_cam)
	_cam.current = true

	_build(0)


func _build(index: int) -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	_world = Node3D.new()
	_vp.add_child(_world)

	# 地面：给一个可见落脚点，否则读不出体型相对什么
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.11, 0.13, 0.17)
	gm.roughness = 1.0
	ground.material_override = gm
	_world.add_child(ground)

	var kind := KINDS[index]
	_current = Enemy3D.new()
	var avatar := EnemyAvatar3D.new()
	avatar.name = "Avatar"
	_current.add_child(avatar)
	# `Enemy3D` 的 `@onready var collision_shape := $CollisionShape3D` 要求这个子节点存在，
	# 而它的场景包装只在正式关卡里提供。这里手工补上，否则每拍一只就刷一条
	# `Node not found: "CollisionShape3D"` —— 出图不受影响，但日志会被噪声淹没。
	var probe_shape := CollisionShape3D.new()
	probe_shape.name = "CollisionShape3D"
	_current.add_child(probe_shape)
	_world.add_child(_current)
	# 数值走**游戏里真实那条路**：MonsterInjector 生成 → configure_from_enemy_data。
	# 不能只调 `apply_profile()` —— 那拿到的是 PROFILES 基线（bullet_kin 会读成
	# 150×NORMAL_HP_MULTIPLIER=450），而实战数值是关卡 `monster_rules.stats.per_kind`
	# 的 `override_max_hp`（150）。两条路差 3 倍，表里就会写成假数。
	var data := _injector.generate_box_enemy(kind, 1, 1)
	if data.is_empty():
		push_error("%s 无法生成，跳过" % kind)
		get_tree().quit(1)
		return
	_current.configure_from_enemy_data(data)
	_current.position = Vector3.ZERO
	# 转 180+22°：模型契约是**朝 −Z**（`EnemyAvatar3D` 表头写死），而相机在 +Z 看向 −Z
	# ⇒ 不转就是拿后脑勺对着镜头（2026-10-30 首轮出图整整一排背影才发现）。
	# 再叠 22° 侧转，露出钳子 / 轨道球 / 剑这些附肢。
	_current.rotation_degrees = Vector3(0, 202, 0)
	_current.set_physics_process(false)
	_current.set_process(false)
	var bar := _current.get_node_or_null("OverheadHealthBar") as Node3D
	if bar != null:
		bar.visible = false
	_pending_shot = true


func _process(_delta: float) -> void:
	if _index >= KINDS.size() or not _pending_shot:
		return
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	_frames = 0
	_pending_shot = false

	var kind := KINDS[_index]
	var img := _vp.get_texture().get_image()
	if img == null:
		push_error("viewport texture 为空：%s" % kind)
		get_tree().quit(1)
		return
	var path := ProjectSettings.globalize_path("%s/%s.png" % [PORTRAIT_DIR, kind])
	var err := img.save_png(path)
	if err != OK:
		push_error("保存失败 err=%d path=%s" % [err, path])
		get_tree().quit(1)
		return
	_manifest.append(_entry_for(kind, path))
	print("EGT_PORTRAIT %s" % path)

	_index += 1
	if _index >= KINDS.size():
		_finish()
		return
	_build(_index)


## 一只怪的**运行时真实数值**。取值全部走 `Enemy3D` 的实例字段（不是再算一遍公式），
## 所以「表里写的就是游戏里跑的」。
func _entry_for(kind: String, png_path: String) -> Dictionary:
	var profile: Dictionary = Enemy3D.PROFILES[kind]
	var asset_kind := EnemyAvatar3D.resolve_asset_kind(kind)
	var uses_formal := EnemyAvatar3D.FORMAL_NORMAL_SCENES.has(asset_kind)
	var tint: Color = EnemyAvatar3D.FORMAL_MODEL_TINT.get(kind, Color.WHITE)
	var shell: Color = EnemyAvatar3D.COLORS.get(
		kind, EnemyAvatar3D.COLORS.get(asset_kind, Color.WHITE)
	)
	var body_scale := float(Enemy3D.BODY_SCALE_BY_KIND.get(kind, 1.0))
	var world_scale := float(Enemy3D.DEFAULT_BASE_SIZE_MULTIPLIER) * body_scale
	var world_height := float(
		EnemyAvatar3D.get_footprint_profile(kind).get("height", 1.2)
	) * world_scale

	var volley: Dictionary = profile.get("volley", {})
	var volley_alt: Dictionary = profile.get("volley_alt", {})
	var out := {
		"kind": kind,
		"png": png_path,
		"hp": int(_current.max_hp),
		"damage": int(_current.contact_damage),
		"move_speed": snappedf(float(_current.move_speed), 0.01),
		"attack_range": float(_current.attack_range),
		"cooldown": float(_current.attack_cooldown),
		"attack_style": str(profile.get("attack_style", "")),
		"projectile_speed": float(profile.get("projectile_speed", 0.0)),
		"projectile_range": float(profile.get("projectile_range", 0.0)),
		# 弹色走实例方法：它会先读 `bullet_color` 键、再按族回退，
		# 与玩家真正看到的弹幕同源（表里"弹色"这一列不能自己再猜一遍）。
		"bullet_color": _hex(_current._egt_projectile_color()),
		"body_scale": body_scale,
		"world_height": snappedf(world_height, 0.01),
		"bar_width": (Enemy3D.HEALTH_BAR_SIZE_BY_KIND.get(kind, Vector2.ZERO) as Vector2).x,
		"asset_kind": asset_kind,
		"uses_formal": uses_formal,
		"body_color": _hex(tint if uses_formal else shell),
		# 「body_color 这一列是不是真色」。
		# 借正式 GLB 且**没登记染色**的怪（分裂族三只）保持原贴图，
		# 此时 `body_color` 只是表里取不到值的兜底白 —— 图注不能把它写成体型色，
		# 否则表上会出现"布洛布是白色的"，而玩家看到的是一身烂衣服的僵尸。
		"tinted": EnemyAvatar3D.FORMAL_MODEL_TINT.has(kind) if uses_formal else true,
		"volley": volley,
		"volley_alt": volley_alt,
		"alt_every": int(profile.get("alt_every", 0)),
		"hover": bool(profile.get("hover", false)),
		"immobile": bool(profile.get("immobile", false)),
		"death_split": profile.get("death_split", {}),
		"death_burst": profile.get("death_burst", {}),
		"blink": profile.get("blink", {}),
		"flee": profile.get("flee", {}),
		"suicide_rush": profile.get("suicide_rush", {}),
		"support_buff": profile.get("support_buff", {}),
		"grab": profile.get("grab", {}),
		"orbit": profile.get("orbit", {}),
		"egg": profile.get("egg", {}),
		"disguise": profile.get("disguise", {}),
		"jammed": profile.get("jammed", {}),
		"chance_moves": profile.get("chance_moves", {}),
		"leap": profile.get("leap", {}),
		"wander": profile.get("wander", {}),
	}
	return out


func _load_monster_rules() -> Dictionary:
	var path := "res://data/level_plans/expedition_03/level_plan.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("读不到远征03 level_plan: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("monster_rules", {}) as Dictionary


static func _hex(c: Color) -> String:
	if c.r > 1.0 or c.g > 1.0 or c.b > 1.0:
		c = Color(c.r / 255.0, c.g / 255.0, c.b / 255.0, 1.0)
	return "#%02X%02X%02X" % [
		int(round(clampf(c.r, 0.0, 1.0) * 255.0)),
		int(round(clampf(c.g, 0.0, 1.0) * 255.0)),
		int(round(clampf(c.b, 0.0, 1.0) * 255.0)),
	]


func _finish() -> void:
	var path := ProjectSettings.globalize_path("%s/manifest.json" % OUT_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("写 manifest 失败")
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify({"count": _manifest.size(), "monsters": _manifest}, "  "))
	f.close()
	print("EGT_PORTRAIT_DONE count=%d" % _manifest.size())
	print("EGT_PORTRAIT_MANIFEST %s" % path)
	get_tree().quit(0)
