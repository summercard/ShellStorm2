class_name Enemy3D
extends CharacterBody3D
## 3D 敌人统一有限状态机。不同怪物只配置参数和攻击策略，不复制生命、寻路、受击或死亡逻辑。

signal killed(enemy: Enemy3D, loot: Dictionary)
signal escaped(enemy: Enemy3D, context: Dictionary)
signal summon_requested(enemy: Enemy3D, count: int)
## 死亡分裂（远征03 布洛布三阶）。与 `summon_requested` 分开是因为二者语义不同：
## 召唤是「活着请求增援」，分裂是「死亡时留下子代」，且**必须指定子代怪种**——
## `summon_requested` 的消费方只产出 `minion` 通用小怪，表达不了「Blobulon 必裂成 Blobuloid」。
## 仍然走 `Dungeon3D._reserve_room_spawn()` 这条既有旁路，不新建实例化出口。
signal split_requested(enemy: Enemy3D, child_kind: String, count: int)
signal state_changed(previous: String, current: String)
signal boss_phase_changed(enemy: Enemy3D, phase: int)
## 显示器 Boss 完整播放激活流程后只发一次；房间玩法不得轮询 MonitorBossCombat 私有状态。
signal boss_activation_completed(enemy: Enemy3D)
signal health_changed(enemy: Enemy3D, current: int, maximum: int)
signal illumination_state_changed(enemy: Enemy3D, previous: String, current: String, context: Dictionary)

const PROJECTILE_SCRIPT := preload("res://src/combat3d/Projectile3D.gd")
const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d.tscn")
const VfxPool3D = preload("res://src/vfx/VfxPool3D.gd")
const VfxEffectBase3D = preload("res://src/vfx/VfxEffectBase3D.gd")
const VfxHealNumber3D = preload("res://src/vfx/VfxHealNumber3D.gd")
const DAMAGE_NUMBER_SCRIPT := preload("res://src/fx/CombatDamageNumber3D.gd")
const ILLUMINATION_SCRIPT := preload("res://src/enemy3d/EnemyIllumination3D.gd")
## 敌人分组名的唯一来源。Player3D/Projectile3D/PlayerVision3D 等按名字扫组，
## 名字写死在多处时改一处会静默漏掉另一处，所以从这里取。
const GROUP_ENEMY_3D := "enemy_3d"
const GROUP_DAMAGEABLE_3D := "damageable_3d"
## 仅供视野管理死亡表现，不能作为战斗/寻路目标。
const GROUP_DEATH_VISUAL_3D := "enemy_death_visual_3d"
## 一次性战斗特效的出生高度：胸口 = 脚底 + 0.65m。
## 特效侧（`VfxZombieGooDeath3D` / `VfxDeathBlast3D` 的 `SPAWN_CENTER_LIFT`）用同一个口径
## 反推脚底 —— 两边必须一致，否则「地上的液体」/「地面冲击波」会浮在怪的腰上。
const EFFECT_SPAWN_LIFT := 0.65
## **命中特效贴肉落点的兜底退让量**（米）。业主 2026-10-14 第四轮初估「大概 0.2 米」。
##
## 根因（已实测，不是推测）：弹体是在**碰撞壳表面**判命中的，而碰撞壳是**玩法口径**、
## 比模型胖一大圈 —— 且两边都被 `_apply_presentation_scale()` 的 0.7 缩放，换算到世界坐标后：
##   melee_chaser  碰撞柱世界半径 **0.714**，模型半宽 x **0.448** / z **0.334**
##   ranged_caster 碰撞柱世界半径 **0.770**，模型半宽 x **0.449** / z **0.602**
##   fat_zombie03  碰撞柱世界半径 **0.770**，模型半宽 x **1.839** / z **0.712**（比壳还胖）
## ⇒ 前两只从正面/背面打中时，壳面比模型**多出 0.27~0.38m**；只退 0.2m 实测仍差 0.18~0.24m。
## 而胖子僵尸的 X 向反过来 —— 壳面**已经在模型里面**，再退就埋进去了。
##
## ⚠ 结论：**一个常数不可能同时满足三只怪 × 各个方向**（壳是各向同性圆柱，模型是各向异性）。
## 真实退让量由 `hit_effect_anchor()` 按**模型实测包围盒**现算（见 `hit_effect_anchor`），
## 本常量只在模型包围盒算不出来时兜底。
##
## 只对**怪**用（见 `hit_effect_anchor`）：墙面 / 掩体没有「模型比碰撞盒小」这个问题，
## 收进去反而会钻进墙里。
const HIT_EFFECT_INSET_M := 0.20
## 贴肉量的**上限**（米）：防止「还差多少」被算得过大时把出生点一路推到怪体中心去
## （那会读成「从肚子里炸」）。取 0.80 —— 三只僵尸的碰撞柱世界半径是 0.714 / 0.770 / 0.770，
## 真实需要的退让量最大约 0.47（警察僵尸正背面），留足余量又远小于半径。
const HIT_EFFECT_MAX_INSET_M := 0.80
## 判定「模型在命中高度上的横截面」时那条薄带的**半高**（米）。
## 取 0.30 ≈ 躯干一层：太薄会卡进网格之间的空隙（读成「这一层没东西」而退回整盒），
## 太厚会把别的高度上的宽件（丸子头 / 脚部）算进这一层的体型。
const HIT_EFFECT_SLAB_BAND_M := 0.30
## 落点再往里咬一点（米）：正好落到包围盒表面上时，浮点误差可能让判定读成「差 1e-4 悬空」；
## 咬这一点点保证落点确实在模型身上，同时小到不影响观感。
const HIT_EFFECT_BITE_M := 0.03
## **僵尸三兄弟**：小僵尸（`melee_chaser`）/ 警察僵尸（`ranged_caster`）/ 胖子僵尸（`fat_zombie03`）。
## 业主 2026-10-14 一次点名，**三条口径都挂在这一个名单上**（别拆成三份会漂的别名）：
##   ① 被枪击 / 被近战打中 ⇒ FX01-20 `VFX-GOO-HIT-3D`（**v002 起 = 金属火星造型 + 僵尸绿**、
##      比打其它物体的那件大 10%），见 `uses_goo_hit_burst()`；
##   ② 死亡后**不再播倒地动画、不留尸体**（`_retire_goo_death_visual()`），见 `uses_no_corpse_death()`；
##   ③ 死亡表现按体型分两支（见 `GOO_DEATH_KINDS` 与 `_spawn_fat_death_burst()`）。
## 精英同族（如「巨大化 · 小僵尸」）一并适用 —— 它们本来就没有倒地动画（走压扁回收），
## 统一成一套表现，避免「同一只怪换个词缀就换一种死法」。
const ZOMBIE_KINDS: Array[String] = ["melee_chaser", "ranged_caster", "fat_zombie03"]
## 死亡走 FX01-19 `VFX-ZOMBIE-GOO-DEATH-3D`（绿方块爆开 + 抛物线飞溅 + 地面液体 + 绿色冲击波）的怪种。
## 胖子僵尸**不在**本名单：它走自己的重型自爆（FX01-17 橙红方块 + 绿色冲击波）。
const GOO_DEATH_KINDS: Array[String] = ["melee_chaser", "ranged_caster"]
## FX01-19 的尺寸基准。业主 2026-10-14 第二轮明确「**小僵尸的死亡特效不要改变**」
## ⇒ 保持 1.0（规格尺寸，几何常量本身不动，验收仍有尺寸线性断言守着）。
const GOO_DEATH_EFFECT_SIZE := 1.0
## FX01-17（胖子僵尸死亡）的尺寸基准。业主 2026-10-14 第二轮：
## 「把小僵尸的死亡特效**放大两倍**给胖子僵尸用」⇒ 由小僵尸的 1.0 提为 2.0。
## ⚠ 这条替换了 v001 的「按伤害半径反推尺寸」（radius × 0.6）口径：
##    现在的尺寸是**业主指定的固定倍率**，冲击波外缘（≈1.548 × 2.0 = 3.1m）
##    不再等于远征01 的 5.0m 伤害半径 —— 它是一条风格元素，不再当半径指示。
const FAT_DEATH_EFFECT_SIZE := 2.0
const VALID_STATES := [
	"dormant", "idle", "patrol", "alert", "chase", "search", "return",
	"telegraph", "attack", "recovery", "stagger", "dead",
]
const NORMAL_HP_MULTIPLIER := 3.0
const BOSS_HP_MULTIPLIER := 10.0
const GLOBAL_MOVE_SPEED_MULTIPLIER := 0.70
## 垂直位移只有一个来源：重力加地面。数值与 Player3D.GRAVITY_MPS2 同源，
## 怪物因此和角色共用同一套地板/坡面口径 —— 脚下没有地板会掉下去，
## 能走上坡下坡，也不会顺着阻挡爬到顶面。
const GRAVITY_MPS2 := 24.0
const TERMINAL_FALL_SPEED_MPS := 32.0
## 贴地时保留的极小向下速度，让 floor_snap 保持接触；不足以把怪沿坡推下去。
const FLOOR_STICK_MPS := -0.01
## 怪与怪的水平分离（不重叠）。权重 = 1 - 距离/最小间距，贴得越近推得越狠，
## 刚好挨着几乎不推，所以一队怪不会互相弹开。
## 分离只写水平分量：垂直永远归重力独占 —— 被四只怪围挤时中间的怪只会被
## 夹在原地，既不会被顶到同伴头顶，也不会被挤到地板以下。
const SEPARATION_WEIGHT := 0.62
const SEPARATION_RADIUS_SCALE := 0.90
const SEPARATION_NEIGHBOR_LIMIT := 8
## 邻居查询的额外半径，用于覆盖最大的 Boss 世界碰撞半径。
const SEPARATION_PROBE_MARGIN_M := 2.4
## 分离力的重算间隔（物理帧）。分离是「视觉上不要叠在一起」的软约束，20Hz 足够，
## 不需要每物理帧重算。依据：一次同类半径查询实测 100~300 微秒，而 38m 预激活半径
## （`Dungeon3D.ENEMY_PREACTIVATION_RANGE`）下同时激活的怪可达数十只 ——
## 每帧每只都查会把 60FPS 的物理预算吃光（实测 120 只 ⇒ 物理帧 42ms，掉到 24FPS）。
const SEPARATION_INTERVAL_FRAMES := 3
## 重力生效后，脚下真出现洞的怪会掉下去。比出生点低过这个深度就判「已离开可行走层」，
## 直接死亡 —— 房间因此不会卡在「有怪但打不到」的未清状态。
## 取值必须大于塔楼整层层高（`TowerGeometry3D.FLOOR_HEIGHT_M = 12.0`）：怪沿楼梯/连接
## 通道追玩家下一层时是 12m 级落差，不能算掉出世界；掉出世界是无限下坠，1.1s 就过 15m。
const FALL_DEATH_DROP_M := 15.0
const DEFAULT_BASE_SIZE_MULTIPLIER := 0.70
const BOSS_SIZE_MULTIPLIER := 1.5
const ARTIFICIAL_LIGHT_MOVE_MULTIPLIER := 0.40
const ARTIFICIAL_LIGHT_ATTACK_FREQUENCY_MULTIPLIER := 0.40
const SUNLIGHT_MAX_HP_DAMAGE_PER_SECOND := 0.02
const ILLUMINATION_UI_COLORS := {
	"darkness": Color(0.42, 0.20, 0.62, 1.0),
	"artificial_light": Color(0.10, 0.78, 1.0, 1.0),
	"sunlight": Color(1.0, 0.70, 0.10, 1.0),
}
const BODY_SCALE_BY_KIND := {
	"fat_zombie03": 1.0,
	"exploder": 0.78,
	"ranged_caster": 1.0,
	"melee_chaser": 1.0,
	"ambusher": 1.0,
	"shielded": 1.2,
	"summoner": 1.2,
	"boss": BOSS_SIZE_MULTIPLIER,
	# =========================================================================
	# 远征03 复刻怪：族内变种的区分体系（2026-10-29）
	#
	# 问题：这批怪复用别的怪资产，5 只远程怪同一个模型、同一个体型（1.0）、
	# 同一个颜色 —— 玩家在战斗中无法分辨"三连发"和"预判弹"该用不同躲避方式。
	#
	# 解法：**每族选一个主区分维度**，不是所有族都堆体型：
	#   远程族  → 体型阶梯（强度）+ 颜色（等于弹色，见 `EnemyAvatar3D.COLORS`）
	#   分裂族  → 纯体型阶梯（就是同一个东西越裂越小，不该变色）
	#   爆炸族  → 体型 + 颜色（三种不同的引爆方式，靠色温分）
	#   辅助族  → 放大 + 高亮（独苗，必须一眼看出"这只不一样，先杀它"）
	#
	# ⚠ 这批**必须逐只显式登记，不能靠别名回退**：
	#   回退会让 5 只远程全部 = `ranged_caster` 的 1.0，区分度归零。
	# =========================================================================
	# —— 远程族：0.86 → 1.18 严格递增，与血量/威胁同序 ——
	# 玩家看到更大的就知道要更小心，这条梯度是直的、可预测的。
	"egt_bullet_kin": 0.86,
	"egt_bandana_kin": 0.94,
	"egt_veteran_kin": 1.02,
	"egt_red_shotgun": 1.10,
	"egt_blue_shotgun": 1.18,
	# —— 分裂族：纯体型阶梯。母体最大，两次分裂每次都明显小一圈。——
	"egt_blobulon": 1.00,
	"egt_blobuloid": 0.62,
	"egt_blobulin": 0.40,
	# —— 爆炸族：pinhead 是标准尺寸(1.00)，nitra 酸性略小，bullat 极小极快。——
	# 注意：`exploder` 基类是 0.78，pinhead 显式写 1.00 是**刻意的** ——
	# 否则它比 nitra 还小，会出现「血更多、威胁更大反而更小」的倒挂。
	"egt_pinhead": 1.00,
	"egt_nitra": 0.90,
	"egt_bullat": 0.55,
	# —— 辅助族：比借用的 summoner(1.2) 再大一档，让它成为房间里的视觉焦点。——
	"egt_gunsinger": 1.30,
	# =========================================================================
	# 第二批 21 只（2026-10-29）：同样**逐只显式登记**，理由与上面一致 ——
	# 靠别名回退会让同族全部拿到被借资产的 1.0（例如书怪三只全 1.0、冲撞三只全 0.78），
	# 族内区分一次归零。顺序按族排，族内**严格单调**（体型随血量不下降）。
	# =========================================================================
	# —— 子弹族补完：cardinal(56) / hollowpoint(61) 都排在族内高端 ——
	"egt_cardinal": 1.08,
	"egt_hollowpoint": 1.12,
	# —— 霰弹枪族补完：老兵 75 血夹在红(69)与蓝(85)之间，体型也必须夹在中间 ——
	"egt_veteran_shotgun": 1.14,
	# —— 爆炸族补完：按血量阶梯排，bullat(6) < shotgat(10) < grenat(13) < spirat(19)
	#    < nitra(31) < pinhead(38) < king_bullat(62) —— 体型严格同序，没有倒挂 ——
	"egt_king_bullat": 1.12,
	"egt_shotgat": 0.62,
	"egt_grenat": 0.70,
	"egt_spirat": 0.78,
	# —— 分裂族补完：Chancebulon 是本族最大（100 血、随机招式）——
	"egt_chancebulon": 1.10,
	# —— 书怪族：三只**同血 25**，体型只用来区分"哪一本"，不代表强度 ——
	"egt_bookllet": 1.00,
	"egt_blue_bookllet": 1.06,
	"egt_green_bookllet": 1.12,
	# —— 法术族：gunjurer(49) 比 gigi(36) 大，同为悬浮施法者 ——
	"egt_gunjurer": 1.20,
	"egt_gigi": 1.10,
	# —— 触发 / 逃逸族：体型按血量排；钥匙小子最小（一直在跑）——
	"egt_keybullet_kin": 0.86,
	"egt_chance_kin": 0.90,
	"egt_confirmed": 1.05,
	"egt_mimic": 1.15,
	"egt_gun_fairy": 0.78,
	"egt_gripmaster": 0.98,
	# —— 重型族：本层普通怪血量顶点，也是体型顶点 ——
	"egt_chain_gunner": 1.14,
	"egt_gun_nut": 1.20,
}
const HEALTH_BAR_SIZE_BY_KIND := {
	"fat_zombie03": Vector2(1.8, 0.18),
	"exploder": Vector2(1.15, 0.14),
	"ranged_caster": Vector2(1.38, 0.15),
	"melee_chaser": Vector2(1.38, 0.15),
	"ambusher": Vector2(1.38, 0.15),
	"shielded": Vector2(1.55, 0.17),
	"summoner": Vector2(1.55, 0.17),
	"boss": Vector2(2.65, 0.24),
	# —— 远征03 复刻怪：血条宽度 = 基类宽度 × 本怪体型（2026-10-29）——
	#
	# 血条**不随父节点 scale 缩放**（`_position_overhead_health_bar()` 里显式
	# `scale = Vector3.ONE`），所以这里乘体型不会被放大两遍。
	# 条宽随体型走的意义：远距离看不清模型时，**条宽是最早能读出"这是哪个变种"的信号**。
	#
	# ⚠ 有可读性下限：体型 0.40 的 blobulin 若严格按比例只有 0.55 宽，
	# 在 1080p 下看不清血条分段。低于 0.72 一律夹到 0.72。
	"egt_bullet_kin": Vector2(1.19, 0.15),
	"egt_bandana_kin": Vector2(1.30, 0.15),
	"egt_veteran_kin": Vector2(1.41, 0.15),
	"egt_red_shotgun": Vector2(1.52, 0.16),
	"egt_blue_shotgun": Vector2(1.63, 0.16),
	"egt_blobulon": Vector2(1.38, 0.15),
	"egt_blobuloid": Vector2(1.00, 0.15),
	"egt_blobulin": Vector2(0.72, 0.13),
	"egt_pinhead": Vector2(1.15, 0.14),
	"egt_nitra": Vector2(1.04, 0.14),
	"egt_bullat": Vector2(0.72, 0.13),
	"egt_gunsinger": Vector2(2.02, 0.18),
	# —— 第二批（2026-10-29）：条宽 = 基类宽度 × 本怪体型，同族随体型递增 ——
	"egt_cardinal": Vector2(1.49, 0.15),
	"egt_hollowpoint": Vector2(1.55, 0.15),
	"egt_veteran_shotgun": Vector2(1.57, 0.16),
	"egt_king_bullat": Vector2(1.29, 0.15),
	"egt_shotgat": Vector2(0.72, 0.13),
	"egt_grenat": Vector2(0.81, 0.13),
	"egt_spirat": Vector2(0.90, 0.14),
	"egt_chancebulon": Vector2(1.52, 0.15),
	"egt_bookllet": Vector2(1.55, 0.16),
	"egt_blue_bookllet": Vector2(1.64, 0.16),
	"egt_green_bookllet": Vector2(1.74, 0.16),
	"egt_gunjurer": Vector2(1.86, 0.17),
	"egt_gigi": Vector2(1.71, 0.16),
	"egt_keybullet_kin": Vector2(1.19, 0.15),
	"egt_chance_kin": Vector2(1.24, 0.15),
	"egt_confirmed": Vector2(1.45, 0.15),
	"egt_mimic": Vector2(2.07, 0.18),
	"egt_gun_fairy": Vector2(1.08, 0.14),
	"egt_gripmaster": Vector2(1.52, 0.16),
	"egt_chain_gunner": Vector2(2.05, 0.18),
	"egt_gun_nut": Vector2(2.16, 0.18),
}
const HEALTH_BAR_FRAME_COLOR := Color(0.12, 0.02, 0.04, 0.96)
const HEALTH_BAR_EMPTY_COLOR := Color(0.018, 0.024, 0.034, 0.98)
const HEALTH_BAR_FULL_COLOR := Color(0.93, 0.055, 0.12, 1.0)
const HEALTH_BAR_LOW_COLOR := Color(1.0, 0.54, 0.12, 1.0)
## 小怪条只缩视觉，不改敌人模型、碰撞或生命数值；Boss 头顶条保持原尺寸。
const NORMAL_HEALTH_BAR_SCALE := 0.80
## 白段是视觉追赶层：真实血量立即减少，白段按速度追到真实比例。
const HEALTH_BAR_DELAY_SPEED := 1.8
const HEALTH_BAR_DELAY_COLOR := Color(1.0, 1.0, 1.0, 0.96)
const HEALTH_BAR_TEXTURE_SIZE := Vector2i(200, 24)
const HEALTH_BAR_BORDER_PX := 2
const HEALTH_BAR_PIXEL_SIZE := 0.005

