class_name EnemyAvatar3D
extends Node3D
## 七类敌人的共用模块化外壳。核心、护甲、附肢和状态特效均为独立组件，
## 运行时只改变组合与材质，避免为每个关卡复制模型。

const COLORS := {
	"fat_zombie03": Color(0.38, 0.43, 0.26),
	"melee_chaser": Color(0.58, 0.19, 0.12),
	"ranged_caster": Color(0.18, 0.44, 0.50),
	"summoner": Color(0.42, 0.22, 0.52),
	"shielded": Color(0.28, 0.34, 0.30),
	"exploder": Color(0.72, 0.30, 0.08),
	"ambusher": Color(0.14, 0.20, 0.18),
	"boss": Color(0.37, 0.12, 0.09),
	# —— 远征03 复刻怪：**这一表只管"与借用基类不同色"的那几只**（2026-10-29）——
	#
	# 规则：颜色 = 它能伤害你的方式。远程族 5 只的身体色**与自己的弹幕色完全一致**
	# （对比 `Enemy3D._egt_projectile_color()`），玩家看怪的颜色就知道要躲什么弹。
	#
	# ⚠ 未在此登记的复刻怪**刻意**沿用基类色，靠 `_rebuild()` 的 `COLORS.get(enemy_kind, …)` 回退：
	#   egt_blobulon / egt_blobuloid / egt_blobulin → melee_chaser 暗红
	#     （分裂体就该长得跟母体一样，变色反而破坏"这是同一只怪炸开的"这层信息）
	#   egt_pinhead → exploder 橙
	#     （它就是标准爆炸怪，橙是这一族的基准色；变异的 nitra/bullat 才换色）
	"egt_bullet_kin": Color(0.20, 0.82, 0.92),
	"egt_bandana_kin": Color(0.36, 0.62, 0.98),
	"egt_veteran_kin": Color(0.98, 0.60, 0.28),
	"egt_red_shotgun": Color(0.92, 0.26, 0.26),
	"egt_blue_shotgun": Color(0.32, 0.52, 0.96),
	"egt_nitra": Color(0.58, 0.68, 0.18),
	"egt_bullat": Color(0.94, 0.80, 0.20),
	# 保险销头**显式写成 exploder 的橙**，而不是靠回退。
	# 理由：回退在数值上等价，但注册一致性探针无法区分「刻意同色」和「忘了登记」——
	# 一旦有人后来改了 exploder 的橙色，pinhead 会静默跟着变，而它是这一族的**基准色**。
	"egt_pinhead": Color(0.72, 0.30, 0.08),
	"egt_gunsinger": Color(0.64, 0.30, 0.82),
	# —— 第二批 21 只（2026-10-29）：全族覆盖，颜色仍守「身体色 = 弹色 = 伤你的方式」——
	# 本表只对**程序化外壳**生效（exploder / summoner 借来的那批）。
	# 借 melee_chaser / ranged_caster / fat_zombie03 的走 FORMAL_MODEL_TINT，原因见 §T3.4。
	# —— 子弹族：青 → 蓝 → 橙 → 玫红 → 紫 ——
	"egt_cardinal": Color(0.86, 0.30, 0.42),
	"egt_hollowpoint": Color(0.66, 0.42, 0.92),
	# —— 霰弹枪族：红 → 金黄 → 深蓝（老兵的金黄＝"必喷"警告色）——
	"egt_veteran_shotgun": Color(0.94, 0.72, 0.10),
	# —— 爆炸族：橙 → 黄绿 → 亮黄 → 红橙 → 紫金（王）——
	"egt_king_bullat": Color(0.62, 0.42, 0.78),
	"egt_grenat": Color(0.90, 0.34, 0.12),
	# —— 冲撞族：青绿 / 青（它们不炸，所以不占用暖色）——
	"egt_shotgat": Color(0.42, 0.78, 0.62),
	"egt_spirat": Color(0.36, 0.86, 0.86),
	# —— 书怪族：米白 / 蓝 / 绿，同血只换色（与弹形一一对应）——
	"egt_bookllet": Color(0.90, 0.88, 0.80),
	"egt_blue_bookllet": Color(0.44, 0.66, 0.98),
	"egt_green_bookllet": Color(0.52, 0.88, 0.48),
	# —— 法术族：淡紫 / 米黄 ——
	"egt_gunjurer": Color(0.72, 0.52, 1.0),
	"egt_gigi": Color(0.96, 0.82, 0.42),
	# —— 触发 / 逃逸族：金（钥匙）→ 青（运气）→ 暗紫 → 棕金（拟态）→ 淡黄 → 蓝紫 ——
	"egt_keybullet_kin": Color(0.98, 0.84, 0.24),
	"egt_chance_kin": Color(0.40, 0.86, 0.90),
	"egt_confirmed": Color(0.56, 0.36, 0.72),
	"egt_mimic": Color(0.70, 0.52, 0.26),
	"egt_gun_fairy": Color(0.98, 0.90, 0.60),
	"egt_gripmaster": Color(0.54, 0.48, 0.92),
	# —— 重型族：灰蓝 / 棕 ——
	"egt_chain_gunner": Color(0.62, 0.68, 0.80),
	"egt_gun_nut": Color(0.66, 0.50, 0.28),
}

