class_name EnemyWarmup
extends RefCounted
## 把「每个怪种本局第一次生成」的 460 ms 挪到加载页背后。
##
## ## 为什么这件事值得做，以及为什么放在加载页
##
## 实测（`tools/_enemy_lifetime_cost_probe`，真渲染 / `--disable-vsync`）：
##
## | 场景 | 每只 |
## |---|---:|
## | 该怪种**本局第一次** | **460 ms** |
## | 同族后续，上一批仍存活 | **1.6 ms** |
## | 上一批全部销毁后再刷同族 | **1.8 ms** |
##
## ⇒ 460 ms 是**一次性**成本（读盘 + 材质变体编译），不是"每只都付"。
## 而它必然发生在"第一只这类怪被刷出来"的那一帧 —— 也就是玩家刚进门、正要开打的时候。
##
## 加载页是唯一的空档：玩家操作锁着、画面被黑幕/光圈盖着、而且**没有战斗**。
## 把 460 ms 放这里有三个好处：
##   ① 玩家完全看不到（不是"快一点"，是"不在他的视野里发生"）；
##   ② 不改变任何玩法时序（怪的刷新时机、数量、位置一个字节都没动）；
##   ③ 不影响表现（材质与模型都是同一套，预热只是让它们**提前被画过一次**）。
##
## ## 为什么预热「Avatar」而不是「Enemy3D」
##
## 460 ms 几乎全在表现层：正式模型 load（100~120 ms）+ 染色（106 ms）+ 壳/核/环材质与网格（101 ms）。
## 而 `Enemy3D` 还带 AI 登记、房间编成、血条、`killed` 记账 —— 在加载期造完整实例要牵连
## `MonsterAIManager` 与 `GameplaySpatialRegistry3D` 的登记/注销，风险远大于收益。
## 只造 `EnemyAvatar3D`（纯表现层，不引用任何玩法系统）就能覆盖掉绝大部分成本。
##
## 实测：预热 3 个基类（398 ms）之后，33 个 `egt_*` 怪种连续生成从 **1038 ms → 603 ms**。
##
## ## 只预热 3 个基类就够（对所有关卡成立）
##
## 有**正式 GLB** 的普通怪基类只有三个（见 `EnemyAvatar3D.FORMAL_NORMAL_SCENES`）：
## `melee_chaser` / `ranged_caster` / `fat_zombie03`。其余基类（`summoner` / `shielded` /
## `exploder` / `ambusher` / `boss`）是程序化外壳，没有读盘成本。
##
## 而远征03 的 33 只复刻怪**全部借用**这三种正式 GLB（见 `EnemyAvatar3D.PROXY_ASSET_KIND`），
## 材质变体族也只有这三族 ⇒ 预热基类等于覆盖全场。逐只预热 33 个只会把加载时间拖到 15 秒，
## 而收益为 0（同一变体第二次是 0.15 ms）。
##
## ⚠ 因此这份集合**与关卡无关**：塔楼、远征 01/02/03/99 一律取同一套。
## 新增一个「有正式 GLB 的普通怪基类」时必须同步加进来，漏加的症状是该怪种第一次
## 出现时卡 460 ms，而不报错。
##
## ## 它还剩什么没解决
##
## 预热后单只仍要 **~18 ms**（骨绑点、血条、碰撞形状、AI 记录…）。
## 一间房 10 只一次刷满 = 一帧 180 ms。这一项**预热解决不了**，要靠分帧生成 ——
## 那会改变"怪什么时候出现"，属手感判断，不在本文件的职责内。

## 预热件的摆放位置：远在场景之外。
##
## 不需要它在视锥内 —— 实测「节点带材质**进渲染场景**」这一下就已经触发管线准备
## （把特效摆在相机背后、根本不绘制，照样 64 ms）。放远处只是为了让它在任何镜头下
## 都不可能被看见，同时避免与房间几何/遮挡判断产生任何交互。
const WARM_OFFSET := Vector3(0.0, -1200.0, 0.0)

## 正式模型的三个基类，也是**全部关卡**的预热集合（见下节「只预热 3 个基类就够」）。
## 别名解析见 `EnemyAvatar3D.resolve_asset_kind`。
const BASE_KINDS: Array[String] = ["melee_chaser", "ranged_caster", "fat_zombie03"]

const AVATAR_SCRIPT := preload("res://src/enemy3d/EnemyAvatar3D.gd")


## 建一个影子 Avatar 并塞进渲染场景。**调用方负责在下一帧 `free()` 它**。
##
## 之所以拆出"建"和"释放"两步，是为了让调用方能把预热夹进它自己的逐帧循环里
## （加载页要把它和"最低可见时长"的空等重叠，见 `ExpeditionLoadingScreen._warm_and_hold()`）。
##
## 返回 null 表示环境不满足（stage 不在树里 / 脚本实例化失败），调用方据此收手即可。
static func spawn_probe(stage: Node3D, kind: String) -> Node3D:
	if stage == null or not is_instance_valid(stage) or not stage.is_inside_tree():
		return null
	var avatar := AVATAR_SCRIPT.new() as Node3D
	if avatar == null:
		return null
	avatar.name = "WarmupAvatar_%s" % kind
	avatar.position = WARM_OFFSET
	# 关掉 `_process`：影子实例不需要跑眼位延迟结算 / 状态同步，
	# 跑起来只会在加载期触发一堆与玩法状态相关的分支（而它根本没有玩法状态）。
	avatar.set_process(false)
	stage.add_child(avatar)
	avatar.call("configure", kind)
	return avatar


## 逐帧预热。**每个怪种一帧**，不是一帧全做 ——
## 单个 ~330 ms 一次排完就是一个硬冻结，摊开之后加载页最多只慢 3 帧。
##
## `stage` 必须是一个**已经在场景树里、且它的 world_3d 是可见的**节点
## （加载页里传当前关卡场景根）。传 null 或未入树时会静默跳过。
static func warm_avatars(stage: Node3D, kinds: Array = BASE_KINDS) -> void:
	if stage == null or not is_instance_valid(stage) or not stage.is_inside_tree():
		return
	var tree := stage.get_tree()
	if tree == null:
		return
	var probe: Node3D = null
	for value in kinds:
		if probe != null and is_instance_valid(probe):
			probe.free()
			probe = null
		probe = spawn_probe(stage, str(value))
		# 等一帧让它真正进入渲染场景（管线准备发生在这里，不是 `configure()` 返回时）。
		await tree.process_frame
	if probe != null and is_instance_valid(probe):
		# `free()` 而不是 `queue_free()`：后者排到帧末，加载页后面紧接着就是开圈，
		# 留一个 1200 m 外的影子节点在树里没有必要。它没有任何外部引用，可以直接释放。
		probe.free()