# shielded仅为旧存档/历史行为测试保留，现行MonsterInjector与编辑器不再投放。
const PROFILES := {
	"fat_zombie03": {"hp": 232, "speed": 0.857142857, "damage": 19, "range": 1.55, "cooldown": 1.3, "patrol_multiplier": 0.5, "telegraph": 1.2, "recovery": 1.3, "alert": 0.6, "stagger": 0.8},
	"melee_chaser": {"hp": 58, "speed": 3.7, "damage": 12, "range": 1.90, "cooldown": 1.05},
	"ranged_caster": {"hp": 46, "speed": 2.25, "damage": 10, "range": 8.8, "cooldown": 1.8},
	"summoner": {"hp": 72, "speed": 1.65, "damage": 8, "range": 7.2, "cooldown": 4.8},
	"shielded": {"hp": 112, "speed": 2.0, "damage": 17, "range": 2.05, "cooldown": 1.55},
	"exploder": {"hp": 42, "speed": 3.1, "damage": 30, "range": 2.85, "cooldown": 3.0},
	"ambusher": {"hp": 50, "speed": 4.65, "damage": 18, "range": 2.15, "cooldown": 1.9},
	# Boss 基础生命 = hp × BOSS_HP_MULTIPLIER(10) = 5200 × 10 = 52000（第1层实测值）；
	# 更高楼层由 MonsterInjector 的 FLOOR_SCALING.hp_mult 与 boss_scale 通过
	# configure_from_enemy_data 的比例还原继续放大。改这一处 = 全楼层等比例放大。
	"boss": {"hp": 5200, "speed": 1.72, "damage": 24, "range": 9.5, "cooldown": 1.45},
	# —— 远征03：《挺进地牢》第一层复刻怪（2026-10-29）——
	# `hp` 是 §T0.2 幂律换算后的**3D 基线**（运行时还会 ×NORMAL_HP_MULTIPLIER=3）。
	# `speed` 是「目标 m/s ÷ 0.7」（apply_profile 里会再 ×GLOBAL_MOVE_SPEED_MULTIPLIER）。
	#
	# 【攻击方式全靠参数，不靠新分支】——见本表末尾 `volley` 键与 `_perform_volley_attack()`：
	#   volley.count      一次攻击发几发（≥2 时按 spread_deg 均匀散开）
	#   volley.spread_deg 扇形半角（度），0 = 全部同向
	#   volley.interval   连发间隔（秒），0 = 齐射
	#   volley.predict    预判系数 0~1（0 = 瞄当前位置，1 = 全量预测走位）
	# 这四项足以表达 EGT 的「单发 / 连发 / 扇形 / 预判」四类差异，
	# 因此五只远程怪共用 `ranged` 策略，符合 [AI 设计 §3.1]「参数优先」。
	"egt_bullet_kin": {
		"attack_style": "volley",
		"hp": 150, "speed": 2.857, "damage": 17, "range": 8.8, "cooldown": 2.2,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"volley": {"count": 1, "spread_deg": 0.0, "interval": 0.0, "predict": 0.0},
	},
	"egt_bandana_kin": {
		"attack_style": "volley",
		"hp": 150, "speed": 2.857, "damage": 17, "range": 8.2, "cooldown": 1.05,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"volley": {"count": 3, "spread_deg": 0.0, "interval": 0.12, "predict": 0.0},
	},
	"egt_veteran_kin": {
		"attack_style": "volley",
		"hp": 150, "speed": 3.714, "damage": 17, "range": 9.6, "cooldown": 1.6,
		"projectile_speed": 10.0, "projectile_range": 22.0,
		# 原作（Wiki 逐字）："They fire **4 bullets in a row**" + 预判 + 跑得比普通小子快。
		# 旧版写成 count=1 只加了预判 —— 那是把"狙击手"当成了"老兵"。
		# interval 0.12 ⇒ 4 连发 0.36 秒打完，配合 1.6 秒冷却才是"持续压制"的节奏。
		"volley": {"count": 4, "spread_deg": 1.5, "interval": 0.12, "predict": 0.62},
	},
	"egt_red_shotgun": {
		"attack_style": "volley",
		"hp": 300, "speed": 2.857, "damage": 17, "range": 6.4, "cooldown": 2.4,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"volley": {"count": 5, "spread_deg": 14.0, "interval": 0.0, "predict": 0.0},
		# 死亡全向喷：EGT 红霰弹「有几率」全向 6 发。这里用 chance 表达「有几率」，
		# 不写成 100% —— 原作三者里红的最安全，正因为它是"有几率"而非"必定"。
		"death_burst": {"count": 6, "chance": 0.35, "damage_ratio": 1.0},
	},
	"egt_blue_shotgun": {
		"attack_style": "volley",
		"hp": 400, "speed": 2.857, "damage": 17, "range": 6.8, "cooldown": 2.4,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"volley": {
			"count": 5, "spread_deg": 26.0, "interval": 0.16, "predict": 0.0,
			# 原作是「宽 5 发 + **快速接**宽 4 发」—— 两段属于**同一次攻击**，
			# 所以用 `followup` 接在主段之后，而不是当成"下一次攻击"（那样中间会隔一个冷却）。
			"followup": {"count": 4, "spread_deg": 26.0, "interval": 0.07, "predict": 0.0, "delay": 0.18},
		},
		"death_burst": {"count": 6, "chance": 0.35, "damage_ratio": 1.0},
	},
	"egt_blobulon": {
		"attack_style": "contact",
		"hp": 200, "speed": 3.143, "damage": 17, "range": 2.05, "cooldown": 1.4,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"death_split": {"child": "egt_blobuloid", "count": 2},
	},
	"egt_blobuloid": {
		"attack_style": "contact",
		"hp": 100, "speed": 3.429, "damage": 17, "range": 1.95, "cooldown": 1.3,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"death_split": {"child": "egt_blobulin", "count": 2},
	},
	"egt_blobulin": {
		"attack_style": "contact",
		"hp": 10, "speed": 4.857, "damage": 17, "range": 1.8, "cooldown": 1.1,
		"projectile_speed": 8.0, "projectile_range": 22.0,
	},
	"egt_pinhead": {
		"attack_style": "explode",
		"hp": 130, "speed": 3.429, "damage": 17, "range": 2.85, "cooldown": 3.0,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		# 原作："If the player gets too close, it will **leap** towards the player and explode"
		# —— 先扑再炸。0.22s 的延迟就是"它扑过来了、快退"这个可读窗口。
		"leap": {"leap_speed": 9.5, "leap_sec": 0.22},
	},
	"egt_nitra": {
		"attack_style": "explode",
		"hp": 100, "speed": 3.429, "damage": 17, "range": 2.6, "cooldown": 3.0,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		# 原作："If the player gets too close, it will **detonate itself**" —— 同样是先扑后炸。
		"leap": {"leap_speed": 8.0, "leap_sec": 0.22},
	},
	"egt_bullat": {
		"attack_style": "rush",
		# 一次性冲撞：命中即自身死亡。`suicide_rush` 是**新策略**（见 §T2）——
		# 常规 MeleeLunge 打完不死，这里"碰到就消失"改变的是行动拓扑而非参数。
		"hp": 10, "speed": 3.429, "damage": 17, "range": 7.5, "cooldown": 99.0,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"suicide_rush": {"speed": 11.0, "max_lifetime": 4.0},
	},
	"egt_gunsinger": {
		"attack_style": "support",
		# 辅助：不攻击玩家，给同伴加血加速。`support_buff` 是新策略（目标类型变了）。
		"hp": 150, "speed": 1.429, "damage": 0, "range": 7.2, "cooldown": 3.6,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"support_buff": {"radius_m": 12.0, "hp_ratio": 0.35, "speed_mult": 1.35, "duration": 5.0},
		# 原作是「停留」，且**玩家靠太近或自己受伤就中断施法逃跑**。
		# 两个键合起来才是完整的它：`immobile` 管常态不动，`interrupt` 管被打断。
		"immobile": true,
		"interrupt": {"flee_radius_m": 6.0, "hurt_window_sec": 2.5, "flee_sec": 2.5, "flee_speed_mult": 1.5},
	},
	# =========================================================================
	# 远征03 第二批：EGT 第一层剩余 21 种（2026-10-29 补齐）
	#
	# 目标：**整层 33 种非 Boss 敌人都能用同一套规格表表达**，不出现"这个怪没做"。
	# 设计依据：`docs/v0.1/reference/挺进地牢/第一层怪物数据表.md` 逐行。
	#
	# 这一批新增的关键键（全部可选，老怪一行都不用改）：
	#   attack_style   攻击骨架（volley / contact / explode / rush / support / flee / grab / orbit / chance）
	#   volley.pattern 弹道图形（line / fan / v / ring / cross / clover / compass / arrows / letter / dice / spiral）
	#   volley.bounce  子弹反弹次数（子弹榴弹王的弹跳弹）
	#   volley.homing  追踪强度 0~1（红衣主教 / 已确认者）
	#   volley_alt + alt_every  每隔 N 次攻击改用另一套规格（蓝霰弹第二段 / 枪坚果箭头弹群）
	#   blink          瞬移（空尖弹周期性、枪法师出手后）
	#   flee           逃跑 + 超时消失（钥匙小子 / 运气小子）
	#   disguise       伪装成宝箱，靠近或被打才现形（拟态怪）
	#   grab           悬停抓取，不改血只改位置（抓握大师）
	#   orbit          绕圈子弹链（链枪手）
	#   chance_moves   随机借用同族招式 + 有几率不攻击直接死（Chancebulon）
	#   death_split.children  死亡生成**多种**子代（子弹榴弹王同时产 Bullat 与 Shotgat）
	#
	# ⚠ 数值口径（2026-10-29 第二轮重定标，别再用旧口径）：
	#   `hp`     = **进场绝对值** = EGT 血量 × 10。10 这个系数来自「保持击杀发数」：
	#              EGT Bullet Kin 15 血 / 初始手枪约 6 伤 = 2.5~3 发；
	#              本工程初始步枪 `bp_starter_rifle` 50 伤/发 ⇒ 150 血正好也是 3 发。
	#              因此血量与原作**严格等比**（6.67 倍差就是 6.67 倍），不再做幂律压缩。
	#   `damage` = **命中玩家的实际伤害**。普通子弹/接触统一 17 = 玩家 100 血的 1/6，
	#              这正是原作「半颗心 = 6 颗心里的 1/6」；爆炸类 26（1.5×）。
	#   `speed`  = 「目标 m/s ÷ 0.7」。目标 m/s 由原作定性分档：慢 2.0 / 中 2.4 / 快 3.4 /
	#              浮空 1.8 / 停留 0.6。原作没有帧数据（见数据表 §8），这是**按定性排序的近似**。
	#   `cooldown` 按「occasionally 2.2 / rapidly 1.05 / periodically 2.6」三档。
	#   `projectile_speed` 以玩家移速（4.5 m/s）为锚：原作子弹约 3.5 倍移速 ⇒ 16 m/s；
	#              原作注明 fast-moving 的用 18~20。`projectile_range = range × 1.4`
	#              —— 原来不设射程时子弹只有 1 秒寿命、飞 7 米就自毁，那才是"看不到子弹"的真因。
	# =========================================================================
	# —— 2.1 子弹族补完：红衣主教（追踪弹簇）、空尖弹（瞬移连发）——
	"egt_cardinal": {
		"attack_style": "volley",
		"hp": 225, "speed": 2.857, "damage": 17, "range": 9.0, "cooldown": 2.3,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.86, 0.30, 0.42),
		# 主攻击：单发直射。每隔 3 次改为 5 发**追踪**弹簇 —— 原作「偶尔」，
		# 用 alt_every 表达频率，不改攻击骨架。
		"volley": {"count": 1, "spread_deg": 0.0, "interval": 0.0, "predict": 0.0},
		"volley_alt": {
			"pattern": "ring", "count": 5, "spread_deg": 0.0, "interval": 0.09,
			"predict": 0.25, "homing": 0.45, "speed": 5.2, "home_lifetime": 3.0,
		},
		"alt_every": 3,
	},
	"egt_hollowpoint": {
		"attack_style": "volley",
		"hp": 250, "speed": 2.571, "damage": 17, "range": 9.6, "cooldown": 1.05,
		"projectile_speed": 10.0, "projectile_range": 22.0,
		"bullet_color": Color(0.72, 0.48, 0.96),
		# 高射速连发（单发伤害低、密度高），周期性消失并在房间他处重现。
		"volley": {"count": 4, "spread_deg": 3.0, "interval": 0.09, "predict": 0.20},
		"blink": {"interval": 2.8, "radius_m": 9.0},
		# 浮空：不吃地面接触，走远程手位（`_is_ranged_style` 由 attack_style 推出）。
		"hover": true,
	},
	# —— 2.2 霰弹枪族补完：老兵霰弹枪（V 型 + 预判，死必喷）——
	"egt_veteran_shotgun": {
		"attack_style": "volley",
		"hp": 338, "speed": 2.857, "damage": 17, "range": 6.8, "cooldown": 2.2,
		"projectile_speed": 10.0, "projectile_range": 22.0,
		"bullet_color": Color(0.96, 0.52, 0.24),
		# 原作原文："a V-shaped spread of 5 fast-moving bullets with **100% predictive aim**"
		# —— 是 100%，不是"高概率"。写成 0.55 等于把它降级成了普通老兵。
		"volley": {"pattern": "v", "count": 5, "spread_deg": 22.0, "interval": 0.0, "predict": 1.0},
		# 原作三只里「必定」全向喷大量子弹 —— chance = 1.0，这是它比蓝霰弹更强的原因。
		"death_burst": {"count": 12, "chance": 1.0, "damage_ratio": 1.0},
	},
	# —— 2.3 爆炸族补完：子弹榴弹王（全向弹跳弹 + 死亡产子代）——
	"egt_king_bullat": {
		"attack_style": "volley",
		"hp": 260, "speed": 0.857, "damage": 17, "range": 9.0, "cooldown": 2.6,
		"projectile_speed": 6.0, "projectile_range": 22.0,
		# 原作全表对它的描述只有"周期向全向发射弹跳弹"，**没有"walks towards"**
		# —— 它是原地漂浮的炮台。`immobile` 让它不进远程绕圈分支。
		"immobile": true,
		"bullet_color": Color(0.98, 0.76, 0.22),
		# 周期性向全向发射**弹跳**弹：ring + bounce。弹跳让它覆盖整间房，
		# 玩家不能靠"站远处"规避。
		"volley": {"pattern": "ring", "count": 8, "interval": 0.05, "predict": 0.0, "bounce": 3},
		# 死亡时生成若干 Bullat 与 Shotgat —— 这是**多种**子代，第一批的
		# `child/count` 表达不了，故扩展为 `children[]`（旧的 child/count 仍然生效）。
		"death_split": {
			"children": [
				{"child": "egt_bullat", "count": 2},
				{"child": "egt_shotgat", "count": 2},
			],
		},
	},
	# —— 2.4 分裂族补完：Chancebulon（随机借用同族招式 + 有几率自杀）——
	"egt_chancebulon": {
		"attack_style": "chance",
		"hp": 500, "speed": 3.429, "damage": 17, "range": 2.1, "cooldown": 1.5,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.86, 0.72, 0.30),
		# 每 5 次里有 1 次**不攻击而是直接死亡**（原作的骰子感）。
		"chance_moves": {
			"self_destruct_chance": 0.20,
			"moves": ["contact", "dice", "ring"],
		},
	},
	# —— 2.5 书怪族：三色同血（25），只换弹形 ——
	# 三只血量完全相同，差异**只在弹道图案**。这是全表最纯粹的"同血不同招"样本。
	"egt_bookllet": {
		"attack_style": "volley",
		"hp": 250, "speed": 2.286, "damage": 17, "range": 9.2, "cooldown": 2.4,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.90, 0.88, 0.80),
		# `count` 必须等于模板笔画数（R = 10 笔），否则只画出第一笔就结束。
		"volley": {"pattern": "letter", "letter": "R", "count": 10, "interval": 0.06, "predict": 0.0},
		"hover": true,
	},
	"egt_blue_bookllet": {
		"attack_style": "volley",
		"hp": 250, "speed": 2.286, "damage": 17, "range": 9.2, "cooldown": 2.5,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.44, 0.66, 0.98),
		# 字母弹 + 来回脉动的环形弹：主攻击是脉动环（两圈环，间隔拉长读作"脉动"）。
		# 8 发 × 2 圈、间隔 0.12 ⇒ 一轮约 1.8 秒，正好在 2.6 秒冷却内打完。
		"volley": {"pattern": "ring", "count": 8, "interval": 0.12, "predict": 0.0, "pulse_rings": 2},
		"volley_alt": {"pattern": "letter", "letter": "N", "count": 9, "interval": 0.06, "predict": 0.0},
		"alt_every": 3,
		"hover": true,
	},
	"egt_green_bookllet": {
		"attack_style": "volley",
		"hp": 250, "speed": 2.286, "damage": 17, "range": 9.2, "cooldown": 2.6,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.52, 0.88, 0.48),
		# 大型四叶草形弹：4 个瓣 × 每瓣 4 发
		"volley": {"pattern": "clover", "count": 4, "spread_deg": 12.0, "interval": 0.07, "predict": 0.0},
		"hover": true,
	},
	# —— 2.6 法术 / 辅助族补完 ——
	"egt_gunjurer": {
		"attack_style": "volley",
		"hp": 188, "speed": 2.143, "damage": 17, "range": 8.8, "cooldown": 2.2,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.72, 0.52, 1.0),
		# 旋转图形弹（三角 / 圆 / X）：`spiral` 逐发旋进，形状随朝向轮转。
		"volley": {"pattern": "spiral", "count": 9, "interval": 0.10, "step_deg": 40.0, "predict": 0.0},
		# 攻击后瞬移换位 —— 与空尖弹同一套 blink，只是触发时机不同（出手后而不是定时）。
		"blink": {"interval": 0.0, "radius_m": 8.0, "on_attack": true},
		"hover": true,
	},
	"egt_gigi": {
		"attack_style": "volley",
		"hp": 120, "speed": 5.143, "damage": 17, "range": 7.6, "cooldown": 2.6,
		"projectile_speed": 4.2, "projectile_range": 22.0,
		"bullet_color": Color(0.96, 0.82, 0.42),
		# 吐「蛋」：蛋飞到玩家附近后炸出一群涌动子弹。
		# 用 `egg` 表达：先发一枚慢速蛋（视觉），再在落点炸一圈。
		"volley": {"count": 1, "spread_deg": 0.0, "interval": 0.0, "predict": 0.25, "speed": 4.2},
		"egg": {"hatch_sec": 0.85, "burst_count": 8, "burst_damage_ratio": 0.7, "homing": 0.25},
	},
	# —— 2.7 一次性冲撞族补完：三种"撞到即死 + 附加弹" ——
	"egt_shotgat": {
		"attack_style": "rush",
		"hp": 20, "speed": 3.429, "damage": 17, "range": 8.0, "cooldown": 99.0,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.86, 0.60, 0.96),
		"suicide_rush": {
			"speed": 10.5, "max_lifetime": 4.0,
			# 撞到/被打死时吐 V 型 2 发（原作「冲撞时附加 V 型 2 发」）
			"on_hit": {"pattern": "v", "count": 2, "spread_deg": 14.0},
		},
	},
	"egt_grenat": {
		"attack_style": "rush",
		"hp": 30, "speed": 3.429, "damage": 17, "range": 8.0, "cooldown": 99.0,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.96, 0.42, 0.18),
		"suicide_rush": {
			"speed": 10.0, "max_lifetime": 4.0,
			"on_hit": {"pattern": "line", "count": 1, "explosive": true, "damage_ratio": 0.7},
		},
	},
	"egt_spirat": {
		"attack_style": "rush",
		"hp": 50, "speed": 3.429, "damage": 17, "range": 8.5, "cooldown": 99.0,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.62, 0.92, 0.86),
		# 多次中途重定位 + 预判走位，撞墙才停 —— `repositions` 是它与 bullat 的唯一差别。
		"suicide_rush": {
			"speed": 9.5, "max_lifetime": 5.0, "repositions": 3, "predict": 0.75,
			"on_hit": {"pattern": "line", "count": 1},
		},
	},
	# —— 2.8 触发 / 逃逸型（不主动攻击，靠"追不上"制造变数）——
	"egt_keybullet_kin": {
		"attack_style": "flee",
		"hp": 150, "speed": 4.286, "damage": 17, "range": 2.0, "cooldown": 1.2,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		# 逃跑 + 超时**传送消失**（不是被打死）。掉落钥匙属局内经济，本关未接入，
		# 见 `怪物设计.md §T6` 的已知差异 —— 这里只保证"打不死就白跑"这条行为。
		"flee": {"speed_mult": 1.45, "vanish_after": 11.0},
	},
	"egt_chance_kin": {
		"attack_style": "flee",
		"hp": 150, "speed": 4.286, "damage": 17, "range": 2.0, "cooldown": 1.2,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"flee": {"speed_mult": 1.45, "vanish_after": 11.0},
	},
	"egt_confirmed": {
		"attack_style": "volley",
		"hp": 450, "speed": 3.143, "damage": 17, "range": 9.8, "cooldown": 2.3,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.56, 0.36, 0.72),
		# 停下时从袍下射出 **4 条蛇形追踪弹**：4 条流，各带追踪。
		"volley": {"pattern": "serpentine", "count": 4, "interval": 0.16, "predict": 0.3, "homing": 0.4, "home_lifetime": 2.8},
	},
	"egt_mimic": {
		"attack_style": "volley",
		"hp": 1000, "speed": 3.143, "damage": 17, "range": 9.0, "cooldown": 1.9,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.92, 0.74, 0.30),
		# 被开箱或被射击才现形：没有宝箱系统时，用「靠近或被打才解除静态伪装」等价表达。
		"disguise": {"reveal_radius_m": 3.4},
		"volley": {"pattern": "ring", "count": 8, "interval": 0.06, "predict": 0.0},
		"volley_alt": {"pattern": "ring", "count": 12, "interval": 0.05, "predict": 0.0},
		"alt_every": 2,
	},
	"egt_gun_fairy": {
		"attack_style": "volley",
		"hp": 150, "speed": 4.286, "damage": 17, "range": 8.4, "cooldown": 1.35,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.98, 0.86, 0.52),
		# 房间内游荡 + 高射速连发（不追人、乱飞，所以命中靠"她自己飘过来"）
		"volley": {"count": 3, "spread_deg": 6.0, "interval": 0.08, "predict": 0.0},
		"wander": {"radius_m": 8.0, "retarget_sec": 2.2},
		"hover": true,
	},
	"egt_gripmaster": {
		"attack_style": "grab",
		"hp": 300, "speed": 2.857, "damage": 0, "range": 3.2, "cooldown": 6.0,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		# 悬在玩家上方、闪蓝后下压抓人。**不改血量、只改位置** —— 与原作一致：
		# 「不造成伤害却改变关卡状态」。原作还会把已清房间重置，本工程缺"房间重置"
		# 这条链路，暂以「抛回房间入口」表达，见 §T6 已知差异。
		"grab": {"hover_height_m": 4.2, "telegraph_sec": 0.8, "dive_speed": 12.0, "throw_distance_m": 10.0},
		# —— 原作两条硬规则（2026-10-29 第三轮补）——
		# ① "Automatically **dies if all other enemies in the room are killed**"
		#    ⇒ 清场后它**自己死**，玩家不需要打它。旧实现只做了"有别人时无敌"，
		#    于是清完场还剩一只 300 血的打不动的在飘 —— 那不是原作的语义。
		# ② "After unsuccessfully trying to grab the player **3 times**, it will vanish"
		#    ⇒ 抓空 3 次就消失，**不是**无限重复。
		"invulnerable_while_others_alive": true,
		"die_when_others_dead": true,
		"max_grab_misses": 3,
		"hover": true,
	},
	# —— 2.9 重型（本层普通怪血量顶点，像"小 Boss"）——
	"egt_gun_nut": {
		"attack_style": "volley",
		"hp": 1000, "speed": 2.571, "damage": 17, "range": 8.6, "cooldown": 2.9,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.78, 0.62, 0.36),
		# 举剑砸地：90° 扇形 + 4 组箭头形弹群；**只能瞄 8 个罗盘方向**（snap_deg = 45）。
		"volley": {"pattern": "compass", "count": 7, "spread_deg": 45.0, "snap_deg": 45.0, "interval": 0.0, "predict": 0.0},
		"volley_alt": {"pattern": "arrows", "count": 4, "spread_deg": 42.0, "snap_deg": 45.0, "interval": 0.0, "predict": 0.0},
		"alt_every": 2,
		# 大 jammed 弹：撞到障碍炸成一圈（原作有，我们之前完全没有）。
		# 速度 6.5 比普通 8 慢 —— 它是"看得到的大弹"，快了就变成突如其来的一圈。
		"jammed": {"speed": 6.5, "predict": 0.0, "shatter_count": 8, "shatter_damage_ratio": 0.5, "shatter_speed": 6.0},
	},
	"egt_chain_gunner": {
		"attack_style": "orbit",
		"hp": 900, "speed": 3.0, "damage": 17, "range": 8.0, "cooldown": 3.4,
		"projectile_speed": 8.0, "projectile_range": 22.0,
		"bullet_color": Color(0.72, 0.80, 0.92),
		# 停下甩出子弹链：约 3 圈/秒转 2 秒，期间缓慢逼近；链可穿墙（子弹不下发射程判定）。
		"orbit": {
			"duration": 2.0, "rev_per_sec": 3.0, "bullets_per_rev": 6,
			"radius_m": 3.2, "speed": 6.4,
		},
	},
}
# 「-强化怪」（`MonsterVariants`）**不在上表占行**。变种的 hp / damage / range /
# 弹道全部由 `_profile_for()` 从基类实时派生，只把倍率作用一次。
# 理由：单独抄一份变种基线 = 两份数值，调普通怪时必然漂移。

## 敌人子弹的**基准弹速**（m/s）。现行敌弹在 `_fire_projectile` 里写死这个数，
## 所有远程怪与 Boss 技能共用同一个值。抽成常量是为了让「强化怪弹速 ×1.3」
## 有一个确定的乘法基准，而不是在派生时凭记忆再写一个 7。
const DEFAULT_ENEMY_PROJECTILE_SPEED := 7.0
## 敌人子弹的**基准飞行距离**（m）。
##
## 敌弹当前没有射程字段（`Projectile3D.range_m == 0` 表示不启用），实际飞行距离由
## 「最大存活 1 秒」兜底给出 ≈ 7 m/s × 1 s。这里把这个**既有事实**显式记下来，
## 好让「强化怪射程 ×2」有基准可乘；普通怪仍然不下发射程 ⇒ 行为逐字不变。
const DEFAULT_ENEMY_PROJECTILE_RANGE_M := 7.0

# MonsterInjector 的旧 2D 基线只用于还原楼层、主题、精英与小怪倍率；
# 实际 3D TTK 必须建立在上面的 PROFILES 上，避免 10–40 HP 覆盖 3D 战斗基线。
const SOURCE_HP_BASE := {
	"fat_zombie03": 100.0,
	"melee_chaser": 25.0, "ranged_caster": 15.0, "summoner": 30.0,
	"shielded": 40.0, "exploder": 10.0, "ambusher": 18.0, "boss": 200.0,
}
const SOURCE_DAMAGE_BASE := {
	"fat_zombie03": 8.0,
	"melee_chaser": 5.0, "ranged_caster": 8.0, "summoner": 0.0,
	"shielded": 3.0, "exploder": 15.0, "ambusher": 7.0, "boss": 20.0,
}

## `_strong` 后缀的三个是「普通怪变种」，定义与倍率见 `MonsterVariants`；
## 列在这里只是为了场景里手动摆放时下拉选得到，它们的数值一律从基类派生。
@export_enum(
	"fat_zombie03", "melee_chaser", "ranged_caster", "summoner", "exploder", "ambusher", "boss",
	"fat_zombie03_strong", "melee_chaser_strong", "ranged_caster_strong",
	"egt_bullet_kin", "egt_bandana_kin", "egt_veteran_kin",
	"egt_red_shotgun", "egt_blue_shotgun",
	"egt_blobulon", "egt_blobuloid", "egt_blobulin",
	"egt_pinhead", "egt_nitra", "egt_bullat", "egt_gunsinger",
	"egt_cardinal", "egt_hollowpoint", "egt_veteran_shotgun", "egt_king_bullat",
	"egt_chancebulon", "egt_bookllet", "egt_blue_bookllet", "egt_green_bookllet",
	"egt_gunjurer", "egt_gigi", "egt_shotgat", "egt_grenat", "egt_spirat",
	"egt_keybullet_kin", "egt_chance_kin", "egt_confirmed", "egt_mimic",
	"egt_gun_fairy", "egt_gripmaster", "egt_gun_nut", "egt_chain_gunner"
) var enemy_kind := "melee_chaser"
@export var room_id := ""

var max_hp := 58
var current_hp := 58
var move_speed := 3.7
var contact_damage := 12
var attack_range := 1.35
var attack_cooldown := 1.05
var ai_state := "idle"
var _state_time := 0.0
var _attack_timer := 0.0
var _slow_factor := 1.0
var _slow_timer := 0.0
# —— 远征03 复刻怪专用运行时状态（2026-10-29）——
# 连发队列：存「延迟 + 散布 + 预判」，到点才算方向。见 `_tick_pending_volleys()`。
var _pending_volleys: Array[Dictionary] = []
# 一次性冲撞（`egt_bullat`）：激活后要么撞到人、要么超时自毁，两者都必须以 `_die()` 收场。
var _suicide_rush_active := false
var _suicide_rush_timer := 0.0
# 加速 buff（`egt_gunsinger` 给的）。与 `_slow_factor` 对称，只乘有效速度，不改 `move_speed`。
var _haste_factor := 1.0
var _haste_timer := 0.0
# —— 远征03 第二批（21 种）新增的运行时状态（2026-10-29）——
# 攻击计数器：`volley_alt` + `alt_every` 靠它决定这一轮走主规格还是备用规格。
# 用计数而不是计时，是为了让「每隔 3 次换招」在帧率波动下仍然精确可复现。
var _egt_attack_count := 0
# 瞬移（空尖弹定时 / 枪法师出手后）。`blink_timer` 到点执行，随后按 interval 重置。
var _blink_timer := 0.0
# 逃跑超时（钥匙小子 / 运气小子）：到点直接消失，**不是被打死**。
var _flee_timer := 0.0
# 施法被打断后的短暂逃跑（枪歌者）。与 `_flee_timer` 刻意分开：
# `flee` 是「这一整局只逃不回头」，这里是「被打断 → 逃几秒 → 回来继续施法」。
var _egt_interrupt_flee := 0.0
# 最近一次受伤的剩余计时（秒）。`interrupt` 用它判断"自己受伤就中断"。
var _egt_hurt_window := 0.0
# 一次性冲撞的重定位（Spirat）：每次重定位都把朝向改成对玩家的新一轮预判。
var _rush_repositions_left := 0
# 抓握大师的下压状态机：idle → telegraph(闪蓝) → dive(下压) → recover。
var _grab_state := "idle"
# 抓空次数。原作 "After unsuccessfully trying to grab the player 3 times, it will vanish"
# —— 没有这个计数，它就是一个无限抓的永动机。
var _grab_miss_count := 0
# 爆炸延迟：扑击到落地之间那段。>0 时 `_tick_egt_state` 递减，到 0 才真的炸。
var _explode_pending := 0.0
var _grab_timer := 0.0
var _grab_dive_target := Vector3.ZERO
# 链枪手的绕圈链：`_orbit_angle` 逐帧推进，`_orbit_timer` 到点收链。
var _orbit_active := false
var _orbit_angle := 0.0
var _orbit_timer := 0.0
var _orbit_emit_accumulator := 0.0
# 拟态怪：`true` 时是"宝箱"状态（不动、不攻击、不吃伤害），靠近或被打才现形。
var _disguised := false
# 吉吉的「蛋」：蛋飞出去之后在落点炸开一群涌动子弹。
# 用独立队列而不是给子弹加回调 —— 子弹池化复借后回调对象可能已经死了，
# 而这只怪的蛋只需要"某个时刻在某个点炸一圈"，不需要真的挂在子弹上。
var _pending_eggs: Array[Dictionary] = []
# 游荡型（枪精灵）：绕着一个随机点飘，不主动贴脸。
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
# 「消失」而不是「死亡」：逃跑超时的钥匙小子 / 运气小子用。
# `_die()` 要负责清房记账，但**不该**喷死亡特效、掉掉落 —— 用这个标志把两者拆开。
var _vanish_requested := false
var _target: Node3D = null
var _last_hit_direction := Vector3.ZERO
# 命中击退强度（m/s）。子弹默认 0（不位移），霰弹=0.8（轻微），由 take_projectile_damage 写入。
var _hit_knockback := 0.0
var _summon_count := 0
var _external_velocity := Vector3.ZERO
var _external_timer := 0.0
var _dot_damage := 0
var _dot_remaining := 0.0
var _dot_tick := 0.0
var enemy_data: Dictionary = {}
var _lost_sight_time := 0.0
var _last_known_target_position := Vector3.ZERO
var _home_position := Vector3.ZERO
var _home_initialized := false
var _runtime_ai_active := true
var _patrol_target := Vector3.ZERO
var elite_modifier_id := ""
var elite_id := ""
var elite_behavior_id := ""
var elite_level := 0
var elite_encounter_instance_id := ""
var elite_translation_id := ""
var elite_stolen_modules: Array[Dictionary] = []
var _elite_growth_profile: Dictionary = {}
var _elite_escape_active := false
var _elite_escape_elapsed := 0.0
var _elite_escape_origin := Vector3.ZERO
var _elite_attack_counter := 0
var _elite_behavior_trigger_count := 0
var _absorb_cooldown := 0.0
var boss_phase := 1
var _ambush_triggered := false
var _strafe_sign := 1.0
var _bypass_shield_once := false
var _fate_statuses: Dictionary = {}
var _fate_freeze_remaining := 0.0
var _fate_visuals: Dictionary = {}
var _fate_ice_slow_active := false
var _damage_element := ""
const DamageStyle := preload("res://src/vfx/DamageNumberStyle.gd")
var _source_hp_scale := 1.0
var _source_damage_scale := 1.0
var _overhead_health_root: Node3D
var _overhead_health_sprite: Sprite3D
var _illumination_status_label: Label3D
var _elite_name_label: Label3D
var _overhead_health_image: Image
var _overhead_health_texture: ImageTexture
var _overhead_health_size := Vector2.ZERO
var _overhead_health_ratio := 1.0
var _overhead_delayed_health_ratio := 1.0
var _overhead_health_bar_initialized := false
## 本怪头顶条实际生效的整体缩放（普通小怪 0.80 / Boss 与精英 1.0）。
## 真正算它的地方只有 `_ensure_overhead_health_bar` 一处，验收从快照读它，
## 免得把「谁该缩」的判断抄进测试里、两边各写一遍。
var _overhead_health_bar_scale := 1.0
var _elite_health_bar_profile: Dictionary = {}
var _kind_scale_multiplier := 1.0
var _variant_scale_multiplier := 1.0
## 当前怪种**生效中**的战斗基线。普通怪就是 `PROFILES` 里那一行；
## 强化怪是 `_profile_for()` 派生出来的副本（不写回表）。
## 每帧读它而不是反复查表/派生，避免在 `_physics_process` 里重复构造字典。
var _active_profile: Dictionary = {}
var illumination_sensor: EnemyIllumination3D
var _illumination_damage_accumulator := 0.0

# ── 启动过程（0.30–0.60s：转身 → 吼叫 → 头顶图标 → 攻击）────────────────────
# 设计见 docs/v0.1/06A_怪物AI系统完整设计_评审稿.md §6.1.1–§6.1.4；
# 数值公式唯一真源 MonsterStartupProfile（本类只消费，不自己算常量）。
## 启动过程是否正在计时。挂在 `alert` 状态上，不新增 AI 状态。
var _startup_active := false
## 段 A（转身）时长（秒）。段 B（吼叫）从它开始。
var _startup_turn_sec := 0.0
## 启动过程总时长（秒），∈ [0.30, 0.60]。
var _startup_total := 0.0
## 本次抽到的随机抖动，转身速率要用同一个值反推，不能重抽。
var _startup_jitter := 0.0
## 归一化后的转角，同上 —— 转身速率必须与时长同源。
var _startup_delta_yaw_deg := 0.0
## 只在跨过段 A/段 B 边界时弹一次图标；重复弹会让「吼」变成闪烁。
var _roar_icon_fired := false
## 头顶吼叫图标实例。挂在 `_overhead_health_root` 下，随血条槽根逐帧跟位。
var _roar_icon: VfxMonsterRoarIcon3D = null
## 同一次交战中只播一次启动过程；脱战静默满 REARM_AFTER_SECONDS 后重新武装。
var _startup_armed := true
## `_target == null` 的连续时长，用于重新武装。
var _disengage_elapsed := 0.0
var _startup_rng := RandomNumberGenerator.new()
var _ai_decision: Dictionary = {}
var _navigation_agent: NavigationAgent3D
var _stuck_time := 0.0
var _stuck_recovery_count := 0
var _avoidance_sign := 1.0
var _last_motion_position := Vector3.ZERO
var _patrol_step := 0
var _boss_skill_bag: Array[String] = []
var _boss_skill_index := 0
var monitor_combat: MonitorBossCombat
## 显示器 Boss 的子弹受击层（3D 第 3 层，与敌人层的值相同）。
## **只有动画受击盒在这个层上。**
## 根节点那个圆柱（半径 1.92×根倍率 = 2.016 m）比可见屏幕宽得多（屏幕半宽仅 0.85 m），
## 若它继续留在子弹层，子弹会在屏幕**前方 1.0–1.3 m** 处就被它拦下 ——
## 实测子弹撞到的 collider 名字就叫 `Enemy3D`，命中特效落在模型前面的空气里，
## 这正是业主看到的「隔空击中」（2026-10-14 第二轮反馈）。
## 圆柱的**移动/阻挡口径一格未动**（自身移动只看 `collision_mask = 1`），
## 只是不再接子弹：接子弹的职责整份交给跟骨走的受击盒。
const MONITOR_BULLET_LAYER := 4

## 显示器 Boss 的**动画受击盒**。根节点那个固定圆柱跟不上屏幕的前倾/扑砸/自转，
## 而且比可见模型宽得多；受击盒挂在**独立代理体** `EnemyHitVolume3D` 上，
## 而不是挂在怪物自己身上 —— 盒子会伸进地面与墙里，挂在身上 `move_and_slide`
## 会把怪顶起来（实测坐地抬高 0.42 m）。
var _monitor_hit_body: EnemyHitVolume3D = null
var _monitor_hit_shapes: Array[CollisionShape3D] = []
var _monitor_hit_presentation: MonitorBossPresentation = null
var _last_attack_result := "none"
var _last_state_reason := "spawned"
var _ambush_reburrow_cooldown := 0.0
var _ambush_unseen_time := 0.0
var _active_explosion_committed := false
## 关卡级死亡自爆规格（远征01 `monster_rules.death_explosion.<kind>`）。
## 空字典 = 本怪不自爆（缺省，塔楼与其余关卡恒为空）。
var _death_explosion: Dictionary = {}
## 当前生效的分离推力速度，以及重算相位（-1 = 尚未初始化）。
var _separation_push := Vector3.ZERO
var _separation_phase := -1