## 远征03 复刻怪的**占位资产别名**（2026-10-29）。
##
## 业主指令：先用现有怪物资产把 EGT 第一层的怪做出来，美术后期再换。
## 这张表就是「套入」的**唯一落点** —— 新 kind 在表现层解析成一只已有怪的资产，
## 同时 `enemy_kind` **保留原名**（名字、血条、掉落、诊断仍按新 kind 走）。
##
## ⚠ 不加这张表的后果（本文件里已写过的同类坑）：`configure()` 开头是
## `var known := COLORS.has(kind) ...`，未知 kind 会被**静默降级成 `melee_chaser`** ——
## 表现退化成一只默认怪，日志一个字都不说。新怪种必须在这里登记，否则等于没做。
##
## 键 = 新怪种 ID，值 = 借用哪只怪的表现资产（必须是 `COLORS` 里已有的基类）。
const PROXY_ASSET_KIND := {
	# —— 远程五兄弟：借保安僵尸（有枪、有射击动作）——
	"egt_bullet_kin": "ranged_caster",
	"egt_bandana_kin": "ranged_caster",
	"egt_veteran_kin": "ranged_caster",
	"egt_red_shotgun": "ranged_caster",
	"egt_blue_shotgun": "ranged_caster",
	# —— 布洛布三阶：借小僵尸（近战扑击动作正好对应接触伤害）——
	"egt_blobulon": "melee_chaser",
	"egt_blobuloid": "melee_chaser",
	"egt_blobulin": "melee_chaser",
	# —— 爆炸/冲撞系：借炸弹果（自爆动作）——
	"egt_pinhead": "exploder",
	"egt_nitra": "exploder",
	"egt_bullat": "exploder",
	# —— 辅助系：借蜂巢怪（原地施法姿态）——
	"egt_gunsinger": "summoner",
	# —— 第二批 21 只（2026-10-29）——
	# 选资产的唯一标准是**姿态对得上**：有枪的借保安僵尸、贴身的借小僵尸、
	# 会炸的借炸弹果、悬浮施法的借蜂巢怪、笨重的借胖子僵尸。
	# ⚠ 这张表是"这套占位会不会静默失效"的开关：漏登记 = 该 kind 在
	# `configure()` 里被判未知、静默降级成小僵尸，日志一个字都不说。
	"egt_cardinal": "ranged_caster",
	"egt_hollowpoint": "ranged_caster",
	"egt_veteran_shotgun": "ranged_caster",
	"egt_confirmed": "ranged_caster",
	"egt_gun_fairy": "ranged_caster",
	"egt_chancebulon": "melee_chaser",
	"egt_keybullet_kin": "melee_chaser",
	"egt_chance_kin": "melee_chaser",
	"egt_king_bullat": "exploder",
	"egt_shotgat": "exploder",
	"egt_grenat": "exploder",
	"egt_spirat": "exploder",
	"egt_bookllet": "summoner",
	"egt_blue_bookllet": "summoner",
	"egt_green_bookllet": "summoner",
	"egt_gunjurer": "summoner",
	"egt_gigi": "summoner",
	"egt_gripmaster": "summoner",
	"egt_mimic": "fat_zombie03",
	"egt_gun_nut": "fat_zombie03",
	"egt_chain_gunner": "fat_zombie03",
}


## 把怪种 ID 解析成**用于查表现资产**的基类。
## 未登记别名的 kind 原样返回 —— 这样旧怪种的行为逐字不变。
static func resolve_asset_kind(kind: String) -> String:
	return str(PROXY_ASSET_KIND.get(kind, kind))

# 与实际模块化模型的最大横向轮廓同源；Enemy3D 直接读取该表生成受击/物理体积。
#
# ⚠ 2026-10-15 业主：「胖子僵尸、小僵尸、警察僵尸的碰撞盒子，**高度不调整，
# **直径**缩小到现在的 **80%**」⇒ 只把这三只的 `radius` ×0.8，`height` **逐字不动**。
#   fat_zombie03  1.10 → 0.88   （1.10 × 0.8）
#   melee_chaser  1.02 → 0.816  （1.02 × 0.8）
#   ranged_caster 1.10 → 0.88   （1.10 × 0.8）
# ⚠️ **这是玩法口径，不是纯视觉**：`radius` 同时被三处消费 ——
#   ① `Enemy3D` 的碰撞柱（能不能被打到、能不能挤过去）；
#   ② `_navigation_agent.radius = radius × 0.72`（寻路能否穿过窄缝）；
#   ③ 状态快照的 `collision_profile`（供验收读取）。
#   `height` 不动 ⇒ 头顶血条高度、伤害飘字高度都不受影响。
# ⚠️ 副作用要知悉：这三只的碰撞柱**变细**了 —— 挤过窄缝更容易，但贴墙时模型会更容易穿进墙里
#   （该表原本刻意留了余量避免穿模）。胖子僵尸尤其明显：它的模型半宽（世界 ≈1.84m）
#   本来就比碰撞柱（现 0.62m）宽得多，缩到 0.8 后差距进一步拉大。
# 其余怪种（summoner / shielded / exploder / ambusher / boss）**逐字不动**。
const FOOTPRINT_PROFILES := {
	"fat_zombie03": {"radius": 0.88, "height": 3.142857},
	"melee_chaser": {"radius": 0.816, "height": 1.30},
	"ranged_caster": {"radius": 0.88, "height": 1.62},
	"summoner": {"radius": 1.22, "height": 1.82},
	"shielded": {"radius": 0.98, "height": 1.42},
	"exploder": {"radius": 0.88, "height": 1.28},
	"ambusher": {"radius": 1.22, "height": 0.86},
	"boss": {"radius": 1.92, "height": 2.30},
}