@onready var avatar: EnemyAvatar3D = $Avatar
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group(GROUP_ENEMY_3D)
	add_to_group(GROUP_DAMAGEABLE_3D)
	collision_layer = 4
	collision_mask = 1
	# 与 Player3D 同一套地面口径：44° 以内算可走的坡，更陡的算墙。
	# floor_snap 只跨数厘米的接缝，不用它模拟楼梯，所以怪不会顺着阻挡爬上顶面。
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_snap_length = 0.32
	floor_max_angle = deg_to_rad(44.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	safe_margin = 0.035
	illumination_sensor = ILLUMINATION_SCRIPT.new() as EnemyIllumination3D
	illumination_sensor.configure(self)
	illumination_sensor.illumination_state_changed.connect(_on_illumination_state_changed)
	_startup_rng.randomize()
	apply_profile(enemy_kind)
	illumination_sensor.force_refresh(true)
	if MonsterAIManager != null:
		MonsterAIManager.register_enemy(self)
	tree_exiting.connect(_on_tree_exiting)
	health_changed.connect(_on_self_health_changed)
	_ensure_overhead_health_bar()
	health_changed.emit(self, current_hp, max_hp)
	transition_to("idle")
	_last_motion_position = global_position


## 查表用的怪种 key：**强化怪一律回退到它的基类**。
##
## 体型表、血条宽表、血量基线表都不为变种单列一行 —— 变种改的是「倍率」，
## 表的形状照抄原怪。于是以后改原怪的体型或条宽，强化怪自动跟随，
## 不存在「同一件事写两处、改一处忘另一处」。
func _table_kind() -> String:
	return MonsterVariants.base_of(enemy_kind) if MonsterVariants.is_variant(enemy_kind) else enemy_kind


## 取某怪种的战斗基线。强化怪 = **原怪基线 × 变种倍率**，实时派生。
##
## 返回的是派生副本，不是 `PROFILES[base]` 的引用 —— 派生值不写回表，
## 所以「原怪基线」始终只有一份。改 `PROFILES["melee_chaser"]["hp"]`，
## 强化怪下一次 `apply_profile` 就跟着变。
##
## 未在 `MonsterVariants` 登记倍率的键（如 `speed` / `cooldown` / `patrol_multiplier`）
## 一律照抄原怪 —— 业主 2026-10-16 未要求强化怪变速，故体型变大但速度不变。
##
## `static` 是刻意的：本函数只读常量，不碰实例状态。于是验收可以**直接调它**，
## 不必实例化一整只怪（裸 `Enemy3D.new()` 缺 Avatar/CollisionShape3D 子节点，
## 一 apply_profile 就刷 engine ERROR，会把「按 ERROR 计数判定」的跑法搅浑）。
## 查 `BODY_SCALE_BY_KIND` / `HEALTH_BAR_SIZE_BY_KIND` 这类**按种分表**的统一入口。
##
## 顺序是「本体 → 借用的资产 → 兜底」：远征03 复刻怪（`egt_*`）的美术是借来的，
## 体型与血条宽度默认也该跟着被借的那只走；只有明确想和"借来的那只"拉开差异的
## （例如布洛布三阶必须看得出阶段）才在表里单独占一行。
static func kind_table_lookup(table: Dictionary, kind: String, fallback: Variant) -> Variant:
	if table.has(kind):
		return table[kind]
	var proxied := EnemyAvatar3D.resolve_asset_kind(kind)
	if table.has(proxied):
		return table[proxied]
	return fallback


static func profile_for(kind: String) -> Dictionary:
	if not MonsterVariants.is_variant(kind):
		return PROFILES.get(kind, PROFILES["melee_chaser"]) as Dictionary
	var base_kind := MonsterVariants.base_of(kind)
	if not PROFILES.has(base_kind):
		return PROFILES["melee_chaser"] as Dictionary
	var spec: Dictionary = MonsterVariants.VARIANTS[base_kind]
	var out: Dictionary = (PROFILES[base_kind] as Dictionary).duplicate(true)
	out["hp"] = float(out["hp"]) * float(spec.get("hp_mult", 1.0))
	out["damage"] = float(out["damage"]) * float(spec.get("damage_mult", 1.0))
	# 体型放大 1.5 倍后攻击距离必须同步放大。否则模型把手/打击面伸到 1.5 倍，
	# 判定还停在原值 ⇒ 出现「视觉上贴上去了却打不到」的错位（业主 2026-10-16 定）。
	out["range"] = float(out["range"]) * float(spec.get("attack_range_mult", 1.0))
	# 弹道只对**声明了倍率**的变种生效（当前只有远程怪）。没声明的变种不写这两个键，
	# 于是 Boss / 精英 / 普通远程怪的子弹逐字不变。
	if spec.has("projectile_speed_mult"):
		out["projectile_speed"] = DEFAULT_ENEMY_PROJECTILE_SPEED * float(spec["projectile_speed_mult"])
	if spec.has("projectile_range_mult"):
		out["projectile_range"] = DEFAULT_ENEMY_PROJECTILE_RANGE_M * float(spec["projectile_range_mult"])
	return out


func apply_profile(kind: String) -> void:
	var known := PROFILES.has(kind) or MonsterVariants.is_variant(kind)
	enemy_kind = kind if known else "melee_chaser"
	_active_profile = profile_for(enemy_kind)
	# 体型 = 原怪的**物种层级** × 变种的**体型倍率**，两段分开乘。
	# 这样物种层级仍只有一份真源：强化胖子跟随胖子的 1.0，
	# 将来胖子调成 1.1，强化胖子自动跟着变 1.65 而不是停在 1.5。
	var kind_scale := float(kind_table_lookup(BODY_SCALE_BY_KIND, _table_kind(), 1.0))
	var variant_base := MonsterVariants.base_of(enemy_kind)
	if not variant_base.is_empty():
		kind_scale *= MonsterVariants.multiplier(variant_base, "scale_mult")
	_kind_scale_multiplier = kind_scale
	var profile: Dictionary = _active_profile
	var hp_multiplier := BOSS_HP_MULTIPLIER if enemy_kind == "boss" else NORMAL_HP_MULTIPLIER
	max_hp = int(round(float(profile["hp"]) * hp_multiplier))
	current_hp = max_hp
	move_speed = float(profile["speed"]) * GLOBAL_MOVE_SPEED_MULTIPLIER
	contact_damage = int(profile["damage"])
	attack_range = float(profile["range"])
	attack_cooldown = float(profile["cooldown"])
	if collision_shape != null:
		var footprint := EnemyAvatar3D.get_footprint_profile(enemy_kind)
		var shape := CylinderShape3D.new()
		shape.radius = float(footprint.get("radius", 0.8))
		shape.height = float(footprint.get("height", 1.2))
		collision_shape.shape = shape
		collision_shape.position.y = shape.height * 0.5
	if avatar != null:
		avatar.configure(enemy_kind)
		avatar.set_ambush_revealed(enemy_kind != "ambusher" or _ambush_triggered)
	_apply_presentation_scale()
	_ensure_overhead_health_bar()
	_strafe_sign = -1.0 if get_instance_id() % 2 == 0 else 1.0
	_reset_egt_state()


## 复刻怪的第二批状态初始化。**换怪（`apply_profile`）时必须全部清干净** ——
## 池化复用会把上一任的"正在冲撞 / 还在绕链 / 已现形"带过来，
## 那种残留的症状是"新刷的怪一出生就在半空冲"。
func _reset_egt_state() -> void:
	_egt_attack_count = 0
	_pending_volleys.clear()
	_pending_eggs.clear()
	_suicide_rush_active = false
	_suicide_rush_timer = 0.0
	_rush_repositions_left = 0
	_orbit_active = false
	_orbit_angle = 0.0
	_orbit_timer = 0.0
	_orbit_emit_accumulator = 0.0
	_grab_state = "idle"
	_grab_timer = attack_cooldown
	_vanish_requested = false
	_wander_target = Vector3.ZERO
	_wander_timer = 0.0
	# 池化复借时这两项必须归零：上一任若是"被打断正在逃的枪歌者"，
	# 新刷出来会一出生就往反方向跑，读起来像出生点没摆好。
	_egt_interrupt_flee = 0.0
	_egt_hurt_window = 0.0
	_explode_pending = 0.0
	_grab_miss_count = 0
	var blink_spec: Variant = _active_profile.get("blink", null)
	_blink_timer = (
		float((blink_spec as Dictionary).get("interval", 0.0))
		if blink_spec is Dictionary
		else 0.0
	)
	var flee_spec: Variant = _active_profile.get("flee", null)
	_flee_timer = (
		float((flee_spec as Dictionary).get("vanish_after", 0.0))
		if flee_spec is Dictionary
		else 0.0
	)
	# 拟态怪**出生即伪装**：这是它的定义，不是运行中触发的状态。
	_disguised = _active_profile.has("disguise")


func configure_from_enemy_data(data: Dictionary) -> void:
	if monitor_combat != null:monitor_combat.cancel()
	monitor_combat = null
	# 重新配置等于换一只怪：上一任的动画受击盒必须一起走，
	# 否则残留形状会在这个位置凭空挡子弹。
	_clear_monitor_hit_volumes()
	enemy_data = data.duplicate(true)
	_death_explosion = (data.get("death_explosion", {}) as Dictionary).duplicate(true)
	if not bool(data.get("is_elite", false)):
		var configured_kind := str(data.get("enemy_type", enemy_kind))
		if configured_kind == "melee_chaser":
			var old_name := str(enemy_data.get("name", "小僵尸"))
			if old_name.ends_with("小菌猪"):
				enemy_data["name"] = old_name.trim_suffix("小菌猪") + "小僵尸"
			elif not enemy_data.has("name"):
				enemy_data["name"] = "小僵尸"
			enemy_data["emoji"] = "尸"
		elif configured_kind == "ranged_caster" and not enemy_data.has("name"):
			enemy_data["name"] = "保安僵尸"
			enemy_data["emoji"] = "尸"
		elif configured_kind == "fat_zombie03" and not enemy_data.has("name"):
			enemy_data["name"] = "胖子僵尸"
			enemy_data["emoji"] = "尸"
	elite_modifier_id = ""
	elite_id = str(data.get("elite_id", ""))
	elite_behavior_id = str(data.get("elite_behavior_id", ""))
	elite_level = int(data.get("elite_level", 0))
	elite_encounter_instance_id = str(data.get("encounter_instance_id", ""))
	elite_translation_id = str(data.get("elite_translation_id", ""))
	elite_stolen_modules.clear()
	for module in data.get("stolen_modules", []) as Array:
		if module is Dictionary:
			elite_stolen_modules.append((module as Dictionary).duplicate(true))
	_elite_growth_profile = (data.get("elite_growth_profile", {}) as Dictionary).duplicate(true)
	_elite_escape_active = false
	_elite_escape_elapsed = 0.0
	_elite_health_bar_profile = (data.get("elite_health_bar_profile", {}) as Dictionary).duplicate(true)
	_elite_attack_counter = 0
	_elite_behavior_trigger_count = 0
	_variant_scale_multiplier = 1.0
	apply_profile(str(data.get("enemy_type", enemy_kind)))
	var profile_hp := max_hp
	var profile_damage := contact_damage
	var source_hp_base := float(SOURCE_HP_BASE.get(_table_kind(), profile_hp))
	var source_max_hp := maxf(1.0, float(data.get("max_hp", data.get("hp", source_hp_base))))
	var source_current_hp := clampf(float(data.get("hp", source_max_hp)), 0.0, source_max_hp)
	_source_hp_scale = maxf(0.05, source_max_hp / maxf(1.0, source_hp_base))
	max_hp = maxi(1, int(round(float(profile_hp) * _source_hp_scale)))
	current_hp = clampi(int(round(float(max_hp) * source_current_hp / source_max_hp)), 1, max_hp)
	var source_damage_base := float(SOURCE_DAMAGE_BASE.get(_table_kind(), profile_damage))
	var source_damage := float(data.get("damage", source_damage_base))
	_source_damage_scale = (
		maxf(0.0, source_damage / source_damage_base)
		if source_damage_base > 0.0
		else 1.0
	)
	contact_damage = maxi(0, int(round(float(profile_damage) * _source_damage_scale)))
	# 2D px/s 按24 px/m适配到3D，再统一降到旧速度的70%。使用原始Profile
	# 作为缺省值，避免apply_profile已经降速后被重复乘0.7。
	var source_speed := float(data.get("speed", float(_active_profile["speed"]) * 24.0))
	move_speed = maxf(0.35, source_speed / 24.0 * GLOBAL_MOVE_SPEED_MULTIPLIER)
	if bool(data.get("is_elite", false)):
		elite_modifier_id = str(data.get("modifier_id_en", "Elite.Huge"))
		var modifier_data := data.get("modifier_data", {}) as Dictionary
		if elite_modifier_id == "Elite.Huge":
			var hp_mult := float(modifier_data.get("hp_mult", 2.0))
			max_hp = int(max_hp * hp_mult)
			current_hp = max_hp
			move_speed *= float(modifier_data.get("speed_mult", 0.8))
			_variant_scale_multiplier *= float(modifier_data.get("scale_mult", 1.5))
		else:
			_variant_scale_multiplier *= 1.16
		max_hp = maxi(1, int(round(float(max_hp) * float(data.get("elite_growth_hp_mult", 1.0)))))
		current_hp = max_hp
		contact_damage = maxi(1, int(round(float(contact_damage) * float(data.get("elite_growth_damage_mult", 1.0)))))
		if not elite_id.is_empty() and EliteRosterService != null:
			EliteRosterService.confirm_reservation(elite_id, elite_encounter_instance_id)
		if avatar != null:
			avatar.configure_elite_content(
				elite_id,
				str(data.get("presentation_asset_id", "")),
				str(data.get("presentation_scene", ""))
			)
	if enemy_kind == "boss":
		_variant_scale_multiplier *= float(data.get("boss_scale", 1.0))
		if avatar != null:
			avatar.configure_boss_content(str(data.get("boss_content_id", "")))
		if str(data.get("boss_content_id", "")) == MonitorBossCombat.ID:
			monitor_combat = MonitorBossCombat.new(self)
			attack_range = 6.0
			if avatar != null:avatar.sync_boss_presentation(monitor_combat.presentation_context())
	# —— 关卡级绝对数值覆盖（远征01 `monster_rules.stats.per_kind`）——
	# 覆盖的是**最终值**，直接赋值、不再参与上面的比例还原：写 350 就是 350 点血。
	# 未配置本段的关卡 data 里没有这三个键 ⇒ 一行都不执行，行为逐字不变。
	# 放在 boss 分支之后：连显示器Boss 的身份基线也一并盖掉。
	if data.has("override_max_hp"):
		max_hp = maxi(1, int(data["override_max_hp"]))
		current_hp = max_hp
	if data.has("override_damage"):
		contact_damage = maxi(0, int(data["override_damage"]))
	if data.has("override_speed"):
		move_speed = maxf(0.05, float(data["override_speed"]))
	_apply_presentation_scale()
	_ensure_overhead_health_bar()
	health_changed.emit(self, current_hp, max_hp)


## 取关卡级 AI 参数（`monster_ai`，由 `MonsterInjector._ai_overrides()` 随配置下发）。
## 键不存在或整段缺失 ⇒ 回退传入的全局常量，未配置关卡逐字不变。
func _ai_param(key: String, fallback: Variant) -> Variant:
	var ai: Variant = enemy_data.get("monster_ai", null)
	if not (ai is Dictionary):
		return fallback
	return (ai as Dictionary).get(key, fallback)


func apply_health_multiplier(multiplier: float) -> void:
	# 关卡修饰器必须保留当前生命比例；生成时满血的敌人经加成后仍应满血，
	# 同时立即将实际数值同步给头顶条，不能等到下一次受击才刷新。
	var health_ratio := clampf(float(current_hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	max_hp = maxi(1, int(round(float(max_hp) * maxf(0.01, multiplier))))
	current_hp = clampi(int(round(float(max_hp) * health_ratio)), 0, max_hp)
	health_changed.emit(self, current_hp, max_hp)


func _apply_presentation_scale() -> void:
	# 全体怪物以旧资产尺寸的70%作为新基础；物种、精英和Boss差异继续叠加，
	# 生命、速度、攻击距离与其他玩法数值不变。
	scale = (
		Vector3.ONE
		* DEFAULT_BASE_SIZE_MULTIPLIER
		* _kind_scale_multiplier
		* _variant_scale_multiplier
	)
	if _overhead_health_root != null:
		_position_overhead_health_bar()


func _ensure_overhead_health_bar() -> void:
	var wanted_size := (
		_elite_health_bar_profile.get("size", kind_table_lookup(HEALTH_BAR_SIZE_BY_KIND, _table_kind(), Vector2(1.65, 0.16)))
		as Vector2
	)
	# 只缩「普通小怪」：Boss 与精英各有独立契约（Boss 条是屏幕顶端条，
	# 精英条靠 2.05m 宽表达"这只不一样"，见 `verify_first_elite_deployment_flow`
	# 的 `overhead_health_bar_size.x >= 2.0`），把 0.80 乘到它们身上等于毁掉这个区分度。
	_overhead_health_bar_scale = (
		NORMAL_HEALTH_BAR_SCALE
		if enemy_kind != "boss" and _elite_health_bar_profile.is_empty()
		else 1.0
	)
	wanted_size *= _overhead_health_bar_scale
	if _overhead_health_root != null and is_instance_valid(_overhead_health_root):
		if _overhead_health_size.is_equal_approx(wanted_size):
			return
		# 场景节点先以默认种类 ready，随后才应用内容数据。种类发生变化时必须
		# 原子重建，避免小怪/Boss 保留默认怪的条宽或旧材质状态。
		if _overhead_health_root.get_parent() != null:
			_overhead_health_root.get_parent().remove_child(_overhead_health_root)
		_overhead_health_root.queue_free()
		_overhead_health_root = null
		_overhead_health_sprite = null
		_illumination_status_label = null
		_elite_name_label = null
		_overhead_health_image = null
		_overhead_health_texture = null
		_overhead_health_bar_initialized = false
		_overhead_delayed_health_ratio = 1.0
	_overhead_health_root = Node3D.new()
	_overhead_health_root.name = "OverheadHealthBar"
	_overhead_health_root.top_level = true
	add_child(_overhead_health_root)
	_overhead_health_size = wanted_size
	_position_overhead_health_bar()
	_overhead_health_image = Image.create(
		HEALTH_BAR_TEXTURE_SIZE.x, HEALTH_BAR_TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8
	)
	_overhead_health_texture = ImageTexture.create_from_image(_overhead_health_image)
	_overhead_health_sprite = Sprite3D.new()
	_overhead_health_sprite.name = "HealthBarSprite"
	_overhead_health_sprite.texture = _overhead_health_texture
	_overhead_health_sprite.pixel_size = HEALTH_BAR_PIXEL_SIZE
	_overhead_health_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead_health_sprite.no_depth_test = true
	_overhead_health_sprite.scale = Vector3(
		_overhead_health_size.x / (float(HEALTH_BAR_TEXTURE_SIZE.x) * HEALTH_BAR_PIXEL_SIZE),
		_overhead_health_size.y / (float(HEALTH_BAR_TEXTURE_SIZE.y) * HEALTH_BAR_PIXEL_SIZE),
		1.0
	)
	_overhead_health_root.add_child(_overhead_health_sprite)
	if not _elite_health_bar_profile.is_empty():
		_elite_name_label = Label3D.new()
		_elite_name_label.name = "EliteNameText"
		_elite_name_label.text = str(_elite_health_bar_profile.get("display_name", enemy_data.get("name", "唯一精英")))
		_elite_name_label.font_size = 40
		_elite_name_label.pixel_size = 0.005
		_elite_name_label.outline_size = 10
		_elite_name_label.outline_modulate = Color(0.02, 0.008, 0.03, 0.98)
		_elite_name_label.modulate = _elite_health_bar_profile.get("frame_color", Color(1.0, 0.62, 0.12)) as Color
		_elite_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_elite_name_label.no_depth_test = true
		_elite_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_elite_name_label.position = Vector3(0.0, _overhead_health_size.y * 0.92, 0.02)
		_overhead_health_root.add_child(_elite_name_label)
	_illumination_status_label = Label3D.new()
	_illumination_status_label.name = "IlluminationStatusText"
	_illumination_status_label.font_size = 34
	_illumination_status_label.pixel_size = 0.005
	_illumination_status_label.outline_size = 8
	_illumination_status_label.outline_modulate = Color(0.015, 0.02, 0.03, 0.96)
	_illumination_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_illumination_status_label.no_depth_test = true
	_illumination_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_illumination_status_label.position = Vector3(
		-_overhead_health_size.x * 0.38,
		-maxf(0.34, _overhead_health_size.y * 1.6),
		0.01
	)
	_overhead_health_root.add_child(_illumination_status_label)
	_on_self_health_changed(self, current_hp, max_hp)


func _position_overhead_health_bar() -> void:
	if _overhead_health_root == null:
		return
	var footprint := EnemyAvatar3D.get_footprint_profile(enemy_kind)
	var local_height := maxf(
		float(footprint.get("height", 1.3)),
		float(_elite_health_bar_profile.get("visual_height", 0.0))
	)
	if avatar != null and avatar.has_formal_normal():
		local_height = maxf(local_height, float(EnemyAvatar3D.FORMAL_NORMAL_HEIGHTS.get(enemy_kind, 0.0)))
	if monitor_combat != null:local_height = maxf(local_height,4.2)
	var world_height := local_height * maxf(scale.y, 0.01)
	_overhead_health_root.global_position = global_position + Vector3.UP * (world_height + 0.58)
	# top_level 已阻断父节点旋转；显式归零可清除热重载或旧实例留下的朝向。
	_overhead_health_root.global_rotation = Vector3.ZERO
	_overhead_health_root.scale = Vector3.ONE


func _on_self_health_changed(_enemy: Enemy3D, current: int, maximum: int) -> void:
	if _overhead_health_sprite == null or _overhead_health_image == null or _overhead_health_texture == null:
		return
	var next_ratio := clampf(float(current) / float(maxi(1, maximum)), 0.0, 1.0)
	_overhead_health_ratio = next_ratio
	# 初始化和治疗时不显示错误的白段；只有受伤时让白段暂留，随后在 _process 中追赶。
	if not _overhead_health_bar_initialized or next_ratio >= _overhead_delayed_health_ratio:
		_overhead_delayed_health_ratio = next_ratio
	_overhead_health_bar_initialized = true
	_redraw_overhead_health_bar()


func _redraw_overhead_health_bar() -> void:
	if _overhead_health_image == null or _overhead_health_texture == null:
		return
	# 单张 Sprite 纹理同时包含底框、白色延迟段和当前血量。没有独立平面的平移/缩放，
	# 所以在任意镜头角度下都不会跑出框外；Sprite3D 自身负责永久朝向摄像机。
	var frame_color := _elite_health_bar_profile.get("frame_color", HEALTH_BAR_FRAME_COLOR) as Color
	var empty_color := _elite_health_bar_profile.get("empty_color", HEALTH_BAR_EMPTY_COLOR) as Color
	var full_color := _elite_health_bar_profile.get("full_color", HEALTH_BAR_FULL_COLOR) as Color
	var low_color := _elite_health_bar_profile.get("low_color", HEALTH_BAR_LOW_COLOR) as Color
	_overhead_health_image.fill(frame_color)
	var inner_rect := Rect2i(
		HEALTH_BAR_BORDER_PX,
		HEALTH_BAR_BORDER_PX,
		HEALTH_BAR_TEXTURE_SIZE.x - HEALTH_BAR_BORDER_PX * 2,
		HEALTH_BAR_TEXTURE_SIZE.y - HEALTH_BAR_BORDER_PX * 2
	)
	_overhead_health_image.fill_rect(inner_rect, empty_color)
	var actual_width := int(round(float(inner_rect.size.x) * _overhead_health_ratio))
	var delayed_width := int(round(float(inner_rect.size.x) * _overhead_delayed_health_ratio))
	if delayed_width > actual_width:
		_overhead_health_image.fill_rect(
			Rect2i(
				inner_rect.position.x + actual_width,
				inner_rect.position.y,
				delayed_width - actual_width,
				inner_rect.size.y
			),
			HEALTH_BAR_DELAY_COLOR
		)
	if actual_width > 0:
		var fill_color := low_color.lerp(full_color, _overhead_health_ratio)
		_overhead_health_image.fill_rect(
			Rect2i(inner_rect.position, Vector2i(actual_width, inner_rect.size.y)), fill_color
		)
	_update_illumination_status_text()
	_overhead_health_texture.update(_overhead_health_image)


## 白段追赶真实血量。独立成函数（而不是内联在 `_process` 里）是为了让验收能
## **手动步进固定 delta** —— 光靠 `await process_frame` 采样，帧时间随机器上下浮动，
## 「白段确实在缩、且没有越过真实血量」这条断言会变成一条飘忽的用例。
func _tick_overhead_health_bar_delay(delta: float) -> void:
	if (
		enemy_kind == "boss"
		or not _overhead_health_bar_initialized
		or _overhead_delayed_health_ratio <= _overhead_health_ratio
	):
		return
	_overhead_delayed_health_ratio = move_toward(
		_overhead_delayed_health_ratio,
		_overhead_health_ratio,
		delta * HEALTH_BAR_DELAY_SPEED
	)
	_redraw_overhead_health_bar()


func _update_illumination_status_text() -> void:
	if _illumination_status_label == null:
		return
	var state := get_illumination_state()
	_illumination_status_label.text = _illumination_ui_text(state)
	_illumination_status_label.modulate = ILLUMINATION_UI_COLORS.get(state, Color.WHITE) as Color


func get_enemy_data() -> Dictionary:
	var result := enemy_data.duplicate(true)
	if result.is_empty():
		result = {"enemy_type": enemy_kind, "floor": 1, "loot_table": "loot_floor_1_2"}
	return result


func get_persistent_id() -> String:
	return str(enemy_data.get(
		"persistent_id",
		"%s:%s:%d" % [room_id, enemy_kind, int(enemy_data.get("spawn_index", get_index()))]
	))


func export_runtime_state() -> Dictionary:
	# 场景退出的同步存档可能发生在敌人已离开SceneTree之后；此时读取
	# global_position会让Godot报错。本项目关卡根没有运行时Transform，
	# 离树阶段使用本地position可保持同一恢复坐标。
	var saved_position := global_position if is_inside_tree() else position
	return {
		"persistent_id": get_persistent_id(),
		"enemy_kind": enemy_kind,
		"enemy_data": enemy_data.duplicate(true),
		"hp": current_hp,
		"max_hp": max_hp,
		"contact_damage": contact_damage,
		"position": [saved_position.x, saved_position.y, saved_position.z],
		"rotation_y": rotation.y,
		"ai_state": ai_state,
		"state_time": _state_time,
		"state_reason": _last_state_reason,
		"last_known_target_position": [
			_last_known_target_position.x,
			_last_known_target_position.y,
			_last_known_target_position.z,
		],
		"boss_phase": boss_phase,
		"ambush_triggered": _ambush_triggered,
		"elite_modifier_id": elite_modifier_id,
		"elite_escape_active": _elite_escape_active,
		"elite_escape_elapsed": _elite_escape_elapsed,
		"elite_escape_origin": [_elite_escape_origin.x, _elite_escape_origin.y, _elite_escape_origin.z],
		"attack_timer": _attack_timer,
		"slow_factor": _slow_factor,
		"slow_timer": _slow_timer,
		"boss_skill_bag": _boss_skill_bag.duplicate(),
		"boss_skill_index": _boss_skill_index,
		"monitor_poise_damage": monitor_combat.poise_damage if monitor_combat != null else 0.0,
		"monitor_electric_cooldown": monitor_combat.electric_cooldown if monitor_combat != null else 0.0,
		"monitor_activation_completed": monitor_combat.activation_completed if monitor_combat != null else true,
		"monitor_activation_started": monitor_combat.activation_started if monitor_combat != null else true,
		"monitor_activation_elapsed": monitor_combat.activation_elapsed if monitor_combat != null else 0.0,
	}


func import_runtime_state(state: Dictionary) -> bool:
	if str(state.get("persistent_id", "")) != get_persistent_id():
		return false
	max_hp = maxi(1, int(state.get("max_hp", max_hp)))
	current_hp = clampi(int(state.get("hp", current_hp)), 0, max_hp)
	contact_damage = maxi(0, int(state.get("contact_damage", contact_damage)))
	var saved_position: Variant = state.get("position", global_position)
	if saved_position is Vector3:
		global_position = saved_position as Vector3
	elif saved_position is Array and (saved_position as Array).size() >= 3:
		global_position = Vector3(
			float((saved_position as Array)[0]),
			float((saved_position as Array)[1]),
			float((saved_position as Array)[2])
		)
	rotation.y = float(state.get("rotation_y", rotation.y))
	var saved_known_position: Variant = state.get("last_known_target_position", [])
	if saved_known_position is Array and (saved_known_position as Array).size() >= 3:
		_last_known_target_position = Vector3(
			float((saved_known_position as Array)[0]),
			float((saved_known_position as Array)[1]),
			float((saved_known_position as Array)[2])
		)
	boss_phase = clampi(int(state.get("boss_phase", boss_phase)), 1, 3)
	_ambush_triggered = bool(state.get("ambush_triggered", _ambush_triggered))
	_elite_escape_active = bool(state.get("elite_escape_active", false))
	_elite_escape_elapsed = maxf(0.0, float(state.get("elite_escape_elapsed", 0.0)))
	var saved_escape_origin: Variant = state.get("elite_escape_origin", [])
	if saved_escape_origin is Array and (saved_escape_origin as Array).size() >= 3:
		_elite_escape_origin = Vector3(
			float((saved_escape_origin as Array)[0]),
			float((saved_escape_origin as Array)[1]),
			float((saved_escape_origin as Array)[2])
		)
	_attack_timer = maxf(0.0, float(state.get("attack_timer", _attack_timer)))
	_slow_factor = clampf(float(state.get("slow_factor", _slow_factor)), 0.25, 1.0)
	_slow_timer = maxf(0.0, float(state.get("slow_timer", _slow_timer)))
	var saved_bag: Variant = state.get("boss_skill_bag", [])
	if saved_bag is Array:
		_boss_skill_bag.clear()
		for value in saved_bag as Array:
			_boss_skill_bag.append(str(value))
	_boss_skill_index = clampi(int(state.get("boss_skill_index", 0)), 0, _boss_skill_bag.size())
	if monitor_combat != null:
		monitor_combat.cancel()
		monitor_combat.poise_damage = maxf(0.0,float(state.get("monitor_poise_damage",0.0)))
		monitor_combat.electric_cooldown = maxf(0.0,float(state.get("monitor_electric_cooldown",0.0)))
		monitor_combat.activation_completed = bool(state.get("monitor_activation_completed",true))
		monitor_combat.activation_elapsed = clampf(float(state.get("monitor_activation_elapsed",0.0)),0.0,MonitorBossCombat.ACTIVATION_DURATION)
		monitor_combat.activation_started = bool(state.get("monitor_activation_started",monitor_combat.activation_completed or monitor_combat.activation_elapsed > 0.0))
	var saved_ai_state := str(state.get("ai_state", "idle"))
	# 生效帧不能跨卸载边界继续伤害；重新进房时退回可读的警戒状态。
	if saved_ai_state in ["telegraph", "attack", "recovery", "stagger"]:
		saved_ai_state = "alert"
	if saved_ai_state in VALID_STATES and saved_ai_state != "dead":
		transition_to(saved_ai_state, "runtime_restore")
		_state_time = maxf(0.0, float(state.get("state_time", 0.0)))
	_last_state_reason = str(state.get("state_reason", _last_state_reason))
	if avatar != null:
		avatar.set_ambush_revealed(enemy_kind != "ambusher" or _ambush_triggered)
	health_changed.emit(self, current_hp, max_hp)
	return true


func set_runtime_active(active: bool, presentation_ready_when_inactive := false) -> void:
	if ai_state == "dead":
		# 房间AI休眠不得暂停倒地或回收；尸体显隐仍由PlayerVision3D管理。
		_runtime_ai_active = false
		process_mode = Node.PROCESS_MODE_INHERIT
		set_physics_process(false)
		set_process(true)
		return
	# 已开启门后的邻房会预先显示敌人，但在玩家正式进入前暂停 AI。
	# process_mode 不能在可见邻房设为 DISABLED：PlayerVision3D 会把它解释为
	# 未加载目标并强制隐藏。改为单独暂停物理 AI，让视野系统仍可正常判定显隐。
	_runtime_ai_active = active
	# 邻房目标先交给 PlayerVision3D 做距离/遮挡判定，避免刚生成的一帧穿墙闪现。
	visible = active
	process_mode = (
		Node.PROCESS_MODE_INHERIT
		if active or presentation_ready_when_inactive
		else Node.PROCESS_MODE_DISABLED
	)
	set_physics_process(active)
	if active and ai_state == "dormant":
		transition_to("idle")
	elif not active and ai_state not in ["dead", "dormant"]:
		transition_to("dormant")


func is_runtime_ai_active() -> bool:
	return _runtime_ai_active


## 该敌人此刻是否在世界上"被藏起来"（潜行用的伏击怪尚未钻出地面）。
## 屏幕外指示箭头据此不给它画箭头 —— 否则玩家还没走到跟前，箭头就把伏击点报出来了。
## 与 `_ambush_triggered` 是同一事实，只是对外给一个只读名字。
func is_concealed_in_world() -> bool:
	return enemy_kind == "ambusher" and not _ambush_triggered


func _process(delta: float) -> void:
	if ai_state == "dead":
		# 死亡进度不依赖已经退出战斗的物理AI。
		_state_time += delta
	if avatar != null:
		if monitor_combat != null:
			avatar.sync_boss_presentation(monitor_combat.presentation_context())
			# 受击盒必须与**本帧渲染出来的**姿态一致：紧跟表现层同步、用同一份骨姿态。
			# 反过来说，盒子再也不会「停在上一帧该在的地方」而和画面错开。
			if _ensure_monitor_hit_volumes():
				_sync_monitor_hit_volumes()
		else:
			avatar.sync_presentation(ai_state, _state_time, Vector2(get_real_velocity().x, get_real_velocity().z).length(), _telegraph_duration(), _recovery_duration())
	_tick_overhead_health_bar_delay(delta)
	# 已加载但尚未进入近距离 AI 圈的怪物仍需低成本监听真实受光刺激。
	# 否则其 physics_process 被暂停后，探照灯永远不可能将它唤醒。
	if _runtime_ai_active or ai_state == "dead" or illumination_sensor == null:
		return
	illumination_sensor.tick(delta)


## 显示器 Boss：按表现层给出的骨局部盒子建一组**跟骨走**的受击形状。
## 形状挂在独立代理体上（`collision_layer` 与本体同层 ⇒ 玩家子弹打得中；
## `collision_mask = 0` ⇒ 谁也不挡），因此子弹拿到的 `collider` 是代理，
## 伤害由 `EnemyHitVolume3D` 转交本体。只在表现层就绪后建一次；
## 非本 Boss（`monitor_combat == null`）永不建。
func _ensure_monitor_hit_volumes() -> bool:
	if monitor_combat == null or avatar == null:
		return false
	if _monitor_hit_body != null and is_instance_valid(_monitor_hit_body):
		return true
	var presentation := avatar.get_animated_boss_root() as MonitorBossPresentation
	if presentation == null or presentation.skeleton == null:
		return false
	var spec := MonitorBossPresentation.get_hit_volume_spec()
	if spec.is_empty():
		return false
	var body := EnemyHitVolume3D.new()
	body.name = "MonitorHitVolumes"
	body.collision_layer = MONITOR_BULLET_LAYER
	body.collision_mask = 0
	body.bind(self)
	add_child(body)
	# 圆柱退出子弹层：它半径 2.016 m、比可见屏幕宽 1 m 以上，留着会把子弹拦在屏幕前 1 m 处。
	# 自身移动只看 `collision_mask`，所以这一步不改变走位、阻挡或任何别的口径。
	collision_layer = 0
	var shapes: Array[CollisionShape3D] = []
	for entry in spec:
		var box := BoxShape3D.new()
		box.size = entry["size"] as Vector3
		var shape := CollisionShape3D.new()
		shape.name = "Volume_%s" % str(entry["bone"]).replace(".", "_")
		shape.shape = box
		body.add_child(shape)
		shapes.append(shape)
	_monitor_hit_body = body
	_monitor_hit_shapes = shapes
	_monitor_hit_presentation = presentation
	_sync_monitor_hit_volumes()
	return true


## 把受击形状搬到本帧骨姿态上。必须在 `sync_boss_presentation` 之后调用 ——
## 否则盒子会停在上一帧的位置，等于把「隔空命中」换个方向重演一遍。
## 顺带把代理体的碰撞层与本体对齐：本体死掉变 layer 0 时，盒子必须一起失效，
## 否则会留下一组「打得到、但怪已经死了」的幽灵体积。
func _sync_monitor_hit_volumes() -> void:
	if _monitor_hit_shapes.is_empty() or _monitor_hit_presentation == null:
		return
	if not is_instance_valid(_monitor_hit_presentation):
		return
	if _monitor_hit_body != null and is_instance_valid(_monitor_hit_body):
		# 死亡后受击盒必须一起失效，否则会留下一组「打得到、但怪已经死了」的幽灵体积。
		# 不能读 `collision_layer` —— 它已被置 0 让出子弹层（见 `_ensure_monitor_hit_volumes`），
		# 读它会让受击盒一建出来就失效。看状态而不是看层。
		_monitor_hit_body.collision_layer = MONITOR_BULLET_LAYER if ai_state != "dead" else 0
	var transforms := _monitor_hit_presentation.hit_volume_transforms()
	var count := mini(transforms.size(), _monitor_hit_shapes.size())
	for index in range(count):
		_monitor_hit_shapes[index].global_transform = transforms[index]


## 供验收读取：本怪当前的动画受击盒容器（null = 非本 Boss 或表现层未就绪）。
func get_monitor_hit_volume_body() -> EnemyHitVolume3D:
	return _monitor_hit_body


## 供验收读取：本怪当前的动画受击形状。
func get_monitor_hit_volumes() -> Array[CollisionShape3D]:
	return _monitor_hit_shapes


func _clear_monitor_hit_volumes() -> void:
	if _monitor_hit_body != null and is_instance_valid(_monitor_hit_body):
		_monitor_hit_body.queue_free()
	_monitor_hit_body = null
	_monitor_hit_shapes.clear()
	_monitor_hit_presentation = null


func activate_from_player_proximity(player_node: Node3D, activation_range: float) -> bool:
	if _runtime_ai_active or player_node == null or not is_instance_valid(player_node):
		return false
	var offset := player_node.global_position - global_position
	# 不跨楼板预激活；同层采用大于一个屏幕的平面距离。
	if absf(offset.y) > 4.5 or Vector2(offset.x, offset.z).length() > activation_range:
		return false
	set_runtime_active(true)
	return true


func activate_from_stimulus(stimulus_position: Vector3, _stimulus_kind := "interaction") -> bool:
	if ai_state == "dead":
		return false
	_last_known_target_position = stimulus_position
	if not _runtime_ai_active:
		set_runtime_active(true)
	return true


func _physics_process(delta: float) -> void:
	_tick_fate_statuses(delta)
	_sync_fate_visuals()
	if _fate_freeze_remaining > 0.0 and ai_state != "dead":
		_fate_freeze_remaining = maxf(0.0, _fate_freeze_remaining - delta)
		velocity = Vector3.ZERO
		return
	if illumination_sensor != null:
		illumination_sensor.tick(delta)
	_tick_illumination_effects(delta)
	_position_overhead_health_bar()
	if not _home_initialized:
		_home_position = global_position
		_home_initialized = true
	if (
		ai_state != "dead"
		and not _elite_escape_active
		and global_position.y < _home_position.y - FALL_DEATH_DROP_M
	):
		_die_from_fall_out()
		return
	_state_time += delta
	_absorb_cooldown = maxf(0.0, _absorb_cooldown - delta)
	_ambush_reburrow_cooldown = maxf(0.0, _ambush_reburrow_cooldown - delta)
	_attack_timer = maxf(0.0, _attack_timer - delta * get_attack_frequency_multiplier())
	_slow_timer = maxf(0.0, _slow_timer - delta)
	# 远征03 复刻怪：连发队列 + 加速 buff + 冲撞超时，都挂在既有递减区，
	# 不另开 `_process`（那会多一份每帧开销与一份时序真源）。
	_tick_pending_volleys(delta)
	# 第二批的行为状态机（瞬移/逃跑/伪装/游荡/抓取/绕圈/冲撞重定位/蛋）。
	# 与连发队列同一个时序真源，不另开 `_process`。
	_tick_egt_state(delta)
	_haste_timer = maxf(0.0, _haste_timer - delta)
	if _haste_timer <= 0.0:
		_haste_factor = 1.0
	if _suicide_rush_active:
		_suicide_rush_timer = maxf(0.0, _suicide_rush_timer - delta)
		if _suicide_rush_timer <= 0.0 and ai_state != "dead":
			_die()
	_external_timer = maxf(0.0, _external_timer - delta)
	if _external_timer <= 0.0:
		_external_velocity = Vector3.ZERO
	_tick_damage_over_time(delta)
	if _slow_timer <= 0.0:
		_slow_factor = 1.0
	if ai_state == "dead":
		velocity = Vector3.ZERO
		return
	if _melee_stagger_remaining > 0.0:
		_melee_stagger_remaining = maxf(0.0, _melee_stagger_remaining - delta)
		_steer_planar(_external_velocity + _last_hit_direction * _hit_knockback, 1.0)
		_commit_motion(delta)
		return
	if _elite_escape_active:
		_tick_elite_escape(delta)
		return
	if bool(enemy_data.get("narrative_stationary", false)):
		_target = null
		if MonsterAIManager != null:
			MonsterAIManager.update_enemy_spatial(self)
		if ai_state != "idle":
			transition_to("idle")
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return
	if monitor_combat != null:
		var activation_was_completed := monitor_combat.activation_completed
		var activation_blocks_ai := monitor_combat.tick_activation(delta)
		if not activation_was_completed and monitor_combat.activation_completed:
			boss_activation_completed.emit(self)
		if activation_blocks_ai:
			return
	if MonsterAIManager != null:
		MonsterAIManager.update_enemy_spatial(self)
	_ai_decision = MonsterAIManager.evaluate_enemy(self) if MonsterAIManager != null else {}
	_apply_ai_decision(_ai_decision)
	# 脱战静默计时 ⇒ 启动过程重新武装。
	# 放在 `_apply_ai_decision` 之后，读的是本帧刚解析出来的目标，不留一帧错位。
	# 语义：连续无目标满 `REARM_AFTER_SECONDS` 才算「真的脱战了」，
	# 否则玩家来回探头会让怪物反复吼叫 —— 那是噪音，不是表现。
	if _target == null or not is_instance_valid(_target):
		_disengage_elapsed += delta
		if _disengage_elapsed >= MonsterStartupProfile.REARM_AFTER_SECONDS:
			_startup_armed = true
	else:
		_disengage_elapsed = 0.0
	if monitor_combat != null and monitor_combat.tick(delta):return
	if enemy_kind == "ambusher" and _ambush_triggered:
		var target_distance := global_position.distance_to(_target.global_position) if _target != null and is_instance_valid(_target) else INF
		if not bool(_ai_decision.get("target_visible", false)) and target_distance > 5.0:
			_ambush_unseen_time += delta
		else:
			_ambush_unseen_time = 0.0
		if (
			_ambush_reburrow_cooldown <= 0.0
			and _ambush_unseen_time >= 2.0
			and get_illumination_state() == EnemyIllumination3D.STATE_DARKNESS
			and ai_state not in ["telegraph", "attack", "recovery", "stagger"]
		):
			_ambush_triggered = false
			_ambush_unseen_time = 0.0
			_target = null
			avatar.set_ambush_revealed(false)
			transition_to("idle", "dark_reburrow_ready")
	if enemy_kind == "ambusher" and not _ambush_triggered:
		_brake_planar(delta * 16.0)
		avatar.set_ambush_revealed(false)
		var exposed_to_light := (
			illumination_sensor != null
			and illumination_sensor.illumination_state != EnemyIllumination3D.STATE_DARKNESS
		)
		var proximity_player := _get_player_in_proximity(4.4)
		if exposed_to_light or current_hp < max_hp or proximity_player != null:
			_ambush_triggered = true
			_ambush_reburrow_cooldown = 6.0
			avatar.set_ambush_revealed(true)
			if _target == null and proximity_player != null:
				_target = proximity_player
			transition_to("telegraph")
		elif _target == null:
			_commit_motion(delta)
			return
	if _target == null:
		if enemy_kind == "fat_zombie03" and ai_state == "stagger":
			_steer_planar(_last_hit_direction * _hit_knockback, 1.0)
			_commit_motion(delta)
			if _state_time >= float(_active_profile["stagger"]):
				transition_to("idle", "stagger_no_target_finished")
			return
		if enemy_kind == "fat_zombie03" and ai_state in ["telegraph", "attack", "recovery"]:
			if MonsterAIManager != null:
				MonsterAIManager.release_attack_token(self)
			transition_to("search", "clap_target_lost")
		var awareness := str(_ai_decision.get("awareness", "unaware"))
		if awareness in ["room_light_search", "seek_darkness", "lost_contact", "proximity_contact", "sound_contact", "hunt_contact"]:
			_last_known_target_position = _ai_decision.get("stimulus_position", global_position) as Vector3
			if awareness in ["proximity_contact", "sound_contact"] and ai_state not in ["alert", "search", "telegraph", "attack", "stagger"]:
				transition_to("alert")
			if ai_state == "alert" and _state_time <= 0.42:
				_brake_planar(delta * 12.0)
				_commit_motion(delta)
				var face_stimulus := _last_known_target_position - global_position
				face_stimulus.y = 0.0
				if face_stimulus.length_squared() > 0.01:
					rotation.y = lerp_angle(rotation.y, atan2(-face_stimulus.x, -face_stimulus.z), minf(1.0, delta * 9.0))
				return
			if ai_state not in ["search", "telegraph", "attack", "stagger"]:
				transition_to("search")
			_tick_search(delta)
			return
		if ai_state == "return":
			_tick_return(delta)
			return
		if ai_state == "idle" and _state_time > 2.2:
			transition_to("patrol")
		if ai_state == "patrol":
			_tick_patrol(delta)
		else:
			transition_to("idle")
			_brake_planar(delta * 10.0)
			_commit_motion(delta)
		return
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var target_visible := bool(_ai_decision.get("target_visible", false))
	var awareness := str(_ai_decision.get("awareness", ""))
	# 手电命中和受击仇恨都是有明确玩家来源的强刺激。它们不依赖当前视锥，
	# 否则怪物转身或远距离中弹后的下一帧就会丢失目标，只停留在原地搜索。
	# `hunt_contact` 是**事件指令**（封锁房、设施触发）下发的"我就是知道你在哪"：
	# 与手电命中、受击仇恨同档，不依赖视锥与视线，否则怪一转身就丢目标。
	var stimulus_tracking := awareness in ["flashlight_contact", "damage_contact", "hunt_contact"]
	if target_visible or stimulus_tracking:
		_last_known_target_position = _ai_decision.get("target_position", _target.global_position) as Vector3
		_lost_sight_time = 0.0
	else:
		_lost_sight_time += delta
		if ai_state == "idle" and _state_time > 2.2:
			transition_to("patrol")
	var engage_distance := float(_ai_param("engage_distance_m", 13.5))
	if (distance < engage_distance or stimulus_tracking) and ai_state in ["idle", "patrol", "search"] and (target_visible or stimulus_tracking):
		transition_to("alert")
		# 确认合法目标 ⇒ 走启动过程（业主 2026-10-14）。Boss、未重新武装的重复遭遇
		# 与退化朝向由 `_begin_monster_startup` 内部判掉；那里返回 false 时，
		# 本状态就退回原来的 `alert_duration` 口径，行为与接线前逐字一致。
		_begin_monster_startup(to_target)
	var alert_duration := float(_ai_param(
		"alert_duration_sec", float(_active_profile.get("alert", 0.28))
	))
	if ai_state == "alert" and _tick_alert_state(to_target, delta, alert_duration):
		# 启动过程独占本帧：它自己处理制动、朝向与 move_and_slide。
		# 直接返回是**不抢跑**的关键 —— 继续往下跑行动 match 会把它推进 chase，
		# 玩家就会看到「怪物直接冲过来」，正是 2026-10-14 要修的现象。
		return
	var lost_sight_limit := float(_ai_param("lost_sight_sec", 1.15))
	match ai_state:
		"chase":
			if _lost_sight_time > lost_sight_limit:
				transition_to("search")
			else:
				_tick_chase(to_target, distance, delta)
		"search":
			_tick_search(delta)
		"patrol":
			_tick_patrol(delta)
		"telegraph":
			_brake_planar(delta * 18.0)
			_push_planar(_external_velocity)
			_commit_motion(delta)
			if _state_time >= _telegraph_duration():
				transition_to("attack")
		"attack":
			_perform_attack(to_target, distance)
			transition_to("recovery")
		"recovery":
			_brake_planar(delta * 18.0)
			_push_planar(_external_velocity)
			_commit_motion(delta)
			if _state_time >= _recovery_duration():
				if MonsterAIManager != null:
					MonsterAIManager.release_attack_token(self)
				transition_to("chase")
		"stagger":
			_steer_planar(_last_hit_direction * _hit_knockback, 1.0)
			_commit_motion(delta)
			if _state_time > float(_active_profile.get("stagger", 0.16)):
				transition_to("chase")
	var clap_locked := enemy_kind == "fat_zombie03" and (ai_state in ["attack", "recovery"] or (ai_state == "telegraph" and _state_time >= 1.0))
	if monitor_combat != null:
		monitor_combat.face_target(to_target,delta)
	elif to_target.length_squared() > 0.01 and not clap_locked:
		rotation.y = lerp_angle(rotation.y, atan2(-to_target.x, -to_target.z), minf(1.0, delta * 8.0))


func _tick_chase(to_target: Vector3, distance: float, delta: float) -> void:
	var monitor_facing_ready := monitor_combat == null or (not monitor_combat.turning and (-global_basis.z).normalized().dot(to_target.normalized()) >= 0.97)
	if distance <= attack_range and _attack_timer <= 0.0 and monitor_facing_ready:
		var channel := "ranged" if _is_ranged_style() else "melee"
		if MonsterAIManager == null or MonsterAIManager.request_attack_token(self, _target, channel):
			_last_attack_result = "token_granted"
			transition_to("telegraph")
			return
		_last_attack_result = "token_wait"
	var effective_move_speed := get_effective_move_speed()
	var desired_direction := _navigation_direction(_target.global_position, to_target)
	var desired := desired_direction * effective_move_speed * _slow_factor
	# —— 复刻怪里"不朝玩家推进"的三种（逃跑 / 游荡 / 抓取）——
	# 它们的位移**完全由 `_tick_egt_state()` 写在 `_external_velocity` 上**。
	# 不在这里掐掉的话会出现一半朝玩家、一半逃跑的折中位移 ——
	# 表现上是"这只怪在发抖"，而数值上它既追不上也跑不掉。
	if _is_egt_kind():
		var style := _egt_attack_style()
		if (
			style == "flee" or style == "grab" or _active_profile.has("wander")
			or bool(_active_profile.get("immobile", false))
		):
			_steer_planar(Vector3.ZERO, minf(1.0, delta * 5.5))
			_push_planar(_external_velocity)
			_commit_motion(delta)
			return
	if _is_ranged_style() and monitor_combat == null:
		var radial := to_target.normalized()
		var tangent := Vector3(-radial.z, 0, radial.x) * _strafe_sign
		var ideal_distance := attack_range * (0.78 if enemy_kind != "summoner" else 0.86)
		var radial_weight := clampf((distance - ideal_distance) / maxf(1.0, ideal_distance), -1.0, 1.0)
		desired = (tangent * 0.78 + radial * radial_weight).normalized() * effective_move_speed * _slow_factor
		if distance < attack_range * 0.52:
			desired = (-radial * 0.82 + tangent * 0.35).normalized() * effective_move_speed * _slow_factor
	desired = _apply_local_avoidance(desired, to_target)
	_steer_planar(desired, minf(1.0, delta * 5.5))
	_push_planar(_external_velocity)
	_commit_motion(delta)
	_track_stuck_recovery(delta, desired)


func _tick_search(delta: float) -> void:
	var offset := _last_known_target_position - global_position
	offset.y = 0.0
	if offset.length() > 0.65:
		var search_direction := _navigation_direction(_last_known_target_position, offset)
		var search_velocity := _apply_local_avoidance(
			search_direction * get_effective_move_speed() * 0.72,
			offset
		)
		_steer_planar(search_velocity, minf(1.0, delta * 4.0))
		_commit_motion(delta)
		_track_stuck_recovery(delta, search_velocity)
	else:
		_brake_planar(delta * 8.0)
		_commit_motion(delta)
	if _state_time > 2.4:
		_target = null
		transition_to("return")


func _tick_return(delta: float) -> void:
	var offset := _home_position - global_position
	offset.y = 0.0
	if offset.length() <= 0.7:
		_stop_planar()
		transition_to("patrol")
		return
	var direction := _navigation_direction(_home_position, offset)
	var desired := _apply_local_avoidance(
		direction * get_effective_move_speed() * 0.64,
		offset
	)
	_steer_planar(desired, minf(1.0, delta * 4.0))
	_commit_motion(delta)
	_track_stuck_recovery(delta, desired)


func _tick_patrol(delta: float) -> void:
	if _patrol_target == Vector3.ZERO or global_position.distance_to(_patrol_target) < 0.55:
		# 只由稳定内容数据和步号决定；不读取墙钟，固定种子下可复现。
		var stable_seed := room_id.hash() ^ enemy_kind.hash() ^ int(enemy_data.get("floor", 0))
		var angle := fmod(float(absi(stable_seed) % 997) * 0.017 + float(_patrol_step) * 2.399963, TAU)
		_patrol_step += 1
		_patrol_target = _home_position + Vector3(cos(angle), 0, sin(angle)) * 1.7
	var offset := _patrol_target - global_position
	offset.y = 0.0
	_steer_planar(offset.normalized() * get_effective_move_speed() * float(_active_profile.get("patrol_multiplier", 0.32)), minf(1.0, delta * 3.2))
	_commit_motion(delta)


func _has_line_of_sight(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.72, 0),
		target.global_position + Vector3(0, 0.72, 0),
		1,
		[get_rid()]
	)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.get("collider") as Node
	return collider == target or (collider != null and target.is_ancestor_of(collider))


func _has_player_in_proximity(radius: float) -> bool:
	return _get_player_in_proximity(radius) != null


func _get_player_in_proximity(radius: float) -> Node3D:
	var radius_squared := radius * radius
	for candidate in get_tree().get_nodes_in_group("player_3d"):
		if candidate is Node3D and global_position.distance_squared_to((candidate as Node3D).global_position) <= radius_squared:
			return candidate as Node3D
	return null


## 这只怪用「远程/施法」手位还是「近战」手位？
##
## 原来的写法是内联 `enemy_kind in ["ranged_caster","summoner","boss"]`，散在两处（攻击令牌
## 通道 + 走位方式）。远征03 复刻怪要加进来，如果继续内联就会变成两份要同步维护的白名单 ——
## 抽成函数，**两份判定共用同一份真源**。
func _is_ranged_style() -> bool:
	if enemy_kind in ["ranged_caster", "summoner", "boss"]:
		return true
	# 复刻怪的"手位"由**攻击骨架**推出，不再逐个列举 —— 第二批加了 21 只，
	# 继续用白名单就要维护 33 行，且漏一只的后果是"远程怪走上前来贴脸"（很难看出来）。
	# 判定依据：会往远处投弹 / 施法的走远程手位；扑、炸、撞、逃走近战手位。
	if _is_egt_kind():
		return _egt_attack_style() in ["volley", "support", "grab", "orbit", "chance"]
	return false


## 本怪是不是远征03 复刻怪。**用前缀判**：这一族由设计文档整批引入，
## 逐只列举只会制造"加了怪忘了改这里"的缺口。
func _is_egt_kind() -> bool:
	return _table_kind().begins_with("egt_")


## 攻击骨架的唯一真源。老怪没写 `attack_style`，按它们已有的专属键反推，
## 于是**表里写什么、运行时就走什么**，不会出现两套判定。
func _egt_attack_style() -> String:
	var declared := str(_active_profile.get("attack_style", ""))
	if not declared.is_empty():
		return declared
	if _active_profile.has("grab"):
		return "grab"
	if _active_profile.has("orbit"):
		return "orbit"
	if _active_profile.has("support_buff"):
		return "support"
	if _active_profile.has("suicide_rush"):
		return "rush"
	if _active_profile.has("flee"):
		return "flee"
	if _active_profile.has("volley"):
		return "volley"
	if _table_kind() in ["egt_pinhead", "egt_nitra"]:
		return "explode"
	return "contact"


func _perform_attack(to_target: Vector3, distance: float) -> void:
	# 自动化与技能预演允许传入显式方向而不绑定目标；实际近战命中仍要求
	# 当前目标有效，避免悬空引用造成重复结算。
	_attack_timer = attack_cooldown
	_last_attack_result = "committed"
	# —— 远征03 复刻怪：**一次分派，永不逐只加分支** ——
	# 第二批把复刻怪扩到 33 只。如果继续在 match 里逐只列举，这里会变成 33 行长名单，
	# 而且每加一只都要改一次"攻击代码"——那正是 §T2「新增怪种只加一行数据」要避免的。
	# 现在由 `_egt_attack_style()` 读表分派，老怪走下面那条一排未改的 match。
	if _is_egt_kind():
		_perform_egt_attack(to_target, distance)
		_apply_unique_elite_attack_behavior(to_target)
		if elite_modifier_id == "Elite.WeaponParasite" and _target != null and _target.has_method("apply_silence"):
			_target.call("apply_silence", 1.8)
		return
	match _table_kind():
		"fat_zombie03":
			_last_attack_result = "miss"
			if distance <= attack_range and (-global_basis.z).dot(to_target.normalized()) >= 0.5 and is_instance_valid(_target) and _has_line_of_sight(_target) and _target.has_method("take_damage"):
				if _target.has_method("notify_attacked_by"):
					_target.call("notify_attacked_by", self)
				_target.call("take_damage", contact_damage, false, to_target.normalized())
				_last_attack_result = "hit"
		"ranged_caster":
			_fire_projectile_volley(to_target, contact_damage, Color(0.20, 0.82, 0.92), 3, 0.18)
		"summoner":
			_summon_count += 1
			summon_requested.emit(self, 2 if _summon_count % 2 == 1 else 1)
			_heal_nearby_allies()
		"exploder":
			_explode()
		"boss":
			var boss_skill := _next_boss_skill()
			_perform_boss_skill(boss_skill, to_target)
		"melee_chaser":
			_external_velocity = to_target.normalized() * 7.2
			_external_timer = 0.16
			if distance <= attack_range + 0.65 and is_instance_valid(_target) and _target.has_method("take_damage"):
				if _target.has_method("notify_attacked_by"):
					_target.call("notify_attacked_by", self)
				_target.call("take_damage", contact_damage, false, to_target.normalized())
		"ambusher":
			_external_velocity = to_target.normalized() * 9.4
			_external_timer = 0.28
			if distance <= attack_range + 1.0 and is_instance_valid(_target) and _target.has_method("take_damage"):
				if _target.has_method("notify_attacked_by"):
					_target.call("notify_attacked_by", self)
				_target.call("take_damage", contact_damage, false, to_target.normalized())
		# —— 远征03 复刻怪的五个旧分支已收进上面的 `_perform_egt_attack()`。
		# 留这一段空档是为了让 diff 能读出「哪些行被搬走了」，不是还被引用。
		_:
			if distance <= attack_range + 0.65 and is_instance_valid(_target) and _target.has_method("take_damage"):
				if _target.has_method("notify_attacked_by"):
					_target.call("notify_attacked_by", self)
				_target.call("take_damage", contact_damage, false, to_target.normalized())
	_apply_unique_elite_attack_behavior(to_target)
	if elite_modifier_id == "Elite.WeaponParasite" and _target != null and _target.has_method("apply_silence"):
		_target.call("apply_silence", 1.8)


## 发一颗子弹。
##
## `behavior` 是**子弹自身的附加行为**（追踪 / 反弹 / 寿命），`speed_override` 覆盖弹速，
## `origin` 覆盖出生点（Gigi 的蛋要在蛋的位置炸开，不能从怪身上炸）。
## 后三个都是可选的：老调用点一行不用改，行为逐字不变。
func _fire_projectile(
	to_target: Vector3,
	amount: int,
	color: Color,
	explosive := false,
	behavior: Dictionary = {},
	speed_override: float = 0.0,
	origin: Variant = null
) -> void:
	if get_tree().current_scene == null:
		return
	var base_speed := float(_active_profile.get("projectile_speed", DEFAULT_ENEMY_PROJECTILE_SPEED))
	if speed_override > 0.0:
		base_speed = speed_override
	var config := {
		"direction": to_target.normalized(),
		"speed": base_speed,
		"range": float(_active_profile.get("projectile_range", 0.0)),
		"damage": amount,
		"hostile": true, "critical": false, "tags": ["explosive"] if explosive else [],
		"color": color, "shooter": self,
	}
	if not behavior.is_empty():
		config["behavior"] = behavior.duplicate(true)
	var world_position := (
		global_position + Vector3(0, 0.92, 0) + to_target.normalized() * 0.72
	)
	if origin is Vector3:
		world_position = origin as Vector3
	var pools := get_tree().get_nodes_in_group("projectile_pool_3d")
	if not pools.is_empty() and pools[0] is ProjectilePool3D:
		(pools[0] as ProjectilePool3D).acquire(config, world_position)
	else:
		var projectile := PROJECTILE_SCRIPT.new() as Projectile3D
		projectile.configure(config)
		get_tree().current_scene.add_child(projectile)
		projectile.global_position = world_position


func _fire_projectile_volley(
	to_target: Vector3,
	amount: int,
	color: Color,
	count: int,
	spread_radians: float,
	explosive := false
) -> void:
	var shot_count := maxi(1, count)
	for index in range(shot_count):
		var ratio := 0.5 if shot_count == 1 else float(index) / float(shot_count - 1)
		var angle := lerpf(-spread_radians, spread_radians, ratio)
		_fire_projectile(to_target.rotated(Vector3.UP, angle), amount, color, explosive)


func _heal_nearby_allies() -> void:
	var candidates: Array[Node3D] = (
		GameplaySpatialRegistry3D.query_radius(
			global_position, 6.5, [GameplaySpatialRegistry3D.KIND_ENEMY], [room_id]
		)
		if GameplaySpatialRegistry3D != null
		else []
	)
	var selected: Enemy3D = null
	var lowest_ratio := 1.01
	for value in candidates:
		var ally := value as Enemy3D
		if ally == null or ally == self or ally.room_id != room_id or ally.ai_state == "dead":
			continue
		var health_ratio := float(ally.current_hp) / float(maxi(1, ally.max_hp))
		if health_ratio < lowest_ratio:
			selected = ally
			lowest_ratio = health_ratio
	if selected != null and lowest_ratio < 1.0:
		selected.receive_healing(maxi(2, int(selected.max_hp * 0.08)))


# =============================================================================
# 远征03 复刻怪：数据驱动的攻击方式（2026-10-29）
#
# 设计依据：`docs/v0.1/design/怪物设计.md` §T2 与 [AI 设计 §3.1]「参数优先」。
# 新增怪种**不允许**在这里长出一个 if 分支 —— 差异全部写在 `PROFILES[kind]` 的
# `volley` / `death_burst` / `suicide_rush` / `support_buff` 键里，由下面这组函数统一消费。
# 这样「加第 13 只怪」是一行数据，而不是一次改代码。
# =============================================================================

## 读本怪的攻击规格。缺键时返回单发直射的默认值 —— 也就是说
## 一只没写 `volley` 的 `egt_*` 怪会退化成「普通单发远程」，不会静默不打人。
func _egt_volley_spec() -> Dictionary:
	var spec: Variant = _active_profile.get("volley", null)
	if spec is Dictionary and not (spec as Dictionary).is_empty():
		return spec as Dictionary
	return {"count": 1, "spread_deg": 0.0, "interval": 0.0, "predict": 0.0}


## 这一轮该用主规格还是备用规格。
## `volley_alt` + `alt_every` 表达的是「每 N 次攻击换一次招」——
## 蓝霰弹枪的「宽 5 发 + 快速接宽 4 发」、枪坚果的「扇形 + 4 组箭头弹群」都是这种结构。
## 用**攻击计数**而不是随机：原作这两只是固定交替，不是掷骰。
func _egt_active_volley_spec() -> Dictionary:
	var alt: Variant = _active_profile.get("volley_alt", null)
	var every := maxi(0, int(_active_profile.get("alt_every", 0)))
	if every > 0 and alt is Dictionary and _egt_attack_count % every == 0:
		return alt as Dictionary
	return _egt_volley_spec()


## 预算目标位置：`predict` 是**预判系数**（0 = 瞄当前位置，1 = 全量预测走位）。
## 只读玩家自己的 `velocity`，不读未来的意图 —— 与「怪物不读全知坐标」的原则一致。
func _predict_target_position(predict_ratio: float) -> Vector3:
	if _target == null or not is_instance_valid(_target) or predict_ratio <= 0.0:
		return _target.global_position if is_instance_valid(_target) else global_position
	var aim := _target.global_position
	if _target is CharacterBody3D:
		aim += (_target as CharacterBody3D).velocity * predict_ratio
	return aim


# -----------------------------------------------------------------------------
# 弹道图案（pattern）
#
# 第二批 21 只怪里有 9 只需要「不是简单扇形」的弹道：环形、V 型、四叶草、字母、
# 罗盘 8 向、箭头群、螺旋、蛇形追踪流、骰子。
# **全部由 `_pattern_directions()` 一个函数产出方向数组**，发射仍然走
# `_fire_projectile()` —— 也就是说「加一种图案」是加一个 case，不是加一条攻击链。
#
# 方向一律在世界水平面上算（怪站在地上，EGT 的弹幕也是平面弹幕）。
# -----------------------------------------------------------------------------

## 字母弹模板：值是**角度序列**（度，0 = 正对玩家）。逐发按 interval 射出，
## 因为弹是连续飞出的，轨迹才连成字母 —— 这和原作 Bookllet 的观感一致。
const LETTER_PATTERNS := {
	"R": [-88.0, -70.0, -52.0, -34.0, -16.0, -34.0, -50.0, -46.0, -30.0, -12.0],
	"N": [-72.0, -52.0, -32.0, -12.0, 8.0, -72.0, -40.0, -8.0, 8.0],
	"phi": [-84.0, -46.0, -12.0, 12.0, 46.0, 84.0, -22.0, 22.0],
}


## 一圈弹的方向：`count` 发均布 360°，第一发朝正前方。
## 环形弹是「无论站哪都要动」的弹型，子弹榴弹王 / Chancebulon / 拟态怪都用它。
static func ring_directions(forward: Vector3, count: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var total := maxi(1, count)
	for index in range(total):
		result.append(forward.rotated(Vector3.UP, TAU * float(index) / float(total)))
	return result


## 一次「攻击事件」的全部方向。`shot_index` 用于**连发型图案**（字母、螺旋）：
## 这类图案的整体形状要靠时间展开，每一次只发其中一发。
func _pattern_directions(spec: Dictionary, forward: Vector3, shot_index: int) -> Array[Vector3]:
	var pattern := str(spec.get("pattern", "line"))
	var count := maxi(1, int(spec.get("count", 1)))
	var spread := deg_to_rad(float(spec.get("spread_deg", 0.0)))
	var result: Array[Vector3] = []
	match pattern:
		"ring":
			return ring_directions(forward, count)
		"cross":
			var arms := maxi(2, count)
			for index in range(arms):
				result.append(forward.rotated(Vector3.UP, TAU * float(index) / float(arms)))
			return result
		"v":
			# V 型：左右各半，从内向外张角递增 —— 中间留空，玩家能站在 V 的凹口里。
			var half := maxi(1, int(ceil(float(count) / 2.0)))
			for index in range(half):
				var ratio := 0.42 + 0.58 * (float(index) / float(maxi(1, half - 1)))
				result.append(forward.rotated(Vector3.UP, -spread * ratio))
				result.append(forward.rotated(Vector3.UP, spread * ratio))
			return result
		"clover":
			# 四叶草：4 个瓣，每瓣 `count` 发小扇形（原作"大型四叶草形弹"）。
			var lobes := 4
			var per_lobe := maxi(1, count)
			for lobe in range(lobes):
				var base := TAU * float(lobe) / float(lobes)
				for index in range(per_lobe):
					var t := 0.5 if per_lobe == 1 else float(index) / float(per_lobe - 1)
					result.append(forward.rotated(Vector3.UP, base + lerpf(-spread, spread, t)))
			return result
		"compass":
			# 罗盘：先把朝向**吸附到 45° 网格**（原作"只能瞄 8 个方向"），再在 ±spread 内散开。
			var snapped := _snap_direction(forward, float(spec.get("snap_deg", 45.0)))
			for index in range(count):
				var t := 0.5 if count == 1 else float(index) / float(count - 1)
				result.append(snapped.rotated(Vector3.UP, lerpf(-spread, spread, t)))
			return result
		"arrows":
			# 箭头形弹群：`count` 组，每组 3 发组成一个尖头（中 + 左右各一），
			# 整组沿 spread 排开 —— 原作 Gun Nut 的"4 组箭头形弹群"。
			var groups := maxi(1, count)
			var snapped_arrow := _snap_direction(forward, float(spec.get("snap_deg", 45.0)))
			for group in range(groups):
				var t := 0.5 if groups == 1 else float(group) / float(groups - 1)
				var center := lerpf(-spread, spread, t)
				for offset in [-9.0, 0.0, 9.0]:
					result.append(snapped_arrow.rotated(Vector3.UP, center + deg_to_rad(offset)))
			return result
		"letter":
			var template: Array = LETTER_PATTERNS.get(str(spec.get("letter", "R")), LETTER_PATTERNS["R"])
			var index_clamped := clampi(shot_index, 0, (template as Array).size() - 1)
			result.append(forward.rotated(Vector3.UP, deg_to_rad(float(template[index_clamped]))))
			return result
		"spiral":
			# 螺旋：逐发旋进。`step_deg` 是每发转多少度。
			var step := deg_to_rad(float(spec.get("step_deg", 30.0)))
			result.append(forward.rotated(Vector3.UP, step * float(clampi(shot_index, 0, count - 1))))
			return result
		"serpentine":
			# 蛇形追踪流：`count` 条平行流，每条各自带追踪（追踪由子弹行为负责）。
			var lanes := maxi(1, count)
			for index in range(lanes):
				var t := 0.5 if lanes == 1 else float(index) / float(lanes - 1)
				result.append(forward.rotated(Vector3.UP, lerpf(-spread, spread, t)))
			return result
		"dice":
			# 骰子弹组：点数 1~6，按点数排成一圈 —— "掷出来几点就是几发"。
			var pips := clampi(shot_index % 6 + 1, 1, 6) if shot_index > 0 else (randi() % 6 + 1)
			return ring_directions(forward, pips)
		_:
			# line / fan：单发直射，或多发在 ±spread 内均匀展开。
			if count == 1:
				return [forward]
			for index in range(count):
				var t := float(index) / float(count - 1)
				result.append(forward.rotated(Vector3.UP, lerpf(-spread, spread, t)))
			return result


## 把朝向吸附到最近的 `snap_deg` 网格上（默认 45° = 8 个罗盘方向）。
## 只在水平面上做，且保持单位长度。
static func _snap_direction(forward: Vector3, snap_deg: float) -> Vector3:
	var planar := Vector3(forward.x, 0.0, forward.z)
	if planar.length_squared() < 0.0001:
		return Vector3.FORWARD
	planar = planar.normalized()
	if snap_deg <= 0.0:
		return planar
	var step := deg_to_rad(snap_deg)
	var yaw := atan2(planar.x, planar.z)
	var snapped := roundf(yaw / step) * step
	return Vector3(sin(snapped), 0.0, cos(snapped))


## 一发子弹的附加行为（追踪 / 反弹 / 弹速 / 延时寿命），由规格直接抄给子弹。
## 只挑**通用**键，不去猜某个怪的名字 —— 于是任何怪都能用同一批能力。
func _volley_bullet_behavior(spec: Dictionary) -> Dictionary:
	var behavior := {}
	if spec.has("homing"):
		behavior["homing"] = true
		behavior["homing_strength"] = clampf(float(spec.get("homing", 0.0)), 0.0, 1.0)
	if spec.has("bounce"):
		behavior["bounce_count"] = maxi(0, int(spec.get("bounce", 0)))
	if spec.has("home_lifetime"):
		behavior["home_lifetime"] = float(spec.get("home_lifetime", 1.0))
	# 射程：追踪弹要飞得够久，否则半路就没了（追踪本来就要绕）。
	if spec.has("homing"):
		behavior["home_lifetime"] = maxf(float(behavior.get("home_lifetime", 1.0)), 2.6)
	return behavior


## 一次完整攻击：把「图案 → 若干次射击事件」算出来，按 `interval` 排队或当帧齐射。
## `interval` 的语义分两种，靠图案是否为**逐发展开型**决定：
##   字母 / 螺旋 → 每发一个事件，沿时间展开成形状
##   其余        → 一次事件出全部发，`interval` 只做逐发微延迟（读作"连发"）
func _perform_volley_attack(to_target: Vector3, _distance: float) -> void:
	if _disguised:
		return
	var spec := _egt_active_volley_spec()
	var interval := maxf(0.0, float(spec.get("interval", 0.0)))
	var bullets := _pattern_bullet_count(spec)
	# 双环/多环（蓝书怪的"来回脉动"）：整组图案重复 `pulse_rings` 次。
	var rings := maxi(1, int(spec.get("pulse_rings", 1)))
	var total := bullets * rings
	# `interval > 0` ⇒ **逐发排期**（连发 / 环形顺次展开 / 字母逐笔画出）。
	# `interval == 0` ⇒ 整组图案当帧齐射（霰弹扇形、十字、四叶草都是这一类）。
	# 判据只认 interval，不认图案类型 —— 否则「同一图案换个节奏」又要加一个分支。
	if interval > 0.0:
		for index in range(total):
			_queue_volley_shot(
				interval * float(index), spec,
				index % bullets, floori(float(index) / float(bullets)), true, index % bullets
			)
	else:
		for ring in range(rings):
			_queue_volley_shot(0.0, spec, 0, ring, false, 0)
	# 第二段（原作蓝霰弹「宽 5 发 → 快速接宽 4 发」）。
	# 接在**主段全部打完**之后，不是另一次攻击 —— 这一点决定玩家能不能把它们当成一波躲。
	var follow: Variant = spec.get("followup", null)
	if follow is Dictionary:
		var fspec := follow as Dictionary
		var fcount := _pattern_bullet_count(fspec)
		var finterval := maxf(0.0, float(fspec.get("interval", 0.0)))
		var offset := float(fspec.get("delay", 0.2))
		offset += interval * float(maxi(0, total - 1))
		if finterval > 0.0:
			for index in range(fcount):
				_queue_volley_shot(offset + finterval * float(index), fspec, index % fcount, 0, true, index % fcount)
		else:
			_queue_volley_shot(offset, fspec, 0, 0, false, 0)
	# 大 jammed 弹（枪坚果）。原作原文：
	#   "they also fire a **larger jammed bullet** that explodes into non-jammed bullets
	#    in all directions **upon hitting an obstacle**"
	# 它**不属于**扇形那 7 发 —— 是额外的一颗，且朝玩家瞄准（原作："always aimed
	# towards the player, but can only be shot within the width of the burst"）。
	# 所以这里不进队列，直接单发；飞行比普通弹慢，玩家有机会看到它脱队。
	var jammed: Variant = spec.get("jammed", null)
	if jammed is Dictionary:
		var jspec := jammed as Dictionary
		var aim := _predict_target_position(float(jspec.get("predict", 0.0)))
		var aim_direction := aim - global_position
		aim_direction.y = 0.0
		if aim_direction.length_squared() > 0.0001:
			_fire_projectile(
				aim_direction.normalized(), contact_damage, _egt_projectile_color(),
				false,
				{
					"shatter_on_wall": true,
					"shatter_count": int(jspec.get("shatter_count", 8)),
					"shatter_damage_ratio": float(jspec.get("shatter_damage_ratio", 0.5)),
					"shatter_speed": float(jspec.get("shatter_speed", 6.0)),
				},
				float(jspec.get("speed", 6.5))
			)
	# 「蛋」（吉吉）：先发一枚慢速蛋，到点在落点炸一圈涌动子弹。
	if _active_profile.has("egg"):
		_schedule_egg(_active_profile["egg"] as Dictionary)


## 排一颗蛋。落点按**玩家当前速度整段预判**：蛋飞行期间玩家会动，
## 瞄当前位置会让蛋永远炸在身后 —— 那样这招就只是"延迟的直线弹"。
func _schedule_egg(spec: Dictionary) -> void:
	var hatch := maxf(0.1, float(spec.get("hatch_sec", 0.85)))
	var aim := _predict_target_position(1.0)
	aim.y = global_position.y + 0.4
	_pending_eggs.append({"timer": hatch, "position": aim, "spec": spec.duplicate(true)})


## 一次图案总共会产生几发子弹。**只用于排期**，不参与方向计算 ——
## 方向仍由 `_pattern_directions()` 现算（玩家在动，方向必须每发重算）。
static func _pattern_bullet_count(spec: Dictionary) -> int:
	var pattern := str(spec.get("pattern", "line"))
	var count := maxi(1, int(spec.get("count", 1)))
	match pattern:
		"v":
			return 2 * maxi(1, int(ceil(float(count) / 2.0)))
		"clover":
			return 4 * count
		"arrows":
			return 3 * count
		"dice":
			return 6
		_:
			return count


## 排队一次射击事件。**不存死的方向**，只存规格与序号 —— 到点那一刻才重新预算目标位置，
## 所以连发期间玩家在动，后几发仍然会跟着修正（锁死第一帧会让连发退化成一次性扇形）。
##
## `slice` = 这次事件只发图案里的**第 `slice_index` 发**（连发/顺次展开），
## 而不是整组。两种模式共用同一个队列，靠一个布尔区分，避免两套时序。
func _queue_volley_shot(
	delay: float, spec: Dictionary, shot_index: int, ring_index: int,
	slice: bool = false, slice_index: int = 0
) -> void:
	_pending_volleys.append({
		"delay": maxf(0.0, delay),
		"spec": spec.duplicate(true),
		"shot_index": shot_index,
		"ring_index": ring_index,
		"slice": slice,
		"slice_index": slice_index,
	})


## 连发推进。挂在 `_physics_process` 的既有递减区旁边，逐帧检查到期。
## 怪死亡时队列直接清空（`_die()` 里做），避免尸体还在开火。
func _tick_pending_volleys(delta: float) -> void:
	if _pending_volleys.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for shot in _pending_volleys:
		var wait := float(shot.get("delay", 0.0)) - delta
		if wait > 0.0:
			shot["delay"] = wait
			remaining.append(shot)
			continue
		if ai_state == "dead" or _disguised:
			continue
		var spec: Dictionary = shot.get("spec", {})
		var predict := clampf(float(spec.get("predict", 0.0)), 0.0, 1.0)
		var aim := _predict_target_position(predict)
		var direction := aim - global_position
		direction.y = 0.0
		if direction.length_squared() < 0.0001:
			continue
		var forward := direction.normalized()
		var dirs := _pattern_directions(spec, forward, int(shot.get("shot_index", 0)))
		if bool(shot.get("slice", false)) and not dirs.is_empty():
			dirs = [dirs[int(shot.get("slice_index", 0)) % dirs.size()]]
		var damage := contact_damage
		if spec.has("damage_ratio"):
			damage = maxi(1, int(round(float(contact_damage) * float(spec["damage_ratio"]))))
		var explosive := bool(spec.get("explosive", false))
		var behavior := _volley_bullet_behavior(spec)
		var bullet_speed := float(spec.get("speed", 0.0))
		for dir in dirs:
			_fire_projectile(
				dir, damage, _egt_projectile_color(), explosive, behavior,
				bullet_speed, global_position
			)
	_pending_volleys = remaining


## 复刻怪的子弹颜色：**优先读表里的 `bullet_color`**，没写才回退到按种取。
## 第一批用的是写死的 match（5 只远程）；第二批有 21 只，再堆 match 就没有底了。
## 颜色规则仍是"身体色 = 弹色"（见设计 §T3.2），查表与染色表一一对应。
func _egt_projectile_color() -> Color:
	var declared: Variant = _active_profile.get("bullet_color", null)
	if declared is Color:
		return declared as Color
	match _table_kind():
		"egt_bandana_kin":
			return Color(0.36, 0.62, 0.98)
		"egt_veteran_kin":
			return Color(0.98, 0.60, 0.28)
		"egt_red_shotgun":
			return Color(0.92, 0.26, 0.26)
		"egt_blue_shotgun":
			return Color(0.32, 0.52, 0.96)
		_:
			return Color(0.62, 0.82, 1.0)


## 复刻怪的攻击分派。**唯一的分歧点** —— 其余全部由 `PROFILES` 的键决定。
func _perform_egt_attack(to_target: Vector3, distance: float) -> void:
	_egt_attack_count += 1
	match _egt_attack_style():
		"volley":
			_perform_volley_attack(to_target, distance)
		"contact":
			_perform_egt_contact(to_target, distance)
		"explode":
			_perform_egt_explode(to_target)
		"rush":
			_perform_suicide_rush(to_target)
		"support":
			_perform_support_buff()
		"orbit":
			_begin_orbit()
		"grab":
			_begin_grab()
		"chance":
			_perform_chance_move(to_target, distance)
		"flee":
			# 逃跑型不攻击玩家（原作钥匙小子 / 运气小子只会跑）。
			pass
		_:
			_perform_egt_contact(to_target, distance)


## 接触型复刻怪（布洛布三阶）：贴身后短突进 + 命中结算，与 `melee_chaser` 同构，
## **不新增策略** —— EGT 这三只本来就是"走向玩家、接触伤害"。
func _perform_egt_contact(to_target: Vector3, distance: float) -> void:
	_external_velocity = to_target.normalized() * 6.4
	_external_timer = 0.16
	if distance <= attack_range + 0.60 and is_instance_valid(_target) and _target.has_method("take_damage"):
		if _target.has_method("notify_attacked_by"):
			_target.call("notify_attacked_by", self)
		_target.call("take_damage", contact_damage, false, to_target.normalized())


## 爆炸族（保险销头 / 硝酸怪）。原作原文：
##   Pinhead  "Walks towards the player and explodes upon death. **If the player gets too
##             close, it will leap towards the player and explode.**"
##   Nitra    "...If the player gets too close, it will **detonate itself**."
## ⇒ 两者都不是"走到射程就原地炸"，而是**先扑上去再炸**。
## 旧实现直接调 `_explode()`，玩家看到的是"它站在两米外突然爆了" —— 少了那个扑的动作，
## 也就少了"这下该后退"的信号。
##
## 实现：给一个朝玩家的冲量（`leap_speed`），把爆炸延后 `leap_sec` 秒。
## 延迟是**必须**的 —— 否则同一帧位移+爆炸，画面上等于没动。
func _perform_egt_explode(to_target: Vector3) -> void:
	var spec: Variant = _active_profile.get("leap", null)
	if not (spec is Dictionary):
		_explode()
		return
	var cfg := spec as Dictionary
	if _explode_pending > 0.0:
		return
	_external_velocity = to_target.normalized() * float(cfg.get("leap_speed", 9.0))
	_external_timer = float(cfg.get("leap_sec", 0.22))
	_explode_pending = float(cfg.get("leap_sec", 0.22))
	_spawn_effect("VFX-IMPACT-3D", 0.55)


## 一次性冲撞（`egt_bullat`）：整只怪当一发子弹打出去，命中或超时都自毁。
## 为什么必须新增而不是复用 MeleeLunge：常规突进**打完还活着**，
## 而这只的语义是「撞到即死」——改变的是行动拓扑，属 §3.1 允许新增的范围。
func _perform_suicide_rush(to_target: Vector3) -> void:
	var spec: Variant = _active_profile.get("suicide_rush", null)
	var rush_speed := 11.0
	var predict := 0.0
	var repositions := 0
	var lifetime := 2.5
	if spec is Dictionary:
		var cfg := spec as Dictionary
		rush_speed = float(cfg.get("speed", rush_speed))
		predict = clampf(float(cfg.get("predict", 0.0)), 0.0, 1.0)
		repositions = maxi(0, int(cfg.get("repositions", 0)))
		lifetime = float(cfg.get("max_lifetime", 2.5))
	var aim := _predict_target_position(predict)
	var heading := aim - global_position
	heading.y = 0.0
	if heading.length_squared() < 0.0001:
		heading = to_target
	_external_velocity = heading.normalized() * rush_speed
	_external_timer = 0.45
	_suicide_rush_active = true
	_suicide_rush_timer = lifetime
	_rush_repositions_left = repositions
	if is_instance_valid(_target) and _target.has_method("take_damage"):
		var flat := _target.global_position - global_position
		flat.y = 0.0
		if flat.length() <= attack_range * 0.55:
			if _target.has_method("notify_attacked_by"):
				_target.call("notify_attacked_by", self)
			_target.call("take_damage", contact_damage, false, to_target.normalized())
			_fire_rush_payload(heading.normalized())
			_die()


## 冲撞的「撞到时附加弹」：Shotgat 的 V 型 2 发、Grenat 的 1 发爆炸弹。
## 写在 `suicide_rush.on_hit` 里，三只冲撞族共用一段代码 —— 差别只是参数。
func _fire_rush_payload(forward: Vector3) -> void:
	var spec: Variant = _active_profile.get("suicide_rush", null)
	if not (spec is Dictionary):
		return
	var payload: Variant = (spec as Dictionary).get("on_hit", null)
	if not (payload is Dictionary):
		return
	var payload_spec := payload as Dictionary
	var damage := contact_damage
	if payload_spec.has("damage_ratio"):
		damage = maxi(1, int(round(float(contact_damage) * float(payload_spec["damage_ratio"]))))
	for dir in _pattern_directions(payload_spec, forward, 0):
		_fire_projectile(
			dir, damage, _egt_projectile_color(),
			bool(payload_spec.get("explosive", false)),
			_volley_bullet_behavior(payload_spec),
			float(payload_spec.get("speed", 0.0)),
			global_position
		)


## 冲撞途中的重定位（Spirat）：偏转航向追新的预判点。
## 只在 `repositions > 0` 的冲撞族身上生效，bullat 那种一次性的不调用。
func _tick_rush_reposition() -> void:
	if _rush_repositions_left <= 0:
		return
	var spec: Variant = _active_profile.get("suicide_rush", null)
	if not (spec is Dictionary):
		return
	var cfg := spec as Dictionary
	var predict := clampf(float(cfg.get("predict", 0.0)), 0.0, 1.0)
	var rush_speed := float(cfg.get("speed", 11.0))
	var aim := _predict_target_position(predict)
	var heading := aim - global_position
	heading.y = 0.0
	if heading.length_squared() < 0.0001:
		return
	_external_velocity = heading.normalized() * rush_speed
	_external_timer = 0.45
	_rush_repositions_left -= 1


## 辅助（`egt_gunsinger`）：不攻击玩家，给半径内**血量比例最低的盟友**加血 + 提速。
## 这是本批唯一「目标类型变成盟友」的策略，按 §3.1 必须独立。
## 自己不受益（原作 Gunsinger 也不给自己 buff），且不治疗满血单位。
func _perform_support_buff() -> void:
	# —— 原作的中断条件（之前完全没实现，等于它可以站着把 buff 刷满）——
	# "They will cancel their spell and **run away if the player is too close
	#  or they take too much damage**."
	# 两条触发条件共用同一段逃跑逻辑：被打断 → 逃 `flee_sec` 秒 → 回来继续施法。
	if _support_interrupted():
		_egt_interrupt_flee = float(_interrupt_spec().get("flee_sec", 2.5))
		return
	var spec: Variant = _active_profile.get("support_buff", null)
	var radius := 12.0
	var hp_ratio := 0.35
	var speed_mult := 1.35
	var duration := 5.0
	if spec is Dictionary:
		radius = float((spec as Dictionary).get("radius_m", radius))
		hp_ratio = float((spec as Dictionary).get("hp_ratio", hp_ratio))
		speed_mult = float((spec as Dictionary).get("speed_mult", speed_mult))
		duration = float((spec as Dictionary).get("duration", duration))
	var candidates: Array[Node3D] = (
		GameplaySpatialRegistry3D.query_radius(
			global_position, radius, [GameplaySpatialRegistry3D.KIND_ENEMY], [room_id]
		)
		if GameplaySpatialRegistry3D != null
		else []
	)
	var selected: Enemy3D = null
	var lowest_ratio := 1.01
	for value in candidates:
		var ally := value as Enemy3D
		if ally == null or ally == self or ally.room_id != room_id or ally.ai_state == "dead":
			continue
		var ratio := float(ally.current_hp) / float(maxi(1, ally.max_hp))
		if ratio < lowest_ratio:
			selected = ally
			lowest_ratio = ratio
	if selected == null:
		return
	selected.receive_healing(maxi(2, int(selected.max_hp * hp_ratio)))
	selected.apply_haste(speed_mult, duration)


## 加速（Gunsinger 的 buff 落点）。与 `_slow_factor` 对称：
## **只乘 `get_effective_move_speed()`，不改 `move_speed` 本体** ——
## 否则 buff 结束得把原值算回来，一旦中途 `apply_profile` 就会算错。
func apply_haste(multiplier: float, duration: float) -> void:
	if ai_state == "dead":
		return
	_haste_factor = maxf(1.0, multiplier)
	_haste_timer = maxf(_haste_timer, duration)


## 死亡全向喷（红/蓝霰弹枪）。`chance` 表达原作的「有几率」——
## 三只霰弹枪里红色的最安全，正因为它是概率而非必定（见设计 §T1）。
func _perform_death_burst() -> void:
	var spec: Variant = _active_profile.get("death_burst", null)
	if not (spec is Dictionary):
		return
	var cfg := spec as Dictionary
	if randf() > float(cfg.get("chance", 1.0)):
		return
	var count := maxi(2, int(cfg.get("count", 6)))
	var damage := maxi(1, int(round(float(contact_damage) * float(cfg.get("damage_ratio", 0.75)))))
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		_fire_projectile(direction, damage, _egt_projectile_color())


## 死亡分裂（布洛布三阶）。子代由房间通过 `split_requested` 统一实例化，
## **不在这里 new 敌人** —— 实例化出口只有 `Dungeon3D._spawn_enemy_batch` 一条。
func _perform_death_split() -> void:
	var spec: Variant = _active_profile.get("death_split", null)
	if not (spec is Dictionary):
		return
	var cfg := spec as Dictionary
	# 新写法 `children[]`：一次死亡生成**多种**子代（子弹榴弹王同时产 Bullat 与 Shotgat）。
	# 旧写法 `child/count` 仍然生效 —— 布洛布三阶一行不用改。
	var children: Variant = cfg.get("children", null)
	if children is Array and not (children as Array).is_empty():
		for entry_value in children as Array:
			if not (entry_value is Dictionary):
				continue
			var entry := entry_value as Dictionary
			var kind := str(entry.get("child", ""))
			if kind.is_empty() or not PROFILES.has(kind):
				continue
			split_requested.emit(self, kind, maxi(1, int(entry.get("count", 1))))
		return
	var child := str(cfg.get("child", ""))
	var count := maxi(1, int(cfg.get("count", 2)))
	if child.is_empty() or not PROFILES.has(child):
		return
	split_requested.emit(self, child, count)


# =============================================================================
# 远征03 第二批：非弹道行为（瞬移 / 逃跑 / 伪装 / 抓取 / 绕圈链 / 随机招式）
#
# 这一组全部挂在 `_tick_egt_state()` 里按帧推进，只对**声明了对应键**的怪生效。
# 没声明这些键的怪（包括第一批 12 只）连函数体都不会进 —— 行为逐字不变。
# =============================================================================

## 复刻怪的状态推进。挂在 `_physics_process` 的既有递减区，与连发队列同一个时序真源。
func _tick_egt_state(delta: float) -> void:
	if not _is_egt_kind() or ai_state == "dead":
		return
	_tick_egt_blink(delta)
	_tick_egt_flee(delta)
	_tick_egt_interrupt(delta)
	_tick_egt_explode_pending(delta)
	_tick_egt_disguise(delta)
	_tick_egt_wander(delta)
	_tick_egt_grab(delta)
	_tick_egt_orbit(delta)
	_tick_egt_eggs(delta)
	_tick_rush_reposition()


## 扑击延迟：到点才真的炸。放在 tick 里而不是 `await`，
## 是为了让「怪死了 / 被冻结」时这条延迟自然失效。
func _tick_egt_explode_pending(delta: float) -> void:
	if _explode_pending <= 0.0:
		return
	_explode_pending = maxf(0.0, _explode_pending - delta)
	if _explode_pending <= 0.0 and ai_state != "dead":
		_explode()


## 读这只怪的 `interrupt` 规格（目前只有枪歌者声明）。
func _interrupt_spec() -> Dictionary:
	var spec: Variant = _active_profile.get("interrupt", null)
	return spec as Dictionary if spec is Dictionary else {}


## 施法是否该被打断：玩家靠太近，或自己在 `hurt_window_sec` 内受过伤。
## 两条都是原作明确写的条件 —— 少实现任何一条，它就会变成"站着把 buff 刷满"的靶子。
func _support_interrupted() -> bool:
	if _egt_hurt_window > 0.0:
		return true
	var radius := float(_interrupt_spec().get("flee_radius_m", 6.0))
	return _get_player_in_proximity(radius) != null


## 被打断后的短暂逃跑：沿远离玩家方向位移 `flee_sec` 秒。
## **不改 `move_speed`**，只写 `_external_velocity` —— 与 `flee` / `grab` 同一套口径，
## 这样被减速/加速时仍按比例生效，也不会污染 profile。
func _tick_egt_interrupt(delta: float) -> void:
	_egt_hurt_window = maxf(0.0, _egt_hurt_window - delta)
	if _egt_interrupt_flee <= 0.0:
		return
	_egt_interrupt_flee = maxf(0.0, _egt_interrupt_flee - delta)
	if not is_instance_valid(_target):
		return
	var away := global_position - _target.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	var mult := float(_interrupt_spec().get("flee_speed_mult", 1.5))
	_external_velocity = away.normalized() * get_effective_move_speed() * mult
	_external_timer = 0.12


## 蛋的孵化：到点在落点炸一圈，子弹带轻微追踪（"涌动"）。
func _tick_egt_eggs(delta: float) -> void:
	if _pending_eggs.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for egg in _pending_eggs:
		var wait := float(egg.get("timer", 0.0)) - delta
		if wait > 0.0:
			egg["timer"] = wait
			remaining.append(egg)
			continue
		if ai_state == "dead":
			continue
		var spec: Dictionary = egg.get("spec", {})
		var point: Vector3 = egg.get("position", global_position)
		var count := maxi(1, int(spec.get("burst_count", 8)))
		var damage := maxi(1, int(round(float(contact_damage) * float(spec.get("burst_damage_ratio", 0.7)))))
		var behavior := {}
		if spec.has("homing"):
			behavior["homing"] = true
			behavior["homing_strength"] = clampf(float(spec.get("homing", 0.0)), 0.0, 1.0)
			behavior["home_lifetime"] = 2.2
		for dir in ring_directions(Vector3.FORWARD, count):
			_fire_projectile(dir, damage, _egt_projectile_color(), false, behavior, 0.0, point)
	_pending_eggs = remaining


## 瞬移（空尖弹定时 / 枪法师出手后）。落在**原地半径内**的一个随机点，
## 不直接传到房间对角：那会让玩家完全丢失目标，读起来像"卡了一下"。
func _tick_egt_blink(delta: float) -> void:
	var spec: Variant = _active_profile.get("blink", null)
	if not (spec is Dictionary):
		return
	var cfg := spec as Dictionary
	if bool(cfg.get("on_attack", false)):
		return
	var interval := float(cfg.get("interval", 0.0))
	if interval <= 0.0:
		return
	_blink_timer = maxf(0.0, _blink_timer - delta)
	if _blink_timer > 0.0:
		return
	_blink_timer = interval
	_blink_to_random(float(cfg.get("radius_m", 8.0)))


## 瞬移到「当前点周围 radius 内」的一个随机水平位置。
## ⚠ 只做水平位移、不改 Y：怪必须继续贴地，否则会浮空或被塞进地板。
func _blink_to_random(radius: float) -> void:
	if radius <= 0.0:
		return
	var angle := randf() * TAU
	var distance := radius * sqrt(randf())
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * distance
	var target := global_position + offset
	if not _is_point_inside_room_hint(target):
		# 落点在房外（或算不出来）⇒ 朝房间中心折半，避免穿墙。
		target = global_position + offset * 0.5
	global_position = Vector3(target.x, global_position.y, target.z)
	velocity = Vector3.ZERO
	_external_velocity = Vector3.ZERO


## 房内判定。**只作"别穿墙"的软约束**，不是精确碰撞：
## 以出生点为房心、用「出生点到当前点的最远距离」当半径的近似。
## 真正的墙判定由 `_track_stuck_recovery` 负责把卡住的怪推回来。
func _is_point_inside_room_hint(point: Vector3) -> bool:
	var limit := maxf(6.0, global_position.distance_to(_home_position) + 6.0)
	return point.distance_to(_home_position) <= limit


## 逃跑（钥匙小子 / 运气小子）：朝**远离玩家**的方向跑，超时直接消失。
## 消失不是死亡 —— 但房间的清怪计数必须跟着减，否则门永远打不开，
## 所以走 `_die()`，只是把掉落与死亡特效关上（见 `_vanish`）。
func _tick_egt_flee(delta: float) -> void:
	var spec: Variant = _active_profile.get("flee", null)
	if not (spec is Dictionary):
		return
	var cfg := spec as Dictionary
	var vanish_after := float(cfg.get("vanish_after", 0.0))
	if vanish_after > 0.0:
		_flee_timer = maxf(0.0, _flee_timer - delta)
		if _flee_timer <= 0.0:
			_vanish()
			return
	# 逃跑的位移指令写在 `_external_velocity` 上：不改 `move_speed`，
	# 于是被减速/加速时仍然按比例生效，也不会污染 profile。
	if not is_instance_valid(_target):
		return
	var away := global_position - _target.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	var speed := get_effective_move_speed() * float(cfg.get("speed_mult", 1.4))
	_external_velocity = away.normalized() * speed
	_external_timer = 0.12


## 伪装（拟态怪）：静止、不攻击、不吃伤害；玩家靠近或自己被打中才现形。
func _tick_egt_disguise(delta: float) -> void:
	var spec: Variant = _active_profile.get("disguise", null)
	if not (spec is Dictionary) or not _disguised:
		return
	var cfg := spec as Dictionary
	var player := _get_player_in_proximity(float(cfg.get("reveal_radius_m", 3.2)))
	if player != null:
		_reveal_disguise()
		return
	velocity = Vector3.ZERO
	_external_velocity = Vector3.ZERO


## 现形。只改一个标志位 —— 表现层（模型/血条）由既有通道自动跟上，
## 不再额外做一套"宝箱模型"。占位期这是可接受的：玩家看到的是"一个箱子突然活了"。
func _reveal_disguise() -> void:
	if not _disguised:
		return
	_disguised = false
	_blink_timer = 0.0
	avatar.flash_hit()


## 游荡（枪精灵）：不贴脸，绕着房间中心的一个随机点飘，到点换目标。
func _tick_egt_wander(delta: float) -> void:
	var spec: Variant = _active_profile.get("wander", null)
	if not (spec is Dictionary):
		return
	var cfg := spec as Dictionary
	_wander_timer = maxf(0.0, _wander_timer - delta)
	if _wander_timer > 0.0 and _wander_target != Vector3.ZERO:
		var offset := _wander_target - global_position
		offset.y = 0.0
		if offset.length() > 0.6:
			_external_velocity = offset.normalized() * get_effective_move_speed() * 0.85
			_external_timer = 0.12
			return
	_wander_timer = float(cfg.get("retarget_sec", 2.2))
	var radius := float(cfg.get("radius_m", 8.0))
	var angle := randf() * TAU
	_wander_target = _home_position + Vector3(cos(angle), 0.0, sin(angle)) * radius * sqrt(randf())


## 抓握大师：悬停 → 闪蓝预警 → 下压抓取 → 复位。
##
## **不改血量、只改位置**（原作这条是「不造成伤害却改变关卡状态」）。
## 缺"房间重置"链路，所以抓到后是**把玩家抛回房间入口方向**，见设计 §T6 已知差异。
func _tick_egt_grab(delta: float) -> void:
	var spec: Variant = _active_profile.get("grab", null)
	if not (spec is Dictionary):
		return
	var cfg := spec as Dictionary
	var hover_height := float(cfg.get("hover_height_m", 4.2))
	match _grab_state:
		"idle":
			# 清场后自动死亡：原作 "Automatically **dies if all other enemies in the room
			# are killed**"。旧实现只有"有别人时无敌"，于是清完场还剩一只打不动的在飘。
			if bool(_active_profile.get("die_when_others_dead", false)) and not _room_has_other_living_enemy():
				_die()
				return
			# 悬停：保持在地面之上一个固定高度（重力对它是关掉的，见 `_egt_hover_lock`）。
			_hold_hover(hover_height)
			_grab_timer = maxf(0.0, _grab_timer - delta)
			if _grab_timer <= 0.0 and is_instance_valid(_target):
				_grab_state = "telegraph"
				_grab_timer = float(cfg.get("telegraph_sec", 0.8))
				avatar.flash_hit()
		"telegraph":
			_hold_hover(hover_height)
			_grab_timer = maxf(0.0, _grab_timer - delta)
			if _grab_timer <= 0.0:
				_grab_state = "dive"
				var aim := _target.global_position if is_instance_valid(_target) else global_position
				_grab_dive_target = Vector3(aim.x, global_position.y, aim.z)
		"dive":
			var to_point := _grab_dive_target - global_position
			to_point.y = 0.0
			var step := float(cfg.get("dive_speed", 12.0)) * delta
			global_position += to_point.normalized() * minf(step, to_point.length())
			if to_point.length() <= 0.9:
				# 原作是 "**attempts** to grab"：闪蓝之后玩家可以走开/翻滚躲掉。
				# 旧实现无条件抛玩家 ⇒ 等于"必中"，玩家无从应对。
				# 判据用「落点与玩家的水平距离 ≤ grab_radius_m」而不是"到达落点即成功"。
				var grab_radius := float(cfg.get("grab_radius_m", 1.6))
				var caught := (
					is_instance_valid(_target)
					and _flat_distance_to(_target) <= grab_radius
				)
				if caught:
					_apply_grab_throw(float(cfg.get("throw_distance_m", 10.0)))
				else:
					_grab_miss_count += 1
					if _grab_miss_count >= int(_active_profile.get("max_grab_misses", 3)):
						_vanish()
						return
				_grab_state = "recover"
				_grab_timer = 1.2
		"recover":
			_hold_hover(hover_height)
			_grab_timer = maxf(0.0, _grab_timer - delta)
			if _grab_timer <= 0.0:
				_grab_state = "idle"
				_grab_timer = attack_cooldown


## 抓握大师起手：进入闪蓝预警。真正的下压由 `_tick_egt_grab()` 推进 ——
## 攻击通道只负责"开始"，时序仍然只有一处真源。
func _begin_grab() -> void:
	var spec: Variant = _active_profile.get("grab", null)
	if not (spec is Dictionary):
		return
	if _grab_state != "idle":
		return
	_grab_state = "telegraph"
	_grab_timer = float((spec as Dictionary).get("telegraph_sec", 0.8))
	avatar.flash_hit()


## 把玩家从当前点**抛向远离抓握大师的方向**。伤害为 0，只做位移与击退。
## 用 `take_damage(0, …)` 的 knockback 通道而不是直接改坐标：
## 玩家自己的位移/碰撞/镜头都在那一条链上，绕过它会和相机打架。
func _apply_grab_throw(throw_distance_m: float) -> void:
	if not is_instance_valid(_target) or not _target.has_method("take_damage"):
		return
	var away := _target.global_position - global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3.FORWARD
	if _target.has_method("notify_attacked_by"):
		_target.call("notify_attacked_by", self)
	_target.call("take_damage", 0, false, away.normalized(), true, throw_distance_m * 0.35)


## 悬停：直接压住 Y 高度（抓握大师不落地）。
func _hold_hover(height: float) -> void:
	var floor_y := _home_position.y + height
	global_position.y = lerpf(global_position.y, floor_y, 0.12)
	velocity.y = 0.0


## 链枪手起手：开始绕圈链。
func _begin_orbit() -> void:
	var spec: Variant = _active_profile.get("orbit", null)
	if not (spec is Dictionary):
		return
	_orbit_active = true
	_orbit_angle = randf() * TAU
	_orbit_timer = float((spec as Dictionary).get("duration", 2.0))
	_orbit_emit_accumulator = 0.0


## 绕圈链推进：一边慢慢逼近玩家，一边按 `rev_per_sec` 转出一串弹。
## 原作「约 3 圈/秒转 2 秒」—— 圈速 × 时长决定了总共几圈，是它压力的全部来源。
func _tick_egt_orbit(delta: float) -> void:
	if not _orbit_active:
		return
	var spec: Variant = _active_profile.get("orbit", null)
	if not (spec is Dictionary):
		_orbit_active = false
		return
	var cfg := spec as Dictionary
	var rev_per_sec := float(cfg.get("rev_per_sec", 3.0))
	var per_rev := maxi(1, int(cfg.get("bullets_per_rev", 6)))
	_orbit_timer = maxf(0.0, _orbit_timer - delta)
	if _orbit_timer <= 0.0:
		_orbit_active = false
		# 原作："If it's the **only enemy alive** in the room, the ball of the chain will
		# **detach and launch** towards the player."
		# 收链那一刻判定 —— 早判定会让"刚打死最后一只的下一轮"漏掉这一次脱手。
		if not _room_has_other_living_enemy():
			_launch_orbit_ball()
		return
	_orbit_angle += TAU * rev_per_sec * delta
	# 按角度累积发射，保证"每圈 N 发"与帧率无关。
	_orbit_emit_accumulator += TAU * rev_per_sec * delta / float(per_rev)
	while _orbit_emit_accumulator >= 1.0:
		_orbit_emit_accumulator -= 1.0
		var direction := Vector3(sin(_orbit_angle), 0.0, cos(_orbit_angle))
		_fire_projectile(
			direction, contact_damage, _egt_projectile_color(), false, {},
			float(cfg.get("speed", 6.4)), global_position
		)
	# 缓慢逼近：链在转的时候整只怪往前压，逼玩家在弹链里移动。
	if is_instance_valid(_target):
		var toward := _target.global_position - global_position
		toward.y = 0.0
		if toward.length() > 1.0:
			_external_velocity = toward.normalized() * get_effective_move_speed() * 0.55
			_external_timer = 0.12


## 链球脱手：链枪手是房内最后一只时，收链瞬间把球甩向玩家。
## 伤害沿用 `contact_damage`，但**弹速更快**（原作是"甩出去"而不是"链在转"），
## 并且带 `explosive` 标签 —— 它是整颗球，不是链上的一节。
func _launch_orbit_ball() -> void:
	if not is_instance_valid(_target):
		return
	var direction := _target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var spec: Variant = _active_profile.get("orbit", null)
	var ball_speed := 11.0
	if spec is Dictionary:
		ball_speed = float((spec as Dictionary).get("ball_speed", ball_speed))
	_fire_projectile(
		direction.normalized(), contact_damage, _egt_projectile_color(),
		true, {}, ball_speed, global_position + Vector3(0, 0.9, 0)
	)


## Chancebulon：随机借用同族招式，且**有几率不攻击而是直接死**（原作骰子感）。
func _perform_chance_move(to_target: Vector3, distance: float) -> void:
	var spec: Variant = _active_profile.get("chance_moves", null)
	if not (spec is Dictionary):
		_perform_egt_contact(to_target, distance)
		return
	var cfg := spec as Dictionary
	if randf() < float(cfg.get("self_destruct_chance", 0.0)):
		# 「有几率不攻击而直接死亡」—— 死法走正常死亡链，掉落照给。
		_die()
		return
	var moves: Array = cfg.get("moves", [])
	if moves.is_empty():
		_perform_egt_contact(to_target, distance)
		return
	match str(moves[randi() % moves.size()]):
		"contact":
			_perform_egt_contact(to_target, distance)
		"ring":
			var forward := to_target
			forward.y = 0.0
			for dir in ring_directions(forward.normalized(), 8):
				_fire_projectile(dir, contact_damage, _egt_projectile_color(), false, {}, 0.0, global_position)
		"dice":
			var forward2 := to_target
			forward2.y = 0.0
			for dir in _pattern_directions({"pattern": "dice", "count": 6}, forward2.normalized(), 1):
				_fire_projectile(dir, contact_damage, _egt_projectile_color(), false, {}, 0.0, global_position)
		_:
			_perform_egt_contact(to_target, distance)


## 抓握大师等"场上还有别人就打不动"的怪。敌人层唯一的无敌判定入口。
## 水平距离（忽略 Y）。抓取判定必须用水平距离：抓握大师悬在 4.2m 高，
## 用三维距离会把"正下方站着"判成很远，等于永远抓不到。
func _flat_distance_to(target: Node3D) -> float:
	var delta := target.global_position - global_position
	delta.y = 0.0
	return delta.length()


## 同房间里是否还有**别的**活着的敌人。
## 两处都用它：`_is_egt_invulnerable()`（有别人时无敌）与
## 抓握大师的 `die_when_others_dead`（全死则自己死）。同一判据只能有一份实现。
func _room_has_other_living_enemy() -> bool:
	if GameplaySpatialRegistry3D == null:
		return false
	var neighbors: Array[Node3D] = GameplaySpatialRegistry3D.query_radius(
		global_position, 60.0, [GameplaySpatialRegistry3D.KIND_ENEMY], [room_id]
	)
	for value in neighbors:
		var other := value as Enemy3D
		if other != null and other != self and other.room_id == room_id and other.ai_state != "dead":
			return true
	return false


func _is_egt_invulnerable() -> bool:
	if not bool(_active_profile.get("invulnerable_while_others_alive", false)):
		return false
	return _room_has_other_living_enemy()


## 逃跑超时消失。**不是死亡**：不喷死亡特效、不结算掉落，但必须走完
## `_die()` 的清房记账（否则房间永远清不掉，门打不开）。
## 用一个标志让 `_die()` 跳过特效与掉落，语义与"被打死"分开。
func _vanish() -> void:
	if ai_state == "dead":
		return
	_vanish_requested = true
	_die()


func receive_healing(amount: int) -> void:
	if ai_state == "dead" or current_hp >= max_hp:
		return
	current_hp = mini(max_hp, current_hp + maxi(0, amount))
	health_changed.emit(self, current_hp, max_hp)
	# 治疗必须走**治疗**飘字（FX02-02）。历史上这里借的是 VFX-DAMAGE-NUMBER-3D 且不带
	# context.text_value ⇒ 回血时会飘一个**红字 "0"**，而 VFX-HEAL-NUMBER-3D 全工程零调用方
	# （2026-09-21 特效审计 P0-1 同源问题）。
	_spawn_heal_number(amount)


func _explode() -> void:
	_active_explosion_committed = true
	_spawn_effect("VFX-EXPLOSION-3D", 1.75)
	if MonsterAIManager != null:
		MonsterAIManager.broadcast_sound_stimulus(global_position, 20.0, "explosion", self)
	for player in get_tree().get_nodes_in_group("player_3d"):
		if player is Node3D and global_position.distance_to((player as Node3D).global_position) <= 3.0 and player.has_method("take_damage"):
			if player.has_method("notify_attacked_by"):
				player.call("notify_attacked_by", self)
			player.call("take_damage", contact_damage, false, ((player as Node3D).global_position - global_position).normalized())
	_die()


## 死亡自爆（远征01 `monster_rules.death_explosion.<kind>`，业主 2026-10-14：胖子僵尸 180）。
##
## **刻意不复用 `_explode()`** —— 那是炸弹果的主动贴近自爆，三条语义都不同：
##   1. 伤害取 `contact_damage`（随楼层缩放/主题倍率漂）→ 本函数用**规格里的固定值**；
##   2. 只伤玩家 → 本函数**敌我通吃**（半径内所有单位，含相邻敌对怪与玩家）；
##   3. 只判 3.0 m → 本函数用规格半径。
##
## 表现（业主 2026-10-14 追加「自爆没有特效」）：走**专属 Prefab** `VFX-DEATH-BLAST-3D`
## （FX01-17，比通用 `VFX-EXPLOSION-3D` 更大更重、并带一盏 BlastLight），
## 随后按规格 `zone` 段在地上留一片**持续伤害场** `DeathBlastZone3D`（FX01-18 视觉，默认 3 秒）。
##
## 级联安全性：本函数给别的怪 `take_damage` 时，若把对方也打死，对方会走自己的
## `_die()` + 自爆；而它反向炸到本怪时会被 `take_damage` 首行的 `ai_state == "dead"`
## 直接挡掉 ⇒ **不存在无限递归**。
## 仇恨不转移：怪物 AI 的目标只从 `player_3d` 组里取，故「怪炸怪」只掉血、不会互殴。
func _detonate_death_explosion() -> void:
	var damage := int(_death_explosion.get("damage", 0))
	var radius := maxf(0.5, float(_death_explosion.get("radius_m", 0.0)))
	var sfx_radius := float(_death_explosion.get("sfx_radius_m", 20.0))
	# 视觉：胖子僵尸的死亡表现 = 小僵尸死亡表现 ×2 + 绿色冲击波（业主 2026-10-14 指定）。
	# ⚠ **表现 ≠ 玩法**：视觉在这一行就出（不管伤害是多少），下面才是伤害结算。
	# 规格里 damage<=0 表示「本关不自爆」—— 那只是不掉血，不是「连死亡表现都不给」。
	# 分开是为了让去掉倒地动画后的胖子僵尸仍有死亡表现（见 `_die()`）。
	_spawn_fat_death_burst(1.0)
	if damage <= 0:
		return
	if radius <= 0.0:
		return
	if sfx_radius > 0.0 and MonsterAIManager != null:
		MonsterAIManager.broadcast_sound_stimulus(global_position, sfx_radius, "explosion", self)
	_damage_allies_in_blast(damage, radius)
	_damage_players_in_blast(damage, radius)
	_spawn_ground_blast_zone(radius)


## 自爆对**敌对单位**的伤害。同房过滤与 `_heal_nearby_allies` / `_strengthen_nearest_enemy`
## 同口径 —— 门是关着的，跨房的怪不该被炸到（也不该被顺带激活）。
func _damage_allies_in_blast(damage: int, radius: float) -> void:
	if GameplaySpatialRegistry3D == null:
		return
	var room_filter: Array[String] = []
	if not room_id.is_empty():
		room_filter.append(room_id)
	for value in GameplaySpatialRegistry3D.query_radius(
		global_position, radius, [GameplaySpatialRegistry3D.KIND_ENEMY], room_filter
	):
		var other := value as Enemy3D
		if other == null or other == self or not is_instance_valid(other):
			continue
		# 已死的（含同帧被前一发炸死的）不再受击，避免重复结算与掉落的二次触发。
		if other.ai_state == "dead" or other.current_hp <= 0:
			continue
		var offset := other.global_position - global_position
		var direction := offset.normalized() if offset.length_squared() > 0.01 else Vector3.UP
		other.take_damage(damage, false, direction)


## 自爆对**玩家**的伤害。距离口径与 `_explode()` 一致（3D 球距离）。
func _damage_players_in_blast(damage: int, radius: float) -> void:
	for player in get_tree().get_nodes_in_group("player_3d"):
		var body := player as Node3D
		if body == null or not is_instance_valid(body):
			continue
		var offset := body.global_position - global_position
		if offset.length() > radius:
			continue
		# 与 `_explode()` 同序：先记仇恨来源（供死亡结算/击杀归属），再结算伤害。
		if body.has_method("notify_attacked_by"):
			body.call("notify_attacked_by", self)
		if body.has_method("take_damage"):
			body.call("take_damage", damage, false, offset.normalized())


## 死亡自爆留在**地上**的持续伤害场（业主 2026-10-14：「在地上留一个持续伤害的范围效果，持续3秒」）。
##
## 只读关卡规格 `monster_rules.death_explosion.<kind>.zone`：
##   - 缺段 / `enabled=false` / `damage_per_tick<=0` ⇒ **一行不生成**，
##     故未配置的关卡（塔楼等）与旧行为逐字一致；
##   - `radius_m` 缺省沿用爆炸半径（同一片杀伤范围，不另立第二份口径）。
##
## 场地是**独立玩法节点**（`DeathBlastZone3D`），自己按周期结算，
## 死亡怪本帧后续被回收也不影响它 —— 它在场景树上、不依赖本怪存活。
func _spawn_ground_blast_zone(radius: float) -> void:
	var zone_cfg := _death_explosion.get("zone", {}) as Dictionary
	if zone_cfg.is_empty() or not bool(zone_cfg.get("enabled", false)):
		return
	var per_tick := int(zone_cfg.get("damage_per_tick", 0))
	if per_tick <= 0:
		return
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_parent()
	if parent == null:
		return
	DeathBlastZone3D.spawn(parent, {
		"origin": global_position,
		"radius": maxf(0.5, float(zone_cfg.get("radius_m", radius))),
		"duration": float(zone_cfg.get("duration_sec", 3.0)),
		"damage_per_tick": per_tick,
		"tick_interval": float(zone_cfg.get("tick_interval_sec", 0.5)),
		"room_id": room_id,
		"color": EnemyAvatar3D.COLORS.get(enemy_kind, Color(1.0, 0.52, 0.18)),
		"source": self,
	})


func take_damage(amount: int, critical := false, hit_direction := Vector3.ZERO, hit_knockback := 0.0, interrupt_movement := true) -> void:
	if ai_state == "dead":
		return
	# 拟态怪：伪装状态下**不吃伤害**，但挨打就现形（原作"被射击才现形"）。
	# 顺序很重要：先现形、再照常结算这一发 —— 否则玩家打中箱子会读成"打空"。
	if _disguised:
		_reveal_disguise()
	if _is_egt_invulnerable():
		avatar.flash_hit()
		_spawn_effect("VFX-IMPACT-3D", 0.82)
		return
	# 受伤窗口：`interrupt` 用它判断「自己受伤就中断施法」（枪歌者）。
	# 放在无敌判定**之后** —— 打不动它的时候不该算"被打断"。
	if _active_profile.has("interrupt"):
		_egt_hurt_window = float(_interrupt_spec().get("hurt_window_sec", 2.5))
	var applied := maxi(1, amount)
	if elite_modifier_id == "Elite.Ricochet" and randf() < 0.30:
		applied = maxi(1, int(applied * 0.5))
		if _target != null and _target.has_method("take_damage"):
			_target.call("take_damage", maxi(1, int(amount * 0.35)), false, -hit_direction)
	if enemy_kind == "shielded" and not _bypass_shield_once and hit_direction.dot(-global_basis.z) < -0.15:
		if randf() < 0.15:
			avatar.flash_hit()
			_spawn_effect("VFX-IMPACT-3D", 0.82)
			return
		applied = maxi(1, int(applied * 0.32))
	if critical:
		applied = maxi(1, int(applied * 1.5))
	current_hp = maxi(0, current_hp - applied)
	health_changed.emit(self, current_hp, max_hp)
	_update_boss_phase()
	_last_hit_direction = hit_direction
	_hit_knockback = maxf(0.0, hit_knockback)
	avatar.flash_hit()
	# 只留一处飘字。历史上这里还有一行 `_spawn_effect("VFX-DAMAGE-NUMBER-3D", 0.72)`
	# 与下一行双发：它不带 context.text_value ⇒ 飘出一个 "0"（2026-09-21 审计 P0-1）。
	_spawn_damage_number(applied, critical, _damage_element)
	if current_hp <= 0:
		_die()
	else:
		if AudioManager != null:
			if critical:
				AudioManager.play_crit_sfx()
			else:
				AudioManager.play_enemy_hit_sfx()
		if _should_begin_elite_escape():
			_begin_elite_escape()
		elif monitor_combat != null:
			monitor_combat.on_damage(applied,critical,hit_knockback,interrupt_movement)
		elif interrupt_movement and (enemy_kind != "fat_zombie03" or critical or hit_knockback >= 0.8 or applied >= max_hp * 0.08):
			transition_to("stagger")


func take_projectile_damage(
	amount: int,
	critical := false,
	hit_direction := Vector3.ZERO,
	tags: Array[String] = [],
	behavior: Dictionary = {},
	attacker: Node3D = null,
	hit_knockback := 0.0
) -> void:
	if ai_state == "dead" or amount <= 0:
		return
	# 伪装 / 无敌同样在这一层先拦：子弹通道与近战通道必须给出**一致的结果**，
	# 否则会出现"枪打不动、近战能砍"（或被反过来）的诡异判定。
	if _disguised:
		_reveal_disguise()
	if _is_egt_invulnerable():
		avatar.flash_hit()
		_spawn_effect("VFX-IMPACT-3D", 0.82)
		return
	if is_instance_valid(attacker):
		notify_attacked_by(attacker)
	_bypass_shield_once = bool(behavior.get("pierce_shield", "armor" in tags or "piercing" in tags))
	if enemy_kind == "shielded" and not _bypass_shield_once and hit_direction.dot(-global_basis.z) < -0.15:
		amount = maxi(1, int(amount * float(behavior.get("shield_damage_scale", 1.0))))
	_damage_element = str(behavior.get("damage_element", ""))
	if _damage_element.is_empty():
		var elements: Dictionary = behavior.get("fate_elements", {})
		for element in ["fire", "ice", "poison"]:
			if elements.has(element):
				_damage_element = element
				break
	take_damage(amount, critical, hit_direction, hit_knockback, hit_knockback > 0.0)
	_damage_element = ""
	_bypass_shield_once = false
	var source: Variant = behavior.get("source_weapon_tree")
	if ai_state == "dead" and is_instance_valid(source):
		source.record_projectile_kill(critical)


func notify_attacked_by(attacker: Node3D) -> void:
	if bool(enemy_data.get("narrative_stationary", false)):
		return
	if MonsterAIManager == null or attacker == null:
		return
	if not _runtime_ai_active:
		set_runtime_active(true)
	MonsterAIManager.notify_enemy_attacked(self, attacker)
	_ai_decision = MonsterAIManager.force_refresh_enemy(self)
	_apply_ai_decision(_ai_decision)
	# 玩家已被作为目标后不再强制重跳 alert：alert 期间会按 0.42s 锁 velocity.move_toward(ZERO)、
	# 造成“被打一下顿一下”的硬直。仇恨已由 notify_enemy_attacked 建立，此处仅保留 chase/telegraph/attack 的合法过渡。
	# alert 路径仍然走（从 idle/patrol/search 发现玩家），由下一帧 physics_process 的 ai_state == "alert" && _state_time > 0.28 自动跳 chase。
	var is_idle_like := ai_state in ["idle", "patrol", "search", "dormant"]
	if _target != null and ai_state not in ["dead", "telegraph", "attack"] and is_idle_like:
		transition_to("alert")


func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = clampf(factor, 0.25, 1.0)
	_slow_timer = maxf(_slow_timer, duration)


func apply_pull(origin: Vector3, strength: float) -> void:
	var direction := origin - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return
	_external_velocity = direction.normalized() * clampf(strength, 0.5, 9.0)
	_external_timer = 0.32


## 近战击退走敌人公开接口，不让玩家动作机直接写 AI 内部速度。
var _melee_stagger_remaining := 0.0

func apply_melee_stagger(duration: float) -> void:
	if current_hp <= 0 or ai_state == "dead" or enemy_kind == "boss" or monitor_combat != null or _elite_escape_active:
		return
	_melee_stagger_remaining = maxf(_melee_stagger_remaining, clampf(duration, 0.0, 0.30))
	transition_to("stagger")


func apply_melee_knockback(direction: Vector3, strength: float, duration := 0.20, strength_cap := 10.5) -> void:
	if ai_state == "dead":
		return
	var planar := direction
	planar.y = 0.0
	if planar.length_squared() <= 0.001:
		return
	_external_velocity = planar.normalized() * clampf(strength, 0.5, clampf(strength_cap,10.5,20.0))
	_external_timer = clampf(duration, 0.08, 0.42)


func apply_fate_element(element: String, params: Dictionary, weapon_damage: int, source: WeaponAssemblyTree, attacker: Node3D) -> void:
	if ai_state == "dead":
		return
	if element == "ice":
		var duration := float(params.get("freeze_duration", 0.5))
		if duration > 0.0:
			if not elite_modifier_id.is_empty() or enemy_kind == "boss":
				duration = float(params.get("freeze_duration_elite", duration * 0.5))
			_fate_freeze_remaining = maxf(_fate_freeze_remaining, duration)
		else:
			apply_slow(1.0 - float(params.get("slow_ratio", 0.35)), float(params.get("slow_duration", 3.0)))
			_fate_ice_slow_active = true
		_sync_fate_visuals()
		return
	var key := element + ("_burst" if params.has("burst_delay") else "")
	var state: Dictionary = _fate_statuses.get(key, {})
	var stacks := mini(int(state.get("stacks", 0)) + 1, int(params.get("max_stacks", 5))) if element == "poison" and not params.has("burst_delay") else 1
	var duration := float(params.get("burst_delay", params.get("dot_duration", 3.0)))
	_fate_statuses[key] = {
		"remaining": duration, "elapsed": float(state.get("elapsed", 0.0)),
		"stacks": stacks, "damage": weapon_damage,
		"ratio": float(params.get("burst_damage_scale", params.get("dot_damage_per_sec", params.get("dot_damage_per_stack", 0.05)))),
		"burst": params.has("burst_delay"), "source": source, "attacker": attacker,
	}

	_sync_fate_visuals()


func _tick_fate_statuses(delta: float) -> void:
	if ai_state == "dead":
		return
	for key in _fate_statuses.keys():
		var state: Dictionary = _fate_statuses[key]
		var active_delta := minf(delta, float(state["remaining"]))
		state["remaining"] = maxf(0.0, float(state["remaining"]) - delta)
		state["elapsed"] = float(state["elapsed"]) + active_delta
		var ticks := 0
		if bool(state["burst"]):
			ticks = 1 if float(state["remaining"]) <= 0.00001 else 0
		else:
			ticks = int(floor(float(state["elapsed"]) + 0.00001))
			state["elapsed"] = float(state["elapsed"]) - ticks
		if ticks > 0:
			var applied := maxi(1, int(round(float(state["damage"]) * float(state["ratio"]) * int(state["stacks"]) * ticks)))
			current_hp = maxi(0, current_hp - applied)
			health_changed.emit(self, current_hp, max_hp)
			_spawn_damage_number(applied, false, "poison" if str(key).begins_with("poison") else "fire")
			if current_hp <= 0:
				var source: Variant = state["source"]
				_die()
				if is_instance_valid(source):
					source.record_projectile_kill(false)
				return
		if float(state["remaining"]) <= 0.00001:
			_fate_statuses.erase(key)


func get_fate_status_snapshot() -> Dictionary:
	return {"elements": _fate_statuses.duplicate(true), "freeze_remaining": _fate_freeze_remaining, "slow_factor": _slow_factor, "slow_remaining": _slow_timer}


func apply_damage_over_time(total_damage: int, duration: float) -> void:
	_dot_damage = maxi(_dot_damage, maxi(1, total_damage))
	_dot_remaining = maxf(_dot_remaining, maxf(0.5, duration))
	_dot_tick = minf(_dot_tick, 0.35)


func _tick_damage_over_time(delta: float) -> void:
	if _dot_remaining <= 0.0 or ai_state == "dead":
		return
	_dot_remaining = maxf(0.0, _dot_remaining - delta)
	_dot_tick -= delta
	if _dot_tick > 0.0:
		return
	_dot_tick = 0.5
	var applied := maxi(1, int(ceil(float(_dot_damage) * 0.2)))
	current_hp = maxi(0, current_hp - applied)
	health_changed.emit(self, current_hp, max_hp)
	avatar.flash_hit()
	_spawn_damage_number(applied, false)
	if current_hp <= 0:
		_die()


func transition_to(state_id: String, reason := "") -> bool:
	if not VALID_STATES.has(state_id) or ai_state == "dead" and state_id != "dead":
		return false
	if monitor_combat != null and not monitor_combat.activation_completed and state_id not in ["dead","dormant","idle","alert"]:
		return false
	if ai_state == state_id:
		return true
	var previous := ai_state
	# 启动过程是「可打断的过渡段」：离开 alert 一律收尾（死亡 / 硬直 / 房间停用 /
	# 失去目标转 search / 回巢）。挂在 transition_to 这一个收口上，而不是往
	# _die / take_damage / set_runtime_active 里各抄一遍 —— 抄漏一处就会出现
	# 「已死还在吼」的假信息，而这正是不该漏的那一种。
	# 唯一的例外是「正常走完转 chase」：那时图标要按自己的 lifetime 播完尾巴，
	# 不能被掐掉（尾巴是「吼 → 打」因果可读性的一部分）。
	if previous == "alert" and state_id != "alert" and state_id != "chase":
		_cancel_monster_startup()
	if previous in ["telegraph", "attack", "recovery"] and state_id not in ["telegraph", "attack", "recovery"]:
		if MonsterAIManager != null:
			MonsterAIManager.release_attack_token(self)
	ai_state = state_id
	if monitor_combat != null:
		if state_id == "telegraph":monitor_combat.begin()
		elif state_id in ["dead","dormant"]:monitor_combat.cancel()
	_last_state_reason = reason if not reason.is_empty() else "%s_to_%s" % [previous, state_id]
	_state_time = 0.0
	if avatar != null:
		avatar.set_ai_state(state_id)
	state_changed.emit(previous, state_id)
	return true


# ── 启动过程（0.30–0.60s：转身 → 吼叫 → 头顶图标 → 攻击）────────────────────
# 设计原文与公式见 docs/v0.1/06A_怪物AI系统完整设计_评审稿.md §6.1.1–§6.1.4。
# 本类是**消费方**：一切时长/尺寸/角速度都从 MonsterStartupProfile 取，不在这里写常量。

## 头顶吼叫图标 Prefab（FX01-16 VFX-MONSTER-ROAR-ICON-3D）。
## 按 14.6 §1.2「Prefab 是特效的唯一出口」，这里 preload Prefab 而不是自己 new 一个
## 同类脚本节点 —— 否则账本登记的路径与实际播放的东西会悄悄脱钩。
const ROAR_ICON_SCENE := preload(
	"res://assets/art/vfx/combat_3d/vfx_monster_roar_icon_root_top3d.tscn"
)


## `alert` 状态逐帧推进。
##
## 返回 **true 表示本帧被启动过程独占** —— 调用方必须立即返回，不得继续跑行动 match。
##
## 抽成具名函数而不是内联在 `_physics_process` 里，是为了让验收能驱动**同一条**代码路径：
## 在 `_physics_process` 里内联时，测试只能自己复刻一遍分支逻辑，那种「测试绿、游戏红」
## 的假绿正是 2026-10-14 这次回归的教训（公式与 Prefab 全对，状态机却把它跨过去）。
func _tick_alert_state(to_target: Vector3, delta: float, alert_duration: float) -> bool:
	if _startup_active:
		_tick_monster_startup(to_target, delta)
		return true
	if _state_time > alert_duration:
		transition_to("chase")
	return false


## 进入启动过程。返回是否真的开始计时。
##
## 三种情况**不启动**，退回原来的 `alert_duration` 口径（行为与接线前一致）：
##   ① Boss：它有自己的完整激活流程，不得叠加（`MonsterStartupProfile.plays_startup`）；
##   ② 本次交战已经吼过一次：脱战静默满 `REARM_AFTER_SECONDS` 才重新武装，
##      否则玩家来回探头会变成「反复吼叫」的噪音；
##   ③ 朝向退化（与玩家几乎重合），算不出有意义的转角。
func _begin_monster_startup(to_target: Vector3) -> bool:
	_startup_active = false
	_roar_icon_fired = false
	if not MonsterStartupProfile.plays_startup(enemy_kind):
		return false
	if not _startup_armed:
		return false
	var planar := Vector3(to_target.x, 0.0, to_target.z)
	if planar.length_squared() <= 0.0001:
		return false
	# 转角一律先归一到最短转向区间：359° 在几何上是「朝左差 1°」，不是「转身 359°」。
	# `angle_difference` 直接给最短差，等价于 MonsterStartupProfile.normalize_delta_yaw，
	# 且两处都过同一条断言（见 verify_monster_startup_roar 的归一化负向自测）。
	var desired := Vector3(-planar.x, 0.0, -planar.z)
	var desired_yaw := atan2(desired.x, desired.z)
	var current_yaw := atan2(-global_basis.z.x, -global_basis.z.z)
	_startup_delta_yaw_deg = rad_to_deg(angle_difference(current_yaw, desired_yaw))
	# 抖动只抽一次：转身速率要从同一个值反推，重抽会让两段时长对不上。
	_startup_jitter = _startup_rng.randf_range(0.0, MonsterStartupProfile.STARTUP_JITTER_MAX)
	_startup_turn_sec = MonsterStartupProfile.turn_seconds(_startup_delta_yaw_deg)
	_startup_total = MonsterStartupProfile.startup_seconds(_startup_delta_yaw_deg, _startup_jitter)
	_startup_active = true
	_startup_armed = false
	return true


## 启动过程逐帧推进：段 A 转身 → 段 B 起吼（弹一次图标）→ 到点转 chase。
##
## 计时用 `_state_time`：它由 `transition_to("alert")` 在进入时归零，语义正好是
## 「本次 alert 已持续多久」= 启动过程已走多久，不必再养第二个时钟。
func _tick_monster_startup(to_target: Vector3, delta: float) -> void:
	if not _startup_active:
		return
	# 段 A：朝玩家恒定转速转身。速率由「转角必须在本段内转完」反推，
	# 不随帧率变化，也不为了凑总时长去乱改转速。
	var planar := Vector3(to_target.x, 0.0, to_target.z)
	if planar.length_squared() > 0.0001:
		var desired_yaw := atan2(-planar.x, -planar.z)
		var rate := MonsterStartupProfile.turn_rate_deg_per_sec(
			_startup_delta_yaw_deg, _startup_jitter
		)
		rotation.y = rotate_toward(rotation.y, desired_yaw, deg_to_rad(rate) * delta)
	if not _roar_icon_fired and _state_time >= _startup_turn_sec:
		_fire_roar_icon()
	# 全程制动：这段的意义就是给玩家一个可反应的窗口，不能边走边吼。
	_brake_planar(delta * 18.0)
	_commit_motion(delta)
	if _state_time >= _startup_total:
		_startup_active = false
		transition_to("chase", "startup_finished")


## 起吼：在头顶血条槽根上方弹出图标。
##
## 挂到 `_overhead_health_root` 下是刻意复用既有契约 —— 那个根节点 `top_level = true`
## 且每帧由 `_position_overhead_health_bar()` 跟位，所以图标自动获得
## 「跟着怪 / 不随怪转身 / 不被身体挡住」三条性质，与头顶血条同一套定位代码，
## 不新增第二份会漂移的实现。
##
## 尺寸按体型：`icon_edge = 头顶血条宽 × 0.42`，钳制 [0.45, 1.20] m。
func _fire_roar_icon() -> void:
	if _overhead_health_root == null or not is_instance_valid(_overhead_health_root):
		# 头顶锚点还没建好：**不置 fired**，下一帧重试，否则这次起吼会被静默吞掉。
		return
	_roar_icon_fired = true
	if _roar_icon != null and is_instance_valid(_roar_icon):
		_roar_icon.dismiss()
		_roar_icon = null
	var icon := ROAR_ICON_SCENE.instantiate() as VfxMonsterRoarIcon3D
	if icon == null:
		return
	_overhead_health_root.add_child(icon)
	var bar_size := _overhead_health_size
	var edge := MonsterStartupProfile.icon_edge_m(bar_size.x)
	var offset_y := MonsterStartupProfile.icon_offset_y_m(bar_size.x, bar_size.y)
	var hold := MonsterStartupProfile.icon_hold_seconds(
		_startup_delta_yaw_deg, _startup_jitter
	)
	# 先 activate（会把 global_position 设成传入值），**后写 position** 把它钉回
	# 「血条槽根 + 偏移」。顺序不能反 —— 反了就会被 activate 覆盖成世界原点。
	icon.activate(
		_overhead_health_root.global_position,
		Color.WHITE,
		edge,
		{
			"hold_seconds": hold,
			"fade_seconds": MonsterStartupProfile.ICON_FADE_SECONDS,
		},
	)
	icon.position = Vector3(0.0, offset_y, 0.0)
	_roar_icon = icon


## 中断启动过程：撤掉头顶图标并清掉计时。
##
## 「已死还在吼」是假信息。死亡 / 硬直 / 房间停用 / 失去目标都必须走这里；
## 调用点收敛在 `transition_to` 离开 alert 的那一处，不往各处分抄。
func _cancel_monster_startup() -> void:
	var had_icon := _roar_icon != null and is_instance_valid(_roar_icon)
	if not _startup_active and not had_icon:
		return
	_startup_active = false
	_roar_icon_fired = false
	if had_icon:
		# `dismiss()` 幂等且会发出提前退场信号；本类不订阅该信号，
		# 所以基类 `_retire()` 会走 queue_free —— 不会每吼一次泄漏一个节点。
		_roar_icon.dismiss()
	_roar_icon = null


func get_state_snapshot() -> Dictionary:
	var shape_snapshot := {}
	if collision_shape != null and collision_shape.shape is CylinderShape3D:
		var cylinder := collision_shape.shape as CylinderShape3D
		shape_snapshot = {"radius": cylinder.radius, "height": cylinder.height}
	var illumination_snapshot := (
		illumination_sensor.get_snapshot() if illumination_sensor != null else {
			"illumination_state": EnemyIllumination3D.STATE_DARKNESS,
			"valid_illumination_states": EnemyIllumination3D.VALID_STATES.duplicate(),
		}
	)
	return {
		"enemy_kind": enemy_kind, "state": ai_state, "valid_states": VALID_STATES.duplicate(),
		# 启动过程事实（供验收断言「怪物是不是真的停了 0.30–0.60s 才冲」）。
		"startup_active": _startup_active,
		"startup_armed": _startup_armed,
		"startup_total_sec": _startup_total,
		"startup_turn_sec": _startup_turn_sec,
		"startup_delta_yaw_deg": _startup_delta_yaw_deg,
		"roar_icon_fired": _roar_icon_fired,
		"roar_icon_active": _roar_icon != null and is_instance_valid(_roar_icon),
		"disengage_elapsed_sec": _disengage_elapsed,
		"hp": current_hp, "max_hp": max_hp, "room_id": room_id, "is_3d": true,
		"elite_modifier_id": elite_modifier_id, "boss_phase": boss_phase,
		"boss_content_id": str(enemy_data.get("boss_content_id", "")),
		"boss_presentation_asset_id": str(enemy_data.get("presentation_asset_id", "")),
		"boss_arena_asset_id": str(enemy_data.get("arena_asset_id", "")),
		"elite_id": elite_id,
		"elite_behavior_id": elite_behavior_id,
		"elite_level": elite_level,
		"elite_translation_id": elite_translation_id,
		"elite_stolen_modules": elite_stolen_modules.duplicate(true),
		"elite_escape_active": _elite_escape_active,
		"elite_escape_elapsed": _elite_escape_elapsed,
		"elite_sidearm_attack_interval": _elite_sidearm_attack_interval(),
		"elite_attack_counter": _elite_attack_counter,
		"elite_behavior_trigger_count": _elite_behavior_trigger_count,
		"elite_encounter_instance_id": elite_encounter_instance_id,
		"source_hp_scale": _source_hp_scale, "source_damage_scale": _source_damage_scale,
		"hp_balance_multiplier": BOSS_HP_MULTIPLIER if enemy_kind == "boss" else NORMAL_HP_MULTIPLIER,
		"move_speed_multiplier": GLOBAL_MOVE_SPEED_MULTIPLIER,
		"boss_size_multiplier": BOSS_SIZE_MULTIPLIER if enemy_kind == "boss" else 1.0,
		"base_size_multiplier": DEFAULT_BASE_SIZE_MULTIPLIER,
		"presentation_scale_multiplier": DEFAULT_BASE_SIZE_MULTIPLIER * _kind_scale_multiplier * _variant_scale_multiplier,
		"world_collision_radius": float(shape_snapshot.get("radius", 0.0)) * scale.x,
		"overhead_health_bar": _overhead_health_root != null,
		"overhead_health_world_locked": _overhead_health_root != null and _overhead_health_root.top_level,
		"overhead_health_bar_size": _overhead_health_size,
		"overhead_health_ratio": _overhead_health_ratio,
		"overhead_delayed_health_ratio": _overhead_delayed_health_ratio,
		"overhead_health_bar_scale": _overhead_health_bar_scale,
		"elite_health_bar": not _elite_health_bar_profile.is_empty(),
		"elite_health_bar_name": _elite_name_label.text if _elite_name_label != null else "",
		"elite_health_bar_profile": _elite_health_bar_profile.duplicate(true),
		"overhead_health_camera_billboard": (
			_overhead_health_sprite != null
			and _overhead_health_sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED
		),
		"collision_profile": shape_snapshot,
		"ambush_triggered": _ambush_triggered,
		"illumination_state": illumination_snapshot.get("illumination_state", EnemyIllumination3D.STATE_DARKNESS),
		"illumination": illumination_snapshot,
		"illumination_move_multiplier": get_illumination_move_multiplier(),
		"illumination_attack_frequency_multiplier": get_attack_frequency_multiplier(),
		"sunlight_damage_per_second": float(max_hp) * SUNLIGHT_MAX_HP_DAMAGE_PER_SECOND,
		"illumination_ui_state": get_illumination_state(),
		"illumination_ui_color": ILLUMINATION_UI_COLORS.get(get_illumination_state(), Color.WHITE),
		"illumination_ui_text": _illumination_ui_text(get_illumination_state()),
		"illumination_ui_before_health_bar": _illumination_status_label != null,
		"ai_decision": _ai_decision.duplicate(true),
		"ai_memory": MonsterAIManager.get_enemy_snapshot(self).get("memory", []) if MonsterAIManager != null else [],
		"reason_code": str(_ai_decision.get("reason_code", "")),
		"state_enter_reason": _last_state_reason,
		"threat_score": float(_ai_decision.get("threat_score", 0.0)),
		"last_attack_result": _last_attack_result,
		"stuck_recovery_count": _stuck_recovery_count,
		"navigation_agent_ready": _navigation_agent != null,
		"attack_token_channel": str(MonsterAIManager.get_enemy_snapshot(self).get("attack_token_channel", "")) if MonsterAIManager != null else "",
		"behavior_role": _behavior_role(),
		"component_snapshot": avatar.get_component_snapshot() if avatar != null else {},
	}


func _elite_sidearm_attack_interval() -> int:
	var base_interval := maxi(1, int(_elite_growth_profile.get("sidearm_base_attack_interval", 3)))
	var step_levels := maxi(1, int(_elite_growth_profile.get("sidearm_interval_step_levels", 4)))
	var minimum_interval := maxi(1, int(_elite_growth_profile.get("sidearm_min_attack_interval", 1)))
	return maxi(minimum_interval, base_interval - int(maxi(0, elite_level - 1) / step_levels))


func get_illumination_state() -> String:
	return (
		illumination_sensor.illumination_state
		if illumination_sensor != null
		else EnemyIllumination3D.STATE_DARKNESS
	)


func force_refresh_illumination(commit_immediately := true) -> void:
	if illumination_sensor != null:
		illumination_sensor.force_refresh(commit_immediately)
	if MonsterAIManager != null:
		MonsterAIManager.invalidate_enemy(self)


func get_illumination_snapshot() -> Dictionary:
	return illumination_sensor.get_snapshot() if illumination_sensor != null else {}


func find_nearby_dark_position(radius: float, candidate_count: int) -> Vector3:
	return (
		illumination_sensor.find_nearby_dark_position(radius, candidate_count)
		if illumination_sensor != null
		else Vector3.ZERO
	)


func get_illumination_move_multiplier() -> float:
	return (
		ARTIFICIAL_LIGHT_MOVE_MULTIPLIER
		if get_illumination_state() == EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT
		else 1.0
	)


func get_effective_move_speed() -> float:
	return move_speed * get_illumination_move_multiplier() * _haste_factor


func get_attack_frequency_multiplier() -> float:
	return (
		ARTIFICIAL_LIGHT_ATTACK_FREQUENCY_MULTIPLIER
		if get_illumination_state() == EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT
		else 1.0
	)


func _tick_illumination_effects(delta: float) -> void:
	if ai_state == "dead":
		return
	if get_illumination_state() != EnemyIllumination3D.STATE_SUNLIGHT:
		_illumination_damage_accumulator = 0.0
		return
	_illumination_damage_accumulator += delta
	while _illumination_damage_accumulator >= 1.0 and ai_state != "dead":
		_illumination_damage_accumulator -= 1.0
		var applied := maxi(1, int(ceil(float(max_hp) * SUNLIGHT_MAX_HP_DAMAGE_PER_SECOND)))
		current_hp = maxi(0, current_hp - applied)
		health_changed.emit(self, current_hp, max_hp)
		avatar.flash_hit()
		_spawn_damage_number(applied, false)
		if current_hp <= 0:
			_die()


func _illumination_ui_text(state: String) -> String:
	return {
		EnemyIllumination3D.STATE_DARKNESS: "暗",
		EnemyIllumination3D.STATE_ARTIFICIAL_LIGHT: "亮",
		EnemyIllumination3D.STATE_SUNLIGHT: "太阳",
	}.get(state, "暗")


func _apply_ai_decision(decision: Dictionary) -> void:
	var target_id := int(decision.get("target_instance_id", 0))
	var resolved := instance_from_id(target_id) as Node3D if target_id > 0 else null
	if is_instance_valid(resolved) and float(resolved.get("current_hp")) > 0.0:
		_target = resolved
	elif not (
		enemy_kind == "ambusher"
		and _ambush_triggered
		and is_instance_valid(_target)
		and global_position.distance_to(_target.global_position) <= 4.4
	):
		_target = null
	var stimulus := decision.get("stimulus_position", Vector3.ZERO) as Vector3
	if stimulus != Vector3.ZERO:
		_last_known_target_position = stimulus


func _on_illumination_state_changed(previous: String, current: String, context: Dictionary) -> void:
	_on_self_health_changed(self, current_hp, max_hp)
	if not _runtime_ai_active and current != EnemyIllumination3D.STATE_DARKNESS:
		set_runtime_active(true)
	if MonsterAIManager != null:
		MonsterAIManager.invalidate_enemy(self)
	illumination_state_changed.emit(self, previous, current, context)


func _on_tree_exiting() -> void:
	if MonsterAIManager != null:
		MonsterAIManager.unregister_enemy(self)


func _ensure_navigation_agent() -> void:
	if _navigation_agent != null:
		return
	_navigation_agent = NavigationAgent3D.new()
	_navigation_agent.name = "NavigationAgent3D"
	_navigation_agent.path_height_offset = 0.0
	_navigation_agent.path_desired_distance = 0.35
	_navigation_agent.target_desired_distance = 0.55
	_navigation_agent.radius = float(EnemyAvatar3D.get_footprint_profile(enemy_kind).get("radius", 0.8)) * 0.72
	_navigation_agent.avoidance_enabled = false
	add_child(_navigation_agent)


func _navigation_direction(target_position: Vector3, fallback_offset: Vector3) -> Vector3:
	var fallback := fallback_offset
	fallback.y = 0.0
	# 未烘焙导航的房间不创建 Agent；导航图真正可用后再惰性实例化。
	# 这样 30 只怪的常见房间不会凭空增加 30 个常驻节点。
	var navigation_map := get_world_3d().navigation_map
	if (
		_navigation_agent == null
		and NavigationServer3D.map_get_iteration_id(navigation_map) > 0
		and not NavigationServer3D.map_get_regions(navigation_map).is_empty()
	):
		_ensure_navigation_agent()
	if _navigation_agent == null or not _navigation_agent.is_inside_tree():
		return fallback.normalized()
	_navigation_agent.target_position = target_position
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) <= 0 or _navigation_agent.is_navigation_finished():
		return fallback.normalized()
	var next_position := _navigation_agent.get_next_path_position()
	var path_offset := next_position - global_position
	path_offset.y = 0.0
	return path_offset.normalized() if path_offset.length_squared() > 0.001 else fallback.normalized()


## 水平位移的唯一写入口。转向、刹车、击退和分离推挤都走这里，
## 保证没有一条通路会顺手改动 `velocity.y` —— 垂直方向只归重力管。
func _steer_planar(target: Vector3, weight: float) -> void:
	var current := Vector3(velocity.x, 0.0, velocity.z)
	var planar_target := Vector3(target.x, 0.0, target.z)
	current = current.lerp(planar_target, clampf(weight, 0.0, 1.0))
	velocity.x = current.x
	velocity.z = current.z


func _brake_planar(amount: float) -> void:
	var planar := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, amount)
	velocity.x = planar.x
	velocity.z = planar.z


func _stop_planar() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _push_planar(vector: Vector3) -> void:
	velocity.x += vector.x
	velocity.z += vector.z


func _apply_gravity(delta: float) -> void:
	# 浮空怪（空尖弹 / 三色书怪 / 枪法师 / 枪精灵 / 抓握大师）不吃重力：
	# 它们在世界里是"悬停"的，掉到地上会毁掉"浮空"这个形态语言。
	# 只对**声明了 `hover`** 的复刻怪生效，其余怪的重力逐字不变。
	if _is_egt_kind() and bool(_active_profile.get("hover", false)):
		_pin_hover_height(delta)
		return
	if is_on_floor():
		# 极小负值让 floor snap 保持接触；不会把无位移的怪沿斜坡推走。
		velocity.y = FLOOR_STICK_MPS
	else:
		velocity.y = maxf(velocity.y - GRAVITY_MPS2 * delta, -TERMINAL_FALL_SPEED_MPS)


## 悬停在「出生点上方 `hover_height_m`」（默认 1.6m）。
## 用 lerp 而不是直接赋值：房间地板若不齐平，硬贴会让怪一半埋进地面。
func _pin_hover_height(delta: float) -> void:
	if not _home_initialized:
		return
	var target_y := _home_position.y + _egt_hover_height()
	global_position.y = lerpf(global_position.y, target_y, minf(1.0, delta * 6.0))
	velocity.y = 0.0


## 悬停高度。抓握大师要悬在**玩家头顶**（更高），所以它走 `grab.hover_height_m`，
## 其余浮空怪走 `hover_height_m`，都没写就按 1.6m。
func _egt_hover_height() -> float:
	var grab_spec: Variant = _active_profile.get("grab", null)
	if grab_spec is Dictionary:
		return float((grab_spec as Dictionary).get("hover_height_m", 4.2))
	return float(_active_profile.get("hover_height_m", 1.6))


## 碰撞柱半径 × 当前缩放，与 `get_state_snapshot().world_collision_radius` 同源。
func get_world_body_radius() -> float:
	if collision_shape == null or not (collision_shape.shape is CylinderShape3D):
		return 0.8
	var cylinder := collision_shape.shape as CylinderShape3D
	return cylinder.radius * maxf(scale.x, scale.z)


## 掉出可行走层：判定为死亡，走标准死亡流程（掉落、死亡特效、房间计数、精英名册结算）。
## **先落回出生点再 `_die()`** 是有意为之：`Dungeon3D._on_enemy_killed` 拿敌人当前位置
## 投递地面掉落，而掉落落点只做 ±3~4m 的向下支撑探测 —— 在虚空里探不到承重面，
## 奖励会留在够不着的半空。落回出生点是同一房间内的保证可行走点。
func _die_from_fall_out() -> void:
	if ai_state == "dead":
		return
	if MonsterAIManager != null:
		MonsterAIManager.release_attack_token(self)
	velocity = Vector3.ZERO
	_target = null
	global_position = _home_position
	_die()


## 怪与怪的水平分离。只查空间索引里的同类，不遍历整棵树：注册表已按 16m 分桶，
## 常见房间只命中本格，几十只怪也不会退化成全表两两比较。
## **按固定相位降频重算**：邻居查询本身是这整套逻辑里最贵的一步，所以每
## `SEPARATION_INTERVAL_FRAMES` 帧才算一次，中间帧沿用上一次的推力向量。
func _apply_separation(planar_velocity: Vector3) -> Vector3:
	if GameplaySpatialRegistry3D == null:
		return planar_velocity
	if _separation_phase < 0:
		# 相位按实例 ID 固定错开，避免全场怪在同一帧集体查询造成尖峰。
		_separation_phase = absi(get_instance_id()) % SEPARATION_INTERVAL_FRAMES
	if Engine.get_physics_frames() % SEPARATION_INTERVAL_FRAMES == _separation_phase:
		_separation_push = _compute_separation_push()
	var result := planar_velocity + _separation_push
	return Vector3(result.x, 0.0, result.z)


## 单次分离推力的实际计算，只在重算帧被调用。
func _compute_separation_push() -> Vector3:
	var self_radius := get_world_body_radius()
	var neighbors: Array[Node3D] = GameplaySpatialRegistry3D.query_radius(
		global_position,
		self_radius + SEPARATION_PROBE_MARGIN_M,
		[GameplaySpatialRegistry3D.KIND_ENEMY]
	)
	if neighbors.is_empty():
		return Vector3.ZERO
	var push := Vector3.ZERO
	var counted := 0
	for node in neighbors:
		if counted >= SEPARATION_NEIGHBOR_LIMIT:
			break
		var other := node as Enemy3D
		if other == null or other == self or other.ai_state == "dead":
			continue
		var offset := global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		var min_distance := (
			(self_radius + other.get_world_body_radius()) * SEPARATION_RADIUS_SCALE
		)
		if min_distance <= 0.0 or distance >= min_distance:
			continue
		counted += 1
		if distance <= 0.001:
			# 完全重合时按实例 ID 取一个固定切向拆开：确定性、不用随机数，
			# 也不会因为除零产生 NaN 速度。
			var angle := float(absi(get_instance_id()) % 360) * 0.0174532925199433
			offset = Vector3(cos(angle), 0.0, sin(angle))
		else:
			offset = offset / distance
		push += offset * (1.0 - distance / min_distance)
	if push.length_squared() <= 0.000001:
		return Vector3.ZERO
	var push_speed := get_effective_move_speed() * SEPARATION_WEIGHT * minf(push.length(), 1.0)
	return push.normalized() * push_speed


## 推进的唯一出口：先让同伴把水平速度推开，再由重力决定垂直速度。
func _commit_motion(delta: float) -> void:
	var planar := _apply_separation(Vector3(velocity.x, 0.0, velocity.z))
	velocity.x = planar.x
	velocity.z = planar.z
	_apply_gravity(delta)
	move_and_slide()


func _apply_local_avoidance(desired_velocity: Vector3, target_offset: Vector3) -> Vector3:
	if desired_velocity.length_squared() <= 0.001 or get_world_3d() == null:
		return desired_velocity
	var direction := desired_velocity.normalized()
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.45,
		global_position + Vector3.UP * 0.45 + direction * 1.15,
		1,
		[get_rid()]
	)
	query.collide_with_areas = false
	if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return desired_velocity
	var tangent := Vector3(-direction.z, 0.0, direction.x) * _avoidance_sign
	if _stuck_time > 0.38:
		_avoidance_sign *= -1.0
	var target_direction := target_offset.normalized()
	return (tangent * 0.88 + target_direction * 0.22).normalized() * desired_velocity.length()


func _track_stuck_recovery(delta: float, intended_velocity: Vector3) -> void:
	var moved := global_position.distance_to(_last_motion_position)
	_last_motion_position = global_position
	if intended_velocity.length() < 0.2 or moved > 0.025:
		_stuck_time = maxf(0.0, _stuck_time - delta * 2.0)
		return
	_stuck_time += delta
	if _stuck_time < 0.8:
		return
	_stuck_time = 0.0
	_stuck_recovery_count += 1
	_avoidance_sign *= -1.0
	_steer_planar(
		Vector3(-intended_velocity.z, 0.0, intended_velocity.x).normalized()
		* get_effective_move_speed(),
		1.0
	)


func _recovery_duration() -> float:
	if _active_profile.has("recovery"):
		return float(_active_profile["recovery"])
	return 0.62 if enemy_kind == "boss" else 0.48 if enemy_kind in ["shielded", "exploder"] else 0.34


func _next_boss_skill() -> String:
	if _boss_skill_bag.is_empty() or _boss_skill_index >= _boss_skill_bag.size():
		_boss_skill_bag.clear()
		var phase_bags := enemy_data.get("boss_phase_skill_bags", {}) as Dictionary
		var configured_bag: Array = phase_bags.get(boss_phase, phase_bags.get(str(boss_phase), [])) as Array
		if configured_bag.is_empty():
			configured_bag = (
				["volley", "summon", "burst", "volley"]
				if boss_phase >= 2
				else ["volley", "summon", "volley"]
			)
		_boss_skill_bag.assign(configured_bag)
		# 固定旋转量来自行动种子/实例数据，不连续重复同一高压技能。
		var rotation := absi(int(enemy_data.get("floor", 0)) + room_id.hash()) % _boss_skill_bag.size()
		for _index in range(rotation):
			_boss_skill_bag.append(_boss_skill_bag.pop_front())
		_boss_skill_index = 0
	var result := _boss_skill_bag[_boss_skill_index]
	_boss_skill_index += 1
	return result