# 正式普通怪表现按逻辑 ID 路由；这里只替换视觉，不改变 Enemy3D 的 AI、碰撞、伤害与掉落。
# 碰撞 FOOTPRINT 仍由各 kind 的既有玩法口径提供，不随美术替换自动收紧。
const FORMAL_NORMAL_SCENES := {
	"fat_zombie03": "res://assets/art/enemies/normal_enemy_3d/fat_zombie03/runtime/enm_normal_fat_zombie03_root_top3d.tscn",
	"melee_chaser": "res://assets/art/enemies/normal_enemy_3d/melee_chaser/runtime/enm_melee_fungboar01_root_top3d.tscn",
	"ranged_caster": "res://assets/art/enemies/normal_enemy_3d/ranged_caster/runtime/enm_ranged_sporeshooter01_root_top3d.tscn",
}
const FORMAL_NORMAL_HEIGHTS := {"fat_zombie03": 3.142857, "melee_chaser": 1.857143, "ranged_caster": 1.857143}
const FORMAL_MELEE_KIND := "melee_chaser"
const FORMAL_MELEE_SCENE_PATH := FORMAL_NORMAL_SCENES[FORMAL_MELEE_KIND]
const FORMAL_MELEE_VISUAL_HEIGHT := FORMAL_NORMAL_HEIGHTS[FORMAL_MELEE_KIND]

## 正式 GLB 模型的**染色系数**（2026-10-29）。
##
## ## 为什么必须有这张表
## `COLORS` 只作用于**程序化外壳**。而 `melee_chaser` / `ranged_caster` / `fat_zombie03`
## 三个基类有正式 GLB（见 `FORMAL_NORMAL_SCENES`），加载时会把外壳、核心、附肢全部
## `hide()` —— 于是 `COLORS` 对它们**一行都不生效**。
##
## 远征03 的 5 只远程怪全部借用 `ranged_caster`，即**同一个 GLB 模型**。
## 不染色的后果：5 只长得一模一样，体型差 0.86~1.18 在实战距离下几乎看不出，
## 玩家无法分辨"三连发"和"预判弹"该用不同躲避方式 —— 这是可读性硬伤，不是审美问题。
##
## ## 为什么值是"偏色近白"而不是纯饱和色
## 实现是 `albedo_color *= tint`（见 `_apply_formal_tint()`）。纯饱和色会把贴图
## 压成一块平色，丢掉全部明暗细节和材质感。用接近白、只做**色相偏移**的系数，
## 既保留原模型细节，又能明显改变色相 —— 远看是"红的那只 / 蓝的那只"。
##
## ## 没登记的怪不染色
## 分裂族三只刻意不染（同一只怪的分裂体应同貌，靠体型区分）；
## 爆炸族与辅助族走程序化外壳，`COLORS` 已经生效，不需要这条通道。
const FORMAL_MODEL_TINT := {
	"egt_bullet_kin": Color(0.45, 1.00, 1.00),
	"egt_bandana_kin": Color(0.52, 0.74, 1.00),
	"egt_veteran_kin": Color(1.00, 0.72, 0.42),
	"egt_red_shotgun": Color(1.00, 0.42, 0.40),
	"egt_blue_shotgun": Color(0.40, 0.54, 1.00),
	# —— 第二批：借**正式 GLB** 的那 11 只，必须在这里给染色系数 ——
	# 借 ranged_caster 的 5 只 + 借 melee_chaser 的 3 只 + 借 fat_zombie03 的 3 只。
	# 一个都不能漏：漏了那只就是"和同族另一只长得一模一样"，而 COLORS 对它完全无效。
	"egt_cardinal": Color(1.00, 0.52, 0.62),
	"egt_hollowpoint": Color(0.84, 0.62, 1.00),
	"egt_veteran_shotgun": Color(1.00, 0.84, 0.42),
	"egt_confirmed": Color(0.80, 0.60, 0.94),
	"egt_gun_fairy": Color(1.00, 0.96, 0.72),
	"egt_chancebulon": Color(1.00, 0.88, 0.58),
	"egt_keybullet_kin": Color(1.00, 0.92, 0.46),
	"egt_chance_kin": Color(0.62, 0.96, 0.96),
	"egt_mimic": Color(1.00, 0.74, 0.40),
	"egt_gun_nut": Color(1.00, 0.84, 0.64),
	"egt_chain_gunner": Color(0.74, 0.84, 1.00),
}

var enemy_kind := "melee_chaser"
## 用于查表的**基类**：强化怪回退到原怪，普通怪等于自己。
##
## 本文件里所有「按种分叉」的判定（外壳尺寸、附肢、正式模型路由、埋伏姿态）
## 都必须读它而不是 `enemy_kind`。否则「小僵尸-强化怪」这种新 kind 会一路
## 掉到 `match` 的默认分支：既拿不到正式小僵尸模型，也生不出正确的外壳 ——
## 表现静默退化成一只默认怪，而日志里一个字都不会说。
var _base_kind := "melee_chaser"
var ai_state := "idle"
var _elapsed := 0.0
var _root: Node3D
var _core: MeshInstance3D
var _shell: MeshInstance3D
var _appendages: Node3D
var _tell_ring: MeshInstance3D
var _base_color := Color.WHITE
var _core_material: StandardMaterial3D
var _shell_material: StandardMaterial3D
var _ambush_revealed := true
var _boss_content_id := ""
var _formal_boss_root: Node3D
var _elite_content_id := ""
var _elite_presentation_asset_id := ""
var _formal_normal_root: Node3D
var _formal_normal_scene_path := ""
var _formal_elite_root: Node3D
## 普通与强化僵尸的双眼红光。
var _eye_glow: StrongVariantEyeGlow3D
## 发光眼所挂的骨骼绑点（`BoneAttachment3D`，挂在 `Head` 骨上）。
var _eye_socket: BoneAttachment3D
## 挂点已建、但偏移还没算（等下一帧）。见 `_setup_eye_socket` 的说明。
var _eye_pending := false
## 骨骼绑点在场景树里的固定名字。验收按名取节点，不靠遍历猜。
const EYE_SOCKET_NODE_NAME := "StrongEyeSocket3D"
## 眼球挂载的目标骨。三个模型都只有这一根头骨（无 eye 骨，见 MonsterVariants 注释）。
const EYE_BONE_NAME := "Head"


func configure(kind: String) -> void:
	# 别名先解析：`egt_*` 这类「借用别人资产的复刻怪」要在 `known` 判定之前落地，
	# 否则会被下面的 else 分支静默换成 melee_chaser（本表存在的理由见 PROXY_ASSET_KIND 注释）。
	var asset_kind := resolve_asset_kind(kind)
	var known := COLORS.has(asset_kind) or MonsterVariants.is_variant(asset_kind)
	enemy_kind = kind if known else "melee_chaser"
	var base_kind := MonsterVariants.base_of(asset_kind)
	_base_kind = base_kind if not base_kind.is_empty() else asset_kind
	if not COLORS.has(_base_kind):
		_base_kind = "melee_chaser"
	_rebuild()


func configure_boss_content(content_id: String) -> bool:
	_boss_content_id = content_id
	if enemy_kind != "boss" or content_id.is_empty() or _root == null:
		return false
	var profile := BossContentCatalog.get_by_content_id(content_id)
	var scene := load(str(profile.get("presentation_scene", ""))) as PackedScene
	if scene == null:
		return false
	if _formal_boss_root != null and is_instance_valid(_formal_boss_root):
		_root.remove_child(_formal_boss_root)
		_formal_boss_root.queue_free()
	_formal_boss_root = scene.instantiate() as Node3D
	_formal_boss_root.name = "FormalBoss_%s" % content_id
	_root.add_child(_formal_boss_root)
	_shell.visible = false
	_core.visible = false
	_appendages.visible = false
	return true


func configure_elite_content(content_id: String, asset_id: String, scene_path: String) -> bool:
	disable_formal_normal()
	_elite_content_id = content_id
	_elite_presentation_asset_id = asset_id
	if content_id.is_empty() or asset_id.is_empty() or scene_path.is_empty() or _root == null:
		return false
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return false
	if _formal_elite_root != null and is_instance_valid(_formal_elite_root):
		_formal_elite_root.queue_free()
	_formal_elite_root = scene.instantiate() as Node3D
	if _formal_elite_root == null:
		return false
	_formal_elite_root.name = "FormalElite_%s" % content_id
	_root.add_child(_formal_elite_root)
	_shell.visible = false
	_core.visible = false
	_appendages.visible = false
	return true


func set_ai_state(state_id: String) -> void:
	ai_state = state_id


func set_ambush_revealed(revealed: bool) -> void:
	_ambush_revealed = revealed


static func get_footprint_profile(kind: String) -> Dictionary:
	# 强化怪回退基类：变种的碰撞体形状照抄原怪，**不在这里放大**。
	# 世界尺寸由 `Enemy3D` 根节点的 `scale`（含变种体型倍率）统一放大，
	# 碰撞柱是它的子节点 ⇒ 自动跟随。在表里再乘一次 1.5 会放大两遍。
	#
	# 远征03 的复刻怪先过一层别名（`egt_*` → 借用的那只怪）：它们借的是**表现资产**，
	# 碰撞柱也就该跟被借的那只一致 —— 否则「模型是保安僵尸、碰撞柱是默认小僵尸」。
	var proxied := resolve_asset_kind(kind)
	var base_kind := MonsterVariants.base_of(proxied)
	var lookup := base_kind if not base_kind.is_empty() else proxied
	return (FOOTPRINT_PROFILES.get(lookup, FOOTPRINT_PROFILES["melee_chaser"]) as Dictionary).duplicate()


func flash_hit() -> void:
	if has_animated_boss():_formal_boss_root.flash_hit()
	if has_formal_normal():
		_formal_normal_root.flash_hit()
	if _shell_material != null:
		_shell_material.albedo_color = Color(1.0, 0.78, 0.60)


func get_formal_death_duration() -> float:
	if has_animated_boss():return 2.0
	if has_formal_normal():
		return float(_formal_normal_root.get_presentation_snapshot().get("death_duration", 2.4))
	return 0.34