func _perform_boss_skill(skill_id: String, to_target: Vector3) -> void:
	var accent: Color = enemy_data.get("boss_accent", Color(1.0, 0.20, 0.08)) as Color
	match skill_id:
		"summon", "summon_scribes", "summon_cinders", "summon_echoes":
			summon_requested.emit(self, 2 if boss_phase < 3 else 3)
		"archive_fan":
			_fire_projectile_volley(to_target, contact_damage, accent, 5, 0.16)
		"index_beam":
			_fire_projectile_volley(to_target, int(round(contact_damage * 1.35)), accent, 3, 0.055, true)
		"archive_storm":
			_fire_projectile_volley(to_target, int(round(contact_damage * 0.82)), accent, 9, 0.23, true)
		"molten_volley":
			_fire_projectile_volley(to_target, contact_damage, accent, 4, 0.13, true)
		"hammer_drive":
			_external_velocity = to_target.normalized() * 8.6
			_external_timer = 0.30
			if is_instance_valid(_target) and global_position.distance_to(_target.global_position) <= 3.6:
				if _target.has_method("notify_attacked_by"):
					_target.call("notify_attacked_by", self)
				_target.call("take_damage", int(round(contact_damage * 1.55)), false, to_target.normalized())
		"furnace_burst":
			_fire_projectile_volley(to_target, int(round(contact_damage * 1.18)), accent, 8, 0.26, true)
		"choir_wave":
			_fire_projectile_volley(to_target, contact_damage, accent, 6, 0.20)
		"silence_chord":
			_fire_projectile_volley(to_target, int(round(contact_damage * 0.90)), accent, 3, 0.11, true)
			if is_instance_valid(_target) and _target.has_method("apply_silence"):
				_target.call("apply_silence", 2.2)
		"echo_burst", "burst":
			_fire_projectile_volley(to_target, contact_damage, accent, 7, 0.28, true)
		_:
			_fire_projectile_volley(to_target, contact_damage, accent, 3 if boss_phase >= 2 else 1, 0.14, true)