func get_component_snapshot() -> Dictionary:
	return {
		"enemy_kind": enemy_kind,
		# 强化怪查表走基类；把两件事分开暴露，验收才能断言
		# 「kind 是变种、但外观/碰撞确实取自原怪」。
		"base_kind": _base_kind,
		"ai_state": ai_state,
		"components": ["skeletal_model", "state_vfx"] if has_formal_normal() else ["core", "shell", "appendages", "state_vfx"],
		"component_count": 2 if has_formal_normal() else 4,
		"formal_normal_asset": has_formal_normal(),
		"presentation": _formal_normal_root.get_presentation_snapshot() if has_formal_normal() else {},
		"procedural_pose": not has_formal_normal() and not has_animated_boss(),
		"boss_presentation": _formal_boss_root.get_presentation_snapshot() if has_animated_boss() else {},
		"footprint": get_footprint_profile(enemy_kind),
		"ambush_revealed": _ambush_revealed,
		"boss_content_id": _boss_content_id,
		"formal_boss_asset": _formal_boss_root != null,
		"elite_content_id": _elite_content_id,
		"elite_presentation_asset_id": _elite_presentation_asset_id,
		"formal_elite_asset": _formal_elite_root != null,
		"eye_glow": _eye_glow.get_presentation_snapshot() if _eye_glow != null else {},
		"eye_socket_bone": _eye_socket.bone_name if _eye_socket != null else "",
		"is_3d": true,
	}


func _process(delta: float) -> void:
	_elapsed += delta
	# 强化怪的发光眼要等一帧：GLB 刚实例化时骨架位姿与挂点世界矩阵还没解析完。
	# 见 `_setup_eye_socket` 的说明（同帧就算会把眼睛送到脚底）。
	if _eye_pending:
		_finalize_eye_glow()
	if _root == null:
		return
	if has_formal_normal() or has_animated_boss():
		_root.position = Vector3.ZERO
		_root.scale = Vector3.ONE
		_tell_ring.visible = ai_state == "telegraph" and not has_animated_boss()
		return
	var bob := sin(_elapsed * 3.3 + float(get_instance_id() % 11)) * 0.07
	var hidden_offset := -0.58 if _base_kind == "ambusher" and not _ambush_revealed else 0.0
	_root.position.y = lerpf(_root.position.y, bob + hidden_offset, minf(1.0, delta * 12.0))
	var target_scale := Vector3(1.0, 0.24, 1.0) if _base_kind == "ambusher" and not _ambush_revealed else Vector3.ONE
	_root.scale = _root.scale.lerp(target_scale, minf(1.0, delta * 14.0))
	_appendages.rotation.y += delta * (1.5 if ai_state == "attack" else 0.18 if ai_state == "recovery" else 0.35)
	_tell_ring.visible = ai_state == "telegraph"
	if _tell_ring.visible:
		_tell_ring.scale = Vector3.ONE * (1.0 + sin(_elapsed * 8.0) * 0.14)
		_tell_ring.rotation.y += delta * 2.5
	var target_color := _base_color
	if ai_state == "dead":
		target_color = _base_color.darkened(0.72)
	elif ai_state == "stagger":
		target_color = Color(1.0, 0.55, 0.34)
	if _shell_material != null:
		_shell_material.albedo_color = _shell_material.albedo_color.lerp(target_color, minf(1.0, delta * 13.0))
	if _core_material != null:
		var pulse := 1.7 + sin(_elapsed * (7.0 if ai_state == "telegraph" else 2.4)) * 0.45
		_core_material.emission_energy_multiplier = pulse


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_root = Node3D.new()
	_formal_boss_root = null
	_formal_elite_root = null
	_formal_normal_root = null
	_formal_normal_scene_path = ""
	# 重建等于换一只怪：上一任的发光眼与绑点必须一起走，
	# 否则残留的 BoneAttachment3D 会挂在新骨架的名字上（骨名相同，静默错挂）。
	_eye_glow = null
	_eye_socket = null
	_eye_pending = false
	_elite_content_id = ""
	_elite_presentation_asset_id = ""
	_root.name = "VisualRoot"
	add_child(_root)
	# 颜色优先取**怪种本身**，没登记才回退基类。
	# 必须这样写：复刻怪的 `_base_kind` 是借用的资产（5 只远程全是 `ranged_caster`），
	# 若直接 `COLORS[_base_kind]`，它们会共用一个颜色，体型之外的区分全部失效。
	_base_color = COLORS.get(enemy_kind, COLORS[_base_kind])
	_shell_material = _material(_base_color, 0.42, 0.66)
	_core_material = _material(_base_color.lightened(0.42), 0.18, 0.32, true)
	_appendages = Node3D.new()
	_appendages.name = "Appendages"
	_root.add_child(_appendages)

	var body_size := Vector3(1.25, 1.15, 1.25)
	if _base_kind == "boss":
		body_size = Vector3(2.3, 2.1, 2.3)
	elif _base_kind in ["ranged_caster", "summoner"]:
		body_size = Vector3(1.05, 1.5, 1.05)
	elif _base_kind == "ambusher":
		body_size = Vector3(1.45, 0.72, 1.45)
	_shell = _add_capsule("Shell", Vector3(0, body_size.y * 0.54, 0), body_size, _shell_material, _root)
	_core = _add_sphere("Core", Vector3(0, body_size.y * 0.75, -body_size.z * 0.48), body_size.x * 0.20, _core_material, _root)

	match _base_kind:
		"melee_chaser":
			_add_claws(0.84, 0.50)
		"ranged_caster":
			_add_orbitals(3, 0.90)
		"summoner":
			_add_orbitals(4, 1.02)
			_add_cylinder("Crown", Vector3(0, 1.72, 0), 0.42, 0.12, _core_material, _appendages)
		"shielded":
			_add_box("FrontShield", Vector3(0, 0.82, -0.84), Vector3(1.65, 1.25, 0.15), _material(Color(0.20, 0.28, 0.25), 0.78, 0.28), _appendages)
		"exploder":
			for side in [-1.0, 1.0]:
				_add_cylinder("Tank", Vector3(side * 0.56, 0.75, 0.18), 0.25, 0.86, _core_material, _appendages)
		"ambusher":
			_add_claws(1.05, 0.32)
		"boss":
			_add_claws(1.45, 0.82)
			_add_orbitals(5, 1.72)
			_add_box("BossPlate", Vector3(0, 1.33, -1.18), Vector3(1.6, 0.72, 0.16), _material(Color(0.10, 0.12, 0.11), 0.82, 0.26), _appendages)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = body_size.x * 0.62
	ring_mesh.outer_radius = body_size.x * 0.72
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 5
	ring_mesh.material = _material(Color(1.0, 0.20, 0.08, 0.76), 0.0, 0.55, true, true)
	_tell_ring = MeshInstance3D.new()
	_tell_ring.name = "StateVFX"
	_tell_ring.position.y = 0.055
	_tell_ring.mesh = ring_mesh
	_tell_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_root.add_child(_tell_ring)
	# 正式普通怪分支：非精英 melee_chaser 在程序化外壳之后挂载独立小僵尸包装，
	# 隐藏壳/核/附肢、保留 tell ring；动画由包装自驱动，避免旧 bob/appendage 程序姿势叠加。
	if FORMAL_NORMAL_SCENES.has(_base_kind) and _root != null:
		_load_formal_normal_model()
		# 按配方为普通与强化僵尸挂接红眼。
		if monster_has_eye_glow():
			_setup_eye_socket()


## 是否有已标定的僵尸眼位配方；普通版和强化版均可用。
func monster_has_eye_glow() -> bool:
	return not MonsterVariants.eye_socket_for(enemy_kind).is_empty()


## 在 `Head` 骨上建绑点。**只建挂点，不算偏移** —— 偏移要等下一帧。
##
## ## 为什么必须走骨骼绑点而不是固定世界坐标
## 怪物的头会随 idle / 攻击 / 受击转动。把眼球做成固定子节点，转脸时眼睛会留在原处 ——
## 那是明显的穿帮。挂到骨骼上则由引擎跟骨，与 `ranged_caster` 的枪
## （`SecurityShotgunAttachment`，同款 `BoneAttachment3D`）是同一套机制。
##
## ## 为什么要分两步（这步是实测逼出来的）
## GLB 是**本帧内刚实例化**的，骨架位姿与挂点世界矩阵在同一帧里还没解析完。
## 此刻读 `_eye_socket.global_transform` 会拿到未解析的值，反解出的偏移把眼睛送到脚底
## （实测 ratio=0.057，应为 0.535）。所以：本帧只建挂点，`_process` 下一帧再算偏移。
func _setup_eye_socket() -> void:
	var socket := MonsterVariants.eye_socket_for(enemy_kind)
	if socket.is_empty() or _formal_normal_root == null:
		return
	var skeleton := _find_formal_normal_skeleton()
	if skeleton == null:
		# 找不到骨架就**明确放弃**，而不是退化成固定坐标节点 ——
		# 后者会在转头时穿帮，且没人会发现。
		push_warning("强化怪 %s 找不到 Skeleton3D，发光眼未挂载" % enemy_kind)
		return
	if skeleton.find_bone(EYE_BONE_NAME) < 0:
		push_warning("强化怪 %s 的骨架里没有 %s 骨，发光眼未挂载" % [enemy_kind, EYE_BONE_NAME])
		return
	if _eye_socket != null and is_instance_valid(_eye_socket):
		_eye_socket.queue_free()
	_eye_socket = BoneAttachment3D.new()
	_eye_socket.name = EYE_SOCKET_NODE_NAME
	_eye_socket.bone_name = EYE_BONE_NAME
	skeleton.add_child(_eye_socket)
	_eye_pending = true