func _apply_unique_elite_attack_behavior(to_target: Vector3) -> void:
	if elite_behavior_id.is_empty():
		return
	_elite_attack_counter += 1
	var level_scale := 1.0 + float(maxi(0, elite_level - 1)) * 0.04
	match elite_behavior_id:
		"armed_rush":
			var base_interval := maxi(1, int(_elite_growth_profile.get("sidearm_base_attack_interval", 3)))
			var step_levels := maxi(1, int(_elite_growth_profile.get("sidearm_interval_step_levels", 4)))
			var minimum_interval := maxi(1, int(_elite_growth_profile.get("sidearm_min_attack_interval", 1)))
			var interval := maxi(minimum_interval, base_interval - int(maxi(0, elite_level - 1) / step_levels))
			if _elite_attack_counter % interval == 0:
				var stolen: Dictionary = elite_stolen_modules.back() if not elite_stolen_modules.is_empty() else {}
				var shot_count := 2 + int(stolen.get("shot_count_budget", 0))
				var traits := stolen.get("bullet_traits", []) as Array
				_fire_projectile_volley(
					to_target,
					int(contact_damage * 0.55 * level_scale),
					Color(0.95, 0.56, 0.16),
					clampi(shot_count, 2, 5),
					0.08,
					"explosive" in traits
				)
		"bullet_devourer":
			if _elite_attack_counter % 3 == 0:
				_fire_projectile_volley(to_target, int(contact_damage * 0.72 * level_scale), Color(0.78, 0.28, 0.94), 3, 0.16)
		"rotating_carapace":
			_external_velocity = Vector3(-to_target.z, 0.0, to_target.x).normalized() * 3.2
			_external_timer = 0.22
		"hive_network":
			if _elite_attack_counter % 2 == 0:
				summon_requested.emit(self, mini(4, 1 + elite_level / 4))
		"renewing_mines":
			_fire_projectile_volley(to_target, int(contact_damage * 0.45 * level_scale), Color(1.0, 0.34, 0.05), mini(7, 3 + elite_level / 3), 0.30, true)
		"false_burrow_routes":
			var feint_sign := -1.0 if _elite_attack_counter % 2 == 0 else 1.0
			_external_velocity = Vector3(-to_target.z, 0.0, to_target.x).normalized() * 7.5 * feint_sign
			_external_timer = 0.26
		"mirror_sector":
			if _elite_attack_counter % 2 == 1:
				_fire_projectile_volley(to_target, int(contact_damage * 0.60), Color(0.66, 0.92, 1.0), 5, 0.22)
		"weapon_phase_swap":
			var phase_count: int = [1, 3, 5][_elite_attack_counter % 3]
			_fire_projectile_volley(to_target, int(contact_damage * level_scale), Color(1.0, 0.22, 0.42), phase_count, 0.12, phase_count >= 5)
		"seven_attack_rule":
			if _elite_attack_counter % 7 == 0:
				_fire_projectile_volley(to_target, int(contact_damage * 0.75 * level_scale), Color(0.98, 0.84, 0.18), 7, 0.24, true)
		"attachment_echo":
			if _elite_attack_counter % 2 == 0:
				summon_requested.emit(self, 2)
		"escape_route":
			if _elite_attack_counter % 2 == 0:
				_external_velocity = -to_target.normalized() * (7.0 + minf(2.0, elite_level * 0.2))
				_external_timer = 0.34
		"three_crowns":
			_fire_projectile_volley(to_target, int(contact_damage * 0.68 * level_scale), Color(0.92, 0.75, 0.20), boss_phase * 2 + 1, 0.20, boss_phase >= 2)
		_:
			return
	_elite_behavior_trigger_count += 1