## 第二帧：算偏移 + 建眼球。由 `_process` 在 `_eye_pending` 时调用。
##
## ## 眼位是怎么算出来的（关键，别改成拍脑袋的常量）
## 三个模型**没有 eye 骨**，且小僵尸 / 保安僵尸的 `Head` 骨 pose 在**胸口**（y≈0.85）
## 而网格的头在 y≈1.5 —— 骨空间与网格**不同源**。所以：
##   ① 用**蒙皮后顶点**算总高，再取两眼附近窄带的脸部表面深度；
##   ② 按配方（`MonsterVariants.EYE_SOCKETS`）算出**模型根空间**的左右眼点；
##   ③ 把眼点换算成挂点的局部坐标 —— 直接对**引擎给出的挂点世界矩阵求逆**。
##
## ③ 刻意不自己拼 `骨位姿`：`BoneAttachment3D` 的 global_transform 除平移外还含骨的
## **旋转 basis**，手写骨空间换算必须逐位对上那个 basis，稍有偏差整只眼就飞走
## （实测把眼睛算到过胸口、下巴、脚底各一次）。让引擎给矩阵、我们求逆，天然一致。
func _finalize_eye_glow() -> void:
	_eye_pending = false
	if _eye_socket == null or not is_instance_valid(_eye_socket) or _formal_normal_root == null:
		return
	var socket_spec := MonsterVariants.eye_socket_for(enemy_kind)
	if socket_spec.is_empty():
		return
	var local_offsets: Array = socket_spec.get("bone_offsets", []).duplicate()
	if local_offsets.is_empty():
		var points := _eye_points_in_model_space(socket_spec)
		if points.is_empty():
			return
		var socket_inverse := _eye_socket.global_transform.affine_inverse()
		for point in points:
			local_offsets.append(socket_inverse * (global_transform * (point as Vector3)))

	if _eye_glow != null and is_instance_valid(_eye_glow):
		_eye_glow.queue_free()
	_eye_glow = StrongVariantEyeGlow3D.new()
	_eye_glow.name = "StrongEyeGlow3D"
	_eye_glow.variant_id = enemy_kind
	_eye_glow.eye_radius = float(socket_spec.get("radius", 0.030))
	# 先把眼球建好再入树，`_process` 一开始就跑在完整结构上。
	_eye_socket.add_child(_eye_glow)
	_eye_glow.build(local_offsets)


## 求左右眼点（**模型根空间**，即 `_root` 的局部空间）。
##
## 返回 `[左眼, 右眼]`（左 = −x）；取不到返回空数组。
##
## ⚠ 用**蒙皮后**顶点，不是 GLB 原始顶点：
## 模型是被骨架驱动摆姿势的，原始顶点只是静止姿势。用原始顶点算眼位，
## 再与「当前姿势的挂点矩阵」配合，两套空间不一致 ⇒ 头部一动眼睛就偏
## （实测：静止看还行，动画一跑就飞到下巴）。
## 蒙皮顶点与挂点同处当前姿势空间，两者相减才有意义。
func _eye_points_in_model_space(socket: Dictionary) -> Array:
	var points := PackedVector3Array()
	var root_inverse := _root.global_transform.affine_inverse()
	for node in _formal_normal_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var mesh := mesh_node.mesh
		if mesh == null:
			continue
		# **只取有蒙皮的角色本体**：保安僵尸（ranged_caster）身上还有一把双管炮，
		# 它是独立的无蒙皮网格。把它算进包围盒会拉低下界（实测 bottom 从 0 掉到 −0.41、
		# 高度从 1.82 涨到 2.24），眼位比例随之被算低 0.11 —— 眼睛落到下巴。
		if mesh_node.skin == null or not (mesh_node.get_parent() is Skeleton3D):
			continue
		var skeleton := mesh_node.get_parent() as Skeleton3D
		var xform := root_inverse * mesh_node.global_transform
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			if verts == null:
				continue
			var vertex_list := verts as PackedVector3Array
			var bone_list := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
			var weight_list := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
			for index in range(vertex_list.size()):
				points.append(xform * _skinned_vertex(
					skeleton, mesh_node.skin, vertex_list[index], bone_list, weight_list, index
				))
	if points.is_empty():
		return []
	var bounds := _vertex_bounds(points)
	var bottom := bounds.position.y
	var height := bounds.size.y
	if height <= 0.0:
		return []
	# 只在每只眼附近取脸部表面。整个头部带的最前点会命中头发、帽檐或鼻尖，
	# 把红眼悬到脸前 0.2–0.3m；正面图看似对齐，俯视就落到下巴/胸口。
	var eye_y := bottom + height * float(socket.get("y_ratio", 0.5))
	var half_x := float(socket.get("half_x", 0.15))
	var front := INF
	for point in points:
		if absf(point.y - eye_y) <= 0.06 and absf(absf(point.x) - half_x) <= 0.09:
			front = minf(front, point.z)
	if front == INF:
		push_warning("Eye surface calibration missing: %s" % enemy_kind)
		return []
	var eye_z := front + float(socket.get("front_offset", -0.015))
	return [Vector3(-half_x, eye_y, eye_z), Vector3(half_x, eye_y, eye_z)]



## 单顶点蒙皮：`Σ wᵢ · (bone_global_poseᵢ · skin.get_bind_poseᵢ) · v`。
##
## 必须用 `Skin.get_bind_pose()`，**不能**用 `get_bone_global_rest().affine_inverse()`：
## 实测两者不等（`Head` 的 bind origin y = −0.890，而 rest y = +0.890），
## 用后者会把整只怪算歪（这是本项目探针里踩过的第二个同类坑）。
func _skinned_vertex(
	skeleton: Skeleton3D, skin: Skin, vertex: Vector3,
	bones: PackedInt32Array, weights: PackedFloat32Array, index: int
) -> Vector3:
	var result := Vector3.ZERO
	var total := 0.0
	for slot_index in range(4):
		var slot := index * 4 + slot_index
		if slot >= bones.size() or slot >= weights.size():
			break
		var weight := weights[slot]
		if weight <= 0.0:
			continue
		var bone := bones[slot]
		# 减骨后骨架骨数可能多于 bind 数：宁可退回原始顶点，也不猜一个错的矩阵。
		if bone < 0 or bone >= skeleton.get_bone_count() or bone >= skin.get_bind_count():
			return vertex
		result += ((skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bone)) * vertex) * weight
		total += weight
	return vertex if total <= 0.0 else result / total