func _behavior_role() -> String:
	return str({
		"melee_chaser": "rush_melee",
		"ranged_caster": "strafe_three_shot_volley",
		"summoner": "summon_and_heal_support",
		"shielded": "frontal_block_tank",
		"exploder": "proximity_charge_and_fragments",
		"ambusher": "buried_trigger_and_lunge",
		"boss": "phased_volley_and_summon",
	}.get(enemy_kind, "rush_melee"))


func _telegraph_duration() -> float:
	if _active_profile.has("telegraph"):
		return float(_active_profile["telegraph"])
	if enemy_kind == "exploder":
		return 0.9
	if enemy_kind == "ambusher":
		return 0.46
	if enemy_kind == "boss":
		return 0.62
	return 0.38


func _die() -> void:
	if ai_state == "dead":
		return
	# —— 「消失」不是「死亡」（逃跑超时的钥匙小子 / 运气小子）——
	# 仍然必须走完清房记账（`killed.emit`），但**不喷死亡特效、不掉掉落**：
	# 玩家看到的是它传送走了，而不是被打爆。这两件事在同一函数里分岔，
	# 是为了保证「房间能不能开门」只认一处记账，不会因为加了逃跑型而漏。
	if _vanish_requested:
		_clear_fate_visuals()
		transition_to("dead")
		_pending_volleys.clear()
		collision_layer = 0
		collision_mask = 0
		_runtime_ai_active = false
		set_physics_process(false)
		if _overhead_health_root != null:
			_overhead_health_root.visible = false
		killed.emit(self, get_enemy_data())
		queue_free()
		return
	_clear_fate_visuals()
	transition_to("dead")
	if AudioManager != null:
		AudioManager.play_enemy_die_sfx()
	if elite_modifier_id == "Elite.SpawnOnDeath":
		summon_requested.emit(self, 3)
	elif elite_modifier_id == "Elite.Parasite":
		_strengthen_nearest_enemy()
	if enemy_kind == "exploder":
		if not _active_explosion_committed:
			_spawn_death_fragments()
	# 关卡级死亡自爆（远征01 胖子僵尸）。放在 `killed.emit` 之前 —— 自爆炸死的怪
	# 也必须各自走完自己的 `_die()` + `killed`（掉落不能因为「死于自爆」而漏结算）。
	# 规格非空 ⇒ 表现 + 伤害结算一起走；规格为空但本怪是胖子僵尸 ⇒ 只留**表现**
	# （见 `_detonate_death_explosion`：视觉那一行不受 damage 影响）。
	if not _death_explosion.is_empty():
		_detonate_death_explosion()
	elif enemy_kind == "fat_zombie03":
		_spawn_fat_death_burst(1.0)
	# —— 远征03 复刻怪的死亡行为（2026-10-29）——
	# 三条都放在「关卡级死亡自爆」之后、`killed.emit` 之前：
	# 子代与弹幕必须在「本怪还算活着」的窗口内发出，否则房间可能在
	# `killed.emit` 之后立刻判清、把门放开，玩家还没看到分裂出来的小怪就走出去了。
	# 连发队列先清 —— 尸体不该继续开火。
	_pending_volleys.clear()
	if _active_profile.has("death_burst"):
		_perform_death_burst()
	if _active_profile.has("death_split"):
		_perform_death_split()
	collision_layer = 0
	collision_mask = 0
	# 死亡表现分两路：僵尸三兄弟**没有尸体** ⇒ 不进死亡显隐组
	# （那个组是给 PlayerVision3D 管尸体显隐用的；没有尸体还留在组里只会留个空壳）。
	var no_corpse := uses_no_corpse_death()
	var goo_death := uses_goo_death_burst()
	if not no_corpse:
		add_to_group(GROUP_DEATH_VISUAL_3D)
	_runtime_ai_active = false
	process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(false)
	set_process(true)
	if _overhead_health_root != null:
		_overhead_health_root.visible = false
	if goo_death:
		_spawn_goo_death_burst()
	elif enemy_kind != "fat_zombie03":
		# 胖子僵尸的死亡表现已在上面的自爆分支里出过（表现 ≠ 玩法：不管有没有伤害规格）
		_spawn_effect("VFX-EXPLOSION-3D" if enemy_kind == "boss" else "VFX-IMPACT-3D", 1.4 if enemy_kind == "boss" else 0.8)
	killed.emit(self, get_enemy_data())
	if not elite_id.is_empty() and EliteRosterService != null:
		EliteRosterService.settle(elite_id, elite_encounter_instance_id, "killed", {
			"floor_number": int(enemy_data.get("floor_number", enemy_data.get("floor", 0))),
			"room_id": room_id,
		})
	if no_corpse:
		# **去掉倒地动画**（业主 2026-10-14，两轮点名：先小僵尸/警察僵尸，再胖子僵尸）：
		# 不再等 `get_formal_death_duration()` 把「dead」段（倒地）播完、也不再留尸体
		# —— 模型本帧即收起、节点本帧回收，死亡表现完全交给各自的特效。
		_retire_goo_death_visual()
	elif avatar != null and (avatar.has_formal_normal() or monitor_combat != null):
		if MonsterAIManager != null:
			MonsterAIManager.unregister_enemy(self)
		remove_from_group("enemy_3d")
		remove_from_group("damageable_3d")
		var death_tween := create_tween()
		death_tween.tween_interval(avatar.get_formal_death_duration())
		death_tween.tween_callback(queue_free)
	else:
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3(1.25, 0.05, 1.25), 0.34)
		tween.tween_callback(queue_free)