func _vertex_bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for point in points:
		box = box.expand(point)
	return box


## 正式普通怪包装里的骨架（三个模型结构一致：VisualGLB/<armature>/Skeleton3D）。
func _find_formal_normal_skeleton() -> Skeleton3D:
	if _formal_normal_root == null:
		return null
	for node in _formal_normal_root.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


func _load_formal_normal_model() -> void:
	var scene_path := str(FORMAL_NORMAL_SCENES.get(_base_kind, ""))
	var scene := load(scene_path) as PackedScene
	assert(scene != null, "Formal normal scene missing for %s" % enemy_kind)
	_formal_normal_root = scene.instantiate() as Node3D
	_formal_normal_root.name = "FormalNormal_%s" % enemy_kind
	_root.add_child(_formal_normal_root)
	_formal_normal_scene_path = scene_path
	_shell.hide()
	_core.hide()
	_appendages.hide()
	_apply_formal_tint()


## 给正式 GLB 模型染色。见 `FORMAL_MODEL_TINT` 的表头注释说明「为什么必须有」。
##
## 实现要点：
## ① **必须 duplicate 材质**。GLB 里的材质在多个实例间共享 —— 直接改 albedo
##    会把场上所有借同一模型的怪一起染成同色（实测踩过：改一只，全变红）。
## ② 逐 MeshInstance3D、逐 surface 处理。一个模型常有多段材质（身体/配件/枪）。
## ③ 只处理 `BaseMaterial3D`。自定义 shader 材质没有 albedo_color，跳过并留日志 ——
##    静默跳过等于"以为染了其实没染"，那是本文件反复警告过的同类坑。
func _apply_formal_tint() -> void:
	if not FORMAL_MODEL_TINT.has(enemy_kind):
		return
	if _formal_normal_root == null:
		return
	var tint: Color = FORMAL_MODEL_TINT[enemy_kind]
	var meshes := _formal_normal_root.find_children("*", "MeshInstance3D", true, false)
	var tinted := 0
	var skipped := 0
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for surface in range(mi.mesh.get_surface_count()):
			var source := mi.get_active_material(surface)
			var base := source as BaseMaterial3D
			if base == null:
				skipped += 1
				continue
			var clone := base.duplicate() as BaseMaterial3D
			clone.albedo_color = base.albedo_color * tint
			mi.set_surface_override_material(surface, clone)
			tinted += 1
	if tinted == 0:
		push_warning(
			"复刻怪 %s 染色失败：模型里没有可染的 BaseMaterial3D（跳过 %d 个 surface）。"
			% [enemy_kind, skipped]
			+ " 该怪将与同族其它变种共用外观。"
		)


func disable_formal_normal() -> void:
	if is_instance_valid(_formal_normal_root):
		_root.remove_child(_formal_normal_root)
		_formal_normal_root.queue_free()
	_formal_normal_root = null
	_formal_normal_scene_path = ""
	_shell.show()
	_core.show()
	_appendages.show()


func has_formal_normal() -> bool:
	return is_instance_valid(_formal_normal_root)


func has_animated_boss() -> bool:
	return is_instance_valid(_formal_boss_root) and _formal_boss_root.has_method("sync_context")

## 已挂载的正式 Boss 表现根；没有则返回 null。
## 给 `Enemy3D` 读骨姿态用（受击体积要跟着骨骼走），不交出物理所有权。
func get_animated_boss_root() -> Node3D:
	return _formal_boss_root if has_animated_boss() else null

func sync_boss_presentation(context: Dictionary) -> void:
	if has_animated_boss():_formal_boss_root.sync_context(context)

func sync_presentation(state: String, state_time: float, speed: float, telegraph_duration: float, recovery_duration: float) -> void:
	if has_formal_normal() and _formal_normal_root.has_method("sync_state"):
		_formal_normal_root.call("sync_state", state, state_time, speed, telegraph_duration, recovery_duration)


func _add_claws(radius: float, height: float) -> void:
	for side in [-1.0, 1.0]:
		var claw := _add_box("Claw", Vector3(side * radius, height, -0.34), Vector3(0.34, 0.32, 0.94), _shell_material, _appendages)
		claw.rotation.y = side * 0.34


func _add_orbitals(count: int, radius: float) -> void:
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		_add_sphere("Orbital", Vector3(cos(angle) * radius, 1.05 + sin(angle * 2.0) * 0.18, sin(angle) * radius), 0.18, _core_material, _appendages)


func _add_capsule(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = size.x * 0.5
	mesh.height = size.y
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	return _mesh_instance(node_name, position, mesh, parent)


func _add_sphere(node_name: String, position: Vector3, radius: float, material: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	return _mesh_instance(node_name, position, mesh, parent)


func _add_box(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	return _mesh_instance(node_name, position, mesh, parent)


func _add_cylinder(node_name: String, position: Vector3, radius: float, height: float, material: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = material
	return _mesh_instance(node_name, position, mesh, parent)


func _mesh_instance(node_name: String, position: Vector3, mesh: PrimitiveMesh, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	instance.layers = 1
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance


func _material(color: Color, metallic: float, roughness: float, emission := false, alpha := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.7
	if alpha:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