## 本怪是否走「绿色方块爆开」死亡表现（小僵尸 / 警察僵尸，见 `GOO_DEATH_KINDS`）。
func uses_goo_death_burst() -> bool:
	return GOO_DEATH_KINDS.has(enemy_kind)


## 本怪死亡后**没有尸体、也不播倒地动画**（僵尸三兄弟，见 `ZOMBIE_KINDS`）。
## 与 `uses_goo_death_burst()` 是**两条不同的轴**，刻意分开命名：
##   前者管「用哪个特效」，本函数管「要不要留一具躯干」。
## 胖子僵尸两条都为真值之一（自爆表现 + 不留尸体）。
func uses_no_corpse_death() -> bool:
	return ZOMBIE_KINDS.has(enemy_kind)


## 本怪是否为**战斗命中特效**的分流对象：打中它时用 FX01-20（`VFX-GOO-HIT-3D`，
## v002 = 金属火星造型 + 僵尸绿）而不是 FX01-21（金色金属火星）。
## 调用方是 `Projectile3D._spawn_hit_effect()` 与 `PlayerMeleeCombat3D._spawn_hit_feedback()`
## —— 两边都读这一个入口，避免「枪击是一种读法、近战又是另一种」。
func uses_goo_hit_burst() -> bool:
	return ZOMBIE_KINDS.has(enemy_kind)


## 把碰撞壳上的命中点**摆到模型面上**：`hit_point` 是物理相交点（落在碰撞壳表面），
## `surface_normal` 是被击面的**外**法线（`KinematicCollision3D.get_normal()` 口径）。
##
## 算法（**按模型实测几何现算**，不是写死的常数）：
##   ① 取「命中高度那一层的横截面 + 全高 Y」的世界包围盒（`_visual_world_hit_box`）；
##   ② 从命中点沿**外法线反向**射一条线，用逐轴夹逼求它**进入**盒子的距离 `travel`；
##   ③ 退让量 = `travel + HIT_EFFECT_BITE_M`（摆到盒面上再往里咬 0.03m，保证落点在肉里）。
##
## ⚠ `travel == 0` 是**必须单独处理**的一侧，不是异常：碰撞壳比模型**窄**时 ——
## 胖子僵尸 X 向：壳世界半径 0.770、模型半宽 **1.839** —— 命中点本来就在模型**里面**，
## 这时 **不要再推**（推了就埋进胖身子，读成「从肚子里炸」）。
## 反过来壳比模型**宽**时（小僵尸 +Z：壳 0.714、模型半宽 0.332）`travel > 0`，落点被收进肉里 ——
## 业主看到的「悬空」正是缺了这一步。
##
## ⚠ 所以**不能**给退让量加「下限 = 0.20」这类固定值：那会在壳比模型窄的那一侧继续往深处推。
## 实测：去掉 `travel == 0` 守卫、改写成 `max(0.20, ...)` 时，胖子僵尸 X 向被推深到
## 0.712 + 0.20 = 0.912。
##
## 为什么不能全用整只怪的包围盒：那是**全高**的并集，头顶的丸子头 / 脚边的件会把 Z 半宽
## 撑到 0.622，而胸口那一层实际只有 0.332 ⇒ 退让量少算 0.29m，落点停在壳边上。
## **真渲染实拍就是这样**：解析读数说「距模型 0.000」，画面里特效却明显在圆柱壳外圈。
## 所以 X/Z 必须取**命中高度那一层**的横截面。
##
## 退化情形（模型盒为空 / 法线不可用）按「从怪体中心指向命中点」定外法线，并退回兜底固定量；
## 连怪体中心都与命中点重合时原样返回（不动比乱动安全）。
## ⚠ 只对怪调用：墙面 / 掩体不存在「模型比碰撞盒小」的问题。
func hit_effect_anchor(hit_point: Vector3, surface_normal: Vector3) -> Vector3:
	var outward := surface_normal
	if outward.length_squared() < 0.0001:
		outward = hit_point - global_position
	if outward.length_squared() < 0.0001:
		return hit_point
	var direction := outward.normalized()

	var box := _visual_world_hit_box(hit_point)
	if box.size.length_squared() < 0.0001:
		# 模型盒不可用（未就绪 / 无网格）⇒ 只能退回固定量
		return hit_point - direction * HIT_EFFECT_INSET_M

	var travel := _ray_box_enter_distance(box, hit_point, -direction)
	if travel < 0.0:
		# 射线沿法线反向打不到模型盒（理论上不该发生）⇒ 只咬一点点，不要盲推
		return hit_point - direction * HIT_EFFECT_BITE_M
	# `travel == 0` ⇒ 命中点**已经在模型盒内**（碰撞壳比模型窄的一侧，例如胖子僵尸 X 向：
	# 壳世界半径 0.770、模型半宽 1.839）⇒ **不要再往里推**，否则埋进胖身子读成「从肚子里炸」。
	# 实测：去掉这条守卫时，胖子僵尸 X 向被推深到 0.712 + 0.20 = 0.912。
	var inset := 0.0
	if travel > 0.0:
		inset = minf(travel + HIT_EFFECT_BITE_M, HIT_EFFECT_MAX_INSET_M)
	return hit_point - direction * inset


## 射线 `origin + t * direction`（t ≥ 0）**进入** AABB 的距离；打不到返回 -1，起点已在盒内返回 0。
##
## ⚠ 必须用这个**逐轴 slab 夹逼**，不能用「盒心支撑函数」那种近似：
## 支撑平面是在盒子某个角上相切的，命中点一旦**偏离盒心**（怪体中心 Y 与命中高度差半截，
## 侧面打时 X/Z 也偏），把落点摆到支撑平面上只保证「在平面上」，不保证「在盒子范围内」——
## 实测会残留 0.32~0.54m 的悬空（警察僵尸 / 胖子僵尸的斜向都中招）。
func _ray_box_enter_distance(box: AABB, origin: Vector3, direction: Vector3) -> float:
	var lower := box.position
	var upper := box.position + box.size
	var t_enter := -INF
	var t_exit := INF
	for axis in 3:
		var start: float = origin[axis]
		var step: float = direction[axis]
		var lo: float = lower[axis]
		var hi: float = upper[axis]
		if absf(step) < 0.000001:
			# 该轴与盒面平行：起点不在这条板内 ⇒ 永远打不到
			if start < lo or start > hi:
				return -1.0
			continue
		var t0 := (lo - start) / step
		var t1 := (hi - start) / step
		if t0 > t1:
			var swap := t0
			t0 = t1
			t1 = swap
		t_enter = maxf(t_enter, t0)
		t_exit = minf(t_exit, t1)
		if t_enter > t_exit:
			return -1.0
	if t_enter < 0.0:
		return 0.0
	return t_enter


## 模型可视件在**本节点局部**空间的包围盒。
##
## ⚠ **不做缓存**（这条踩过坑，值得写下来）：正式模型是**异步挂上** `avatar` 的。
## 一旦把「第一次调用时算出来的盒子」缓存下来，就可能缓存到**只有占位件 / 只挂了一半**
## 的那一版 ⇒ 之后再也不重算，贴肉量按错误的体型算，特效时对时错（真渲染里表现为
## 「还是悬在壳边上」，而单测里因为调用时机不同却是对的 —— 两边永远对不上）。
## 本函数只在**命中时**被调一次（不是每帧），树也浅（十来个节点），重算的开销可以忽略。
##
## ⚠ 而且**必须按命中高度切一层薄片**，不能用整只怪的包围盒（见 `_visual_local_slab_aabb`）。
func _visual_local_aabb() -> AABB:
	var box := AABB()
	var has := false
	for mesh_node in _collect_meshes(avatar):
		if mesh_node.mesh == null:
			continue
		if not _is_shown_under_avatar(mesh_node):
			continue
		# 换算到本节点局部空间（去掉 Enemy3D 自身的缩放/旋转/位移）
		var local := global_transform.affine_inverse() * mesh_node.global_transform * mesh_node.get_aabb()
		if not has:
			box = local
			has = true
		else:
			box = box.merge(local)
	return box


## **命中高度处**的模型横截面包围盒（本节点局部空间，Y 只留一条薄带）。
##
## ⚠ 为什么不能直接用整只怪的包围盒：那是**全高**的并集 —— 只要头顶的丸子头往后凸一点、
## 或者脚边有件宽东西，整盒的 Z 半宽就被它们撑到 0.62，而**胸口那一层**实际只有 0.33。
## 于是「还差多少才贴到身上」被算小了 0.29m，特效停在壳边上 ——
## **真渲染实拍就是这样**：解析读数说「距模型 0.000」，画面里特效却明显在圆柱壳外圈。
## 判据与观感对不上的根因就在这：读者要的是「贴在**被打那一层**的肉上」。
##
## ⚠ 本函数只给「横截面」用（`_visual_local_hit_box` 会把 Y 换回全高）。
## **不要**直接拿这条薄带去跑射线：薄带在 Y 上只有 ±0.21m，斜向的射线会在碰到侧面之前
## 先从 Y 面穿出去 ⇒ 判成「打不到模型」⇒ 退让量掉成 0、落点重新悬空
## （实测：零法线兜底的斜向射线因此差 0.354m）。
func _visual_local_slab_aabb(local_y: float, band: float) -> AABB:
	var low := local_y - band
	var high := local_y + band
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for mesh_node in _collect_meshes(avatar):
		if mesh_node.mesh == null:
			continue
		if not _is_shown_under_avatar(mesh_node):
			continue
		var local := global_transform.affine_inverse() * mesh_node.global_transform * mesh_node.get_aabb()
		# 该件的 Y 区间与这条薄带不重叠 ⇒ 它长在别的高度上，不属于这一层的体型
		if local.position.y + local.size.y < low or local.position.y > high:
			continue
		min_x = minf(min_x, local.position.x)
		min_z = minf(min_z, local.position.z)
		max_x = maxf(max_x, local.position.x + local.size.x)
		max_z = maxf(max_z, local.position.z + local.size.z)
	if min_x > max_x or min_z > max_z:
		# 这一层没有任何可视件（例如命中点高过头顶）⇒ 退回整只怪的包围盒
		return _visual_local_aabb()
	return AABB(
		Vector3(min_x, low, min_z),
		Vector3(maxf(0.001, max_x - min_x), maxf(0.001, band * 2.0), maxf(0.001, max_z - min_z))
	)


## 射线求交用的「命中盒」：**X/Z 取命中高度那一层的横截面**，**Y 用整只怪的全高**。
##
## 两个空间各取所需，缺一不可：
##   · X/Z 用横截面 ⇒ 贴肉量按「被打那一层的肉有多宽」算（而不是被头顶/脚部的宽件撑大后算小）；
##   · Y 用全高     ⇒ 斜向射线不会在碰到侧面之前先从薄带的上/下面穿出去。
func _visual_local_hit_box(local_y: float, band: float, full: AABB) -> AABB:
	var slab := _visual_local_slab_aabb(local_y, band)
	return AABB(
		Vector3(slab.position.x, full.position.y, slab.position.z),
		Vector3(slab.size.x, full.size.y, slab.size.z)
	)


## 该网格是否**真的在画**：自身可见，且直到 `avatar`（不含）之前的每一层祖先都可见。
## ⚠ 必须滤两层（都踩过坑）：
##   ① 占位件（`_core` / `_shell` / `_appendages`）在挂上正式模型后会被隐藏，网格数据还在 ——
##      不过滤会把包围盒从 0.90×1.30×0.67 撑到 2.31×1.86×1.78（**2.6 倍**），贴肉量永远算不足；
##   ② 只滤**自身** `visible` 还不够：模型内部还有**中间节点被隐藏**的件（炮管 / 爪 / LOD 变体），
##      它们自身可见、祖先被关掉 ⇒ 实际没在画。实测漏掉这层会让小僵尸盒子 Z 从 0.67 虚胖到 0.92、
##      警察僵尸 +Z 虚胖到 1.54，**正面打仍差 0.18~0.24m**。
## 刻意**不**看 `avatar` 自身的可见性 —— 它在出生弹出 / 死亡收起时会整体关掉。
func _is_shown_under_avatar(mesh_node: MeshInstance3D) -> bool:
	if not mesh_node.visible:
		return false
	var node := mesh_node.get_parent()
	while node != null and node != avatar:
		if node is Node3D and not (node as Node3D).visible:
			return false
		node = node.get_parent()
	return true


## 包围盒换算到世界空间（本节点缩放是均匀的 ⇒ 变换后的 AABB 仍然贴合）
func _visual_world_aabb() -> AABB:
	return global_transform * _visual_local_aabb()


## 命中点所在高度那一层的模型横截面（世界空间），Y 取全高 —— 供射线求交用。
## `HIT_EFFECT_SLAB_BAND_M` 是薄带的半高：太薄会让薄带落在网格之间的空隙上（读成「这一层没东西」），
## 太厚又会把别的高度上的宽件算进来（回到整盒的老问题）。0.30m ≈ 躯干一层。
func _visual_world_hit_box(hit_point: Vector3) -> AABB:
	var local_point := global_transform.affine_inverse() * hit_point
	return global_transform * _visual_local_hit_box(
		local_point.y, HIT_EFFECT_SLAB_BAND_M, _visual_local_aabb()
	)


func _collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root == null:
		return found
	if root is MeshInstance3D:
		found.append(root as MeshInstance3D)
	for child in root.get_children():
		found.append_array(_collect_meshes(child))
	return found


## 生成 FX01-19 `VFX-ZOMBIE-GOO-DEATH-3D`：出生点取**胸口**（与 `_spawn_effect` 同口径），
## 并把 `floor_y = 脚底行走面` 交给特效 —— 它靠这个高度用解析式求飞溅粒子的落点、
## 并把「地上的液体」与「绿色冲击波」铺在真正的地面上。
## ⚠ 塔楼楼层向下建造（98F ≈ −1176 m），`floor_y` **必须**是真实高度，
## 绝不能让特效自己兜底成 0（那就是 2026-09-22 弹壳「实机看不见」的同一类缺陷）。
func _spawn_goo_death_burst() -> void:
	_spawn_zombie_death_effect(VfxPool3D.FX01_ZOMBIE_GOO_DEATH, GOO_DEATH_EFFECT_SIZE)


## 生成 FX01-17 `VFX-DEATH-BLAST-3D`（胖子僵尸死亡：小僵尸死亡表现 ×2 + 绿色冲击波）。
## `radius` 只用于「有没有规格」的判断，**不再决定视觉尺寸** —— 尺寸走
## `FAT_DEATH_EFFECT_SIZE`（业主指定的固定倍率）。伤害结算与视觉是两条独立的线，见
## `_detonate_death_explosion`。
func _spawn_fat_death_burst(radius: float) -> void:
	if radius <= 0.0:
		return
	_spawn_zombie_death_effect(VfxPool3D.FX01_DEATH_BLAST, FAT_DEATH_EFFECT_SIZE)


## 僵尸死亡特效的共用出口：胸口出生 + `floor_y = 脚底行走面`。
## 两件（FX01-17 / FX01-19）走同一个函数，保证「地面高度真源」只有一处口径。
func _spawn_zombie_death_effect(asset_id: StringName, size: float) -> void:
	if get_tree().current_scene == null:
		return
	var world_position := global_position + Vector3(0, EFFECT_SPAWN_LIFT, 0)
	var color: Color = EnemyAvatar3D.COLORS.get(enemy_kind, Color.WHITE)
	var context := {"floor_y": global_position.y}
	var vfx_pools: Array = get_tree().get_nodes_in_group("vfx_pool_3d")
	if not vfx_pools.is_empty() and vfx_pools[0] is VfxPool3D:
		(vfx_pools[0] as VfxPool3D).acquire(asset_id, world_position, color, size, context)
		return
	# 无池时独立实例化作后备（与 `_spawn_effect` 同口径）
	var effect := VfxPool3D.create_unpooled(asset_id)
	if effect != null:
		get_tree().current_scene.add_child(effect)
		effect.activate(world_position, color, size, context)


## 收起模型并本帧回收：这条路**没有倒地动画、也没有尸体**。
## 与旧路径的差别是「不再 `tween_interval(get_formal_death_duration())`」——
## 小僵尸的倒地段实测 2.4s、胖子僵尸 2.6s，留着它就等于没去掉倒地动画。
func _retire_goo_death_visual() -> void:
	if MonsterAIManager != null:
		MonsterAIManager.unregister_enemy(self)
	remove_from_group("enemy_3d")
	remove_from_group("damageable_3d")
	remove_from_group(GROUP_DEATH_VISUAL_3D)
	if avatar != null:
		avatar.visible = false
	set_process(false)
	queue_free()


func _should_begin_elite_escape() -> bool:
	return (
		not elite_id.is_empty()
		and not _elite_escape_active
		and bool(_elite_growth_profile.get("escape_enabled", false))
		and current_hp > 0
		and float(current_hp) / float(maxi(1, max_hp)) <= float(_elite_growth_profile.get("escape_health_ratio", 0.20))
	)


func _begin_elite_escape() -> void:
	_elite_escape_active = true
	_elite_escape_elapsed = 0.0
	_elite_escape_origin = global_position
	if MonsterAIManager != null:
		MonsterAIManager.release_attack_token(self)
	transition_to("return", "unique_elite_escape")
	if _elite_name_label != null:
		_elite_name_label.text = "%s · 撤离中" % str(_elite_health_bar_profile.get("display_name", enemy_data.get("name", "唯一精英")))


func _tick_elite_escape(delta: float) -> void:
	_elite_escape_elapsed += delta
	var escape_direction := Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	if _target != null and is_instance_valid(_target):
		escape_direction = global_position - _target.global_position
		escape_direction.y = 0.0
	if escape_direction.length_squared() <= 0.01:
		escape_direction = Vector3.FORWARD
	escape_direction = escape_direction.normalized()
	var speed_multiplier := maxf(1.0, float(_elite_growth_profile.get("escape_speed_multiplier", 1.55)))
	_steer_planar(
		escape_direction * get_effective_move_speed() * speed_multiplier,
		minf(1.0, delta * 7.0)
	)
	_commit_motion(delta)
	rotation.y = lerp_angle(rotation.y, atan2(-escape_direction.x, -escape_direction.z), minf(1.0, delta * 10.0))
	if _elite_escape_elapsed >= maxf(0.5, float(_elite_growth_profile.get("escape_duration", 4.2))):
		_complete_elite_escape()


func _complete_elite_escape() -> void:
	if not _elite_escape_active or ai_state == "dead":
		return
	var weapon_snapshot: Dictionary = {}
	if _target != null and is_instance_valid(_target) and _target.has_method("get_weapon_snapshot"):
		weapon_snapshot = _target.call("get_weapon_snapshot") as Dictionary
	var context := {
		"floor_number": int(enemy_data.get("floor_number", enemy_data.get("floor", 0))),
		"room_id": room_id,
		"weapon_snapshot": weapon_snapshot,
		"distance_travelled": global_position.distance_to(_elite_escape_origin),
	}
	var settled: bool = (
		EliteRosterService == null
		or EliteRosterService.settle(elite_id, elite_encounter_instance_id, "escaped", context)
	)
	if not settled:
		# 长期档案保存失败时精英不能从世界消失；保留撤离态并按短间隔重试，
		# 让名册预约、场景事实和玩家看到的结果保持一致。
		_elite_escape_elapsed = maxf(0.0, float(_elite_growth_profile.get("escape_duration", 4.2)) - 0.8)
		return
	_elite_escape_active = false
	transition_to("dead", "unique_elite_escaped")
	collision_layer = 0
	collision_mask = 0
	escaped.emit(self, context)
	queue_free()


func force_complete_elite_escape_for_test() -> void:
	_complete_elite_escape()


func complete_elite_escape_after_external_settlement(context: Dictionary) -> bool:
	if ai_state == "dead" or elite_id.is_empty():
		return false
	_elite_escape_active = false
	transition_to("dead", "unique_elite_escaped_after_player_kill")
	collision_layer = 0
	collision_mask = 0
	escaped.emit(self, context.duplicate(true))
	queue_free()
	return true


func _spawn_death_fragments() -> void:
	for index in range(8):
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / 8.0)
		_fire_projectile(direction, maxi(3, int(contact_damage * 0.28)), Color(1.0, 0.42, 0.10))


func can_absorb_projectile(_tags: Array[String]) -> bool:
	return elite_modifier_id == "Elite.BulletEater" and _absorb_cooldown <= 0.0


func on_projectile_absorbed(absorbed_damage: int) -> void:
	_absorb_cooldown = 0.75
	if _target != null:
		_fire_projectile(
			_target.global_position - global_position,
			maxi(4, absorbed_damage / 2),
			Color(0.78, 0.28, 0.94)
		)


func apply_elite_boon(multiplier: float) -> void:
	max_hp = int(max_hp * multiplier)
	current_hp = mini(max_hp, int(current_hp * multiplier + max_hp * 0.15))
	contact_damage = int(contact_damage * multiplier)
	move_speed *= minf(1.2, multiplier)
	_variant_scale_multiplier *= 1.08
	_apply_presentation_scale()
	health_changed.emit(self, current_hp, max_hp)


func _strengthen_nearest_enemy() -> void:
	var best: Enemy3D = null
	var best_distance := 12.0
	var candidates: Array[Node3D] = (
		GameplaySpatialRegistry3D.query_radius(
			global_position, best_distance, [GameplaySpatialRegistry3D.KIND_ENEMY], [room_id]
		)
		if GameplaySpatialRegistry3D != null
		else []
	)
	for value in candidates:
		var candidate := value as Enemy3D
		if candidate == null or candidate == self or candidate.room_id != room_id or candidate.ai_state == "dead":
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	if best != null:
		best.apply_elite_boon(1.3)


func _update_boss_phase() -> void:
	if enemy_kind != "boss" or max_hp <= 0:
		return
	var ratio := float(current_hp) / float(max_hp)
	var next_phase := 3 if ratio <= 0.30 else 2 if ratio <= 0.65 else 1
	if monitor_combat != null:next_phase = 3 if ratio <= 0.33 else 2 if ratio <= 0.66 else 1
	if next_phase <= boss_phase:
		return
	boss_phase = next_phase
	_boss_skill_bag.clear()
	_boss_skill_index = 0
	if monitor_combat != null:
		boss_phase_changed.emit(self,boss_phase)
		return
	attack_cooldown *= 0.82
	move_speed *= 1.10
	if boss_phase == 3:
		summon_requested.emit(self, 3)
	boss_phase_changed.emit(self, boss_phase)


func _spawn_effect(asset_id: StringName, size: float) -> void:
	if get_tree().current_scene == null:
		return
	var world_position := global_position + Vector3(0, EFFECT_SPAWN_LIFT, 0)
	var color: Color = EnemyAvatar3D.COLORS.get(enemy_kind, Color.WHITE)
	# FX01-* 战斗反馈特效：走 VfxPool3D 新体系
	var vfx_pools: Array = get_tree().get_nodes_in_group("vfx_pool_3d")
	if not vfx_pools.is_empty() and vfx_pools[0] is VfxPool3D:
		(vfx_pools[0] as VfxPool3D).acquire(asset_id, world_position, color, size)
		return
	# 兼容旧 CombatEffectPool3D（待 14.6 §6 迁移完成后删除）
	var pools := get_tree().get_nodes_in_group("combat_effect_pool_3d")
	if not pools.is_empty() and pools[0] is CombatEffectPool3D:
		(pools[0] as CombatEffectPool3D).acquire(
			str(asset_id).to_lower(), color, size, world_position
		)
		return
	# 直接独立实例化作为后备
	var effect := VfxPool3D.create_unpooled(asset_id)
	if effect != null:
		get_tree().current_scene.add_child(effect)
		effect.activate(world_position, color, size)


## 飘字逐发随机幅度（业主 2026-10-16：「不要太整齐，带一些随机」）。
##
## 为什么随机必须活在**调用方**而不是特效脚本：FX02-01 / FX02-02 是被逐帧断言驱动的对象
## （验收与视觉探针都手动步进到固定时刻再断言姿态 / 高度），把 `randf()` 埋进 `_on_activate`
## 会让那些断言变成随机红。⇒ 随机在本文件生成、经 context 传给特效；
##    特效对同一 context **逐位可复现**，源码里不出现 `randf()`。
##    这条纪律与 FX01-06 抛壳随机化（vfx skill §5.5.3）完全同源。
##
## 每项都是"把随机化之前特效里的那个固定点摊成一团"。漂移用 Vector2(X 幅度, Z 幅度)：
## 只沿镜头水平面散布，Y 由上升距离负责。
const DMG_NUM_SPAWN_JITTER := Vector3(0.16, 0.06, 0.16)
const DMG_NUM_RISE_SCALE := Vector2(0.85, 1.30)
const DMG_NUM_HORIZONTAL_DRIFT := Vector2(0.22, 0.22)
const DMG_NUM_POP_SCALE := Vector2(1.28, 1.48)
const DMG_NUM_DURATION_SCALE := Vector2(0.90, 1.18)
const HEAL_NUMBER_PREFIX := "+"


func _spawn_damage_number(amount: int, critical: bool, element := "") -> void:
	if amount <= 0 or get_tree().current_scene == null:
		return
	var spawn_position := _damage_number_spawn_position()
	# 元素色与暴击金色统一由 DamageStyle 管理。
	var dmg_color: Color = DamageStyle.damage_color(critical, element)
	# FX02-01 伤害飘字：走 VfxPool3D 新体系
	var vfx_pools: Array = get_tree().get_nodes_in_group("vfx_pool_3d")
	if not vfx_pools.is_empty() and vfx_pools[0] is VfxPool3D:
		(vfx_pools[0] as VfxPool3D).acquire(
			VfxPool3D.FX02_DAMAGE_NUMBER, spawn_position, dmg_color, 1.0,
			_damage_number_context(amount, critical, str(amount))
		)
		return
	# 兼容旧 DAMAGE_NUMBER_SCRIPT（待 14.6 §6 迁移完成后删除）
	var damage_number := DAMAGE_NUMBER_SCRIPT.new() as Node3D
	get_tree().current_scene.add_child(damage_number)
	damage_number.global_position = spawn_position
	damage_number.call("configure", amount, critical, element)


## 治疗飘字（FX02-02）。与伤害飘字共用同一套随机幅度和出生点口径，
## 只有颜色（治疗绿，由特效自己定，不由调用方指定）与文本（"+N"）不同。
func _spawn_heal_number(amount: int) -> void:
	if amount <= 0 or get_tree().current_scene == null:
		return
	var spawn_position := _damage_number_spawn_position()
	var vfx_pools: Array = get_tree().get_nodes_in_group("vfx_pool_3d")
	if not vfx_pools.is_empty() and vfx_pools[0] is VfxPool3D:
		(vfx_pools[0] as VfxPool3D).acquire(
			VfxPool3D.FX02_HEAL_NUMBER, spawn_position, VfxHealNumber3D.HEAL_COLOR, 1.0,
			_damage_number_context(amount, false, HEAL_NUMBER_PREFIX + str(amount))
		)
		return
	# 池不可用时退化为兜底脚本 —— 它画不出治疗绿，但至少把数值显示出来（不静默）。
	var heal_number := DAMAGE_NUMBER_SCRIPT.new() as Node3D
	get_tree().current_scene.add_child(heal_number)
	heal_number.global_position = spawn_position
	heal_number.call("configure", amount, false)


## 飘字出生点：怪物头顶。按体型轮廓高度 × 当前根缩放换算，与血条/吼叫图标同一口径。
func _damage_number_spawn_position() -> Vector3:
	var footprint := EnemyAvatar3D.get_footprint_profile(enemy_kind)
	var world_height := float(footprint.get("height", 1.3)) * maxf(scale.y, 0.01)
	return global_position + Vector3.UP * (world_height + 0.72)


## 逐发随机 context。键的口径见 `src/vfx/VfxDamageNumber3D.gd` 头注。
## `magnitude` 必须单独传：特效的字号 / 描边分级读它，而不是去解析 `text_value`
## —— 解析字符串会让 "+12" 这类带前缀的文本被分错档。
func _damage_number_context(amount: int, critical: bool, text: String) -> Dictionary:
	return {
		"text_value": text,
		"magnitude": amount,
		"critical": critical,
		"spawn_offset": Vector3(
			randf_range(-DMG_NUM_SPAWN_JITTER.x, DMG_NUM_SPAWN_JITTER.x),
			randf_range(-DMG_NUM_SPAWN_JITTER.y, DMG_NUM_SPAWN_JITTER.y),
			randf_range(-DMG_NUM_SPAWN_JITTER.z, DMG_NUM_SPAWN_JITTER.z)
		),
		"rise_scale": randf_range(DMG_NUM_RISE_SCALE.x, DMG_NUM_RISE_SCALE.y),
		"drift": Vector3(
			randf_range(-DMG_NUM_HORIZONTAL_DRIFT.x, DMG_NUM_HORIZONTAL_DRIFT.x),
			0.0,
			randf_range(-DMG_NUM_HORIZONTAL_DRIFT.y, DMG_NUM_HORIZONTAL_DRIFT.y)
		),
		"pop_scale": randf_range(DMG_NUM_POP_SCALE.x, DMG_NUM_POP_SCALE.y),
		"duration_scale": randf_range(DMG_NUM_DURATION_SCALE.x, DMG_NUM_DURATION_SCALE.y),
	}


## Visuals consume the existing gameplay state; stacking never creates more particles.
func _sync_fate_visuals() -> void:
	if ai_state == "dead":
		_clear_fate_visuals()
		return
	if _slow_timer <= 0.0:
		_fate_ice_slow_active = false
	_set_fate_visual(VfxPool3D.FX01_FATE_FIRE, _fate_statuses.has("fire"))
	_set_fate_visual(VfxPool3D.FX01_FATE_POISON, _fate_statuses.has("poison") or _fate_statuses.has("poison_burst"))
	_set_fate_visual(VfxPool3D.FX01_FATE_FROST, _fate_freeze_remaining > 0.0 or _fate_ice_slow_active)

func _set_fate_visual(asset_id: StringName, enabled: bool) -> void:
	var current: Variant = _fate_visuals.get(asset_id)
	if not enabled:
		if is_instance_valid(current):
			current.finish()
		_fate_visuals.erase(asset_id)
		return
	if is_instance_valid(current):
		return
	var footprint := EnemyAvatar3D.get_footprint_profile(enemy_kind)
	var visual_size := clampf(float(footprint.get("height", 1.3)) / 1.3 * absf(global_basis.y.length()), 0.65, 2.0)
	var context := {"follow": self, "follow_local_offset": Vector3.ZERO}
	var pools := get_tree().get_nodes_in_group("vfx_pool_3d")
	var visual: VfxEffectBase3D
	if not pools.is_empty() and pools[0] is VfxPool3D:
		visual = (pools[0] as VfxPool3D).acquire(asset_id, global_position, Color.WHITE, visual_size, context)
	else:
		visual = VfxPool3D.create_unpooled(asset_id)
		if visual != null:
			get_parent().add_child(visual)
			visual.activate(global_position, Color.WHITE, visual_size, context)
	if visual != null:
		_fate_visuals[asset_id] = visual

func _clear_fate_visuals() -> void:
	for visual in _fate_visuals.values():
		if is_instance_valid(visual):
			visual.finish()
	_fate_visuals.clear()

func _exit_tree() -> void:
	_clear_fate_visuals()
