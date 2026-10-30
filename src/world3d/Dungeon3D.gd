class_name Dungeon3D
extends Node3D
## 四主题关卡共用的 3D 运行时。MapThemeProfile 保留原玩法配方，DungeonTheme3D 负责空间美术；
## 随机地图、房间内容、敌人、撤离和结算只有这一套实现。

const EQUIPMENT_TRANSACTION_SERVICE = preload("res://src/game/EquipmentTransactionService.gd")
const ROOM_GRAPH_RUNTIME_SCRIPT = preload("res://src/world3d/RoomGraphRuntime.gd")
const RUN_PERSISTENCE_SERVICE = preload("res://src/world3d/RunPersistenceService.gd")
const HUD_PRESENTER_SCRIPT = preload("res://src/ui/HUDPresenter3D.gd")
const RUNTIME_REWARD_COORDINATOR_SCRIPT = preload("res://src/rewards/RuntimeRewardCoordinator.gd")
const REWARD_SINK_SCRIPT = preload("res://src/rewards/RewardSink.gd")
const RUN_MERCHANT_SERVICE_SCRIPT = preload("res://src/game/RunMerchantService.gd")
const FATE_ECONOMY_SERVICE_SCRIPT = preload("res://src/game/FateEconomyService.gd")
const SPAWN_BOX_CATALOG_SCRIPT = preload("res://src/map/SpawnBoxCatalog.gd")
const ENCOUNTER_EVENT_DIRECTOR_SCRIPT = preload("res://src/world3d/EncounterEventDirector3D.gd")
const ENCOUNTER_EVENT_HOST_SCRIPT = preload("res://src/world3d/EncounterEventHost3D.gd")
const AVATAR_CUSTOMIZATION_PERSISTENCE = preload(
	"res://src/player3d/customization/AvatarCustomizationPersistence.gd"
)

signal generation_completed(snapshot: Dictionary)
signal run_completed(success: bool, summary: Dictionary)
signal kill_recorded()
signal room_cleared(room_data)
## 本房**首领已阵亡**。与 `room_cleared` 刻意分开：后者还要求增援与波次全清。
## 需要的场合（Boss房02 竞技场门控「Boss 一死就开闸」）只认这条。
signal room_boss_defeated(room_id: String)
signal room_entered(room_data)
signal backpack_equipment_changed(snapshot: Dictionary)
signal encounter_event_started(snapshot: Dictionary)
signal encounter_event_stage_started(snapshot: Dictionary, stage_index: int)
signal encounter_event_finished(snapshot: Dictionary)

const ROOM_SCENE: PackedScene = preload("res://assets/art/environments/dungeon_3d/env_dungeon_runtime_kit_top3d.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const EXTRACTION_SCENE: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_extraction_beacon_root_top3d.tscn")
const KEY_SCRIPT := preload("res://src/world3d/RoomKeyPickup3D.gd")
## 传送支线管理器（支线秘密房间设计）。只在房表声明了 `secret_site` 的关卡上实例化。
const SECRET_BRANCH_SCRIPT := preload("res://src/world3d/SecretBranch3D.gd")
## 子图房型表走 L3 加载器（与生成器/校验器同一份读取口径，不另写文件解析）。
const LEVEL_PLAN_LOADER := preload("res://src/map/LevelPlanLoader.gd")
const GROUND_LOOT_SCRIPT := preload("res://src/world3d/GroundLootPickup3D.gd")
const WORKBENCH_SCENE: PackedScene = preload("res://scenes/WorkbenchPanel.tscn")
const WEAPON_PRESENTATION_SCENE: PackedScene = preload("res://scenes/WeaponAssemblyTreePanel.tscn")
const CORRIDOR_FLOOR_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_floor_segment.tscn")
const CORRIDOR_WALL_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_wall_segment.tscn")
const CORRIDOR_CEILING_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_ceiling_segment.tscn")
const CORRIDOR_STAIR_TREAD_PREFAB: PackedScene = preload("res://assets/art/props/dungeon_3d/prp_corridor_stair_tread.tscn")
const CODE_HUD_GLYPH_SCRIPT := preload("res://src/ui/CodeHUDGlyph.gd")
const ITEM_MODEL_ICON_SCENE: PackedScene = preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn")
const HUD_RELOAD_RING_SCRIPT := preload("res://src/ui/HudReloadRing.gd")
const ENCOUNTER_COUNTDOWN_RING_SCRIPT := preload("res://src/ui/EncounterCountdownRing.gd")
## —— HUD 遭遇倒计时环（2026-10-16，业主标注放右上角）——
## 外径取 108 设计 px（×HUD_UI_SCALE ⇒ 86.4 canvas px）：
## 圆心那行 `M:SS` 用的是与右下金币读数**同一个**字号（26×0.8≈21 px），
## 环再小一圈就会让 5 个字符贴到环带上。
const ENCOUNTER_COUNTDOWN_RING_DIAMETER_DESIGN := 108.0
const FATE_CARD_FEEDBACK_SCRIPT := preload("res://src/ui/FateCardFeedback.gd")
const HUD_UI_SCALE := 0.80
## —— HUD 换弹环（2026-10-15：从武器图标迁到角色右下侧）——
## 继续复用 2D HudReloadRing；退役的世界环 RELOAD_RING_IN_WORLD 保持 false。
## 新标注圈约 24×25 屏幕像素。1280×720 基准取外径 25 canvas px，
## 尺寸与偏移仍统一写成「设计 px × HUD_UI_SCALE」，随 HUD/stretch 同比例缩放。
const HUD_RELOAD_RING_OUTER_DIAMETER_DESIGN := 31.25
## 相对角色脚底投影点：基准屏幕右 34 px、下 10 px，让环位于角色身侧而不盖住模型。
## 相机投影决定锚点，偏移只决定身侧位置；不硬编码标注图的绝对圈心。
const HUD_RELOAD_RING_CHARACTER_OFFSET_DESIGN := Vector2(42.5, 12.5)
##
## 武器图标「弹一下」：时长与峰值放大倍率。主人要求「枪械的图标要放大缩小的弹一下」。
## 0.42 s 比一次换弹（2 s 上下）短一档 —— 它标的是"扣下换弹键"那一下，不是整个装填过程。
const HUD_WEAPON_ICON_POP_DURATION := 0.42
const HUD_WEAPON_ICON_POP_PEAK := 0.30
## 弹跳曲线三段在归一化时间轴上的宽度，**三者之和必须 = 1.0**（`hud_weapon_icon_pop_scale`
## 的 else 分支就是按这个前提写的）：起跳 22% / 回落 40% / 收尾 38%。
## 高峰落在 t ≈ 0.22 × 0.42 s ≈ 0.09 s —— "扣下换弹键"那一下的即时反馈。
const HUD_WEAPON_ICON_POP_RISE_SPAN := 0.22
const HUD_WEAPON_ICON_POP_FALL_SPAN := 0.40
const HUD_WEAPON_ICON_POP_SETTLE_SPAN := 0.38
const EXTRACTION_MID_PROGRESS := 0.36
const EXTRACTION_FINAL_PROGRESS := 0.70
const ENEMY_PREACTIVATION_RANGE := 38.0
const ENEMY_PREACTIVATION_INTERVAL := 0.12
const ROOM_WAVE_INTERMISSION_SECONDS := 2.0
const HOSTILE_ROOM_TYPES: Array[String] = GameDesignConfig.ROOM_TYPES_WITH_HOSTILES
const ENEMY_FILL_ATTEMPT_LIMIT := 4
## —— 地面掉落的散布（业主 2026-09-29：原来的落点太集中，但要散得开又不能不进墙）——
## 半径曲线按「等面积」取 sqrt：落点铺满圆面，而不是件数越多越往外稀、中心却空一圈。
## 外半径随件数按 sqrt 抬：`r_max = clamp(单件基准半径 × sqrt(件数), 下限, 上限)`。
## 掉落散布使用以落点为中心的方形范围，而不是无限扩大的圆。
## `LOOT_SCATTER_HALF_EXTENT_M = 1.0` 表示 X/Z 各自 [-1.0m, +1.0m]，
## 即总范围 2m × 2m；后续可在 Inspector 内把它调小，但不会超过设计上限。
@export_range(0.5, 1.0, 0.05) var loot_scatter_half_extent_m: float = 1.0
const LOOT_SCATTER_HALF_EXTENT_M := 1.0
const LOOT_SCATTER_MIN_RADIUS_M := 0.30
## 黄金角：逐件错开、件数少时也不会连成一条同向螺旋线。
const LOOT_SCATTER_GOLDEN_ANGLE := 2.399963
## 落点水平净空：贴地后在这个高度上用这个半径探一次，撞到层 1 的墙/家具就换候选点。
## 高度取 0.45 m（矮于台面、高于地面），半径取 0.30 m（略大于掉落物自身半径）。
## 单件家具贴脸时最多退到原点附近 —— 宁可挤，不可塞进墙里。
const LOOT_SCATTER_CLEARANCE_HEIGHT_M := 0.45
const LOOT_SCATTER_CLEARANCE_RADIUS_M := 0.30
## 候选点被占时按这个比例向原点方向收缩重试。
const LOOT_SCATTER_FALLBACK_SHRINK := [0.66, 0.33]
const MINIMAP_RUNTIME_INTERVAL := 1.0 / 15.0
const OFFSCREEN_INDICATOR_SCRIPT := preload("res://src/ui/OffscreenEnemyIndicator3D.gd")
## 屏幕外怪物指示箭头的喂数节奏。比小地图快一档：相机一转，整屏的"屏幕外"就全变了。
const OFFSCREEN_INDICATOR_INTERVAL := 1.0 / 20.0
## 取数半径（米，平面距离）。最大战斗房 65×65 ⇒ 半对角线 ≈ 46 m，向上取整到 50，
## 保证"站在房中央能指到房间四角还活着的那只"；再远就跨到别的房间了，箭头会变成噪音。
## 这只是上限：真正的门是 `Enemy3D.is_runtime_ai_active()`（休眠怪不给箭头）。
const OFFSCREEN_INDICATOR_RANGE_M := 50.0
## 同层容差，沿用 `Enemy3D.activate_from_player_proximity` 的楼板口径（4.5 m）。
## 分两层楼的怪不互相指 —— 塔楼里指到上一层没有任何意义。
const OFFSCREEN_INDICATOR_FLOOR_TOLERANCE_M := 4.5
## 箭头指向的高度：怪的原点在脚底，指脚底会让箭头在透视下偏低；
## 取 0.9 m ≈ 躯干中线（小怪体高约 1.7 m），指向与肉眼看到的身体位置一致。
const OFFSCREEN_INDICATOR_TARGET_HEIGHT_M := 0.9
## HUD 血条白色延迟层只负责视觉追赶，真实生命值仍由 ProgressBar.value 立即同步。
## 速度与头顶条**同一个真源**（`Enemy3D.HEALTH_BAR_DELAY_SPEED`）—— 全游戏所有白段的
## 追赶手感必须一致，否则同一场战斗里 Boss 屏条、玩家主界面条、小怪头顶条会三种节奏。
## 2026-10-15：Boss 屏条与玩家主界面条共用这两个常量（此前只有 Boss 条一个使用者）。
const HUD_HEALTH_BAR_DELAY_SPEED := Enemy3D.HEALTH_BAR_DELAY_SPEED
const HUD_HEALTH_BAR_DELAY_COLOR := Enemy3D.HEALTH_BAR_DELAY_COLOR
## 非远征门后购卡的历史稀有度基准；远征01改由 FateEconomyService 的真实收益区间冻结报价。
## 只由 `GameManager.currency`（本局金币）支付；局外总池 `BaseManager.get_extraction_points()` 永不参与。
const FATE_PRICE_BY_RARITY := [30, 60, 110, 180, 270]

## 远征命运经济由纯服务持有；门后报价只从该服务读冻结快照。
var _fate_economy = FATE_ECONOMY_SERVICE_SCRIPT.new()
var _fate_door_quote: Dictionary = {}
var _fate_door_offer_id := 0
var _fate_door_snapshot_to_restore: Dictionary = {}

## 已购买卡的整体缩小倍率（业主 2026-10-14 指定 70%）。
## ⚠️ 这一档是**基准缩放**，不是悬停反馈 —— `_tween_fate_card_scale` 收到的所有 target
## 都是「相对基准的倍率」，最终尺寸 = `target × 基准`。否则 `_reset_fate_feedback()` 那句
## 「把所有卡复位到 1.0」会把已购卡的 0.70 直接冲掉。
const FATE_PURCHASED_CARD_SCALE := 0.70
## 已购卡的压暗（乘性 modulate）：整列统一乘这个值，卡背线稿与卡下文字一起变暗。
##
## 取值 0.40（2026-10-14 主人先要「暗下去」给了 0.62，随后追加「还要再暗一些」⇒ 下调）：
## 卡背线稿去色后亮度约 0.85，× 0.40 ≈ 0.34 深灰 —— 在深色弹窗底上仍看得出「这里有一张卡」，
## 但已经明显退到背景，不会再和未购卡抢注意力。
##
## 🔴 **必须是中性灰（R=G=B）**：这里只管「暗多少」，色相归零是灰度材质的职责；
## 掺一点冷调就会让「所有都改成灰色」变成「所有都改成灰蓝」，与主人要求不符。
const FATE_PURCHASED_DIM_COLOR := Color(0.40, 0.40, 0.40)
## 已购卡**卡背贴图**的半透明档（主人 2026-10-15：「翻过去的命运卡做一下半透明处理，更淡一些」）。
##
## ⚠️ 只作用在卡背贴图层（`tarot_back_node`），**不作用在整列**：卡下那行「已购买」是这张卡
## 唯一还需要被读到的事实（它证明这张卡买过了），整列半透明会让它变成
## `0.72 × 0.40 × α ≈ 0.13` 的有效亮度，直接读不出来。所以「淡」只淡卡牌本身。
##
## 与 `FATE_PURCHASED_DIM_COLOR` 分工：那个管「暗多少」（乘性颜色），这个管「透多少」（alpha）。
## 取 0.45：线稿去色压暗后线条亮度约 0.34，半透明混到深底（≈0.03）上落到 ≈0.17 ——
## 卡形仍读得出，但已经明显像一张「翻过去不用的牌」。
const FATE_PURCHASED_CARD_ALPHA := 0.45
## 已购卡的文字色：中性灰。卡下说明原本按作用域着色（紫/金/浅蓝）、价格行原本是绿，
## 这两个彩色都是「这张卡有什么效果」的信息载体，卡买完就不需要再抢注意力了。
##
## 比 `FATE_PURCHASED_DIM_COLOR` 留一点余量（0.72 vs 0.40）：整列 modulate 会**再乘一次**，
## 「已购买」这三个字是这张卡唯一还需要被读到的事实（它证明这张卡买过了），
## 跟着卡面一起沉到 0.34 会读不出来。实测有效亮度 = 0.72 × 0.40 ≈ 0.29，是暗但可辨的一档。
## 同样必须 R=G=B，理由同上。
const FATE_PURCHASED_TEXT_COLOR := Color(0.72, 0.72, 0.72)
## 已购卡的灰度去色 shader（`canvas_item`，挂在卡背层上）。
##
## 为什么非要用材质而不是只调 `modulate`：卡背线稿本身是亮青绿（`#02FC8E` 级别），
## `modulate` 只能整体压暗、**去不掉色相**，压完仍是「暗绿」而不是「灰」。
## 这里保留原亮度分布、只丢掉色相，压暗交给 `FATE_PURCHASED_DIM_COLOR` 管（职责分开，
## 将来单独调「灰多少」或「暗多少」互不影响）。
const FATE_GREYSCALE_SHADER_CODE := """
shader_type canvas_item;
varying vec4 canvas_tint;

void vertex() {
    canvas_tint = COLOR;
}

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    float luminance = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
    // Keep inherited dim/alpha: replacing COLOR without its vertex tint makes purchased cards ignore exit fades.
    COLOR = vec4(vec3(luminance), base.a) * canvas_tint;
}
"""

## 右下角本局金币读数（`RunLootReadout`）的常色（金色）。
## 抽成常量：「金币不足」反馈要在闪红之后**恢复**它，两处必须取同一个值，不能各写一份。
const RUN_COIN_READOUT_COLOR := UIPalette.PRISM_WARN
## —— 门后购卡的交互反馈（主人 2026-10-15：让反馈更容易被看到）——
##
## 总原则：**视线在哪里，反馈就落在哪里**。金币的唯一读数在右下角（主人 2026-10-15：
## 顶部余额行移除，右下金币作为高亮），三张卡在屏幕中央；所以「为什么买不了」「花了多少」
## 这类反馈必须落在卡上和右下金币读数上，状态栏文字只作为补充。
##
## 卡上拒绝反馈：卡片横向抖动（px）与总时长。抖动是**拒绝**语义，与购买成功的
## 卡背翻转是两套完全不同的动作，不会被混淆。
const FATE_REJECT_SHAKE_PX := 12.0
const FATE_REJECT_SHAKE_DURATION := 0.30
## 拒绝时价格行的瞬时提亮（乘性 modulate，>1 才能压过字色本身）。
const FATE_REJECT_PRICE_FLASH := Color(1.5, 1.5, 1.5)
const FATE_REJECT_PRICE_SCALE := 1.14
## 金币读数扣款时的一次脉冲缩放与时长。
const FATE_BALANCE_PULSE_SCALE := 1.16
const FATE_BALANCE_PULSE_DURATION := 0.30
## 金币读数「金币不足」时闪红的颜色与持续时长（之后恢复 `RUN_COIN_READOUT_COLOR`）。
const FATE_BALANCE_SHORTAGE_COLOR := Color(1.0, 0.38, 0.32)
const FATE_BALANCE_SHORTAGE_DURATION := 0.50
## 扣款飘字：`-N 金币` 从右下金币读数上方浮起并淡出。
## 为什么要飘字：读数是「32 → 2」的一次数字替换，一闪而过很难被注意到；
## 飘字把「刚才那一下花了多少」写明白，玩家不用自己去减。
const FATE_SPEND_POPUP_COLOR := Color(1.0, 0.74, 0.38)
const FATE_SPEND_POPUP_LIFETIME := 0.90
const FATE_SPEND_POPUP_RISE := 42
## 点击退出后，卡列先完成「翻回背面 + 缩小淡出」，再回收整个命运卡弹窗。
## 这段时长要足够让翻面被看见，但不能让退出像卡住；减少动效时直接跳过。
const FATE_OVERLAY_EXIT_DURATION := 0.42
const FATE_OVERLAY_EXIT_FLIP_DURATION := 0.16
## 门后购卡弹窗（含全屏暗化层）的 `z_index`，写在 `HUD` 下。
const FATE_OVERLAY_Z_INDEX := 900
## 弹窗打开期间给金币读数的 `z_index`（`loot_label` 挂在 `ReferenceCombatHUD` 下，父 z=100）。
## 100 + 900 = 1000 > 弹窗 900 ⇒ 读数不被暗化层压暗。
## 主人 2026-10-19：别把金币 UI 遮掉 —— 这张弹窗里唯一的对照数字就是它（价格 vs 余额）。
const FATE_COIN_READOUT_Z_ABOVE_VEIL := 900

const BASE_INVENTORY_CAPACITY := 40
## 保底武装配套弹药：入场即给 `item_ammo_pack` 的发数（每单位 = 1 发真实备弹）。
## 白送手枪由 `Player3D.start_with_weapon` 负责，那条链路只给枪不给弹；
## 没有这份备弹时，弹匣打空且没捡到掉落 = 保底武装彻底哑火。数值是设计输入，不要就地写数字。
const GUARANTEED_LOADOUT_AMMO_ROUNDS := 300
## 玩家头顶气泡的挂高（米）。玩家是 1.5m 级小机器人，气泡放在头顶正上方；
## 偏移**只含垂直分量**，角色绕 Y 轴转身不会带动气泡横向位移。
## 2026-09-21 主人反馈"太低、挡住角色"：1.95 → 2.55。俯视角下原高度让气泡底边
## 压在角色身上，抬高后与头顶拉开约 0.8m。
const PLAYER_BARK_HEIGHT_M := 2.55

@export var gameplay_theme: MapThemeProfile
@export var visual_theme: DungeonTheme3D
@export var run_seed_override := -1
@export var test_mode := false
@export_file("*.tscn") var return_scene_path := GameDesignConfig.BASE_SCENE_3D

@onready var player: Player3D = $Player3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var key_light: DirectionalLight3D = $DirectionalLight3D
@onready var title_label: Label = $HUD/TopBar/Margin/HBox/TitleLabel
@onready var seed_label: Label = $HUD/TopBar/Margin/HBox/SeedLabel
@onready var hp_label: Label = $HUD/TopBar/Margin/HBox/HPLabel
@onready var hp_bar: ProgressBar = $HUD/TopBar/Margin/HBox/HPBar
@onready var ammo_label: Label = $HUD/TopBar/Margin/HBox/AmmoLabel
@onready var room_label: Label = $HUD/TopBar/Margin/HBox/RoomLabel
@onready var loot_label: Label = $HUD/TopBar/Margin/HBox/LootLabel
@onready var status_label: Label = $HUD/StatusPanel/Margin/StatusLabel
@onready var extraction_bar: ProgressBar = $HUD/ExtractionPanel/Margin/VBox/ExtractionBar
@onready var extraction_panel: PanelContainer = $HUD/ExtractionPanel
@onready var minimap: DungeonMinimap3D = $HUD/DungeonMinimap3D
@onready var low_health_vignette: ColorRect = $HUD/LowHealthVignette

var run_seed := 1
var _run_id := ""
var _rng := RandomNumberGenerator.new()
var _rooms: Array[DungeonRoom3D] = []
var _room_by_id: Dictionary = {}
var _records: Array[Dictionary] = []
var _alive_by_room: Dictionary = {}
## 本房首领**已被击杀**的登记（房 id → true）。只由 `_on_enemy_killed` 里的
## `enemy_kind == "boss"` 分支写入，且**只在真死时**写 —— 与 `room.cleared`
## （还要求增援/波次全清）是两条独立事实，门控按需各取其一。
var _boss_defeated_rooms: Dictionary = {}
var _spawned_rooms: Dictionary = {}
var _run_loot: Array[Dictionary] = []
var _run_value := 0
## 上一次写进右下金币读数的值，用于判断这次刷新是「获得 / 消费 / 无变化」。
## `-1` 表示还没显示过任何值（首帧初始化不播动画）。
var _loot_readout_last_value := -1
var _kills := 0
var _completed := false
var _death_dialog: Control = null
var _death_animation_ready := false
## 行动代际：每次「本次行动已终局结算并把世界复位成新一轮」时 +1。
## 死亡动画 1.35s 比成功撤离的 0.8s 返航窗口更长，复位之后才结束的那次死亡
## 属于上一代行动，必须作废 —— 否则同一次行动会先判撤离成功、再判阵亡结算。
var _run_generation := 0
## 当前这次死亡是在哪一代行动里发生的。与 _run_generation 不一致即表示
## 该死亡已被终局结算覆盖，不得再弹框、不得再结算。
var _death_recorded_generation := -1
var _extraction: ExtractionBeacon3D = null
## 传送支线管理器（支线秘密房间设计）。未声明 `secret_site` 的关卡恒为 null。
var _secret_branch: Node3D = null
## 子图房间登记表：room_id -> DungeonRoom3D。**只收已经在子图里刷过怪的房**。
## 用途有三，都不碰主图那套账：
##   · `_on_enemy_killed` 取 `loot_room`（掉落要按房间做散布，null 会静默掉 0 件）；
##   · `_resolve_room_enemy_departure` 判「这是子图的房」⇒ 走子图清房分支；
##   · 门交互路由：子图房不在 `_room_by_id` 里。
var _secret_branch_room_ids: Dictionary = {}
## 最近一次进入的**主图**房间。子图不参与存档，在子图里存档时回落到它
## （见 `_runtime_current_room_id_for_save`）。
var _last_main_room_id := ""
var _standard_extraction: ExtractionBeacon3D = null
var _emergency_extraction: ExtractionBeacon3D = null
var _conditional_extractions: Dictionary = {}
var _active_extraction_beacon: ExtractionBeacon3D = null
var _extraction_defense_active := false
var _extraction_encounter_instance_id := ""
var _last_player_hp := -1
var _current_room_id := ""
var _encounter_event_director: EncounterEventDirector3D
var _encounter_event_host: EncounterEventHost3D
var _encounter_event_completed_history: Array[String] = []
var _room_neighbors: Dictionary = {}
var _open_edges: Dictionary = {}
var _corridor_by_edge: Dictionary = {}
var _spawned_key_rooms: Dictionary = {}
var _room_key_count := 1
var _enemy_nodes_by_room: Dictionary = {}
var _room_wave_queues: Dictionary = {}
var _room_wave_numbers: Dictionary = {}
var _room_wave_totals: Dictionary = {}
var _wave_spawn_pending: Dictionary = {}
var _room_wave_intermission_tokens: Dictionary = {}
var _reserved_room_spawns: Dictionary = {}
## —— 触发器刷怪：延迟出怪在途（`docs/v0.1/design/触发器刷怪设计.md` §3.1 delay_sec）——
## room_id → [{serial, config, position, delay_sec}]。摘出来的怪记在「待生成」账上
## （见 `_pending_delayed_spawn_count`），期间本波**不判清**，到点后再实例化 ——
## 这就是「延迟几秒怪才出现」的落地方式，且不破坏既有「全灭才推进」的波次语义。
var _pending_delayed_spawns: Dictionary = {}
## 延迟出怪的唯一序号（每批一个），用于定时器回执时在队列里认领自己那一条。
var _delayed_spawn_serial := 0
## 本房波间隙秒数。缺省沿用 ROOM_WAVE_INTERMISSION_SECONDS；
## `encounter.intermission_sec` 可逐房覆盖（触发器刷怪设计 §3.3）。
var _room_intermission_seconds: Dictionary = {}
var _room_fate_wave_queued: Dictionary = {}
var _room_spawn_blocked: Dictionary = {}
## —— 踩点触发式遭遇（`docs/v0.1/design/触发器刷怪设计.md` §3.3 调用层扩展）——
## 本房声明了 `encounter.trigger` 时就**不在进房时刷怪**，改由玩家走到房间内某个点触发。
## `_room_encounters_fired` 记录已触发过的房（每局一次），`_room_encounter_active` 记录
## 进行中的事件实例 —— 后者是「本房有怪没清完」之外的**第二个不判清房**的理由：
## 波与波之间场上会短暂清空，若没有这道门，房间会在两波之间被误判为已肃清并放行。
var _room_encounters_fired: Dictionary = {}
var _room_encounter_active: Dictionary = {}
## 被「落下门扇」封住的房间（room_id → 原因）。封住期间门不可交互、且保持关闭。
var _sealed_rooms: Dictionary = {}
var _loot_module: LootModule
var _reward_coordinator: RuntimeRewardCoordinator
var _monster_injector: MonsterInjector
## 关卡级怪物规则（`level_plan.json` 顶层 `monster_rules`，远征01 专属）。
## 空字典 = 未配置 ⇒ 数值与 AI 全部走原常量，未配置关卡逐字不变。
var _monster_rules: Dictionary = {}
var _inventory: InventoryModule
var _insurance: InsuranceModule
var _quick_inventory: InventoryModule
var _death_settlement: DeathSettlementModule
var _player_killer_elite_settled := false
var _inventory_ui: InventoryUI
var _weapon_panel: WeaponAssemblyTreePanel
var _workbench_panel: WorkbenchPanel
var _merchant_ui: MerchantUI
var _merchant_service: RunMerchantService
var _merchant_stock_restore_failed := false
var _trade_extraction_unlocked := false
var _trade_extraction_room_id := ""
var _enemy_preactivation_accumulator := 0.0
var _door_fate_active := false
var _fate_offer_policy_snapshot: Dictionary = {}
var _door_fate_choices: Array[FateCard] = []
## 本次门后购卡中已被买下的卡位（与 `_door_fate_choices` 同序）；退出后清空。
var _door_fate_purchased: Array[bool] = []
## 底部退出按钮的引用，供退出流程与验收查询。
## 顶部「本局金币」余额行已按主人 2026-10-15 要求整体移除：右下角的
## `RunLootReadout`（`loot_label`）是唯一的金币读数，扣款/获得反馈都落在它身上。
var _fate_exit_button: Button = null
var _pending_fate_door_from_id := ""
var _pending_fate_door_target_id := ""
var _fate_overlay: Control
var _fate_overlay_closing := false
var _fate_choice_buttons: Array[Button] = []
var _fate_feedback_label: Label = null
var _fate_feedback_tweens: Dictionary = {}
var _fate_feedback_locked := false
var _fate_feedback_selected_index := -1
var _fate_feedback_dispatch: Tween = null
var _fate_initializing_focus := false
## 已购卡共用的灰阶材质（懒建一次，三张卡共享同一实例）。
var _fate_greyscale_material: ShaderMaterial = null
## 卡片「拒绝」抖动的 tween，按按钮 instance_id 存。
## 🔴 与 `_fate_feedback_tweens` **分开存**：那个表里是缩放 tween，两者动的是不同属性
## （`position:x` vs `scale`），共用一个槽会在求值时把对方 kill 掉。
var _fate_shake_tweens: Dictionary = {}
## 价格行「拒绝」闪烁的 tween，同样按按钮 instance_id 存（与抖动分开，属性也不重叠）。
var _fate_price_flash_tweens: Dictionary = {}
## 余额行的扣款脉冲 / 不足闪红 tween。两个分开持有，各自只在同类反馈里互相替换。
## 名称里的 balance 是历史叫法：反馈宿主现在是右下角金币读数 `loot_label`。
var _fate_balance_pulse_tween: Tween = null
var _fate_balance_warn_tween: Tween = null
var _map_fate_triggers: MapFateTriggers
# 模态浮窗（雷达 / 背包）的 ESC 关闭按钮
var _radar_close_button: Button = null
var _inventory_close_button: Button = null
var last_killed_enemy_data: Dictionary = {}
var _resolved_event_rooms: Dictionary = {}
var _event_combat_rooms: Dictionary = {}
var _next_chest_quality_boost := 0
var _extra_loot_next_chest_count := 0
var _next_room_enemy_count := 0
var _next_room_enemy_hp_multiplier := 1.0
var _next_room_enemy_damage_multiplier := 1.0
var _next_room_currency_multiplier := 1.0
var _room_enemy_hp_multipliers: Dictionary = {}
var _room_enemy_damage_multipliers: Dictionary = {}
var _room_currency_multipliers: Dictionary = {}
var _room_spawn_plan_suppressed_reinforcements: Dictionary = {}
var _world_currency_multiplier := 1.0
var _fate_visited_rooms: Dictionary = {}
var _next_chest_max_rarity := ""
var _next_room_elite_configs: Array[Dictionary] = []
var _fate_elite_reservation_serial := 0
var _next_room_clear_currency := 0
var _room_fate_clear_currency: Dictionary = {}
var _fate_bounty_queues: Array[Dictionary] = []
var _room_fate_bounties: Dictionary = {}
var _room_zero_currency: Dictionary = {}
var _fate_drop_quality_rules: Array[Dictionary] = []
var _temporary_room_keys := 0
var _temporary_key_floor := ""
var _extraction_time_multiplier := 1.0
var _extraction_enemy_speed_multiplier := 1.0
var _starter_cache_opened := false
var _boss_panel: PanelContainer = null
var _boss_label: Label = null
var _boss_bar: ProgressBar = null
var _boss_delayed_bar: ProgressBar = null
var _boss_delayed_value := 1.0
## 玩家主界面条（`ReferenceCombatHUD/PlayerStatusBlock`）的延迟白段。
## 与 Boss 屏条同构：白条在下、红条在上，两层占同一矩形 —— 见 `_build_reference_main_hud`。
var _player_delayed_bar: ProgressBar = null
var _player_delayed_ratio := 1.0
var _player_health_bar_initialized := false
var _active_boss: Enemy3D = null
# 常驻交互圆点（门的锚点）单帧缓存：见 _refresh_interaction_dot_cache。
var _dot_cache_frame := -1
var _dot_anchor_cache := Vector3.ZERO
var _dot_visible_cache := false
var _reference_hud_root: Control = null
var _hud_weapon_meta_label: Label = null
var _hud_weapon_fate_label: Label = null
var _hud_weapon_model_icon: ItemModelIcon3D = null
## HUD 换弹环（角色右下侧的屏幕投影）。见 HUD_RELOAD_RING_* 一族常量。
var _hud_reload_ring: HudReloadRing = null
## 右上角遭遇倒计时环（只在事件声明了 `hud_countdown` 且仍在跑时可见）。
var _hud_countdown_ring: EncounterCountdownRing = null
var _hud_reload_ring_active := false
## 图标弹跳的已用时长；< 0 表示没在弹（负数不用 0 是因为 t=0 本身是合法采样点）。
var _hud_weapon_icon_pop_elapsed := -1.0
var _hud_presenter: HUDPresenter3D = HUD_PRESENTER_SCRIPT.new()
var _hud_quick_item_icons: Array = [null, null]
var _hud_quick_item_icon_hosts: Array[Control] = []
var _hud_quick_item_labels: Array[Label] = []
var _quick_item_ids: Array[String] = ["", ""]

# 手电筒电量 HUD 复用头像下方原本未接玩法的三格指示器。
var _hud_battery_time_label: Label = null
var _hud_battery_cells: Array[Panel] = []
var _hud_battery_panel: Control = null
var _hud_battery_cell_prev_filled: Array[bool] = []
var _hud_battery_blink_accum := 0.0
var _last_battery_tier := -1
var _hud_battery_blink_visible := 1.0
var _full_map_overlay: Control = null
var _full_map_control: DungeonMinimap3D = null
var _offscreen_indicator: OffscreenEnemyIndicator3D = null
var _offscreen_indicator_accumulator := 0.0
var _hud_floor_label: Label = null
var _hud_timer_label: Label = null
var _hud_wave_label: Label = null
var _hud_run_elapsed := 0.0
var _hud_last_elapsed_second := -1
var _minimap_runtime_accumulator := 0.0
var _runtime_restore_snapshot: Dictionary = {}
## 基地快照只恢复世界和携带物；玩家仍在基地固定点出生。
var _runtime_base_restore_snapshot: Dictionary = {}
## 独立副本「撤离信号塔成功返航」的所有权交接快照。与 `_runtime_restore_snapshot`
## 的区别是只交接玩家携带物，绝不恢复世界布局、房间状态与坐标。
var _runtime_carry_restore_snapshot: Dictionary = {}
## 基地 → 新行动地图（远征情报室传送）的出发交接快照。与 `_runtime_carry_restore_snapshot`
## 的区别：返航交接的落点就是 99F 基地房，所以它顺带恢复房间与坐标；而出发交接的落点
## 是新地图自己的出生点，坐标与房间一律不许被基地快照覆盖（见
## `MISSION_OPERATIONS_DEPARTURE_CARRY_KEY`）。
var _runtime_departure_carry_snapshot: Dictionary = {}
var _runtime_persistence_active := false
var _pending_run_settlement_transaction_id := ""
var _pending_insurance_return_restore := false
var _segment_runtime_state: Dictionary = {}
## Boss 房持续增援状态：room_id → {armed, elapsed, round, cursor, stopped}。
## 轮次与倒计时随房间段快照保存；不使用裸 Timer，切房/续局不会重复启动或遗留回调。
var _boss_reinforcement_states: Dictionary = {}
var _narrative_spawned_keys: Dictionary = {}
var _room_graph_runtime: RoomGraphRuntime = ROOM_GRAPH_RUNTIME_SCRIPT.new()


const LOADING_RESOURCE_WARMUP := preload("res://src/world3d/LoadingResourceWarmup.gd")
const DEFAULT_VISUAL_THEME_PATH := "res://assets/art/environments/dungeon_3d/env_iron_frontier_kit_top3d_v001.tres"

var _loading_scene_resources: Array[Resource] = []


func _ready() -> void:
	if not _hud_presenter.weapon_hud_command_ready.is_connected(_apply_weapon_hud_command):
		_hud_presenter.weapon_hud_command_ready.connect(_apply_weapon_hud_command)
	add_to_group("room_game_mode")
	add_to_group(PlayerInteractionController3D.PROVIDER_GROUP)
	if not test_mode and BaseManager != null:
		# 死亡保险中转是已经完成结算的更高优先级边界。即使上一次清理
		# 战斗检查点时写盘失败，也不能让旧战斗房快照覆盖保险返城数据。
		var has_death_insurance_return := (
			_accepts_pending_insurance_return_at_spawn()
			and not BaseManager.get_pending_insurance_slots().is_empty()
		)
		if not has_death_insurance_return:
			var candidate := BaseManager.get_active_run_checkpoint()
			if _is_combat_runtime_snapshot(candidate) and _snapshot_matches_runtime_map(candidate):
				_runtime_restore_snapshot = candidate
				run_seed_override = int(candidate.get("run_seed", run_seed_override))
				_run_id = str(candidate.get("run_id", ""))
			elif _is_successful_extraction_carry_snapshot(candidate):
				# 独立副本的成功撤离已经完成结算，这里只是把同一批物品实例
				# 从关卡场景交接给返航落点（99F）。它绝不是一次可续局行动，
				# 所以不走上面的 combat 分支，也不改 run_seed / run_id。
				_runtime_carry_restore_snapshot = candidate
			elif (
				RUN_PERSISTENCE_SERVICE.supports_runtime_snapshot(candidate)
				and str(candidate.get("scope", "")) == "base"
				and _snapshot_matches_runtime_map(candidate)
				and str((candidate.get("world_state", {}) as Dictionary).get("schema", ""))
				in ["tower_world_state_v1", "dungeon_world_state_v1"]
			):
				_runtime_base_restore_snapshot = candidate
				run_seed_override = int(candidate.get("run_seed", run_seed_override))
				_run_id = str(candidate.get("run_id", ""))
			elif _is_mission_operations_departure_carry_snapshot(candidate):
				# 基地 → 新行动地图的出发交接（见 MISSION_OPERATIONS_DEPARTURE_CARRY_KEY）。
				# ⚠️ 顺序是契约：必须排在 base 分支之后 —— 塔楼自己的场景要靠 base 分支
				# 恢复世界与坐标，而出发交接刻意不恢复它们。这里也刻意不继承 run_seed /
				# run_id：远征是新行动，身份由目的地场景自己派生。
				_runtime_departure_carry_snapshot = candidate
	if gameplay_theme == null:
		if _uses_loading_frame_budget():
			gameplay_theme = await _load_bootstrap_resource("res://data/map_themes/iron_frontier.tres") as MapThemeProfile
		else:
			gameplay_theme = load("res://data/map_themes/iron_frontier.tres") as MapThemeProfile
	if visual_theme == null:
		if _uses_loading_frame_budget():
			visual_theme = await _load_bootstrap_resource(DEFAULT_VISUAL_THEME_PATH) as DungeonTheme3D
		else:
			visual_theme = load(DEFAULT_VISUAL_THEME_PATH) as DungeonTheme3D
	if gameplay_theme == null or visual_theme == null:
		_on_loading_resource_failed("地图主题")
		return
	run_seed = run_seed_override
	if run_seed < 0:
		run_seed = LevelSelect.selected_seed if LevelSelect != null and LevelSelect.selected_seed >= 0 else int(Time.get_unix_time_from_system()) ^ randi()
	if _run_id.is_empty():
		_run_id = RUN_PERSISTENCE_SERVICE.generate_run_id(run_seed)
	_rng.seed = run_seed
	_setup_run_modules()
	if _uses_loading_frame_budget():
		await get_tree().process_frame
	# 热返城不会重新创建主入口界面，因此玩法场景自身必须恢复已保存外观。
	# test_mode 禁止读取开发者真实档案，专项测试可显式调用持久化服务。
	if not test_mode:
		AVATAR_CUSTOMIZATION_PERSISTENCE.apply_saved_to_player(player)
	_map_fate_triggers = MapFateTriggers.new()
	_map_fate_triggers.name = "MapFateTriggers3D"
	add_child(_map_fate_triggers)
	_install_holographic_hud_style()
	_configure_environment()
	if RuntimePerformanceManager != null:
		RuntimePerformanceManager.register_atmosphere(self)
	if _uses_loading_frame_budget():
		if has_method("hold_loading_render"):
			call("hold_loading_render")
		await get_tree().process_frame
		await _generate_layout_for_loading()
	else:
		_generate_layout()
	if not _can_finish_layout_bootstrap():
		return
	player.set_combat_enabled(true)
	FateCardGameBridge.reset_run_state()
	FateCardGameBridge.set_player(player)
	if not FateCardGameBridge.scope_state_changed.is_connected(_on_fate_scope_state_changed):
		FateCardGameBridge.scope_state_changed.connect(_on_fate_scope_state_changed)
	player.hp_changed.connect(_on_player_hp_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	# 换弹环的驱动源：武器换弹进度 → Player3D 透传 → 本 HUD 环（2026-10-08）。
	# 只听不写：环的进度与显隐完全由武器换弹计时器决定，HUD 不反向影响换弹时长。
	player.reload_progress_changed.connect(_on_player_reload_progress_changed)
	player.reload_ended.connect(_on_player_reload_ended)
	player.presentation_state_changed.connect(_on_player_state_changed)
	player.death_animation_finished.connect(_on_player_death_animation_finished)
	player.debug_scale_changed.connect(_on_player_debug_scale_changed)
	if not player.weapon_instance_changed.is_connected(_on_hud_weapon_instance_changed):
		player.weapon_instance_changed.connect(_on_hud_weapon_instance_changed)
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	if flashlight != null:
		_apply_persisted_flashlight_module()
		if not flashlight.charge_changed.is_connected(_on_flashlight_charge_changed):
			flashlight.charge_changed.connect(_on_flashlight_charge_changed)
		if not flashlight.state_changed.is_connected(_on_flashlight_state_changed):
			flashlight.state_changed.connect(_on_flashlight_state_changed)
		_update_battery_hud()
	player.global_position = Vector3(0, 0.05, 0)
	_on_room_entered(_room_by_id.get("start") as DungeonRoom3D)
	_on_player_hp_changed(player.current_hp, player.max_hp)
	var weapon_snapshot := player.get_weapon_snapshot()
	_on_ammo_changed(int(weapon_snapshot.get("current_ammo", 0)), int(weapon_snapshot.get("magazine_size", 0)))
	title_label.text = "%s · 3D行动区" % gameplay_theme.display_name
	seed_label.text = "SEED %d" % run_seed
	status_label.text = "%s · 初始钥匙 1，把战利品安全带到撤离点" % gameplay_theme.fantasy
	_refresh_loot_label()
	generation_completed.emit(get_generation_snapshot())
	var world_audio := preload("res://src/audio/WorldAudioEnvironment3D.gd").new()
	world_audio.name = "WorldAudioEnvironment"
	add_child(world_audio)
	world_audio.configure(self, player)
	call_deferred("_activate_runtime_persistence")


## 子类可在规划失败时阻止出生、生成完成信号与持久化激活。
func _can_finish_layout_bootstrap() -> bool:
	return true


func _exit_tree() -> void:
	if _encounter_event_director != null:
		_encounter_event_director.cancel_all("scene_unloaded")
	for room_id in _wave_spawn_pending.keys():
		_cancel_room_wave_intermission(str(room_id))
	if not test_mode and BaseManager != null and _runtime_persistence_active:
		BaseManager.unregister_runtime_checkpoint_provider(self, true)
	_runtime_persistence_active = false


func _activate_runtime_persistence() -> void:
	if test_mode or BaseManager == null or not is_inside_tree():
		return
	if not _runtime_restore_snapshot.is_empty():
		_restore_runtime_save_snapshot(_runtime_restore_snapshot)
	if not _runtime_base_restore_snapshot.is_empty():
		_restore_base_runtime_save_snapshot(_runtime_base_restore_snapshot)
	if not _runtime_carry_restore_snapshot.is_empty():
		# 独立副本成功撤离的交接只认玩家所有权：世界、房间、坐标一律按落点
		# 场景自己生成，否则会把返航目标改成刚离开的那张关卡地图。
		_restore_carried_ownership(_runtime_carry_restore_snapshot)
		_runtime_carry_restore_snapshot = {}
	if not _runtime_departure_carry_snapshot.is_empty():
		# 基地 → 新行动地图的出发交接：装所有权与状态（背包/主副枪/装备背包/快捷栏/
		# 保险格/HP/手电/钥匙），坐标与房间留给落点场景自己的出生点 —— 远征是
		# 「安全房中心朝前门方向偏 4m」，而 `_resolve_runtime_restore_room()` 会拿基地的
		# `current_room_id=facility` 兜底解析成安全房中心，直接把出生点偏移抹掉。
		_restore_carried_ownership(_runtime_departure_carry_snapshot, false)
		_runtime_departure_carry_snapshot = {}
	if _pending_insurance_return_restore:
		# 中转集合与当前基地检查点必须原子交接；失败时清掉内存投影，
		# 长期中转仍在，下次进入基地可以安全重试且不会复制。
		if BaseManager.commit_pending_insurance_to_runtime(build_runtime_save_snapshot()):
			_pending_insurance_return_restore = false
		else:
			_insurance.clear_all()
			push_error("[Dungeon3D] Failed to commit death-insurance return to the 99F runtime checkpoint")
	_runtime_persistence_active = true
	if _door_fate_active:
		call_deferred("_restore_pending_door_fate_overlay")
	BaseManager.register_runtime_checkpoint_provider(self)
	if _inventory != null and not _inventory.inventory_changed.is_connected(_on_runtime_inventory_changed):
		_inventory.inventory_changed.connect(_on_runtime_inventory_changed)
	if _insurance != null and not _insurance.insurance_changed.is_connected(_on_runtime_insurance_changed):
		_insurance.insurance_changed.connect(_on_runtime_insurance_changed)
	if _quick_inventory != null and not _quick_inventory.inventory_changed.is_connected(_on_runtime_quick_inventory_changed):
		_quick_inventory.inventory_changed.connect(_on_runtime_quick_inventory_changed)
	if player != null:
		if not player.weapon_loadout_changed.is_connected(_on_runtime_weapon_changed):
			player.weapon_loadout_changed.connect(_on_runtime_weapon_changed)
		if not player.backpack_equipment_changed.is_connected(_on_runtime_backpack_changed):
			player.backpack_equipment_changed.connect(_on_runtime_backpack_changed)
	BaseManager.queue_runtime_checkpoint("runtime_ready", 0.1)


func _on_runtime_inventory_changed() -> void:
	_queue_runtime_autosave("inventory_changed")


func _on_runtime_insurance_changed() -> void:
	_queue_runtime_autosave("insurance_changed")


func _on_runtime_quick_inventory_changed() -> void:
	_queue_runtime_autosave("quick_inventory_changed")


func _on_runtime_weapon_changed(_snapshot: Dictionary) -> void:
	_queue_runtime_autosave("weapon_changed")


func _on_runtime_backpack_changed(_snapshot: Dictionary) -> void:
	_queue_runtime_autosave("backpack_changed")


func _queue_runtime_autosave(reason: String) -> void:
	if _runtime_persistence_active and not _completed and BaseManager != null:
		BaseManager.queue_runtime_checkpoint(reason)


# 运行时存档归属的独立地图 ID。默认空字符串即“旧塔楼/兼容”地图；
# 独立副本（如 RogueMap01）覆盖为自身 ID，实现存档隔离与旧档兼容。
func get_runtime_map_id() -> String:
	return ""

func build_runtime_save_snapshot() -> Dictionary:
	if player == null or _inventory == null or _insurance == null:
		return {}
	var weapon_items: Array[Dictionary] = []
	for slot_index in range(2):
		weapon_items.append(player.get_equipped_weapon_item_for_slot(slot_index))
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	# 场景卸载时子节点可能已经离开 SceneTree；此时读取 global_position 会触发引擎错误。
	# Tower 根节点没有运行时位移，因此本地 position 是安全的最终兜底。
	var position := player.global_position if player.is_inside_tree() else player.position
	var runtime_room_id := _runtime_current_room_id_for_save()
	var runtime_floor_index := _runtime_current_floor_index()
	var snapshot := {
		"valid": true,
		"schema": "runtime_player_state_v2",
		"checkpoint_id": "runtime_player_state_v2",
		"layout_id": "runtime_player_state_v2",
		"scope": _runtime_scope_for_save(runtime_floor_index, runtime_room_id),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"run_seed": run_seed,
		"run_id": _run_id,
		"current_room_id": runtime_room_id,
		"current_floor_index": runtime_floor_index,
		"player_position": [position.x, position.y, position.z],
		# 玩家根节点同时是固定俯视相机的父节点，不能持久化角色朝向。
		# 武器/角色朝向由 aim_yaw 与表现层单独管理；保留字段仅用于旧存档结构兼容。
		"player_rotation_y": 0.0,
		"player_hp": player.current_hp,
		"inventory_capacity": _inventory.get_capacity(),
		"inventory_slots": _inventory.get_slots_snapshot(),
		"insurance_capacity": _insurance.get_max_slots(),
		"insurance_slots": _insurance.get_slots_snapshot(),
		"equipped_weapon_items": weapon_items,
		"active_weapon_slot": player.get_active_weapon_slot(),
		"weapon_holstered": player.weapon_holstered,
		"equipped_backpack_item": player.get_equipped_backpack_item(),
		"flashlight_module_id": flashlight.get_module_id() if flashlight != null else "basic",
		"flashlight_charge_ratio": flashlight.get_charge_ratio() if flashlight != null else 1.0,
		"quick_item_slots": _quick_inventory.get_slots_snapshot(),
		"quick_item_ids": _quick_item_ids.duplicate(),
		"room_key_count": _room_key_count,
		"run_value": _run_value,
		"kills": _kills,
		"run_currency": GameManager.currency,
		"trade_extraction_unlocked": _trade_extraction_unlocked,
		"trade_extraction_room_id": _trade_extraction_room_id,
		"merchant_stock": _merchant_service.export_stock_snapshot() if _merchant_service != null else {
			"schema": "run_merchant_stock_v1", "stocks": {},
		},
		"edge_states": _open_edges.duplicate(true),
		"runtime_map_id": get_runtime_map_id(),
	}
	snapshot["world_state"] = _build_runtime_world_save_snapshot()
	snapshot["fate_run_state"] = {
		"version": 1,
		"player": player.export_fate_snapshot(),
		"world": export_world_fate_snapshot(),
		"bridge": FateCardGameBridge.export_fate_snapshot(),
		"economy": _fate_economy.export_snapshot(),
		"door": _export_door_fate_snapshot(),
	}
	return RUN_PERSISTENCE_SERVICE.finalize_runtime_snapshot(snapshot)


func _runtime_current_floor_index() -> int:
	return 0


func _runtime_current_room_id_for_save() -> String:
	# 在子图里存档时**不能**把 `secret_*` 写进去：那个 id 不在 `_room_by_id` 里，
	# 续局按它取房只会得到 null，玩家会被丢进一个没有房间的世界。
	# 回落到最近一次主图房间 —— 子图本来就不参与存档（它不在 `_records`、
	# 不写全层地图、刷出来的怪也不进 segment 状态）。
	if _secret_branch_room_ids.has(_current_room_id):
		return _last_main_room_id
	return _current_room_id


func _runtime_scope_for_save(_floor_index: int, room_id: String) -> String:
	return "base" if room_id == "facility" else "combat"


## 只有仍在塔内的行动快照才续局。99F/100F 的基地快照只记录上次
## 下线所在楼层，下一次进入按固定基地出生点重建，不能把玩家投回旧的任意坐标。
func _is_combat_runtime_snapshot(snapshot: Dictionary) -> bool:
	if not RUN_PERSISTENCE_SERVICE.supports_runtime_snapshot(snapshot):
		return false
	if str(snapshot.get("scope", "")) == "base":
		return false
	# v1 旧档没有 scope；只要并非99F facility，按原行动快照兼容恢复。
	return str(snapshot.get("current_room_id", "")) != "facility"


const SUCCESSFUL_EXTRACTION_CARRY_KEY := "successful_extraction_carry"

## 基地 → 新行动地图（远征情报室传送）的出发交接标记。
##
## 起因（2026-09-26 实测 bug）：基地快照的身份是塔楼 —— `scope=base` 且
## `runtime_map_id` 为空串；而远征场景的身份是 `expedition_01`。三条既有恢复通道
## 的判据全都要求地图 ID 相同（见 `_snapshot_matches_runtime_map`），于是这一跳
## 被整条丢弃：玩家带着 99F 基地的背包与主副枪出发，进远征却只剩空背包 +
## 白送武器 + 保底备弹。业主裁定「远征入场必然带着 99F 基地的所有物品和状态入场」，
## 故新增本标记：目的地图命中它时**只交接玩家所有权与状态，不再要求地图 ID 相同，
## 也绝不恢复塔楼世界、房间进度与坐标**（远征是单层独立关卡，塔楼世界对它无意义）。
##
## 判据必须是显式的：基地快照本身就是 `scope=base` + 空 map id，光看这两项无法把它
## 与「塔楼自己的基地快照」区分开 —— 后者必须连世界一起恢复，所以不能放宽
## `_snapshot_matches_runtime_map()`，只能新增标记。
const MISSION_OPERATIONS_DEPARTURE_CARRY_KEY := "mission_operations_departure_carry"


## 独立副本「撤离信号塔」成功返航写入的所有权交接快照。它与可续局行动快照
## 互斥：标记存在时只交接携带物，绝不把玩家送回刚撤离的那张关卡地图。
func _is_successful_extraction_carry_snapshot(snapshot: Dictionary) -> bool:
	if not RUN_PERSISTENCE_SERVICE.supports_runtime_snapshot(snapshot):
		return false
	return bool(snapshot.get(SUCCESSFUL_EXTRACTION_CARRY_KEY, false))


## 基地 → 新行动地图的出发交接快照（见 `MISSION_OPERATIONS_DEPARTURE_CARRY_KEY`）。
## 与 `_is_successful_extraction_carry_snapshot` 同构：同样只交接玩家所有权与状态。
func _is_mission_operations_departure_carry_snapshot(snapshot: Dictionary) -> bool:
	if not RUN_PERSISTENCE_SERVICE.supports_runtime_snapshot(snapshot):
		return false
	return bool(snapshot.get(MISSION_OPERATIONS_DEPARTURE_CARRY_KEY, false))


## 运行时存档按 runtime_map_id 隔离：旧塔楼（空）只匹配缺失/空的 map id，
## 独立副本只匹配自身 ID，互不续对方的局。
func _snapshot_matches_runtime_map(snapshot: Dictionary) -> bool:
	var snapshot_map := str(snapshot.get("runtime_map_id", ""))
	var self_map := get_runtime_map_id()
	if self_map.is_empty():
		return snapshot_map.is_empty()
	return snapshot_map == self_map


func _build_runtime_world_save_snapshot() -> Dictionary:
	_capture_loaded_runtime_rooms()
	var world_state := RUN_PERSISTENCE_SERVICE.build_world_state(
		"dungeon_world_state_v1", _segment_runtime_state,
		{"narrative_spawned_keys": _narrative_spawned_keys}
	)
	world_state["encounter_events"] = _encounter_event_director.export_snapshot() if _encounter_event_director != null else {
		"schema_version": 1, "next_instance_number": 1, "instances": [],
	}
	return world_state


func _restore_runtime_save_snapshot(snapshot: Dictionary) -> void:
	if not _restore_runtime_world_save_snapshot(snapshot):
		# 世界布局或版本校验失败时保留玩家所有权数据，但拒绝使用旧房间和坐标。
		# 子类可据此回退基地/入口安全点，不能把角色投放进半生成世界。
		snapshot = snapshot.duplicate(true)
		snapshot["world_restore_failed"] = true
		snapshot["current_room_id"] = ""
		snapshot["player_position"] = []
		# 世界被拒绝时路线、商人和撤离解锁也属于旧世界，不能混入新布局。
		snapshot["edge_states"] = {}
		snapshot.erase("merchant_stock")
		snapshot["trade_extraction_unlocked"] = false
		snapshot["trade_extraction_room_id"] = ""
	_restore_carried_ownership(snapshot)
	if not _fate_door_snapshot_to_restore.is_empty():
		call_deferred("_restore_pending_door_fate_overlay")
	_restore_merchant_stock_from_snapshot(snapshot)
	_trade_extraction_unlocked = bool(snapshot.get("trade_extraction_unlocked", false))
	_trade_extraction_room_id = str(snapshot.get("trade_extraction_room_id", ""))
	if _trade_extraction_unlocked and not _trade_extraction_room_id.is_empty():
		var trade_room := _room_by_id.get(_trade_extraction_room_id) as DungeonRoom3D
		if trade_room != null:
			_ensure_conditional_extraction("TRADE", trade_room, Vector3(-4.0, 0.0, 3.0))


func _restore_base_runtime_save_snapshot(snapshot: Dictionary) -> void:
	var restored := snapshot.duplicate(true)
	if not _restore_runtime_world_save_snapshot(snapshot):
		restored["world_restore_failed"] = true
	var base_room_id := "facility" if _room_by_id.has("facility") else "start"
	var base_room := _room_by_id.get(base_room_id) as DungeonRoom3D
	if base_room == null:
		push_error("[Dungeon3D] Base snapshot has no safe spawn room")
		return
	restored["current_room_id"] = base_room_id
	var safe_position := _base_runtime_restore_position(base_room)
	restored["player_position"] = [safe_position.x, safe_position.y, safe_position.z]
	_restore_carried_ownership(restored)
	_restore_merchant_stock_from_snapshot(snapshot)


func _restore_merchant_stock_from_snapshot(snapshot: Dictionary) -> void:
	_merchant_stock_restore_failed = false
	_merchant_service = RUN_MERCHANT_SERVICE_SCRIPT.new()
	if not snapshot.has("merchant_stock"):
		return # 旧档：本局尚未生成商人货架。
	var stock_value: Variant = snapshot.get("merchant_stock")
	if not stock_value is Dictionary or not _merchant_service.restore_stock_snapshot(stock_value as Dictionary):
		_merchant_stock_restore_failed = true
		push_warning("[Dungeon3D] Merchant stock snapshot rejected; merchant stays closed")


func _base_runtime_restore_position(room: DungeonRoom3D) -> Vector3:
	return room.global_position + Vector3.UP * 0.05


## 玩家携带物的所有权恢复 —— 世界、房间与坐标不归这里管。
## 独立副本「撤离信号塔成功返航」只走这一半（见 `_runtime_carry_restore_snapshot`），
## 因此它必须自洽：按快照整格装回，重复调用幂等，不会留下第二份实例。
##
## `restore_location=false` 是「基地 → 新行动地图」出发交专用的读法（见
## `MISSION_OPERATIONS_DEPARTURE_CARRY_KEY`）：所有权与状态照常装回，但房间与坐标
## 一律留给落点场景自己的出生点。不这么做的话，基地快照的 `current_room_id=facility`
## 会在目的地图里被 `_resolve_runtime_restore_room()` 兜底解析成"入口安全房"，
## 把远征刻意的出生点偏移（安全房中心朝前门偏 4m）直接抹掉。
func _export_door_fate_snapshot() -> Dictionary:
	var cards: Array = []
	for index in range(_door_fate_choices.size()):
		var card := _door_fate_choices[index]
		cards.append({
			"stable_card_id": card.get_stable_card_id(),
			"orientation": "REVERSED" if card.is_reversed() else "UPRIGHT",
			"orientation_roll": card.orientation_roll,
			"purchased": bool(_door_fate_purchased[index]) if index < _door_fate_purchased.size() else false,
			"price": int(_fate_door_quote.get(card.get_stable_card_id(), _fate_price(card))),
		})
	return {
		"schema_version": 1,
		"policy": _fate_offer_policy_snapshot.duplicate(true),
		"active": _door_fate_active,
		"offer_id": _fate_door_offer_id,
		"from_id": _pending_fate_door_from_id,
		"target_id": _pending_fate_door_target_id,
		"closing": false,
		"cards": cards,
		"quotes": _fate_door_quote.duplicate(true),
	}


func _import_door_fate_snapshot(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var snapshot: Dictionary = value as Dictionary
	if int(snapshot.get("schema_version", 0)) != 1:
		return false
	var restored_cards: Array[FateCard] = []
	var restored_purchased: Array[bool] = []
	for row_value in snapshot.get("cards", []) as Array:
		if not row_value is Dictionary:
			return false
		var row: Dictionary = row_value as Dictionary
		var stable_id := str(row.get("stable_card_id", ""))
		var card: FateCard = null
		for candidate in FateCardPresets.door_reward_presets():
			if candidate.get_stable_card_id() == stable_id:
				card = candidate
				break
		if card == null:
			return false
		var orientation := FateCard.Orientation.REVERSED if str(row.get("orientation", "UPRIGHT")) in ["REVERSED", "逆位"] else FateCard.Orientation.UPRIGHT
		card.set_orientation(orientation, float(row.get("orientation_roll", 0.0)))
		restored_cards.append(card)
		restored_purchased.append(bool(row.get("purchased", false)))
	_fate_offer_policy_snapshot = (snapshot.get("policy", {}) as Dictionary).duplicate(true)
	_door_fate_choices.assign(restored_cards)
	_door_fate_purchased.assign(restored_purchased)
	_fate_door_offer_id = maxi(0, int(snapshot.get("offer_id", 0)))
	_fate_door_quote = (snapshot.get("quotes", {}) as Dictionary).duplicate(true)
	_pending_fate_door_from_id = str(snapshot.get("from_id", ""))
	_pending_fate_door_target_id = str(snapshot.get("target_id", ""))
	_door_fate_active = bool(snapshot.get("active", false)) and not restored_cards.is_empty()
	_fate_door_snapshot_to_restore = snapshot.duplicate(true) if (
		_door_fate_active or not _pending_fate_door_target_id.is_empty()
	) else {}
	return true


func _restore_pending_door_fate_overlay() -> void:
	if _fate_door_snapshot_to_restore.is_empty() or _fate_overlay != null:
		return
	_fate_door_snapshot_to_restore = {}
	if not _door_fate_active:
		if not _pending_fate_door_target_id.is_empty():
			_show_door_fate_choices()
		return
	_build_door_fate_overlay()
	for index in range(_door_fate_purchased.size()):
		if not _door_fate_purchased[index]:
			continue
		var button := _fate_choice_button(index)
		if button != null:
			button.set_meta("tarot_purchased", true)
			_flip_fate_card_to_back(button, index)
	_refresh_door_fate_prices()
	_sync_player_input_lock()


func _restore_carried_ownership(snapshot: Dictionary, restore_location := true) -> void:
	# 角色在位置恢复期间保持无命运效果，避免安全落点被算成一次进房奖励。
	player.reset_character_fate_state()
	var fate: Variant = snapshot.get("fate_run_state", {})
	var resume_fate: bool = fate is Dictionary and int((fate as Dictionary).get("version", 0)) == 1 and not bool(snapshot.get(SUCCESSFUL_EXTRACTION_CARRY_KEY, false)) and not bool(snapshot.get(MISSION_OPERATIONS_DEPARTURE_CARRY_KEY, false))
	if resume_fate and not bool(snapshot.get("world_restore_failed", false)):
		import_world_fate_snapshot(fate.get("world"))
		_fate_economy.import_snapshot(fate.get("economy", {}))
		_import_door_fate_snapshot(fate.get("door", {}))
	else:
		import_world_fate_snapshot({})
	var backpack := snapshot.get("equipped_backpack_item", {}) as Dictionary
	if player.has_method("clear_equipped_backpack"):
		player.clear_equipped_backpack()
	if not backpack.is_empty():
		player.equip_backpack_item(backpack)
	_inventory.set_capacity(maxi(1, int(snapshot.get("inventory_capacity", BASE_INVENTORY_CAPACITY))))
	var inventory_slots: Variant = snapshot.get("inventory_slots", [])
	if inventory_slots is Array:
		_inventory.restore_slots_snapshot(inventory_slots as Array)
	_insurance.set_max_slots(maxi(16, int(snapshot.get("insurance_capacity", _insurance.get_max_slots()))))
	var insurance_slots: Variant = snapshot.get("insurance_slots", [])
	if insurance_slots is Array:
		_insurance.restore_slots_snapshot(insurance_slots as Array)
	player.clear_all_equipped_weapons()
	player.clear_fate_weapon_cache_for_restore()
	var weapon_items: Variant = snapshot.get("equipped_weapon_items", [])
	if weapon_items is Array:
		for slot_index in mini(2, (weapon_items as Array).size()):
			var item: Variant = (weapon_items as Array)[slot_index]
			if item is Dictionary and not (item as Dictionary).is_empty():
				player.equip_weapon_item_to_slot(item as Dictionary, slot_index)
	var active_slot := clampi(int(snapshot.get("active_weapon_slot", 0)), 0, 1)
	if not player.get_equipped_weapon_item_for_slot(active_slot).is_empty():
		player.switch_weapon_slot(active_slot)
	player.set_weapon_holstered(bool(snapshot.get("weapon_holstered", false)))
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	if flashlight != null:
		player.restore_flashlight_module(str(snapshot.get("flashlight_module_id", "basic")))
		flashlight.set_charge_ratio(float(snapshot.get("flashlight_charge_ratio", 1.0)))
	var quick_slots: Variant = snapshot.get("quick_item_slots", [])
	if quick_slots is Array and not (quick_slots as Array).is_empty():
		_quick_inventory.restore_slots_snapshot(quick_slots as Array)
	else:
		# v2旧档的快捷栏只是背包物品ID引用。首次恢复时把对应整组物品
		# 原子迁入真实快捷槽，避免新旧模型同时拥有同一件物品。
		var legacy_quick_ids := snapshot.get("quick_item_ids", ["", ""]) as Array
		for quick_index in mini(2, legacy_quick_ids.size()):
			var item_id := str(legacy_quick_ids[quick_index])
			var source_slot := _find_inventory_item_slot(item_id)
			if source_slot >= 0:
				_move_inventory_item_to_quick(source_slot, quick_index)
	_sync_quick_item_ids()
	_room_key_count = maxi(0, int(snapshot.get("room_key_count", 1)))
	_run_value = maxi(0, int(snapshot.get("run_value", 0)))
	_kills = maxi(0, int(snapshot.get("kills", 0)))
	GameManager.currency = maxi(0, int(snapshot.get("run_currency", 0)))
	GameManager.currency_changed.emit(GameManager.currency)
	var restored_edges := RUN_PERSISTENCE_SERVICE.merge_known_edge_states(
		_open_edges, snapshot.get("edge_states", {})
	)
	for edge_value in restored_edges.keys():
		var edge := str(edge_value)
		var opened := bool(restored_edges[edge_value])
		_open_edges[edge] = opened
		var edge_rooms := edge.split("|", false, 1)
		if edge_rooms.size() == 2:
			_refresh_edge_visuals(edge_rooms[0], edge_rooms[1], opened)
	if not restored_edges.is_empty():
		minimap.configure(_records, _open_edges)
	if restore_location:
		var room := _resolve_runtime_restore_room(snapshot)
		if room != null:
			_current_room_id = ""
			_on_room_entered(room)
		var saved_position: Variant = snapshot.get("player_position", [])
		var restore_position := _runtime_restore_fallback_position(room)
		if saved_position is Array and (saved_position as Array).size() >= 3:
			var candidate_position := Vector3(
				float((saved_position as Array)[0]),
				float((saved_position as Array)[1]),
				float((saved_position as Array)[2]),
			)
			if room != null and _is_runtime_restore_position_valid(room, candidate_position):
				restore_position = candidate_position
		if room != null:
			player.global_position = restore_position
			player.velocity = Vector3.ZERO
		# 旧存档曾写入约 +/-PI 的玩家根节点旋转，恢复后会连同子相机一起掉头，
		# 造成整幅画面与输入的屏幕相对方向同时反转。固定相机项目中根节点必须归零。
		player.rotation.y = 0.0
	player.import_fate_snapshot(fate.get("player", {}) if resume_fate else {})
	FateCardGameBridge.set_player(player)
	FateCardGameBridge.import_fate_snapshot(fate.get("bridge", {}) if resume_fate else {})
	player.current_hp = clampi(int(snapshot.get("player_hp", player.current_hp)), 1, player.max_hp)
	player.hp_changed.emit(player.current_hp, player.max_hp)
	if _inventory_ui != null:
		_inventory_ui.set_quick_item_module(_quick_inventory)
	_refresh_quick_item_hud()
	_refresh_loot_label()


func _restore_runtime_world_save_snapshot(snapshot: Dictionary) -> bool:
	_segment_runtime_state = RUN_PERSISTENCE_SERVICE.read_segment_runtime_state(snapshot)
	if _encounter_event_director != null:
		var encounter_world_state: Dictionary = snapshot.get("world_state", {}) as Dictionary
		var encounter_state: Variant = encounter_world_state.get("encounter_events", {})
		if encounter_state is Dictionary:
			_encounter_event_director.import_snapshot(encounter_state as Dictionary)
	_restore_narrative_spawned_keys(snapshot)
	return true


func _restore_narrative_spawned_keys(snapshot: Dictionary) -> void:
	_narrative_spawned_keys.clear()
	var world_state := snapshot.get("world_state", {}) as Dictionary
	var saved_keys: Variant = world_state.get("narrative_spawned_keys", {})
	if saved_keys is Dictionary:
		for key_value in (saved_keys as Dictionary).keys():
			var key := str(key_value)
			if not key.is_empty() and bool((saved_keys as Dictionary)[key_value]):
				_narrative_spawned_keys[key] = true


func _resolve_runtime_restore_room(snapshot: Dictionary) -> DungeonRoom3D:
	return _room_by_id.get(str(snapshot.get("current_room_id", ""))) as DungeonRoom3D


func _runtime_restore_fallback_position(room: DungeonRoom3D) -> Vector3:
	return room.global_position + Vector3.UP * 0.05 if room != null else Vector3.ZERO


func _is_runtime_restore_position_valid(room: DungeonRoom3D, world_position: Vector3) -> bool:
	if room == null or not world_position.is_finite():
		return false
	var local := (
		room.to_local(world_position)
		if room.is_inside_tree()
		else world_position - room.position
	)
	var dimensions := room.get_dimensions()
	return (
		absf(local.x) <= dimensions.x * 0.5 + 2.0
		and absf(local.z) <= dimensions.y * 0.5 + 2.0
		and local.y >= -0.6
		and local.y <= 2.5
	)


## 每局只在初始化时从 BaseData 注入模块；局内仍由 PlayerFlashlight3D 拒绝换装。
func _apply_persisted_flashlight_module() -> void:
	if player == null or not player.has_method("restore_flashlight_module"):
		return
	var module_id := BaseManager.get_equipped_flashlight_module_id()
	if not BaseManager.is_flashlight_module_unlocked(module_id):
		module_id = "basic"
	player.restore_flashlight_module(module_id)


func _unhandled_input(event: InputEvent) -> void:
	# 这一组走 InputMap action 而不是硬比 keycode：project.godot 里
	# toggle_floor_map / select_primary_weapon / select_secondary_weapon /
	# use_quick_item_1 / use_quick_item_2 已经绑好 M 与 1/2/3/4；手柄侧由
	# GamepadInput 在运行时补上左摇杆按下 / LB / RB / 十字键左右，
	# 因此键盘与手柄共用同一条通路，键位重绑也自动跟随。
	if event.is_action_pressed("toggle_floor_map"):
		_toggle_full_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("select_primary_weapon") and _can_switch_weapon_slot():
		_select_weapon_slot(0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("select_secondary_weapon") and _can_switch_weapon_slot():
		_select_weapon_slot(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("use_quick_item_1") and _can_switch_weapon_slot():
		_use_quick_item(0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("use_quick_item_2") and _can_switch_weapon_slot():
		_use_quick_item(1)
		get_viewport().set_input_as_handled()
		return
	# 命运卡弹窗的「放弃」走 InputMap action：键盘 ESC 与手柄 B 都能放弃。
	# 硬比 KEY_ESCAPE 只有键盘能触发，手柄的 ui_cancel（B 键）到不了这里
	# —— 与 0808 记录里把 M/1/2/3/4 从硬比 keycode 改成 action 是同一类修正。
	if _door_fate_active and event.is_action_pressed("ui_cancel"):
		_cancel_door_fate_selection()
		get_viewport().set_input_as_handled()
		return
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and (key_event.keycode == KEY_K or key_event.physical_keycode == KEY_K):
		var presentation_panel := _ensure_weapon_presentation_panel()
		if presentation_panel != null:
			presentation_panel.toggle()
			get_viewport().set_input_as_handled()
		return


## 换武器 / 用快捷物品的共同前置：没有独占弹窗、背包没打开。
func _can_switch_weapon_slot() -> bool:
	return not _has_exclusive_modal() and not (
		_inventory_ui != null and _inventory_ui.is_inventory_open()
	)


func get_interaction_candidate(interacting_player: Player3D) -> Dictionary:
	if _completed or interacting_player == null or interacting_player != player:
		return {}
	# 被封住的房间：整房不提供任何门交互（门扇已落下，玩家按不出"开门"）。
	# 放在最前面，先于「最近的门」查询 —— 否则玩家走到门前仍会看到开门提示与圆点。
	if _room_is_sealed(_current_room_id):
		return {}
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if room == null:
		# 子图房间不在 `_room_by_id`（设计 §1：主图与子图刻意隔离）。不补这条，
		# 子图里的房间门永远给不出候选 —— 玩家按 E 没反应，卡在第二间门外。
		return _secret_branch_door_candidate(interacting_player)
	var door_info := room.get_nearest_door(player.global_position)
	if door_info.is_empty() or bool(door_info.get("is_open", false)):
		return {}
	var door := door_info.get("door") as RoomDoor3D
	if door == null:
		return {}
	# 感应门（远征03 的「可开启」态）不按 E：玩家走近它就开。
	# 这类门还给交互圆点/提示，会和自动开合打架，也会让玩家以为门卡住了。
	if not door.is_manual_interaction_enabled():
		return {}
	return _make_door_interaction_candidate(
		door,
		"room_door",
		str(door_info.get("target_room_id", "")),
		80
	)


## 门的文字提示牌退役为纯文案载体；可见反馈统一由常驻圆点承担。
func set_interaction_focus(candidate: Dictionary, focused: bool) -> void:
	var door := candidate.get("door") as RoomDoor3D
	if door != null and is_instance_valid(door):
		door.set_prompt_visible(focused)


## 房间门不是独立 provider，交互候选由本场景统一路由。因此门的常驻圆点也挂在本场景
## 这个 provider 上：锚点取当前候选门的提示位置，没候选（或已通关）时圆点淡出。
func get_interaction_dot_anchor() -> Vector3:
	_refresh_interaction_dot_cache()
	return _dot_anchor_cache


func is_interaction_dot_visible() -> bool:
	_refresh_interaction_dot_cache()
	return _dot_visible_cache


## 每帧最多解析一次候选（TowerDescent3D 的多门路由成本不低）。
func _refresh_interaction_dot_cache() -> void:
	var frame := Engine.get_process_frames()
	if frame == _dot_cache_frame:
		return
	_dot_cache_frame = frame
	var candidate := get_interaction_candidate(player) if player != null else {}
	if candidate.is_empty():
		_dot_visible_cache = false
		_dot_anchor_cache = global_position
		return
	_dot_visible_cache = true
	var raw: Variant = candidate.get("dot_anchor")
	_dot_anchor_cache = (
		raw as Vector3
		if raw is Vector3 and (raw as Vector3).is_finite()
		else global_position + Vector3.UP * 1.7
	)


func perform_interaction(
	interacting_player: Player3D,
	candidate: Dictionary
) -> bool:
	if interacting_player == null or interacting_player != player or _completed:
		return false
	# 子图房间门：不消耗钥匙、不触发命运卡、不要求清房（见 `SecretBranch3D` 的
	# `door_policies`）。这里只做「把那扇门抬起来」。
	if str(candidate.get("mode", "")) == "secret_branch_door":
		return _open_secret_branch_door(candidate.get("door"))
	var target_room_id := str(candidate.get("target_room_id", ""))
	return not target_room_id.is_empty() and _try_open_room_door(target_room_id)


## 子图房间最近的一扇关着的门 → 交互候选。
## 门位与距离判定都在 `SecretBranch3D.nearest_closed_door`（它手里才有子图房间表）。
func _secret_branch_door_candidate(interacting_player: Player3D) -> Dictionary:
	if _secret_branch == null or not is_instance_valid(_secret_branch):
		return {}
	var info := _secret_branch.call(
		"nearest_closed_door", interacting_player.global_position
	) as Dictionary
	if info.is_empty():
		return {}
	var door := info.get("door") as RoomDoor3D
	if door == null or not is_instance_valid(door):
		return {}
	return _make_door_interaction_candidate(
		door, "secret_branch_door", str(info.get("target_room_id", "")), 80
	)


func _open_secret_branch_door(door_value: Variant) -> bool:
	var door := door_value as RoomDoor3D
	if door == null or not is_instance_valid(door) or door.is_open:
		return false
	door.set_open(true)
	status_label.text = "暗室通道已开启"
	if MonsterAIManager != null and player != null:
		MonsterAIManager.broadcast_sound_stimulus(player.global_position, 6.5, "door_open", player)
	return true


func _make_door_interaction_candidate(
	door: RoomDoor3D,
	mode: String,
	target_room_id: String,
	priority: int
) -> Dictionary:
	if door == null or not is_instance_valid(door):
		return {}
	return {
		"available": true,
		"interaction_id": "door:%d:%s" % [door.get_instance_id(), mode],
		"position": door.global_position,
		"priority": priority,
		"prompt": door.get_interaction_prompt_text(),
		"mode": mode,
		"door": door,
		"target_room_id": target_room_id,
		# 供常驻圆点使用的精确锚点：门自己的提示牌位置。
		"dot_anchor": door.get_interaction_dot_anchor(),
	}


## 启动一项独立运行时遭遇事件。配置先由 Owner 完整校验，拒绝不产生刷怪/标志副作用。
func start_encounter_event(config: Dictionary) -> Dictionary:
	if _encounter_event_director == null:
		return {"ok": false, "error": "encounter_event_unavailable"}
	return _encounter_event_director.start(config)


func cancel_encounter_event(instance_id: String, reason: String = "cancelled", despawn := false) -> Dictionary:
	if _encounter_event_director == null:
		return {"ok": false, "error": "encounter_event_unavailable"}
	return _encounter_event_director.cancel(instance_id, reason, despawn)


func get_encounter_event_snapshot(instance_id: String) -> Dictionary:
	if _encounter_event_director == null:
		return {}
	return _encounter_event_director.get_snapshot(instance_id)


func advance_encounter_event(instance_id: String, progress: float) -> Dictionary:
	if _encounter_event_director == null:
		return {"ok": false, "error": "encounter_event_unavailable"}
	return _encounter_event_director.advance_external(instance_id, progress)


func _on_encounter_event_started(snapshot: Dictionary) -> void:
	encounter_event_started.emit(snapshot)


func _on_encounter_event_stage_started(snapshot: Dictionary, stage_index: int) -> void:
	encounter_event_stage_started.emit(snapshot, stage_index)


func _on_encounter_event_finished(snapshot: Dictionary) -> void:
	var event_id := str(snapshot.get("event_id", ""))
	var status := str(snapshot.get("status", ""))
	if str(snapshot.get("status", "")) == "completed" and not event_id.is_empty() and event_id not in _encounter_event_completed_history:
		_encounter_event_completed_history.append(event_id)
	var room_id := str(snapshot.get("room_id", ""))
	if not room_id.is_empty() and _room_encounter_active.has(room_id):
		_room_encounter_active.erase(room_id)
		if status == "completed":
			# 计时到点：不再出新波，但**已出的怪还要打完**。
			# 若此刻场上已空（玩家在到点前刚把最后一波清干净），本房直接判肃清 ——
			# 否则不会再有击杀事件来推动清房判定，房间会一直锁着。
			_try_settle_encounter_room_clear(room_id)
		else:
			# 取消 / 失败一律解封：任何非正常收尾都不能把玩家永久锁死在房里。
			set_room_seal(room_id, false)
	encounter_event_finished.emit(snapshot)
	_queue_runtime_autosave("encounter_event_finished")


## 遭遇收尾补判：场上真的空了 ⇒ 本房肃清。
## 只由 `_on_encounter_event_finished` 调用 —— 正常路径仍走击杀事件。
func _try_settle_encounter_room_clear(room_id: String) -> void:
	if int(_alive_by_room.get(room_id, 0)) > 0 or _reserved_spawn_count(room_id) > 0:
		return
	if not (_enemy_nodes_by_room.get(room_id, []) as Array).is_empty():
		return
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null or room.cleared:
		return
	_mark_room_cleared(room, true)
	status_label.text = "遭遇结束 · 房间肃清，钥匙已掉落"


func _process(delta: float) -> void:
	if _encounter_event_director != null:
		_encounter_event_director.tick(delta)
	_tick_room_encounter_triggers(delta)
	_tick_encounter_countdown_hud()
	_tick_bless_dead(delta)
	_tick_boss_health_bar_delay(delta)
	_tick_player_health_bar_delay(delta)
	_tick_boss_reinforcements(delta)
	_tick_battery_blink(delta)
	_tick_enemy_preactivation(delta)
	_hud_run_elapsed += delta
	var elapsed_seconds := int(_hud_run_elapsed)
	if _hud_timer_label != null and elapsed_seconds != _hud_last_elapsed_second:
		_hud_last_elapsed_second = elapsed_seconds
		_hud_timer_label.text = "%02d:%02d" % [elapsed_seconds / 60, elapsed_seconds % 60]
	_minimap_runtime_accumulator += delta
	if _minimap_runtime_accumulator >= MINIMAP_RUNTIME_INTERVAL:
		_minimap_runtime_accumulator = fmod(
			_minimap_runtime_accumulator, MINIMAP_RUNTIME_INTERVAL
		)
		if _hud_floor_label != null and minimap != null:
			var next_floor_text := _hud_floor_label_text()
			if _hud_floor_label.text != next_floor_text:
				_hud_floor_label.text = next_floor_text
		if minimap != null and player != null:
			minimap.set_player_state(
				player.global_position,
				player.aim_direction
			)
			# 「战斗之外」档（原作默认）要靠这个开关判断当前该不该显示地图：
			# 当前房还有活怪 = 战斗中。取数口与红点同一处，避免两套口径。
			var live_enemies := _get_minimap_enemy_positions()
			minimap.set_enemy_positions(live_enemies)
			minimap.set_in_combat(not live_enemies.is_empty())
			if _full_map_control != null and is_instance_valid(_full_map_control):
				_full_map_control.copy_state_from(minimap)
	_offscreen_indicator_accumulator += delta
	if _offscreen_indicator_accumulator >= OFFSCREEN_INDICATOR_INTERVAL:
		_offscreen_indicator_accumulator = fmod(
			_offscreen_indicator_accumulator, OFFSCREEN_INDICATOR_INTERVAL
		)
		if _offscreen_indicator != null and is_instance_valid(_offscreen_indicator):
			_offscreen_indicator.set_targets(
				_get_offscreen_enemy_positions(),
				get_viewport().get_camera_3d()
			)
	_tick_hud_reload_feedback(delta)


## 换弹反馈（HUD 侧）每帧步进：① 从当前相机投影角色位置；② 保留武器图标弹跳。
## 每帧重算锚点，跟随角色移动、镜头跟随/切换和窗口变化，不依赖武器图标的布局。
##
## 单独成函数（而不是直接写进 `_process`）是为了让验收能**手动步进固定 delta**：
## `verify_reference_hud_fate_visual` 会在冻结 `set_process(false)` 的场景里直接调它，
## 否则"图标弹一下"这条动画契约在无渲染/冻结帧的验收里根本取不到采样点。
func _tick_hud_reload_feedback(delta: float) -> void:
	_place_hud_reload_ring()
	_tick_hud_weapon_icon_pop(delta)


func _place_hud_reload_ring() -> void:
	if not is_instance_valid(_hud_reload_ring):
		return
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(player) or not is_instance_valid(camera):
		_hud_reload_ring.visible = false
		return
	if camera.is_position_behind(player.global_position):
		_hud_reload_ring.visible = false
		return
	# unproject_position 返回视口坐标（非物理窗口像素），逆变换到 HUD 父控件局部坐标。
	var target := camera.unproject_position(player.global_position)
	var parent := _hud_reload_ring.get_parent() as Control
	if parent != null:
		target = parent.get_global_transform_with_canvas().affine_inverse() * target
	target += _hud_size(HUD_RELOAD_RING_CHARACTER_OFFSET_DESIGN)
	_hud_reload_ring.position = target - _hud_reload_ring.size * 0.5
	_hud_reload_ring.visible = _hud_reload_ring_active


func _tick_hud_weapon_icon_pop(delta: float) -> void:
	if _hud_weapon_model_icon == null or not is_instance_valid(_hud_weapon_model_icon):
		return
	if _hud_weapon_icon_pop_elapsed < 0.0:
		return
	if not _hud_weapon_model_icon.visible:
		# 近战/空手时图标本身被隐藏（clear_model）—— 不弹，也不留下半格缩放与残留枢轴。
		_hud_weapon_icon_pop_elapsed = -1.0
		_hud_weapon_model_icon.scale = Vector2.ONE
		_hud_weapon_model_icon.pivot_offset = Vector2.ZERO
		return
	_hud_weapon_icon_pop_elapsed += delta
	var ratio := _hud_weapon_icon_pop_elapsed / HUD_WEAPON_ICON_POP_DURATION
	if ratio >= 1.0:
		_hud_weapon_icon_pop_elapsed = -1.0
		_hud_weapon_model_icon.scale = Vector2.ONE
		_hud_weapon_model_icon.pivot_offset = Vector2.ZERO
		return
	# 绕控件中心缩放：`scale` 的原点是控件左上角，不设 pivot 会朝右下角"长"出去，
	# 看着像整个 HUD 在抖，而不是图标在原地弹。
	_hud_weapon_model_icon.pivot_offset = _hud_weapon_model_icon.size * 0.5
	_hud_weapon_model_icon.scale = Vector2.ONE * hud_weapon_icon_pop_scale(ratio)


## 武器图标「弹一下」的缩放曲线：`t ∈ [0,1]` → 缩放倍率。
##
## 三段、写成**纯函数**：起止都精确归 1、冲高到 `1 + HUD_WEAPON_ICON_POP_PEAK`、
## 回落时略低于 1（回弹感）、收在 1 上不留偏移。
## 纯函数的意义是这条动画能被**逐点断言**（`verify_reference_hud_fate_visual` 直接调它），
## 否则"弹得对不对"只能靠人眼看动画 —— 而那正是本项目吃过亏的地方。
static func hud_weapon_icon_pop_scale(t: float) -> float:
	var clamped := clampf(t, 0.0, 1.0)
	var peak := 1.0 + HUD_WEAPON_ICON_POP_PEAK
	var dip := 1.0 - HUD_WEAPON_ICON_POP_PEAK * 0.35
	var value := peak
	if clamped < HUD_WEAPON_ICON_POP_RISE_SPAN:
		# 起跳到峰值：三次缓出（起步快、到顶慢），不会在 t=0 出现速度突跳。
		var rise := clamped / HUD_WEAPON_ICON_POP_RISE_SPAN
		value = lerpf(1.0, peak, 1.0 - pow(1.0 - rise, 3.0))
	elif clamped < HUD_WEAPON_ICON_POP_RISE_SPAN + HUD_WEAPON_ICON_POP_FALL_SPAN:
		var fall := (clamped - HUD_WEAPON_ICON_POP_RISE_SPAN) / HUD_WEAPON_ICON_POP_FALL_SPAN
		value = lerpf(peak, dip, fall * fall * (3.0 - 2.0 * fall))
	else:
		var settle := (clamped - HUD_WEAPON_ICON_POP_RISE_SPAN - HUD_WEAPON_ICON_POP_FALL_SPAN) / HUD_WEAPON_ICON_POP_SETTLE_SPAN
		value = lerpf(dip, 1.0, settle * settle * (3.0 - 2.0 * settle))
	return value


func _on_player_reload_progress_changed(progress: float, _remaining: float) -> void:
	if _hud_reload_ring == null:
		return
	if not _hud_reload_ring_active:
		# 只有**这一轮换弹的第一次**推送才起弹跳；之后的进度推送不动图标。
		_hud_reload_ring_active = true
		_hud_weapon_icon_pop_elapsed = 0.0
	# 进度 0 也可见：那是一圈"空槽"，与退役的世界环同口径（0 是"刚开始装填"，不是"没在装填"）。
	_hud_reload_ring.progress = progress
	_place_hud_reload_ring()


func _on_player_reload_ended(_completed: bool) -> void:
	_hud_reload_ring_active = false
	if _hud_reload_ring == null:
		return
	# 取消/切枪/死亡都会走到这里（reload_ended(false)），环一并收干净。
	_hud_reload_ring.progress = 0.0
	_hud_reload_ring.visible = false


## HUD 右上、小地图正上方那块「当前所处区域」标签的文案。
## 塔楼口径是「高塔外层 · <层或 LIVE>」；单层独立关卡必须覆写它，
## 否则会一直顶着塔楼语义（既没有「高塔外层」也没有楼层号）。
func _hud_floor_label_text() -> String:
	return "高塔外层 · %s" % minimap.get_floor_label()


## 装载关卡级怪物规则（远征01 专属）。由 `TowerDescent3D` 在 bootstrap 拿到 plan 时调一次。
## 空字典合法 = 本关未配置 ⇒ 全部回退全局常量。
func set_monster_rules(rules: Dictionary) -> void:
	_monster_rules = rules.duplicate(true) if rules != null else {}
	if _monster_injector != null:
		_monster_injector.set_level_rules(_monster_rules)
	# 货币分档同步给奖励协调器：货币是**独立通道**，不经过 MonsterInjector。
	if _reward_coordinator != null:
		_reward_coordinator.configure_level_currency(
			_monster_rules.get("currency", {}) as Dictionary
		)


## 远征命运经济只从当前关卡设计源的真实刷怪盒/遭遇编成建模。
## 这里不触碰商人、背包或训练 UI；纯服务只接收数据并冻结报价。
##
## **关卡无关**：本函数不判断 `level_id` 是否等于某个具体关卡。
## 任何远征关卡只要 `plan` 非空、能从中读出真实编成，就会被建模并置 `_configured = true`；
## 读不出（空 plan / 缺编成）时 `configure_from_runtime` 会保持未配置，
## 消费方统一经 `uses_dynamic_fate_economy()` 回退到历史固定价格表。
##
## ⚠️ 历史上这里写的是 `level_id != "expedition_01" → return`，那会造成自锁：
## 新增关卡永远不配置经济 ⇒ `is_configured()` 恒假 ⇒ 永远拿不到逐门定价。
## 新增关卡时**不要**在这里补 `== "expedition_0N"`，见
## [关卡接入规范](../../docs/v0.1/关卡接入规范.md) §3。
func configure_expedition_fate_economy(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	var box_catalog: Dictionary = {}
	for box_id_value in SPAWN_BOX_CATALOG_SCRIPT.all_ids():
		var box_id := str(box_id_value)
		box_catalog[box_id] = SPAWN_BOX_CATALOG_SCRIPT.load_box(box_id)
	var rooms: Array = plan.get("rooms", []) as Array
	var floor := maxi(1, visual_theme.difficulty_rank if visual_theme != null else 1)
	_fate_economy.configure_from_runtime(
		rooms,
		box_catalog,
		(_monster_rules.get("currency", {}) as Dictionary),
		floor,
		maxi(1, int(plan.get("content_room_count", 10))),
		float((_monster_rules.get("strong_variant", {}) as Dictionary).get("chance", 0.0))
	)


## **唯一判据**：本局是否使用「关卡级动态命运经济」（逐门定价 / 稀有度解锁 / 报价区间）。
##
## 只看能力，不看关卡 ID：
## - 为真 ⇒ 报价取 `_fate_economy` 的冻结快照，同门同价、可恢复；
## - 为假 ⇒ 回退历史固定价格表 `FATE_PRICE_BY_RARITY`（塔楼与非远征路径）。
##
## ❗ 这是全文件**唯一**允许判断"要不要用动态经济"的地方。
## 新增关卡时不要在别处再写 `get_runtime_map_id() == "expedition_0N"`：
## 那个写法会让新关卡在配置环节被挡掉、在消费环节却以为已配置，
## 形成"永远走不到"的死分支。见 [关卡接入规范](../../docs/v0.1/关卡接入规范.md) §3。
func uses_dynamic_fate_economy() -> bool:
	return _fate_economy.is_configured()


## 取关卡级 AI 参数（`monster_rules.ai.<key>`）。键不存在 ⇒ 回退传入的全局常量，
## 于是「未配置本段」与「配了但没写这个键」两种情形行为都逐字不变。
func _ai_param(key: String, fallback: Variant) -> Variant:
	var ai: Dictionary = _monster_rules.get("ai", {}) as Dictionary
	return ai.get(key, fallback)


func _tick_enemy_preactivation(delta: float) -> void:
	_enemy_preactivation_accumulator += delta
	if _enemy_preactivation_accumulator < ENEMY_PREACTIVATION_INTERVAL:
		return
	_enemy_preactivation_accumulator = fmod(
		_enemy_preactivation_accumulator, ENEMY_PREACTIVATION_INTERVAL
	)
	if player == null:
		return
	# 预激活半径可由关卡级规则覆盖（远征01）：默认 38 m = 现有全局常量。
	var preactivation_range := float(_ai_param("preactivation_range_m", ENEMY_PREACTIVATION_RANGE))
	var candidates: Array[Node3D] = (
		GameplaySpatialRegistry3D.query_radius(
			player.global_position,
			preactivation_range,
			[GameplaySpatialRegistry3D.KIND_ENEMY]
		)
		if GameplaySpatialRegistry3D != null
		else []
	)
	for value in candidates:
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and is_ancestor_of(enemy):
			enemy.activate_from_player_proximity(player, preactivation_range)


func _setup_run_modules() -> void:
	GameManager.currency = 0
	GameManager.currency_changed.emit(0)
	_inventory = InventoryModule.new(BASE_INVENTORY_CAPACITY)
	player.set_reload_ammo_provider(Callable(self, "_provide_reload_ammo"))
	_insurance = InsuranceModule.new()
	_quick_inventory = InventoryModule.new(2)
	_death_settlement = DeathSettlementModule.new()
	if not test_mode and BaseManager != null and _accepts_pending_insurance_return_at_spawn():
		var pending_insurance := BaseManager.get_pending_insurance_slots()
		if not pending_insurance.is_empty():
			var restored_slots: Array[Dictionary] = []
			restored_slots.resize(_insurance.get_max_slots())
			for index in restored_slots.size():
				restored_slots[index] = {}
			for entry in pending_insurance:
				var target_index := clampi(
					int(entry.get("insurance_slot", 0)), 0, restored_slots.size() - 1
				)
				if not restored_slots[target_index].is_empty():
					target_index = restored_slots.find({})
				if target_index < 0:
					break
				restored_slots[target_index] = (entry as Dictionary).duplicate(true)
			_insurance.restore_slots_snapshot(restored_slots)
			_pending_insurance_return_restore = _insurance.get_used_slots() > 0
	_loot_module = LootModule.new()
	_loot_module.set_seed(run_seed ^ 0x4C4F4F54)
	_reward_coordinator = RUNTIME_REWARD_COORDINATOR_SCRIPT.new()
	_reward_coordinator.configure(run_seed ^ 0x52455744)
	_monster_injector = MonsterInjector.new()
	_monster_injector.set_seed(run_seed ^ 0x454E454D)
	_monster_injector.set_theme_profile(gameplay_theme)
	_monster_injector.set_level_rules(_monster_rules)
	_encounter_event_host = ENCOUNTER_EVENT_HOST_SCRIPT.new(self)
	_encounter_event_director = ENCOUNTER_EVENT_DIRECTOR_SCRIPT.new(_encounter_event_host)
	_encounter_event_director.encounter_event_started.connect(_on_encounter_event_started)
	_encounter_event_director.encounter_event_stage_started.connect(_on_encounter_event_stage_started)
	_encounter_event_director.encounter_event_finished.connect(_on_encounter_event_finished)
	if not test_mode and BaseManager != null:
		for staged in BaseManager.consume_pending_loadout():
			if not staged is Dictionary:
				continue
			var item := (staged as Dictionary).duplicate(true)
			var requested := int(item.get("count", 1))
			var added := _inventory.add_item(item, requested)
			if added < requested:
				item["count"] = requested - added
				BaseManager.add_vault_item(item)
	# 保底武装配套：白送手枪每次装配场景都会给，弹药按同一生命周期补一份，
	# 否则「返城时手上有一把枪」实际是枪 + 0 发备弹，弹匣打空就再也打不响。
	# 与 consume_pending_loadout 同一条边界，不读开发者真实档案的测试路径不受影响。
	if not test_mode:
		_grant_guaranteed_loadout_ammo()
	_inventory.inventory_changed.connect(_refresh_loot_label)
	GameManager.currency_changed.connect(_on_run_currency_changed)
	_inventory_ui = InventoryUI.new()
	_inventory_ui.name = "InventoryUI3D"
	_inventory_ui.accept_tab_shortcut = true
	$HUD.add_child(_inventory_ui)
	_inventory_ui.set_inventory_module(_inventory)
	_inventory_ui.set_insurance_module(_insurance)
	_inventory_ui.set_quick_item_module(_quick_inventory)
	_inventory_ui.set_weapon_tree(player.get_weapon_tree())
	_inventory_ui.set_weapon_owner(player)
	_inventory_ui.set_backpack_owner(self)
	_inventory_ui.set_world_drop_handler(_drop_inventory_item_to_world)
	_inventory_ui.item_to_insurance_requested.connect(_on_insure_item_requested)
	_inventory_ui.item_to_insurance_slot_requested.connect(_on_insure_item_to_slot_requested)
	_inventory_ui.item_extraction_requested.connect(_on_claim_insurance_requested)
	_inventory_ui.insurance_item_move_requested.connect(_on_insurance_item_move_requested)
	_inventory_ui.item_clicked.connect(_on_inventory_item_clicked)
	_inventory_ui.inventory_open_changed.connect(_on_inventory_open_changed)
	_inventory_ui.weapon_slot_equip_requested.connect(_on_weapon_slot_equip_requested)
	_inventory_ui.equipped_weapon_to_inventory_requested.connect(_on_equipped_weapon_to_inventory_requested)
	_inventory_ui.equipped_weapon_drop_requested.connect(_on_equipped_weapon_drop_requested)
	_inventory_ui.attachment_slot_install_requested.connect(_on_attachment_slot_install_requested)
	_inventory_ui.attachment_slot_remove_requested.connect(_on_attachment_slot_remove_requested)
	_inventory_ui.attachment_slot_drop_requested.connect(_on_attachment_slot_drop_requested)
	_inventory_ui.bullet_module_install_requested.connect(_on_bullet_module_install_requested)
	_inventory_ui.backpack_slot_equip_requested.connect(_on_backpack_slot_equip_requested)
	_inventory_ui.equipped_backpack_to_inventory_requested.connect(_on_equipped_backpack_to_inventory_requested)
	_inventory_ui.equipped_backpack_drop_requested.connect(_on_equipped_backpack_drop_requested)
	_inventory_ui.quick_item_assignment_requested.connect(_on_quick_item_assignment_requested)
	_inventory_ui.inventory_item_to_quick_requested.connect(_on_inventory_item_to_quick_requested)
	_inventory_ui.quick_item_move_requested.connect(_on_quick_item_move_requested)
	_inventory_ui.quick_item_use_requested.connect(_use_quick_item)
	_sync_quick_item_state()


## 保底武装配套弹药：把入场即得的通用备弹放进主背包。
## 与白送手枪同一条生命周期（每次装配战局/基地场景都会重新给），因此续档恢复
## 会在 `_restore_runtime_save_snapshot()` 里被存档快照整格覆盖，不会重复累计。
## 返回实际入包发数；背包格位被占满时可能少于 `GUARANTEED_LOADOUT_AMMO_ROUNDS`。

func _grant_guaranteed_loadout_ammo() -> int:
	if _inventory == null or GUARANTEED_LOADOUT_AMMO_ROUNDS <= 0:
		return 0
	var report := _reward_coordinator.resolve_fixed_item(
		"item_ammo_pack", GUARANTEED_LOADOUT_AMMO_ROUNDS, "guaranteed_loadout_ammo"
	)
	if not bool(report.get("ok", false)):
		return 0
	var grants := report.get("grants", []) as Array
	var ammo_grant := grants[0] as Dictionary if not grants.is_empty() else {}
	var ammo := (ammo_grant.get("item", {}) as Dictionary).duplicate(true)
	if ammo.is_empty():
		return 0
	var ammo_count := int(ammo_grant.get("count", GUARANTEED_LOADOUT_AMMO_ROUNDS))
	ammo["count"] = ammo_count
	var added := _inventory.add_item(ammo, ammo_count)
	if added > 0:
		_refresh_loot_label()
	return added


## 供验收读取的保底备弹发数；内容数值的唯一出口，禁止在测试里重复写死数字。
func get_guaranteed_loadout_ammo_rounds() -> int:
	return GUARANTEED_LOADOUT_AMMO_ROUNDS


## 武器表现页只在玩家首次按 K 时创建。隐藏的完整树面板无需常驻 HUD，
## 这既保持真实输入契约，也把固定 UI 壳节点留在性能预算内。
func _ensure_weapon_presentation_panel() -> WeaponAssemblyTreePanel:
	if _weapon_panel != null and is_instance_valid(_weapon_panel):
		return _weapon_panel
	_weapon_panel = WEAPON_PRESENTATION_SCENE.instantiate() as WeaponAssemblyTreePanel
	if _weapon_panel != null:
		_weapon_panel.name = "WeaponPresentationPage3D"
		$HUD.add_child(_weapon_panel)
		# 独立管理页居中覆盖战场，与背包/基地设施的模态信息架构一致。
		# Godot 4 中 Control.position 当锐点都是 0.5 时会直接成为全局位置（不是相对父容器中心偏移），
		# 所以需要从 viewport size 计算使面板中心 = 屏幕中心。
		_weapon_panel.set_anchors_preset(Control.PRESET_CENTER)
		var _vp_size: Vector2i = get_viewport().get_visible_rect().size
		var _panel_size := Vector2(520.0, 620.0)
		_weapon_panel.size = _panel_size
		_weapon_panel.position = Vector2(
			(_vp_size.x - _panel_size.x) * 0.5,
			(_vp_size.y - _panel_size.y) * 0.5
		)
		_weapon_panel.z_index = 420
		_weapon_panel.set_weapon_tree(player.get_weapon_tree())
		_weapon_panel.set_weapon_owner(player)
	return _weapon_panel


func _accepts_pending_insurance_return_at_spawn() -> bool:
	return false


func _install_holographic_hud_style() -> void:
	# 原节点路径仍由自动化读取；视觉层改由独立锚点控件承载。
	($HUD/TopBar as Control).visible = false
	($HUD/StatusPanel as Control).visible = false
	($HUD/ControlHint as Control).visible = false
	($HUD/VisionHint as Control).visible = false
	_build_reference_main_hud()
	_install_offscreen_enemy_indicator()

	# 2026-10-17 主人要求：主 HUD 的背框全部撤掉，撤离进度条外壳同样改为全透明。
	# 进度条本体（background + fill）保留 —— 那是内容，不是背板。
	extraction_panel.add_theme_stylebox_override("panel", _make_bare_hud_style())
	_anchor_control(extraction_panel, 0.5, 1.0, 0.5, 1.0, -250, -252, 250, -184)
	extraction_bar.custom_minimum_size = _hud_size(Vector2(460, 22))
	var progress_background := StyleBoxFlat.new()
	progress_background.bg_color = Color(1.0, 1.0, 1.0, 0.16)
	progress_background.border_color = UIPalette.PRISM_LINE_SOFT
	progress_background.set_border_width_all(1)
	progress_background.set_corner_radius_all(1)
	extraction_bar.add_theme_stylebox_override("background", progress_background)
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = UIPalette.PRISM_ACCENT
	progress_fill.set_corner_radius_all(1)
	progress_fill.shadow_size = 0
	extraction_bar.add_theme_stylebox_override("fill", progress_fill)



func _build_reference_main_hud() -> void:
	_reference_hud_root = Control.new()
	_reference_hud_root.name = "ReferenceCombatHUD"
	_reference_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reference_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reference_hud_root.z_index = 100
	$HUD.add_child(_reference_hud_root)

	var cyan := Color(0.23, 0.88, 1.0)
	var subdued := Color(0.62, 0.74, 0.82)
	var identity := _make_hud_label("弹壳风暴 2  |  向下，寻找世界的答案", 15, Color(0.86, 0.92, 0.96))
	_anchor_control(identity, 0.0, 0.0, 0.0, 0.0, 18, 10, 520, 36)
	_reference_hud_root.add_child(identity)

	room_label = _make_hud_label("ROOM", 14, Color(0.60, 0.90, 1.0))
	room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_control(room_label, 0.5, 0.0, 0.5, 0.0, -220, 14, 220, 38)
	_reference_hud_root.add_child(room_label)
	_hud_wave_label = _make_hud_label("波次 —", 14, Color(0.98, 0.78, 0.32))
	_hud_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_control(_hud_wave_label, 0.5, 0.0, 0.5, 0.0, -220, 40, 220, 62)
	_reference_hud_root.add_child(_hud_wave_label)

	var player_panel := _make_hud_panel(cyan, Color(0.006, 0.018, 0.030, 0.88))
	# 2026-10-17 主人要求：主 HUD 的背框（底衬 + 描边 + 四角括号）**全部撤掉** —— 太占视野。
	# 统一收敛到 `_make_bare_hud_style()` 的全透明外壳：内边距仍由内层 MarginContainer 承担，
	# 所以血条 / 电芯 / 文字的落位一像素不动；可读性交给 `_make_hud_label` 自带的描边兜底。
	player_panel.add_theme_stylebox_override("panel", _make_bare_hud_style())
	player_panel.name = "PlayerStatusBlock"
	_anchor_control(player_panel, 0.0, 0.0, 0.0, 0.0, 18, 44, 358, 174)
	_reference_hud_root.add_child(player_panel)
	# tap 头像 → 切换背包（键 I / Tab 等效）
	player_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	player_panel.tooltip_text = "点击打开/关闭背包 [键 I / Tab]"
	player_panel.gui_input.connect(_on_player_status_gui_input.bind(player_panel))
	var player_margin := _make_margin(12, 8, 12, 8)
	player_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_panel.add_child(player_margin)
	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", _hud_int(12))
	player_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_margin.add_child(player_row)
	var portrait := CODE_HUD_GLYPH_SCRIPT.new() as CodeHUDGlyph
	portrait.custom_minimum_size = _hud_size(Vector2(82, 82))
	portrait.configure("robot", Color(1.0, 0.25, 0.84))
	portrait.visible = false
	player_row.add_child(portrait)
	var stat_vbox := VBoxContainer.new()
	stat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	stat_vbox.add_theme_constant_override("separation", _hud_int(6))
	player_row.add_child(stat_vbox)
	# 对标《逃离鸭科夫》圆角胶囊血条：HP 读数直接居中嵌在圆角红血条正中央，省去上方冗余独立行
	var hp_stack := Control.new()
	hp_stack.name = "PlayerHealthBarStack"
	hp_stack.custom_minimum_size = _hud_size(Vector2(220, 26))
	hp_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_vbox.add_child(hp_stack)
	_player_delayed_bar = ProgressBar.new()
	_player_delayed_bar.name = "PlayerHealthBarDelayed"
	_player_delayed_bar.custom_minimum_size = _hud_size(Vector2(220, 26))
	_player_delayed_bar.show_percentage = false
	_player_delayed_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player_delayed_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hp_bg_style := _make_bar_style(UIPalette.PRISM_HP_BG, 1)
	hp_bg_style.border_color = Color(1.0, 1.0, 1.0, 0.30)
	hp_bg_style.set_border_width_all(1)
	_player_delayed_bar.add_theme_stylebox_override("background", hp_bg_style)
	_player_delayed_bar.add_theme_stylebox_override(
		"fill", _make_bar_style(HUD_HEALTH_BAR_DELAY_COLOR, 1)
	)
	hp_stack.add_child(_player_delayed_bar)
	hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.custom_minimum_size = _hud_size(Vector2(220, 26))
	hp_bar.show_percentage = false
	hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.12, 0.02, 0.04, 0.0), 1))
	# 平红实心条，无辉光 —— 棱镜语言的条是"色块"，不是"发光管"
	var hp_fill := _make_bar_style(UIPalette.PRISM_HP_RED, 1)
	hp_fill.shadow_size = 0
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_stack.add_child(hp_bar)
	hp_label = _make_hud_label("230 / 230", 16, Color.WHITE)
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_stack.add_child(hp_label)
	var energy := HBoxContainer.new()
	energy.name = "FlashlightBatteryPanel"
	energy.custom_minimum_size = _hud_size(Vector2(220, 18))
	energy.add_theme_constant_override("separation", _hud_int(6))
	energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_vbox.add_child(energy)
	_hud_battery_panel = energy
	for index in range(3):
		var pip := Panel.new()
		pip.name = "BatteryCell_%d" % index
		pip.custom_minimum_size = _hud_size(Vector2(34, 11))
		pip.add_theme_stylebox_override(
			"panel",
			_make_prism_hud_card_style(UIPalette.PRISM_LINE, 0.46, 1, 1)
		)
		energy.add_child(pip)
		_hud_battery_cells.append(pip)
	_hud_battery_time_label = _make_hud_label("基地内暂停耗电 · 100%", 12, Color(0.84, 0.92, 0.98))
	_hud_battery_time_label.name = "BatteryTimeLabel"
	_hud_battery_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_battery_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	energy.add_child(_hud_battery_time_label)
	for label in [hp_label, _hud_battery_time_label]:
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.88))
		label.add_theme_constant_override("outline_size", 4)


	seed_label = _make_hud_label("SEED", 12, subdued)
	_anchor_control(seed_label, 0.0, 0.0, 0.0, 0.0, 22, 180, 360, 202)
	_reference_hud_root.add_child(seed_label)

	# 右上角小地图：**2026-10-28 起改为"挺进地牢式"矩形拼图**（业主指令）。
	# 与 2026-09-28 退役的圆形雷达不是同一个形态：不跟随玩家、不居中、不裁圆，
	# 固定缩放、右上贴边、房间是"填充+描边+门洞"的矩形块，房型靠图标区分。
	# 规格与依据：docs/v0.1/reference/挺进地牢/minimap实现方式.md
	# 节点名与路径保持不变 —— 多枚探针直接读 get_node("HUD/DungeonMinimap3D")。
	minimap.z_index = 105
	# 设计盒 382×265（×HUD_UI_SCALE 0.8 ⇒ 305.6×212 canvas）。
	# 2026-10-29 业主指令：**去掉半透明底 + 整体缩到业主红框的大小**。
	# 红框在实机截图（1280×720，与 canvas 1:1）上的包围盒是 x 962..1267、y 40..251，
	# 反推设计 px：宽 306/0.8=382.5、高 212/0.8=265 ⇒ 取 382×265；
	# 右缘距屏幕右 13 canvas px ⇒ offset_right=-16（设计 px）；
	# 上缘 40 canvas px ⇒ offset_top=50。
	# 上一版是 458×346（⇒366×277 canvas），因为面板太大糊掉半个右上角 ——
	# 业主直接标了红框要求缩小。这个盒是**上限**，楼层更方时会自动填满（缩放按盒夹紧）。
	_anchor_control(minimap, 1.0, 0.0, 1.0, 0.0, -398, 50, -16, 315)
	minimap.visible = true
	# tap 小地图 → 切换全层地图（键 M 等效）
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.tooltip_text = "点击打开/关闭全层地图 [键 M]"
	minimap.gui_input.connect(_on_radar_gui_input.bind(minimap))
	_hud_floor_label = _make_hud_label("高塔外层", 15, Color(0.90, 0.94, 0.96))
	_hud_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_control(_hud_floor_label, 1.0, 0.0, 1.0, 0.0, -300, 12, -12, 38)
	_reference_hud_root.add_child(_hud_floor_label)

	# —— 右上角遭遇倒计时环（2026-10-16）——
	# 位置按业主标注：右上角，落在世界时间（`WorldDateTimeHUD`，右缘 -18、y 48..98）
	# 正下方。右缘与世界时间对齐同一列 —— 两块右边缘对齐才不会是"一高一低地飘"。
	# 外径 = -126 到 -18 = 108 设计 px，与 `ENCOUNTER_COUNTDOWN_RING_DIAMETER_DESIGN` 同值。
	# 2026-10-28 业主裁定：**挪到画面左下方**。原位置（右上 1.0/0.0 锚点）与小地图矩形拼图
	# 在 y 100..208 必叠，环压在地图上读数虽不被盖住，但两块 UI 抢同一块空间。
	# 改锚 (0.0, 1.0, 0.0, 1.0) = 相对**左下角**定位，地图与环从此分居屏幕两侧，结构上不可能重叠。
	# 落点 40..148 / -148..-40（设计 px）：距左边缘 40、距底边 40。
	# 同区域核查过不撞：`hint` 是居中锚（x 280..1000），`extraction_panel` 居中（x 390..890），
	# `weapon_panel` / `loot_label` 在右下，左侧 y 500 以下原本全空。
	_hud_countdown_ring = ENCOUNTER_COUNTDOWN_RING_SCRIPT.new() as EncounterCountdownRing
	_hud_countdown_ring.name = "EncounterCountdownRing"
	_hud_countdown_ring.visible = false
	_hud_countdown_ring.z_index = 120
	_anchor_control(_hud_countdown_ring, 0.0, 1.0, 0.0, 1.0, 40, -148, 148, -40)
	_reference_hud_root.add_child(_hud_countdown_ring)
	# 中间那行时间「用下方金币的字体」= 与右下 `RunLootReadout` **同一个** `_make_hud_label`
	# 口径（同字号 26、同 `RUN_COIN_READOUT_COLOR`、同 `_outline_labels` 描边）。
	# 环本身也取同一色系（见 `EncounterCountdownRing.FILL_COLOR`），
	# 否则"金币字体"那句话只落实了一半：字是金的、圈是青的。
	var countdown_label := _make_hud_label("1:00", 26, RUN_COIN_READOUT_COLOR)
	_outline_labels([countdown_label])
	_hud_countdown_ring.bind_label(countdown_label)
	# 2026-09-28 主人要求：右侧两块「时间」分开处置 —— 下面的本局计时栏（「◷ 00:12 ⏸」）
	# 整个去掉，上面的世界时间只去背板（见 TowerDescent3D._install_world_time_hud）。
	# 只隐藏外壳、不删节点：_update_hud_timer 仍每帧写 _hud_timer_label.text，
	# 节点在树上才不会让那处空引用；将来要恢复也只需删掉下面这一行。
	# 显式命个名：此前它只有自动名 @PanelContainer@N，调试与探针只能按内容猜。
	var timer_panel := _make_bare_hud_panel()
	timer_panel.name = "SessionTimerPanel"
	_anchor_control(timer_panel, 1.0, 0.0, 1.0, 0.0, -214, 318, -18, 358)
	_reference_hud_root.add_child(timer_panel)
	timer_panel.visible = false
	var timer_row := HBoxContainer.new()
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_row.add_theme_constant_override("separation", _hud_int(16))
	timer_panel.add_child(timer_row)
	var timer_caption := _make_hud_label("◷", 18, Color.WHITE)
	timer_row.add_child(timer_caption)
	_hud_timer_label = _make_hud_label("00:00", 17, Color.WHITE)
	timer_row.add_child(_hud_timer_label)
	var pause_icon := CODE_HUD_GLYPH_SCRIPT.new() as CodeHUDGlyph
	pause_icon.custom_minimum_size = _hud_size(Vector2(30, 30))
	pause_icon.configure("pause", Color(0.84, 0.90, 0.96))
	timer_row.add_child(pause_icon)
	_outline_labels([timer_caption, _hud_timer_label])

	var info_panel := _make_hud_panel(cyan, Color(0.008, 0.035, 0.052, 0.50))
	info_panel.name = "CurrentInfoPanel"
	# 放到左侧目标卡下方，避免继续遮挡角色前方与中央战斗视野。
	_anchor_control(info_panel, 0.0, 0.0, 0.0, 0.0, 18, 370, 338, 425)
	_reference_hud_root.add_child(info_panel)
	var info_margin := _make_margin(10, 5, 10, 5)
	info_panel.add_child(info_margin)
	status_label = _make_hud_label("正在建立行动区……", 11, Color(0.76, 0.91, 0.98))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_margin.add_child(status_label)
	# 2026-09-28 主人要求：任务卡下方那条状态栏（「返回已探索房间 · 已肃清」等）不再显示。
	# 只隐藏外壳：status_label 仍在树上可读写 text —— 多枚探针（门通行提示、波次间歇、
	# 远征 01 门未开诊断、奖励落地回执、有限弹药）都读它的 text，隐藏不影响那些断言。
	info_panel.visible = false

	# 2026-09-28 主人要求（第五轮）：武器栏精简并**挪到右下角**。只保留三项有效信息 ——
	# 枪械模型图标、当前子弹数 · N备弹、命运卡槽占用（0/4）；武器名与「实例 #… · K 详情」
	# 两行不再显示；字号放大。背板口径不变：仍是全透明外壳（_make_bare_hud_panel），
	# 下方 QuickItemHUD_0/1 两块保持原位不动。
	var weapon_panel := _make_bare_hud_panel()
	weapon_panel.name = "CurrentWeaponPanel"
	# 2026-10-17 主人要求：右下武器栏同样撤掉背框（`_make_bare_hud_panel` 已是全透明外壳，
	# 原先附加的棱镜卡片底衬 + 四角括号在此删除）。弹药读数靠描边压在实景上仍然清晰。
	# 右下角。offset 仍是 canvas 坐标、且会被 ×HUD_UI_SCALE：350×70 → 实际 280×56，
	# 落在 verify_finite_ammo_flow 的「250..312 × 44..59」尺寸契约内（内容更小 ⇒ 由锚框决定）。
	_anchor_control(weapon_panel, 1.0, 1.0, 1.0, 1.0, -368, -90, -18, -20)
	_reference_hud_root.add_child(weapon_panel)
	# 右下武器栏：tap 在主武器 / 副武器 之间切换（_on_ammo_changed 里 [N] 会自动反映新槽位）
	weapon_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	weapon_panel.tooltip_text = "点击切换主/副武器 [键 1 / 2]"
	weapon_panel.gui_input.connect(_on_weapon_panel_gui_input.bind(weapon_panel))
	var weapon_margin := _make_margin(8, 4, 10, 4)
	weapon_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_panel.add_child(weapon_margin)
	var weapon_row := HBoxContainer.new()
	# 内容靠右贴角：面板宽度由锚框（280）撑住，内容只有约 200 ⇒ 右侧对齐才不会飘在中间。
	weapon_row.alignment = BoxContainer.ALIGNMENT_END
	weapon_row.add_theme_constant_override("separation", _hud_int(8))
	weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_margin.add_child(weapon_row)
	# 棱镜实体白底黑字方键帽 [1/2]
	var weapon_keycap := UIStyleFactory.make_prism_keycap_badge("1", _hud_int(12), _hud_size(Vector2(22, 20)))
	weapon_keycap.name = "WeaponSlotKeycap"
	weapon_keycap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	weapon_row.add_child(weapon_keycap)
	_hud_weapon_model_icon = ITEM_MODEL_ICON_SCENE.instantiate() as ItemModelIcon3D
	_hud_weapon_model_icon.name = "CurrentWeaponModelIcon3D"
	_hud_weapon_model_icon.custom_minimum_size = _hud_size(Vector2(60, 44))
	_hud_weapon_model_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hud_weapon_model_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(_hud_weapon_model_icon)
	_refresh_hud_weapon_model(true)
	# 有效信息一：当前子弹数 · N备弹（不再显示弹匣容量）。font 26×0.8 → 21 px。
	ammo_label = _make_hud_label("0 · 0备弹", 26, Color.WHITE)
	ammo_label.custom_minimum_size = _hud_size(Vector2(92, 42))
	ammo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(ammo_label)
	# 有效信息二：命运卡槽占用，只留「已用/容量」。天青色小号，与左边白色弹药数区分开。
	_hud_weapon_fate_label = _make_hud_label("0/0", 15, UIPalette.PRISM_ACCENT)
	_hud_weapon_fate_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_weapon_fate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(_hud_weapon_fate_label)
	# 武器名（[N] 名称 · 主/副武器）：主人要求「其它文字不要」⇒ 不再显示。
	# 但节点保留在树上并继续接收 weapon_meta_text —— Presenter 的只读投影契约
	# （verify_hud_presenter_3d）要求该字段逐字产出，删节点会让写入路径空引用。
	_hud_weapon_meta_label = _make_hud_label("当前武器 · 未装备", 9, Color(0.92, 0.95, 0.98))
	_hud_weapon_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_weapon_meta_label.visible = false
	weapon_panel.add_child(_hud_weapon_meta_label)
	_outline_labels([ammo_label, _hud_weapon_fate_label])
	# 有效信息三（2026-10-15）：右下角只显示本局金币（保持字号26与右对齐契约）。
	loot_label = _make_hud_label("金币 0", 26, RUN_COIN_READOUT_COLOR)
	loot_label.name = "RunLootReadout"
	loot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	loot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_anchor_control(loot_label, 1.0, 1.0, 1.0, 1.0, -420, -148, -36, -90)
	_reference_hud_root.add_child(loot_label)
	_outline_labels([loot_label])
	# 角色身侧换弹环继续挂在 HUD 根：不受武器图标缩放/隐藏影响，不恢复世界环。
	# 每帧投影角色位置；进度与生命周期仍只消费真实武器事件。
	# z_index 保证提示画在场景之上。
	_hud_reload_ring = HUD_RELOAD_RING_SCRIPT.new() as HudReloadRing
	_hud_reload_ring.name = "HudReloadRing"
	_hud_reload_ring.z_index = 1
	_hud_reload_ring.visible = false
	_hud_reload_ring.size = _hud_size(
		Vector2(HUD_RELOAD_RING_OUTER_DIAMETER_DESIGN, HUD_RELOAD_RING_OUTER_DIAMETER_DESIGN)
	)
	_reference_hud_root.add_child(_hud_reload_ring)
	_place_hud_reload_ring()
	for quick_index in range(2):
		var quick_panel := _make_bare_hud_panel()
		quick_panel.name = "QuickItemHUD_%d" % quick_index
		# 2026-10-17：快捷物品槽的背框一并撤掉（内容只有一枚图标 + 一行小字，框纯属占用）。
		var left := -220.0 if quick_index == 0 else 162.0
		var right := -162.0 if quick_index == 0 else 220.0
		_anchor_control(quick_panel, 0.5, 1.0, 0.5, 1.0, left, -75, right, -20)
		_reference_hud_root.add_child(quick_panel)
		# 快捷物品槽：[3]/[4] 直接 tap 使用，对应键位 use_quick_item_1/2
		quick_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		quick_panel.tooltip_text = "点击使用快捷物品 [键%d]" % (quick_index + 3)
		quick_panel.gui_input.connect(_on_quick_item_gui_input.bind(quick_index, quick_panel))
		var quick_box := VBoxContainer.new()
		quick_box.alignment = BoxContainer.ALIGNMENT_CENTER
		quick_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quick_panel.add_child(quick_box)
		var quick_icon_host := Control.new()
		quick_icon_host.name = "QuickItemIconHost_%d" % quick_index
		quick_icon_host.custom_minimum_size = _hud_size(Vector2(48, 35))
		quick_icon_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quick_box.add_child(quick_icon_host)
		_hud_quick_item_icon_hosts.append(quick_icon_host)
		var quick_label := _make_hud_label("[%d] 空" % (quick_index + 3), 8, Color(0.92, 0.96, 1.0))
		quick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quick_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quick_box.add_child(quick_label)
		_hud_quick_item_labels.append(quick_label)
		_outline_labels([quick_label])
	_refresh_quick_item_hud()

	# 右下角不再放 R/SHIFT/F/E 四个动作键图标：动作本身仍走 InputMap（键盘与手柄照常），
	# 这里只去掉 HUD 上的可视 + 点击入口。


## 屏幕外怪物指示箭头（UI-HUD r2）。设计与判据见
## `docs/v0.1/design/对话与战斗信息呈现设计.md` 的「屏幕外怪物指示箭头」。
##
## 放在 `$HUD` 下、而**不是** ReferenceCombatHUD 里：它与小地图同属"看世界"的层，
## 不参与 HUD 面板布局；`z_index = 110` 压在小地图（105）之上、低血量暗角（220）之下，
## 保证箭头不被面板背板吃掉，但也盖不住血量告急的全屏效果。
func _install_offscreen_enemy_indicator() -> void:
	if _offscreen_indicator != null and is_instance_valid(_offscreen_indicator):
		return
	var indicator := OFFSCREEN_INDICATOR_SCRIPT.new() as OffscreenEnemyIndicator3D
	indicator.name = "OffscreenEnemyIndicator3D"
	indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.z_index = 110
	$HUD.add_child(indicator)
	_offscreen_indicator = indicator


func _on_weapon_panel_gui_input(event: InputEvent, panel: PanelContainer) -> void:
	# tap 在主/副武器槽之间循环：当前 0 → 切 1，当前 1 → 切 0。状态本身存于 Player3D.active_weapon_slot。
	if not _is_panel_press(event):
		return
	if player == null:
		return
	var current_slot := 0
	if player.has_method("get_active_weapon_slot"):
		current_slot = int(player.call("get_active_weapon_slot"))
	var next_slot := 1 if current_slot == 0 else 0
	_select_weapon_slot(next_slot)
	_flash_action_key(panel)
	get_viewport().set_input_as_handled()

func _on_quick_item_gui_input(event: InputEvent, quick_index: int, panel: PanelContainer) -> void:
	# tap 使用快捷物品：对齐键位 3/4。空槽/物品耗尽时 _use_quick_item 会写 status_label 反馈。
	if not _is_panel_press(event):
		return
	_use_quick_item(quick_index)
	_flash_action_key(panel)
	get_viewport().set_input_as_handled()

func _is_panel_press(event: InputEvent) -> bool:
	# 同时识别 PC 鼠标左键和移动端触屏按下（武器栏 / 快捷物品 / 小地图 / 头像面板共用）
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return st.pressed
	return false

func _on_radar_gui_input(event: InputEvent, panel: Control) -> void:
	# tap 右上小地图 = M 键
	if not _is_panel_press(event):
		return
	_toggle_full_map()
	_flash_action_key(panel)
	get_viewport().set_input_as_handled()

func _on_player_status_gui_input(event: InputEvent, panel: PanelContainer) -> void:
	# tap 头像面板 = I / Tab 键
	if not _is_panel_press(event):
		return
	if _inventory_ui != null:
		_inventory_ui.toggle_inventory_panel()
	_flash_action_key(panel)
	get_viewport().set_input_as_handled()

func _build_modal_close_button(label: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.tooltip_text = label + "（对应 ESC 键）"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = _hud_size(Vector2(150, 36))
	btn.add_theme_font_size_override("font_size", _hud_int(13))
	UIStyleFactory.apply_prism_button(btn, "ghost", 2, 13, 2, "none")
	btn.pressed.connect(on_press)
	return btn

func _ensure_inventory_close_button() -> void:
	_teardown_inventory_close_button()

func _teardown_inventory_close_button() -> void:
	if _inventory_close_button != null and is_instance_valid(_inventory_close_button):
		_inventory_close_button.queue_free()
	_inventory_close_button = null

func _close_inventory_via_button() -> void:
	if _inventory_ui != null:
		_inventory_ui.set_inventory_panel_open(false)


func _flash_action_key(panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	var original_modulate := panel.modulate
	panel.modulate = Color(1.55, 1.55, 1.55, 1.0)
	var tween := create_tween()
	tween.tween_interval(0.10)
	tween.tween_callback(func():
		if is_instance_valid(panel):
			panel.modulate = original_modulate
	)


func _tap_input_action(action: StringName) -> void:
	# 仿照 Player3D._tap_input_action：把一次性的 input action 注入 Input 单次队列。
	# Player3D 端 _update_combat_input / PlayerFlashlight3D._unhandled_input / 状态机的
	# is_action_just_pressed("dash") 都会在下一帧检测到。
	var pressed_event := InputEventAction.new()
	pressed_event.action = action
	pressed_event.pressed = true
	Input.parse_input_event(pressed_event)
	var released_event := InputEventAction.new()
	released_event.action = action
	released_event.pressed = false
	Input.parse_input_event(released_event)


func _make_hud_panel(accent: Color, background: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_hud_style(accent, background, 1))
	return panel


func _make_hud_style(accent: Color, background: Color, border_width: int) -> StyleBoxFlat:
	# 局内 HUD 弹层统一到「棱镜线框」：冷蓝半透底 + 白系细线，零圆角、零投影。
	# 底色 alpha 仍严格 <= 0.50（verify_finite_ammo_flow 的透明度契约）。
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		UIPalette.PRISM_SURFACE.r,
		UIPalette.PRISM_SURFACE.g,
		UIPalette.PRISM_SURFACE.b,
		minf(maxf(background.a, 0.0), 0.50)
	)
	# 只有"语义色"（危险 / 警告 / 强调）才允许给线着色，其余一律走次级白线 ——
	# 避免把旧的霓虹青当成"结构色"铺满整屏。
	var semantic := UIStyleFactory.prism_normalize_color(accent)
	if semantic == UIPalette.PRISM_DANGER or semantic == UIPalette.PRISM_WARN or semantic == UIPalette.PRISM_ACCENT:
		style.border_color = semantic
	else:
		style.border_color = UIPalette.PRISM_LINE_SOFT
	style.set_border_width_all(maxi(1, border_width))
	style.set_corner_radius_all(2)
	style.shadow_size = 0
	return style


## 构造「棱镜线框」HUD 卡片 StyleBox：极淡深蓝底衬 + 1px 白线方角细框，零辉光。
## 严格保证 alpha <= 0.50 —— verify_finite_ammo_flow 的五十趴透明度探针契约。
func _make_prism_hud_card_style(
	border_color: Color = UIPalette.PRISM_LINE_SOFT,
	alpha: float = 0.44,
	radius: int = 2,
	border_width: int = 1
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		UIPalette.PRISM_SURFACE.r,
		UIPalette.PRISM_SURFACE.g,
		UIPalette.PRISM_SURFACE.b,
		clampf(alpha, 0.0, 0.50)
	)
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_size = 0
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style



## 全透明 HUD 外壳：撤掉底色、描边、圆角与外发光，只保留 PanelContainer 的布局职责。
## 2026-09-28 主人连续要求去掉各处背板，统一收敛到这一个口径，免得每处各写一遍。
## 注意：全透明 StyleBox 仍参与 PanelContainer 的内容边距计算，所以内层
## MarginContainer 的数值是唯一内边距来源时，内容位置不会变。
func _make_bare_hud_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	return style


## 无背板 HUD 外壳的构造入口。对齐 _make_hud_panel 的签名习惯，但外观恒为全透明。
## 必须走 StyleBoxFlat 覆盖：PanelContainer 若不覆盖 panel，会退回主题默认深色底，
## 那样「去掉背板」就失效了。
func _make_bare_hud_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_bare_hud_style())
	return panel


## 给 Label 加文字描边。撤掉背板后文字直接压在实景上，浅色天花板/桥体下
## 白字与浅蓝字会同明度而读不出。描边不是背板 —— 不占像素、不改颜色、不改布局。
func _outline_labels(labels: Array) -> void:
	for entry in labels:
		var label := entry as Label
		if label == null:
			continue
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
		label.add_theme_constant_override("outline_size", 5)


func _make_bar_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


func _make_hud_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", _hud_int(font_size))
	# 调色板收口：HUD 里散落的硬编码色（近白 / 霓虹青 / 金币金 / 平红）按色相
	# 归到棱镜语义槽，不再逐处改写 —— 语义分工（危险/警告/强调/成功）完整保留。
	# 原色的 alpha 予以保留（有些 HUD 字本来就带半透，例如淡出态）。
	var normalized := UIStyleFactory.prism_normalize_color(color)
	normalized.a = color.a
	label.add_theme_color_override("font_color", normalized)
	# HUD 压在明亮低多边形实景上，白字必须留描边 —— 棱镜规范 §4.4 的可读性例外，
	# 也是"无背板 / 无卡片"语言下唯一能保证任意背景可读的手段。
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.025, 0.045, 0.94))
	label.add_theme_constant_override("outline_size", 3)
	var font := UIStyleFactory.make_prism_font(1)
	if font != null:
		label.add_theme_font_override("font", font)
	return label


func _make_margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", _hud_int(left))
	margin.add_theme_constant_override("margin_top", _hud_int(top))
	margin.add_theme_constant_override("margin_right", _hud_int(right))
	margin.add_theme_constant_override("margin_bottom", _hud_int(bottom))
	return margin


func _anchor_control(
	control: Control,
	anchor_left: float, anchor_top: float, anchor_right: float, anchor_bottom: float,
	offset_left: float, offset_top: float, offset_right: float, offset_bottom: float
) -> void:
	control.anchor_left = anchor_left
	control.anchor_top = anchor_top
	control.anchor_right = anchor_right
	control.anchor_bottom = anchor_bottom
	control.offset_left = offset_left * HUD_UI_SCALE
	control.offset_top = offset_top * HUD_UI_SCALE
	control.offset_right = offset_right * HUD_UI_SCALE
	control.offset_bottom = offset_bottom * HUD_UI_SCALE


func _hud_size(value: Vector2) -> Vector2:
	return value * HUD_UI_SCALE


func _hud_int(value: int) -> int:
	return maxi(1, int(round(float(value) * HUD_UI_SCALE)))


func _on_inventory_open_changed(opened: bool) -> void:
	if opened and _has_exclusive_modal():
		_inventory_ui.set_inventory_panel_open(false)
		status_label.text = "先完成当前交互，再打开背包"
		return
	_sync_player_input_lock()
	if opened:
		status_label.text = "背包已打开 · 左键使用/装备，右键存入保险格"
		_ensure_inventory_close_button()
	else:
		status_label.text = "背包已关闭 · 继续搜索、战斗或撤离"
		_teardown_inventory_close_button()


func _has_exclusive_modal() -> bool:
	# 撤离不再锁定输入：玩家可以自由移动/开枪/翻滚；
	# _extraction_defense_active 仅作为“撤离进行中”标记存在。
	return (
		_completed
		or _door_fate_active
		or (_full_map_overlay != null and is_instance_valid(_full_map_overlay))
		or (_workbench_panel != null and is_instance_valid(_workbench_panel))
		or (_merchant_ui != null and is_instance_valid(_merchant_ui) and _merchant_ui.visible)
	)


func _sync_player_input_lock() -> void:
	if player == null:
		return
	var inventory_open := _inventory_ui != null and _inventory_ui.is_inventory_open()
	player.set_input_locked(
		_has_exclusive_modal() or inventory_open or _narrative_holds_player_input()
	)


## 剧情演出期间的输入独占归叙事导演（08 文档 §5.5）。本函数被 15+ 处调用，
## 不加这一条就会逐帧把演出的锁顶掉 —— 表现为"剧本说了停住，角色照常能动"，
## 且运行时没有任何报错。所以这里显式让权。
func _narrative_holds_player_input() -> bool:
	return (
		NarrativeDirector != null
		and NarrativeDirector.has_method("is_player_input_locked")
		and bool(NarrativeDirector.is_player_input_locked())
	)


## 供叙事收口时要求重算（08 文档 §5.5）。归还独占权后必须再裁决一次 ——
## 本函数是事件驱动的（27 处调用），演出结束后没人再喊它，
## 玩家就会一直锁着：键盘与开枪全废、鼠标仍能转向，且运行时零报错。
func refresh_player_input_lock() -> void:
	_sync_player_input_lock()


func _close_inventory_for_modal() -> void:
	if _inventory_ui != null and _inventory_ui.is_inventory_open():
		_inventory_ui.set_inventory_panel_open(false)


func try_close_modal_for_pause() -> bool:
	if _full_map_overlay != null and is_instance_valid(_full_map_overlay):
		_close_full_map()
		return true
	if _inventory_ui != null and _inventory_ui.is_inventory_open():
		_inventory_ui.set_inventory_panel_open(false)
		return true
	if _workbench_panel != null and is_instance_valid(_workbench_panel):
		handle_esc()
		return true
	if _merchant_ui != null and is_instance_valid(_merchant_ui) and _merchant_ui.visible:
		_merchant_ui.hide_merchant()
		return true
	if _door_fate_active:
		_cancel_door_fate_selection()
		return true
	return false


func _toggle_full_map() -> void:
	if _full_map_overlay != null and is_instance_valid(_full_map_overlay):
		_close_full_map()
		return
	if _has_exclusive_modal():
		status_label.text = "先完成当前交互，再打开楼层大地图"
		return
	_close_inventory_for_modal()
	_full_map_overlay = Control.new()
	_full_map_overlay.name = "ExploredFloorMapOverlay"
	_full_map_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_map_overlay.z_index = 850
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_map_overlay.add_child(dim)
	_full_map_control = DungeonMinimap3D.new()
	_full_map_control.name = "FullFloorMap3D"
	_full_map_control.set_anchors_preset(Control.PRESET_CENTER)
	_full_map_control.position = Vector2(-470, -300)
	_full_map_control.size = Vector2(940, 600)
	_full_map_control.custom_minimum_size = Vector2(940, 600)
	_full_map_control.set_full_map_mode(true)
	_full_map_control.copy_state_from(minimap)
	_full_map_overlay.add_child(_full_map_control)
	var hint := _make_hud_label("M / ESC 关闭 · 仅显示本层已探索房间与当前位置", 14, UIPalette.PRISM_LABEL)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_control(hint, 0.5, 1.0, 0.5, 1.0, -360, -44, 360, -16)
	_full_map_overlay.add_child(hint)
	$HUD.add_child(_full_map_overlay)
	_sync_player_input_lock()
	# tap 关闭按钮（ESC 等效）
	var radar_close_btn := _build_modal_close_button("关闭 · ESC", _close_full_map)
	_anchor_control(radar_close_btn, 1.0, 0.0, 1.0, 0.0, -180, 18, -18, 60)
	_full_map_overlay.add_child(radar_close_btn)
	_radar_close_button = radar_close_btn
	status_label.text = "楼层大地图已打开 · 仅展示已探索区域"


func _close_full_map() -> void:
	if _full_map_overlay != null and is_instance_valid(_full_map_overlay):
		_full_map_overlay.queue_free()
	_full_map_overlay = null
	_full_map_control = null
	if _radar_close_button != null and is_instance_valid(_radar_close_button):
		_radar_close_button.queue_free()
	_radar_close_button = null
	_sync_player_input_lock()
	status_label.text = "楼层大地图已关闭"


func _configure_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = visual_theme.fog_color.darkened(0.32)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = visual_theme.ambient_color
	# 暗室保留低照度层次而非纯黑；玩家真实灯光只影响材质，玩法显隐仍完全独立。
	environment.ambient_light_energy = clampf(visual_theme.ambient_energy * 0.32, 0.16, 0.22)
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.18
	environment.fog_enabled = true
	environment.fog_light_color = visual_theme.fog_color.lightened(0.13)
	environment.fog_light_energy = 0.36
	environment.fog_density = visual_theme.fog_density
	environment.fog_height = 0.0
	environment.fog_height_density = 0.0  # 纯距离雾，关闭高度差异
	world_environment.environment = environment
	if GraphicsSettingsManager != null:
		GraphicsSettingsManager.register_environment(environment)
	key_light.light_color = visual_theme.key_light_color.lerp(Color(1.0, 0.54, 0.24), 0.18)
	key_light.light_energy = 0.10
	key_light.shadow_enabled = true
	key_light.light_cull_mask = GameDesignConfig.LIGHT_MASK_WORLD_AND_PLAYER
	key_light.shadow_caster_mask = GameDesignConfig.SHADOW_MASK_WORLD_AND_PLAYER
	key_light.add_to_group(EnemyIllumination3D.SUN_GROUP)
	key_light.set_meta("gameplay_light_kind", "sun")
	if GameplaySpatialRegistry3D != null:
		GameplaySpatialRegistry3D.register_node(key_light, GameplaySpatialRegistry3D.KIND_SUN)
		key_light.tree_exiting.connect(GameplaySpatialRegistry3D.unregister_node.bind(key_light))


func apply_performance_quality(profile: String) -> void:
	if world_environment.environment != null:
		world_environment.environment.fog_enabled = (
			profile != "low"
			and (GraphicsSettingsManager == null or GraphicsSettingsManager.is_enabled("distance_fog"))
		)
		world_environment.environment.fog_density = (
			visual_theme.fog_density
			if profile == "high"
			else visual_theme.fog_density * 0.72
		)
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 96.0 if profile == "high" else 64.0 if profile == "balanced" else 36.0


## 读取页活动时让装配按房间交还主线程；普通入口与专项仍同步完成。
func _uses_loading_frame_budget() -> bool:
	return not test_mode and IrisTransition != null and IrisTransition.is_loading_scene(self)


func _load_bootstrap_resource(path: String, type_hint := "") -> Resource:
	if type_hint == "PackedScene":
		var warm_error := await LOADING_RESOURCE_WARMUP.warm(path, get_tree(), _loading_scene_resources)
		if warm_error != OK:
			return null
	var error := ResourceLoader.load_threaded_request(path, type_hint)
	if error != OK:
		push_error("后台读取失败：%s (%s)" % [path, error_string(error)])
		return null
	# 请求与轮询分在不同帧；只在 LOADED 后取资源，避免 get 等待后台线程。
	await get_tree().process_frame
	var status := ResourceLoader.load_threaded_get_status(path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(path)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("后台资源读取失败：%s" % path)
		return null
	var resource := ResourceLoader.load_threaded_get(path)
	# 保持强引用，确保房间内的 load 只命中缓存。
	_loading_scene_resources.append(resource)
	return resource


func _load_room_visual_for_loading(room: DungeonRoom3D) -> bool:
	var path := room.static_layout_scene_path
	if path.is_empty() or not DungeonRoom3D.use_expedition_static_layout_scenes or not ResourceLoader.exists(path):
		return true
	return await _load_bootstrap_resource(path, "PackedScene") != null


func _build_room_shell_for_loading(room: DungeonRoom3D) -> bool:
	if not await _load_room_visual_for_loading(room):
		_on_loading_resource_failed(room.static_layout_scene_path)
		return false
	room.ensure_shell_built()
	room.visible = true
	await get_tree().process_frame
	return true


func _on_loading_resource_failed(path: String) -> void:
	push_error("地图装配资源不可用：%s" % path)


func _generate_layout() -> void:
	_prepare_layout_rooms()
	_plan_room_layout()
	_ensure_structural_shells_resident()
	_finish_layout_connections()


func _generate_layout_for_loading() -> void:
	_prepare_layout_rooms()
	_plan_room_layout()
	await get_tree().process_frame
	for room in _rooms:
		if not await _build_room_shell_for_loading(room):
			return
	_finish_layout_connections()


func _prepare_layout_rooms() -> void:
	_build_records()
	_build_topology()
	minimap.configure(_records, _open_edges)
	minimap.reveal_room("start")
	for record in _records:
		var room := ROOM_SCENE.instantiate() as DungeonRoom3D
		room.configure({
			"room_id": record["id"], "room_type": record["type"], "size_class": record["size"],
			"doors": record["doors"], "door_targets": record.get("door_targets", {}), "theme": visual_theme,
			"door_policies": _door_policies_for_record(record),
			"seed": run_seed + int(record["index"]) * 104729, "is_main_path": record["main"],
			"custom_dimensions": record.get("custom_dimensions", Vector2.ZERO),
			"tower_module_shell": bool(record.get("tower_module_shell", false)),
			"open_wall_directions": record.get("open_wall_directions", []),
			"enemy_spawn_plan": record.get("enemy_spawn_plan", {}),
			"spawn_placements": record.get("spawn_placements", []),
			"encounter": record.get("encounter", {}),
			"spawn_boxes_only": bool(record.get("spawn_boxes_only", false)),
			"reward_plan": record.get("reward_plan", {}),
			# 宝箱放置层（2026-10-29）：与其余房间级字段同样逐级透传。
			# 未写本段的关卡得到空数组 ⇒ 一个箱子都不建，行为逐字不变。
			"chest_placements": record.get("chest_placements", []),
			"safe_room_corner_l": bool(record.get("safe_room_corner_l", false)),
			# 授权布局壳体（区块00 98F 入口房）：入口房由本路径在开局就实例化，
			# 而其余房间在 FloorBundle 里走 TowerDescent3D._instantiate_dynamic_room。
			# 两处 configure 必须同样透传，否则入口房会退回通用 5m 程序化壳体。
			"authored_layout_shell": bool(record.get("authored_layout_shell", false)),
			"authored_layout_asset_id": str(record.get("authored_layout_asset_id", "")),
			"authored_layout_version": str(record.get("authored_layout_version", "")),
			"authored_layout_room_id": str(record.get("authored_layout_room_id", "")),
			"authored_layout_peaceful": bool(record.get("authored_layout_peaceful", false)),
			"search_facilities_enabled": bool(record.get("search_facilities_enabled", true)),
			"authored_room_light_on": bool(record.get("authored_room_light_on", false)),
			"authored_layout_instances": record.get("authored_layout_instances", []),
			"static_layout_scene_path": str(record.get("static_layout_scene_path", "")),
			"connection_ports": record.get("connection_ports", []),
			"camera_profile": record.get("camera_profile", {}),
			"door_endpoint_owners": record.get("door_endpoint_owners", {}),
			# 门扇开合方式：未声明的关卡得到空串 ⇒ RoomDoor3D 用缺省升降，行为逐字不变。
			"door_opening_style": str(record.get("door_opening_style", "")),
			# 传送支线位点（支线秘密房间设计 §3.2）：与其余房间级字段同样逐级透传。
			# 未声明位点的房间得到空字典 ⇒ 一个节点都不建，行为逐字不变。
			"secret_site": record.get("secret_site", {}),
			# 易碎小物件随机布置计划：与其余房间级字段同样逐级透传。
			# 未写本段的关卡得到空字典 ⇒ 房间只摆固定件，行为逐字不变。
			"interactive_clutter": record.get("interactive_clutter", {}),
		})
		room.position = record["position"]
		$GeneratedRooms.add_child(room)
		_rooms.append(room)
		_room_by_id[room.room_id] = room
		room.player_entered.connect(_on_room_entered)
		room.prop_searched.connect(_on_prop_searched)
		room.service_activated.connect(_on_service_activated)
		room.light_toggled.connect(_on_room_light_toggled)
		room.chest_open_requested.connect(_on_chest_open_requested)


func _finish_layout_connections() -> void:
	_bind_shared_edge_doors()
	for record in _records:
		if str(record.get("parent", "")).is_empty():
			continue
		var parent: DungeonRoom3D = _room_by_id.get(str(record["parent"])) as DungeonRoom3D
		var child: DungeonRoom3D = _room_by_id.get(str(record["id"])) as DungeonRoom3D
		if parent != null and child != null:
			_build_corridor(parent, child, int(record["index"]))
	_create_extraction()
	_create_secret_branches()


## 传送支线（支线秘密房间设计 §3）：房表声明了 `secret_site` 才装配。
##
## 刻意与主图隔离：
##   · 子图房间**不进** `_records`、不进全层地图、不参与流送与拓扑校验；
##   · 位点坐标由房间外框 + wall 现算，不读设计源世界坐标；
##   · 未声明位点的关卡（塔楼、远征 02）一个节点都不建，行为逐字不变。
func _create_secret_branches() -> void:
	# 幂等：远征在 bootstrap 里显式调用一次，`_finish_layout_connections` 那条链
	# 也可能在别的关卡路径上再调一次。重复装配会造出两套板体。
	#
	# 第二次进来时房间已全部装配完，正好补做「位点外推」：bootstrap 那次房间还没进树，
	# 拿不到墙体几何，暗门会埋在墙里（远征 01 的 S1 实测被墙包住 0.465m）。
	if _secret_branch != null and is_instance_valid(_secret_branch):
		_secret_branch.call("settle_sites")
		return
	var declared := false
	for record in _records:
		if not (record.get("secret_site", {}) as Dictionary).is_empty():
			declared = true
			break
	if not declared:
		return
	var branch_node := SECRET_BRANCH_SCRIPT.new()
	branch_node.name = "SecretBranches"
	add_child(branch_node)
	# 主图房间坐标已是世界坐标，原点取零即可 —— 子图按 +1000m 偏移，不撞主图。
	#
	# 子图房型、走廊、美术都**取自现成实现**，不给支线单开一套：
	#   · `room_templates` = L3 模板表（设计 §3.5 的房型池）；
	#   · `corridor_builder` = 主路同一条 `_build_corridor`；
	#   · `room_theme` = 本关主题，子图房与主路房同材质；
	#   · `beacon_factory` = 主撤离房同一个信标工厂；
	#   · `level_id` = 拼共享房壳路径（子图房借主路房间的正式 tscn，不是灰盒）。
	# 缺任一项时支线**降级但不崩**：模板缺失退回内值尺寸，走廊缺失只告警，
	# 房间壳缺失退回程序化（A18 会把「灰盒」判红）。
	var branch_level_id := _resolve_branch_level_id()
	branch_node.configure(
		Vector3.ZERO, run_seed, _records, Callable(self, "_count_cleared_content_rooms"),
		Callable(self, "_room_cleared"), Callable(self, "_count_content_rooms"),
		_load_secret_branch_room_templates(branch_level_id),
		Callable(self, "_build_secret_branch_corridor"), visual_theme,
		Callable(self, "_create_secret_branch_extraction_beacon"), branch_level_id,
		Callable(self, "_on_secret_branch_room_entered"),
		Callable(self, "_set_secret_branch_status")
	)
	branch_node.build()
	_secret_branch = branch_node


## 子图撤离房的信标：**复用** `_create_extraction_beacon`，不新建撤离系统。
##
## `STANDARD` + 非锁定（设计 §6.1）。结算走现成的 `extraction_completed →
## _finish_run(true)`，与主撤离房完全一致（设计 §6.3）。
##
## 打 `secret_branch` 标记只有一个用处：`_on_extraction_started` 据此**跳过防线遭遇** ——
## 子图房间不进 `_room_by_id`，那份遭遇会按 `_current_room_id` 落到玩家已经离开的主图房间上，
## 表现成「人在子图读条，主图房里刷怪」。
func _create_secret_branch_extraction_beacon(room: DungeonRoom3D) -> void:
	var beacon := _create_extraction_beacon(room, "STANDARD", 30.0, false, Vector3.ZERO)
	if beacon == null:
		push_warning("[Dungeon3D] 子图撤离信标创建失败：%s" % str(room.room_id if room else "<null>"))
		return
	beacon.set_meta("secret_branch", true)


## 子图走廊：与主路**同一条实现**，但常驻启用（子图房间不进流送/开门边集合），
## 且按房间声明的 lane 平移中心线。
func _build_secret_branch_corridor(
	from_room: DungeonRoom3D, to_room: DungeonRoom3D, index: int, lateral_offset_m: float
) -> void:
	_build_corridor(from_room, to_room, index, true, lateral_offset_m)


# ============================================================================
# 子图战斗（业主 2026-10-18：每间固定 5 只强化怪 + 2 只普通怪，不加掉落加成）
# ----------------------------------------------------------------------------
# 子图房间**不在** `_records` / `_room_by_id` / 流送图里（设计 §1：物理与拓扑都
# 刻意隔离）。所以这里既不调 `_on_room_entered`，也不调 `_mark_room_cleared`，
# 只借用两件**与本图无关**的东西：
#   · `_spawn_enemy_batch`：实例化、接信号、挂 `$ActiveEnemies`、写存活账；
#   · `_enemy_nodes_by_room` / `_alive_by_room`：击杀与掉落本来就在这张账上。
# ============================================================================


## 玩家踏进子图房间：切「当前房间」，首次进入时按编成刷怪。
##
## 为什么必须切 `_current_room_id`（漏了这条，怪会站着不动）：
##   · `MonsterAIManager._target_is_legal` 只允许「本房敌人」追玩家；
##   · `_spawn_enemy_batch` 用 `room.room_id == _current_room_id` 决定敌人是否激活；
##   · `_update_wave_hud` 也按它决定这一屏该显示谁的波次。
##
## 为什么不走 `_on_room_entered`：那条链要重算流送、换小地图、写存档检查点，
## 全部以「主图房间图」为前提。子图不在那张图里，塞进去会改坏主图的流送状态。
func _on_secret_branch_room_entered(room: DungeonRoom3D, with_encounter: bool) -> void:
	if room == null or not is_instance_valid(room):
		return
	_secret_branch_room_ids[room.room_id] = room
	_current_room_id = room.room_id
	room_label.text = "%s · 暗室" % room.room_id
	_update_wave_hud(room.room_id)
	if not with_encounter or _spawned_rooms.has(room.room_id):
		return
	_spawned_rooms[room.room_id] = true
	_spawn_secret_branch_room_enemies(room)


## 子图一间房的固定编成：**5 只强化怪 + 2 只普通怪**。
##
## 编成由 `MonsterInjector.build_secret_branch_encounter` 出（数量与档位的唯一真源），
## 实例化/掉落/击杀账全部复用 `_spawn_enemy_batch` —— 不给子图另开一套刷怪链，
## 否则「召唤、延迟出怪、掉落、清房判定」会出现两份实现并且迟早分叉。
##
## 与主路的四处差别（都是有意的）：
##   · 不消费命运卡给的「下一房加成」（不调 `_note_room_enemy_modifiers`）；
##   · 不吃「已清房数」难度曲线：7 只是固定承诺，不随进度漂移；
##   · 不产房间钥匙（子图的门不消耗钥匙，见 `SecretBranch3D` 的 `door_policies`）；
##   · 不加掉落加成（业主 2026-10-18：收益就走常规击杀掉落）。
func _spawn_secret_branch_room_enemies(room: DungeonRoom3D) -> int:
	if _monster_injector == null:
		return 0
	var floor_number := maxi(1, visual_theme.difficulty_rank)
	var floor_level := RoomData.FloorLevel.MEDIUM
	var configs := _monster_injector.build_secret_branch_encounter(
		floor_number, floor_level, run_seed ^ room.room_id.hash()
	)
	if configs.is_empty():
		push_error("[Dungeon3D] 子图房间 %s 编成为空，本间保持空置" % room.room_id)
		room.cleared = true
		return 0
	# 一间只有一波：波次账写 1/1，HUD 显示「波次 1/1」而不是「波次 —」。
	_room_wave_queues[room.room_id] = []
	_room_wave_numbers[room.room_id] = 1
	_room_wave_totals[room.room_id] = 1
	_enemy_nodes_by_room[room.room_id] = []
	var spawned := _spawn_enemy_batch(room, configs, false)
	if spawned <= 0:
		push_error("[Dungeon3D] 子图房间 %s 刷怪失败，本间放行" % room.room_id)
		_room_wave_queues[room.room_id] = []
		_alive_by_room[room.room_id] = 0
		# 刷不出来也不能让玩家对着空房等：直接标清。
		room.cleared = true
		_update_wave_hud(room.room_id, "刷怪失败 · 已放行")
		return 0
	_update_wave_hud(room.room_id, "暗室清剿")
	status_label.text = "暗室警戒 · %d 只强化怪 + %d 只普通怪" % [
		MonsterInjector.SECRET_BRANCH_STRONG_COUNT,
		MonsterInjector.SECRET_BRANCH_NORMAL_COUNT,
	]
	return spawned


## 子图房间肃清（7 只全死）。
##
## **不走 `_mark_room_cleared`**：那条链会发房间钥匙、走奖励协调器结算、推进命运卡、
## 刷新撤离信标锁 —— 全是主图语义，用在子图上会凭空多出钥匙与结算。
func _on_secret_branch_room_cleared(room_id: String) -> void:
	var room := _secret_branch_room_ids.get(room_id) as DungeonRoom3D
	if room == null or not is_instance_valid(room):
		return
	room.cleared = true
	if AudioManager != null:
		AudioManager.play_sfx("wave_clear", -3.0)
	var total := (
		MonsterInjector.SECRET_BRANCH_STRONG_COUNT + MonsterInjector.SECRET_BRANCH_NORMAL_COUNT
	)
	status_label.text = "暗室肃清 · 本间 %d 个敌对信号已清除" % total
	_update_wave_hud(room_id, "房间肃清")


## 子图状态栏文案（`SecretBranch3D` 打开房间门时上报）。缺省不写。
func _set_secret_branch_status(text: String) -> void:
	if not text.is_empty():
		status_label.text = text


## 供验收与诊断：子图逐间的编成/存活/清房状态。
## 存活数按 `_enemy_nodes_by_room` 里**还没死**的实体数算，与击杀账同一口径。
func secret_branch_encounter_snapshot() -> Array:
	var rows: Array = []
	for room_id in _secret_branch_room_ids:
		var room := _secret_branch_room_ids[room_id] as DungeonRoom3D
		var strong := 0
		var plain := 0
		var kinds: Array = []
		for value in _enemy_nodes_by_room.get(room_id, []):
			if not is_instance_valid(value) or not (value is Enemy3D):
				continue
			var enemy := value as Enemy3D
			if enemy.ai_state == "dead":
				continue
			var kind := str(enemy.enemy_kind)
			kinds.append(kind)
			if MonsterVariants.is_variant(kind):
				strong += 1
			else:
				plain += 1
		rows.append({
			"room_id": room_id,
			"strong_alive": strong,
			"plain_alive": plain,
			"kinds": kinds,
			"cleared": room.cleared if room != null and is_instance_valid(room) else false,
			"current": room_id == _current_room_id,
		})
	return rows


## 子图房型表：按当前关卡 id 读 L3 模板。取不到返回空字典（支线用内值尺寸兜底）。
##
## 关卡 id 从祖先节点取 —— `Dungeon3D` 自己不知道关卡身份，但远征/塔楼的
## 上层节点知道（`get_expedition_level_id` / `get_runtime_map_id`）。
func _load_secret_branch_room_templates(level_id: String = "") -> Dictionary:
	var resolved := level_id if not level_id.is_empty() else _resolve_branch_level_id()
	if resolved.is_empty():
		return {}
	return LEVEL_PLAN_LOADER.load_room_templates(resolved)


## 本关 id（支线用）。逐级向上问，先问远征关卡 id，再问运行时地图 id。
func _resolve_branch_level_id() -> String:
	var node: Node = self
	while node != null:
		if node.has_method("get_expedition_level_id"):
			var expedition_id := str(node.call("get_expedition_level_id"))
			if not expedition_id.is_empty():
				return expedition_id
		if node.has_method("get_runtime_map_id"):
			var map_id := str(node.call("get_runtime_map_id"))
			if not map_id.is_empty():
				return map_id
		node = node.get_parent()
	return ""


## 「已清内容房数」：板体血量与撤离门解锁条件都吃这个值（设计 §4.1 / §6.2）。
##
## 什么算「内容房」：玩家必须清掉才有进度的房间。
## 排除项的口径在 2026-10-18 修正过一次 —— 原来的排除表只有
## `START/EXTRACTION/ELEVATOR/FACILITY`，但**运行时的 room_type 是语义类型**
## （`COMBAT`/`SCAVENGE`/`STORAGE`/`EVENT`/`BOSS`/`STAIR_LOBBY`/`EXTRACTION`），
## 设计源里的 `COMMON_ROOM` 到这里已经不存在了。于是入口大厅（`STAIR_LOBBY`，
## 初始即 `cleared == true`）被当成内容房，造成两处偏差：
##   · 远征 01 内容房总数虚高到 12（实际 11）
##   · 已清数开局就是 1 ⇒ 所有木板白送 20 血、撤离门白送 1 点进度
## 加上 `STAIR_LOBBY` 与 `SAFE_ROOM` 之后远征 01：总数 11、开局 0、阈值 5。
const NON_CONTENT_ROOM_TYPES := [
	"START", "EXTRACTION", "ELEVATOR", "FACILITY", "STAIR_LOBBY", "SAFE_ROOM",
]


func _is_content_room(room: DungeonRoom3D) -> bool:
	if room == null or not is_instance_valid(room):
		return false
	return not (str(room.room_type) in NON_CONTENT_ROOM_TYPES)


func _count_cleared_content_rooms() -> int:
	var count := 0
	for room in _rooms:
		if _is_content_room(room) and room.cleared:
			count += 1
	return count


## 内容房总数：撤离门阈值 `ceil(总内容房数 × 0.4)` 的分母（设计 §6.2）。
func _count_content_rooms() -> int:
	var count := 0
	for room in _rooms:
		if _is_content_room(room):
			count += 1
	return count


## 清房后刷新支线两道锁。只做「解锁」，不做「重新上锁」——
## 已经打开的门不该因为后续状态变化再关上。
func _refresh_secret_locks_after_clear() -> void:
	if _secret_branch == null or not is_instance_valid(_secret_branch):
		return
	_secret_branch.call("refresh_entry_locks", Callable(self, "_room_cleared"))
	_secret_branch.call("refresh_extraction_locks")


## 按 room_id 查某间房是否已清。入口板是否可破吃这个（设计 §5.2）。
## 查不到一律返回 false —— 位点对应不到房间时宁可锁着，也不要放玩家进一条
## 状态未知的支线。
func _room_cleared(room_id: String) -> bool:
	if room_id.is_empty():
		return false
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null or not is_instance_valid(room):
		return false
	return room.cleared


func _ensure_structural_shells_resident() -> void:
	# 必须在门轴/最终房间坐标提交后构建，避免用未冻结拓扑生成错误门洞。
	for room in _rooms:
		if room != null and is_instance_valid(room):
			room.ensure_shell_built()
			room.visible = true


## 子类可在全部结构壳体完成后，把一条边唯一的门实体绑定给另一端房间。
## 默认关卡仍各房自持门，本实现为空以保持旧行为。
func _bind_shared_edge_doors() -> void:
	pass


func _build_records() -> void:
	_records.clear()
	var path_length := int(gameplay_theme.get_layout_rule("path_length", 6))
	var sequence: Array = gameplay_theme.get_layout_rule("path_sequence", ["COMBAT", "SCAVENGE", "EVENT"])
	# 最大 ARENA 仍保留 6m 以上门外缓冲，避免房间扩大后互相穿插。
	var spacing := 62.0
	_records.append(_record("start", "START", "medium", Vector3.ZERO, ["east"], true, "", 0))
	for index in range(1, path_length + 1):
		var room_type := str(sequence[(index - 1) % sequence.size()])
		var size := _room_size_for(room_type, index)
		var doors: Array[String] = ["west", "east"]
		_records.append(_record("main_%02d" % index, room_type, size, Vector3(index * spacing, 0, 0), doors, true, "main_%02d" % (index - 1) if index > 1 else "start", index))
	var boss_index := path_length + 1
	_records.append(_record("boss", "BOSS", "arena", Vector3(boss_index * spacing, 0, 0), ["west", "east"], true, "main_%02d" % path_length, boss_index))
	_records.append(_record("extraction", "EXTRACTION", "medium", Vector3((boss_index + 1) * spacing, 0, 0), ["west"], true, "boss", boss_index + 1))

	var branch_types: Array[String] = gameplay_theme.required_branch_types.duplicate()
	var chance := float(gameplay_theme.get_layout_rule("branch_chance", 0.5))
	var optional_types := ["SCAVENGE", "STORAGE", "EVENT", "TRAP"]
	for optional in optional_types:
		if _rng.randf() <= chance * 0.42:
			branch_types.append(optional)
	var used_parents: Dictionary = {}
	for branch_index in range(branch_types.size()):
		var parent_index := 1 + ((branch_index * 2 + _rng.randi_range(0, maxi(1, path_length - 2))) % path_length)
		while used_parents.has(parent_index) and used_parents.size() < path_length:
			parent_index = 1 + parent_index % path_length
		used_parents[parent_index] = true
		var sign_z := -1.0 if branch_index % 2 == 0 else 1.0
		var parent_id := "main_%02d" % parent_index
		var parent_record: Dictionary = _find_record(parent_id)
		var parent_doors: Array = parent_record["doors"]
		parent_doors.append("north" if sign_z < 0.0 else "south")
		var branch_id := "branch_%02d" % (branch_index + 1)
		var branch_position := Vector3(parent_index * spacing, 0, sign_z * 50.0)
		var branch_doors: Array[String] = ["south" if sign_z < 0.0 else "north"]
		_records.append(_record(branch_id, branch_types[branch_index], _room_size_for(branch_types[branch_index], branch_index), branch_position, branch_doors, false, parent_id, boss_index + 2 + branch_index))

	var basement_created := false
	if _rng.randf() < float(gameplay_theme.get_layout_rule("basement_chance", 0.30)):
		basement_created = _try_add_vertical_branch("basement", "STAIRS_DOWN", -1, 2, path_length)
	if _rng.randf() < float(gameplay_theme.get_layout_rule("upper_chance", 0.20)):
		var access_type := "ELEVATOR" if visual_theme.difficulty_rank >= 3 else "STAIRS_UP"
		_try_add_vertical_branch("upper", access_type, 1, 1, path_length)
	# 深层主题至少展示一次原 2D 的垂直探索结构；普通主题仍完全遵循概率。
	if not basement_created and visual_theme.difficulty_rank >= 3:
		_try_add_vertical_branch("basement", "STAIRS_DOWN", -1, 2, path_length)


func _record(id: String, type_id: String, size: String, position: Vector3, doors: Array[String], main: bool, parent: String, index: int, vertical_level := 0) -> Dictionary:
	return {
		"id": id, "type": type_id, "size": size, "position": position,
		"doors": doors, "door_targets": {}, "main": main, "parent": parent,
		"index": index, "vertical_level": vertical_level,
		# 🔴 门端口归属必须**在这里**就初始化。`TowerDescent3D._register_edge_topology`
		#    会无条件执行 `(record["door_endpoint_owners"] as Dictionary)[dir] = ...`；
		#    若某条 record 缺这个键，`record[...]` 返回 null、`as Dictionary` 仍是 null，
		#    对 null 索引赋值即抛
		#    `Invalid access to property or key 'door_endpoint_owners' on a base object of type 'Dictionary'`。
		#    之前只有 `_append_plan_room_record` 补过它，经 `_append_tower_record`
		#    创建的 record（塔楼壳体、楼梯端点等）一直缺键 —— 撤离返航重建初始环时就会踩到。
		"door_endpoint_owners": {},
	}


func _try_add_vertical_branch(prefix: String, access_type: String, target_level: int, room_count: int, path_length: int) -> bool:
	var parent_indices: Array[int] = []
	for index in range(2, maxi(3, path_length)):
		parent_indices.append(index)
	for shuffle_index in range(parent_indices.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, shuffle_index)
		var held := parent_indices[shuffle_index]
		parent_indices[shuffle_index] = parent_indices[swap_index]
		parent_indices[swap_index] = held
	for parent_index in parent_indices:
		var parent_id := "main_%02d" % parent_index
		var parent_record := _find_record(parent_id)
		if parent_record.is_empty():
			continue
		var parent_doors := parent_record["doors"] as Array
		var outward := "south" if "south" not in parent_doors else "north" if "north" not in parent_doors else ""
		if outward.is_empty():
			continue
		parent_doors.append(outward)
		var sign_z := 1.0 if outward == "south" else -1.0
		var parent_position := parent_record["position"] as Vector3
		var access_id := "%s_access" % prefix
		var access_position := parent_position + Vector3(0, 0, sign_z * 52.0)
		var back := "north" if outward == "south" else "south"
		_records.append(_record(
			access_id, access_type, "small", access_position, [back, outward], false,
			parent_id, _records.size(), 0
		))
		var previous_id := access_id
		for room_index in range(maxi(1, room_count)):
			var room_id := "%s_%02d" % [prefix, room_index + 1]
			var type_id := "BASEMENT" if target_level < 0 and room_index == 0 else _choose_vertical_room_type()
			var room_position := Vector3(
				parent_position.x + (54.0 * room_index), target_level * 7.5,
				parent_position.z + sign_z * 104.0
			)
			var room_doors: Array[String] = []
			room_doors.append(back if room_index == 0 else "west")
			if room_index < room_count - 1:
				room_doors.append("east")
			_records.append(_record(
				room_id, type_id, _room_size_for(type_id, room_index + 2), room_position,
				room_doors, false, previous_id, _records.size(), target_level
			))
			previous_id = room_id
		return true
	return false


func _choose_vertical_room_type() -> String:
	var weights := gameplay_theme.get_layout_rule("vertical_room_weights", {}) as Dictionary
	if weights.is_empty():
		return ["SCAVENGE", "COMBAT", "ELITE", "STORAGE", "EVENT"][_rng.randi_range(0, 4)]
	var total := 0.0
	for value in weights.values():
		total += maxf(0.0, float(value))
	var roll := _rng.randf() * maxf(0.001, total)
	for key in weights.keys():
		roll -= maxf(0.0, float(weights[key]))
		if roll <= 0.0:
			return str(key)
	return "SCAVENGE"


func _build_topology() -> void:
	_room_neighbors.clear()
	_open_edges.clear()
	for record in _records:
		_room_neighbors[str(record["id"])] = []
	for record in _records:
		var child_id := str(record["id"])
		var parent_id := str(record.get("parent", ""))
		if parent_id.is_empty():
			continue
		(_room_neighbors[parent_id] as Array).append(child_id)
		(_room_neighbors[child_id] as Array).append(parent_id)
		_open_edges[_edge_key(parent_id, child_id)] = false
		var child_pos := record["position"] as Vector3
		var parent_record := _find_record(parent_id)
		var parent_pos := parent_record["position"] as Vector3
		var parent_direction := _direction_between(parent_pos, child_pos)
		var child_direction := _opposite_direction(parent_direction)
		(parent_record["door_targets"] as Dictionary)[parent_direction] = child_id
		(record["door_targets"] as Dictionary)[child_direction] = parent_id
	_room_graph_runtime.configure(_records, _room_neighbors, _open_edges)


func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func _door_policy_for_edge(_from_room_id: String, _target_room_id: String) -> Dictionary:
	return {
		"requires_clear": true,
		"requires_key": true,
		"triggers_fate": true,
	}


func _door_policies_for_record(record: Dictionary) -> Dictionary:
	var policies := {}
	var room_id := str(record.get("id", ""))
	var targets := record.get("door_targets", {}) as Dictionary
	# 和平区（区块00 等）：门**只做普通开关** —— 不看清房进度、不要钥匙、不弹命运卡。
	# 覆盖放在这里而不是 `_door_policy_for_edge` 的逐边白名单里：区域内加门/改拓扑
	# 都不需要再动一次策略表，区域的全部门天然同策。
	if bool(record.get("authored_layout_peaceful", false)):
		for direction in targets.keys():
			policies[str(direction)] = {
				"requires_clear": false,
				"requires_key": false,
				"triggers_fate": false,
			}
		return policies
	for direction in targets.keys():
		policies[str(direction)] = _door_policy_for_edge(
			room_id,
			str(targets[direction])
		)
	return policies


func _direction_between(from: Vector3, to: Vector3) -> String:
	var delta := to - from
	if absf(delta.x) >= absf(delta.z):
		return "east" if delta.x >= 0.0 else "west"
	return "south" if delta.z >= 0.0 else "north"


func _opposite_direction(direction: String) -> String:
	return {"north": "south", "south": "north", "west": "east", "east": "west"}.get(direction, "east")


func _find_record(id: String) -> Dictionary:
	for record in _records:
		if record["id"] == id:
			return record
	return {}


func _room_size_for(type_id: String, index: int) -> String:
	if type_id == "BOSS":
		return "arena"
	if type_id in ["ELITE", "BASEMENT"]:
		return "large"
	if type_id in ["STORAGE", "TRAP", "STAIRS_DOWN", "STAIRS_UP", "ELEVATOR"]:
		return "small"
	if type_id in ["MERCHANT", "UPGRADE", "EVENT"]:
		return "small" if index % 2 == 0 else "medium"
	return ["small", "medium", "medium", "large"][index % 4]


func _build_corridor(
	from_room: DungeonRoom3D,
	to_room: DungeonRoom3D,
	index: int,
	persistent: bool = false,
	lateral_offset_m: float = 0.0
) -> void:
	var from := from_room.global_position
	var to := to_room.global_position
	var delta := to - from
	var horizontal := absf(delta.x) > absf(delta.z)
	var planar_delta := Vector3(delta.x, 0, delta.z)
	var direction := planar_delta.normalized()
	var from_dimensions := from_room.get_dimensions()
	var to_dimensions := to_room.get_dimensions()
	var from_half := from_dimensions.x * 0.5 if horizontal else from_dimensions.y * 0.5
	var to_half := to_dimensions.x * 0.5 if horizontal else to_dimensions.y * 0.5
	var start := from + direction * (from_half - 0.18)
	var end := to - direction * (to_half - 0.18)
	# 走廊中心线 = 两端门位（05.2 §3.5.2「两侧 lane 决定同一条走廊中心线」）。
	# 门位不在墙面中心时，走廊必须整体沿切向平移同样的距离，否则门在左侧、
	# 走道在中轴，玩家出门就撞墙。
	if not is_zero_approx(lateral_offset_m):
		var lateral_axis := Vector3(0, 0, 1) if horizontal else Vector3(1, 0, 0)
		start += lateral_axis * lateral_offset_m
		end += lateral_axis * lateral_offset_m
	var center := (start + end) * 0.5
	var length := maxf(0.6, start.distance_to(end))
	var body := StaticBody3D.new()
	body.name = "Corridor_%02d" % index
	body.position = center + Vector3(0, -0.12, 0)
	var is_vertical_connector := absf(end.y - start.y) > 0.01
	if horizontal and is_vertical_connector:
		var dx := end.x - start.x
		body.rotation.z = atan((end.y - start.y) / dx) if absf(dx) > 0.01 else 0.0
	elif not horizontal and is_vertical_connector:
		var dz := end.z - start.z
		body.rotation.x = -atan((end.y - start.y) / dz) if absf(dz) > 0.01 else 0.0
	body.set_meta("is_vertical_connector", is_vertical_connector)
	body.set_meta("from_room_id", from_room.room_id)
	body.set_meta("to_room_id", to_room.room_id)
	body.set_meta("height_delta", to.y - from.y)
	body.collision_layer = 1
	body.collision_mask = 0
	$GeneratedCorridors.add_child(body)
	var edge := _edge_key(from_room.room_id, to_room.room_id)
	if not persistent:
		_corridor_by_edge[edge] = body
	# `persistent` = 子图走廊：子图房间不进 `_open_edges` / `_spawned_rooms`，
	# 走流送判定的走廊会永远 visible=false 且碰撞被禁用 —— 玩家一脚踩空掉出关卡。
	body.visible = persistent
	body.process_mode = Node.PROCESS_MODE_INHERIT if persistent else Node.PROCESS_MODE_DISABLED
	var floor_size := Vector3(length, 0.26, 3.8) if horizontal else Vector3(3.8, 0.26, length)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = visual_theme.floor_color.lightened(0.055)
	floor_material.metallic = 0.08
	floor_material.roughness = 0.90
	_spawn_corridor_piece(body, "CorridorFloor_%02d" % index, CORRIDOR_FLOOR_PREFAB, floor_size, Vector3.ZERO, floor_material, not persistent)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = visual_theme.wall_color.darkened(0.08)
	wall_material.metallic = 0.62
	wall_material.roughness = 0.58
	for side in [-1.0, 1.0]:
		var wall_size := Vector3(length, 2.25, 0.25) if horizontal else Vector3(0.25, 2.25, length)
		var wall_offset := Vector3(0, 1.25, side * 1.92) if horizontal else Vector3(side * 1.92, 1.25, 0)
		var side_index := 0 if side < 0.0 else 1
		_spawn_corridor_piece(body, "CorridorWall_%02d_%d" % [index, side_index], CORRIDOR_WALL_PREFAB, wall_size, wall_offset, wall_material, not persistent)
	if is_vertical_connector:
		# 封闭楼梯间顶部与墙共同阻挡视线；台阶只做可读表现，连续斜坡承担移动碰撞。
		var ceiling_size := Vector3(length, 0.22, 3.8) if horizontal else Vector3(3.8, 0.22, length)
		_spawn_corridor_piece(body, "StairwellCeiling_%02d" % index, CORRIDOR_CEILING_PREFAB, ceiling_size, Vector3(0, 2.38, 0), wall_material)
		var step_count := maxi(5, int(length / 0.85))
		for step_index in range(step_count):
			var ratio := (float(step_index) + 0.5) / float(step_count)
			var tread_size := Vector3(length / float(step_count) * 0.82, 0.07, 3.46) if horizontal else Vector3(3.46, 0.07, length / float(step_count) * 0.82)
			var tread_offset := Vector3(
				lerpf(-length * 0.5, length * 0.5, ratio) if horizontal else 0.0,
				0.075,
				0.0 if horizontal else lerpf(-length * 0.5, length * 0.5, ratio)
			)
			_spawn_corridor_piece(body, "StairTread_%02d_%02d" % [index, step_index], CORRIDOR_STAIR_TREAD_PREFAB, tread_size, tread_offset, wall_material, not persistent)


func _spawn_corridor_piece(parent: Node3D, node_name: String, prefab: PackedScene, scale_vec: Vector3, local_position: Vector3, material: StandardMaterial3D, collisions_disabled: bool = true) -> void:
	if prefab == null:
		push_error("Dungeon3D: missing corridor prefab for %s" % node_name)
		return
	var instance := prefab.instantiate() as Node3D
	if instance == null:
		return
	instance.name = node_name
	instance.position = local_position
	instance.scale = scale_vec
	_apply_corridor_material_override(instance, material)
	_set_corridor_collisions_disabled(instance, collisions_disabled)
	parent.add_child(instance)


func _apply_corridor_material_override(root: Node, material: StandardMaterial3D) -> void:
	if material == null:
		return
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = material
	for child in root.get_children():
		_apply_corridor_material_override(child, material)


func _set_corridor_collisions_disabled(root: Node, disabled: bool) -> void:
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = disabled
	for child in root.get_children():
		_set_corridor_collisions_disabled(child, disabled)


## v0.1 v2 房间布局规划阶段
## 遍历所有房与门，根据门 world pos 预存 “room_door_world_<dir>” meta。
## 拼墙阶段 (_build_corner_aware_wall_run) 读这个 meta 以门 world pos 作锥点拼门洞。
func _plan_room_layout() -> void:
	for room in _rooms:
		if room == null:
			continue
		var dimensions := room.get_dimensions()
		# 1. 为每扇门算 door_offset_along（距 0 最近的 5m 段中心点），写 meta
		for direction in room.doors:
			var horizontal := direction in ["north", "south"]
			var length := dimensions.x if horizontal else dimensions.y
			if length <= 0.0:
				continue
			var module_count := maxi(1, int(round(length / 5.0)))
			# 默认门位于沿墙中心：选距 0 最近的 5m 段。
			var best_module := -1
			var best_dist := 1e9
			for module_index in range(module_count):
				var segment_center := -length * 0.5 + 5.0 * (float(module_index) + 0.5)
				var d := absf(segment_center)
				if d < best_dist:
					best_dist = d
					best_module = module_index
			var door_offset_along := -length * 0.5 + 5.0 * (float(best_module) + 0.5)
			room.set_meta("tower_wall_door_offset_%s" % direction, door_offset_along)
		# 2. meta 写完后，门 world pos 重新算（读完刚写入的 meta）→ 存 room_door_world_<dir>
		for direction in room.doors:
			var door_world: Vector3 = _room_door_world_position(room, direction)
			room.set_meta("room_door_world_%s" % direction, door_world)


## 房间门 world 位置（基类实现，默认门位于房间中心偏门所在墙中点）。
## TowerDescent3D 会重写以支持楼梯特殊情况。

func _room_door_world_position(room: DungeonRoom3D, side: String) -> Vector3:
	var outward := {
		"north": Vector3(0, 0, -1),
		"south": Vector3(0, 0, 1),
		"west": Vector3(-1, 0, 0),
		"east": Vector3(1, 0, 0),
	}.get(side, Vector3(-1, 0, 0)) as Vector3
	var dimensions := room.get_dimensions()
	var half_extent := dimensions.y * 0.5 if side in ["north", "south"] else dimensions.x * 0.5
	var along_axis := Vector3(1, 0, 0) if side in ["north", "south"] else Vector3(0, 0, 1)
	# 默认门距 0：门位于沿墙中心位置 (0 + 0)
	var door_offset_along := 0.0
	return room.global_position + outward * half_extent + along_axis * door_offset_along


func _create_extraction() -> void:
	var room: DungeonRoom3D = _room_by_id.get("extraction") as DungeonRoom3D
	if room == null:
		return
	_extraction = _create_extraction_beacon(room, "BOSS_KILL", 30.0, true, Vector3.ZERO)
	_conditional_extractions["BOSS_KILL"] = _extraction
	var fixed_candidates: Array[String] = []
	for record in _records:
		var candidate_id := str(record.get("id", ""))
		var candidate_role := str(record.get("role", ""))
		# TowerDescent3D 把战斗房 id 写成 floor_NN_main_XX，
		# 早期手写关卡才是 main_XX；两种 id 格式都要兼容。
		if (candidate_id.begins_with("main_") or candidate_role == "main") and int(record.get("index", 0)) >= 2:
			fixed_candidates.append(candidate_id)
	# 1. facility（99 层基地）：玩家随时撤离的兑底点，locally 始终存在。
	var facility_room := _room_by_id.get("facility") as DungeonRoom3D
	if facility_room != null:
		_standard_extraction = _create_extraction_beacon(facility_room, "STANDARD", 30.0, false, Vector3(-4.2, 0.0, 3.2))
		_conditional_extractions["STANDARD"] = _standard_extraction
	# 2. 随机战斗房：随机放置一个额外的 STANDARD 撤离点。
	if not fixed_candidates.is_empty():
		var fixed_id := fixed_candidates[_rng.randi_range(0, fixed_candidates.size() - 1)]
		var fixed_room := _room_by_id.get(fixed_id) as DungeonRoom3D
		if fixed_room != null:
			var extra := _create_extraction_beacon(fixed_room, "STANDARD", 30.0, false, Vector3(-4.2, 0.0, 3.2))
			# 非塔楼行动区没有 facility：此时随机战斗房就是唯一 STANDARD，
			# 仍需写入标准键并保存主引用，不能只登记成 BONUS 后失去测试/交互入口。
			if _standard_extraction == null:
				_standard_extraction = extra
				_conditional_extractions["STANDARD"] = extra
			else:
				_conditional_extractions["STANDARD_BONUS"] = extra


func _create_extraction_beacon(room: DungeonRoom3D, type_id: String, countdown: float, locked: bool, local_position: Vector3) -> ExtractionBeacon3D:
	if room == null:
		return null
	var beacon := EXTRACTION_SCENE.instantiate() as ExtractionBeacon3D
	beacon.configure(visual_theme.accent_color, countdown * _extraction_time_multiplier, type_id)
	room.add_child(beacon)
	beacon.position = local_position
	beacon.set_locked(locked)
	beacon.extraction_started.connect(_on_extraction_started.bind(beacon))
	beacon.extraction_progress.connect(_on_extraction_progress.bind(beacon))
	beacon.extraction_cancelled.connect(_on_extraction_cancelled.bind(beacon))
	beacon.extraction_completed.connect(_on_extraction_completed.bind(beacon))
	return beacon


func _on_room_entered(room: DungeonRoom3D) -> void:
	if room == null:
		return
	var first_visit := not _fate_visited_rooms.has(room.room_id)
	if first_visit:
		_fate_visited_rooms[room.room_id] = true
		player.on_fate_room_entered(room.room_id)
	_expire_temporary_room_keys(_fate_floor_key(room))
	var previous_runtime_room_id := _current_room_id
	if not _current_room_id.is_empty() and _current_room_id != room.room_id:
		var previous_room := _room_by_id.get(_current_room_id) as DungeonRoom3D
		if previous_room != null:
			previous_room.hide_door_prompts()
	if not previous_runtime_room_id.is_empty() and previous_runtime_room_id != room.room_id:
		_cancel_room_wave_intermission(previous_runtime_room_id)
		_capture_room_runtime_state(previous_runtime_room_id)
	_current_room_id = room.room_id
	_last_main_room_id = room.room_id
	room_entered.emit(room)
	if _runtime_persistence_active and BaseManager != null:
		BaseManager.flush_runtime_checkpoint("room_transition")
	minimap.set_current_room(room.room_id)
	_update_room_streaming(room.room_id)
	room_label.text = "%s · %s/%s" % [room.room_id, room.room_type, room.size_class.to_upper()]
	_update_wave_hud(room.room_id)
	if _spawned_rooms.has(room.room_id):
		_ensure_room_key_reward(room)
		_repair_room_progress(room)
		if not _wave_spawn_pending.has(room.room_id):
			status_label.text = _return_room_status(room)
		return
	_spawned_rooms[room.room_id] = true
	if _room_grants_starter_supply(room):
		call_deferred("_spawn_starter_weapon_pickup", room)
	if room.room_type in HOSTILE_ROOM_TYPES:
		_spawn_room_enemies(room)
	elif room.room_type == "EVENT":
		room.cleared = false
		var event_ready := _ensure_event_room_objective(room)
		# 「事件 + 战斗」双职房（业主裁定 2026-09-26）：EVENT 房带**编排战斗**时，事件终端照常保留、
		# 同时出波。⚠️ 只有真有编排战斗才进刷怪入口 —— 否则无编成的 EVENT 房会掉进
		# `_spawn_room_enemies` 的公式兜底刷出随机怪（不是本意）。
		# 编排战斗的两种承载（触发盒 / 踩点触发式遭遇）都由 `_event_room_has_authored_combat` 认。
		if _event_room_has_authored_combat(room):
			_event_combat_rooms[room.room_id] = true
			_spawn_room_enemies(room)
			if event_ready:
				status_label.text = "事件房：清除异常敌群，并按 E 使用紫色光柱"
			else:
				status_label.text = "事件房：清除异常敌群"
		elif event_ready:
			status_label.text = "事件房：前往紫色光柱，按 E 使用异常信号终端"
	else:
		status_label.text = _room_status(room.room_type)
		_mark_room_cleared(room, room.room_type not in ["START", "EXTRACTION", "ELEVATOR"])


## 「事件 + 战斗」双职房判据：EVENT 房带了**编排战斗**才带战斗（业主裁定 2026-09-26）。
## 刻意与 `HOSTILE_ROOM_TYPES` 分开：EVENT 不在**公式刷怪**的入口门里，只有带编排战斗才有战斗，
## 免得塔楼 / 主题池里没有编排战斗的程序化事件房被顺带刷上随机怪。
## 判据只看设计源（`spawn_placements` / `encounter.trigger`），不看运行态 —— 进房首帧就要定。
##
## ⚠ 2026-10-16 扩展：编排战斗现在有两种承载 —— **触发盒**与**踩点触发式遭遇**。
## 旧判据只认盒子，而 `room_09`（本关唯一 EVENT 房）改踩点遭遇后 `spawn_placements` 清空 ⇒
## 判据返回 false ⇒ `_on_room_entered` 的 EVENT 分支**根本不调 `_spawn_room_enemies()`**，
## 该房于是被当成「纯事件房」：`_event_combat_rooms` 不登记 ⇒
## 事件终端一结算就走到 `_mark_room_cleared()`，**敌群还在场上就把去路门放行**。
## 所以判据必须与「编排战斗由谁承载」同步扩，不能只认其中一种。
func _event_room_has_authored_combat(room: DungeonRoom3D) -> bool:
	if room == null or room.room_type != "EVENT":
		return false
	if _room_has_encounter_trigger(room):
		return true
	return not room.spawn_placements.is_empty()


## —— 踩点触发式遭遇（`encounter.trigger`，调用层扩展）——
##
## 与既有「触发盒」的关系：**盒子管出什么怪，这里管什么时候开始**，正是
## `触发器刷怪设计.md` §3.3「调用机制与盒子分开写」那条分层的直接落地。
## 现有调用机制只有一种（玩家进房即出）；本段加上第二种（走到房间内某点才出）。
##
## 三条硬约束，缺一都会表现成「说不清的怪现象」：
##   1. 进房时**不刷怪、且不判清房**（见 `_spawn_room_enemies` 的早退分支）——
##      否则去路门立刻解锁，玩家根本不会走到触发点。
##   2. 波与波之间场上会短暂清空 ⇒ `_resolve_room_enemy_departure` 必须认
##      `_room_encounter_active` 这道门，否则第一波清完就把房间判清、门放行。
##   3. 计时到点后不再开新波（由 Director 的 `_drop_unstarted_stages` 负责），
##      但**已出的怪仍要打完** —— 所以封门只在「房间真被肃清」时解除。
const STRONG_RANDOM_FALLBACK: Array[String] = [
	"melee_chaser_strong", "fat_zombie03_strong", "ranged_caster_strong",
]


func _room_has_encounter_trigger(room: DungeonRoom3D) -> bool:
	if room == null:
		return false
	return not (room.encounter.get("trigger", {}) as Dictionary).is_empty()


## 触发区中心（带心 / 圆心）。**按房间局部坐标换算到世界**，不是把偏移当世界轴用 ——
## 远征01 的 room_04 / room_06 / room_10 被端口对接链旋转过 90°，布局里的
## `size_m` / `position_m` 是**示例版图**口径，与运行时局部轴不是同一套
## （实测：room_04 布局写 45×40，运行时是 40×45；布局写 `template_rotation_deg: 0`，
## 而运行时几何已经转过了）。
func _room_encounter_trigger_center(room: DungeonRoom3D) -> Vector3:
	var trigger := room.encounter.get("trigger", {}) as Dictionary
	var offset := _placement_vec2(trigger.get("offset_m", [0.0, 0.0]))
	return room.to_global(Vector3(offset.x, 0.0, offset.y))


## 触发判定：`circle`（房心半径，沿用）或 `band`（**满宽带**）。
##
## 为什么要有带：圆的半径再大也**绕得过去** —— 玩家贴着墙走就能从旁边溜过，
## 触发不了。带的作用是**不可绕过**：它沿 `axis` 铺满房间在该轴上的整个跨度，
## 只在另一根轴上有 `thickness_m` 的厚度；只要厚度轴与**入口门的法线同轴**，
## 从入口进来的任何一条连续路径都必须穿过它。
##
## 判定在**房间局部坐标**里做（`to_local`），因此房间被旋转过也照样正确 ——
## 而且「铺满整轴」按的是运行时 `get_dimensions()`，不是写死的数字：
## 房间被重新对接、尺寸变化时，带子自动跟着铺满，不会留下一条可钻的缝。
func _room_encounter_trigger_contains(room: DungeonRoom3D, world_position: Vector3) -> bool:
	if room == null:
		return false
	var trigger := room.encounter.get("trigger", {}) as Dictionary
	if trigger.is_empty():
		return false
	var offset := _placement_vec2(trigger.get("offset_m", [0.0, 0.0]))
	var local := room.to_local(world_position) - Vector3(offset.x, 0.0, offset.y)
	local.y = 0.0
	if str(trigger.get("shape", "circle")) == "band":
		var thickness := maxf(0.1, float(trigger.get("thickness_m", 6.0)))
		var dimensions := room.get_dimensions()
		# 轴约定与 `DungeonRoom3D` 的门位表同一套：北 = -z、南 = +z、东 = +x、西 = -x。
		if str(trigger.get("axis", "z")) == "x":
			return absf(local.z) <= thickness * 0.5 and absf(local.x) <= dimensions.x * 0.5
		return absf(local.x) <= thickness * 0.5 and absf(local.z) <= dimensions.y * 0.5
	var radius := maxf(1.0, float(trigger.get("radius_m", 6.0)))
	return local.length() <= radius


## 右上角遭遇倒计时环：只对「当前房里、仍在跑、且声明了 `hud_countdown` 的事件」显示。
##
## 不按事件类型硬编码 —— 撤离防守若哪天也想要环，只需在它的配置里开
## `hud_countdown`，不必在这里再加一条分支。读数直接取自事件快照，
## 不另存一份倒计时：两处计时必然会漂，而漂了之后没人知道该信哪个。
func _tick_encounter_countdown_hud() -> void:
	if _hud_countdown_ring == null:
		return
	if _encounter_event_director == null or _current_room_id.is_empty():
		_hud_countdown_ring.visible = false
		return
	var snapshot := _encounter_event_director.get_room_countdown_snapshot(_current_room_id)
	if snapshot.is_empty():
		# 事件终结（完成 / 取消 / 失败）或玩家离房 ⇒ 环立即消失，不留残影。
		_hud_countdown_ring.visible = false
		return
	var config := snapshot.get("config", {}) as Dictionary
	var duration := maxf(0.001, float(config.get("duration_sec", 0.0)))
	_hud_countdown_ring.visible = true
	_hud_countdown_ring.set_time(duration - float(snapshot.get("elapsed", 0.0)), duration)


## 逐帧轮询触发点。**刻意不用 Area3D**：与剧情位置触发同一取舍 ——
## 多一个常驻 Area3D 就是多一份节点预算与碰撞层维护，而这里只需要一次距离比较。
func _tick_room_encounter_triggers(_delta: float) -> void:
	if _completed or _current_room_id.is_empty() or player == null:
		return
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if not _room_has_encounter_trigger(room):
		return
	if _room_encounters_fired.has(room.room_id):
		return
	if not _room_encounter_trigger_contains(room, player.global_position):
		return
	_start_room_encounter(room)


func _start_room_encounter(room: DungeonRoom3D) -> Dictionary:
	# 先记「已触发」再启动：启动失败也**不再重试**，避免玩家站在触发点上反复弹警告。
	_room_encounters_fired[room.room_id] = true
	var started := start_encounter_event(_build_room_encounter_config(room))
	if not bool(started.get("ok", false)):
		push_warning("[Dungeon3D] 踩点遭遇启动失败（%s）：%s" % [room.room_id, str(started)])
		return started
	_room_encounter_active[room.room_id] = str(started.get("instance_id", ""))
	if bool(room.encounter.get("seal_room", true)):
		set_room_seal(room.room_id, true, "encounter")
	if AudioManager != null:
		AudioManager.play_sfx("wave_start", -3.0)
	if _is_current_room(room.room_id):
		status_label.text = "遭遇开始 · 击退所有波次才能离开"
	return started


## 由房间的 `encounter` 编译成遭遇事件配置。
##
## 与撤离防守的差别只有两处，都是刻意的：
##   · `progress_mode: tick`（自己计时，不需要外部喂进度）；
##   · `stage_advance: clear`（一波清完才出下一波，而不是按撤离进度追加）。
func _build_room_encounter_config(room: DungeonRoom3D) -> Dictionary:
	var encounter := room.encounter
	var floor := maxi(1, visual_theme.difficulty_rank)
	var floor_level := clampi(
		int(float(_record_index(room.room_id)) / maxf(1.0, float(_records.size() - 1)) * 3.0), 0, 3
	)
	var start_delay := maxf(0.0, float(encounter.get("start_delay_sec", 1.0)))
	var stages: Array = []
	var raw_stages := encounter.get("stages", []) as Array
	for index in raw_stages.size():
		var raw_stage := raw_stages[index] as Dictionary
		var monsters := _resolve_encounter_stage_monsters(
			raw_stage, room, floor, floor_level
		)
		if monsters.is_empty():
			continue
		stages.append({
			# 第一波给「落门 → 出怪」的准备间隔；后续波的门槛由清算条件把关，
			# 时间阈值只写 0 表示「前一波刚清完即可立刻开始」。
			"at_sec": start_delay if stages.is_empty() else 0.0,
			"monsters": monsters,
		})
	var actions: Array = []
	if bool(encounter.get("light_on_finish", false)):
		actions.append({"type": "light", "room_id": room.room_id, "on": true})
	# `hunt_player`：让这一波的怪**主动围向玩家**（而不是站在暗处等玩家撞上来）。
	# 触发式遭遇是"把玩家关进房里打完"，等同竞技场 —— 若还按野外潜行那套
	# 「要有视锥 + 视线才追」，关灯房里会有一半怪站原地不动。
	# `hud_countdown`：右上角倒计时环。二者都只是开关，判据全在机制侧。
	return {
		"schema_version": 1,
		"event_id": "room_encounter:%s" % room.room_id,
		"room_id": room.room_id,
		"duration_sec": maxf(1.0, float(encounter.get("duration_sec", 60.0))),
		"completion": "timer",
		"progress_mode": "tick",
		# 从数据读，缺省 `clear`。**不能写死**：`stage_advance` 是被
		# `LevelPlanValidator` 逐值校验的正式键（只许 `time` / `clear`），
		# 硬编码会让 `"time"` 静默失效 —— 数据说"按时间叠加"、
		# 实际表现却是"清完才出下一波"，这类"配了没生效"最难查。
		"stage_advance": str(encounter.get("stage_advance", "clear")),
		"hunt_player": bool(encounter.get("hunt_player", false)),
		"hud_countdown": bool(encounter.get("hud_countdown", true)),
		"leave_policy": "cancel",
		"max_alive": 2147483647,
		"prereqs": {"player_alive": true, "run_active": true},
		"stages": stages,
		"on_completed": actions,
	}


## 把一波的声明解析成遭遇事件的 `monsters` 数组。
##
## 两种写法，同一房里**只许用其中一种**：
##   · `{"monsters": [{"type": "melee_chaser", "count": 8}, ...]}` —— 显式编成；
##   · `{"type": "strong_random", "count": 2}` —— 「随机的强化僵尸」，
##     触发时从 `MonsterVariants` 的变种池里抽，抽成几个具体 `*_strong` 条目。
##     解析放在这里而不是 Director 里：Director 的配置契约只认**具体怪种**，
##     留在那边会污染它的类型白名单。
func _resolve_encounter_stage_monsters(
	raw_stage: Dictionary, room: DungeonRoom3D, floor: int, floor_level: int
) -> Array:
	var monsters: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ room.room_id.hash() ^ 0x53545247
	var pool: Array[String] = []
	pool.assign(MonsterVariants.all_variant_ids())
	if pool.is_empty():
		pool.assign(STRONG_RANDOM_FALLBACK)
	for value in raw_stage.get("monsters", []) as Array:
		var entry := value as Dictionary
		var type_id := str(entry.get("type", ""))
		var count := maxi(0, int(entry.get("count", 0)))
		if count <= 0:
			continue
		if type_id != "strong_random":
			monsters.append({"type": type_id, "count": count})
			continue
		# 抽成逐只的具体变种，再按怪种归并 —— Director 只认「具体怪种 + 数量」。
		var tally: Dictionary = {}
		for _unit in count:
			var picked: String = pool[rng.randi() % pool.size()]
			tally[picked] = int(tally.get(picked, 0)) + 1
		for picked_value in tally.keys():
			monsters.append({"type": str(picked_value), "count": int(tally[picked_value])})
	return monsters


## 封住 / 解开一个房间：封住期间门保持关闭且不可交互。
##
## 为什么不能只 `set_door_open(false)`：门关上了玩家按 E 还能再开（来路的边已是
## 开启状态，`_try_open_room_door` 会直接回「通道已经开启」）。所以必须同时
## 掐掉交互候选与开门判定，见 `get_interaction_candidate` / `_try_open_room_door`。
##
## ⚠ **共享边的门扇不在本房手里**（2026-10-16 修）：一条边只由一端建门扇，另一端
## `_door_nodes` 里没有节点。旧实现只遍历本房 `door_targets` 并 `room.set_door_open(...)`：
## 入口方向拿不到节点时 `set_door_open` 里 `if door != null` 静默早退 —— 门根本没关，
## 玩家可以直接从进来那扇门走出去。所以本房没有节点时，必须**按目标房去对端关那扇**。
func set_room_seal(room_id: String, sealed: bool, reason: String = "") -> void:
	if room_id.is_empty():
		return
	if sealed:
		_sealed_rooms[room_id] = reason
	else:
		_sealed_rooms.erase(room_id)
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null or not is_instance_valid(room):
		return
	if not sealed:
		# 解封只恢复「可以开」，不替玩家把门推开 —— 门该由玩家自己按 E。
		return
	for direction_value in room.door_targets.keys():
		var direction := str(direction_value)
		var local_door := room.get_door_node(direction)
		if local_door != null:
			room.set_door_open(direction, false)
			continue
		# 本房没有这扇门 ⇒ 它是共享边，门扇在对端。按"通向哪一间"去对端取同一扇门。
		var peer_id := str(room.door_targets[direction_value])
		var peer := _room_by_id.get(peer_id) as DungeonRoom3D
		if peer == null or not is_instance_valid(peer):
			continue
		var peer_door := peer.get_door_node_towards(room_id)
		if peer_door != null:
			peer_door.set_open(false)


## 房间肃清、解封之后的关卡级收尾。基类什么都不做。
##
## 存在的理由：flow 关卡（远征03）要在这一刻**自动把门推开**，
## 而 `_mark_room_cleared()` 是塔楼与远征共用的实现 —— 直接往里塞关卡分支
## 会让两个玩法的清房语义互相污染。钩子只给需要定制的关卡一个落点。
func _on_room_unsealed(_room: DungeonRoom3D) -> void:
	pass


func _room_is_sealed(room_id: String) -> bool:
	return _sealed_rooms.has(room_id)


func _is_current_room(room_id: String) -> bool:
	return room_id == _current_room_id


func _spawn_room_enemies(room: DungeonRoom3D) -> bool:
	if room == null:
		return false
	# —— 踩点触发式遭遇（`encounter.trigger`）——
	# 本房不在进房时刷怪：玩家走到房间里那个触发点才开始。这里**刻意清空**波次账、
	# 但**绝不 `_mark_room_cleared`** —— 房间要保持「未肃清」，否则去路门会被当成
	# 已通、玩家可以直接走到下一房，触发也就没意义了。
	# 触发本身由 `_tick_room_encounter_triggers()` 逐帧轮询（零新增常驻节点）。
	if _room_has_encounter_trigger(room):
		_alive_by_room[room.room_id] = 0
		_room_wave_queues[room.room_id] = []
		room.cleared = false
		_update_wave_hud(room.room_id)
		return true
	# 和平区（区块00 等叙事固定关卡）：本房**不刷怪**，开局即放行。
	#   · 房型保持 COMBAT 不变（HUD / 小地图 / 流送语义与塔楼其余楼层一致），
	#     只是没有敌人 —— 与「未指派首领的 BOSS 房」同口径：立刻清房，绝不留下锁门。
	#   · `cleared = true` 同时挡住 `_repair_hostile_room_progress` 的补刷路径
	#     （它头一行就是 `room.cleared` 早退），所以这里不需要在那边再加分支。
	#   · 不给钥匙奖励（spawn_key=false）：门策略已全放行，区域不产生战斗收益。
	if room.authored_layout_peaceful:
		_alive_by_room[room.room_id] = 0
		_room_wave_queues[room.room_id] = []
		_mark_room_cleared(room, false)
		status_label.text = "和平区 · 无敌对信号"
		return true
	var floor := maxi(1, visual_theme.difficulty_rank)
	var floor_level := clampi(int(float(_record_index(room.room_id)) / maxf(1.0, float(_records.size() - 1)) * 3.0), 0, 3)
	# —— 触发盒路径（`docs/v0.1/design/触发器刷怪设计.md` §4）——
	# 房间声明了 `spawn_placements` 就**只认盒子**：出什么怪、几只、几时出全部由盒子给，
	# 旧的三条路（enemy_spawn_plan / 房型分支 / 数量公式）一律不参与。
	# 「只认盒子」层（spawn_boxes_only）里没摆盒子 ⇒ **不刷怪**（业主裁定：没盒子就不刷）：
	# 房型保持敌对不变（门/小地图/HUD 语义一致），只是没有敌人，立刻清房，绝不留锁门。
	var box_waves := _spawn_box_waves(room, floor, floor_level)
	if not box_waves.is_empty():
		return _commit_room_waves(room, box_waves)
	if room.spawn_boxes_only:
		_alive_by_room[room.room_id] = 0
		_room_wave_queues[room.room_id] = []
		_mark_room_cleared(room, false)
		status_label.text = "本区未布置触发盒 · 无敌对信号"
		return true
	# —— 设计源覆盖（房间级）——
	# 房间若声明了 enemy_spawn_plan，则波次数、每波数量、怪物组成全部以设计源为准：
	# desired 数量公式、COMBAT 波次表 [1,2,2,3]、主题权重池（enemy_pool）一律不参与。
	# 单只怪的数值仍由 MonsterInjector 出（主题倍率 + 楼层缩放照常生效）。
	var authored_waves := _authored_spawn_waves(room, floor, floor_level)
	if not authored_waves.is_empty():
		return _commit_room_waves(room, authored_waves)
	var enemy_configs: Array[Dictionary] = []
	match room.room_type:
		"BOSS":
			# Boss 身份由 BossContentCatalog 唯一解析（设计源 boss_content_id 优先，其次按层号）。
			# 取不到 → 本房不出 Boss，这是「没写 boss 就是没有 boss」的口径，属**合法空房**。
			var boss_configs := _monster_injector.generate_enemies({
				"type": "boss", "floor": floor, "floor_level": floor_level,
				"floor_number": _elite_floor_number(room),
				"boss_content_id": str(room.get_meta("boss_content_id", "")),
			})
			# 声明了 Boss 增援计划的房间同时声明唯一中心出生点；只改 Boss，不挪精英随从。
			if not room.boss_reinforcement_plan.is_empty():
				for boss_config in boss_configs:
					boss_config["spawn_position"] = room.boss_spawn_position_world()
			enemy_configs.assign(boss_configs)
			# 没有 Boss 就不配精英随从：否则「未指派首领房」会变成精英房，与本房声明不符。
			if not boss_configs.is_empty():
				enemy_configs.append_array(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": floor_level, "floor_number": _elite_floor_number(room), "encounter_id": _elite_encounter_id(room), "seed": run_seed}))
		"ELITE":
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": floor_level, "floor_number": _elite_floor_number(room), "encounter_id": _elite_encounter_id(room), "seed": run_seed}))
		"TRAP":
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "ambush", "count": 3 + floor / 2, "floor": floor, "floor_level": floor_level}))
		"BASEMENT":
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "elite", "floor": floor, "floor_level": maxi(RoomData.FloorLevel.MEDIUM, floor_level), "floor_number": _elite_floor_number(room), "encounter_id": _elite_encounter_id(room), "seed": run_seed}))
			enemy_configs.append_array(_monster_injector.generate_enemies({"type": "random", "floor": floor, "floor_level": maxi(RoomData.FloorLevel.MEDIUM, floor_level)}))
		_:
			enemy_configs.assign(_monster_injector.generate_enemies({"type": "random", "floor": floor, "floor_level": floor_level}))
			var desired := 4 + floor * 2 + (2 if room.size_class == "large" else 4 if room.size_class == "arena" else 0)
			var attempts := 0
			while enemy_configs.size() < desired and attempts < ENEMY_FILL_ATTEMPT_LIMIT:
				attempts += 1
				var generated := _monster_injector.generate_enemies({
					"type": "random", "floor": floor, "floor_level": floor_level,
				})
				if generated.is_empty():
					continue
				enemy_configs.append_array(generated)
			# 主题怪物池损坏时也不能无限循环或留下未清空的锁房。
			while enemy_configs.size() < desired:
				var fallback := _monster_injector.generate_enemies({
					"type": "safe_fallback", "floor": floor, "floor_level": floor_level,
				})
				if fallback.is_empty():
					break
				enemy_configs.append(fallback[0])
	# 未正式投放的精英不会以通用外壳混入游戏。精英/地下室房在当前楼层
	# 没有可用内容时降级为普通战斗；Boss房则保持Boss单独出场。
	if enemy_configs.is_empty() and room.room_type in ["ELITE", "BASEMENT"]:
		enemy_configs.assign(_monster_injector.generate_enemies({
			"type": "random", "floor": floor, "floor_level": floor_level,
		}))
	# 设计源把 BOSS 房留空（未指派首领，且本层也没有按层指派的内容）是**合法空房**：
	# 不刷 Boss、不报错、直接放行 —— 这是「没写 boss 就是没有 boss」这一条口径的落地。
	# 必须早于下面的通用空房分支，否则会以「敌群生成失败」误报并刷屏 push_error。
	# 顺序要紧：塔楼的 _mark_room_cleared 会在 BOSS 房授予下行权限并改状态栏文案，
	# 故先清房、后写文案，免得留下「Boss 已击败」这种不实提示。
	if enemy_configs.is_empty() and room.room_type == "BOSS":
		_alive_by_room[room.room_id] = 0
		_room_wave_queues[room.room_id] = []
		_mark_room_cleared(room, true)
		status_label.text = "首领房未指派首领 · 区域已放行"
		return true
	if enemy_configs.is_empty():
		push_error("Hostile room %s generated no enemies; unlocking room to prevent a soft lock" % room.room_id)
		_alive_by_room[room.room_id] = 0
		_room_wave_queues[room.room_id] = []
		_mark_room_cleared(room, true)
		status_label.text = "敌群生成失败，房间已安全解锁"
		return false
	var wave_count := 1
	if room.room_type == "COMBAT":
		wave_count = [1, 2, 2, 3][floor_level]
	wave_count = clampi(wave_count, 1, maxi(1, enemy_configs.size()))
	var waves: Array = []
	var cursor := 0
	for wave_index in range(wave_count):
		var remaining := enemy_configs.size() - cursor
		var batch_size := int(ceil(float(remaining) / float(wave_count - wave_index)))
		var batch: Array[Dictionary] = []
		for _index in range(batch_size):
			batch.append(enemy_configs[cursor])
			cursor += 1
		waves.append(batch)
	return _commit_room_waves(room, waves)


## 只在真实敌群首次提交时消费下一房规则，和平房与预览不吞卡。
func _note_room_enemy_modifiers(room: DungeonRoom3D) -> void:
	if _room_enemy_hp_multipliers.has(room.room_id):
		return
	_room_enemy_hp_multipliers[room.room_id] = _next_room_enemy_hp_multiplier
	_room_enemy_damage_multipliers[room.room_id] = float(_room_enemy_damage_multipliers.get(room.room_id, 1.0)) * _next_room_enemy_damage_multiplier
	_room_currency_multipliers[room.room_id] = float(_room_currency_multipliers.get(room.room_id, 1.0)) * _next_room_currency_multiplier
	_next_room_enemy_hp_multiplier = 1.0
	_next_room_enemy_damage_multiplier = 1.0
	_next_room_currency_multiplier = 1.0
	_room_fate_clear_currency[room.room_id] = _next_room_clear_currency
	_next_room_clear_currency = 0
	var bounty := 0
	for rule in _fate_bounty_queues:
		if int(rule["rooms"]) > 0:
			bounty += int(rule["amount"])
			rule["rooms"] = int(rule["rooms"]) - 1
		elif int(rule["zero_rooms"]) > 0:
			_room_zero_currency[room.room_id] = true
			rule["zero_rooms"] = int(rule["zero_rooms"]) - 1
	_room_fate_bounties[room.room_id] = bounty
	_fate_bounty_queues = _fate_bounty_queues.filter(func(rule: Dictionary) -> bool: return int(rule["rooms"]) > 0 or int(rule["zero_rooms"]) > 0)


## 读房间设计源给出的刷怪计划并转成波次（每项一波）。
## 返回空数组 = 没有覆盖（回退全局公式），不是「零敌人」。
## 房型判据走 GameDesignConfig.is_spawn_plan_authorable_room 这一条唯一口径，不在本处复刻：
## BOSS 房一律不接管 —— 即便数据绕过了静态校验，也必须让 boss + elite 生成照常执行，
## 否则表现为「Boss 房没有 Boss」并可能锁死下楼门。
func _authored_spawn_waves(room: DungeonRoom3D, floor: int, floor_level: int) -> Array:
	if _monster_injector == null or room.enemy_spawn_plan.is_empty():
		return []
	if not GameDesignConfig.is_spawn_plan_authorable_room(room.room_type):
		return []
	return _monster_injector.build_waves_from_plan(
		room.enemy_spawn_plan,
		floor,
		floor_level,
		# 「半钉死」波次的抽取种子：run_seed + 房 id 派生 ⇒ 同一局同一房每次调用结果一致
		#（补刷兜底重调 `_spawn_room_enemies` 时不会换成另一份编成），不同局 / 不同房则不同。
		# 逐值固定写法不使用它，故老关卡（99F）行为逐字不变。
		run_seed + room.room_id.hash()
	)


## —— 触发盒波次（`docs/v0.1/design/触发器刷怪设计.md` §4）——
##
## 房间声明了 `spawn_placements` 就**只认盒子**：出什么怪（type）、几只（count）、
## 几时出（delay_sec）全部由盒子给；本房摆几个盒子、第几波调哪几个由 `encounter` 给。
##
## 返回空数组 = 本房没摆盒子 ⇒ 由调用方决定「不刷」还是「回退旧路径」。
## 盒子只负责出怪，**调用机制不在盒子里**（业主口径），故本函数只管把两层拼起来。
func _spawn_box_waves(room: DungeonRoom3D, floor: int, floor_level: int) -> Array:
	var placements := room.spawn_placements
	if placements.is_empty():
		return []
	var stages := _resolve_encounter_stages(room.encounter, placements.size())
	if stages.is_empty():
		return []
	# 波间隙：`encounter.intermission_sec` 可逐房覆盖，缺省沿用全局常量。
	_room_intermission_seconds[room.room_id] = maxf(
		0.0, float(room.encounter.get("intermission_sec", ROOM_WAVE_INTERMISSION_SECONDS))
	)
	# 盒内数量区间（count.min/max）与「半钉死」编成同口径：本函数私有 rng，
	# 种子 = run_seed ^ 房 id 派生 ⇒ 同局同房每次调用恒定、不同局/不同房不同。
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ room.room_id.hash() ^ 0x424f5831
	var waves: Array = []
	for stage_value in stages:
		var entries: Array[Dictionary] = []
		for instance_value in (stage_value as Array):
			_collect_box_stage_entries(
				room, placements, int(instance_value), floor, floor_level, rng, entries
			)
		if entries.is_empty():
			continue
		# 每波至少一条**立刻**出怪：全员延迟时把第一条拉回 0。
		# 为什么必须要这条不变量：整波都是延迟 ⇒ 本批实到 0 只 ⇒ 落进既有空批分支
		# （push_error + 解锁房间），表现为「房间白送」，与作者意图完全相反。
		var has_immediate := false
		for entry in entries:
			if float(entry.get("spawn_delay_sec", 0.0)) <= 0.0:
				has_immediate = true
				break
		if not has_immediate:
			entries[0]["spawn_delay_sec"] = 0.0
		var batch: Array[Dictionary] = []
		batch.assign(entries)
		waves.append(batch)
	return waves


## 把某个盒子实例的出怪清单展开为一批敌人配置，追加进 `entries`（跨条目共享落点池）。
func _collect_box_stage_entries(
	room: DungeonRoom3D,
	placements: Array,
	instance_index: int,
	floor: int,
	floor_level: int,
	rng: RandomNumberGenerator,
	entries: Array[Dictionary]
) -> void:
	var placement := _box_placement_at(placements, instance_index)
	if placement.is_empty():
		return
	var box := SpawnBoxCatalog.load_box(str(placement.get("box", "")))
	if box.is_empty():
		push_error(
			"[Dungeon3D] 房间 %s 的触发盒实例 %d（%s）解析失败，已跳过"
			% [room.room_id, instance_index, str(placement.get("box", ""))]
		)
		return
	var spec: Array[Dictionary] = []
	var total := 0
	# 逐实例出怪总量增量（`spawn_placements[].count_bonus`，设计 §3.2）：
	# 只加在**首条非身份条目**上。为什么排除 `elite` / `boss`：那两条是**身份指派**
	# （内容），「加量」的语义是加普通杂兵；把它加到精英条目上会把「1 只精英」变成
	# 「N 只精英」，是阶跃式的难度跳变，不是业主口径的「多刷几只怪」。
	# 每条目仍各自抽 `count.min/max`，增量加在抽签结果上 ⇒ `box_wall_arc` 的 1~2 区间
	# 平移成 (1+N)~(2+N)，随机性保留。
	var bonus := int(placement.get("box_count_bonus", 0))
	var bonus_used := false
	# 逐实例出怪倍率（`spawn_placements[].count_multiplier`，设计 §3.2）：
	# 与 `count_bonus` 正交 —— 倍率管「每条目各自乘」，增量管「一次性平移总量」。
	# 业主 2026-09-29 口径「room1/room2 每个盒子里数量翻倍」= 倍率 2。
	# 为什么不能只靠 `count_bonus` 兑现翻倍：增量只加在**首条**条目上，
	# `box_room_spread`（近战×2 → 1s 爆×1）加 +3 会得到 5+1，不是 4+2 —— 翻不了。
	# 身份条目（elite/boss）同样**不参与**倍率：翻倍是加杂兵，不是加精英。
	var multiplier := maxi(1, int(placement.get("box_count_multiplier", 1)))
	for spawn_value in (box.get("spawns", []) as Array):
		var spawn := spawn_value as Dictionary
		var type_id := str(spawn.get("type", ""))
		var count := _roll_box_count(spawn, rng)
		if count > 0 and type_id != "elite" and type_id != "boss":
			# 先乘后加：`(抽签 × 倍率) + 增量`。顺序固定 ⇒ 同 seed 结果可复现。
			if multiplier > 1:
				count *= multiplier
			if bonus > 0 and not bonus_used:
				count += bonus
				bonus_used = true
		if count <= 0:
			continue
		spec.append({
			"type": type_id,
			"count": count,
			"delay_sec": float(placement.get("box_delay", 0.0)) + float(spawn.get("delay_sec", 0.0)),
		})
		total += count
	if total <= 0:
		return
	# 一次性取满 total 个盒内落点，再按条目切分 —— 让「同盒内的怪」彼此拉开，
	# 而不是每条各自从最远点重新起算（那会让第二条压到第一条头上）。
	var points := room.spawn_points_in_box(
		placement.get("box_center", Vector2.ZERO) as Vector2,
		placement.get("box_size", Vector2.ZERO) as Vector2,
		total,
		float(placement.get("box_rotation", 0.0)),
		float(box.get("min_spacing_m", 0.0)),
		int(box.get("wall_recess_tiles", SpawnBoxCatalog.DEFAULT_WALL_RECESS_TILES))
	)
	# 盒内排不下（异形房凹口 / 家具占位 / 盒太小）时**只出排得下的那几只**：
	# `spawn_points_in_box` 尾部补的 `Vector3.INF` 绝不能进 `_spawn_enemy_batch` ——
	# 后者见到非有限点会整批判「无合法落点」、置 `_room_spawn_blocked` 并把本房锁死，
	# 表现是「一只都不出且房间不解锁」（比少出几只严重得多）。降级语义与业主口径
	# 「没盒子就不刷」同源：宁可少出，不可锁死。
	var available: Array[Vector3] = []
	for point in points:
		if point.is_finite():
			available.append(point)
	if available.is_empty():
		return
	var cursor := 0
	for spec_value in spec:
		if cursor >= available.size():
			break
		var item := spec_value as Dictionary
		for _repeat in range(int(item["count"])):
			if cursor >= available.size():
				break
			var point := available[cursor]
			cursor += 1
			var config := _make_box_enemy(str(item["type"]), floor, floor_level, room)
			if config.is_empty():
				continue
			# `spawn_position` 是落点直通键，`_spawn_enemy_batch` 会取用并在实例化前摘掉；
			# `spawn_delay_sec` 是延迟键，非 0 的条目会被摘进 `_pending_delayed_spawns`。
			config["spawn_position"] = point
			# Monitor encounter: center the boss only; retain the authored escort placements.
			#
			# 「居中」以**设计源声明的首领中心**为准（`boss_reinforcement_plan.boss_spawn_local_m`
			# → `boss_spawn_position_world()`），而不是房间几何中心：多标高房（Boss房02 深井）
			# 的几何中心落在楼梯与平台之间，按几何中心投放会把首领放进楼梯底下。
			# 未声明增援计划的房（历史 Boss 房）走原路径 ⇒ 行为逐字不变。
			if str(config.get("boss_content_id", "")) == "boss_monitor002":
				if room.boss_reinforcement_plan.is_empty():
					config["spawn_position"] = Vector3(
						room.global_position.x, point.y, room.global_position.z
					)
				else:
					var boss_center := room.boss_spawn_position_world()
					config["spawn_position"] = Vector3(boss_center.x, point.y, boss_center.z)
			config["spawn_delay_sec"] = float(item["delay_sec"])
			entries.append(config)


## 解析调用层：返回「每波 = 一组盒子实例下标」。空 = 本房没摆盒子（由调用方决定语义）。
## `encounter.stages` 缺省时全部实例并进一波（口径与设计 §3.3 一致）。
func _resolve_encounter_stages(encounter: Dictionary, placement_count: int) -> Array:
	if placement_count <= 0:
		return []
	var raw: Variant = encounter.get("stages", [])
	if raw is Array and not (raw as Array).is_empty():
		var stages: Array = []
		for stage_value in (raw as Array):
			if not (stage_value is Dictionary):
				continue
			var boxes: Array = []
			for index_value in ((stage_value as Dictionary).get("boxes", []) as Array):
				var index := int(index_value)
				# 越界下标在静态层已被拦；此处再兜一层是「绝不静默替换成别的实例」，
				# 直接丢弃并让该波少一个盒子 —— 表现是少出怪，不是出到别的盒子上去。
				if index >= 0 and index < placement_count:
					boxes.append(index)
			stages.append(boxes)
		return stages
	var all: Array = []
	for index in range(placement_count):
		all.append(index)
	return [all]


## 取一个盒子实例并预解析成运行时结构（盒心/尺寸/姿态/额外延迟）。
## 非法引用（box 空、未登记、文件坏）返回 {}，由调用方跳过 —— 不静默替换成别的盒子。
func _box_placement_at(placements: Array, index: int) -> Dictionary:
	if index < 0 or index >= placements.size():
		return {}
	var raw: Variant = placements[index]
	if not (raw is Dictionary):
		return {}
	var placement := (raw as Dictionary).duplicate(true)
	var box_id := str(placement.get("box", ""))
	if box_id.is_empty() or not SpawnBoxCatalog.has_id(box_id):
		return {}
	var box := SpawnBoxCatalog.load_box(box_id)
	if box.is_empty():
		return {}
	var size := box.get("size_m", Vector2.ZERO) as Vector2
	var raw_size: Variant = placement.get("size_m", null)
	if raw_size is Array and (raw_size as Array).size() >= 2:
		size = Vector2(float((raw_size as Array)[0]), float((raw_size as Array)[1]))
	placement["box"] = box_id
	placement["box_center"] = _placement_vec2(placement.get("center_m", []))
	placement["box_size"] = size
	placement["box_rotation"] = float(placement.get("rotation_deg", 0.0))
	placement["box_delay"] = float(placement.get("delay_sec", 0.0))
	# 逐实例出怪增量：数据键为 `count_bonus` / `count_multiplier`（设计 §3.2），
	# 运行时统一挂在 `box_*` 上供 `_collect_box_stage_entries` 取用 —— 一处归一，
	# 避免数据层与运行层各叫一个名字。缺省 0 / 1 = 维持盒子资产原始数量。
	placement["box_count_bonus"] = int(placement.get("count_bonus", 0))
	placement["box_count_multiplier"] = maxi(
		1, int(placement.get("count_multiplier", 1))
	)
	return placement


## 盒子数量区间抽签（含 `count` 写死为正整数的情况，此时 min == max）。
func _roll_box_count(spawn: Dictionary, rng: RandomNumberGenerator) -> int:
	var minimum := int(spawn.get("count_min", 0))
	var maximum := int(spawn.get("count_max", minimum))
	if maximum < minimum:
		maximum = minimum
	if maximum <= 0:
		return 0
	return rng.randi_range(minimum, maximum)


## 按**点名怪种**生成一只敌人。普通怪直取 `MonsterInjector.generate_box_enemy`，
## elite / boss 走各自装配端（身份指派），未知 type 返回 {}。
func _make_box_enemy(
	type_id: String,
	floor: int,
	floor_level: int,
	room: DungeonRoom3D,
	elite_encounter_id: String = ""
) -> Dictionary:
	if _monster_injector == null:
		return {}
	var encounter_id := elite_encounter_id if not elite_encounter_id.is_empty() else _elite_encounter_id(room)
	return _monster_injector.generate_box_enemy(type_id, floor, floor_level, {
		"floor": floor,
		"floor_level": floor_level,
		"floor_number": _elite_floor_number(room),
		"encounter_id": encounter_id,
		"seed": run_seed,
		"boss_content_id": str(room.get_meta("boss_content_id", "")),
	})


func _placement_vec2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO


## —— 延迟出怪（盒子 `spawns[].delay_sec`）——
## 摘出来的怪记进 `_pending_delayed_spawns` 并挂一枚定时器；期间计入「待生成」，
## 本波不会被判清（见 `_pending_delayed_spawn_count` 并入 `_reserved_spawn_count`），
## 到点后回 `_spawn_enemy_batch` 实到。这样「延迟几秒再出怪」与既有
## 「全灭才推进」的波次语义相容，不需要另造一套调度。
func _queue_delayed_spawn(
	room: DungeonRoom3D, config: Dictionary, position: Vector3, delay_sec: float
) -> void:
	var payload := config.duplicate(true)
	payload.erase("spawn_delay_sec")
	_delayed_spawn_serial += 1
	var serial := _delayed_spawn_serial
	if not _pending_delayed_spawns.has(room.room_id):
		_pending_delayed_spawns[room.room_id] = []
	(_pending_delayed_spawns[room.room_id] as Array).append({
		"serial": serial,
		"config": payload,
		"position": position,
	})
	get_tree().create_timer(maxf(0.05, delay_sec), false).timeout.connect(
		_on_delayed_spawn_timeout.bind(room.room_id, serial)
	)


func _on_delayed_spawn_timeout(room_id: String, serial: int) -> void:
	var entries := _pending_delayed_spawns.get(room_id, []) as Array
	var found := -1
	for index in entries.size():
		if int((entries[index] as Dictionary).get("serial", -1)) == serial:
			found = index
			break
	# 找不到 = 本条已被撤销（房间换代/存档重载）。直接返回，不重试、不补发。
	if found < 0:
		return
	var entry := entries[found] as Dictionary
	entries.remove_at(found)
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	# 只认「确实还没到的」：房间不在了、或在途期间已被判无落点，就丢弃这一条。
	# 丢弃而不保留，是为了不让待生成计数永远悬着（那是软锁，不是延迟）。
	if (
		_completed
		or not is_instance_valid(room)
		or not room.is_streamed()
		or _room_spawn_blocked.has(room_id)
	):
		# The timer callback has already removed the entry. The reservation was
		# counted when queued, so release that count even when the room vanished
		# before the delayed spawn became eligible.
		_alive_by_room[room_id] = maxi(0, int(_alive_by_room.get(room_id, 0)) - 1)
		if room_id == _current_room_id:
			_update_wave_hud(room_id)
		return
	var configs: Array[Dictionary] = []
	configs.append(entry.get("config", {}) as Dictionary)
	var positions: Array = [entry.get("position", Vector3.INF) as Vector3]
	# additive=true：**加**在本房存活账之上，不覆盖（首批已记账）。
	# count_reserved=true：本条在 `_queue_delayed_spawn` 那一刻就已经进了存活账
	# （见 `_spawn_enemy_batch` 尾部口径注释），到点实到时**不许再加**，
	# 否则每只延迟怪都会留下一个永远清不掉的幽灵计数。
	_spawn_enemy_batch(room, configs, true, true, positions)


func _pending_delayed_spawn_count(room_id: String) -> int:
	return (_pending_delayed_spawns.get(room_id, []) as Array).size()


## 落点解析优先级：**显式 positions 数组** > 配置内嵌 `spawn_position`（触发盒落点）
## > 房间级贪心 `spawn_point_for_index`。三者互斥地只走一条，绝不混算。
func _resolve_spawn_position(
	room: DungeonRoom3D, config: Dictionary, index: int, positions: Array
) -> Vector3:
	if index < positions.size():
		return positions[index] as Vector3
	var embedded: Variant = config.get("spawn_position", null)
	if embedded is Vector3:
		return embedded as Vector3
	return room.spawn_point_for_index(index)


## ==================== 编成外增援（远征） ====================
##
## 业主口径 2026-10-18：「可以加怪，但是不要影响卡片价格和本身逻辑」。
##
## **不能加进关卡编成**：门后报价基准 `B_k` 直接由 `spawn_placements` /
## `encounter.stages` 的编成收益算出（`FateEconomyService.configure_from_runtime`）。
## 往编成里加 25% 的怪，参考收益涨 25%、卡价也涨 25%，玩家买到的张数一张不多
## （整条主路模拟：x1.25 → 10 张，x1.5 → 10 张，与不加怪完全相同）。
##
## 所以这里在**编成之外**追加一波：它在 `_commit_room_waves` 之后才进队列，
## 关卡计划里没有它 ⇒ 参考收益、冻结报价、抽牌规则全部一个字都不变；玩家实际
## 多杀一批怪、多拿金币（走同一条击杀记账通道），同样三张卡于是更容易买得起。
##
## 比例按**该房第一波的怪数**算，不按金币算 —— 收益表以后改了也不用重调。
const EXPEDITION_SURPLUS_RATIO := 0.25
const EXPEDITION_SURPLUS_MIN := 1
const EXPEDITION_SURPLUS_MAX := 8
## 指定房固定总量（业主 2026-10-19：「room1改成15只 room2改成12只」）。
## 口径是**该房第一波的总怪数**（含延迟在途预约），即玩家实际要清掉的只数。
## 写法仍是「编成外补齐」：第一波先按设计源刷出来，再把差额补进同一波 ⇒
## 卡价与抽牌完全看不到这些怪（见上方说明）。
const EXPEDITION_ROOM_ENEMY_TOTALS := {
	"room_01": 15,
	"room_02": 12,
}
## 只给**有战斗的内容房**加。Boss 战不该被增援放大难度；交通房（撤离 / 安全屋 /
## 楼梯厅 / 起点）没有战斗编成，也就没有金币可加。
const EXPEDITION_SURPLUS_EXCLUDED_ROOM_TYPES := [
	"BOSS", "EXTRACTION", "SAFE_ROOM", "STAIR_LOBBY", "START",
]
## 增援开关。**生产恒为 true**；只为「只测波次记账 / 时序」的老专项提供隔离手段，
## 免得它们的「实体 1 + 在途 1」这类精确计数被多出来的小怪打红 —— 那些用例测的是
## 记账口径，不是怪量。增援本身由 `verify_expedition_fate_surplus` 独立验证。
var expedition_surplus_enabled := true


## 该房应该补多少只怪。返回 0 = 不补。
##
## 已指定总量的房按「目标 − 现有」算；其余战斗房沿用 25% 比例。
## 入参是该房**当前存活账**（= 已实到 + 延迟在途预约），所以差额是精确的 ——
## 补完之后 `_alive_by_room` 恰好等于目标值，不受延迟出怪影响。
func _expedition_surplus_deficit(room: DungeonRoom3D, alive: int) -> int:
	if not expedition_surplus_enabled:
		return 0
	if not get_runtime_map_id().begins_with("expedition"):
		return 0
	if room == null or alive <= 0:
		return 0
	# 「只认盒子」的关卡**不做编成外补齐**（2026-10-29）。
	#
	# 补齐的本意是「设计源只写了大致规模时，按比例多塞几只让房间别太空」。
	# 但 `spawn_boxes_only` 层恰恰相反：那一层的编成是**逐房手作的精确敌群**
	# （远征03 照《挺进地牢》第一层摆的族群搭配），按比例加怪会：
	#   ① 打破精确编成 —— 每房多出 30% 的怪，难度曲线失控；
	#   ② 补出来的是 `MonsterInjector` 的原生怪（melee_chaser 等），
	#      于是「全 egt_* 的复刻房」里混进原生僵尸，复刻目标当场失效。
	# 实测：hub_01 编成 7 只，被补齐成 9 只（多出 2 只 melee_chaser）。
	#
	# 判据用 `spawn_boxes_only` 而不是关卡 ID —— 与其余字段一致：
	# 任何关卡写这一层都同样生效，不写就一个字节都不变。
	if room.spawn_boxes_only:
		return 0
	if str(room.room_type) in EXPEDITION_SURPLUS_EXCLUDED_ROOM_TYPES:
		return 0
	var target := alive + clampi(
		int(round(float(alive) * EXPEDITION_SURPLUS_RATIO)),
		EXPEDITION_SURPLUS_MIN,
		EXPEDITION_SURPLUS_MAX
	)
	if EXPEDITION_ROOM_ENEMY_TOTALS.has(room.room_id):
		target = int(EXPEDITION_ROOM_ENEMY_TOTALS[room.room_id])
	return maxi(0, target - alive)


## 把差额补进**当前这一波**（additive=true，不新增波次）。
## 不新增波次 ⇒ 清房时机、波次 HUD、木板血量与撤离进度的时间轴全部不变。
## 返回实际补上的只数。
func _apply_expedition_surplus(room: DungeonRoom3D, alive: int) -> int:
	var deficit := _expedition_surplus_deficit(room, alive)
	if deficit <= 0:
		return 0
	# 随机流隔离：`MonsterInjector` 的 `_rng` / `_strong_rng` 是**全关卡共享的有状态流**，
	# 直接借用会让后续房间的编成跟着变，且同种子重开不再逐字复现。
	# 这里按 `run_seed + room_id` 派生一个确定状态生成增援，生成完原样还原 ⇒
	# 增援自身可复现（同房同种子必然同一批怪），且对其它房间零影响。
	var plain_rng: RandomNumberGenerator = _monster_injector.get("_rng")
	var strong_rng: RandomNumberGenerator = _monster_injector.get("_strong_rng")
	var saved_plain := 0
	var saved_strong := 0
	if plain_rng != null:
		saved_plain = plain_rng.state
		plain_rng.state = hash("%d|%s|fate_surplus" % [run_seed, room.room_id])
	if strong_rng != null:
		saved_strong = strong_rng.state
		strong_rng.state = hash("%d|%s|fate_surplus_strong" % [run_seed, room.room_id])
	var extra := _monster_injector.generate_enemies({
		"type": "ambush",
		"count": deficit,
		"floor": maxi(1, visual_theme.difficulty_rank if visual_theme != null else 1),
		"floor_level": 0,
	})
	if plain_rng != null:
		plain_rng.state = saved_plain
	if strong_rng != null:
		strong_rng.state = saved_strong
	if extra.is_empty():
		return 0
	if _spawn_enemy_batch(room, extra, true) < 0:
		return 0
	return extra.size()


## 把已分好的波次提交为本房的刷怪队列，并立刻刷出第一波。
## `waves` 每项是一波的敌人配置数组（公式路径与设计源路径共用此处）。
## 返回是否成功出怪；任一步失败都会把房间解锁，防软锁。
func _commit_room_waves(room: DungeonRoom3D, waves: Array) -> bool:
	if waves.is_empty():
		return false
	if not _room_enemy_hp_multipliers.has(room.room_id):
		var extra: Array[Dictionary] = []
		if _next_room_enemy_count > 0:
			extra.assign(_monster_injector.generate_enemies({
				"type": "ambush", "count": _next_room_enemy_count,
				"floor": maxi(1, visual_theme.difficulty_rank), "floor_level": 0,
			}))
		extra.append_array(_next_room_elite_configs)
		if not extra.is_empty():
			(waves[0] as Array).append_array(extra)
		_next_room_enemy_count = 0
		_next_room_elite_configs.clear()
		_note_room_enemy_modifiers(room)
	var wave_count := waves.size()
	var first_wave: Array[Dictionary] = waves.pop_front() as Array[Dictionary]
	_cancel_room_wave_intermission(room.room_id)
	_room_wave_queues[room.room_id] = waves
	_room_wave_numbers[room.room_id] = 1
	_room_wave_totals[room.room_id] = wave_count
	_enemy_nodes_by_room[room.room_id] = []
	var spawned := _spawn_enemy_batch(room, first_wave, false)
	if spawned < 0:
		waves.push_front(first_wave)
		_room_wave_numbers[room.room_id] = 0
		_alive_by_room[room.room_id] = 0
		_update_wave_hud(room.room_id)
		return false
	if spawned <= 0:
		push_error("Hostile room %s failed to instantiate its first wave; unlocking room" % room.room_id)
		_room_wave_queues[room.room_id] = []
		_mark_room_cleared(room, true)
		status_label.text = "敌群载入失败，房间已安全解锁"
		return false
	# 编成外补齐：第一波先按设计源刷出来，再按「目标 − 现有存活账」补差额进同一波。
	# ① 不写回关卡计划 ⇒ 参考收益 / 冻结报价 / 抽牌规则一个字不变（卡价不动）；
	# ② 不新增波次 ⇒ 清房时机、波次 HUD、木板血量与撤离进度的时间轴全部不变。
	# 放在 `_spawn_enemy_batch` 之后而不是之前，是因为差额要按**真实存活账**算：
	# 盒子倍率、延迟在途预约都会影响实际只数，只有刷完才知道差多少。
	_apply_expedition_surplus(room, int(_alive_by_room.get(room.room_id, 0)))
	status_label.text = "区域警戒：波次 1/%d · %d 个敌对信号" % [
		wave_count, int(_alive_by_room.get(room.room_id, spawned)),
	]
	_update_wave_hud(room.room_id)
	return true


func _elite_encounter_id(room: DungeonRoom3D) -> String:
	var run_id := str(build_runtime_save_snapshot().get("run_id", "run:%d" % run_seed))
	return "%s:%s:elite" % [run_id, room.room_id]


func _elite_floor_number(room: DungeonRoom3D) -> int:
	return maxi(1, int(room.get_meta("floor_number", visual_theme.difficulty_rank)))


func _prepare_revealed_hostile_room(room: DungeonRoom3D) -> bool:
	if (
		room == null
		or room.room_type not in HOSTILE_ROOM_TYPES
		or _spawned_rooms.has(room.room_id)
	):
		return false
	# 房门开启后目标房间已经进入可见流送状态；首波必须在这一刻存在，
	# 不能等角色靠近触发 RoomArea 后才突然生成。AI 是否运行仍由当前房控制。
	_spawned_rooms[room.room_id] = true
	room.cleared = false
	return _spawn_room_enemies(room)


## 起始补给（地面那把关卡起点枪）只发给**真正的关卡起点房**。
##
## ⛔ 塔楼 100F 天台是塔楼里唯一 `room_type == "START"` 的房间，但它**不再**吃这条补给：
## 2026-09-22/23 起「全新存档开场」改落 98F 主人办公室，开场那把枪由剧本
## `nar_tower_opening_01_wake` 的 `scene.spawn_item` 刷 `weapon_starter_rifle`
## （契约见 `TowerDescent3D._clear_new_game_opening_loadout()`）。
## 天台这把霰弹枪是**旧新手教程的遗留**，且它在**每一局**首次进入天台时都会重刷一次、
## 写进存档 `segment_runtime_state[].ground_items` 一直躺在天台地面上 ——
## 从 99F 归航基地抬头看天台地面，就是「一把悬在半空、捡不到也说不清的枪」。
##
## 判据用 `size_class`：`"rooftop"` 只由 `TowerDescent3D._build_records()` 的天台记录声明
## （`_append_tower_record("start", "START", "rooftop", ...)`），其余关卡 ——
## `Dungeon3D` 默认地图（起点房 size = `medium`）与 `scenes/levels3d/*` ——
## 行为逐字不变，`verify_full_3d_game_flow` 的「拾取初始霰弹枪」用例仍然成立。
func _room_grants_starter_supply(room: DungeonRoom3D) -> bool:
	if room == null or room.room_type != "START":
		return false
	return room.size_class != "rooftop"


func _spawn_starter_weapon_pickup(room: DungeonRoom3D) -> void:
	if room == null or _starter_cache_opened:
		return
	_starter_cache_opened = true
	var starter := ItemRegistry.get_instance().get_item("weapon_shotgun")
	if starter.is_empty():
		return
	_spawn_loot_items(room, [starter], room.global_position + Vector3(2.1, 0.08, -1.4))
	status_label.text = "起始补给：拾取霰弹枪后按 I 打开背包并点击装备 · 墙边 E 可开中央灯"


func _spawn_enemy_batch(room: DungeonRoom3D, enemy_configs: Array[Dictionary], additive: bool, count_reserved := false, positions: Array = []) -> int:
	if room == null or enemy_configs.is_empty():
		return 0
	if _room_spawn_blocked.has(room.room_id):
		return -1
	# 延迟出怪（触发盒 `spawns[].delay_sec`）：整批预检**之前**先摘出来挂定时器。
	# 摘走的条目**不参与本次实例化**，也不计入本批实到数；它们由待生成账兜着，
	# 本波因此不会被提前判清。`positions` 是并行数组，摘的时候必须同步撇掉。
	var queued_delayed := 0
	if not count_reserved:
		var kept_configs: Array[Dictionary] = []
		var kept_positions: Array = []
		for index in enemy_configs.size():
			var candidate := enemy_configs[index]
			var delay := float(candidate.get("spawn_delay_sec", 0.0))
			if delay > 0.0:
				_queue_delayed_spawn(
					room, candidate, _resolve_spawn_position(room, candidate, index, positions), delay
				)
				queued_delayed += 1
				continue
			kept_configs.append(candidate)
			if index < positions.size():
				kept_positions.append(positions[index])
		enemy_configs = kept_configs
		positions = kept_positions
		# 整批都是延迟：本批实到 0 只，交由既有空批分支处理（见 _spawn_box_waves 的
		# 「每波至少一条立刻出怪」不变量 —— 触发盒路径不会走到这里）。
		if enemy_configs.is_empty():
			return -1
	# 整批预检先于实例化，任何非法点都不能形成半波或写入实体transform。
	var spawn_positions: Array[Vector3] = []
	for index in enemy_configs.size():
		var point := _resolve_spawn_position(room, enemy_configs[index], index, positions)
		if not point.is_finite():
			_room_spawn_blocked[room.room_id] = true
			_cancel_room_wave_intermission(room.room_id)
			_update_wave_hud(room.room_id)
			if room.room_id == _current_room_id:
				status_label.text = "刷怪暂停：无合法落点，波次保留"
			return -1
		spawn_positions.append(point)
	_cancel_room_wave_intermission(room.room_id)
	_update_wave_hud(room.room_id)
	if not _enemy_nodes_by_room.has(room.room_id):
		_enemy_nodes_by_room[room.room_id] = []
	var spawned_count := 0
	for index in range(enemy_configs.size()):
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		if enemy == null:
			continue
		enemy.room_id = room.room_id
		$ActiveEnemies.add_child(enemy)
		var spawn_data := enemy_configs[index].duplicate(true)
		# 房间级 AI 覆盖（`encounter.monster_ai`）：与关卡级同键合并，**房间级优先**。
		# 两层都空 ⇒ 不写这个键 ⇒ `Enemy3D` 全部回退全局常量（塔楼等未配置关卡逐字不变）。
		var room_ai: Dictionary = room.encounter.get("monster_ai", {}) as Dictionary
		if not room_ai.is_empty():
			var merged_ai: Dictionary = (
				spawn_data.get("monster_ai", {}) as Dictionary
			).duplicate(true)
			merged_ai.merge(room_ai, true)
			spawn_data["monster_ai"] = merged_ai
		var launch_target: Variant = spawn_data.get("spawn_launch_target", null)
		var launch_speed := float(spawn_data.get("spawn_launch_speed_mps", 0.0))
		var launch_duration := float(spawn_data.get("spawn_launch_duration_sec", 0.0))
		# 落点 / 延迟 / 出生抛射键是**本系统的私有通道**，不是敌人数据的一部分：
		# 摘掉再喂给 `configure_from_enemy_data`，免得它们漏进存档或敌人快照。
		spawn_data.erase("spawn_position")
		spawn_data.erase("spawn_delay_sec")
		spawn_data.erase("spawn_launch_target")
		spawn_data.erase("spawn_launch_speed_mps")
		spawn_data.erase("spawn_launch_duration_sec")
		if not spawn_data.has("spawn_index"):
			spawn_data["spawn_index"] = index
		if not spawn_data.has("persistent_id"):
			spawn_data["persistent_id"] = "%s:wave_%d:%d" % [
				room.room_id,
				int(_room_wave_numbers.get(room.room_id, 1)),
				index,
			]
		enemy.configure_from_enemy_data(spawn_data)
		enemy.set_meta("fate_kill_currency", int(spawn_data.get("fate_kill_currency", 0)))
		enemy.state_changed.connect(_on_fate_enemy_state_changed.bind(enemy))
		# 剧情生成的怪打标记，剧情撤怪只认自己生成的那些。
		if bool(spawn_data.get("narrative_spawned", false)):
			enemy.set_meta("narrative_spawned", true)
		var hp_multiplier := float(_room_enemy_hp_multipliers.get(room.room_id, 1.0))
		if not is_equal_approx(hp_multiplier, 1.0):
			enemy.apply_health_multiplier(hp_multiplier)
		var damage_multiplier := float(_room_enemy_damage_multipliers.get(room.room_id, 1.0))
		if not is_equal_approx(damage_multiplier, 1.0):
			enemy.contact_damage = maxi(1, int(round(float(enemy.contact_damage) * damage_multiplier)))
		enemy.global_position = spawn_positions[index]
		# 房间矩形注入（2026-10-30）。瞬移/游荡的「别出房」判据必须用**矩形**，
		# 不能用「离出生点不超过 R」的圆形近似 —— 那个近似的 R 会随当前位置自增，
		# 于是怪能一路飘出房间（实测 25×25 房 84% 的瞬移落点在房外、最远 99.84m）。
		# 出房后玩家子弹被墙挡、它的子弹也被墙挡，就是「瞬移后双向都打不中」。
		# 这里只注入几何，不改任何 AI 决策：没声明 `blink`/`wander` 的怪一个字节都不变。
		var room_half := room.get_dimensions() * 0.5
		enemy.set_room_bounds(room.global_transform, room_half)
		if launch_target is Vector3 and launch_speed > 0.0 and launch_duration > 0.0:
			enemy.apply_melee_knockback(
				(launch_target as Vector3) - enemy.global_position,
				launch_speed,
				launch_duration
			)
		if str(spawn_data.get("boss_content_id", "")) == "boss_monitor002":
			# Characters face local -Z; PI points toward world south (+Z).
			enemy.global_rotation.y = PI
		enemy.killed.connect(_on_enemy_killed)
		enemy.escaped.connect(_on_enemy_escaped)
		enemy.summon_requested.connect(_on_summon_requested)
		enemy.split_requested.connect(_on_split_requested)
		enemy.boss_phase_changed.connect(_on_boss_phase_changed)
		enemy.boss_activation_completed.connect(_on_boss_activation_completed)
		enemy.health_changed.connect(_on_enemy_health_changed)
		(_enemy_nodes_by_room[room.room_id] as Array).append(enemy)
		spawned_count += 1
		var room_visible := room.is_streamed()
		enemy.set_runtime_active(room.room_id == _current_room_id, room_visible)
		if enemy.enemy_kind == "boss":
			_show_boss_hud(enemy)
	# 🔴 存活账口径必须**统一**：`_alive_by_room` = 已实例化敌人 ＋ **在途预约**
	#    （召唤预约 `_reserved_room_spawns` ＋ 延迟出怪 `_pending_delayed_spawns`）。
	#    证据：`_reserve_room_spawn` 在**预约时**就 `+= configs.size()`，实到时走
	#    `count_reserved=true` 不再加；`_repair_hostile_room_progress` /
	#    `_restore_room_runtime_state` 也都按 `已实例化 + _reserved_spawn_count()` 重算。
	#    延迟出怪原本两头都不占：`_queue_delayed_spawn` 时**不加**（存活账里没有它），
	#    到点实到时却按 `additive=true` **加一次** ⇒ 净多 1 个「幽灵计数」：
	#    延迟怪被杀掉后 `_alive_by_room` 永远回不到 0，
	#    `_can_advance_room_wave` 的 `alive == 0` 判据恒不成立 ⇒ 下一波永不自动来，
	#    必须靠玩家按门触发 `_repair_hostile_room_progress`（用真实实体重算）才推进。
	#    这里把「摘出去挂定时器的那几只」当场记进存活账，到点补位时账不再动。
	if not count_reserved:
		var base_alive := int(_alive_by_room.get(room.room_id, 0)) if additive else 0
		_alive_by_room[room.room_id] = base_alive + spawned_count + queued_delayed
	elif spawned_count < enemy_configs.size():
		_alive_by_room[room.room_id] = maxi(
			0,
			int(_alive_by_room.get(room.room_id, 0))
			- (enemy_configs.size() - spawned_count)
		)
	return spawned_count


## —— 剧情系统正门（见 docs/v0.1/08_技术施工_剧情触发.md §5.2 / §5.4）——
## 敌人生成要接 6 个信号、上 $ActiveEnemies、写存活账 —— 那是本系统的私事，
## 剧情只许走这三个正门，不许自己 instantiate。


## 玩家头顶气泡的稳定入口。台词内容由剧情给，气泡挂点与挂高由本系统决定。
func narrative_player_bark() -> CharacterBark3D:
	return _ensure_player_bark()


## 剧情刷怪：在指定站位生成 count 只 kind。
## 单只数值取自 MonsterInjector.BASE_ENEMY_TYPES（项目唯一真源），
## 不在这里另写一套数值，避免剧情怪与玩法怪两套口径。
## `origin` = 队列中心，`axis` = 展开轴（单位向量），沿轴 `spread` 米一字排开。
## 返回实际生成数（0 = 房间不存在或生成失败）。
func narrative_spawn_enemies(
	room_id: String, kind: String, count: int, origin: Vector3,
	axis: Vector3 = Vector3.RIGHT, spread: float = 1.6,
	stagger: Vector3 = Vector3.ZERO, options: Dictionary = {}
) -> int:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null or count <= 0:
		return 0
	var spawn_key := str(options.get("spawn_key", ""))
	if not spawn_key.is_empty() and _narrative_spawned_keys.has(spawn_key):
		return count # 已刷/已死均视作已完成，镜头仍可按该锚点复演。
	var base_type: Dictionary = MonsterInjector.BASE_ENEMY_TYPES.get(kind, {})
	if base_type.is_empty():
		push_warning("[Dungeon3D] 剧情刷怪：未知怪物 kind『%s』。" % kind)
		return 0
	var presentation: Dictionary = MonsterInjector.ENEMY_PRESENTATION.get(kind, {})
	var flat_axis := Vector3(axis.x, 0.0, axis.z)
	flat_axis = flat_axis.normalized() if flat_axis.length_squared() > 0.000001 else Vector3.RIGHT
	var row := float(count - 1) * 0.5
	var configs: Array[Dictionary] = []
	var positions: Array = []
	for index in range(count):
		configs.append({
			"enemy_type": kind,
			"name": str(base_type.get("name", kind)),
			"emoji": str(presentation.get("emoji", "\u5c38")),
			"hp": int(base_type.get("hp_base", 20)),
			"max_hp": int(base_type.get("hp_base", 20)),
			"damage": int(base_type.get("damage_base", 5)),
			"speed": float(base_type.get("speed", 60.0)),
			"narrative_spawned": true,
			"narrative_stationary": bool(options.get("stationary", false)),
			"narrative_placement": str(options.get("placement", "")),
			"persistent_id": "%s:%d" % [spawn_key if not spawn_key.is_empty() else "narrative:%s:%d" % [room_id, (_enemy_nodes_by_room.get(room_id, []) as Array).size()], index],
		})
		# 交错：相邻两只沿垂直方向往两边让开一点，别站成一条笔直的队。
		var lateral_stagger := stagger * (0.5 if index % 2 == 1 else -0.5)
		positions.append(
			origin + flat_axis * ((float(index) - row) * spread) + lateral_stagger
		)
	if str(options.get("placement", "")) == "room_floor":
		var requested: Array[Vector3] = []
		requested.assign(positions)
		var occupied: Array[Vector3] = []
		for enemy in _enemy_nodes_by_room.get(room_id, []) as Array:
			if is_instance_valid(enemy) and enemy is Enemy3D and enemy.ai_state != "dead":
				occupied.append(enemy.global_position)
		var safe := room.resolve_narrative_floor_positions(requested, occupied, maxf(0.0, float(options.get("max_adjustment_m", 12.0))))
		if safe.size() != count:
			push_warning("[Dungeon3D] 剧情刷怪没有同层安全落点：%s / %s" % [room_id, spawn_key])
			return 0
		positions.assign(safe)
	# additive=true：剧情刷的怪**加**在房间原有敌人之上，不覆盖存活账。
	var before_nodes: Array = (_enemy_nodes_by_room.get(room_id, []) as Array).duplicate()
	var spawned := maxi(0, _spawn_enemy_batch(room, configs, true, false, positions))
	if spawned == count:
		if not spawn_key.is_empty():
			_narrative_spawned_keys[spawn_key] = true
		_capture_room_runtime_state(room_id)
		return spawned
	# 原子批次：失败不留半批，重试不会复制已成功的几只。
	for enemy in _enemy_nodes_by_room.get(room_id, []) as Array:
		if enemy not in before_nodes and is_instance_valid(enemy):
			enemy.queue_free()
	_enemy_nodes_by_room[room_id] = before_nodes
	_alive_by_room[room_id] = maxi(0, int(_alive_by_room.get(room_id, 0)) - spawned)
	return 0


## 镜头目标取实际生成的批次中心，避免安全落点调整后镜头仍对着旧坐标。
func narrative_spawn_origin(spawn_key: String, fallback: Vector3) -> Vector3:
	if spawn_key.is_empty():
		return fallback
	var total := Vector3.ZERO
	var count := 0
	for nodes in _enemy_nodes_by_room.values():
		for enemy in nodes as Array:
			if is_instance_valid(enemy) and enemy is Enemy3D and enemy.get_persistent_id().begins_with(spawn_key + ":"):
				total += enemy.global_position
				count += 1
	return total / float(count) if count > 0 else fallback


## 剧情撤怪：清掉本房**剧情生成**的怪。按 `narrative_spawned` 元数据认领，
## 不会误伤玩法刷出来的敌人。
func narrative_despawn_enemies(room_id: String) -> int:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null:
		return 0
	var nodes: Array = _enemy_nodes_by_room.get(room_id, [])
	var removed := 0
	var kept: Array = []
	for enemy in nodes:
		if (
			enemy is Node
			and is_instance_valid(enemy)
			and bool(enemy.get_meta("narrative_spawned", false))
		):
			(enemy as Node).queue_free()
			removed += 1
		else:
			kept.append(enemy)
	_enemy_nodes_by_room[room_id] = kept
	_alive_by_room[room_id] = maxi(0, int(_alive_by_room.get(room_id, 0)) - removed)
	return removed


## 剧情固定物品奖励的稳定入口。解析归 RewardService，背包满出的余量仍按正式地面物发放。
func narrative_grant_item(item_id: String, count: int) -> Dictionary:
	if _reward_coordinator == null or _inventory == null or item_id.is_empty() or count <= 0:
		return {"success": false, "granted_count": 0, "deferred_count": count, "errors": ["INVALID_GRANT"]}
	var report := _reward_coordinator.resolve_fixed_item(
		item_id, count, "narrative:%s:%d" % [item_id, count], maxi(1, visual_theme.difficulty_rank)
	)
	if not bool(report.get("ok", false)):
		return {"success": false, "granted_count": 0, "deferred_count": count, "errors": report.get("errors", [])}
	var grants := report.get("grants", []) as Array
	if grants.is_empty():
		return {"success": false, "granted_count": 0, "deferred_count": count, "errors": ["EMPTY_GRANT"]}
	# 先校验整批再写背包；武器 count=N 在 RewardService 中是 N 条独立实例。
	for grant_value in grants:
		var grant := grant_value as Dictionary
		var item := grant.get("item", {}) as Dictionary
		if item.is_empty() or str(item.get("id", "")) != str(grant.get("item_id", "")):
			return {"success": false, "granted_count": 0, "deferred_count": count, "errors": ["INVALID_GRANT_ITEM"]}
	var granted_total := 0
	var deferred_total := 0
	for grant_value in grants:
		var grant := grant_value as Dictionary
		var item := (grant.get("item", {}) as Dictionary).duplicate(true)
		var requested := int(grant.get("count", 1))
		item["count"] = requested
		var added := _inventory.add_item(item, requested)
		granted_total += added
		var overflow := maxi(0, requested - added)
		if overflow > 0:
			var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
			if room == null or player == null:
				return {"success": false, "granted_count": granted_total, "deferred_count": deferred_total + overflow, "errors": ["NO_GROUND_SINK"]}
			item["count"] = overflow
			if _spawn_loot_items(room, [item], player.global_position + player.aim_direction * 1.2) != 1:
				return {"success": false, "granted_count": granted_total, "deferred_count": deferred_total + overflow, "errors": ["GROUND_SINK_REJECTED"]}
			deferred_total += overflow
	_refresh_loot_label()
	return {"success": true, "granted_count": granted_total, "deferred_count": deferred_total, "errors": []}


## 剧情把物品**放到地面**（不是进包 —— 进包走 `grant.item`）。
## 为什么要有这条：地面道具的归属、贴地校位、可拾取连接都是本系统的私事
## （`_spawn_loot_items` + `_find_supported_spawn_position`），剧情不该自己 instantiate。
## `item_id` 的解析复用奖励服务（唯一真源），不在这里另写一张物品表。
## `spread=false`（默认）时**精确**落在 origin —— 剧本要"转身对着它说"就必须精确。
func narrative_spawn_item(
	room_id: String, item_id: String, count: int, origin: Vector3, spread := false,
	spawn_key: String = "", auto_equip := false
) -> int:
	if not spawn_key.is_empty() and _narrative_spawned_keys.has(spawn_key):
		return 1
	if _reward_coordinator == null or item_id.is_empty() or count <= 0:
		return 0
	var report := _reward_coordinator.resolve_fixed_item(
		item_id, count, "narrative_drop:%s:%d" % [item_id, count],
		maxi(1, visual_theme.difficulty_rank)
	)
	if not bool(report.get("ok", false)):
		push_warning(
			"[Dungeon3D] 剧情刷物品：『%s』解析失败（%s）。" % [item_id, str(report.get("errors", []))]
		)
		return 0
	var delivery := REWARD_SINK_SCRIPT.apply_ground(
		report.get("grants", []),
		func(items: Array) -> int:
			if auto_equip:
				for item_value in items:
					if item_value is Dictionary and str((item_value as Dictionary).get("type", "")) == "weapon":
						(item_value as Dictionary)["narrative_auto_equip"] = true
			return narrative_spawn_loot(room_id, items, origin, spread)
	)
	var spawned := (delivery.get("granted", []) as Array).size()
	if spawned > 0:
		if not spawn_key.is_empty():
			_narrative_spawned_keys[spawn_key] = true
		_queue_runtime_autosave("narrative_ground_loot_spawned")
	return spawned


## 剧情把**现成的 item 字典**放到地面（不解析、不重造）。
## 给「把玩家手上那把原样丢下」这类用法：实例身份与已装改造必须保持。
func narrative_spawn_loot(
	room_id: String, items: Array, origin: Vector3, spread := false
) -> int:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null or items.is_empty():
		return 0
	return _spawn_loot_items(room, items, origin, 0.0, spread)


func _repair_room_progress(room: DungeonRoom3D) -> void:
	if room == null or room.cleared:
		return
	if room.room_type in HOSTILE_ROOM_TYPES:
		_repair_hostile_room_progress(room)
		return
	if room.room_type != "EVENT":
		return
	# 带战斗的事件房（自带触发盒的双职房 / 事件召唤的敌群）先把战斗修好再谈事件结算：
	# `_repair_hostile_room_progress` 在战斗没清完时自己早退，清完才 `_mark_room_cleared`，
	# 因此插在最前也不会误放行。纯事件房 `_event_combat_rooms` 为空 ⇒ 原路径逐字不变。
	if _event_combat_rooms.has(room.room_id):
		_repair_hostile_room_progress(room, true)
		return
	if not _resolved_event_rooms.has(room.room_id):
		_ensure_event_room_objective(room)
		return
	# 非战斗事件一经记录为已结算就不应继续锁门；这是热重载/旧存档兜底。
	_mark_room_cleared(room, true)


func _return_room_status(room: DungeonRoom3D) -> String:
	if room == null:
		return "返回已探索房间"
	if room.cleared:
		return "返回已探索房间 · 已肃清"
	if room.room_type == "EVENT":
		if _event_combat_rooms.has(room.room_id):
			return "返回事件房 · 异常敌群尚未肃清"
		return "返回事件房 · 前往紫色光柱，按 E 结算事件"
	return "返回已探索房间 · 战斗未结束"


func _ensure_event_room_objective(room: DungeonRoom3D) -> bool:
	if room == null or room.room_type != "EVENT":
		return false
	var station := room.ensure_required_service_station()
	if station != null:
		return true
	# 必做交互物实例化失败时，优先保住流程，绝不让一局永久卡死。
	push_error("Event room %s has no event station; unlocking room to prevent a soft lock" % room.room_id)
	_resolved_event_rooms[room.room_id] = true
	_mark_room_cleared(room, true)
	status_label.text = "事件终端载入失败，房间已安全解锁"
	return false


func _repair_hostile_room_progress(room: DungeonRoom3D, allow_event_combat := false) -> void:
	if (
		room == null
		or room.cleared
		or (room.room_type not in HOSTILE_ROOM_TYPES and not allow_event_combat)
	):
		return
	# DATA_ONLY 的空节点表是流送卸载，不是死亡；预约生成也属于本波存活账。
	if not room.is_streamed() or _room_spawn_blocked.has(room.room_id):
		return
	var live_count := _reserved_spawn_count(room.room_id)
	var live_references: Array = []
	for value in _enemy_nodes_by_room.get(room.room_id, []):
		if not is_instance_valid(value):
			continue
		var enemy := value as Enemy3D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		live_references.append(enemy)
		live_count += 1
	_enemy_nodes_by_room[room.room_id] = live_references
	_alive_by_room[room.room_id] = live_count
	if live_count > 0:
		_cancel_room_wave_intermission(room.room_id)
		_update_wave_hud(room.room_id)
		return
	var pending_waves := _room_wave_queues.get(room.room_id, []) as Array
	if not pending_waves.is_empty():
		# 到这里已确认本波全清；重进房/流送修复也必须走完整间歇。
		_schedule_room_wave_intermission(room.room_id)
		return
	if _room_wave_totals.has(room.room_id):
		# 已建立过波次的房间没有待发队列时，只能是终波已处理或失败兜底；
		# 不得重新调用 _spawn_room_enemies 形成无限刷怪。
		_mark_room_cleared(room, true)
		return
	# 尚未建立过波次的旧存档/事件战斗仍沿用原有修复入口。
	_spawn_room_enemies(room)


## 本房是否还压着未清完的战斗 —— 存活 / 在途预约 / 待发波 / 本波间歇，四者任一即算。
## 供「事件 + 战斗」双职房判定「结算事件能否直接放行」用（见 `_resolve_event_room`）。
func _room_has_pending_combat(room: DungeonRoom3D) -> bool:
	if room == null:
		return false
	if int(_alive_by_room.get(room.room_id, 0)) > 0:
		return true
	if _reserved_spawn_count(room.room_id) > 0:
		return true
	if not (_room_wave_queues.get(room.room_id, []) as Array).is_empty():
		return true
	return _wave_spawn_pending.has(room.room_id)


func _can_advance_room_wave(room_id: String) -> bool:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	return (
		is_inside_tree() and not _completed and _current_room_id == room_id
		and is_instance_valid(room) and room.is_streamed() and not room.cleared
		and not _room_spawn_blocked.has(room_id)
		and int(_alive_by_room.get(room_id, 0)) == 0
		and _reserved_spawn_count(room_id) == 0
		and (_enemy_nodes_by_room.get(room_id, []) as Array).is_empty()
	)


func _schedule_room_wave_intermission(room_id: String) -> void:
	if not _can_advance_room_wave(room_id):
		return
	var queue := _room_wave_queues.get(room_id, []) as Array
	if queue.is_empty() or _wave_spawn_pending.has(room_id):
		return
	var token := int(_room_wave_intermission_tokens.get(room_id, 0)) + 1
	_room_wave_intermission_tokens[room_id] = token
	_wave_spawn_pending[room_id] = token
	var wave_number := int(_room_wave_numbers.get(room_id, 1))
	var total := int(_room_wave_totals.get(room_id, 1))
	var intermission := maxf(
		0.0, float(_room_intermission_seconds.get(room_id, ROOM_WAVE_INTERMISSION_SECONDS))
	)
	status_label.text = "波次 %d/%d 已清空 · %.0f秒后生成下一整波" % [wave_number, total, intermission]
	_update_wave_hud(room_id, "间歇中 · %.0f秒后下一波" % intermission)
	get_tree().create_timer(intermission, false).timeout.connect(
		_on_room_wave_intermission_timeout.bind(room_id, token)
	)


func _cancel_room_wave_intermission(room_id: String) -> void:
	if room_id.is_empty():
		return
	_room_wave_intermission_tokens[room_id] = int(_room_wave_intermission_tokens.get(room_id, 0)) + 1
	_wave_spawn_pending.erase(room_id)


func _on_room_wave_intermission_timeout(room_id: String, token: int) -> void:
	if int(_room_wave_intermission_tokens.get(room_id, 0)) != token:
		return
	if int(_wave_spawn_pending.get(room_id, -1)) != token:
		return
	_spawn_next_room_wave(room_id, token)


func _update_wave_hud(room_id: String, suffix := "") -> void:
	if _hud_wave_label == null or room_id != _current_room_id:
		return
	if _room_spawn_blocked.has(room_id):
		_hud_wave_label.text = "波次 %d/%d · 无合法落点，刷怪暂停" % [int(_room_wave_numbers.get(room_id, 0)), int(_room_wave_totals.get(room_id, 0))]
		return
	if suffix.is_empty():
		var room := _room_by_id.get(room_id) as DungeonRoom3D
		if room != null and room.cleared:
			suffix = "房间肃清"
		elif _wave_spawn_pending.has(room_id):
			suffix = "间歇中 · 2秒后下一波"
	var current := int(_room_wave_numbers.get(room_id, 0))
	var total := int(_room_wave_totals.get(room_id, 0))
	if current <= 0 or total <= 0:
		_hud_wave_label.text = "波次 —"
		return
	_hud_wave_label.text = "波次 %d/%d" % [current, total]
	if not suffix.is_empty():
		_hud_wave_label.text += " · %s" % suffix


func _spawn_next_room_wave(room_id: String, token := -1) -> void:
	if token < 0 or int(_wave_spawn_pending.get(room_id, -1)) != token:
		return
	_cancel_room_wave_intermission(room_id)
	if not _can_advance_room_wave(room_id) or not _room_wave_queues.has(room_id):
		return
	var queue := _room_wave_queues[room_id] as Array
	if queue.is_empty():
		return
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	var batch: Array[Dictionary] = []
	batch.assign(queue[0])
	var previous_wave := int(_room_wave_numbers.get(room_id, 1))
	_room_wave_numbers[room_id] = previous_wave + 1
	var spawned := _spawn_enemy_batch(room, batch, false)
	if spawned < 0:
		_room_wave_numbers[room_id] = previous_wave
		_update_wave_hud(room_id)
		return
	queue.pop_front()
	if spawned <= 0:
		push_error("Hostile room %s failed to instantiate a later wave; unlocking room" % room_id)
		_room_wave_queues[room_id] = []
		_alive_by_room[room_id] = 0
		if room != null:
			_mark_room_cleared(room, true)
		status_label.text = "增援载入失败，房间已安全解锁"
		_update_wave_hud(room_id, "生成失败 · 房间已解锁")
		return
	status_label.text = "增援抵达：波次 %d/%d · %d 个敌对信号" % [
		int(_room_wave_numbers[room_id]), int(_room_wave_totals.get(room_id, 1)), spawned,
	]
	_update_wave_hud(room_id)
	if AudioManager != null:
		AudioManager.play_sfx("wave_start", -3.0)


func _record_index(room_id: String) -> int:
	var record := _find_record(room_id)
	return int(record.get("index", 0))


## 死亡分裂（远征03 布洛布三阶）。子代**类型由死者指定**，因此不能用 `_on_summon_requested`
## （那条只产出 `minion` 通用小怪，表达不了「Blobulon 必裂成 Blobuloid」）。
##
## 仍然复用 `_reserve_room_spawn()` 这条既有旁路 —— 它是设计文档 §0.4 登记的
## 「预约刷怪」，会正确计入 `_reserved_spawn_count`，于是**子代没出完之前房间不会被判清**。
## 这一点必须靠它、不能直接实例化：否则玩家会看到门先开、小怪后冒出来。
func _on_split_requested(source: Enemy3D, child_kind: String, count: int) -> void:
	if _completed or not is_instance_valid(source):
		return
	var room_id := source.room_id
	# 容量保护与召唤同源：本房同时存活上限 8，分裂子代也不能突破。
	var live_count := 0
	for value in _enemy_nodes_by_room.get(room_id, []):
		if is_instance_valid(value) and value is Enemy3D and (value as Enemy3D).ai_state != "dead":
			live_count += 1
	var spawn_count := mini(mini(3, count), maxi(0, 8 - live_count))
	if spawn_count <= 0:
		return
	var floor_value := maxi(1, visual_theme.difficulty_rank)
	var configs: Array[Dictionary] = []
	var positions: Array = []
	for index in range(spawn_count):
		var child_data := _monster_injector.generate_split_child(child_kind, floor_value, 1)
		if child_data.is_empty():
			continue
		var spawn_data := child_data.duplicate(true)
		spawn_data["spawn_index"] = index
		# `persistent_id` 必须唯一：同一帧两只布洛布同时裂开会撞号，
		# 撞号会让存档恢复把两只子代认成同一只。
		spawn_data["persistent_id"] = "%s:split_%d:%d:%d" % [
			room_id, Time.get_ticks_usec(), source.get_instance_id(), index
		]
		configs.append(spawn_data)
		# 子代落在死者的两侧而不是正中心：中心会被玩家的下一发子弹立刻清掉。
		var angle := TAU * float(index) / float(maxi(1, spawn_count)) + PI * 0.5
		positions.append(
			source.global_position + Vector3(cos(angle) * 1.4, 0.0, sin(angle) * 1.4)
		)
	_reserve_room_spawn(room_id, configs, positions)


func _on_summon_requested(source: Enemy3D, count: int) -> void:
	if _completed or not is_instance_valid(source) or not (_enemy_nodes_by_room.get(source.room_id, []) as Array).has(source):
		return
	if source.ai_state == "dead" and source.elite_modifier_id != "Elite.SpawnOnDeath":
		return
	var live_count := 0
	for value in _enemy_nodes_by_room.get(source.room_id, []):
		if is_instance_valid(value) and value is Enemy3D and (value as Enemy3D).ai_state != "dead":
			live_count += 1
	var reserved_count := mini(mini(3, count), maxi(0, 8 - live_count))
	if reserved_count <= 0:
		return
	var configs: Array[Dictionary] = []
	var positions: Array = []
	for index in range(reserved_count):
		var minion_data: Array[Dictionary] = _monster_injector.generate_enemies({"type": "minion", "floor": maxi(1, visual_theme.difficulty_rank), "floor_level": 1})
		if minion_data.is_empty():
			continue
		var spawn_data := minion_data[index % minion_data.size()].duplicate(true)
		spawn_data["spawn_index"] = index
		spawn_data["persistent_id"] = "%s:summon_%d:%d:%d" % [source.room_id, Time.get_ticks_usec(), source.get_instance_id(), index]
		configs.append(spawn_data)
		positions.append(source.global_position + Vector3(cos(index * TAU / reserved_count) * 1.8, 0, sin(index * TAU / reserved_count) * 1.8))
	_reserve_room_spawn(source.room_id, configs, positions)


func _reserved_spawn_count(room_id: String) -> int:
	var count := 0
	for request in _reserved_room_spawns.get(room_id, []):
		count += (request.get("configs", []) as Array).size()
	# 延迟出怪（触发盒 delay_sec）也算「在途」：本波没到齐就不许判清房，
	# 否则会先解锁房间、再凭空冒出一波，观感与逻辑都是错的。
	count += _pending_delayed_spawn_count(room_id)
	return count


func _reserve_room_spawn(room_id: String, configs: Array[Dictionary], positions: Array = []) -> void:
	if configs.is_empty():
		return
	_cancel_room_wave_intermission(room_id)
	if not _reserved_room_spawns.has(room_id):
		_reserved_room_spawns[room_id] = []
	var saved_positions: Array = []
	for position_value in positions:
		var point := position_value as Vector3
		saved_positions.append([point.x, point.y, point.z])
	(_reserved_room_spawns[room_id] as Array).append({"configs": configs, "positions": saved_positions})
	_alive_by_room[room_id] = int(_alive_by_room.get(room_id, 0)) + configs.size()
	_update_wave_hud(room_id)
	call_deferred("_flush_reserved_room_spawns", room_id)


func _flush_reserved_room_spawns(room_id: String) -> void:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if _completed or not is_instance_valid(room) or not room.is_streamed():
		return
	var requests := _reserved_room_spawns.get(room_id, []) as Array
	if _room_spawn_blocked.has(room_id):
		return
	while not requests.is_empty():
		var request := requests[0] as Dictionary
		var configs: Array[Dictionary] = []
		configs.assign(request.get("configs", []))
		var positions: Array = []
		for point in request.get("positions", []):
			positions.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
		if _spawn_enemy_batch(room, configs, true, true, positions) < 0:
			return
		requests.pop_front()
	_reserved_room_spawns.erase(room_id)


func _on_enemy_killed(enemy: Enemy3D, enemy_data: Dictionary) -> void:
	# 首领阵亡登记**先于**离场记账：门控（Boss房02 竞技场）只认这条，
	# 而离场记账可能要等增援全清才把 `room.cleared` 置真。
	# `enemy_kind == "boss"` 是导出枚举，与血量/体型倍率同一判据，不会误判增援。
	if enemy != null and is_instance_valid(enemy) and enemy.enemy_kind == "boss":
		_mark_room_boss_defeated(enemy.room_id)
	if not _claim_enemy_departure(enemy):
		return
	_kills += 1
	last_killed_enemy_data = enemy_data.duplicate(true)
	kill_recorded.emit()
	var loot_room := _room_by_id.get(enemy.room_id) as DungeonRoom3D
	# 子图房间不在 `_room_by_id` 里；不补这一句，`_spawn_loot_items(null, ...)`
	# 会**静默返回 0** —— 表现是「7 只怪打死了，地上什么也没有」。
	# 这里只是借用子图房自己的包围盒做散布与贴地，掉落表仍来自敌人数据。
	if loot_room == null:
		loot_room = _secret_branch_room_ids.get(enemy.room_id) as DungeonRoom3D
	# 宝箱拟态：箱内的东西不在开箱时给，在**它肚子里**。放在击杀结算之前发 ——
	# 击杀掉落可能因为掉落表为空而返回 0 条，箱内物资不该被一起吞掉。
	if enemy.get_meta("chest_mimic", false) and loot_room != null:
		_deliver_chest_mimic_loot(loot_room, enemy)
	var reward_report := _reward_coordinator.resolve_kill(
		loot_room.reward_plan if loot_room != null else {},
		enemy_data,
		"%s:%s" % [enemy.room_id, enemy.get_persistent_id()]
	)
	if not bool(reward_report.get("ok", false)):
		push_warning("[Dungeon3D] Kill reward resolution failed (%s): %s" % [
			enemy.get_persistent_id(), str(reward_report.get("errors", []))
		])
	var grants := (reward_report.get("grants", []) as Array).duplicate(true)
	# 星币王牌的精英击杀赏金并入唯一金币球；房间倍率在统一地面出口应用。
	var kill_currency := int(enemy.get_meta("fate_kill_currency", 0))
	if kill_currency > 0:
		var merged := false
		for grant in grants:
			if str(grant.get("kind", "")) == "currency":
				grant["amount"] = int(grant.get("amount", 0)) + kill_currency
				merged = true
				break
		if not merged:
			grants.append({"kind": "currency", "amount": kill_currency})
	if _fate_economy.is_configured():
		var kill_income := 0
		for grant_value in grants:
			var grant := grant_value as Dictionary
			if str(grant.get("kind", "")) != "currency":
				continue
			if bool(_room_zero_currency.get(enemy.room_id, false)):
				continue
			var multiplier := float(_room_currency_multipliers.get(enemy.room_id, 1.0))
			kill_income += maxi(0, int(round(float(grant.get("amount", 0)) * multiplier)))
		_fate_economy.record_actual_kill_income(kill_income)
	if (bool(enemy_data.get("is_elite", false)) or enemy.enemy_kind == "boss") and player.has_method("on_fate_elite_killed"):
		player.call("on_fate_elite_killed")
	if not grants.is_empty():
		call_deferred(
			"_deliver_ground_rewards", loot_room, grants, enemy.global_position,
			"kill:%s:%s" % [enemy.room_id, enemy.get_persistent_id()]
		)
	if _encounter_event_director != null:
		_encounter_event_director.notify_enemy_departed(
			_encounter_owner_id(enemy_data), "killed"
		)
	_resolve_room_enemy_departure(enemy, false, enemy_data)


func _on_enemy_escaped(enemy: Enemy3D, _context: Dictionary) -> void:
	if not _claim_enemy_departure(enemy):
		return
	if _encounter_event_director != null:
		_encounter_event_director.notify_enemy_departed(
			_encounter_owner_id(enemy.get_enemy_data()), "escaped"
		)
	_resolve_room_enemy_departure(enemy, true, enemy.get_enemy_data())


func _encounter_owner_id(enemy_data: Dictionary) -> String:
	var event_id := str(enemy_data.get("encounter_event_instance_id", ""))
	return event_id if not event_id.is_empty() else str(enemy_data.get("encounter_instance_id", ""))


func _claim_enemy_departure(enemy: Enemy3D) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var members := _enemy_nodes_by_room.get(enemy.room_id, []) as Array
	if not members.has(enemy) or enemy.is_queued_for_deletion():
		return false
	# 先原子提交成员与计数，再发布击杀事件；同步订阅者可能重入房间修复。
	members.erase(enemy)
	_alive_by_room[enemy.room_id] = maxi(0, int(_alive_by_room.get(enemy.room_id, 0)) - 1)
	return true


func _resolve_room_enemy_departure(enemy: Enemy3D, did_escape: bool, enemy_data: Dictionary) -> void:
	# 宝箱拟态**不是本房波次的一部分** —— 它死了不代表房间肃清。
	#
	# 不在这里拦一句，宝箱房会被 `_mark_room_cleared()` 记成「已清内容房」：白送一次
	# 清房结算（宝箱房自己 `reward_plan` 是空的，但 `resolve_clear` 有全局兜底表），
	# 还会让「已清内容房数」提前涨一格、把传送支线与撤离门的解锁条件提前满足。
	# 实测这些副作用都不报错，只是数值悄悄变了 —— 属于最难被发现的那一类。
	if enemy.get_meta("chest_mimic", false):
		return
	if not _alive_by_room.has(enemy.room_id) or _room_spawn_blocked.has(enemy.room_id):
		return
	if int(_alive_by_room[enemy.room_id]) > 0:
		status_label.text = "残余敌对信号：%d" % int(_alive_by_room[enemy.room_id])
		return
	var pending_waves := _room_wave_queues.get(enemy.room_id, []) as Array
	if not pending_waves.is_empty():
		_schedule_room_wave_intermission(enemy.room_id)
		return
	var room: DungeonRoom3D = _room_by_id.get(enemy.room_id) as DungeonRoom3D
	# 踩点遭遇进行中：波与波之间场上会短暂清空，这时**不能**判本房已肃清 ——
	# 否则第一波刚清完房间就被放行、封门也一并解除，后续波次形同虚设。
	if _room_encounter_active.has(enemy.room_id):
		status_label.text = "遭遇进行中 · 尚有波次待发"
		return
	if _extraction_defense_active and enemy.room_id == _current_room_id:
		status_label.text = "撤离拦截波已压制 · 信号仍在同步"
		return
	# 子图房间：清房语义与主图不同（不发钥匙、不结算、不推进命运卡），
	# 且房间不在 `_room_by_id` 里 —— 上面那句 `_mark_room_cleared(room, true)`
	# 对它会静默变成空操作（`room == null` 直接 return），于是「打完了但房间永远算不清」。
	if _secret_branch_room_ids.has(enemy.room_id):
		_on_secret_branch_room_cleared(enemy.room_id)
		return
	_mark_room_cleared(room, true)
	status_label.text = (
		"精英已逃脱并记入跨局档案 · 房间通路恢复"
		if did_escape
		else "房间肃清 · 钥匙已掉落，可继续搜索或推进"
	)
	if AudioManager != null:
		AudioManager.play_sfx("wave_clear", -3.0)
	if (
		_extraction != null
		and (
			enemy.room_id == "boss"
			or (
				room != null
				and room.room_type == "BOSS"
			)
		)
	):
		_extraction.set_locked(false)
		_hide_boss_hud()
		if AudioManager != null:
			AudioManager.play_sfx("boss_defeat", -1.0)
		status_label.text = "Boss 已清除 · 撤离信标已解锁"
	if not did_escape and bool(enemy_data.get("is_elite", false)) and room != null:
		call_deferred("_ensure_conditional_extraction", "ELITE_KILL", room, Vector3(4.0, 0.0, 3.0))
	_refresh_loot_label()


func _on_boss_phase_changed(enemy: Enemy3D, phase: int) -> void:
	if enemy == _active_boss and _boss_label != null:
		_boss_label.text = "%s  ·  阶段 %d" % [enemy.get_enemy_data().get("name", "废土首领"), phase]
	status_label.text = "Boss 阶段 %d · 攻击节奏与增援强度提升" % phase
	if AudioManager != null:
		AudioManager.play_sfx("boss_phase", -2.0)


func _on_fate_enemy_state_changed(_previous: String, current: String, enemy: Enemy3D) -> void:
	if current not in ["chase", "telegraph", "attack", "recovery"] or not is_instance_valid(enemy):
		return
	if bool(enemy.get_enemy_data().get("is_elite", false)) or enemy.enemy_kind == "boss":
		player.on_fate_elite_combat_started("%s:%s" % [enemy.room_id, enemy.get_persistent_id()])


func _on_boss_activation_completed(enemy: Enemy3D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_on_fate_enemy_state_changed("dormant", "chase", enemy)
	# Boss HUD 与战斗开放使用同一条公共激活完成信号：出场动画期间只绑定数据，
	# 完整结束后才揭示血条，避免玩家一进房就提前看到首领信息。
	if enemy == _active_boss and _boss_panel != null:
		_boss_panel.visible = true
	var room := _room_by_id.get(enemy.room_id) as DungeonRoom3D
	if room == null or room.boss_reinforcement_plan.is_empty() or room.cleared:
		return
	var state := _boss_reinforcement_states.get(room.room_id, {}) as Dictionary
	state["armed"] = true
	state["stopped"] = false
	state["elapsed"] = 0.0
	state["round"] = maxi(0, int(state.get("round", 0)))
	state["cursor"] = maxi(0, int(state.get("cursor", 0)))
	_boss_reinforcement_states[room.room_id] = state
	status_label.text = "Boss 已激活 · 10 秒后两侧增援开始投放"


func _tick_boss_reinforcements(delta: float) -> void:
	if delta <= 0.0 or _completed or _current_room_id.is_empty():
		return
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if (
		room == null
		or room.cleared
		or room.boss_reinforcement_plan.is_empty()
		or not bool(room.boss_reinforcement_plan.get("enabled", false))
	):
		return
	var boss := _boss_reinforcement_boss(room.room_id)
	if boss == null:
		if _boss_reinforcement_states.has(room.room_id):
			(_boss_reinforcement_states[room.room_id] as Dictionary)["stopped"] = true
		return
	var state := _boss_reinforcement_states.get(room.room_id, {}) as Dictionary
	# 旧存档可能已保存「Boss 激活完成」却没有本控制器状态；从 Boss 的正式恢复状态补建，
	# 但不会重置已有轮次或倒计时。
	if not bool(state.get("armed", false)):
		if boss.monitor_combat == null or not boss.monitor_combat.activation_completed:
			return
		state = {
			"armed": true,
			"stopped": false,
			"elapsed": 0.0,
			"round": 0,
			"cursor": 0,
		}
	if bool(state.get("stopped", false)):
		return
	state["elapsed"] = float(state.get("elapsed", 0.0)) + delta
	var round_index := maxi(0, int(state.get("round", 0)))
	var wait_seconds := (
		maxf(0.1, float(room.boss_reinforcement_plan.get("activation_delay_sec", 10.0)))
		if round_index == 0
		else _boss_reinforcement_interval(room.boss_reinforcement_plan, round_index)
	)
	if float(state["elapsed"]) < wait_seconds:
		_boss_reinforcement_states[room.room_id] = state
		return
	var spawned := _spawn_boss_reinforcement_round(room, state)
	if spawned > 0:
		state["elapsed"] = 0.0
		state["round"] = round_index + 1
		status_label.text = "Boss 增援第 %d 轮 · 两侧投放 %d 只" % [round_index + 1, spawned]
	else:
		# 容量已满时保持“已到期”，一旦腾出名额就在下一帧补投，不再额外等完整轮次。
		state["elapsed"] = wait_seconds
	_boss_reinforcement_states[room.room_id] = state


func _boss_reinforcement_boss(room_id: String) -> Enemy3D:
	for value in _enemy_nodes_by_room.get(room_id, []) as Array:
		if not is_instance_valid(value) or not value is Enemy3D:
			continue
		var enemy := value as Enemy3D
		if (
			enemy.ai_state != "dead"
			and str(enemy.get_enemy_data().get("boss_content_id", "")) == "boss_monitor002"
		):
			return enemy
	return null


func _boss_reinforcement_alive(room_id: String) -> int:
	var count := 0
	for value in _enemy_nodes_by_room.get(room_id, []) as Array:
		if not is_instance_valid(value) or not value is Enemy3D:
			continue
		var enemy := value as Enemy3D
		if enemy.ai_state != "dead" and bool(enemy.get_enemy_data().get("boss_reinforcement_spawned", false)):
			count += 1
	# 预约在 call_deferred 实到前已经占用存活账；上限也必须把这段窗口算进去，
	# 否则同帧重复触发或房间流送暂停时可连续预约并突破 max_reinforcement_alive。
	for request_value in _reserved_room_spawns.get(room_id, []) as Array:
		var request := request_value as Dictionary
		for config_value in request.get("configs", []) as Array:
			if bool((config_value as Dictionary).get("boss_reinforcement_spawned", false)):
				count += 1
	return count


func _boss_reinforcement_interval(plan: Dictionary, completed_rounds: int) -> float:
	var initial := maxf(0.1, float(plan.get("initial_interval_sec", 6.0)))
	var step := float(plan.get("interval_step_sec", -0.35))
	var minimum := maxf(0.1, float(plan.get("min_interval_sec", 2.5)))
	return maxf(minimum, initial + step * float(completed_rounds))


func _boss_reinforcement_marker_cycle(room: DungeonRoom3D) -> Array[Marker3D]:
	var west: Array[Marker3D] = []
	var east: Array[Marker3D] = []
	var other: Array[Marker3D] = []
	for marker in room.boss_reinforcement_spawn_markers():
		match str(marker.get_meta("spawn_side", "")):
			"west": west.append(marker)
			"east": east.append(marker)
			_: other.append(marker)
	var result: Array[Marker3D] = []
	var paired := maxi(west.size(), east.size())
	for index in range(paired):
		if index < west.size():
			result.append(west[index])
		if index < east.size():
			result.append(east[index])
	result.append_array(other)
	return result


func _spawn_boss_reinforcement_round(room: DungeonRoom3D, state: Dictionary) -> int:
	var plan := room.boss_reinforcement_plan
	var markers := _boss_reinforcement_marker_cycle(room)
	if markers.is_empty():
		return 0
	var max_alive := maxi(1, int(plan.get("max_reinforcement_alive", 18)))
	var capacity := maxi(0, max_alive - _boss_reinforcement_alive(room.room_id))
	if capacity <= 0:
		return 0
	var round_index := maxi(0, int(state.get("round", 0)))
	var desired := mini(
		maxi(1, int(plan.get("initial_count", 3)) + round_index * int(plan.get("count_step", 1))),
		maxi(1, int(plan.get("max_count_per_round", 8)))
	)
	var count := mini(desired, capacity)
	var floor := maxi(1, visual_theme.difficulty_rank)
	var floor_level := clampi(
		int(float(_record_index(room.room_id)) / maxf(1.0, float(_records.size() - 1)) * 3.0),
		0,
		3
	)
	var configs := _monster_injector.generate_enemies({
		"type": str(plan.get("enemy_request_type", "ambush")),
		"count": count,
		"floor": floor,
		"floor_level": floor_level,
	})
	if configs.is_empty():
		return 0
	count = mini(count, configs.size())
	configs.resize(count)
	var positions: Array = []
	var cursor := maxi(0, int(state.get("cursor", 0)))
	var center := room.boss_spawn_position_world()
	for index in range(count):
		var marker := markers[(cursor + index) % markers.size()]
		positions.append(marker.global_position)
		configs[index]["boss_reinforcement_spawned"] = true
		configs[index]["persistent_id"] = "%s:boss_reinforcement:%d:%d" % [
			room.room_id, round_index + 1, index,
		]
		configs[index]["spawn_launch_target"] = center
		configs[index]["spawn_launch_speed_mps"] = float(plan.get("launch_speed_mps", 8.5))
		configs[index]["spawn_launch_duration_sec"] = float(plan.get("launch_duration_sec", 0.38))
	state["cursor"] = (cursor + count) % markers.size()
	_reserve_room_spawn(room.room_id, configs, positions)
	return count


func _on_enemy_health_changed(enemy: Enemy3D, current: int, maximum: int) -> void:
	if enemy != _active_boss or _boss_bar == null:
		return
	_boss_bar.max_value = maxi(1, maximum)
	_boss_bar.value = current
	if _boss_delayed_bar != null:
		_boss_delayed_bar.max_value = _boss_bar.max_value
	var next_ratio := clampf(float(current) / float(maxi(1, maximum)), 0.0, 1.0)
	if _boss_delayed_bar == null or next_ratio >= _boss_delayed_value:
		_boss_delayed_value = next_ratio
		if _boss_delayed_bar != null:
			_boss_delayed_bar.value = _boss_delayed_value * _boss_delayed_bar.max_value


func _tick_boss_health_bar_delay(delta: float) -> void:
	if _boss_delayed_bar == null or _boss_bar == null:
		return
	var actual_ratio := _boss_bar.value / maxf(1.0, _boss_bar.max_value)
	if _boss_delayed_value <= actual_ratio:
		return
	_boss_delayed_value = move_toward(
		_boss_delayed_value,
		actual_ratio,
		delta * HUD_HEALTH_BAR_DELAY_SPEED
	)
	_boss_delayed_bar.value = _boss_delayed_value * _boss_delayed_bar.max_value


func _show_boss_hud(enemy: Enemy3D) -> void:
	var is_new_boss := enemy != _active_boss
	_active_boss = enemy
	if _boss_panel == null:
		# 简约首领条：透明外壳只负责布局，不再使用厚重面板、霓虹边框或投影。
		_boss_panel = _make_bare_hud_panel()
		_boss_panel.name = "BossHUD3D"
		# 2026-10-14 主人：「boss血条放在画面的上面一些，现在还是会遮挡」。
		# 上移 106 → 80（canvas 84.8 → 64.0），给 Boss 本体让出约 21 px。
		# 新位置的下界由**关卡标题带**定：房间行（设计 14..38）与波次行（设计 40..62）
		# 的实底在 canvas ≈49.6，64.0 留出约 14 px 净空 —— 这就是
		# `verify_expedition_monitor_boss_flow` 里那条「位于关卡标题带下方、不发生文字重叠」
		# 断言真正要守的东西（旧阈值 80.0 只是「设计 100」的口径，比标题带实底低 30 px）。
		# 注意这条要跟着 `HUD_UI_SCALE` 一起想：canvas y = 设计 y × HUD_UI_SCALE(0.80)。
		_anchor_control(_boss_panel, 0.5, 0.0, 0.5, 0.0, -340, 80, 340, 134)
		$HUD.add_child(_boss_panel)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", _hud_int(18))
		margin.add_theme_constant_override("margin_right", _hud_int(18))
		_boss_panel.add_child(margin)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", _hud_int(7))
		margin.add_child(box)
		_boss_label = Label.new()
		_boss_label.name = "BossName"
		_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_boss_label.add_theme_font_size_override("font_size", _hud_int(21))
		# BOSS 名归到棱镜"危险"语义槽（与 BossPanel 的 danger 线同色），
		# 不再用上一代那层暖白偏粉的手调色。
		_boss_label.add_theme_color_override("font_color", UIPalette.PRISM_DANGER)
		_boss_label.add_theme_color_override("font_outline_color", Color(0.08, 0.01, 0.015, 0.96))
		_boss_label.add_theme_constant_override("outline_size", _hud_int(5))
		var boss_font := UIStyleFactory.make_prism_font(3)
		if boss_font != null:
			_boss_label.add_theme_font_override("font", boss_font)
		box.add_child(_boss_label)
		# 两层叠放：白条追赶真实红条；两者都保留在同一薄条区域内，不增加高度。
		var bar_stack := Control.new()
		bar_stack.name = "BossHealthBarStack"
		bar_stack.custom_minimum_size.y = _hud_int(10)
		box.add_child(bar_stack)
		_boss_delayed_bar = ProgressBar.new()
		_boss_delayed_bar.name = "BossHealthBarDelayed"
		_boss_delayed_bar.show_percentage = false
		_boss_delayed_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_boss_delayed_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var delayed_background := StyleBoxFlat.new()
		delayed_background.bg_color = Color(0.07, 0.025, 0.03, 0.88)
		delayed_background.border_color = Color(1.0, 0.46, 0.42, 0.38)
		delayed_background.set_border_width_all(1)
		delayed_background.set_corner_radius_all(_hud_int(2))
		_boss_delayed_bar.add_theme_stylebox_override("background", delayed_background)
		var delayed_fill := StyleBoxFlat.new()
		delayed_fill.bg_color = HUD_HEALTH_BAR_DELAY_COLOR
		delayed_fill.set_corner_radius_all(_hud_int(2))
		_boss_delayed_bar.add_theme_stylebox_override("fill", delayed_fill)
		bar_stack.add_child(_boss_delayed_bar)
		_boss_bar = ProgressBar.new()
		_boss_bar.name = "BossHealthBar"
		_boss_bar.show_percentage = false
		_boss_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar_background := StyleBoxFlat.new()
		bar_background.bg_color = Color(0.07, 0.025, 0.03, 0.0)
		bar_background.border_color = Color(1.0, 0.46, 0.42, 0.38)
		bar_background.set_border_width_all(1)
		bar_background.set_corner_radius_all(_hud_int(2))
		_boss_bar.add_theme_stylebox_override("background", bar_background)
		var bar_fill := StyleBoxFlat.new()
		bar_fill.bg_color = Color(0.96, 0.13, 0.17)
		bar_fill.set_corner_radius_all(_hud_int(2))
		_boss_bar.add_theme_stylebox_override("fill", bar_fill)
		bar_stack.add_child(_boss_bar)
	# 有正式出场流程的 Boss 必须等动画完成；没有该流程的旧 Boss 保持即时显示。
	_boss_panel.visible = enemy.monitor_combat == null or enemy.monitor_combat.activation_completed
	if is_new_boss and AudioManager != null:
		AudioManager.play_sfx("boss_intro", -1.5)
	_boss_label.text = "%s  ·  阶段 %d" % [enemy.get_enemy_data().get("name", "废土首领"), enemy.boss_phase]
	if is_new_boss:
		_boss_delayed_value = clampf(float(enemy.current_hp) / float(maxi(1, enemy.max_hp)), 0.0, 1.0)
	_on_enemy_health_changed(enemy, enemy.current_hp, enemy.max_hp)


func _hide_boss_hud() -> void:
	_active_boss = null
	if _boss_panel != null:
		_boss_panel.visible = false


func _ensure_conditional_extraction(type_id: String, room: DungeonRoom3D, local_position: Vector3) -> ExtractionBeacon3D:
	var existing := _conditional_extractions.get(type_id) as ExtractionBeacon3D
	if existing != null and is_instance_valid(existing):
		existing.set_locked(false)
		return existing
	var duration := 30.0 if type_id == "ELITE_KILL" else 30.0
	var beacon := _create_extraction_beacon(room, type_id, duration, false, local_position)
	_conditional_extractions[type_id] = beacon
	minimap.reveal_room(room.room_id)
	return beacon


func _on_prop_searched(room: DungeonRoom3D, loot_hint: Dictionary) -> void:
	if MonsterAIManager != null:
		MonsterAIManager.broadcast_sound_stimulus(
			loot_hint.get("sound_position", room.global_position) as Vector3,
			8.0,
			"container_open",
			player
		)
	if _map_fate_triggers != null:
		_map_fate_triggers.on_container_opened(str(loot_hint.get("size_class", "crate")))
	var size_class := str(loot_hint.get("size_class", "medium"))
	var container_type := "crate" if size_class == "small" else "locker" if size_class == "medium" else "hidden_cache"
	var reward_floor := maxi(1, visual_theme.difficulty_rank)
	var event_id := "search:%s:%s" % [room.room_id, str(loot_hint.get("prop_id", "unknown"))]
	var report := _reward_coordinator.resolve_search(
		room.reward_plan,
		"scavenge_floor_%d" % mini(5, reward_floor),
		reward_floor,
		event_id
	)
	if not bool(report.get("ok", false)):
		push_warning("[Dungeon3D] Search reward resolution failed (%s): %s" % [
			event_id, str(report.get("errors", []))
		])
		status_label.text = "搜索失败 · 奖励配置无效"
		return
	var candidates := _ground_reward_candidates(report.get("grants", []))
	if _extra_loot_next_chest_count > 0:
		var ranked: Array[Dictionary] = []
		ranked.append_array(candidates)
		for _extra_index in range(_extra_loot_next_chest_count):
			var extra_report := _reward_coordinator.resolve_search(
				room.reward_plan,
				"scavenge_floor_%d" % mini(5, reward_floor),
				reward_floor,
				"%s:extra:%d" % [event_id, _extra_index]
			)
			var extra := _ground_reward_candidates(extra_report.get("grants", []))
			if not extra.is_empty():
				ranked.append(extra[0])
		if not ranked.is_empty():
			ranked.sort_custom(
				func(a: Dictionary, b: Dictionary) -> bool:
					return _fate_rarity_rank(a.get("item", {}) as Dictionary) > _fate_rarity_rank(b.get("item", {}) as Dictionary)
			)
			candidates = [ranked[0]]
		_extra_loot_next_chest_count = 0
	if candidates.is_empty():
		status_label.text = "容器为空"
		return
	var selected := (candidates[0].get("grant", {}) as Dictionary).duplicate(true)
	if str(selected.get("kind", "")) == "currency":
		selected["amount"] = 1
	else:
		selected["count"] = 1
		var item := selected.get("item", {}) as Dictionary
		_apply_fate_item_quality(item, _next_chest_quality_boost, _next_chest_max_rarity)
		item["fate_rarity_cap"] = _next_chest_max_rarity
	_next_chest_quality_boost = 0
	_next_chest_max_rarity = ""
	var delivery := _deliver_ground_rewards(
		room, [selected], player.global_position + player.aim_direction * 1.2, event_id
	)
	status_label.text = (
		"搜索完成 · 1 件物资落地"
		if not (delivery.get("granted", []) as Array).is_empty()
		else "搜索完成 · 物资落地失败"
	)


## 宝箱开箱（2026-10-29）。玩家在 REWARD 房按 E 触发。
##
## **顺序是刻意的：扣钥匙 → 收口箱子形态 → 掉落 → 命运卡。**
##   · 钥匙在最前：没有钥匙就什么都别发生，箱子保持可交互（玩家去拿了钥匙还能回来开）；
##   · 收口形态在结算前：一旦扣了钥匙就必须把箱子标成已开，否则玩家能反复按 E
##     白嫖多次掉落（`commit_opened()` 幂等，重复调用无副作用）；
##   · 掉落先于命运卡：命运卡可能改变后续掉落品质（`fate_lucky_chest` 之类），
##     先发卡再抽掉落会让"这一箱吃不吃得到卡的效果"变成时序竞态。
func _on_chest_open_requested(room: DungeonRoom3D, chest: TreasureChest3D) -> void:
	if room == null or chest == null or not is_instance_valid(chest):
		return
	if chest.is_opened():
		return
	if chest.requires_key:
		if _get_total_room_keys() <= 0:
			status_label.text = "宝箱上锁 · 需要 1 把房间钥匙"
			# 不置 `_opened`、不扣任何东西：箱子留在原地等玩家带钥匙回来。
			return
		_consume_room_key()
		_refresh_loot_label()
	if chest.mimic:
		# 拟态：钥匙照扣，然后箱子变成怪。**这一条不能挪到扣钥匙前面** ——
		# 先现形再判钥匙，会出现「没钥匙也把拟态惊动了、箱子已经没了」。
		_reveal_chest_mimic(room, chest)
		return
	chest.commit_opened()
	if _map_fate_triggers != null:
		# 宝箱算一次"容器开启"。给独立的 size_class 值，方便将来按箱/罐分别计数：
		# 传 "crate" 会让宝箱与普通箱子混在一起，统计再也分不开。
		_map_fate_triggers.on_container_opened("treasure_chest")

	var grants := _resolve_chest_grants(room, chest)
	var delivered := 0
	if not grants.is_empty():
		var delivery := _deliver_ground_rewards(
			room, grants,
			chest.global_position + Vector3(0, 0.4, 0),
			"chest:%s:%s" % [room.room_id, chest.chest_id]
		)
		delivered = (delivery.get("granted", []) as Array).size()

	var fate := _grant_chest_fate_cards(chest.fate_card_per_open)
	var parts: Array[String] = []
	parts.append("宝箱开启 · %d 件物资" % delivered if delivered > 0 else "宝箱开启 · 箱内为空")
	if not (fate.get("applied", []) as Array).is_empty():
		parts.append("命运卡「%s」" % str((fate["applied"] as Array)[0]))
	elif int(fate.get("pending", 0)) > 0:
		# 卡没能当场生效（枪械命运槽满 / 需要选来源）——它已经被桥上记账，
		# 玩家可以从 HUD 的待领取按钮处理。**不能静默**：那等于宝箱少给了一样东西。
		parts.append("命运卡已暂存（槽位或来源不可用，见待领取）")
	elif int(fate.get("drawn", 0)) == 0 and chest.fate_card_per_open > 0:
		parts.append("命运卡发放失败")
	status_label.text = " · ".join(parts)


## 拟态刷怪的最小离玩家距离。开箱那一刻玩家就贴在箱子前，直接在箱子位置刷怪
## 会让怪与玩家重叠 —— 接触伤害在同帧结算，玩家连后撤的机会都没有。
const CHEST_MIMIC_MIN_SPAWN_DISTANCE_M := 3.0


## 宝箱拟态现形（2026-10-30 接回）。
##
## 与普通开箱只差两处：**箱子消失**、**奖励改成击杀后才掉**。钥匙照扣 ——
## 这正是这条机制的全部恶意：宝箱房里那只箱子可能不是箱子，而你按 E 的时候无从分辨。
## 想清楚「钥匙白花」这件事是有意的，别把它当 bug 修掉。
func _reveal_chest_mimic(room: DungeonRoom3D, chest: TreasureChest3D) -> void:
	if room == null or chest == null:
		return
	chest.commit_mimic_reveal()
	if _map_fate_triggers != null:
		# 对命运卡系统来说「箱子被打开过」这件事仍然成立，统计口径保持一致。
		_map_fate_triggers.on_container_opened("treasure_chest")
	var kind := str(chest.mimic_monster_kind)
	var base_type: Dictionary = MonsterInjector.BASE_ENEMY_TYPES.get(kind, {})
	if base_type.is_empty():
		# 钥匙已经扣了、箱子也没了。必须吼出来 —— 否则表现是「花了钥匙什么都没发生」，
		# 排查时会被当成随机 bug。
		push_error(
			"[Dungeon3D] 宝箱拟态：未知怪物 kind『%s』（%s/%s），本箱无补偿"
			% [kind, room.room_id, chest.chest_id]
		)
		status_label.text = "宝箱开启 · 箱内为空"
		return
	var presentation: Dictionary = MonsterInjector.ENEMY_PRESENTATION.get(kind, {})
	var config := {
		"enemy_type": kind,
		"name": str(base_type.get("name", kind)),
		"emoji": str(presentation.get("emoji", "\u5c38")),
		"hp": int(base_type.get("hp_base", 20)),
		"max_hp": int(base_type.get("hp_base", 20)),
		"damage": int(base_type.get("damage_base", 5)),
		"speed": float(base_type.get("speed", 60.0)),
		"persistent_id": "chest_mimic:%s:%s" % [room.room_id, chest.chest_id],
	}
	var before: Array = (_enemy_nodes_by_room.get(room.room_id, []) as Array).duplicate()
	var spawned := _spawn_enemy_batch(
		room, [config], true, false, [_chest_mimic_spawn_position(room, chest)]
	)
	var mimicked: Enemy3D = null
	for value in _enemy_nodes_by_room.get(room.room_id, []):
		if before.has(value):
			continue
		if is_instance_valid(value) and value is Enemy3D:
			mimicked = value as Enemy3D
			break
	if spawned <= 0 or mimicked == null:
		push_error(
			"[Dungeon3D] 宝箱拟态生成失败（%s/%s，spawned=%d）—— 钥匙已扣，玩家什么也没得到"
			% [room.room_id, chest.chest_id, spawned]
		)
		status_label.text = "宝箱开启 · 箱内为空"
		return
	# 打两个标记：`chest_mimic` 用于「它死了不算清房」，`chest_mimic_loot` 是
	# **开箱那一刻就抽好的**箱内物资 —— 击杀时直接落地，不再抽第二次（重抽会让
	# 「拟态箱」的实际收益和普通箱不同，品质加成也就对不上了）。
	mimicked.set_meta("chest_mimic", true)
	mimicked.set_meta("chest_mimic_loot", _resolve_chest_grants(room, chest))
	mimicked.set_meta("chest_mimic_fate_cards", chest.fate_card_per_open)
	# 出生即现形。`egt_mimic` 的 profile 里带 `disguise`（伪装态静止 / 不攻击 / **不吃伤害**），
	# 那是给它「在房间里蹲着装箱子」用的；而这里它已经当着玩家的面从箱子里咬出来了，
	# 再伪装就等于刷出一只打不动的假箱子。
	mimicked.reveal_disguise_now()
	status_label.text = "宝箱是拟态！击破它才能拿回箱内物资"


## 拟态的落点：箱子的位置，但**必须推开玩家**。
func _chest_mimic_spawn_position(room: DungeonRoom3D, chest: TreasureChest3D) -> Vector3:
	var floor_y := float(room.get_meta("walk_surface_y_m", 0.0))
	var point := chest.global_position
	point.y = floor_y
	if player != null and is_instance_valid(player):
		var away := point - player.global_position
		away.y = 0.0
		if away.length() < CHEST_MIMIC_MIN_SPAWN_DISTANCE_M:
			away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
			point = player.global_position + away * CHEST_MIMIC_MIN_SPAWN_DISTANCE_M
			point.y = floor_y
	# 夹进房间。箱子本来就在房里，这一句只是保险 —— 但少它就是「怪刷在墙外」。
	var half := room.get_dimensions() * 0.5
	var local := room.global_transform.affine_inverse() * point
	local.x = clampf(local.x, -half.x + 1.2, half.x - 1.2)
	local.z = clampf(local.z, -half.y + 1.2, half.y - 1.2)
	var resolved := room.global_transform * local
	resolved.y = floor_y
	return resolved


## 拟态被击杀：把开箱时抽好的那份物资与命运卡补给玩家。
##
## 为什么不在开箱时就给：那样「箱子是拟态」就只是多打一只怪，风险与回报无关。
## 现在的结构是「你付了钥匙，物资在那只怪肚子里」—— 跑了就真的没了。
func _deliver_chest_mimic_loot(room: DungeonRoom3D, enemy: Enemy3D) -> void:
	var grants: Array = (enemy.get_meta("chest_mimic_loot", []) as Array).duplicate(true)
	var delivered := 0
	if not grants.is_empty():
		var delivery := _deliver_ground_rewards(
			room, grants,
			enemy.global_position + Vector3(0, 0.4, 0),
			"chest_mimic:%s:%s" % [room.room_id, enemy.get_persistent_id()]
		)
		delivered = (delivery.get("granted", []) as Array).size()
	var fate := _grant_chest_fate_cards(int(enemy.get_meta("chest_mimic_fate_cards", 0)))
	# 清掉标记：`_on_enemy_killed` 与 `escaped` 理论上只来一次，但这里不做幂等假设 ——
	# 一份物资发两遍是最难被玩家原谅的那类 bug。
	enemy.set_meta("chest_mimic_loot", [])
	enemy.set_meta("chest_mimic_fate_cards", 0)
	var parts: Array[String] = []
	parts.append("拟态击破 · %d 件物资" % delivered if delivered > 0 else "拟态击破 · 腹中空空")
	if not (fate.get("applied", []) as Array).is_empty():
		parts.append("命运卡「%s」" % str((fate["applied"] as Array)[0]))
	elif int(fate.get("pending", 0)) > 0:
		parts.append("命运卡已暂存（见待领取）")
	status_label.text = " · ".join(parts)


## 抽这一箱的掉落。**每件独立抽一次**（`drop_count` 次 `resolve_search`），
## 而不是抽一次再复制 —— 复制会让"开一箱得两件同样的东西"，读起来像 bug。
func _resolve_chest_grants(room: DungeonRoom3D, chest: TreasureChest3D) -> Array:
	var floor_level := maxi(1, visual_theme.difficulty_rank)
	var pool_id := str(chest.reward_pool_id)
	if pool_id.is_empty():
		pool_id = "loot_floor_1_2"
	var grants: Array = []
	for index in range(chest.drop_count):
		var event_id := "chest:%s:%s:%d" % [room.room_id, chest.chest_id, index]
		var report := _reward_coordinator.resolve_search(
			room.reward_plan, pool_id, floor_level, event_id
		)
		if not bool(report.get("ok", false)):
			push_warning("[Dungeon3D] Chest reward resolution failed (%s): %s" % [
				event_id, str(report.get("errors", []))
			])
			continue
		var candidates := _ground_reward_candidates(report.get("grants", []))
		if candidates.is_empty():
			continue
		var grant := (candidates[0].get("grant", {}) as Dictionary).duplicate(true)
		if str(grant.get("kind", "")) == "currency":
			# 货币单件化：箱子里滚一堆小钱球没有意义，一个球就够表达"里面有钱"。
			grant["amount"] = 1
		else:
			grant["count"] = 1
			var item := grant.get("item", {}) as Dictionary
			# 品质加成：箱子越好，抽出来的东西品质越高。**这是箱子品质唯一的作用**，
			# 它不改变掉落数量（数量由 `drop_count` 决定，玩家读得懂）。
			_apply_fate_item_quality(item, chest.quality_tier(), "")
		grants.append(grant)
	return grants


## 开箱给命运卡。走 `FateCardGameBridge.grant_random_card_from_character()` ——
## 而不是自己 `draw_offer` + `apply_card_instance`，因为那个函数已经处理了两件麻烦事：
##   ① 用不了（枪械命运槽满 / 需要选来源）时把卡**留在待领取**而不是丢弃；
##   ② 扣费与回滚。
## 自己实现一遍就等于把这两条重新写错一次。
func _grant_chest_fate_cards(count: int) -> Dictionary:
	var result := {"drawn": 0, "applied": [], "pending": 0}
	if count <= 0:
		return result
	var bridge := get_node_or_null("/root/FateCardGameBridge")
	if bridge == null:
		push_warning("[Dungeon3D] 宝箱命运卡失败：FateCardGameBridge 未注册")
		return result
	for _index in range(count):
		result["drawn"] = int(result["drawn"]) + 1
		var single: Dictionary = bridge.call("grant_random_card_from_character", 0)
		if bool(single.get("success", false)):
			var cards: Array = bridge.call("get_cards")
			if not cards.is_empty():
				var card := cards[cards.size() - 1] as FateCard
				if card != null:
					(result["applied"] as Array).append(card.card_name)
		elif bool(single.get("pending", false)):
			result["pending"] = int(result["pending"]) + 1
	return result


const FATE_RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]


func _fate_rarity_rank(item: Dictionary) -> int:
	return maxi(0, FATE_RARITIES.find(str(item.get("rarity", "common")).to_lower()))


func _apply_fate_item_quality(item: Dictionary, tiers: int, cap: String = "") -> void:
	if item.is_empty() or str(item.get("type", "")) == "currency":
		return
	var rank := clampi(_fate_rarity_rank(item) + tiers, 0, FATE_RARITIES.size() - 1)
	if not cap.is_empty():
		rank = mini(rank, maxi(0, FATE_RARITIES.find(cap.to_lower())))
	item["rarity"] = FATE_RARITIES[rank]
	if item.get("weapon_instance") is Dictionary:
		(item["weapon_instance"] as Dictionary)["rarity"] = item["rarity"]


## 候选按物品实际稀有度排序，池档位不等同于品质。
func _ground_reward_candidates(grants: Array) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for value in grants:
		if not value is Dictionary:
			continue
		var item := REWARD_SINK_SCRIPT.materialize_ground_items([value])
		if item.size() == 1:
			candidates.append({"grant": (value as Dictionary).duplicate(true), "item": item[0]})
	return candidates


## 唯一的一次性地面发放回调：场景负责房间/落点，Sink 负责结果账。
func _deliver_ground_rewards(
	room: DungeonRoom3D, grants: Array, origin: Vector3, context: String
) -> Dictionary:
	var adjusted: Array = []
	for value in grants:
		var grant := (value as Dictionary).duplicate(true)
		if str(grant.get("kind", "")) == "currency":
			if room != null and bool(_room_zero_currency.get(room.room_id, false)):
				continue
			var multiplier := float(_room_currency_multipliers.get(room.room_id, 1.0)) if room != null else 1.0
			grant["amount"] = maxi(0, int(round(float(grant.get("amount", 0)) * multiplier)))
			if int(grant["amount"]) <= 0:
				continue
		adjusted.append(grant)
	var delivery := REWARD_SINK_SCRIPT.apply_ground(
		adjusted, func(items: Array) -> int:
			for item in items:
				if str(item.get("type", "")) == "currency":
					continue
				var tiers := 0
				for rule in _fate_drop_quality_rules:
					rule["count"] = int(rule["count"]) + 1
					if int(rule["count"]) % int(rule["every"]) == 0:
						tiers += int(rule["tiers"])
				_apply_fate_item_quality(item, tiers, str(item.get("fate_rarity_cap", "")))
			return _spawn_loot_items(room, items, origin)
	)
	var rejected := delivery.get("rejected", []) as Array
	if not rejected.is_empty():
		push_warning("[Dungeon3D] Ground reward rejected (%s): %d/%d" % [context, rejected.size(), grants.size()])
	return delivery


## `spread`：是否按「第几件」做确定性散布（多件掉落才需要，避免叠在一起）。
## 单件、且落点要被别处（如剧本的朝向目标点）精确引用时传 `false` ——
## 散布在 index=0 时也至少有 `LOOT_SCATTER_MIN_RADIUS_M` 的偏移，
## 会让「指那个常量点」与「枪实际在哪」对不上（2026-09-22 开场那把枪）。
## 散开范围与曲线见 `loot_scatter_half_extent_m`；落点仍逐件过贴地校位 + 净空校验，
## 目的是「散得开」，不是「散进墙里」。
func _spawn_loot_items(
	room: DungeonRoom3D,
	items: Array,
	world_position: Vector3,
	pickup_grace_seconds: float = 0.0,
	spread: bool = true
) -> int:
	if room == null or not is_instance_valid(room):
		return 0
	var spawned := 0
	var scatter_max_radius := _loot_scatter_max_radius(room, items.size())
	for index in range(items.size()):
		var item_value: Variant = items[index]
		if not item_value is Dictionary:
			push_warning("[Dungeon3D] Ignored non-dictionary loot entry at index %d" % index)
			continue
		var item: Dictionary = (item_value as Dictionary).duplicate(true)
		# 堆叠数量是物品真实数量；尤其弹药必须以“发”为单位落地和拾取。
		item["count"] = maxi(1, int(item.get("count", 1)))
		var pickup := GROUND_LOOT_SCRIPT.new() as GroundLootPickup3D
		var color := ItemModelFactory3D.get_item_color(item)
		var narrative_auto_equip := bool(item.get("narrative_auto_equip", false))
		pickup.configure(item, color)
		# `GroundLootPickup3D.configure()` 会规范化武器实例；剧情标记必须显式
		# 回写到规范化字典，确保它随地面实体和运行时快照继续存在。
		if narrative_auto_equip and str(item.get("type", "")) == "weapon":
			pickup.item_data["narrative_auto_equip"] = true
		pickup.set_pickup_grace_seconds(pickup_grace_seconds)
		room.add_child(pickup)
		var requested_position := world_position
		if spread:
			requested_position += _loot_scatter_offset(index, items.size(), scatter_max_radius)
		pickup.global_position = _resolve_loot_spawn_position(
			requested_position,
			world_position
		)
		pickup.pickup_requested.connect(_on_ground_loot_requested)
		# 怪物掉落、搜索产出和主动落地都先经过“抛高→落地→两次弹跳”；
		# 存档恢复不走这里，避免读档时把已经稳定的物品再次弹起。
		pickup.begin_spawn_animation()
		spawned += 1
	return spawned


## 本次掉落的散布半边长：件数越多越接近 2m × 2m，但受房间尺寸夹紧。
## 返回值仍沿用旧函数名，避免已有调用方和探针改动；它现在表示方形半边长。
func _loot_scatter_max_radius(room: DungeonRoom3D, item_count: int) -> float:
	var dimensions := room.get_dimensions()
	var room_half_min := maxf(0.0, minf(dimensions.x, dimensions.y) * 0.5 - 1.2)
	var count_ratio := sqrt(float(maxi(1, item_count)) / 6.0)
	return clampf(
		minf(loot_scatter_half_extent_m * count_ratio, room_half_min),
		LOOT_SCATTER_MIN_RADIUS_M,
		LOOT_SCATTER_HALF_EXTENT_M
	)


## 第 `index` 件的水平偏移（确定性，不掷骰）：按黄金角取方向，
## 再把圆形半径映射到正方形边界。这样每个候选点都满足
## `abs(x) <= half_extent` 且 `abs(z) <= half_extent`，总散布范围严格为 2m × 2m 内。
func _loot_scatter_offset(index: int, item_count: int, max_radius: float) -> Vector3:
	var half_extent := clampf(max_radius, LOOT_SCATTER_MIN_RADIUS_M, LOOT_SCATTER_HALF_EXTENT_M)
	var unit := clampf((float(index) + 0.5) / float(maxi(1, item_count)), 0.0, 1.0)
	var angle := float(index) * LOOT_SCATTER_GOLDEN_ANGLE + 0.35
	var direction := Vector2(cos(angle), sin(angle))
	var square_boundary_radius := half_extent / maxf(absf(direction.x), absf(direction.y))
	var radius := square_boundary_radius * sqrt(unit)
	return Vector3(direction.x, 0.0, direction.y) * radius


## 把「想要的落点」变成「真能站人的落点」：
## ① 先按想要的位置找支撑面（贴地）；② 该点在 0.45 m 高、0.30 m 半径内若被层 1 碰撞体占住
## （墙、箱柜、门框），就沿原点方向按 `LOOT_SCATTER_FALLBACK_SHRINK` 收缩重试；
## ③ 都占着才回到掉落原点本身 —— 宁可几件挤在一起，也不塞进阻挡里。
## 注意：净空只在**贴地校位之后**判，否则地板自己会把所有候选点判成「被占」。
func _resolve_loot_spawn_position(
	requested_world_position: Vector3,
	fallback_world_position: Vector3
) -> Vector3:
	var supported := _find_supported_spawn_position(requested_world_position, fallback_world_position)
	if _is_loot_landing_clear(supported):
		return supported
	var offset := requested_world_position - fallback_world_position
	for shrink_value in LOOT_SCATTER_FALLBACK_SHRINK:
		var probe := fallback_world_position + offset * float(shrink_value)
		var probe_supported := _find_supported_spawn_position(probe, fallback_world_position)
		if _is_loot_landing_clear(probe_supported):
			return probe_supported
	return _find_supported_spawn_position(fallback_world_position, fallback_world_position)


## 落点上方一小段空间里有没有静态阻挡（墙/家具/门框）。
## 只查层 1 的 body、不查 Area3D：掉落物自己的拾取区是 Area 且层 0，碰不到自己人。
func _is_loot_landing_clear(landing_world_position: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var shape := SphereShape3D.new()
	shape.radius = LOOT_SCATTER_CLEARANCE_RADIUS_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.transform = Transform3D(
		Basis.IDENTITY,
		landing_world_position + Vector3.UP * LOOT_SCATTER_CLEARANCE_HEIGHT_M
	)
	if player != null and is_instance_valid(player):
		query.exclude = [player.get_rid()]
	return world.direct_space_state.intersect_shape(query, 1).is_empty()


func _on_ground_loot_requested(pickup: GroundLootPickup3D, item: Dictionary) -> void:
	if not is_instance_valid(pickup) or not pickup.is_pickup_available() or not is_instance_valid(player):
		return
	var pickup_offset := player.global_position - pickup.global_position
	pickup_offset.y = 0.0
	# 剧情开场枪是可恢复的“一次性自动装备”实体。正式 Area3D 请求仍只能
	# 在拾取距离内发出；这里额外允许同房的恢复/重放事务完成交接，避免
	# 玩家下线后回到房间中心时，明明站在保留的枪旁边却无法完成剧情枪接管。
	var narrative_auto_equip := bool(item.get("narrative_auto_equip", false)) and str(item.get("type", "")) == "weapon"
	if pickup_offset.length() > pickup.get_pickup_distance_m() and not narrative_auto_equip:
		return
	if bool(item.get("is_currency", false)) or str(item.get("id", "")) == "__currency__":
		var granted := _grant_run_currency(int(item.get("count", 1)))
		if _map_fate_triggers != null:
			_map_fate_triggers.on_currency_collected(granted)
		pickup.accept_pickup(player)
		_queue_runtime_autosave("ground_loot_picked_up")
		status_label.text = "取得 %d 金币" % granted
		_refresh_loot_label()
		return
	var requested := maxi(1, int(item.get("count", 1)))
	# 开场剧情的武器是专门的"捡起即装备"物品：先完成正式武器实例装备，
	# 成功后再收掉地面实体，避免出现地面实体消失但武器没有落到槽位的半成功状态。
	if bool(item.get("narrative_auto_equip", false)) and str(item.get("type", "")) == "weapon":
		if player == null or not player.has_method("equip_weapon_item_to_slot"):
			status_label.text = "武器装备失败 · 物品留在地面"
			return
		# 先把旧主枪放入背包，再调用装备接口；满包时不会改主槽，装备拒绝时
		# 只恢复背包快照，不依赖一次可能再次失败的装备回滚。
		var old_item := player.get_equipped_weapon_item_for_slot(0)
		var inventory_before: Array = _inventory.get_slots_snapshot()
		if not old_item.is_empty() and _inventory.add_item(old_item, 1) != 1:
			_inventory.restore_slots_snapshot(inventory_before)
			status_label.text = "背包已满 · 无法替换当前武器，物品留在地面"
			return
		# 标记只属于这次地面拾取；失败时原实体不变，成功装备后不让
		# 玩家主动丢出的同一把枪再次触发剧情自动装备。
		var equipped_item := item.duplicate(true)
		equipped_item.erase("narrative_auto_equip")
		var equip_result := player.equip_weapon_item_to_slot(equipped_item, 0)
		if not bool(equip_result.get("success", false)):
			_inventory.restore_slots_snapshot(inventory_before)
			status_label.text = "%s · 物品留在地面" % str(equip_result.get("reason", "武器装备失败"))
			return
		pickup.accept_pickup(player)
		_queue_runtime_autosave("ground_loot_weapon_auto_equipped")
		status_label.text = "已装备 %s" % WeaponDropGrade.label_for(item)
		_refresh_loot_label()
		return
	var added := _inventory.add_item(item, requested)
	if added <= 0:
		status_label.text = "背包已满 · %s 留在地面" % WeaponDropGrade.label_for(item)
		return
	if added >= requested:
		pickup.accept_pickup(player)
	else:
		pickup.item_data["count"] = requested - added
	_queue_runtime_autosave("ground_loot_picked_up")
	status_label.text = "拾取 %s x%d%s" % [
		WeaponDropGrade.label_for(item),
		added,
		" · 按 I 打开背包，左键装备" if str(item.get("type", "")) == "weapon" else "",
	]
	_refresh_loot_label()


func _grant_run_currency(amount: int) -> int:
	var granted := maxi(0, int(round(float(maxi(0, amount)) * _world_currency_multiplier)))
	if granted > 0:
		GameManager.add_currency(granted)
	return granted


func _drop_inventory_item_to_world(item: Dictionary, count: int) -> bool:
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if room == null or player == null or item.is_empty():
		return false
	var dropped := item.duplicate(true)
	dropped["count"] = maxi(1, count)
	_spawn_loot_items(
		room,
		[dropped],
		player.global_position + player.aim_direction * 1.55 + Vector3(0.0, 0.08, 0.0),
		0.65
	)
	var identity := ""
	if str(dropped.get("type", "")) == "weapon":
		identity = " #%s" % str(dropped.get("weapon_instance_id", "")).right(6).to_upper()
	status_label.text = "已丢弃 %s%s x%d · 完整物品留在当前房间" % [
		dropped.get("name", dropped.get("id", "物品")), identity, maxi(1, count),
	]
	return true


func _get_minimap_enemy_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var live_enemies: Array = []
	for value in _enemy_nodes_by_room.get(_current_room_id, []):
		# 已释放对象不能先做类型转换；先验证实例，避免 Godot 的 freed-object cast 报错。
		if value == null or not is_instance_valid(value):
			continue
		var enemy := value as Enemy3D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		if enemy.current_hp <= 0:
			continue
		live_enemies.append(enemy)
		result.append(enemy.global_position)
	_enemy_nodes_by_room[_current_room_id] = live_enemies
	return result


## 屏幕外怪物指示箭头的取数口：谁有资格被箭头指。
##
## 判据（四条，缺一不可）：
## 1. 活怪：`current_hp > 0` 且没在排队释放；
## 2. **已经醒着**：`Enemy3D.is_runtime_ai_active()`。门后还没进的房间、离玩家超过预激活半径
##    的怪一律休眠 ⇒ 不给箭头。潜行与门禁是设计的一部分，箭头不能隔墙把它报出来。
## 3. 与玩家同层：|Δy| ≤ 4.5 m（沿用 `Enemy3D.activate_from_player_proximity` 的楼板口径）；
## 4. 平面距离 ≤ 50 m（最大战斗房 65×65 的半对角线 ≈ 46 m，向上取整）。
##
## 另外显式排除"被藏起来的伏击怪"：它虽然已经醒着，但正趴在地下，箭头会毁掉伏击。
## 与 `_get_minimap_enemy_positions()` 的区别是刻意的：小地图只画当前房间（雷达口径），
## 箭头要覆盖"预激活圈内已经追着你跑的邻房怪"（改屏口径），所以这里按玩家半径取数。
func _get_offscreen_enemy_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	if player == null or not is_instance_valid(player):
		return result
	var origin := player.global_position
	for node in get_tree().get_nodes_in_group(Enemy3D.GROUP_ENEMY_3D):
		var enemy := node as Enemy3D
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		# 只认本战局里的怪：别处（基地区域、训练场）残留的敌人物体不算。
		if not is_ancestor_of(enemy) or enemy.current_hp <= 0:
			continue
		if not enemy.is_runtime_ai_active() or enemy.is_concealed_in_world():
			continue
		var offset := enemy.global_position - origin
		if absf(offset.y) > OFFSCREEN_INDICATOR_FLOOR_TOLERANCE_M:
			continue
		if Vector2(offset.x, offset.z).length() > OFFSCREEN_INDICATOR_RANGE_M:
			continue
		result.append(enemy.global_position + Vector3.UP * OFFSCREEN_INDICATOR_TARGET_HEIGHT_M)
	return result


func _on_service_activated(_room: DungeonRoom3D, station: ServiceStation3D) -> void:
	match station.station_type:
		"merchant":
			_open_merchant(_room.room_id if _room != null else "")
		"upgrade":
			_open_workbench()
		"event":
			_resolve_event_room(_room)
	_refresh_loot_label()


## 玩家自己按下的灯开关，由玩家自己嘟囔一句（3 套随机文案）。
## 剧情系统尚未建立前的最小直连实现：只做"开灯 → 说话"，不改任何玩法状态。
## 台词取自 BarkCatalog，逻辑侧不出现文本字面量。
func _on_room_light_toggled(_room: DungeonRoom3D, is_on: bool) -> void:
	var bark := _ensure_player_bark()
	if bark == null:
		return
	bark.say_bark(BarkCatalog.BARK_LAMP_ON if is_on else BarkCatalog.BARK_LAMP_OFF)


## 玩家身上的说话能力按需挂载；重复调用复用同一个实例。
func _ensure_player_bark() -> CharacterBark3D:
	if player == null or not is_instance_valid(player):
		return null
	var existing := player.get_node_or_null("CharacterBark3D") as CharacterBark3D
	if existing != null:
		return existing
	return CharacterBark3D.attach_to(player, PLAYER_BARK_HEIGHT_M)


func _open_workbench() -> void:
	if _workbench_panel != null and is_instance_valid(_workbench_panel):
		return
	_workbench_panel = WORKBENCH_SCENE.instantiate() as WorkbenchPanel
	_workbench_panel.set_player(player)
	_workbench_panel.set_workbench_ref(self)
	$HUD.add_child(_workbench_panel)
	_close_inventory_for_modal()
	_sync_player_input_lock()
	status_label.text = "改造台：投入武器与弹药模块熔炼，产出品质与弹种重掷的新枪"


func _open_merchant(merchant_id: String = "") -> void:
	if _merchant_ui != null and is_instance_valid(_merchant_ui):
		return
	if _merchant_stock_restore_failed:
		status_label.text = "商人货架存档无效 · 已暂停交易"
		return
	if merchant_id.is_empty():
		merchant_id = _current_room_id
	if merchant_id.is_empty():
		status_label.text = "商人房间身份缺失"
		return
	if _merchant_service == null:
		_merchant_service = RUN_MERCHANT_SERVICE_SCRIPT.new()
	var was_new_stock := not _merchant_service.has_stock(merchant_id)
	var stock_before := _merchant_service.export_stock_snapshot()
	var goods: Array[Dictionary] = []
	if was_new_stock:
		goods = _loot_module.generate_merchant_goods(maxi(1, visual_theme.difficulty_rank), 6)
	var session_id := "%s:merchant:%d" % [_run_id, Time.get_ticks_usec()]
	var opened := _merchant_service.open_session(session_id, merchant_id, goods)
	if not bool(opened.get("success", false)):
		status_label.text = "商人会话无法开启"
		return
	if was_new_stock:
		var persisted := false
		if _runtime_persistence_active and BaseManager != null:
			persisted = BaseManager.flush_runtime_checkpoint("run_merchant_stock_opened")
		elif test_mode:
			persisted = true
		if not persisted:
			_merchant_service.restore_stock_snapshot(stock_before)
			status_label.text = "商人货架保存失败 · 请重试"
			return
	_merchant_ui = MerchantUI.new()
	_merchant_ui.name = "MerchantUI3D"
	_merchant_ui.set_anchors_preset(Control.PRESET_CENTER)
	_merchant_ui.offset_left = -300
	_merchant_ui.offset_top = -220
	_merchant_ui.offset_right = 300
	_merchant_ui.offset_bottom = 220
	_merchant_ui.set_tier(maxi(1, visual_theme.difficulty_rank))
	_merchant_ui.set_shop_name("%s · 废土拾荒商" % gameplay_theme.display_name)
	$HUD.add_child(_merchant_ui)
	_merchant_ui.purchase_command_requested.connect(_on_merchant_purchase_command)
	_merchant_ui.merchant_closed.connect(_on_merchant_closed)
	_merchant_ui.show_offers(session_id, _merchant_service.get_offers_snapshot())
	_close_inventory_for_modal()
	_sync_player_input_lock()
	status_label.text = "拾荒商已接入 · 购买会占用真实背包格"


func _on_merchant_purchase_command(
	session_id: String, offer_id: String, weapon_instance_id: String
) -> void:
	if _merchant_service == null:
		return
	var result := _merchant_service.purchase(
		session_id, offer_id, weapon_instance_id, _inventory, GameManager,
		Callable(self, "_commit_merchant_purchase_checkpoint"),
		Callable(self, "_merchant_weapon_instance_already_owned")
	)
	if not bool(result.get("success", false)):
		status_label.text = "商人交易失败：%s" % str(result.get("code", "unknown"))
		return
	var item := result.get("item", {}) as Dictionary
	if _merchant_ui != null and is_instance_valid(_merchant_ui):
		_merchant_ui.update_offers(_merchant_service.get_offers_snapshot())
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	_ensure_conditional_extraction("TRADE", room, Vector3(-4.0, 0.0, 3.0))
	status_label.text = "购入 %s · 交易撤离条件已解锁" % item.get("name", "物品")


func _commit_merchant_purchase_checkpoint() -> bool:
	var was_unlocked := _trade_extraction_unlocked
	var previous_room_id := _trade_extraction_room_id
	_trade_extraction_unlocked = true
	_trade_extraction_room_id = _current_room_id
	if not _runtime_persistence_active:
		return true
	if BaseManager != null and BaseManager.flush_runtime_checkpoint("run_merchant_purchase"):
		return true
	_trade_extraction_unlocked = was_unlocked
	_trade_extraction_room_id = previous_room_id
	return false


func _merchant_weapon_instance_already_owned(instance_id: String) -> bool:
	if instance_id.is_empty():
		return false
	if _inventory != null and _inventory.has_weapon_instance(instance_id):
		return true
	if _insurance != null and _insurance.has_weapon_instance(instance_id):
		return true
	if _quick_inventory != null and _quick_inventory.has_weapon_instance(instance_id):
		return true
	if player != null:
		for slot_index in range(2):
			if player.get_equipped_weapon_instance_id_for_slot(slot_index) == instance_id:
				return true
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and is_ancestor_of(value):
			if str((value as GroundLootPickup3D).item_data.get("weapon_instance_id", "")) == instance_id:
				return true
	return false


func _on_merchant_closed() -> void:
	if _merchant_service != null:
		_merchant_service.close_session()
	if _merchant_ui != null and is_instance_valid(_merchant_ui):
		var closing := _merchant_ui
		get_tree().create_timer(0.3).timeout.connect(closing.queue_free)
	_merchant_ui = null
	_sync_player_input_lock()


func _on_run_currency_changed(amount: int) -> void:
	_run_value = amount
	_refresh_loot_label()
	_queue_runtime_autosave("currency_changed")


func _resolve_event_room(room: DungeonRoom3D) -> void:
	if room == null or _resolved_event_rooms.has(room.room_id):
		status_label.text = "本房事件已经结算"
		return
	_resolved_event_rooms[room.room_id] = true
	var event_station := room.get_service_station("event")
	if event_station != null:
		event_station.set_objective_resolved()
	var event_id: String = ["CURSE", "BLESSING", "TRADE", "GAMBLE", "REVEAL", "SUMMON"][_rng.randi_range(0, 5)]
	match event_id:
		"CURSE":
			room.cleared = false
			_event_combat_rooms[room.room_id] = true
			_spawn_room_enemies(room)
			for value in _enemy_nodes_by_room.get(room.room_id, []):
				if is_instance_valid(value) and value is Enemy3D:
					(value as Enemy3D).contact_damage = int((value as Enemy3D).contact_damage * 1.15)
			status_label.text = "诅咒降临：额外敌群伤害 +15%，清除后结算"
			return
		"BLESSING":
			player.apply_damage_buff("event_blessing", 0.10)
			get_tree().create_timer(60.0).timeout.connect(player.remove_damage_buff.bind("event_blessing"))
			status_label.text = "祝福降临：武器伤害 +10%，持续 60 秒"
		"TRADE":
			if FateCardGameBridge.get_card_count() > 0:
				var reward := _rng.randi_range(30, 80)
				var granted := _grant_run_currency(reward)
				status_label.text = "命运交易完成：获得 %d 金币" % granted
			else:
				status_label.text = "命运交易取消：尚无已应用卡片"
		"GAMBLE":
			if GameManager.currency < 20:
				status_label.text = "赌局取消：至少需要 20 金币"
			else:
				var bet := clampi(GameManager.currency / 2, 20, 100)
				GameManager.spend_currency(bet)
				if _rng.randf() < 0.5:
					var multiplier := _rng.randi_range(2, 5)
					var granted := _grant_run_currency(bet * multiplier)
					status_label.text = "赌局胜利：投入 %d，获得 %d 金币" % [bet, granted]
				else:
					status_label.text = "赌局失败：损失 %d 金币" % bet
		"REVEAL":
			_reveal_nearby_rooms(room.room_id, 2)
			status_label.text = "地图揭示：周围房间类型已标记"
		"SUMMON":
			room.cleared = false
			_event_combat_rooms[room.room_id] = true
			_spawn_room_enemies(room)
			status_label.text = "亡者召唤：额外敌群出现，击杀后获得掉落"
			return
	# 本房若还压着编排战斗（自带触发盒的「事件 + 战斗」双职房），结算事件不足以放行 ——
	# 必须等敌群清空，由波次链的 `_repair_hostile_room_progress` 负责清房 / 开门。
	# 纯事件房（`_event_combat_rooms` 为空）此判据恒 false ⇒ 原行为逐字不变。
	if _event_combat_rooms.has(room.room_id) and _room_has_pending_combat(room):
		status_label.text = "事件已结算 · 异常敌群尚未肃清，清除后方可放行"
		return
	_mark_room_cleared(room, true)


func _reveal_nearby_rooms(origin_id: String, depth: int, hide_room_types: bool = false) -> void:
	var frontier: Array[String] = [origin_id]
	var visited := {origin_id: true}
	for _step in range(maxi(1, depth)):
		var next: Array[String] = []
		for room_id in frontier:
			for neighbor in _room_neighbors.get(room_id, []):
				var neighbor_id := str(neighbor)
				if visited.has(neighbor_id):
					continue
				visited[neighbor_id] = true
				next.append(neighbor_id)
				minimap.reveal_room(neighbor_id, hide_room_types)
		frontier = next


func trigger_extra_wave(effect: Dictionary = {}) -> Dictionary:
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if _completed or room == null or room.cleared or not _room_wave_totals.has(_current_room_id):
		return {"success": false, "error": "room_not_in_combat", "message": "当前房间不在战斗中，未消耗命运"}
	if _room_fate_wave_queued.has(room.room_id):
		return {"success": false, "error": "fate_wave_already_queued", "message": "本房已接受命运增援"}
	var configs: Array[Dictionary] = []
	if bool(effect.get("spawn_elite", false)):
		configs = _reserve_fate_elite(room, "reinforce")
	else:
		configs.assign(_monster_injector.generate_enemies({
			"type": "ambush", "count": int(effect.get("spawn_count", 3)),
			"floor": maxi(1, visual_theme.difficulty_rank), "floor_level": 0,
		}))
	if configs.is_empty():
		return {"success": false, "error": "reinforcement_unavailable", "message": "没有可用增援，未消耗命运"}
	for config in configs:
		config["fate_kill_currency"] = int(effect.get("clear_currency", 0))
	_room_fate_wave_queued[room.room_id] = true
	(_room_wave_queues[room.room_id] as Array).append(configs)
	_room_wave_totals[room.room_id] = int(_room_wave_totals[room.room_id]) + 1
	_update_wave_hud(room.room_id)
	_schedule_room_wave_intermission(room.room_id)
	status_label.text = "命运增援已排队 · 本房最多追加一波"
	return {"success": true, "message": status_label.text}


func _reserve_fate_elite(room: DungeonRoom3D, source: String) -> Array[Dictionary]:
	_fate_elite_reservation_serial += 1
	return _monster_injector.generate_enemies({
		"type": "elite", "floor": maxi(1, visual_theme.difficulty_rank), "floor_level": 0,
		"floor_number": _elite_floor_number(room), "seed": run_seed,
		"encounter_id": "%s:fate:%s:%d" % [_elite_encounter_id(room), source, _fate_elite_reservation_serial],
	})


func set_next_chest_quality_boost(boost: int) -> void:
	_next_chest_quality_boost += boost


func set_extra_loot_next_chest(enabled: bool) -> void:
	_extra_loot_next_chest_count = maxi(_extra_loot_next_chest_count, 1 if enabled else 0)


func _on_fate_scope_state_changed(_scope: String, _stable_card_id: String) -> void:
	# 此信号只通知显示层；规则由有失败返回的命令入口一次执行。
	pass


func apply_world_fate_card(card: FateCard) -> Dictionary:
	if card == null or card.scope != FateCard.Scope.WORLD or _completed:
		return {"success": false, "error": "invalid_world_card", "message": "当前不能应用世界命运"}
	var effect := card.effect
	match card.stable_card_id:
		"fate_reinforce":
			return trigger_extra_wave(effect)
		"fate_curse_map":
			return apply_curse_to_current_room(float(effect.get("enemy_damage_multiplier", effect.get("damage_multiplier", 1.15))), float(effect.get("currency_multiplier", 1.0)))
		"fate_lucky_chest", "fate_extra_loot":
			_next_chest_quality_boost += int(effect.get("quality_boost", 0))
			_extra_loot_next_chest_count += int(effect.get("extra_count", 1 if card.stable_card_id == "fate_extra_loot" else 0))
		"fate_sun_quality":
			_next_chest_quality_boost += int(effect.get("tiers", 1))
		"fate_sun_extra_loot":
			_extra_loot_next_chest_count += maxi(0, int(effect.get("count", 1)))
			if effect.has("max_rarity"):
				_next_chest_max_rarity = str(effect["max_rarity"]).to_lower()
		"fate_sun_reinforce":
			if int(effect.get("elite_count", 0)) > 0:
				var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
				if room == null:
					return {"success": false, "error": "room_missing", "message": "没有当前楼层"}
				var elites := _reserve_fate_elite(room, "emperor")
				if elites.is_empty():
					return {"success": false, "error": "elite_unavailable", "message": "当前楼层无可用精英，未消耗命运"}
				_next_room_elite_configs.append_array(elites)
				_next_room_clear_currency += int(effect.get("clear_currency", 0))
			else:
				_next_room_enemy_count += maxi(0, int(effect.get("count", 0)))
		"fate_sun_reveal":
			_reveal_nearby_rooms(_current_room_id, int(effect.get("radius", 1)), bool(effect.get("hide_room_types", false)))
		"fate_sun_key":
			if bool(effect.get("temporary_floor_only", false)):
				_temporary_key_floor = _fate_floor_key(_room_by_id.get(_current_room_id) as DungeonRoom3D)
				_temporary_room_keys += maxi(0, int(effect.get("count", 1)))
			else:
				_room_key_count += maxi(0, int(effect.get("count", 1)))
			_refresh_loot_label()
		"fate_sun_currency":
			_world_currency_multiplier *= maxf(0.0, float(effect.get("multiplier", 1.0)))
			if int(effect.get("quality_every", 0)) > 0:
				_fate_drop_quality_rules.append({"every": int(effect["quality_every"]), "tiers": int(effect.get("quality_tiers", 1)), "count": 0})
		"fate_sun_scorch":
			_next_room_enemy_hp_multiplier *= maxf(0.01, float(effect.get("multiplier", 1.0)))
			_next_room_enemy_damage_multiplier *= maxf(0.0, float(effect.get("damage_multiplier", 1.0)))
		"fate_sun_trial":
			_next_room_enemy_damage_multiplier *= maxf(0.0, float(effect.get("damage_multiplier", 1.0)))
			_next_room_currency_multiplier *= maxf(0.0, float(effect.get("currency_multiplier", 1.0)))
		"fate_sun_bounty":
			_fate_bounty_queues.append({"rooms": int(effect.get("rooms", 0)), "amount": int(effect.get("amount", 0)), "zero_rooms": int(effect.get("zero_currency_rooms_after", 0))})
		"fate_sun_extraction":
			var multiplier := maxf(0.01, float(effect.get("multiplier", 1.0)))
			_extraction_time_multiplier *= multiplier
			_extraction_enemy_speed_multiplier *= maxf(0.01, float(effect.get("enemy_speed_multiplier", 1.0)))
			for beacon_value in get_tree().get_nodes_in_group("extraction_beacon_3d"):
				var beacon := beacon_value as ExtractionBeacon3D
				if beacon != null and is_ancestor_of(beacon):
					beacon.apply_fate_time_multiplier(multiplier)
		_:
			return {"success": false, "error": "unsupported_world_card", "message": "世界命运尚无执行器"}
	return {"success": true, "message": "已应用世界命运：%s" % card.card_name}


func reset_world_fate_state() -> void:
	_next_chest_quality_boost = 0
	_extra_loot_next_chest_count = 0
	_next_chest_max_rarity = ""
	_next_room_enemy_count = 0
	for config in _next_room_elite_configs:
		EliteRosterService.settle(str(config.get("elite_id", "")), str(config.get("encounter_instance_id", "")), "despawned")
	_next_room_elite_configs.clear()
	_next_room_clear_currency = 0
	_next_room_enemy_hp_multiplier = 1.0
	_next_room_enemy_damage_multiplier = 1.0
	_next_room_currency_multiplier = 1.0
	_world_currency_multiplier = 1.0
	_temporary_room_keys = 0
	_temporary_key_floor = ""
	_fate_visited_rooms.clear()
	_room_fate_wave_queued.clear()
	_fate_elite_reservation_serial = 0
	_fate_bounty_queues.clear()
	_fate_drop_quality_rules.clear()
	_room_fate_bounties.clear()
	_room_fate_clear_currency.clear()
	_room_zero_currency.clear()
	_room_enemy_hp_multipliers.clear()
	_room_enemy_damage_multipliers.clear()
	_room_currency_multipliers.clear()
	_extraction_enemy_speed_multiplier = 1.0
	_update_fate_extraction_slow()
	for beacon_value in get_tree().get_nodes_in_group("extraction_beacon_3d"):
		var beacon := beacon_value as ExtractionBeacon3D
		if beacon != null and is_ancestor_of(beacon):
			beacon.apply_fate_time_multiplier(1.0 / _extraction_time_multiplier)
	_extraction_time_multiplier = 1.0


const WORLD_FATE_SAVE_DEFAULTS := {
	"_next_chest_quality_boost": 0, "_extra_loot_next_chest_count": 0, "_next_chest_max_rarity": "",
	"_next_room_enemy_count": 0, "_next_room_elite_configs": [], "_fate_elite_reservation_serial": 0,
	"_next_room_clear_currency": 0, "_next_room_enemy_hp_multiplier": 1.0,
	"_next_room_enemy_damage_multiplier": 1.0, "_next_room_currency_multiplier": 1.0,
	"_world_currency_multiplier": 1.0, "_temporary_room_keys": 0, "_temporary_key_floor": "",
	"_fate_visited_rooms": {}, "_fate_bounty_queues": [], "_fate_drop_quality_rules": [],
	"_room_fate_bounties": {}, "_room_fate_clear_currency": {}, "_room_zero_currency": {},
	"_room_enemy_hp_multipliers": {}, "_room_enemy_damage_multipliers": {}, "_room_currency_multipliers": {},
	"_room_fate_wave_queued": {}, "_extraction_time_multiplier": 1.0, "_extraction_enemy_speed_multiplier": 1.0,
}


func export_world_fate_snapshot() -> Dictionary:
	var state: Dictionary = {}
	for key in WORLD_FATE_SAVE_DEFAULTS:
		var value: Variant = get(key)
		state[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	var exploration: Dictionary = {}
	for key in ["_revealed", "_hidden_room_types", "_visited_room_types"]:
		exploration[key] = minimap.get(key).duplicate(true)
	var triggers: Dictionary = {}
	if _map_fate_triggers != null:
		for type in MapFateTriggers.TriggerType.values():
			triggers[str(type)] = {
				"count": _map_fate_triggers._counters.get(type, 0),
				"used": _map_fate_triggers._triggered_this_run.get(type, false),
				"age": maxf(0.0, Time.get_ticks_msec() / 1000.0 - float(_map_fate_triggers._last_trigger_time.get(type, -999.0))),
			}
	return {"version": 1, "state": state, "exploration": exploration, "triggers": triggers}


func import_world_fate_snapshot(value: Variant) -> bool:
	var previous_time := _extraction_time_multiplier
	# 恢复不是退役精英预约：不调用会 settle 的 reset_world_fate_state。
	for key in WORLD_FATE_SAVE_DEFAULTS:
		var initial: Variant = WORLD_FATE_SAVE_DEFAULTS[key]
		if initial is Array:
			get(key).clear()
		elif initial is Dictionary:
			set(key, initial.duplicate(true))
		else:
			set(key, initial)
	for beacon_value in get_tree().get_nodes_in_group("extraction_beacon_3d"):
		if beacon_value is ExtractionBeacon3D and is_ancestor_of(beacon_value):
			beacon_value.apply_fate_time_multiplier(1.0 / maxf(0.01, previous_time))
	if not value is Dictionary or value.get("version", 0) != 1:
		return false
	var state := Player3D.read_fate_snapshot_fields(value.get("state"), WORLD_FATE_SAVE_DEFAULTS, ["_next_chest_quality_boost", "_extra_loot_next_chest_count"])
	if state.is_empty() or state["_next_chest_max_rarity"] not in ["", "common", "uncommon", "rare", "epic", "legendary"]:
		return false
	for key in ["_next_room_enemy_hp_multiplier", "_extraction_time_multiplier", "_extraction_enemy_speed_multiplier"]:
		if float(state[key]) <= 0.0:
			return false
	for key in WORLD_FATE_SAVE_DEFAULTS:
		if not WORLD_FATE_SAVE_DEFAULTS[key] is Dictionary:
			continue
		for id in state[key]:
			var flag: bool = key in ["_fate_visited_rooms", "_room_zero_currency", "_room_fate_wave_queued"]
			if not id is String or id.is_empty() or (flag and state[key][id] != true) or (not flag and not Player3D.is_fate_snapshot_number(state[key][id], 0, 2147483647)):
				return false
	for key in ["_fate_bounty_queues", "_fate_drop_quality_rules"]:
		var defaults: Dictionary = {"rooms": 0, "amount": 0, "zero_rooms": 0} if key == "_fate_bounty_queues" else {"every": 1, "tiers": 0, "count": 0}
		var rules: Array[Dictionary] = []
		for row in state[key]:
			var rule := Player3D.read_fate_snapshot_fields(row, defaults)
			if rule.is_empty() or (key == "_fate_drop_quality_rules" and rule["every"] < 1):
				return false
			rules.append(rule)
		state[key] = rules
	for config in state["_next_room_elite_configs"]:
		if not config is Dictionary or not config.get("elite_id") is String or not config.get("encounter_instance_id") is String or config.get("elite_id", "").is_empty() or config.get("encounter_instance_id", "").is_empty():
			return false
		for key in ["hp", "max_hp", "damage", "speed", "floor"]:
			if not Player3D.is_fate_snapshot_number(config.get(key, 0), 0, 2147483647):
				return false
	var exploration := Player3D.read_fate_snapshot_fields(value.get("exploration", {}), {"_revealed": {}, "_hidden_room_types": {}, "_visited_room_types": {}})
	if exploration.is_empty():
		return false
	var triggers := value.get("triggers", {}) as Dictionary
	if not triggers.is_empty() and _map_fate_triggers != null:
		for type in MapFateTriggers.TriggerType.values():
			var row := triggers.get(str(type), {}) as Dictionary
			if row.is_empty() or not Player3D.is_fate_snapshot_number(row.get("count"), 0, 2147483647, true) or row.get("used") not in [true, false] or not Player3D.is_fate_snapshot_number(row.get("age"), 0.0, 315360000.0):
				return false
	for key in exploration:
		for id in exploration[key]:
			if not id is String or exploration[key][id] != true:
				return false
	for key in state:
		if WORLD_FATE_SAVE_DEFAULTS[key] is Array:
			get(key).assign(state[key])
		else:
			set(key, state[key])
	for key in exploration:
		minimap.set(key, exploration[key].duplicate(true))
	if not triggers.is_empty() and _map_fate_triggers != null:
		for type in MapFateTriggers.TriggerType.values():
			var row := triggers[str(type)] as Dictionary
			_map_fate_triggers._counters[type] = int(row["count"])
			_map_fate_triggers._triggered_this_run[type] = bool(row["used"])
			_map_fate_triggers._last_trigger_time[type] = Time.get_ticks_msec() / 1000.0 - float(row["age"])
	minimap.queue_redraw()
	for beacon_value in get_tree().get_nodes_in_group("extraction_beacon_3d"):
		if beacon_value is ExtractionBeacon3D and is_ancestor_of(beacon_value):
			beacon_value.apply_fate_time_multiplier(_extraction_time_multiplier)
	return true


func get_world_fate_snapshot() -> Dictionary:
	return {
		"next_chest_quality": _next_chest_quality_boost,
		"next_chest_extra": _extra_loot_next_chest_count,
		"next_room_enemy_count": _next_room_enemy_count,
		"next_room_enemy_hp_multiplier": _next_room_enemy_hp_multiplier,
		"next_room_enemy_damage_multiplier": _next_room_enemy_damage_multiplier,
		"next_room_currency_multiplier": _next_room_currency_multiplier,
		"currency_multiplier": _world_currency_multiplier,
		"bounty_queues": _fate_bounty_queues.duplicate(true),
		"temporary_keys": _temporary_room_keys,
		"next_room_elite_count": _next_room_elite_configs.size(),
		"next_chest_max_rarity": _next_chest_max_rarity,
		"extraction_time_multiplier": _extraction_time_multiplier,
	}


func apply_curse_to_current_room(damage_multiplier: float, currency_multiplier: float = 1.0) -> Dictionary:
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if room == null or room.cleared or not _room_wave_totals.has(_current_room_id):
		return {"success": false, "error": "room_not_in_combat", "message": "当前没有可诅咒的战斗，未消耗命运"}
	_room_enemy_damage_multipliers[_current_room_id] = float(_room_enemy_damage_multipliers.get(_current_room_id, 1.0)) * damage_multiplier
	_room_currency_multipliers[_current_room_id] = float(_room_currency_multipliers.get(_current_room_id, 1.0)) * currency_multiplier
	for value in _enemy_nodes_by_room.get(_current_room_id, []):
		if not is_instance_valid(value):
			continue
		var enemy := value as Enemy3D
		if enemy != null and enemy.ai_state != "dead":
			enemy.contact_damage = maxi(0, int(round(enemy.contact_damage * damage_multiplier)))
	return {"success": true, "message": "本房所有波次诅咒已生效"}


func apply_bless_dead(hp_threshold: float, survive_duration: float, damage_bonus: float) -> void:
	player.apply_character_fate_modifier({"modifier": "survival_blessing", "hp_threshold": hp_threshold, "survive_duration": survive_duration, "damage_bonus": damage_bonus})


func _tick_bless_dead(delta: float) -> void:
	if not _completed and player != null:
		player.update_fate_survival(delta)
	_update_fate_extraction_slow()


func _fate_floor_key(room: DungeonRoom3D) -> String:
	return str(room.get_meta("floor_number", room.position.y)) if room != null else ""


func _expire_temporary_room_keys(floor_key: String) -> void:
	if _temporary_room_keys > 0 and floor_key != _temporary_key_floor:
		_temporary_room_keys = 0
		_temporary_key_floor = ""
		_refresh_loot_label()


func _update_fate_extraction_slow() -> void:
	for value in $ActiveEnemies.get_children():
		var enemy := value as Enemy3D
		if enemy == null or enemy.ai_state == "dead":
			continue
		var multiplier := 1.0
		if not is_equal_approx(_extraction_enemy_speed_multiplier, 1.0):
			for beacon_value in get_tree().get_nodes_in_group("extraction_beacon_3d"):
				var beacon := beacon_value as ExtractionBeacon3D
				if beacon != null and is_ancestor_of(beacon) and beacon.is_in_active_sync_area(enemy.global_position):
					multiplier = _extraction_enemy_speed_multiplier
					break
		var previous := float(enemy.get_meta("fate_extraction_speed", 1.0))
		if not is_equal_approx(previous, multiplier):
			enemy.move_speed = enemy.move_speed / previous * multiplier
			enemy.set_meta("fate_extraction_speed", multiplier)


func handle_esc() -> void:
	if _workbench_panel != null and is_instance_valid(_workbench_panel):
		_workbench_panel.queue_free()
	_workbench_panel = null
	_sync_player_input_lock()


## 本房首领是否**已被击杀**。与 `room.cleared` 是两条独立事实：
## Boss 倒下后增援可能还在跑，此时本函数为 true、`room.cleared` 仍为 false。
func is_room_boss_defeated(room_id: String) -> bool:
	return bool(_boss_defeated_rooms.get(room_id, false))


## 登记首领阵亡。幂等 —— 重复登记不重复发信号（下游据此开闸，重放会让护栏
## 在「已开」与「再开」之间抖动）。
func _mark_room_boss_defeated(room_id: String) -> void:
	if room_id.is_empty() or is_room_boss_defeated(room_id):
		return
	_boss_defeated_rooms[room_id] = true
	room_boss_defeated.emit(room_id)


func _mark_room_cleared(room: DungeonRoom3D, spawn_key: bool) -> void:
	if room == null:
		return
	var was_cleared := room.cleared
	room.cleared = true
	# 小地图的绿色弹夹标记（原作"已清 + 可传送"那个图形）只认这一处状态，
	# 不另立一套"清理"口径 —— 否则地图上的"已清"和玩法里的"已清"会分叉。
	if minimap != null:
		minimap.mark_room_cleared(room.room_id)
	# 踩点遭遇的房间：肃清即解封 —— 门扇恢复可交互，玩家可以开门离开。
	_room_encounter_active.erase(room.room_id)
	set_room_seal(room.room_id, false)
	# 解封之后的关卡级收尾钩子（基类空实现）。
	# flow 关卡在这里把门**自动推开** —— EGT 清完怪门就开，不需要玩家按 E。
	# 放在 `set_room_seal(false)` 之后：钩子里要用"已解封"的状态去推门。
	_on_room_unsealed(room)
	if _boss_reinforcement_states.has(room.room_id):
		(_boss_reinforcement_states[room.room_id] as Dictionary)["stopped"] = true
	_cancel_room_wave_intermission(room.room_id)
	_update_wave_hud(room.room_id)
	if not was_cleared:
		player.on_fate_room_cleared(room.room_id)
		room_cleared.emit(room)
		# 传送支线的两道锁都吃「已清内容房数」：
		#   · 入口木板：入口房清完才可破（设计 §5.2）
		#   · 撤离门：已清 ≥ ceil(总数×0.4) 解锁（设计 §6.2）
		# 放在这里而不是每帧轮询 —— 这两个值只会随清房变化。
		_refresh_secret_locks_after_clear()
		var clear_report := _reward_coordinator.resolve_clear(
			room.reward_plan,
			maxi(1, visual_theme.difficulty_rank),
			"room_clear:%s" % room.room_id
		)
		_deliver_ground_rewards(
			room, clear_report.get("grants", []), room.global_position,
			"clear:%s" % room.room_id
		)
	if not was_cleared:
		var bounty := int(_room_fate_bounties.get(room.room_id, 0)) + int(_room_fate_clear_currency.get(room.room_id, 0))
		_grant_run_currency(bounty)
		_refresh_loot_label()
	if spawn_key and not was_cleared:
		call_deferred("_ensure_room_key_reward", room)


## 本房该不该产出「房间钥匙」奖励（= 本房的门是否消耗钥匙）。
## （同一判据也给 HUD 目标文案用：不消耗钥匙时不提「用钥匙开门」。）
## 钥匙的唯一用途是开下一扇门；若本房所有门都不消耗钥匙（和平区如 98F 区块00），
## 钥匙就是永远用不掉的垃圾道具 —— 必须一并不发。
## ⛔ 这里必须**自检**，不能只信调用方的 `spawn_key` 形参：
## `_on_room_entered()` 的「重进已探索房间」分支是无条件调用本函数的，
## 于是玩家回头走一趟刚清过的和平区，地上就会掉出一把钥匙（2026-09-22 人报截图）。
func _room_produces_room_key(room: DungeonRoom3D) -> bool:
	if room == null:
		return false
	if room.authored_layout_peaceful:
		return false
	var declared: Dictionary = room.door_policies
	var targets: Dictionary = room.door_targets
	for direction in declared.keys():
		# ⛔ 只认「有实际去向」的门。`door_targets[direction]` 为空 = 该侧是安全房壳体的
		# 「封闭抵达门 / [E] 退出战局门」：它不经 `_try_open_room_door()`、从不消耗钥匙
		# （`verify_expedition_level01_flow._verify_safe_room` 按这个口径断言「唯一封闭抵达门」）。
		# 旧实现把它连同 `_door_policies_for_record()` 给的 `requires_key: true` 一起算进来，
		# 于是整间入口安全房被判成产钥匙房 —— 进房即刻白掉一把**永远用不掉**的钥匙
		# （前门 → room_01 是免费通行，退出门又不吃钥匙）。2026-10-12 人报「安全房默认刷钥匙」。
		if str(targets.get(direction, "")).is_empty():
			continue
		if bool((declared[direction] as Dictionary).get("requires_key", true)):
			return true
	return declared.is_empty()


func _ensure_room_key_reward(room: DungeonRoom3D) -> void:
	if (
		room == null
		or not is_instance_valid(room)
		or not room.cleared
		or not _room_produces_room_key(room)
		or room.room_type in ["START", "EXTRACTION", "FACILITY", "ELEVATOR"]
		or _spawned_key_rooms.has(room.room_id)
	):
		return
	_spawn_room_key(room)


func _spawn_room_key(room: DungeonRoom3D) -> void:
	if room == null or not is_instance_valid(room) or _spawned_key_rooms.has(room.room_id):
		return
	var reward_report := _reward_coordinator.resolve_fixed_item(
		"item_room_key", 1, "room_clear_key:%s" % room.room_id, maxi(1, visual_theme.difficulty_rank)
	)
	if not bool(reward_report.get("ok", false)) or (reward_report.get("grants", []) as Array).is_empty():
		push_error("Room key reward rejected by RewardService: %s" % str(reward_report.get("errors", [])))
		return
	var key := KEY_SCRIPT.new() as RoomKeyPickup3D
	key.configure(room.room_id)
	room.add_child(key)
	var spawn_position := Vector3(0, 0.05, -2.2)
	if player != null and is_instance_valid(player) and _current_room_id == room.room_id:
		var player_local := room.to_local(player.global_position)
		player_local.y = 0.05
		var toward_center := Vector3(-player_local.x, 0, -player_local.z)
		if toward_center.length_squared() <= 0.001:
			var fallback_angle := fmod(float(room.room_seed) * 0.731, TAU)
			toward_center = Vector3(cos(fallback_angle), 0, sin(fallback_angle))
		spawn_position = player_local + toward_center.normalized() * 2.2
	var dimensions := room.get_dimensions()
	var safe_half_x := maxf(1.0, dimensions.x * 0.5 - 2.1)
	var safe_half_z := maxf(1.0, dimensions.y * 0.5 - 2.1)
	spawn_position.x = clampf(spawn_position.x, -safe_half_x, safe_half_x)
	spawn_position.z = clampf(spawn_position.z, -safe_half_z, safe_half_z)
	key.global_position = _find_supported_spawn_position(
		room.to_global(spawn_position),
		room.global_position
	)
	key.collected.connect(_on_room_key_collected)
	_spawned_key_rooms[room.room_id] = true


func _find_supported_spawn_position(
	requested_world_position: Vector3,
	fallback_world_position: Vector3
) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return requested_world_position
	for candidate in [requested_world_position, fallback_world_position]:
		var query := PhysicsRayQueryParameters3D.create(
			candidate + Vector3.UP * 3.0,
			candidate + Vector3.DOWN * 4.0,
			1
		)
		query.collide_with_areas = false
		query.hit_back_faces = true
		if player != null and is_instance_valid(player):
			query.exclude = [player.get_rid()]
		var hit := world.direct_space_state.intersect_ray(query)
		if (
			not hit.is_empty()
			and (hit.get("normal", Vector3.ZERO) as Vector3).y >= 0.55
		):
			return (hit.get("position", candidate) as Vector3) + Vector3.UP * 0.05
	return fallback_world_position + Vector3.UP * 0.05


func _on_room_key_collected(_room_id: String) -> void:
	_room_key_count += 1
	status_label.text = "获得房间钥匙 · 靠近门按 E 开启"
	_refresh_loot_label()


## 取「从 `room_id` 走向 `target_room_id` 这扇门」的策略：**优先房间声明的那份**，
## 缺失才回落到 `_door_policy_for_edge()`。`door_policies` 是按**门方向**存的，
## 所以这里先用 `door_targets` 把目标房反查回方向。
func _door_policy_towards(room_id: String, target_room_id: String) -> Dictionary:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room != null:
		var declared: Dictionary = room.door_policies
		var targets: Dictionary = room.door_targets
		for direction in targets.keys():
			if str(targets[direction]) != target_room_id:
				continue
			if declared.has(direction):
				return declared[direction]
	return _door_policy_for_edge(room_id, target_room_id)


func _try_open_room_door(target_room_id: String) -> bool:
	if target_room_id.is_empty() or _current_room_id.is_empty():
		return false
	# 封住期间一律拒绝，且**必须放在 `_open_edges` 早退之前**：
	# 来路那条边本来就是开启状态，否则会走到「通道已经开启」分支直接放行。
	if _room_is_sealed(_current_room_id):
		status_label.text = "门扇已落下 · 击退所有波次才能离开"
		return false
	if _door_fate_active:
		status_label.text = "先选择当前命运卡片，再开启下一扇门"
		return false
	var edge := _edge_key(_current_room_id, target_room_id)
	# 门策略优先读**房间按方向声明的** `door_policies` —— 和平区（区块00）就是靠它把
	# 「清房 / 钥匙 / 命运卡」三项全部关掉的。只有房间没声明该方向时才回落到默认策略。
	# ⛔ 老实现直接调 `_door_policy_for_edge()`（硬编码三项全 true），于是和平区那句
	# 「门只做普通开关」是**空承诺**：98F 每扇门都要清房 + 消耗房间钥匙（2026-09-22 人报）。
	var policy := _door_policy_towards(_current_room_id, target_room_id)
	if bool(_open_edges.get(edge, false)):
		# 边已开启也要刷新门视觉：默认开的 vertical edge
		# （如成顶↔99层基地）会在首次走到门附近时同时勾起门。
		_refresh_edge_visuals(_current_room_id, target_room_id, true)
		status_label.text = "通道已经开启"
		return true
	var current := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if current == null:
		return false
	_repair_room_progress(current)
	if bool(policy.get("requires_clear", true)) and not current.cleared:
		if current.room_type == "EVENT":
			status_label.text = (
				"先清除本房异常敌群，才能开启房门"
				if _event_combat_rooms.has(current.room_id)
				else "先前往紫色光柱，按 E 结算房间事件"
			)
		else:
			status_label.text = "先清理当前房间，才能开启房门"
		return false
	var requires_key := bool(policy.get("requires_key", true))
	if requires_key and _get_total_room_keys() <= 0:
		status_label.text = "需要房间钥匙"
		return false
	if requires_key:
		_consume_room_key()
	_open_edges[edge] = true
	if MonsterAIManager != null and player != null:
		MonsterAIManager.broadcast_sound_stimulus(player.global_position, 6.5, "door_open", player)
	minimap.set_edge_open(_current_room_id, target_room_id, true)
	_refresh_edge_visuals(_current_room_id, target_room_id, true)
	status_label.text = (
		"房门已开启 · 剩余钥匙 %d" % _get_total_room_keys()
		if requires_key
		else "通行门已开启 · 未消耗钥匙"
	)
	_refresh_loot_label()
	if bool(policy.get("triggers_fate", true)):
		# 目标房敌人必须在选卡后生成，否则“下一个房间”类世界命运会错过
		# 刚开启的房间，实际落到再下一间。
		_pending_fate_door_from_id = _current_room_id
		_pending_fate_door_target_id = target_room_id
		call_deferred("_show_door_fate_choices")
	else:
		_update_room_streaming(_current_room_id)
	return true


func try_open_room_door(target_room_id: String) -> bool:
	return _try_open_room_door(target_room_id)


func _show_door_fate_choices() -> void:
	if _door_fate_active:
		return
	var offer: Array[FateCard] = (
		_gate_expedition_fate_offer()
		if uses_dynamic_fate_economy()
		else FateCardPresets.draw_offer(3, _rng, get_runtime_map_id())
	)
	if offer.is_empty():
		_commit_pending_fate_door_streaming()
		return
	_door_fate_choices.clear()
	_door_fate_purchased.clear()
	_fate_door_offer_id += 1
	_fate_door_quote.clear()
	for card_value in offer:
		var offered_card := card_value as FateCard
		if offered_card == null:
			continue
		_fate_door_quote[offered_card.get_stable_card_id()] = (
			_fate_economy.frozen_quote_for_card(
				int(offered_card.card_rarity), _fate_door_offer_id, offered_card.get_stable_card_id(), run_seed
			)
			if _fate_economy.is_configured()
			else int(FATE_PRICE_BY_RARITY[clampi(int(offered_card.card_rarity), 0, FATE_PRICE_BY_RARITY.size() - 1)])
		)
	var rules := preload("res://src/weapons/FateOfferPolicy.gd").policy(get_runtime_map_id())
	_fate_offer_policy_snapshot = {"policy_id": rules.get("policy_id", "global"), "revision": rules.get("revision", 0)}
	_door_fate_choices.assign(offer)
	# 三张卡全部出现在场上，买与不买由玩家决定 ⇒ 每个卡位都要有独立的购买状态。
	for _choice_index in range(_door_fate_choices.size()):
		_door_fate_purchased.append(false)
	# 报价填完之后才有价可判：三张全买不起时把最低那张压到当前余额。
	_ensure_affordable_fate_choice()
	_door_fate_active = true
	_close_inventory_for_modal()
	_sync_player_input_lock()
	_build_door_fate_overlay()
	_queue_runtime_autosave("fate_door_offer_opened")
	status_label.text = "门已开启 · 用本局金币购买命运卡，买好后退出"


func _build_door_fate_overlay() -> void:
	_fate_overlay = Control.new()
	_fate_overlay.name = "DoorFateOverlay3D"
	_fate_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fate_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_fate_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_fate_overlay.z_index = FATE_OVERLAY_Z_INDEX
	$HUD.add_child(_fate_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.002, 0.008, 0.016, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fate_overlay.add_child(dim)

	# 金币读数浮到暗化层之上（主人 2026-10-19：不要遮住金币 UI）。
	# 只提这一行，不动别的 HUD：暗化仍负责把战斗画面压下去，读数则保持常色可读 ——
	# 「还要攒多少」现在完全靠自己对照价格与余额，读数被压暗就等于把唯一依据抹掉。
	# 复原在 `_close_door_fate_overlay()`，与弹窗生命周期同进同出。
	if loot_label != null and is_instance_valid(loot_label):
		loot_label.z_index = FATE_COIN_READOUT_Z_ABOVE_VEIL

	# 顶部标题已按主人 2026-10-14 要求移除；顶部「本局金币」余额行也按主人
	# 2026-10-15 要求整体移除 —— 金币的唯一读数是右下角的 `RunLootReadout`，
	# 两个数字说同一件事，留一份就够了。卡列纵向位置保持不变（74..800），
	# 顶部留白由暗化层吸收，不重排卡片。

	# 三张卡是本弹窗的主体，占据余额行与退出按钮之间的全部纵向空间。
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _hud_int(56))
	# 卡列由 `106` 上提到 `74`：头部只剩一行了，若还留在 106，余额行与卡顶之间会空出
	# 40 px（改前那 10 px 的 4 倍），看着像掉了一行东西。74 让这个间距回到 14 px 的原有节奏。
	# 下沿给到 800（而不是等比例上移的 774）：卡列自身只有 694 高、且顶部对齐，多出的余量
	# 只是容器的空余，换来卡底与退出按钮之间约 29 px 的间距，与改前的 24 px 同一档。
	_anchor_control(row, 0.5, 0.0, 0.5, 0.0, -570, 74, 570, 800)
	_fate_overlay.add_child(row)
	_fate_choice_buttons.clear()
	var card_buttons: Array[Button] = []
	for choice_index in range(_door_fate_choices.size()):
		var card := _door_fate_choices[choice_index]
		var card_view := _create_reference_fate_card_view(card, choice_index)
		row.add_child(card_view)
		# 设计契约：三张卡持续做轻微错相漂浮与透视感旋转。
		# 作用于列容器，和卡面翻牌、悬停缩放分层，避免相互覆盖。
		_start_fate_card_idle_motion(card_view, choice_index)
		var card_button := card_view.get_meta("tarot_button") as Button
		if card_button != null:
			card_buttons.append(card_button)
			_fate_choice_buttons.append(card_button)
			_play_reference_tarot_flip(card_button, card, choice_index)
	# 屏幕下方正中的退出按钮：买与不买都由它收尾，ESC / 手柄 B 是同一入口。
	# **必须在 `_configure_fate_card_focus_navigation` 之前建**：焦点链要把三张卡的「下」
	# 接到它身上，建晚了这一步拿到的就是 null，手柄会走不到退出按钮。
	_fate_exit_button = Button.new()
	_fate_exit_button.name = "FateExitButton"
	_fate_exit_button.text = "退 出"
	_fate_exit_button.tooltip_text = "退出命运卡购买（对应 ESC）· 已购买的卡继续生效"
	_fate_exit_button.focus_mode = Control.FOCUS_ALL
	_fate_exit_button.custom_minimum_size = _hud_size(Vector2(220, 44))
	_fate_exit_button.add_theme_font_size_override("font_size", _hud_int(24))
	var exit_styles := UIStyleFactory.make_button_style(
		UIStyleFactory.make_panel_bg(2).bg_color,
		Color(0.62, 0.90, 0.96)
	)
	UIStyleFactory.apply_button_style(_fate_exit_button, exit_styles)
	_fate_exit_button.pressed.connect(_cancel_door_fate_selection)
	_anchor_control(_fate_exit_button, 0.5, 1.0, 0.5, 1.0, -110, -64, 110, -20)
	_fate_overlay.add_child(_fate_exit_button)

	_configure_fate_card_focus_navigation(card_buttons)

	# 底部信息条已移除：选择反馈通过卡片的放大/缩小动画、价格行和状态栏完成。
	_fate_feedback_label = null
	_refresh_door_fate_prices()


## 门后购卡层的单张命运卡：**塔罗图卡**（卡面贴图 + 卡下功能文字 + 卡下购买价）。
##
## 返回「卡片列」容器（卡 + 卡下功能文字 + 价格行）；真正可聚焦的按钮挂在 meta `tarot_button` 上，
## 供焦点导航与翻转动画复用。卡面图片本身已带边框与圆角，因此不再叠加程序绘制的
## 品质描边、作用域标签、方位三角、目标预览与页脚。
## 有对应塔罗美术时用贴图层；缺图时回退到程序卡面，保证补图落地前仍可玩。
func _create_reference_fate_card_view(card: FateCard, choice_index: int) -> Control:
	var accent := FateCard.scope_color(card.scope)
	var column := VBoxContainer.new()
	column.name = "FateChoiceColumn_%d" % choice_index
	# 三列必须使用同一高度并从同一条顶线开始；否则枪械卡多一行文字时，
	# VBoxContainer 的居中布局会把整张卡向上顶，造成截图中的卡片错位。
	# 高度 = 卡面 546 + 说明 92 + 价格行 32 + 两条 12px 间距 = 694，与外层 row 完全等高。
	column.custom_minimum_size = _hud_size(Vector2(346, 694))
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", _hud_int(12))

	var button := Button.new()
	button.name = "FateChoiceCard_%d" % choice_index
	button.custom_minimum_size = _hud_size(Vector2(346, 546))
	button.text = ""
	button.clip_contents = false
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = "%s · %s\n%s" % [card.card_name, card.orientation_name(), card.description]
	button.disabled = true
	button.set_meta("tarot_face_ready", false)
	button.set_meta("tarot_orientation", card.orientation_name())
	button.set_meta("tarot_button", button)
	# 卡身份：供验收把卡面贴图与被抽中的卡牌逐一对上，防止"图装错牌"。
	button.set_meta("tarot_stable_card_id", card.get_stable_card_id())
	button.set_meta("tarot_scope_color", accent)

	# 卡面自身已经包含完整外框；按钮只承担命中区域，不再绘制紫色背框、焦点框或按下框。
	var bare_button := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", bare_button)
	button.add_theme_stylebox_override("hover", bare_button)
	button.add_theme_stylebox_override("focus", bare_button)
	button.add_theme_stylebox_override("pressed", bare_button)
	column.add_child(button)

	var art := FateCardView.art_for(card)
	var art_mode := art != null
	button.set_meta("tarot_art_mode", art_mode)
	var face_node: Control = null
	var back_node: Control = null
	if art_mode:
		var back_tex := FateCardView.back_texture()
		if back_tex != null:
			back_node = FateCardView.build_back_layer(button)
		face_node = FateCardView.build_art_layer(button, art, card.is_reversed(), "TarotArtFace")
		if face_node != null:
			face_node.visible = false
	else:
		face_node = _build_programmatic_fate_face(button, card, accent)
		back_node = _build_programmatic_fate_back(button, accent)

	button.set_meta("tarot_face_node", face_node)
	button.set_meta("tarot_back_node", back_node)
	button.set_meta("fate_feedback_view", column)
	button.set_meta("fate_feedback_hovered", false)
	var feedback: Control = FATE_CARD_FEEDBACK_SCRIPT.new() as Control
	feedback.name = "FateCardFeedback"
	feedback.set_anchors_preset(Control.PRESET_FULL_RECT)
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.setup(accent)
	button.add_child(feedback)
	button.set_meta("fate_feedback_node", feedback)
	# 枢轴同步用 lambda：静态/实例方法的 Callable 在多张卡 bind 到不同按钮时
	# 会被引擎判为同一连接，导致翻转绕旧轴心（卡面飞出）。
	var sync_pivot := func() -> void:
		if is_instance_valid(button):
			button.pivot_offset = button.size * 0.5
	sync_pivot.call()
	button.resized.connect(sync_pivot)
	var sync_column_pivot := func() -> void:
		if is_instance_valid(column):
			column.pivot_offset = column.size * 0.5
	sync_column_pivot.call()
	column.resized.connect(sync_column_pivot)
	button.mouse_entered.connect(_on_reference_fate_card_hover.bind(button, true))
	button.mouse_exited.connect(_on_reference_fate_card_hover.bind(button, false))
	button.focus_entered.connect(_on_reference_fate_card_focus.bind(button, true))
	button.focus_exited.connect(_on_reference_fate_card_focus.bind(button, false))
	button.pressed.connect(_on_reference_fate_card_pressed.bind(button, choice_index))

	var target_detail := ""
	if card.scope == FateCard.Scope.WEAPON:
		var target := FateCardGameBridge.get_target_summary(card)
		var weapon_name := str(target.get("display_name", "当前枪械"))
		var used := int(target.get("fate_slot_used", 0))
		var capacity := int(target.get("fate_slot_capacity", 0))
		if capacity > 0:
			target_detail = "%s  %d/%d" % [weapon_name, used, capacity]
		else:
			target_detail = weapon_name
	var caption := FateCardView.build_caption(card, _hud_int(22), _hud_size(Vector2(346, 0)).x, target_detail)
	# 说明区也统一预留高度：先保证三张卡面和文字基线整齐，再容纳枪械卡的第二行信息。
	caption.custom_minimum_size = _hud_size(Vector2(346, 92))
	caption.add_theme_color_override(
		"font_color", UIStyleFactory.prism_normalize_color(accent)
	)
	var caption_font := UIStyleFactory.make_prism_font(2)
	if caption_font != null:
		caption.add_theme_font_override("font", caption_font)
	caption.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.88))
	caption.add_theme_constant_override("outline_size", _hud_int(3))
	caption.add_theme_constant_override("line_spacing", _hud_int(3))
	column.add_child(caption)
	# 卡下说明与价格行都要能被「买下后整体去色」重新着色，故各挂一份 meta。
	button.set_meta("tarot_caption_label", caption)
	# 卡下价格行：这是「购买制」对玩家的唯一价格口径，只读 `FATE_PRICE_BY_RARITY`。
	# 状态（可买 / 金币不足 / 命运槽已满 / 已购买）也由这一行承载，卡片本体不额外加角标。
	var price_label := _make_hud_label("", 22, accent)
	price_label.name = "FateChoicePrice_%d" % choice_index
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_label.custom_minimum_size = _hud_size(Vector2(346, 32))
	price_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.90))
	price_label.add_theme_constant_override("outline_size", _hud_int(3))
	column.add_child(price_label)
	button.set_meta("tarot_price", _fate_price(card))
	button.set_meta("tarot_price_bounds", _fate_price_bounds(card))
	button.set_meta("tarot_price_label", price_label)
	button.set_meta("tarot_purchased", false)
	# 调用方拿到的是「列」而不是按钮，故在列上也挂一份，避免从列上取不到按钮。
	column.set_meta("tarot_button", button)
	return column


## 缺图回退：程序绘制的卡面（作用域 + 卡名 + 方位 + 功能）。
## 塔罗美术补齐后这一支不再被走到。
func _build_programmatic_fate_face(host: Control, card: FateCard, accent: Color) -> Control:
	var margin := _make_margin(22, 20, 22, 20)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.name = "TarotFaceText"
	margin.visible = false
	host.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", _hud_int(8))
	margin.add_child(vbox)
	var scope_label := _make_hud_label(FateCard.scope_display_name(card.scope), 20, accent)
	scope_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(scope_label)
	var card_name := _make_hud_label(card.card_name, 28, Color(0.94, 0.96, 1.0))
	card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(card_name)
	var orientation_label := _make_hud_label(
		"%s %s" % [card.orientation_symbol(), card.orientation_name()],
		18,
		Color(1.0, 0.72, 0.34) if card.is_reversed() else Color(0.62, 0.94, 1.0),
	)
	orientation_label.name = "TarotOrientationLabel"
	orientation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(orientation_label)
	var effect_text := card.short_description if not card.short_description.is_empty() else card.description
	var effect := _make_hud_label(effect_text, 19, Color(0.91, 0.93, 0.96))
	effect.custom_minimum_size = _hud_size(Vector2(280, 120))
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(effect)
	return margin


func _build_programmatic_fate_back(host: Control, accent: Color) -> Control:
	var back := Panel.new()
	back.name = "TarotCardBack"
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 卡背要**遮住翻转中的卡面**，不能用 HUD 弹层的 0.50 半透底
	# （那是 verify_finite_ammo_flow 对 HUD 面板的透明度契约，不适用于卡牌实体）。
	# 这里给卡背一块近乎不透明的棱镜深墨板 + 1px 线，方角。
	var back_style := UIStyleFactory.make_prism_panel(true, 0.96)
	back_style.border_color = UIStyleFactory.prism_normalize_color(Color(accent, 0.92))
	back_style.set_border_width_all(1)
	back_style.set_corner_radius_all(2)
	back.add_theme_stylebox_override("panel", back_style)
	host.add_child(back)
	var back_glyph := _make_hud_label("✦\n命运塔罗\nFATE", 30, Color(accent, 0.92))
	back_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	back_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(back_glyph)
	return back


func _play_reference_tarot_flip(button: Button, card: FateCard, choice_index: int) -> void:
	if button == null:
		return
	button.scale = Vector2.ONE
	button.pivot_offset = button.size * 0.5
	# 注意：不能用 get_meta(key, null) 取默认——Godot 在默认值本身为 null 时仍会打错误日志。
	var face := (button.get_meta("tarot_face_node") if button.has_meta("tarot_face_node") else null) as Control
	var back := (button.get_meta("tarot_back_node") if button.has_meta("tarot_back_node") else null) as Control
	var reduce_motion := bool(ProjectSettings.get_setting("accessibility/reduce_motion", false))
	var tween := button.create_tween()
	button.set_meta("fate_flip_tween", tween)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if reduce_motion:
		_reveal_reference_tarot_face(button, face, back, card.is_reversed())
		button.modulate.a = 0.0
		tween.tween_property(button, "modulate:a", 1.0, 0.15)
	else:
		tween.tween_interval(0.10 + float(choice_index) * 0.08)
		tween.tween_property(button, "scale:x", 0.04, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(_reveal_reference_tarot_face.bind(button, face, back, card.is_reversed()))
		tween.tween_property(button, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish_reference_tarot_flip.bind(button, card))


func _reveal_reference_tarot_face(button: Control, face: Control, back: Control, is_reversed: bool) -> void:
	# 图卡模式：只把**卡面图案**绕中心倒置，按钮与卡下功能文字层都不旋转。
	# 程序卡面回退：沿用「卡框倒置 + 文字层反向补偿」的旧规则。
	if button != null and is_instance_valid(button) and face != null:
		if bool(button.get_meta("tarot_art_mode", false)):
			face.pivot_offset = face.size * 0.5
			face.rotation = PI if is_reversed else 0.0
		else:
			var ornament := face.find_child("TarotOrientationOrnament", true, false) as Control
			UIStyleFactory.apply_tarot_orientation(button as Button, face, is_reversed, ornament)
	if back != null and is_instance_valid(back):
		back.visible = false
	if face != null and is_instance_valid(face):
		face.visible = true


func _finish_reference_tarot_flip(button: Button, card: FateCard) -> void:
	if button == null or not is_instance_valid(button):
		return
	button.disabled = false
	button.set_meta("tarot_face_ready", true)
	button.set_meta("tarot_face_side", "front")
	button.set_meta("tarot_orientation", card.orientation_name())
	button.set_meta("tarot_face_rotation", button.rotation)
	if bool(button.get_meta("tarot_purchased", false)):
		_show_fate_card_back(button)
	_maybe_focus_fate_card(button)


## 买下之后把这张卡做成**灰阶 + 压暗 + 缩到 70%**，并翻回背面（主人 2026-10-14 要求）。
##
## 为什么必须翻回去：卡位已经用掉了，还露着牌面会让玩家以为这张还能再买一次；
## 而且「已购买」这个状态在视觉上要能和「买得起但没买」一眼分开，不能只靠卡下那行小字。
## 手法与 `_play_reference_tarot_flip` 严格对偶：同样在 90° 薄边时换面，减少动效时直接换。
##
## ⚠️ 不碰 `tarot_face_ready`：那是「翻牌动画结束、可以交互」的标记，不是「正在露牌面」。
## 置回 false 会让 `_set_fate_feedback_buttons_disabled(false)` 把这张卡永久禁用，
## 键盘/手柄的焦点导航当场断链（购买制下焦点链还要经过卡列回退出按钮）。
func _flip_fate_card_to_back(button: Button, choice_index: int) -> void:
	if button == null or not is_instance_valid(button):
		return
	var back := (button.get_meta("tarot_back_node") if button.has_meta("tarot_back_node") else null) as Control
	# 没有卡背层（图卡缺背图）就保持正面：翻过去会变成一张空白卡，比不翻更糟。
	# 但**去色 / 压暗 / 缩小照样做** —— 那三样不依赖有没有背图。
	_style_purchased_fate_card(button, choice_index)
	if back == null or not is_instance_valid(back):
		return
	button.pivot_offset = button.size * 0.5
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		_show_fate_card_back(button)
		return
	var tween := button.create_tween()
	button.set_meta("fate_flip_tween", tween)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# stagger 比首次翻牌短：这是玩家刚点完的卡，反馈要跟手，不能等三张卡的错峰节奏。
	tween.tween_interval(0.04 + float(choice_index) * 0.04)
	tween.tween_property(button, "scale:x", 0.04, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_show_fate_card_back.bind(button))
	tween.tween_property(button, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 翻回背面的换面动作：藏卡面、露卡背，并把 `tarot_face_side` 翻到 `back`。
## 三个动作必须在**同一步**完成 —— 谁先谁后都会让「现在到底朝哪面」有一段时间说不清。
## 卡面若原本是逆位（绕中心 180°）不必复位：它已经不可见，且这张卡不会再翻回正面。
func _show_fate_card_back(button: Control) -> void:
	if button == null or not is_instance_valid(button):
		return
	var face := (button.get_meta("tarot_face_node") if button.has_meta("tarot_face_node") else null) as Control
	var back := (button.get_meta("tarot_back_node") if button.has_meta("tarot_back_node") else null) as Control
	if face != null and is_instance_valid(face):
		face.visible = false
	if back != null and is_instance_valid(back):
		back.visible = true
	button.set_meta("tarot_face_side", "back")


## 已购卡的共用灰阶材质：懒建一次，三张卡共享。
##
## 为什么要材质而不是只调 `modulate`：卡背线稿本身是亮青绿（`#02FC8E` 级别），
## `modulate` 只能整体压暗、**去不掉色相**，压完仍是「暗绿」不是「灰」。
func _ensure_fate_greyscale_material() -> ShaderMaterial:
	if _fate_greyscale_material == null:
		var shader := Shader.new()
		shader.code = FATE_GREYSCALE_SHADER_CODE
		_fate_greyscale_material = ShaderMaterial.new()
		_fate_greyscale_material.shader = shader
	return _fate_greyscale_material


## 把一张已购卡做成「灰阶 + 压暗 + 70%」。**幂等**：重复调用不会叠加效果。
##
## 只作用于**可见的那一层贴图**（卡背 `tarot_back_node`）。卡面层 `TarotArtFace`
## 自带扫描光 shader，翻背后已隐藏，不去动它 —— 换掉会连带丢掉那条 shader，
## 万一将来要「翻回正面」就没有扫描光了。
func _style_purchased_fate_card(button: Button, choice_index: int) -> void:
	if button == null or not is_instance_valid(button):
		return
	var back := (button.get_meta("tarot_back_node") if button.has_meta("tarot_back_node") else null) as CanvasItem
	if back != null and is_instance_valid(back):
		back.material = _ensure_fate_greyscale_material()
		# 半透明：只淡**卡牌本身**（主人 2026-10-15 要求），不淡卡下文字 ——
		# 见 `FATE_PURCHASED_CARD_ALPHA` 的注释，整列半透明会把「已购买」读没。
		back.modulate = Color(1.0, 1.0, 1.0, FATE_PURCHASED_CARD_ALPHA)
	# 文字也去色：作用域色（紫/金/浅蓝）与「已购买」的绿都不是灰阶，留着会和卡面打架。
	var caption := (button.get_meta("tarot_caption_label") if button.has_meta("tarot_caption_label") else null) as Label
	if caption != null and is_instance_valid(caption):
		caption.add_theme_color_override("font_color", FATE_PURCHASED_TEXT_COLOR)
	var price_label := (button.get_meta("tarot_price_label") if button.has_meta("tarot_price_label") else null) as Label
	if price_label != null and is_instance_valid(price_label):
		price_label.add_theme_color_override("font_color", FATE_PURCHASED_TEXT_COLOR)
	# 整列压暗走 modulate（乘性），与灰阶材质分工：材质管去色，modulate 管变暗。
	var view := button.get_meta("fate_feedback_view") as Control
	if view != null and is_instance_valid(view):
		view.modulate = FATE_PURCHASED_DIM_COLOR
	# 缩到 70%：走 `_tween_fate_card_scale`，它会乘上 `_fate_card_base_scale()`，
	# 所以后续任何悬停复位 / 重排都不会把这张卡弹回 100%。
	_tween_fate_card_scale(
		button, 1.0,
		0.0 if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)) else 0.32
	)


## 命运卡三选一是**代码构造**的覆盖层（不是场景菜单），因此不在
## `UiMenuFocus.ensure_focus` 的那批静态菜单里，需要自己抓默认焦点。
##
## 时机是硬约束：卡片在翻转动画期间 `disabled = true`（防止翻面前误点），
## 而 `UiMenuFocus.is_focusable` 会排除禁用按钮、`grab_focus()` 对禁用按钮也无效
## ⇒ 只有 `_finish_reference_tarot_flip` 解除 disabled 的那一刻才抓得到。
## 三张卡的翻转动画带 stagger，第一张最早解锁，于是焦点落在第一张卡上。
##
## 只在当前没有焦点持有者时抓：玩家若已用鼠标/手柄选中了某张卡，不抢回来。
func _maybe_focus_fate_card(button: Button) -> void:
	if not _door_fate_active:
		return
	if _fate_overlay == null or not is_instance_valid(_fate_overlay):
		return
	if button == null or not is_instance_valid(button):
		return
	if not button.is_inside_tree() or not button.is_visible_in_tree():
		return
	var viewport := get_viewport()
	if viewport != null and viewport.gui_get_focus_owner() != null:
		return
	_fate_initializing_focus = true
	button.grab_focus()
	_fate_initializing_focus = false
	# 默认焦点只服务键盘/手柄导航，不制造一次假的鼠标悬停放大。
	button.set_meta("fate_feedback_focused", false)
	_tween_fate_card_scale(button, 1.0, 0.0)
	var feedback := (button.get_meta("fate_feedback_node") if button.has_meta("fate_feedback_node") else null) as Control
	if feedback != null and is_instance_valid(feedback):
		feedback.call("set_hovered", bool(button.get_meta("fate_feedback_hovered", false)))


## 三张命运卡横向排布，显式指定左右邻居并首尾环绕；**下方向接到屏幕下方的退出按钮**。
##
## 为什么要显式指定而不是靠引擎自动推导：逆位卡是**整张旋转 180°** 的实体卡面，
## 自动 neighbor 推导依赖控件可见矩形的方位关系，旋转后可能失准；显式指定同时补上
## 「第一张按左回到最后一张」的环绕（自动推导不做环绕，按到头就没反应了）。
## 上下为什么不再共用左右环绕：购买制新增了底部退出按钮。若「下」还指向相邻卡，
## 手柄玩家**永远走不到退出按钮**（自动推导对跨容器、锚点差异大的两个控件同样不可靠），
## 而这张弹窗现在只有它一个出口 —— 走不到就等于手柄无法离开购卡界面。
func _configure_fate_card_focus_navigation(buttons: Array[Button]) -> void:
	var count := buttons.size()
	if count <= 0:
		return
	for index in range(count):
		var button := buttons[index]
		if button == null or not is_instance_valid(button):
			continue
		var previous := buttons[(index - 1 + count) % count]
		var following := buttons[(index + 1) % count]
		var previous_path := _safe_fate_focus_neighbor_path(button, previous)
		var following_path := _safe_fate_focus_neighbor_path(button, following)
		# Empty paths deliberately fall back to Godot's automatic neighbor search.
		# More importantly, we never call get_path_to() across detached trees: doing
		# so emits "common_parent is null" while the fate overlay is being rebuilt.
		button.focus_neighbor_left = previous_path
		button.focus_neighbor_right = following_path
		button.focus_neighbor_top = previous_path
		button.focus_neighbor_bottom = _safe_fate_focus_neighbor_path(button, _fate_exit_button)
	if _fate_exit_button == null or not is_instance_valid(_fate_exit_button):
		return
	# 退出按钮留在同一组里：左右环绕整排卡，向上回第一张卡，再按上/下回到自己。
	# 这样手柄「下 → 退出 → 上 → 卡」形成闭环，不会把焦点扔出弹窗。
	var first_card_path := _safe_fate_focus_neighbor_path(_fate_exit_button, buttons[0])
	_fate_exit_button.focus_neighbor_left = _safe_fate_focus_neighbor_path(_fate_exit_button, buttons[count - 1])
	_fate_exit_button.focus_neighbor_right = first_card_path
	_fate_exit_button.focus_neighbor_top = first_card_path
	_fate_exit_button.focus_neighbor_bottom = first_card_path


func _safe_fate_focus_neighbor_path(source: Control, target: Control) -> NodePath:
	if source == null or target == null:
		return NodePath()
	if not is_instance_valid(source) or not is_instance_valid(target):
		return NodePath()
	if not source.is_inside_tree() or not target.is_inside_tree():
		return NodePath()
	var source_tree := source.get_tree()
	var target_tree := target.get_tree()
	if source_tree == null or target_tree == null or source_tree != target_tree:
		return NodePath()
	return source.get_path_to(target)


func _get_fate_target_preview(card: FateCard) -> String:
	if card.scope != FateCard.Scope.WEAPON:
		return FateCard.scope_target_text(card.scope)
	var target := FateCardGameBridge.get_target_summary(card)
	var used := int(target.get("fate_slot_used", 0))
	var capacity := int(target.get("fate_slot_capacity", 0))
	if capacity > 0 and used >= capacity:
		return "当前枪 #%s\n命运槽已满 %d / %d · 不可购买" % [
			target.get("instance_suffix", str(target.get("weapon_instance_id", "")).right(6).to_upper()),
			used, capacity,
		]
	return "当前枪 #%s\n下一槽 %d / %d" % [
		target.get("instance_suffix", str(target.get("weapon_instance_id", "")).right(6).to_upper()),
		mini(used + 1, capacity),
		capacity,
	]


func _start_fate_card_idle_motion(card_view: Control, choice_index: int) -> void:
	if card_view == null or not is_instance_valid(card_view):
		return
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		return
	card_view.pivot_offset = card_view.size * 0.5
	# 每张卡使用不同相位、幅度与周期，避免三张卡同步摆动。
	var phase := float(choice_index) * 0.95
	var lift := 3.0 + float(choice_index % 2) * 1.2
	var tilt := deg_to_rad(0.55 + float(choice_index) * 0.18)
	var cycle := 2.8 + float(choice_index) * 0.42
	var tween := card_view.create_tween().set_loops()
	card_view.set_meta("fate_idle_tween", tween)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(fmod(phase, 0.85))
	tween.tween_property(card_view, "position:y", -lift, cycle * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(card_view, "rotation", tilt, cycle * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(card_view, "position:y", 0.0, cycle * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(card_view, "rotation", -tilt, cycle * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(card_view, "rotation", 0.0, cycle * 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_reference_fate_card_hover(button: Button, hovered: bool) -> void:
	_set_fate_card_pointer_state(button, hovered, false)


func _on_reference_fate_card_focus(button: Button, focused: bool) -> void:
	# 焦点反馈走独立状态，不伪造 mouse_entered，避免初始化焦点把鼠标态锁死。
	if _fate_initializing_focus:
		return
	_set_fate_card_pointer_state(button, focused, true)


func _set_fate_card_pointer_state(button: Button, active: bool, from_focus: bool) -> void:
	if button == null or not is_instance_valid(button):
		return
	button.set_meta("fate_feedback_focused" if from_focus else "fate_feedback_hovered", active)
	var hovered := bool(button.get_meta("fate_feedback_hovered", false))
	var focused := bool(button.get_meta("fate_feedback_focused", false))
	if _fate_feedback_locked or not bool(button.get_meta("tarot_face_ready", false)):
		return
	# 已购买的卡不再放大、也不再有悬停亮边（主人 2026-10-14 要求）：这张卡已经翻回背面、
	# 卡位用掉了，任何「碰得到」的反馈都是在骗玩家 —— 它再点也只会弹一句「已购买」。
	# 注意这里只掐**视觉反馈**：按钮本身仍保持可聚焦，键盘/手柄的焦点导航不能断链。
	var interactive := not bool(button.get_meta("tarot_purchased", false))
	var target := 1.045 if interactive and (hovered or focused) else 1.0
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		target = 1.0
	_tween_fate_card_scale(button, target, 0.18)
	var feedback := (button.get_meta("fate_feedback_node") if button.has_meta("fate_feedback_node") else null) as Control
	if feedback != null and is_instance_valid(feedback):
		feedback.call("set_hovered", interactive and (hovered or focused))


## 已购买卡的整体缩小倍率（业主 2026-10-14 指定 70%）。
## 这一档是**基准缩放**，不是悬停反馈 —— `_tween_fate_card_scale` 的所有 target 都是
## 「相对基准的倍率」，最终尺寸 = `target × 基准`。否则 `_reset_fate_feedback()` 那句
## 「把所有卡复位到 1.0」会把已购卡的 0.70 直接冲掉。
func _kill_fate_feedback_tween(button: Control) -> void:
	if button == null or not is_instance_valid(button):
		return
	var key := button.get_instance_id()
	var previous: Variant = _fate_feedback_tweens.get(key, null)
	if previous != null and is_instance_valid(previous):
		(previous as Tween).kill()
	_fate_feedback_tweens.erase(key)


## 一张卡的**基准缩放**：已购买 = 0.70，其余 = 1.0。
func _fate_card_base_scale(button: Control) -> float:
	if button == null or not is_instance_valid(button):
		return 1.0
	return FATE_PURCHASED_CARD_SCALE if bool(button.get_meta("tarot_purchased", false)) else 1.0


func _tween_fate_card_scale(button: Button, target: float, duration: float) -> void:
	if button == null or not is_instance_valid(button):
		return
	var view: Control = button.get_meta("fate_feedback_view") as Control
	view.pivot_offset = view.size * 0.5
	_kill_fate_feedback_tween(button)
	# `target` 是相对倍率（1.045 = 悬停放大 4.5%），基准由购买状态决定 ⇒ 已购卡
	# 无论被悬停、复位还是重排，都稳定停在 0.70，不会被复位到 1.0 弹回去。
	var absolute := target * _fate_card_base_scale(button)
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)) or duration <= 0.0:
		view.scale = Vector2.ONE * absolute
		return
	var tween := view.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "scale", Vector2.ONE * absolute, duration)
	_fate_feedback_tweens[button.get_instance_id()] = tween


func _on_reference_fate_card_pressed(button: Button, choice_index: int) -> void:
	if button == null or not is_instance_valid(button) or _fate_feedback_locked:
		return
	if not bool(button.get_meta("tarot_face_ready", false)):
		return
	# 购买制的前置校验必须在播放「选中」动画之前：不能对一张买不起的卡
	# 播完放大/闪光再告诉玩家扣不了钱，那是一次假的选中反馈。
	var block_reason := _fate_card_block_reason(choice_index)
	if not block_reason.is_empty():
		_report_fate_block(choice_index, block_reason)
		return
	_fate_feedback_locked = true
	_fate_feedback_selected_index = choice_index
	_set_fate_feedback_buttons_disabled(true)
	for other_button in _fate_choice_buttons:
		if other_button == null or not is_instance_valid(other_button):
			continue
		var target := 1.10 if other_button == button else 0.92
		if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
			target = 1.0
		_tween_fate_card_scale(other_button, target, 0.25)
	var feedback := (button.get_meta("fate_feedback_node") if button.has_meta("fate_feedback_node") else null) as Control
	if feedback != null and is_instance_valid(feedback):
		feedback.call("trigger_flash")
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		_apply_fate_choice_after_feedback(choice_index)
		return
	# 短促的按下回弹先于选中放大，所有 tween 都由共享表统一 kill，快进快出不会竞态。
	_kill_fate_feedback_tween(button)
	var view: Control = button.get_meta("fate_feedback_view") as Control
	var impact := view.create_tween()
	impact.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	impact.tween_property(view, "scale", Vector2.ONE * 0.965, 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	impact.tween_property(view, "scale", Vector2.ONE * 1.055, 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	impact.tween_property(view, "scale", Vector2.ONE * 1.10, 0.17).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fate_feedback_tweens[button.get_instance_id()] = impact
	_fate_feedback_dispatch = _fate_overlay.create_tween()
	_fate_feedback_dispatch.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fate_feedback_dispatch.tween_interval(0.36)
	_fate_feedback_dispatch.tween_callback(_apply_fate_choice_after_feedback.bind(choice_index))


func _set_fate_feedback_buttons_disabled(disabled: bool) -> void:
	for button in _fate_choice_buttons:
		if button == null or not is_instance_valid(button):
			continue
		button.disabled = disabled if disabled else not bool(button.get_meta("tarot_face_ready", false))


func _reset_fate_feedback(immediate := false) -> void:
	if _fate_feedback_dispatch != null and _fate_feedback_dispatch.is_valid():
		_fate_feedback_dispatch.kill()
	_fate_feedback_dispatch = null
	var focus_index := _fate_feedback_selected_index
	_fate_feedback_locked = false
	_fate_feedback_selected_index = -1
	for button in _fate_choice_buttons:
		if button == null or not is_instance_valid(button):
			continue
		_tween_fate_card_scale(button, 1.0, 0.0 if immediate else 0.18)
		button.set_meta("fate_feedback_hovered", false)
		button.set_meta("fate_feedback_focused", false)
		var feedback := (button.get_meta("fate_feedback_node") if button.has_meta("fate_feedback_node") else null) as Control
		if feedback != null and is_instance_valid(feedback):
			feedback.call("reset_feedback")
		_reset_fate_price_flash(button)
	_set_fate_feedback_buttons_disabled(false)
	if not immediate and focus_index >= 0 and focus_index < _fate_choice_buttons.size():
		_fate_initializing_focus = true
		_fate_choice_buttons[focus_index].grab_focus()
		_fate_initializing_focus = false
	if immediate:
		_fate_feedback_tweens.clear()


func _apply_fate_choice_after_feedback(choice_index: int) -> void:
	if not _door_fate_active or not _fate_feedback_locked or choice_index != _fate_feedback_selected_index:
		return
	await _purchase_fate_card(choice_index)
	# 买下后弹窗**保持打开**（可以继续买另外两张），只把这一次的按下反馈复位。
	if _door_fate_active and not _fate_overlay_closing:
		_reset_fate_feedback()


func _rarity_color(rarity: FateCard.CardRarity) -> Color:
	match rarity:
		FateCard.CardRarity.COMMON: return Color(0.76, 0.82, 0.88)
		FateCard.CardRarity.RARE: return Color(0.24, 0.72, 1.0)
		FateCard.CardRarity.EPIC: return Color(0.78, 0.36, 1.0)
		FateCard.CardRarity.LEGENDARY: return Color(1.0, 0.70, 0.22)
		FateCard.CardRarity.MYSTIC: return Color(1.0, 0.22, 0.28)
	return Color.WHITE


func _get_fate_choice_text(card: FateCard) -> String:
	var target_text := FateCard.scope_target_text(card.scope)
	if card.scope == FateCard.Scope.WEAPON:
		var target := FateCardGameBridge.get_target_summary(card)
		var instance_tail := str(target.get("weapon_instance_id", "")).right(6).to_upper()
		var used := int(target.get("fate_slot_used", 0))
		var capacity := int(target.get("fate_slot_capacity", 0))
		target_text = "当前枪 #%s · 下一槽 %d/%d\n永久刻印，不可逆" % [
			instance_tail, mini(used + 1, capacity), capacity,
		]
	return "%s\n[%s · %s] %s\n%s\n\n%s" % [
		FateCard.scope_display_name(card.scope),
		FateCard.rarity_name(card.card_rarity), FateCard.type_name(card.card_type),
		card.card_name, target_text, card.description,
	]


## 兼容入口：直接购买指定卡位（不走按钮动画反馈）。门后流程与验收用例共用。
## 真正的购买事务在 `_purchase_fate_card`；本函数只做参数裁剪。
func _on_door_fate_selected(choice_index: int) -> void:
	await _purchase_fate_card(choice_index)


## 门后命运卡「购买」事务：扣**局内金币** → 应用卡牌 → 标记该卡位已购买。
##
## 硬边界：只动 `GameManager.currency`（本局金币）。局外总货币池
## `BaseManager.get_extraction_points()` 在任何分支都不得被读写 —— 门后买卡是
## 一次纯局内交易，玩家不会因为买卡而损失带出基地的抽取点。
##
## 弹窗保持打开：三张卡可以全买，也可以一张不买，退出按钮才收尾。
func _purchase_fate_card(choice_index: int) -> void:
	if not _door_fate_active or _fate_overlay_closing or choice_index < 0 or choice_index >= _door_fate_choices.size():
		return
	var block_reason := _fate_card_block_reason(choice_index)
	if not block_reason.is_empty():
		_report_fate_block(choice_index, block_reason)
		return
	var card := _door_fate_choices[choice_index]
	var price := _fate_price(card)
	if not GameManager.spend_currency(price):
		_report_fate_block(choice_index, "insufficient")
		_refresh_door_fate_prices()
		return
	var result := await FateCardGameBridge.apply_card_with_source_selection(card, _fate_overlay)
	if not is_inside_tree() or not _door_fate_active:
		return
	if not bool(result.get("success", false)):
		# 付了金币但牌没生效 ⇒ 必须原额退金币，不能出现「钱花了、卡没刻上」的静默损失。
		GameManager.add_currency(price)
		var failure := str(result.get("message", result.get("reason", "当前目标无法承载该命运")))
		status_label.text = "购买失败 · %s：%s · 已退还 %d 金币" % [card.card_name, failure, price]
		_refresh_door_fate_prices()
		return
	if choice_index < _door_fate_purchased.size():
		_door_fate_purchased[choice_index] = true
	var button := _fate_choice_button(choice_index)
	if button != null:
		button.set_meta("tarot_purchased", true)
		# 买下的卡翻回背面：卡位已经用掉了，露着牌面会让玩家以为还能再买一次。
		_flip_fate_card_to_back(button, choice_index)
	if AudioManager != null:
		AudioManager.play_fate_card_sfx()
	status_label.text = "命运生效：%s · 花费 %d 金币 · 剩余 %d 金币" % [card.card_name, price, GameManager.currency]
	_refresh_door_fate_prices()
	_queue_runtime_autosave("fate_card_purchased")
	# 扣款反馈必须晚于刷新：刷新会把余额文本换成新值，飘字是对「这次变化」的注解。
	_play_fate_balance_spend_feedback(price)


func _is_weapon_fate_target_full(card: FateCard) -> bool:
	if card == null or card.scope != FateCard.Scope.WEAPON:
		return false
	var target := FateCardGameBridge.get_target_summary(card)
	var capacity := int(target.get("fate_slot_capacity", 0))
	return capacity > 0 and int(target.get("fate_slot_used", 0)) >= capacity


## 单张卡价格只读本门打开时冻结的报价。
## 远征公式见 FateEconomyService：真实编成参考收益 → 明示上下界；实际击杀收入只解锁稀有度，
## 不改已经冻结的报价，也不按剩余余额动态宰价。非远征专项继续使用历史价格表。
func _fate_price(card: FateCard) -> int:
	if card == null:
		return 0
	var stable_id := card.get_stable_card_id()
	if _fate_door_quote.has(stable_id):
		return int(_fate_door_quote[stable_id])
	var rarity := clampi(int(card.card_rarity), 0, FATE_PRICE_BY_RARITY.size() - 1)
	if uses_dynamic_fate_economy():
		return _fate_economy.frozen_quote_for_card(rarity, _fate_door_offer_id, stable_id, run_seed)
	return int(FATE_PRICE_BY_RARITY[rarity])


func _fate_price_bounds(card: FateCard) -> Dictionary:
	if card == null:
		return {"min": 0, "quote": 0, "max": 0}
	if uses_dynamic_fate_economy():
		return _fate_economy.price_bounds_for_card(
			int(card.card_rarity), card.get_stable_card_id(), _fate_door_offer_id
		)
	var price := _fate_price(card)
	return {"min": price, "quote": price, "max": price}


## 门后保底：每次三张里至少一张买得起。
##
## 命运门总是在清完一间房之后才开（安全屋→room_01 是入口交通门，不弹卡），所以玩家
## 手里通常有钱；但三张是稀有度全开随机，仍可能整手都是高价卡，或者前面几门把钱花光。
## 这里把**报价最低的那张**下调到当前余额：只降不升、只动一张、且只在三张全买不起时生效。
##
## 这是「冻结报价」的唯一例外 —— 冻结价仍由门序号 / 基准房收益 / 种子决定，
## 保底只做兜底压价；压价结果写进 `_fate_door_quote`，随快照恢复，不重算、不随余额涨回去。
## 非远征入口（塔楼等）继续用历史固定价，不参与保底。
func _ensure_affordable_fate_choice() -> void:
	if not uses_dynamic_fate_economy() or _door_fate_choices.is_empty():
		return
	var wallet := maxi(0, GameManager.currency)
	var cheapest: FateCard = null
	for card in _door_fate_choices:
		if card == null:
			continue
		if cheapest == null or _fate_price(card) < _fate_price(cheapest):
			cheapest = card
	if cheapest == null:
		return
	if _fate_price(cheapest) > wallet:
		_fate_door_quote[cheapest.get_stable_card_id()] = wallet


func _gate_expedition_fate_offer() -> Array[FateCard]:
	# 只按关卡白名单过滤，不再按「已解锁稀有度」收窄：主人的口径是池子 21 张、
	# 每次随机 3 张、保底一张买得起。稀有度门槛会把初期池子压到 2 张，直接违背这条。
	var pool: Array[FateCard] = []
	var ids: Dictionary = {}
	for card in FateCardPresets.door_reward_presets():
		var stable_id := card.get_stable_card_id()
		if not ids.has(stable_id) and preload("res://src/weapons/FateOfferPolicy.gd").allows(get_runtime_map_id(), stable_id):
			pool.append(card)
			ids[stable_id] = true
	var identity_rng := RandomNumberGenerator.new()
	identity_rng.seed = hash("%d|%d|fate_identity" % [run_seed, _fate_door_offer_id + 1])
	var orientation_rng := RandomNumberGenerator.new()
	orientation_rng.seed = hash("%d|%d|fate_orientation" % [run_seed, _fate_door_offer_id + 1])
	var offer: Array[FateCard] = []
	while offer.size() < 3 and not pool.is_empty():
		var index := identity_rng.randi_range(0, pool.size() - 1)
		var card := pool[index]
		pool.remove_at(index)
		preload("res://src/weapons/FateOfferPolicy.gd").orient(card, orientation_rng.randf(), get_runtime_map_id())
		offer.append(card)
	return offer


func _fate_choice_button(choice_index: int) -> Button:
	if choice_index < 0 or choice_index >= _fate_choice_buttons.size():
		return null
	var button := _fate_choice_buttons[choice_index]
	if button == null or not is_instance_valid(button):
		return null
	return button


## 这张卡此刻能不能买。返回空串 = 可买；否则是拒绝原因码。
## 顺序即优先级：已购买 > 命运槽已满 > 金币不足。
func _fate_card_block_reason(choice_index: int) -> String:
	if not _door_fate_active or choice_index < 0 or choice_index >= _door_fate_choices.size():
		return "invalid"
	if choice_index < _door_fate_purchased.size() and _door_fate_purchased[choice_index]:
		return "purchased"
	var button := _fate_choice_button(choice_index)
	if button != null and bool(button.get_meta("tarot_purchased", false)):
		return "purchased"
	var card := _door_fate_choices[choice_index]
	if _is_weapon_fate_target_full(card):
		return "slot_full"
	if GameManager.currency < _fate_price(card):
		return "insufficient"
	return ""


## 买不了时的唯一反馈口：不扣金币、不关弹窗、不播选中动画。
##
## 反馈落在**三个地方**，优先级从高到低：卡片本身（抖动 + 价格行闪烁）→ 余额行
## （金币不足时闪红）→ 状态栏文字（最好看的理由）。原因是视线分布：状态栏在屏幕左上角，
## 而玩家的视线在三张卡上，「点了没反应」是购卡界面最容易被当成 bug 的体验。
func _report_fate_block(choice_index: int, block_reason: String) -> void:
	var card := (
		_door_fate_choices[choice_index]
		if choice_index >= 0 and choice_index < _door_fate_choices.size()
		else null
	)
	var card_name := card.card_name if card != null else "命运卡"
	match block_reason:
		"purchased":
			status_label.text = "%s 已购买 · 同一次门后不能重复购买" % card_name
		"slot_full":
			status_label.text = "%s：目标枪命运槽已满，无法购买" % card_name
		"insufficient":
			status_label.text = "%s 需要 %d 金币，当前只有 %d 金币" % [
				card_name, _fate_price(card), GameManager.currency,
			]
		_:
			status_label.text = "%s 当前无法购买" % card_name
	# 先刷新再闪：价格行的最终文字与字色由 `_refresh_door_fate_prices()` 决定，
	# 顺序反过来会让这次的提亮被随后的着色当场冲掉。
	_refresh_door_fate_prices()
	_play_fate_reject_feedback(choice_index)
	if block_reason == "insufficient":
		_play_fate_balance_shortage_feedback()


## 买不了时的**卡上**反馈：卡片横向抖动 + 价格行瞬时提亮放大。
##
## 为什么抖 `position:x`：这三张卡有常驻的错相漂浮（动 `position:y` 与 `rotation`），
## 悬停/选中动的是整列 `scale`。`position:x` 是这条链上唯一空闲的通道，三者叠加互不覆盖。
## 抖完回到**当次取值**而不是写死的 0：容器在抖动期间重排也不会把卡写坏。
func _play_fate_reject_feedback(choice_index: int) -> void:
	var button := _fate_choice_button(choice_index)
	if button == null:
		return
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		return
	var column := (
		button.get_meta("fate_feedback_view") if button.has_meta("fate_feedback_view") else null
	) as Control
	if column != null and is_instance_valid(column):
		var key := button.get_instance_id()
		# 🔴 基准 x 记在 meta 上、跨调用复用：若每次都以「当前 position.x」为基准，
		# 连点会在上一轮还没归位时取到中间值，卡位会一轮轮往右漂。
		var base_x := float(button.get_meta("fate_shake_base_x", column.position.x))
		button.set_meta("fate_shake_base_x", base_x)
		var previous: Variant = _fate_shake_tweens.get(key, null)
		if previous != null and is_instance_valid(previous):
			(previous as Tween).kill()
		column.position.x = base_x
		var shake := column.create_tween()
		shake.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		shake.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		shake.tween_property(column, "position:x", base_x + FATE_REJECT_SHAKE_PX, FATE_REJECT_SHAKE_DURATION * 0.18)
		shake.tween_property(column, "position:x", base_x - FATE_REJECT_SHAKE_PX * 0.72, FATE_REJECT_SHAKE_DURATION * 0.28)
		shake.tween_property(column, "position:x", base_x + FATE_REJECT_SHAKE_PX * 0.42, FATE_REJECT_SHAKE_DURATION * 0.26)
		shake.tween_property(column, "position:x", base_x, FATE_REJECT_SHAKE_DURATION * 0.28)
		# 收尾再写死一次基准：tween 的最后一帧只到「接近 base_x」，显式归位消除浮点残留。
		shake.tween_callback(_reset_fate_card_shake_x.bind(button, base_x))
		_fate_shake_tweens[key] = shake
	# 价格行同步闪一下并按一下：视线落在卡上，反馈就要落在卡上。
	var price_label := (
		button.get_meta("tarot_price_label") if button.has_meta("tarot_price_label") else null
	) as Label
	if price_label == null or not is_instance_valid(price_label):
		return
	var flash_key := button.get_instance_id()
	var previous_flash: Variant = _fate_price_flash_tweens.get(flash_key, null)
	if previous_flash != null and is_instance_valid(previous_flash):
		(previous_flash as Tween).kill()
	price_label.pivot_offset = price_label.size * 0.5
	price_label.scale = Vector2.ONE
	price_label.modulate = Color.WHITE
	var flash := price_label.create_tween()
	flash.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	flash.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash.tween_property(price_label, "scale", Vector2.ONE * FATE_REJECT_PRICE_SCALE, 0.10)
	flash.parallel().tween_property(price_label, "modulate", FATE_REJECT_PRICE_FLASH, 0.10)
	flash.tween_property(price_label, "scale", Vector2.ONE, 0.20)
	flash.parallel().tween_property(price_label, "modulate", Color.WHITE, 0.20)
	_fate_price_flash_tweens[flash_key] = flash


func _reset_fate_card_shake_x(button: Button, base_x: float) -> void:
	if button == null or not is_instance_valid(button):
		return
	var column := (
		button.get_meta("fate_feedback_view") if button.has_meta("fate_feedback_view") else null
	) as Control
	if column != null and is_instance_valid(column):
		column.position.x = base_x


## 把价格行的拒绝闪烁归位。防御性收尾：闪烁若被中途 kill，scale 会卡在 1.14 上 ——
## 视觉上就是一行比别张卡更大的字，而且看不出原因（正是 `_reset_fate_feedback` 要清掉的那类残影）。
func _reset_fate_price_flash(button: Button) -> void:
	if button == null or not is_instance_valid(button):
		return
	var key := button.get_instance_id()
	var previous: Variant = _fate_price_flash_tweens.get(key, null)
	if previous != null and is_instance_valid(previous):
		(previous as Tween).kill()
	_fate_price_flash_tweens.erase(key)
	var price_label := (
		button.get_meta("tarot_price_label") if button.has_meta("tarot_price_label") else null
	) as Label
	if price_label != null and is_instance_valid(price_label):
		price_label.scale = Vector2.ONE
		price_label.modulate = Color.WHITE


## 金币读数「金币不足」反馈：整行闪红再回到常色。
##
## 只闪红、**不抖动**：抖动是「这张卡拒绝你」的语义，两种反馈不能共用同一个动作，
## 否则玩家分不清是卡的问题还是钱的问题。这里闪红就是把原因直接指回钱上。
## 宿主是右下角金币读数（主人 2026-10-15：顶部余额行移除后它是唯一金币口径）。
func _play_fate_balance_shortage_feedback() -> void:
	var label := loot_label
	if label == null or not is_instance_valid(label):
		return
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		return
	label.add_theme_color_override("font_color", FATE_BALANCE_SHORTAGE_COLOR)
	if _fate_balance_warn_tween != null and _fate_balance_warn_tween.is_valid():
		_fate_balance_warn_tween.kill()
	# tween 宿主用 label 本身而不是弹窗：闪红可能发生在弹窗即将关闭的瞬间，
	# 挂在弹窗上会让「恢复常色」跟着弹窗一起被销毁，读数从此卡在红色。
	_fate_balance_warn_tween = label.create_tween()
	_fate_balance_warn_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fate_balance_warn_tween.tween_interval(FATE_BALANCE_SHORTAGE_DURATION)
	_fate_balance_warn_tween.tween_callback(_restore_fate_balance_color)


func _restore_fate_balance_color() -> void:
	if loot_label != null and is_instance_valid(loot_label):
		loot_label.add_theme_color_override("font_color", RUN_COIN_READOUT_COLOR)


## 金币读数的数字变化脉冲：scale 弹到 `FATE_BALANCE_PULSE_SCALE` 再弹回。
##
## 消费（买命运卡）与获得（捡金币/击杀赏金/退款）共用同一条曲线 ——
## 主人 2026-10-15：消费时的数字变化动画，获得金币的时候也要有。
## 数值方向由调用方保证：这里只负责「数字变了，让人看见」。
func _pulse_coin_readout() -> void:
	var label := loot_label
	if label == null or not is_instance_valid(label):
		return
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		return
	if _fate_balance_warn_tween != null and _fate_balance_warn_tween.is_valid():
		_fate_balance_warn_tween.kill()
	_restore_fate_balance_color()
	label.pivot_offset = label.size * 0.5
	if _fate_balance_pulse_tween != null and _fate_balance_pulse_tween.is_valid():
		_fate_balance_pulse_tween.kill()
	label.scale = Vector2.ONE
	_fate_balance_pulse_tween = label.create_tween()
	_fate_balance_pulse_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fate_balance_pulse_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fate_balance_pulse_tween.tween_property(
		label, "scale", Vector2.ONE * FATE_BALANCE_PULSE_SCALE, FATE_BALANCE_PULSE_DURATION * 0.35
	)
	_fate_balance_pulse_tween.tween_property(label, "scale", Vector2.ONE, FATE_BALANCE_PULSE_DURATION * 0.65)


## 扣款反馈：右下金币读数弹一下 + 读数上方浮出 `-N 金币` 飘字。
##
## 为什么光靠读数数字不够：32 → 2 是一次「文本替换」，一闪而过、很容易被忽略；
## 飘字把「刚才那一下花了多少」写明白，玩家不用自己拿两次读数相减。
func _play_fate_balance_spend_feedback(amount: int) -> void:
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		return
	_pulse_coin_readout()
	_spawn_fate_spend_popup(amount)


## 扣款飘字：从右下金币读数上方浮起并淡出，播完自毁。
## 位置跟着金币读数（同为右下 1.0 锚点、贴在它正上方），确保「减去多少」贴着钱看。
func _spawn_fate_spend_popup(amount: int) -> void:
	if _fate_overlay == null or not is_instance_valid(_fate_overlay):
		return
	var popup := _make_hud_label("- %d 金币" % amount, 26, FATE_SPEND_POPUP_COLOR)
	popup.name = "FateCurrencySpendPopup"
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	popup.add_theme_constant_override("outline_size", _hud_int(4))
	# 读数占 `(-420,-148)..(-36,-90)`（右下 1.0 锚点），飘字贴其正上方 `8 px`。
	_anchor_control(popup, 1.0, 1.0, 1.0, 1.0, -430, -200, -60, -156)
	_fate_overlay.add_child(popup)
	var start_y := popup.position.y
	var rise := float(_hud_int(FATE_SPEND_POPUP_RISE))
	var tween := popup.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "position:y", start_y - rise, FATE_SPEND_POPUP_LIFETIME)
	tween.parallel().tween_property(popup, "modulate:a", 0.0, FATE_SPEND_POPUP_LIFETIME)
	tween.tween_callback(popup.queue_free)


## 刷新三张卡的卡下价格行与置灰状态。扣金币/购买/打开弹窗后必须调用。
## （顶部余额行已移除：金币读数由 `loot_label` 经 `currency_changed` 信号链自行刷新。）
func _refresh_door_fate_prices() -> void:
	for choice_index in range(_door_fate_choices.size()):
		var button := _fate_choice_button(choice_index)
		if button == null:
			continue
		var card := _door_fate_choices[choice_index]
		var purchased := bool(button.get_meta("tarot_purchased", false))
		var block_reason := (
			"purchased" if purchased else _fate_card_block_reason(choice_index)
		)
		var label := button.get_meta("tarot_price_label") as Label
		if label != null and is_instance_valid(label):
			match block_reason:
				"purchased":
					label.text = "已购买"
					label.add_theme_color_override("font_color", FATE_PURCHASED_TEXT_COLOR)
				"slot_full":
					label.text = "命运槽已满"
					label.add_theme_color_override("font_color", Color(1.0, 0.44, 0.34))
				"insufficient":
					# 主人 2026-10-19：卡下只写价格，不写「还差 M」。
					# 买不起这件事由字色（琥珀）+ 卡片轻度压暗表达；右下金币读数就在同一屏，
					# 玩家自己对照即可，卡下不必再替他算一遍减法。
					label.text = "◈ %d 金币" % _fate_price(card)
					label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.36))
				_:
					# 同样只留价格：远征动态报价的「区间 a–b」也不再上屏（主人 2026-10-19）。
					label.text = "◈ %d 金币" % _fate_price(card)
					label.add_theme_color_override("font_color", _rarity_color(card.card_rarity))
		# 三种不可买状态的压暗强度刻意分两档：
		# · 已购买 ⇒ **灰阶 + 压暗 + 缩到 70%**（卡位用掉了，退到背景）
		# · 买不起 / 槽满 ⇒ 只做轻度压暗。它们是「暂时/本枪买不了」，不是「已经没了」，
		#   压成灰阶会让玩家以为这张卡已经消失，其实是攒够金币就能买。
		var view := button.get_meta("fate_feedback_view") as Control
		if view != null and is_instance_valid(view):
			if purchased:
				view.modulate = FATE_PURCHASED_DIM_COLOR
			elif block_reason.is_empty():
				view.modulate = Color.WHITE
			else:
				view.modulate = Color(0.56, 0.59, 0.64)


## 退出命运卡购买时的统一退场：三张卡同时「翻回背面 + 缩小 + 淡出」，
## 动画结束后才清理覆盖层。这里不直接把 `_door_fate_active` 置 false，
## 否则 ESC/手柄 B 在动画期间会让玩家输入穿透到战斗层。
func _animate_fate_overlay_exit(bought: int) -> void:
	var overlay := _fate_overlay
	if overlay == null or not is_instance_valid(overlay):
		_finish_fate_overlay_exit(overlay, bought)
		return
	_fate_feedback_locked = true
	if _fate_feedback_dispatch != null and _fate_feedback_dispatch.is_valid():
		_fate_feedback_dispatch.kill()
	_fate_feedback_dispatch = null
	_set_fate_feedback_buttons_disabled(true)
	if _fate_exit_button != null and is_instance_valid(_fate_exit_button):
		_fate_exit_button.disabled = true
		_fate_exit_button.release_focus()
	var cards: Array[Dictionary] = []
	for button in _fate_choice_buttons:
		if button == null or not is_instance_valid(button):
			continue
		var view := (button.get_meta("fate_feedback_view") if button.has_meta("fate_feedback_view") else null) as Control
		if view == null or not is_instance_valid(view):
			continue
		# 退场接管当前姿态，不先跳回基准缩放；停掉进场/购买翻牌与漂浮，避免抢写。
		_kill_fate_feedback_tween(button)
		for host in [button, view]:
			for key in ["fate_flip_tween", "fate_idle_tween"]:
				var previous: Tween = host.get_meta(key) as Tween if host.has_meta(key) else null
				if previous != null and previous.is_valid():
					previous.kill()
		button.pivot_offset = button.size * 0.5
		view.pivot_offset = view.size * 0.5
		cards.append({"button": button, "view": view, "scale": view.scale, "alpha": view.modulate.a, "flip_x": button.scale.x})
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		_finish_fate_overlay_exit(overlay, bought)
		return
	# 全部属性由同一进度驱动：没有相互串行的 parallel()、也没有提前回收的固定计时器。
	var exit_tween := overlay.create_tween()
	overlay.set_meta("fate_exit_tween", exit_tween)
	exit_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	exit_tween.tween_method(_sample_fate_overlay_exit.bind(overlay, cards), 0.0, 1.0, FATE_OVERLAY_EXIT_DURATION)
	exit_tween.tween_callback(_finish_fate_overlay_exit.bind(overlay, bought))


func _sample_fate_overlay_exit(progress: float, overlay: Control, cards: Array[Dictionary]) -> void:
	if not is_instance_valid(overlay) or overlay != _fate_overlay:
		return
	overlay.set_meta("fate_exit_progress", progress)
	var flip_mid := FATE_OVERLAY_EXIT_FLIP_DURATION / FATE_OVERLAY_EXIT_DURATION
	for state in cards:
		var button: Button = state["button"]
		var view: Control = state["view"]
		if not is_instance_valid(button) or not is_instance_valid(view):
			continue
		if progress <= flip_mid:
			var fold := clampf(progress / flip_mid, 0.0, 1.0)
			button.scale.x = lerpf(float(state["flip_x"]), 0.04, fold * fold)
		else:
			# 有卡背时才换面，缺背图保持原层；不改变已购卡灰阶/半透明样式。
			var back := button.get_meta("tarot_back_node") as Control if button.has_meta("tarot_back_node") else null
			if back != null and is_instance_valid(back):
				_show_fate_card_back(button)
			var unfold := clampf((progress - flip_mid) / flip_mid, 0.0, 1.0)
			button.scale.x = lerpf(0.04, 1.0, 1.0 - pow(1.0 - unfold, 2.0))
		# 前段保留足够的卡形读出翻面，尾段缩到零并淡出，节点销毁时已不可见。
		view.scale = (state["scale"] as Vector2) * (1.0 - progress * progress)
		view.modulate.a = float(state["alpha"]) * (1.0 - progress * progress)
	# 余额、退出按钮和遮罩也随尾段淡出，而不是最后一帧突然消失。
	overlay.modulate.a = 1.0 - clampf((progress - 0.55) / 0.45, 0.0, 1.0)


func _finish_fate_overlay_exit(overlay: Control, bought: int) -> void:
	# 紧急清理或重开以后，旧动画不得关闭新弹窗。
	if not _door_fate_active or overlay != _fate_overlay:
		return
	_close_door_fate_overlay()
	status_label.text = (
		"已退出命运购买 · 本次买下 %d 张 · 行动继续" % bought
		if bought > 0
		else "已退出命运购买 · 未消费金币 · 行动继续"
	)


func _close_door_fate_overlay() -> void:
	# 这是最终清理口。用户点击退出时会先走 `_animate_fate_overlay_exit()`；
	# 其他流程（房间切换、测试收尾、异常中止）仍可直接调用这里硬清理。
	_fate_overlay_closing = false
	_reset_fate_feedback(true)
	_door_fate_active = false
	_door_fate_choices.clear()
	_door_fate_purchased.clear()
	_fate_choice_buttons.clear()
	_fate_exit_button = null
	# 金币读数的层级随弹窗一起复原：弹窗开着时它被提到暗化层之上，
	# 关掉后必须回到普通 HUD 层，否则后续弹层（背包/暂停）再也压不住它。
	if loot_label != null and is_instance_valid(loot_label):
		loot_label.z_index = 0
	if _fate_overlay != null and is_instance_valid(_fate_overlay):
		# 先摘除再回收：queue_free() 要等到帧末才真正释放节点。若同一帧内再次
		# 打开弹窗（连续两次命运卡流程/验收用例），新节点会与仍挂在树上的旧节点
		# 撞名、被引擎静默改名为 DoorFateOverlay3D2，此后所有按名查询
		# （探针/验收里的 HUD/DoorFateOverlay3D）就再也找不到这个弹窗。
		var overlay_parent := _fate_overlay.get_parent()
		if overlay_parent != null:
			overlay_parent.remove_child(_fate_overlay)
		_fate_overlay.queue_free()
	_fate_overlay = null
	_fate_feedback_label = null
	# 反馈 tween 的宿主已经销毁，引用一并清掉，免得下一轮弹窗拿到失效对象。
	_fate_shake_tweens.clear()
	_fate_price_flash_tweens.clear()
	_fate_balance_pulse_tween = null
	_fate_balance_warn_tween = null
	_commit_pending_fate_door_streaming()
	_queue_runtime_autosave("fate_door_closed")
	_sync_player_input_lock()


func _commit_pending_fate_door_streaming() -> void:
	if _pending_fate_door_target_id.is_empty():
		return
	var source_id := _pending_fate_door_from_id
	_pending_fate_door_from_id = ""
	_pending_fate_door_target_id = ""
	_update_room_streaming(source_id if not source_id.is_empty() else _current_room_id)


## 退出按钮 / ESC / 手柄 B 三条路共用：已买下的卡保持生效，未买的直接放弃。
## 点击退出不会硬切：三张卡先同步翻回背面并缩小淡出，动画完成后才关闭弹窗。
func _cancel_door_fate_selection() -> void:
	if not _door_fate_active or _fate_overlay_closing:
		return
	_fate_overlay_closing = true
	var bought := 0
	for purchased in _door_fate_purchased:
		if purchased:
			bought += 1
	_animate_fate_overlay_exit(bought)


func show_reference_fate_overlay_for_test() -> bool:
	if _door_fate_active:
		return false
	var pool := FateCardPresets.door_reward_presets()
	_door_fate_choices.clear()
	_door_fate_purchased.clear()
	for wanted_scope in [FateCard.Scope.WEAPON, FateCard.Scope.WORLD, FateCard.Scope.CHARACTER]:
		for card in pool:
			if card.scope == wanted_scope:
				_door_fate_choices.append(card)
				break
	if _door_fate_choices.size() != 3:
		return false
	_door_fate_choices[0].set_orientation(FateCard.Orientation.UPRIGHT, 0.25)
	_door_fate_choices[1].set_orientation(FateCard.Orientation.REVERSED, 0.75)
	_door_fate_choices[2].set_orientation(FateCard.Orientation.UPRIGHT, 0.25)
	_fate_door_offer_id += 1
	_fate_door_quote.clear()
	for card in _door_fate_choices:
		_fate_door_quote[card.get_stable_card_id()] = int(FATE_PRICE_BY_RARITY[clampi(int(card.card_rarity), 0, FATE_PRICE_BY_RARITY.size() - 1)])
	for _choice_index in range(_door_fate_choices.size()):
		_door_fate_purchased.append(false)
	_door_fate_active = true
	_close_inventory_for_modal()
	_sync_player_input_lock()
	_build_door_fate_overlay()
	status_label.text = "视觉验收 · 命运卡购买"
	return true


## 测试口：退出门后购卡弹窗，把门后流程推下去。
## 购买经济（扣金币 / 余额不足 / 满槽 / 已购买 / 退出按钮）由
## `verify_fate_card_purchase_flow` 专项覆盖；这里刻意不消费金币、不应用卡，
## 免得给既有流程用例塞进一张随机命运带来副作用。
func resolve_fate_choice_for_test(_choice_index := 0) -> void:
	if not _door_fate_active:
		return
	_close_door_fate_overlay()


func _get_total_room_keys() -> int:
	return _room_key_count + _temporary_room_keys + (_inventory.get_item_count("item_room_key") if _inventory != null else 0)


func _consume_room_key() -> void:
	if _temporary_room_keys > 0:
		_temporary_room_keys -= 1
	elif _inventory != null and _inventory.has_item("item_room_key"):
		_inventory.consume_item("item_room_key", 1)
	else:
		_room_key_count = maxi(0, _room_key_count - 1)


func _refresh_edge_visuals(a: String, b: String, opened: bool) -> void:
	var room_a := _room_by_id.get(a) as DungeonRoom3D
	var room_b := _room_by_id.get(b) as DungeonRoom3D
	if room_a == null or room_b == null:
		return
	# 已拆门的98F固定通道不能被旧存档的关门状态重新封锁。
	if room_a.authored_layout_asset_id == "ENV-BATTLE-BLOCK00-ART-LAYOUT-3D" and Block00MasterOfficeLayout3D.is_removed_door_pair(a, b):
		opened = true
		_open_edges[_edge_key(a, b)] = true
	var direction_a := _direction_between(room_a.global_position, room_b.global_position)
	room_a.set_door_open(direction_a, opened)
	room_b.set_door_open(_opposite_direction(direction_a), opened)


func _update_room_streaming(current_id: String) -> void:
	_room_graph_runtime.configure(_records, _room_neighbors, _open_edges)
	for room in _rooms:
		var state := _room_graph_runtime.resolve_stream_state(
			room.room_id,
			current_id,
			DungeonRoom3D.STREAM_DATA_ONLY,
			DungeonRoom3D.STREAM_SHELL_READY,
			DungeonRoom3D.STREAM_ACTIVE
		)
		var transition := _room_graph_runtime.commit_stream_state(
			room.room_id, state, DungeonRoom3D.STREAM_DATA_ONLY
		)
		if bool(transition.get("changed", false)):
			if bool(transition.get("hibernate", false)):
				_hibernate_room_entities(room.room_id)
		room.set_stream_state(state)
		if state > 0:
			_prepare_revealed_hostile_room(room)
			# 运行快照只在房间从 DATA_ONLY 真正重新载入时回灌。开门会刷新
			# 当前房和邻房的流送状态；若对仍处于 ACTIVE/SHELL_READY 的房间
			# 无条件回灌，战斗中较早保存的快照会覆盖刚提交的 cleared、灯光和
			# 敌人集合，表现为“清房后开门，当前房间又刷新”。
			if (
				bool(transition.get("changed", false))
				and int(transition.get("previous", DungeonRoom3D.STREAM_DATA_ONLY))
				== DungeonRoom3D.STREAM_DATA_ONLY
			):
				_restore_room_runtime_state(room.room_id)
	_update_corridor_streaming(current_id)
	for room_id in _enemy_nodes_by_room.keys():
		var live_references: Array = []
		for value in _enemy_nodes_by_room[room_id]:
			if not is_instance_valid(value) or (value as Node).is_queued_for_deletion():
				continue
			var enemy := value as Enemy3D
			if enemy != null and is_instance_valid(enemy):
				live_references.append(enemy)
				var enemy_room := _room_by_id.get(str(room_id)) as DungeonRoom3D
				var room_visible := (
					enemy_room != null
					and enemy_room.is_streamed()
				)
				enemy.set_runtime_active(str(room_id) == current_id, room_visible)
		_enemy_nodes_by_room[room_id] = live_references


func _hibernate_room_entities(room_id: String) -> void:
	_cancel_room_wave_intermission(room_id)
	_capture_room_runtime_state(room_id)
	for value in _enemy_nodes_by_room.get(room_id, []):
		if not is_instance_valid(value) or not value is Enemy3D:
			continue
		var enemy := value as Enemy3D
		if MonsterAIManager != null:
			MonsterAIManager.unregister_enemy(enemy)
		enemy.queue_free()
	_enemy_nodes_by_room[room_id] = []
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null:
		return
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and room.is_ancestor_of(value) and not value.is_queued_for_deletion() and not (value as GroundLootPickup3D).is_pickup_accepted():
			(value as GroundLootPickup3D).queue_free()
	for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
		if value is RoomKeyPickup3D and room.is_ancestor_of(value):
			(value as RoomKeyPickup3D).queue_free()


func _capture_room_runtime_state(room_id: String) -> void:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null or not is_instance_valid(room):
		return
	var enemy_states: Array[Dictionary] = []
	for value in _enemy_nodes_by_room.get(room_id, []):
		if not is_instance_valid(value) or not value is Enemy3D:
			continue
		var enemy := value as Enemy3D
		if enemy.ai_state == "dead":
			continue
		enemy_states.append(enemy.export_runtime_state())
	var ground_items: Array[Dictionary] = []
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and room.is_ancestor_of(value) and not value.is_queued_for_deletion() and not (value as GroundLootPickup3D).is_pickup_accepted():
			var pickup := value as GroundLootPickup3D
			ground_items.append({
				"item_data": pickup.item_data.duplicate(true),
				"position": [pickup.global_position.x, pickup.global_position.y, pickup.global_position.z],
			})
	var room_keys: Array[Dictionary] = []
	if _room_produces_room_key(room):
		for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
			if value is RoomKeyPickup3D and room.is_ancestor_of(value) and not value.is_queued_for_deletion():
				var key := value as RoomKeyPickup3D
				room_keys.append({
					"room_id": key.room_id,
					"position": [key.global_position.x, key.global_position.y, key.global_position.z],
				})
	var container_states: Dictionary = {}
	for value in get_tree().get_nodes_in_group("room_prop_3d"):
		if value is RoomFurniture3D and room.is_ancestor_of(value):
			var prop := value as RoomFurniture3D
			container_states[prop.prop_id] = prop.is_searched()
	# 宝箱与易碎杂物读**房间自持的账**，不扫 group。理由见
	# `DungeonRoom3D.get_persistent_detail_state()`：detail 已随流送卸载时，
	# 组里一件实例都没有，扫出来是空表，会把「开过的箱子 / 砸碎的罐子」洗回未开。
	# 这两本账跟着房间节点走，与 `visited` / `cleared` 同一权威层级。
	_segment_runtime_state[room_id] = {
		"visited": room.visited,
		"cleared": room.cleared,
		"room_light_on": room.is_room_light_on(),
		"enemies": enemy_states,
		"ground_items": ground_items,
		"room_keys": room_keys,
		"containers": container_states,
		"treasure_chests": room.get_persistent_detail_state("treasure_chests"),
		"breakable_clutter": room.get_persistent_detail_state("breakable_clutter"),
		"alive_count": int(_alive_by_room.get(room_id, enemy_states.size())),
		"spawn_blocked": _room_spawn_blocked.has(room_id),
		"fate_wave_queued": _room_fate_wave_queued.has(room_id),
		"reserved_spawns": (_reserved_room_spawns.get(room_id, []) as Array).duplicate(true),
		"wave_queue": (_room_wave_queues.get(room_id, []) as Array).duplicate(true),
		"wave_number": int(_room_wave_numbers.get(room_id, 1)),
		"wave_total": int(_room_wave_totals.get(room_id, 1)),
		# 🔴 本房有没有「建立过波次账」的显式标记。见 `_restore_room_runtime_state`
		#    顶部注释：没这个标记就无法区分「真的只有 1 波」和「抓快照时还没刷怪」。
		"wave_established": _room_wave_totals.has(room_id),
		"boss_reinforcement_state": (
			_boss_reinforcement_states.get(room_id, {}) as Dictionary
		).duplicate(true),
		"captured_at_msec": Time.get_ticks_msec(),
	}


## 主线开场 2.5 的窄灯光边界：只同步目标房间的灯光布尔值，
## 不触发整房捕获/恢复，不触碰敌人、掉落物或容器状态。
func apply_narrative_light_state(room_id: String, enabled: bool) -> bool:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null or not is_instance_valid(room):
		return false
	if not room.has_method("apply_narrative_light_state"):
		return false
	if not bool(room.call("apply_narrative_light_state", enabled)):
		return false
	if _segment_runtime_state.has(room_id):
		var state := _segment_runtime_state[room_id] as Dictionary
		state["room_light_on"] = enabled
		_segment_runtime_state[room_id] = state
	return true


func _normalize_narrative_02_stationary_data(enemy_data: Dictionary, room_id: String) -> void:
	# 剧情02旧快照曾把98F会议室后三只怪标成冻结策略；内容已改为普通AI。
	# 只迁移稳定ID对应的三只，保留血量、位置、持久ID与幂等账，不重刷也不复活。
	if room_id != "floor_01_main_02":
		return
	var persistent_id := str(enemy_data.get("persistent_id", ""))
	if not persistent_id.begins_with("nar_tower_opening_02_zombies:stationary_"):
		return
	if persistent_id not in [
		"nar_tower_opening_02_zombies:stationary_0:0",
		"nar_tower_opening_02_zombies:stationary_1:0",
		"nar_tower_opening_02_zombies:stationary_2:0",
	]:
		return
	enemy_data["narrative_stationary"] = false
	if not enemy_data.has("narrative_placement"):
		enemy_data["narrative_placement"] = "room_floor"


func _restore_room_runtime_state(room_id: String) -> void:
	if not _segment_runtime_state.has(room_id):
		return
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room == null or not is_instance_valid(room):
		return
	_cancel_room_wave_intermission(room_id)
	var state := _segment_runtime_state[room_id] as Dictionary
	if bool(state.get("spawn_blocked", false)):
		_room_spawn_blocked[room_id] = true
	if bool(state.get("fate_wave_queued", false)):
		_room_fate_wave_queued[room_id] = true
	# 🔴 快照可能是「本房建立波次之前」抓的：`_on_room_entered` 里的存档点
	#    (`BaseManager.flush_runtime_checkpoint("room_transition")`) 跑在
	#    `_spawn_room_enemies` **之前**，那时本房还没有 `_room_wave_totals` 条目，
	#    落进快照的 `wave_total` 只是 `get()` 的兜底值 1、`wave_queue` 是空数组、
	#    `alive_count`/`reserved_spawns` 也都是空的。
	#    这种快照一旦回灌，会把 `_commit_room_waves` 刚写好的波次账覆盖回
	#    「1 波 · 无待发队列」⇒ 清完第一波时 `_resolve_room_enemy_departure`
	#    看到空队列，直接 `_mark_room_cleared(room, true)`，第 2 波起永不出现。
	#    玩家侧观感就是「波次不续、必须跑去按离开的门才会推进」。
	#    判据：快照没建立过波次账（旧存档缺该字段一律按「没建立」处理），
	#    而本局运行态已经建立 ⇒ 保留运行态，战斗账整段不回灌。
	var snapshot_established_waves := bool(state.get("wave_established", false))
	var keep_live_combat_progress := (
		not snapshot_established_waves and _room_wave_totals.has(room_id)
	)
	room.visited = bool(state.get("visited", room.visited))
	var boss_reinforcement_state := state.get("boss_reinforcement_state", {}) as Dictionary
	if not boss_reinforcement_state.is_empty():
		_boss_reinforcement_states[room_id] = boss_reinforcement_state.duplicate(true)
	if not keep_live_combat_progress:
		_reserved_room_spawns[room_id] = (state.get("reserved_spawns", []) as Array).duplicate(true)
		room.cleared = bool(state.get("cleared", room.cleared))
		_alive_by_room[room_id] = maxi(0, int(state.get("alive_count", _alive_by_room.get(room_id, 0))))
		_room_wave_queues[room_id] = (state.get("wave_queue", []) as Array).duplicate(true)
		_room_wave_numbers[room_id] = maxi(0, int(state.get("wave_number", 1)))
		_room_wave_totals[room_id] = maxi(1, int(state.get("wave_total", 1)))
	# 宝箱/杂物只在**存档确实带了这个键**时才下发：旧存档两个键都没有，
	# 传空字典会盖掉房间内存里的账（`apply_runtime_detail_state()` 是合并语义，
	# 但空字典本身也是一次有效的写入）。缺席即"这局没有记录"，不动内存账。
	var detail_state := {
		"room_light_on": bool(state.get("room_light_on", false)),
		"containers": (state.get("containers", {}) as Dictionary).duplicate(true),
	}
	for optional_key in ["treasure_chests", "breakable_clutter"]:
		if state.has(optional_key):
			detail_state[optional_key] = (state[optional_key] as Dictionary).duplicate(true)
	room.apply_runtime_detail_state(detail_state)
	var live_enemies: Array = []
	for value in _enemy_nodes_by_room.get(room_id, []):
		if is_instance_valid(value) and not (value as Node).is_queued_for_deletion() and value is Enemy3D:
			live_enemies.append(value)
			var persistent_id := (value as Enemy3D).get_persistent_id()
			for runtime_value in state.get("enemies", []):
				var enemy_state := runtime_value as Dictionary
				if str(enemy_state.get("persistent_id", "")) == persistent_id:
					_normalize_narrative_02_stationary_data((value as Enemy3D).enemy_data, room_id)
					(value as Enemy3D).import_runtime_state(enemy_state)
					break
	if live_enemies.is_empty():
		for runtime_value in state.get("enemies", []):
			var enemy_state := runtime_value as Dictionary
			var enemy_data := (enemy_state.get("enemy_data", {}) as Dictionary).duplicate(true)
			_normalize_narrative_02_stationary_data(enemy_data, room_id)
			if room.cleared and not bool(enemy_data.get("narrative_spawned", false)):
				continue
			if enemy_data.is_empty():
				enemy_data = {
					"enemy_type": str(enemy_state.get("enemy_kind", "melee_chaser")),
					"persistent_id": str(enemy_state.get("persistent_id", "")),
					"floor": maxi(1, visual_theme.difficulty_rank),
				}
			var enemy := ENEMY_SCENE.instantiate() as Enemy3D
			if enemy == null:
				continue
			enemy.room_id = room_id
			$ActiveEnemies.add_child(enemy)
			# 与 `_spawn_enemy_batch()` **同一条注入**（2026-10-30）。
			# 漏了它的话：读档恢复出来的怪 `_has_room_bounds` 恒为 false ⇒
			# 瞬移退回「以出生点为圆心、半径随位置自增」的圆形近似 ⇒ 一路飘出房。
			# 这正是"只有读档之后才会再次出现"的那类间歇性 bug。
			var restore_half := room.get_dimensions() * 0.5
			enemy.set_room_bounds(room.global_transform, restore_half)
			enemy.configure_from_enemy_data(enemy_data)
			if bool(enemy_data.get("narrative_spawned", false)):
				enemy.set_meta("narrative_spawned", true)
			enemy.set_meta("fate_kill_currency", int(enemy_data.get("fate_kill_currency", 0)))
			enemy.state_changed.connect(_on_fate_enemy_state_changed.bind(enemy))
			enemy.killed.connect(_on_enemy_killed)
			enemy.escaped.connect(_on_enemy_escaped)
			enemy.summon_requested.connect(_on_summon_requested)
			enemy.split_requested.connect(_on_split_requested)
			enemy.boss_phase_changed.connect(_on_boss_phase_changed)
			enemy.boss_activation_completed.connect(_on_boss_activation_completed)
			enemy.health_changed.connect(_on_enemy_health_changed)
			enemy.import_runtime_state(enemy_state)
			live_enemies.append(enemy)
			if enemy.enemy_kind == "boss":
				_show_boss_hud(enemy)
	_enemy_nodes_by_room[room_id] = live_enemies
	# 仅修复存活剧情怪的非法主层落点；兼容修复前原地怪/天台怪的快照。
	# 已合法的怪、血量与持久ID保持原值，快照里不存在的死怪不会被补回。
	var repaired_narrative_position := false
	for value in live_enemies:
		var enemy := value as Enemy3D
		if not bool(enemy.enemy_data.get("narrative_spawned", false)):
			continue
		var uses_room_floor := str(enemy.enemy_data.get("narrative_placement", "")) == "room_floor" or bool(enemy.enemy_data.get("narrative_stationary", false)) or room_id == "start"
		if not uses_room_floor or room.is_narrative_floor_position_valid(enemy.global_position):
			continue
		var occupied: Array[Vector3] = []
		for other in live_enemies:
			if other != enemy:
				occupied.append((other as Enemy3D).global_position)
		var safe := room.resolve_narrative_floor_positions([enemy.global_position], occupied)
		if not safe.is_empty():
			enemy.global_position = safe[0]
			enemy.velocity = Vector3.ZERO
			repaired_narrative_position = true
		else:
			push_warning("[Dungeon3D] 无法修复剧情怪快照落点：%s" % enemy.get_persistent_id())
	_alive_by_room[room_id] = live_enemies.size() + _reserved_spawn_count(room_id)
	if repaired_narrative_position:
		_capture_room_runtime_state(room_id)
	call_deferred("_flush_reserved_room_spawns", room_id)
	if room_id == _current_room_id and not room.cleared:
		_schedule_room_wave_intermission(room_id)
	_update_wave_hud(room_id)
	# 地面掉落只在当前 ACTIVE 房创建；邻房安全壳不承担可拾取物和预览模型成本。
	if room_id != _current_room_id:
		return
	var has_live_ground_item := false
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and room.is_ancestor_of(value) and not value.is_queued_for_deletion():
			has_live_ground_item = true
			break
	if not has_live_ground_item:
		for runtime_value in state.get("ground_items", []):
			var item_state := runtime_value as Dictionary
			var item_data := (item_state.get("item_data", {}) as Dictionary).duplicate(true)
			if item_data.is_empty():
				continue
			var pickup := GROUND_LOOT_SCRIPT.new() as GroundLootPickup3D
			pickup.configure(item_data, ItemModelFactory3D.get_item_color(item_data))
			room.add_child(pickup)
			var saved_position: Variant = item_state.get("position", room.global_position)
			if saved_position is Vector3:
				pickup.global_position = saved_position as Vector3
			elif saved_position is Array and (saved_position as Array).size() >= 3:
				pickup.global_position = Vector3(
					float((saved_position as Array)[0]),
					float((saved_position as Array)[1]),
					float((saved_position as Array)[2])
				)
			pickup.pickup_requested.connect(_on_ground_loot_requested)
	var has_live_room_key := false
	if not _room_produces_room_key(room):
		for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
			if value is RoomKeyPickup3D and room.is_ancestor_of(value):
				(value as RoomKeyPickup3D).queue_free()
	if _room_produces_room_key(room):
		for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
			if value is RoomKeyPickup3D and room.is_ancestor_of(value) and not value.is_queued_for_deletion():
				has_live_room_key = true
				break
		if not has_live_room_key:
			for runtime_value in state.get("room_keys", []):
				var key_state := runtime_value as Dictionary
				var key := KEY_SCRIPT.new() as RoomKeyPickup3D
				key.configure(str(key_state.get("room_id", room_id)))
				room.add_child(key)
				var saved_position: Variant = key_state.get("position", room.global_position)
				if saved_position is Array and (saved_position as Array).size() >= 3:
					key.global_position = Vector3(
						float((saved_position as Array)[0]),
						float((saved_position as Array)[1]),
						float((saved_position as Array)[2])
					)
				key.collected.connect(_on_room_key_collected)
				_spawned_key_rooms[room_id] = true


func get_segment_runtime_snapshot() -> Dictionary:
	_capture_loaded_runtime_rooms()
	return {
		"schema": "segment_runtime_state_v2",
		"current_room_id": _current_room_id,
		"room_count": _segment_runtime_state.size(),
		"rooms": _segment_runtime_state.duplicate(true),
		"stream_states": _room_graph_runtime.get_stream_states_snapshot(),
	}


func _capture_loaded_runtime_rooms() -> void:
	# 当前房及已预刷邻房都必须进快照。否则重启后会留下 spawned=true、
	# 但没有可恢复敌人的锁房。
	for room in _rooms:
		if room == null or room.get_stream_state() == DungeonRoom3D.STREAM_DATA_ONLY:
			continue
		if (
			room.room_id == _current_room_id
			or _spawned_rooms.has(room.room_id)
			or _segment_runtime_state.has(room.room_id)
		):
			_capture_room_runtime_state(room.room_id)


func _update_corridor_streaming(current_id: String) -> void:
	for edge in _corridor_by_edge.keys():
		var corridor := _corridor_by_edge[edge] as StaticBody3D
		if corridor == null:
			continue
		var ids := str(edge).split("|")
		var active := bool(_open_edges.get(edge, false)) and current_id in ids
		corridor.visible = active
		corridor.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		_set_corridor_collisions_disabled(corridor, not active)


func _on_insure_item_requested(slot_index: int) -> void:
	if not _insurance.insure_item(_inventory, slot_index):
		status_label.text = "保险格已满或物品无效"


func _on_insure_item_to_slot_requested(source_slot_index: int, insurance_slot_index: int, rotation: int = -1) -> void:
	if not _insurance.insure_item_to_slot(_inventory, source_slot_index, insurance_slot_index, rotation):
		status_label.text = "目标保险格不可用或物品无效"


func _on_claim_insurance_requested(slot_index: int) -> void:
	var item := _insurance.claim_item(slot_index)
	if item.is_empty():
		return
	var count := maxi(1, int(item.get("count", 1)))
	var inventory_before := _inventory.get_slots_snapshot()
	if _inventory.add_item(item, count) != count:
		_inventory.restore_slots_snapshot(inventory_before)
		_insurance.insure_item_direct(item)
		status_label.text = "背包已满，保险物品未取出"


func _on_insurance_item_move_requested(
	insurance_slot_index: int, target_index: int, target_kind: String, rotation: int = -1
) -> void:
	# 保险是“当前所在集合享受离场保留”，不是物品锁。转出采用背包与
	# 保险双快照；目标操作失败时恢复两个集合，避免丢失或复制。
	var inventory_before := _inventory.get_slots_snapshot()
	var insurance_before := _insurance.get_slots_snapshot()
	var quick_before := _quick_inventory.get_slots_snapshot()
	var item := _insurance.claim_item(insurance_slot_index)
	if item.is_empty():
		return
	if rotation >= 0:
		item["grid_rotation"] = rotation
	var count := maxi(1, int(item.get("count", 1)))
	var moved := false
	match target_kind:
		"inventory":
			moved = _inventory.put_item_in_empty_slot(target_index, item, count)
		"drop":
			moved = _drop_inventory_item_to_world(item, count)
		"quick_0", "quick_1":
			var quick_index := int(target_kind.trim_prefix("quick_"))
			var previous := _quick_inventory.get_slot(quick_index)
			if not previous.is_empty():
				_quick_inventory.clear_slot(quick_index)
			moved = _quick_inventory.put_item_in_empty_slot(quick_index, item, count)
			if moved and not previous.is_empty():
				moved = _insurance.insure_item_direct(
					(previous.get("item", {}) as Dictionary).merged(
						{"count": int(previous.get("count", 1))}, true
					)
				)
		"weapon_0", "weapon_1", "backpack":
			var staging_slot := _find_empty_inventory_slot()
			if staging_slot >= 0 and _inventory.put_item_in_empty_slot(staging_slot, item, count):
				moved = (
					_equip_weapon_from_inventory(staging_slot, item, int(target_kind.trim_prefix("weapon_")))
					if target_kind.begins_with("weapon_")
					else _equip_backpack_from_inventory(staging_slot, item)
				)
		_ when target_kind.begins_with("attachment_"):
			var staging_slot := _find_empty_inventory_slot()
			var parts := target_kind.split("_")
			if staging_slot >= 0 and parts.size() >= 3 and _inventory.put_item_in_empty_slot(staging_slot, item, count):
				moved = _install_attachment_from_inventory(
					staging_slot, item, int(parts[1]), int(parts[2])
				)
	if moved:
		_sync_quick_item_state()
		return
	_inventory.restore_slots_snapshot(inventory_before)
	_quick_inventory.restore_slots_snapshot(quick_before)
	_insurance.restore_slots_snapshot(insurance_before)
	status_label.text = "移动失败，物品仍保留在保险格"


func _find_empty_inventory_slot() -> int:
	for index in _inventory.get_capacity():
		if _inventory.get_slot(index).is_empty():
			return index
	return -1


func _on_inventory_item_clicked(slot_index: int, _item_hint: Dictionary) -> void:
	var slot := _inventory.get_slot(slot_index)
	if slot.is_empty():
		return
	var item := slot.get("item", {}) as Dictionary
	if str(item.get("id", "")) == "item_ammo_pack":
		status_label.text = (
			"开始装填 · 完成后按弹匣缺口扣除备弹"
			if player.request_reload()
			else "无需装填或背包没有可用备弹"
		)
		return
	if item.get("type", "") == "weapon":
		_equip_weapon_from_inventory(slot_index, item)
		return
	if str(item.get("type", "")) == "equipment" and str(item.get("subtype", "")) == "backpack":
		_equip_backpack_from_inventory(slot_index, item)
		return
	if str(item.get("subtype", "")) == "flashlight_module":
		var flashlight_handler := ItemUseHandler.new()
		var flashlight_applied := flashlight_handler.apply(item, {"player": player, "extraction_director": self})
		flashlight_handler.free()
		if flashlight_applied:
			_inventory.remove_from_slot(slot_index, 1)
			status_label.text = "已安装%s" % item.get("name", "手电筒模块")
		else:
			status_label.text = "%s只能在99F基地安装" % item.get("name", "手电筒模块")
		return
	if item.get("type", "") == "attachment":
		_install_attachment_from_inventory(slot_index, item, player.get_active_weapon_slot(), _slot_type_for_item(item))
		return
	if item.get("type", "") == "module":
		# 子弹模块走专用事务（写武器实例 + 旧模块回背包 + 装备界面立刻刷新）；
		# 其它模块（手电筒等）仍走原来的就地挂载路径。
		if str(item.get("subtype", "")) == "bullet":
			# 2026-10-19：手动更换总闸关闭。这里先拦一次，避免「先从背包扣 1 个、
			# 事务再拒绝」的中间态；真正的判据仍在 Player3D 事务里。
			if not WeaponBulletDrop.is_manual_swap_enabled():
				_reject_manual_bullet_module_swap()
				return
			_install_bullet_module_from_inventory(
				slot_index, item, player.get_active_weapon_slot()
			)
		elif _can_swap_installed_module(item, slot_index):
			_inventory.remove_from_slot(slot_index, 1)
			if not _install_weapon_module_from_item(item):
				_inventory.add_item(item, 1)
		return
	var use_action := str(item.get("use_action", ""))
	if use_action.is_empty():
		status_label.text = "%s：右键可存入保险格" % item.get("name", "物品")
		return
	var handler := ItemUseHandler.new()
	var applied := handler.apply(item, {"player": player, "extraction_director": self})
	handler.free()
	if applied:
		_inventory.remove_from_slot(slot_index, 1)
		status_label.text = "已使用 %s" % item.get("name", "物品")
	else:
		status_label.text = "%s 当前无法使用" % item.get("name", "物品")


func _on_weapon_slot_equip_requested(source_slot_index: int, weapon_slot_index: int) -> void:
	var slot := _inventory.get_slot(source_slot_index)
	if slot.is_empty():
		return
	var item := slot.get("item", {}) as Dictionary
	if str(item.get("type", "")) != "weapon":
		status_label.text = "只能把枪械拖入主/副武器栏"
		return
	_equip_weapon_from_inventory(source_slot_index, item, weapon_slot_index)


func _on_attachment_slot_install_requested(
	source_slot_index: int, weapon_slot_index: int, attachment_slot_type: int
) -> void:
	var source := _inventory.get_slot(source_slot_index)
	if source.is_empty():
		return
	_install_attachment_from_inventory(
		source_slot_index,
		source.get("item", {}) as Dictionary,
		weapon_slot_index,
		attachment_slot_type
	)


func _on_attachment_slot_remove_requested(
	weapon_slot_index: int, attachment_slot_type: int, target_slot_index: int
) -> void:
	_remove_attachment_to_inventory(weapon_slot_index, attachment_slot_type, target_slot_index)


func _on_attachment_slot_drop_requested(weapon_slot_index: int, attachment_slot_type: int) -> void:
	if player == null or not player.has_method("remove_attachment_from_weapon_slot"):
		return
	var result := player.call(
		"remove_attachment_from_weapon_slot", weapon_slot_index, attachment_slot_type
	) as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "配件拆卸失败"))
		return
	var removed_item := result.get("removed_item", {}) as Dictionary
	if _drop_inventory_item_to_world(removed_item, 1):
		status_label.text = "已从%s拆下并丢弃%s" % [
			"主武器" if weapon_slot_index == 0 else "副武器",
			removed_item.get("name", "配件"),
		]
		return
	var rollback := player.call(
		"install_attachment_item_to_weapon_slot",
		removed_item,
		weapon_slot_index,
		attachment_slot_type
	) as Dictionary
	status_label.text = (
		"丢弃失败，配件已恢复到原枪"
		if bool(rollback.get("success", false))
		else "配件丢弃事务异常：恢复失败"
	)


func get_equipped_backpack_item() -> Dictionary:
	return player.get_equipped_backpack_item() if player != null and player.has_method("get_equipped_backpack_item") else {}


func get_backpack_equipment_snapshot() -> Dictionary:
	var snapshot := player.get_backpack_equipment_snapshot() if player != null and player.has_method("get_backpack_equipment_snapshot") else {}
	snapshot["base_capacity"] = BASE_INVENTORY_CAPACITY
	snapshot["inventory_capacity"] = _inventory.get_capacity() if _inventory != null else BASE_INVENTORY_CAPACITY
	return snapshot


func _on_backpack_slot_equip_requested(source_slot_index: int) -> void:
	var slot := _inventory.get_slot(source_slot_index)
	if slot.is_empty():
		return
	_equip_backpack_from_inventory(source_slot_index, slot.get("item", {}) as Dictionary)


func _equip_backpack_from_inventory(slot_index: int, item: Dictionary) -> bool:
	if player == null or not player.has_method("equip_backpack_item"):
		return false
	if str(item.get("type", "")) != "equipment" or str(item.get("subtype", "")) != "backpack":
		status_label.text = "只能把背包装备拖入背包栏"
		return false
	var target_capacity := BASE_INVENTORY_CAPACITY + int(item.get("extra_slots", 0))
	var old_item := get_equipped_backpack_item()
	var predicted_used := _inventory.get_used_slots() - 1 + (0 if old_item.is_empty() else 1)
	if predicted_used > target_capacity and not _can_spawn_overflow_in_current_room():
		status_label.text = "更换背包失败：当前房间无法生成溢出物"
		return false
	if not _inventory.remove_from_slot(slot_index, 1):
		return false
	var equip_result := player.call("equip_backpack_item", item) as Dictionary
	if not bool(equip_result.get("success", false)):
		_inventory.put_item_in_empty_slot(slot_index, item, 1)
		status_label.text = str(equip_result.get("reason", "背包装备失败"))
		return false
	if not old_item.is_empty() and not _inventory.put_item_in_empty_slot(slot_index, old_item, 1):
		player.call("equip_backpack_item", old_item)
		_inventory.put_item_in_empty_slot(slot_index, item, 1)
		status_label.text = "更换背包失败：旧背包无法返回来源格，已回滚"
		return false
	var overflow := _inventory.resize_capacity_collect_overflow(target_capacity)
	_drop_backpack_capacity_overflow(overflow)
	_emit_backpack_equipment_changed()
	status_label.text = "已装备%s · 背包容量%d格%s" % [
		item.get("name", "背包"), target_capacity,
		" · %d格物品已落地" % overflow.size() if not overflow.is_empty() else "",
	]
	return true


func _on_equipped_backpack_to_inventory_requested(target_slot_index: int) -> void:
	if player == null or not player.has_method("unequip_backpack_item"):
		return
	if target_slot_index < 0 or target_slot_index >= BASE_INVENTORY_CAPACITY:
		status_label.text = "卸下背包时请选择基础%d格内的空格" % BASE_INVENTORY_CAPACITY
		return
	if not _inventory.get_slot(target_slot_index).is_empty():
		status_label.text = "卸下背包失败：目标格已有物品"
		return
	var predicted_used := _inventory.get_used_slots() + 1
	if predicted_used > BASE_INVENTORY_CAPACITY and not _can_spawn_overflow_in_current_room():
		status_label.text = "卸下背包失败：当前房间无法生成溢出物"
		return
	var result := player.call("unequip_backpack_item") as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "卸下背包失败"))
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _inventory.put_item_in_empty_slot(target_slot_index, old_item, 1):
		player.call("equip_backpack_item", old_item)
		status_label.text = "卸下背包失败：目标格写入失败，已回滚"
		return
	var overflow := _inventory.resize_capacity_collect_overflow(BASE_INVENTORY_CAPACITY)
	_drop_backpack_capacity_overflow(overflow)
	_emit_backpack_equipment_changed()
	status_label.text = "已卸下%s%s" % [
		old_item.get("name", "背包"),
		" · %d格物品已落地" % overflow.size() if not overflow.is_empty() else "",
	]


func _on_equipped_backpack_drop_requested() -> void:
	if player == null or not player.has_method("unequip_backpack_item"):
		return
	var current := get_equipped_backpack_item()
	if current.is_empty():
		return
	var predicted_overflow := maxi(0, _inventory.get_used_slots() - BASE_INVENTORY_CAPACITY)
	if predicted_overflow > 0 and not _can_spawn_overflow_in_current_room():
		status_label.text = "丢弃背包失败：当前房间无法生成溢出物"
		return
	var result := player.call("unequip_backpack_item") as Dictionary
	if not bool(result.get("success", false)):
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _drop_inventory_item_to_world(old_item, 1):
		player.call("equip_backpack_item", old_item)
		status_label.text = "丢弃背包失败：已恢复装备"
		return
	var overflow := _inventory.resize_capacity_collect_overflow(BASE_INVENTORY_CAPACITY)
	_drop_backpack_capacity_overflow(overflow)
	_emit_backpack_equipment_changed()
	status_label.text = "已丢弃%s · 容量恢复%d格%s" % [
		old_item.get("name", "背包"), BASE_INVENTORY_CAPACITY,
		" · %d格物品同时落地" % overflow.size() if not overflow.is_empty() else "",
	]


func _can_spawn_overflow_in_current_room() -> bool:
	return player != null and _room_by_id.get(_current_room_id) is DungeonRoom3D


func _drop_backpack_capacity_overflow(overflow: Array[Dictionary]) -> void:
	for entry in overflow:
		var item := entry.get("item", {}) as Dictionary
		var count := int(entry.get("count", 1))
		_drop_inventory_item_to_world(item, count)


func _emit_backpack_equipment_changed() -> void:
	var snapshot := get_backpack_equipment_snapshot()
	backpack_equipment_changed.emit(snapshot)
	_refresh_loot_label()


func _on_quick_item_assignment_requested(quick_slot_index: int, item_id: String) -> void:
	# 兼容旧调用与旧测试：ID引用不再作为正式所有权，只用于定位背包
	# 中的真实物品组并迁入快捷槽。
	var source_slot := _find_inventory_item_slot(item_id)
	if source_slot < 0 or not _move_inventory_item_to_quick(source_slot, quick_slot_index):
		status_label.text = "背包中没有可移动到快捷栏的%s" % item_id


func _on_inventory_item_to_quick_requested(source_slot_index: int, quick_slot_index: int) -> void:
	_move_inventory_item_to_quick(source_slot_index, quick_slot_index)


func _move_inventory_item_to_quick(source_slot_index: int, quick_slot_index: int) -> bool:
	if quick_slot_index < 0 or quick_slot_index >= _quick_inventory.get_capacity():
		return false
	var source := _inventory.get_slot(source_slot_index)
	if source.is_empty():
		return false
	var item := source.get("item", {}) as Dictionary
	if str(item.get("use_action", "")).is_empty():
		status_label.text = "该物品不能主动使用，无法放入快捷栏"
		return false
	var inventory_before := _inventory.get_slots_snapshot()
	var quick_before := _quick_inventory.get_slots_snapshot()
	var previous := _quick_inventory.get_slot(quick_slot_index)
	_inventory.clear_slot(source_slot_index)
	if not previous.is_empty():
		_quick_inventory.clear_slot(quick_slot_index)
	var moved := _quick_inventory.put_item_in_empty_slot(
		quick_slot_index, item, int(source.get("count", 1))
	)
	if moved and not previous.is_empty():
		moved = _inventory.put_item_in_empty_slot(
			source_slot_index,
			previous.get("item", {}) as Dictionary,
			int(previous.get("count", 1))
		)
	if not moved:
		_inventory.restore_slots_snapshot(inventory_before)
		_quick_inventory.restore_slots_snapshot(quick_before)
		status_label.text = "快捷栏移动失败，物品已回滚"
		return false
	_sync_quick_item_state()
	status_label.text = "已将%s移动到快捷键%d" % [item.get("name", "物品"), quick_slot_index + 3]
	return true


func _on_quick_item_move_requested(
	source_quick_index: int, target_index: int, target_kind: String
) -> void:
	var source := _quick_inventory.get_slot(source_quick_index)
	if source.is_empty():
		return
	var quick_before := _quick_inventory.get_slots_snapshot()
	var inventory_before := _inventory.get_slots_snapshot()
	var insurance_before := _insurance.get_slots_snapshot()
	var item := source.get("item", {}) as Dictionary
	var count := int(source.get("count", 1))
	var moved := false
	match target_kind:
		"inventory":
			if _inventory.get_slot(target_index).is_empty():
				_quick_inventory.clear_slot(source_quick_index)
				moved = _inventory.put_item_in_empty_slot(target_index, item, count)
		"quick_0", "quick_1":
			var target_quick_index := int(target_kind.trim_prefix("quick_"))
			if target_quick_index == source_quick_index:
				moved = true
			else:
				moved = _quick_inventory.move_or_swap_slots(source_quick_index, target_quick_index)
		"insurance":
			moved = _insurance.insure_item_to_slot(
				_quick_inventory, source_quick_index, target_index
			)
		"drop":
			_quick_inventory.clear_slot(source_quick_index)
			moved = _drop_inventory_item_to_world(item, count)
	if not moved:
		_inventory.restore_slots_snapshot(inventory_before)
		_quick_inventory.restore_slots_snapshot(quick_before)
		_insurance.restore_slots_snapshot(insurance_before)
		status_label.text = "快捷物品移动失败，已恢复原位置"
		return
	_sync_quick_item_state()


func _sync_quick_item_ids() -> void:
	_quick_item_ids = ["", ""]
	for quick_index in range(2):
		var slot := _quick_inventory.get_slot(quick_index)
		if not slot.is_empty():
			_quick_item_ids[quick_index] = str((slot.get("item", {}) as Dictionary).get("id", ""))


func _sync_quick_item_state() -> void:
	_sync_quick_item_ids()
	if _inventory_ui != null:
		_inventory_ui.set_quick_item_module(_quick_inventory)
	_refresh_quick_item_hud()


func _find_inventory_item_slot(item_id: String) -> int:
	if item_id.is_empty():
		return -1
	for entry in _inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


func _use_quick_item(quick_slot_index: int) -> bool:
	if quick_slot_index < 0 or quick_slot_index >= _quick_inventory.get_capacity():
		return false
	var slot := _quick_inventory.get_slot(quick_slot_index)
	if slot.is_empty():
		status_label.text = "快捷栏%d没有物品" % (quick_slot_index + 3)
		return false
	var item := slot.get("item", {}) as Dictionary
	if str(item.get("id", "")) == "item_ammo_pack":
		var reload_started := player.request_reload()
		status_label.text = "开始装填 · 备弹将在完成时扣除" if reload_started else "无需装填或备弹不足"
		return reload_started
	var handler := ItemUseHandler.new()
	var applied := handler.apply(item, {"player": player, "extraction_director": self})
	handler.free()
	if not applied:
		status_label.text = "%s当前无法使用" % item.get("name", "物品")
		return false
	if not _quick_inventory.remove_from_slot(quick_slot_index, 1):
		status_label.text = "使用结算失败，物品未扣除"
		return false
	_sync_quick_item_state()
	status_label.text = "[%d] 已使用%s" % [quick_slot_index + 3, item.get("name", "物品")]
	return true


func _refresh_quick_item_hud() -> void:
	if _hud_quick_item_icons.size() < 2 or _hud_quick_item_labels.size() < 2:
		return
	for quick_index in range(2):
		var slot := _quick_inventory.get_slot(quick_index) if _quick_inventory != null else {}
		if slot.is_empty():
			var empty_icon := _hud_quick_item_icons[quick_index] as ItemModelIcon3D
			if empty_icon != null:
				empty_icon.clear_model()
			_hud_quick_item_labels[quick_index].text = "[%d] 空" % (quick_index + 3)
			continue
		var item := slot.get("item", {}) as Dictionary
		var item_id := str(item.get("id", ""))
		var count := int(slot.get("count", 1))
		var quick_icon := _ensure_hud_quick_item_icon(quick_index)
		if quick_icon != null:
			quick_icon.configure(item)
		_hud_quick_item_labels[quick_index].text = "[%d] %s ×%d" % [
			quick_index + 3, item.get("name", item_id), count,
		]


func _ensure_hud_quick_item_icon(quick_index: int) -> ItemModelIcon3D:
	if quick_index < 0 or quick_index >= _hud_quick_item_icons.size() or quick_index >= _hud_quick_item_icon_hosts.size():
		return null
	var existing := _hud_quick_item_icons[quick_index] as ItemModelIcon3D
	if existing != null and is_instance_valid(existing):
		return existing
	var icon := ITEM_MODEL_ICON_SCENE.instantiate() as ItemModelIcon3D
	icon.name = "QuickItemModelIcon3D_%d" % quick_index
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 同样交给自适应取景；原 0.68 是「按小图标另调一档」的写法，现在由模型外接盒决定。
	_hud_quick_item_icon_hosts[quick_index].add_child(icon)
	_hud_quick_item_icons[quick_index] = icon
	return icon


func _select_weapon_slot(slot_index: int) -> bool:
	if player == null or not player.has_method("request_weapon_slot"):
		return false
	var result := player.call("request_weapon_slot", slot_index) as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "武器切换失败"))
		return false
	if bool(result.get("pending", false)):
		status_label.text = "正在收起武器" if bool(result.get("holstering", false)) else "正在取出[%d]武器" % (slot_index + 1)
		return true
	var snapshot := result.get("snapshot", player.get_weapon_presentation_snapshot()) as Dictionary
	status_label.text = "已切换至[%d] %s #%s" % [
		slot_index + 1, snapshot.get("display_name", "武器"), snapshot.get("instance_suffix", "------"),
	]
	return true


func _equip_weapon_from_inventory(slot_index: int, item: Dictionary, target_weapon_slot := -1) -> bool:
	var result: Dictionary = EQUIPMENT_TRANSACTION_SERVICE.equip_weapon_from_inventory(
		_inventory, player, slot_index, item, target_weapon_slot
	)
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("message", "换枪失败"))
		return false
	var snapshot := result.get("snapshot", {}) as Dictionary
	status_label.text = "已装备到%s：%s #%s · 构筑 %d/%d · 原武器完整放回背包" % [
		"当前栏" if target_weapon_slot < 0 else "主武器栏" if target_weapon_slot == 0 else "副武器栏",
		snapshot.get("display_name", item.get("name", "武器")),
		snapshot.get("instance_suffix", "------"),
		snapshot.get("fate_slot_used", 0),
		snapshot.get("fate_slot_capacity", 0),
	]
	return true


func _on_equipped_weapon_to_inventory_requested(weapon_slot_index: int, target_slot_index: int) -> void:
	if player == null or not player.has_method("unequip_weapon_item_from_slot"):
		return
	if not _inventory.get_slot(target_slot_index).is_empty():
		status_label.text = "卸装失败：目标背包格已有物品"
		return
	var result := player.call("unequip_weapon_item_from_slot", weapon_slot_index) as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "卸装失败"))
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _inventory.put_item_in_empty_slot(target_slot_index, old_item, 1):
		var rollback := player.call("equip_weapon_item_to_slot", old_item, weapon_slot_index) as Dictionary
		status_label.text = (
			"卸装失败：背包写入失败，已恢复原武器"
			if bool(rollback.get("success", false))
			else "卸装事务异常：原武器恢复失败"
		)
		return
	status_label.text = "已卸下 %s #%s · 完整构筑进入背包" % [
		old_item.get("name", "武器"),
		str(old_item.get("weapon_instance_id", "")).right(6).to_upper(),
	]


func _on_equipped_weapon_drop_requested(weapon_slot_index: int) -> void:
	if player == null or not player.has_method("unequip_weapon_item_from_slot"):
		return
	var result := player.call("unequip_weapon_item_from_slot", weapon_slot_index) as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "卸装失败"))
		return
	var old_item := result.get("old_item", {}) as Dictionary
	if not _drop_inventory_item_to_world(old_item, 1):
		var rollback := player.call("equip_weapon_item_to_slot", old_item, weapon_slot_index) as Dictionary
		status_label.text = (
			"丢弃失败：已恢复原武器"
			if bool(rollback.get("success", false))
			else "丢弃事务异常：原武器恢复失败"
		)
		return
	status_label.text = "已卸下并丢弃 %s #%s" % [
		old_item.get("name", "武器"),
		str(old_item.get("weapon_instance_id", "")).right(6).to_upper(),
	]


func _install_attachment_from_inventory(
	source_slot_index: int,
	item: Dictionary,
	weapon_slot_index: int,
	attachment_slot_type: int
) -> bool:
	if player == null or not player.has_method("install_attachment_item_to_weapon_slot"):
		return false
	if str(item.get("type", "")) != "attachment":
		status_label.text = "只能把枪械配件拖入配件槽"
		return false
	var inventory_before := _inventory.get_slots_snapshot()
	if not _inventory.remove_from_slot(source_slot_index, 1):
		return false
	var result := player.call(
		"install_attachment_item_to_weapon_slot", item, weapon_slot_index, attachment_slot_type
	) as Dictionary
	if not bool(result.get("success", false)):
		_inventory.restore_slots_snapshot(inventory_before)
		status_label.text = str(result.get("reason", "配件安装失败"))
		return false
	var removed_item := result.get("removed_item", {}) as Dictionary
	if not removed_item.is_empty() and _inventory.add_item(removed_item, 1) != 1:
		# 背包写入异常时把旧配件重新装回，并精确恢复格位快照。
		player.call(
			"install_attachment_item_to_weapon_slot",
			removed_item,
			weapon_slot_index,
			attachment_slot_type
		)
		_inventory.restore_slots_snapshot(inventory_before)
		status_label.text = "配件交换失败：旧配件无法返回背包，已回滚"
		return false
	status_label.text = "已给%s安装%s%s" % [
		"主武器" if weapon_slot_index == 0 else "副武器",
		item.get("name", "配件"),
		" · 旧配件已回到背包" if not removed_item.is_empty() else "",
	]
	return true


func _remove_attachment_to_inventory(
	weapon_slot_index: int, attachment_slot_type: int, target_slot_index: int = -1
) -> bool:
	if player == null or not player.has_method("remove_attachment_from_weapon_slot"):
		return false
	if target_slot_index >= 0 and not _inventory.get_slot(target_slot_index).is_empty():
		status_label.text = "拆卸失败：目标背包格已有物品"
		return false
	var result := player.call(
		"remove_attachment_from_weapon_slot", weapon_slot_index, attachment_slot_type
	) as Dictionary
	if not bool(result.get("success", false)):
		status_label.text = str(result.get("reason", "配件拆卸失败"))
		return false
	var removed_item := result.get("removed_item", {}) as Dictionary
	var stored := (
		_inventory.put_item_in_empty_slot(target_slot_index, removed_item, 1)
		if target_slot_index >= 0
		else _inventory.add_item(removed_item, 1) == 1
	)
	if not stored:
		var rollback := player.call(
			"install_attachment_item_to_weapon_slot",
			removed_item,
			weapon_slot_index,
			attachment_slot_type
		) as Dictionary
		status_label.text = (
			"背包已满，配件已恢复到原枪"
			if bool(rollback.get("success", false))
			else "拆卸事务异常：配件恢复失败"
		)
		return false
	status_label.text = "已从%s拆下%s" % [
		"主武器" if weapon_slot_index == 0 else "副武器",
		removed_item.get("name", AssemblyNode.get_attachment_slot_display_name(attachment_slot_type)),
	]
	return true


## 子弹模块从背包装入指定主/副武器的弹药槽（装备界面拖放 → 武器格）。
##
## 事务顺序：先从背包扣 1 个 → 调 `Player3D.install_bullet_module_to_weapon_slot`
## （写武器实例 + 刷新运行态）→ 换下的旧模块放回背包。任何一步失败都整体回滚，
## 不能出现「背包少了模块、枪上也没装上」的中间态。
func _on_bullet_module_install_requested(source_slot_index: int, weapon_slot_index: int) -> void:
	var source := _inventory.get_slot(source_slot_index)
	if source.is_empty():
		return
	_install_bullet_module_from_inventory(
		source_slot_index, source.get("item", {}) as Dictionary, weapon_slot_index
	)


## 手动更换弹药模块的统一拒绝口（2026-10-19 总闸关闭）。
##
## 背包左键与 `_install_bullet_module_from_inventory` 都先经过这里；账本
## 《背包物品调用索引》的「使用/装配入口」也指向本函数 —— 它如实描述当前唯一行为：
## 拒绝手动换弹，并提示去枪械工坊。
func _reject_manual_bullet_module_swap() -> bool:
	status_label.text = WeaponBulletDrop.manual_swap_block_reason()
	return false


func _install_bullet_module_from_inventory(
	source_slot_index: int, item: Dictionary, weapon_slot_index: int
) -> bool:
	if player == null or not player.has_method("install_bullet_module_to_weapon_slot"):
		return false
	if str(item.get("type", "")) != "module" or str(item.get("subtype", "")) != "bullet":
		status_label.text = "只能把子弹模块拖到武器格"
		return false
	# 先判渠道，再动背包：总闸关闭时不能先 remove_from_slot 再回滚。
	if not WeaponBulletDrop.is_manual_swap_enabled():
		return _reject_manual_bullet_module_swap()
	if not _inventory.remove_from_slot(source_slot_index, 1):
		return false
	var result := player.call(
		"install_bullet_module_to_weapon_slot", item, weapon_slot_index
	) as Dictionary
	if not bool(result.get("success", false)):
		_inventory.add_item(item, 1)
		status_label.text = str(result.get("reason", "子弹模块装配失败"))
		return false
	var removed_item := result.get("removed_item", {}) as Dictionary
	if not removed_item.is_empty() and _inventory.add_item(removed_item, 1) <= 0:
		# 背包放不下换下的旧模块 ⇒ 把旧弹装回去、新弹退回，保持与操作前一致。
		player.call("install_bullet_module_to_weapon_slot", removed_item, weapon_slot_index)
		_inventory.add_item(item, 1)
		status_label.text = "弹药槽更换失败 · 背包没有空间容纳换下的模块"
		return false
	status_label.text = "已把%s装到%s%s" % [
		item.get("name", "子弹模块"),
		"主武器" if weapon_slot_index == 0 else "副武器",
		"" if removed_item.is_empty() else "（换下%s）" % removed_item.get("name", "旧模块"),
	]
	return true


func _install_weapon_module_from_item(item: Dictionary) -> bool:
	var tree := player.get_weapon_tree()
	if tree == null or tree.get_root() == null:
		return false
	# 局内快捷装配这条链**绕过** `Player3D.install_bullet_module_to_weapon_slot`，
	# 直接改运行树；不在这里单独拦一次，绑定锁定形同虚设。
	# 2026-10-19 追加：手动更换总闸关闭后，非掉落枪也走不到这条旁路。
	if str(item.get("subtype", "")) == "bullet":
		if tree.bullet_module_locked:
			status_label.text = "该枪的弹药模块已绑定，无法手动更换（需在枪械工坊）"
			return false
		if not WeaponBulletDrop.is_manual_swap_enabled():
			return _reject_manual_bullet_module_swap()
	var new_node := BlueprintRegistry.create_assembly_node(str(item.get("assembly_id", item.get("id", ""))))
	if new_node == null:
		return false
	var slot_type := AssemblyNode.SlotType.MOUNT
	match str(item.get("subtype", "")):
		"bullet":
			slot_type = AssemblyNode.SlotType.BULLET
		"muzzle":
			slot_type = AssemblyNode.SlotType.MUZZLE
		"magazine":
			slot_type = AssemblyNode.SlotType.MAGAZINE
		_:
			slot_type = AssemblyNode.SlotType.MOUNT
	var root := tree.get_root()
	var existing := root.slots.get(slot_type) as AssemblyNode
	if existing != null and _item_id_for_assembly_node(existing) == str(item.get("id", "")):
		new_node.free()
		status_label.text = "当前槽位已经装配 %s" % item.get("name", "模块")
		return false
	if existing != null:
		tree.unmount(existing)
	if not tree.mount(root, slot_type, new_node):
		if existing != null:
			tree.mount(root, slot_type, existing)
		new_node.free()
		return false
	if existing != null:
		var old_item := _item_for_assembly_node(existing)
		if old_item.is_empty() or _inventory.add_item(old_item, 1) <= 0:
			tree.unmount(new_node)
			tree.mount(root, slot_type, existing)
			new_node.free()
			status_label.text = "模块交换失败 · 换下的模块无法放回背包"
			return false
		existing.free()
		status_label.text = "已装配 %s · 旧模块放回背包" % item.get("name", "模块")
	else:
		status_label.text = "已装配 %s" % item.get("name", "模块")
	return true


func _can_swap_installed_module(item: Dictionary, source_slot_index: int) -> bool:
	var tree := player.get_weapon_tree()
	if tree == null or tree.get_root() == null:
		return false
	var slot_type := _slot_type_for_item(item)
	var existing := tree.get_root().slots.get(slot_type) as AssemblyNode
	if existing == null:
		return true
	var existing_item := _item_for_assembly_node(existing)
	if existing_item.is_empty():
		status_label.text = "当前模块缺少物品映射，已阻止可能的数据丢失"
		return false
	if _item_id_for_assembly_node(existing) == str(item.get("id", "")):
		status_label.text = "当前槽位已经装配 %s" % item.get("name", "模块")
		return false
	if _inventory.get_free_slots() > 0:
		return true
	var source_slot := _inventory.get_slot(source_slot_index)
	if int(source_slot.get("count", 0)) <= 1:
		return true
	var existing_id := str(existing_item.get("id", ""))
	var stack_max := maxi(1, int(existing_item.get("stack_max", 1)))
	for occupied in _inventory.get_occupied_slots():
		if str((occupied.get("item", {}) as Dictionary).get("id", "")) == existing_id:
			if int(occupied.get("count", 0)) < stack_max:
				return true
	status_label.text = "背包没有空间容纳换下的模块"
	return false


func _slot_type_for_item(item: Dictionary) -> int:
	match str(item.get("subtype", "")):
		"bullet":
			return AssemblyNode.SlotType.BULLET
		"muzzle":
			return AssemblyNode.SlotType.MUZZLE
		"magazine":
			return AssemblyNode.SlotType.MAGAZINE
		"scope":
			return AssemblyNode.SlotType.SCOPE
		"stock":
			return AssemblyNode.SlotType.STOCK
		"external":
			return AssemblyNode.SlotType.TACTICAL
		"mutator":
			return AssemblyNode.SlotType.MUTATOR
		_:
			return AssemblyNode.SlotType.MOUNT


func _item_for_weapon_root(root: AssemblyNode) -> Dictionary:
	return BlueprintRegistry.get_item_for_assembly_node(root)


func _item_for_assembly_node(node: AssemblyNode) -> Dictionary:
	return BlueprintRegistry.get_item_for_assembly_node(node)


func _item_id_for_assembly_node(node: AssemblyNode) -> String:
	return BlueprintRegistry.get_item_id_for_assembly_node(node)


func summon_beacon_extraction() -> bool:
	if _emergency_extraction != null and is_instance_valid(_emergency_extraction):
		return false
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	if room == null:
		return false
	_emergency_extraction = _create_extraction_beacon(room, "BEACON", 30.0, false, Vector3.ZERO)
	_emergency_extraction.global_position = player.global_position + player.aim_direction * 2.2
	status_label.text = "紧急撤离信标已部署 · 读条期间不得离开范围"
	return true


func get_inventory_module() -> InventoryModule:
	return _inventory


func get_insurance_module() -> InsuranceModule:
	return _insurance


func get_last_killed_enemy() -> Dictionary:
	return last_killed_enemy_data.duplicate(true)


func _on_extraction_started(start_duration: float, beacon: ExtractionBeacon3D) -> void:
	_active_extraction_beacon = beacon
	_extraction_defense_active = true
	_close_inventory_for_modal()
	_sync_player_input_lock()
	if AudioManager != null:
		AudioManager.play_sfx("extraction_start")
	extraction_panel.visible = true
	extraction_bar.value = 0.0
	var room := _room_by_id.get(_current_room_id) as DungeonRoom3D
	# 子图撤离房跳过防线遭遇：子图房不在 `_room_by_id` 里，按 `_current_room_id`
	# 取的会是玩家**已经离开**的主图房间 —— 表现成「人在子图读条、主图房里刷怪」。
	# 读条、面板与结算全部照旧，只有这一场遭遇不建。
	var skip_defense := beacon.has_meta("secret_branch")
	if not skip_defense and room != null and _encounter_event_director != null:
		var config := _build_extraction_encounter_config(room, start_duration)
		var started := start_encounter_event(config)
		if bool(started.get("ok", false)):
			_extraction_encounter_instance_id = str(started.get("instance_id", ""))
			_advance_extraction_encounter(0.0, beacon)
		else:
			_extraction_encounter_instance_id = ""
			push_warning("[Dungeon3D] Extraction encounter failed to start: %s" % str(started))
	# 自由撤离：玩家可移动、可射击，30 秒读条中只会越过阈值才离开。
	status_label.text = "%s撤离启动 · %.0f秒后安全返航，行动自由" % [
		beacon.beacon_type,
		start_duration,
	]


func _on_extraction_progress(progress: float, beacon: ExtractionBeacon3D) -> void:
	if beacon != _active_extraction_beacon:
		return
	extraction_bar.value = progress * 100.0
	_advance_extraction_encounter(progress, beacon)


func _advance_extraction_encounter(progress: float, beacon: ExtractionBeacon3D) -> void:
	if beacon != _active_extraction_beacon or _extraction_encounter_instance_id.is_empty():
		return
	var result := advance_encounter_event(_extraction_encounter_instance_id, progress)
	if not bool(result.get("ok", false)):
		push_warning("[Dungeon3D] Extraction encounter progress rejected: %s" % str(result))


func _on_extraction_cancelled(beacon: ExtractionBeacon3D) -> void:
	if beacon != _active_extraction_beacon:
		return
	if not _extraction_encounter_instance_id.is_empty() and _encounter_event_director != null:
		cancel_encounter_event(_extraction_encounter_instance_id, "extraction_cancelled", false)
	_extraction_encounter_instance_id = ""
	_extraction_defense_active = false
	_active_extraction_beacon = null
	_sync_player_input_lock()
	if AudioManager != null:
		AudioManager.play_sfx("extraction_abort")
	extraction_panel.visible = false
	status_label.text = "撤离中断 · 受击或离开同步范围，拦截者仍然存在"


func _on_extraction_completed(beacon: ExtractionBeacon3D) -> void:
	if _active_extraction_beacon != null and beacon != _active_extraction_beacon:
		return
	_extraction_encounter_instance_id = ""
	# 阵亡优先，双条件缺一不可：
	# `_completed` 防一次行动结算两次；`_is_player_dead()` 防「阵亡被判撤离成功」——
	# 信标 _process 只认读条归零，不看玩家死活，尸体旁的读条会照常走完。
	if _completed or _is_player_dead():
		_extraction_defense_active = false
		_active_extraction_beacon = null
		if is_instance_valid(beacon):
			beacon.abort_extraction()
		return
	_extraction_defense_active = false
	_active_extraction_beacon = null
	if AudioManager != null:
		AudioManager.play_sfx("extraction_done")
	_finish_run(true)


## 玩家是否已阵亡。状态机负责「死亡动画进行中」，HP 负责「动画尚未开始」，
## 两个判据都要看：只查状态机会漏掉 take_damage 里 HP 刚归零的那一帧。
func _is_player_dead() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return player.get_state_machine_state() == "dead" or player.current_hp <= 0


## 阵亡时作废进行中的撤离：中断读条并解绑，避免信标在尸体旁读到 0 秒后判撤离成功。
## 顺序是契约 —— 先清 _active_extraction_beacon 再 abort，让 extraction_cancelled
## 回调在「不再是当前信标」处直接返回，不要用「受击中断」文案顶掉死亡文案。
func _abort_extraction_on_death() -> void:
	if not _extraction_encounter_instance_id.is_empty() and _encounter_event_director != null:
		cancel_encounter_event(_extraction_encounter_instance_id, "player_dead", true)
	_extraction_encounter_instance_id = ""
	var beacon := _active_extraction_beacon
	_active_extraction_beacon = null
	_extraction_defense_active = false
	if beacon != null and is_instance_valid(beacon):
		beacon.abort_extraction()
	extraction_panel.visible = false


func _build_extraction_encounter_config(room: DungeonRoom3D, duration_sec: float) -> Dictionary:
	var floor := maxi(1, visual_theme.difficulty_rank)
	var floor_level := clampi(_record_index(room.room_id) / 3, 0, 3)
	var stages: Array = []
	stages.append({"at_ratio": 0.0, "monsters": _roll_extraction_specs("random", 4, floor, floor_level)})
	stages.append({"at_ratio": 0.18, "monsters": _roll_extraction_specs("ambush", 5, floor, floor_level)})
	stages.append({"at_ratio": 0.36, "monsters": _roll_extraction_specs("ambush", 6, floor, floor_level)})
	var mixed_stage := [{"type": "elite", "count": 1}]
	mixed_stage.append_array(_roll_extraction_specs("random", 3, floor, floor_level))
	stages.append({"at_ratio": 0.58, "monsters": mixed_stage})
	var final_stage := [{"type": "elite", "count": 2}]
	final_stage.append_array(_roll_extraction_specs("ambush", 4, floor, floor_level))
	stages.append({"at_ratio": 0.78, "monsters": final_stage})
	return {
		"schema_version": 1,
		"event_id": "extraction_defense:%s" % room.room_id,
		"room_id": room.room_id,
		"duration_sec": maxf(0.1, duration_sec),
		"completion": "timer",
		"progress_mode": "external",
		"leave_policy": "follow_current_room",
		"follow_current_room": true,
		"max_alive": 2147483647,
		"prereqs": {"player_alive": true, "run_active": true},
		"stages": stages,
		"on_completed": [],
	}

func _roll_extraction_specs(mode: String, count: int, floor: int, floor_level: int) -> Array:
	var generated: Array[Dictionary] = []
	if mode == "random":
		while generated.size() < count:
			generated.append_array(_monster_injector.generate_enemies({
				"type": "random", "floor": floor, "floor_level": floor_level,
			}))
	else:
		generated.assign(_monster_injector.generate_enemies({
			"type": mode, "count": count, "floor": floor, "floor_level": floor_level,
		}))
	var result: Array = []
	var accepted := 0
	for config in generated:
		if accepted >= count:
			break
		var type_id := str(config.get("enemy_type", ""))
		if MonsterInjector.is_authorable_enemy_type(type_id):
			accepted += 1
			var found := false
			for spec_value in result:
				var spec := spec_value as Dictionary
				if str(spec.get("type", "")) == type_id:
					spec["count"] = int(spec.get("count", 0)) + 1
					found = true
					break
			if not found:
				result.append({"type": type_id, "count": 1})
	return result


func _on_player_hp_changed(current: int, maximum: int) -> void:
	_queue_runtime_autosave("health_changed")
	hp_label.text = "%d / %d" % [current, maximum]
	hp_bar.max_value = maxi(1, maximum)
	hp_bar.value = clampi(current, 0, maximum)
	var hp_ratio := float(current) / float(maxi(1, maximum))
	var vignette_intensity := clampf((0.34 - hp_ratio) / 0.34, 0.0, 1.0)
	var vignette_material := low_health_vignette.material as ShaderMaterial
	if vignette_material != null:
		vignette_material.set_shader_parameter("intensity", vignette_intensity)
	hp_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.28, 0.22) if hp_ratio <= 0.30 else Color(0.92, 0.95, 1.0),
	)
	var took_damage := _last_player_hp >= 0 and current < _last_player_hp
	_last_player_hp = current
	_sync_player_health_bar_delay(hp_ratio, took_damage)
	# 自由撤离：玩家可以被打但不被中断。
	# 只要 HP 不归零就读条继续。
	if current <= 0:
		# 阵亡必须中断撤离读条。信标只认 _remaining <= 0，不看玩家死活，
		# 读条期间被打死本来就会被判「撤离成功」（塔楼双结算、独立副本吞掉死亡）。
		# 注意调用顺序：先作废信标，再写状态文案 —— abort 会同步触发
		# extraction_cancelled，写在前面会被中断文案顶掉。
		_death_recorded_generation = _run_generation
		_abort_extraction_on_death()
		status_label.text = "生命信号中断 · 正在确认防护体状态"


## 玩家主界面条的白色延迟层。语义与 Boss 屏条、小怪头顶条**逐条一致**：
## 只有「受伤」才留下白段；初始化/治疗/复活/读档立即对齐，否则开局或补血后会挂一段假白。
## 白段只在 `_player_delayed_ratio` 里活着，**永不写进 `player.current_hp`**，
## 不参与伤害判定、格挡结算与存档。
func _sync_player_health_bar_delay(hp_ratio: float, took_damage: bool) -> void:
	if _player_delayed_bar == null or hp_bar == null:
		return
	_player_delayed_bar.max_value = hp_bar.max_value
	if not _player_health_bar_initialized or not took_damage or hp_ratio >= _player_delayed_ratio:
		_player_delayed_ratio = hp_ratio
	_player_health_bar_initialized = true
	_player_delayed_bar.value = _player_delayed_ratio * _player_delayed_bar.max_value


func _tick_player_health_bar_delay(delta: float) -> void:
	if _player_delayed_bar == null or hp_bar == null:
		return
	var actual_ratio := hp_bar.value / maxf(1.0, hp_bar.max_value)
	# 白段只朝真实血量收，永不越过 —— 越过了就会在红条**左侧**露出一截白，
	# 看起来像掉血掉反。红条的 shadow 会自然糊在白段左缘，无需额外混合。
	if _player_delayed_ratio <= actual_ratio:
		return
	_player_delayed_ratio = move_toward(
		_player_delayed_ratio, actual_ratio, delta * HUD_HEALTH_BAR_DELAY_SPEED
	)
	_player_delayed_bar.value = _player_delayed_ratio * _player_delayed_bar.max_value


## 玩家主界面血条快照。白段是纯视觉层，无法从 `hp_bar.value` 反推，验收只能从这里读。
func get_player_vitals_bar_snapshot() -> Dictionary:
	return {
		"actual_ratio": (
			hp_bar.value / maxf(1.0, hp_bar.max_value) if hp_bar != null else 0.0
		),
		"delayed_ratio": _player_delayed_ratio,
		"delayed_layer_present": _player_delayed_bar != null,
		"delayed_layer_name": _player_delayed_bar.name if _player_delayed_bar != null else "",
		"delayed_speed": HUD_HEALTH_BAR_DELAY_SPEED,
	}


func _on_player_debug_scale_changed(snapshot: Dictionary) -> void:
	status_label.text = "角色调试尺寸：%d%% · 每档按基础尺寸增减10%%" % int(
		snapshot.get("scale_percent", 100)
	)


func _on_ammo_changed(current: int, maximum: int) -> void:
	_queue_runtime_autosave("ammo_changed")
	var snapshot := player.get_weapon_presentation_snapshot() if player != null else {}
	var weapon_snapshot := player.get_weapon_snapshot() if player != null else {}
	var active_slot := player.get_active_weapon_slot() if player != null and player.has_method("get_active_weapon_slot") else 0
	var weapon_item := player.get_equipped_weapon_item() if player != null else {}
	_hud_presenter.present_weapon(
		snapshot, weapon_snapshot, active_slot, current, maximum, weapon_item
	)


func _on_hud_weapon_instance_changed(_snapshot: Dictionary) -> void:
	_refresh_hud_weapon_model(true)
	var weapon_snapshot := player.get_weapon_snapshot() if player != null else {}
	_on_ammo_changed(
		int(weapon_snapshot.get("current_ammo", 0)),
		int(weapon_snapshot.get("magazine_size", 0)),
	)


func _refresh_hud_weapon_model(force := false) -> void:
	if player == null:
		return
	var item := player.get_equipped_weapon_item()
	var weapon_snapshot := player.get_weapon_snapshot()
	_hud_presenter.present_weapon(
		player.get_weapon_presentation_snapshot(),
		weapon_snapshot,
		player.get_active_weapon_slot(),
		int(weapon_snapshot.get("current_ammo", 0)),
		int(weapon_snapshot.get("magazine_size", 0)),
		item,
		force
	)


func _apply_weapon_hud_command(command: Dictionary) -> void:
	if ammo_label != null:
		var ammo_text := str(command.get("ammo_text", "0 / 0"))
		if ammo_text.begins_with("近战"):
			# 近战武器没有弹药口径，沿用 Presenter 的「近战 · 三段」。
			ammo_label.text = ammo_text
		else:
			# 2026-09-28 主人要求：不再显示弹匣容量（原「子弹 / 总弹药 · N备弹」），
			# 只留「当前子弹数 · N备弹」。当前值走结构化字段 ammo_current，不解析字符串。
			var ammo_display := "%d" % int(command.get("ammo_current", 0))
			if _inventory != null:
				ammo_display += " · %d备弹" % _get_reserve_ammo_count()
			ammo_label.text = ammo_display
	if _hud_weapon_meta_label != null:
		# 面板上已不显示（visible=false），但仍按只读投影契约逐字接收文本。
		_hud_weapon_meta_label.text = str(command.get("weapon_meta_text", "当前武器 · 未装备"))
		if _reference_hud_root != null:
			var keycap_lbl := _reference_hud_root.find_child("KeycapLabel", true, false) as Label
			if keycap_lbl != null:
				var meta_str := _hud_weapon_meta_label.text
				keycap_lbl.text = "2" if meta_str.begins_with("[2]") else "1"

	if _hud_weapon_fate_label != null:
		# 只留命运卡槽占用「已用/容量」，去掉「实例 #… · 命运 … · K 详情」整行。
		_hud_weapon_fate_label.text = "%d/%d" % [
			int(command.get("fate_slot_used", 0)),
			int(command.get("fate_slot_capacity", 0)),
		]
	if _hud_weapon_model_icon == null:
		return
	match str(command.get("model_action", "keep")):
		"clear":
			_hud_weapon_model_icon.clear_model()
		"replace":
			_hud_weapon_model_icon.configure(command.get("weapon_item", {}) as Dictionary)


func get_hud_weapon_model_snapshot() -> Dictionary:
	return _hud_weapon_model_icon.get_snapshot() if _hud_weapon_model_icon != null else {}


func _provide_reload_ammo(requested_rounds: int) -> int:
	if _inventory == null:
		return 0
	var backpack_available := _inventory.get_item_count("item_ammo_pack")
	var available := _get_reserve_ammo_count()
	if requested_rounds <= 0:
		return available
	var consumed := mini(available, requested_rounds)
	var from_backpack := mini(backpack_available, consumed)
	if from_backpack > 0 and not _inventory.consume_item("item_ammo_pack", from_backpack):
		return 0
	var from_quick := consumed - from_backpack
	if from_quick > 0 and (
		_quick_inventory == null
		or not _quick_inventory.consume_item("item_ammo_pack", from_quick)
	):
		# 理论上查询与扣除在同一主线程帧；若快捷栏异常，退回主背包部分。
		return from_backpack
	return consumed


func _get_reserve_ammo_count() -> int:
	return (
		(_inventory.get_item_count("item_ammo_pack") if _inventory != null else 0)
		+ (_quick_inventory.get_item_count("item_ammo_pack") if _quick_inventory != null else 0)
	)


func _on_player_state_changed(state_id: String, _context: Dictionary) -> void:
	if state_id == "dead":
		_settle_player_killer_elite()
		status_label.text = "行动失败 · 防护体失去响应"


func _settle_player_killer_elite() -> void:
	if _player_killer_elite_settled or player == null or not player.has_method("get_last_damage_source_snapshot"):
		return
	var source := player.call("get_last_damage_source_snapshot") as Dictionary
	var elite_id := str(source.get("elite_id", ""))
	var encounter_id := str(source.get("encounter_instance_id", ""))
	if elite_id.is_empty() or encounter_id.is_empty():
		return
	var settlement_context := {
		"floor_number": int(source.get("floor_number", 0)),
		"room_id": str(source.get("room_id", _current_room_id)),
		"killed_player": true,
		"weapon_snapshot": player.get_weapon_snapshot(),
	}
	_player_killer_elite_settled = EliteRosterService != null and EliteRosterService.settle(
		elite_id,
		encounter_id,
		"escaped",
		settlement_context
	)
	if not _player_killer_elite_settled:
		return
	for value in _enemy_nodes_by_room.get(str(source.get("room_id", _current_room_id)), []):
		if not is_instance_valid(value) or not value is Enemy3D:
			continue
		var enemy := value as Enemy3D
		if enemy.elite_id == elite_id and enemy.elite_encounter_instance_id == encounter_id:
			enemy.complete_elite_escape_after_external_settlement(settlement_context)
			break


func _on_player_death_animation_finished() -> void:
	if _completed or _death_animation_ready:
		return
	# 这次阵亡发生在一个已经被终局结算覆盖的旧代行动里：成功撤离提交后有 0.8s
	# 返航窗口，此时玩家输入被锁、站着挨打，而死亡动画要 1.35s —— 复位成新一轮
	# 之后动画才结束。再弹死亡框就会让同一次行动既记撤离成功、又记阵亡结算。
	# -1 表示本次行动没登记过死亡，保持既有行为放行。
	if _death_recorded_generation >= 0 and _death_recorded_generation != _run_generation:
		push_warning(
			"[Dungeon3D] 阵亡已被终局结算覆盖，跳过死亡结算：死亡代际 %d / 当前行动代际 %d"
			% [_death_recorded_generation, _run_generation]
		)
		return
	_death_animation_ready = true
	_show_death_confirmation_dialog()


## 清除上一轮行动遗留的死亡状态。终局复位（塔楼成功返航）后必须调用，
## 否则新一轮再阵亡时 `_death_animation_ready` 仍是 true，死亡框不会再弹。
func _reset_death_settlement_state() -> void:
	_death_animation_ready = false
	if _death_dialog != null and is_instance_valid(_death_dialog):
		_death_dialog.queue_free()
	_death_dialog = null


func _show_death_confirmation_dialog() -> void:
	if _death_dialog != null and is_instance_valid(_death_dialog):
		return
	# 「棱镜线框」死亡结算确认：冷蓝压暗 + 四角括号模态卡 + 黑徽章标题（含下折角）
	# + 内嵌规则说明白线框 + 单枚实心近白高对比按钮（死亡本身已发生，按钮是"继续"而非"销毁"）。
	var spec := UIStyleFactory.make_prism_confirm_modal(
		"行动人员已倒下",
		"MIA / DOWNED",
		"未保险物资将按死亡规则结算，保险柜内物资予以保留。\n确认后立即返回 %s。" % _death_return_location_text(),
		[
			UIStyleFactory.prism_button_spec(
				"ConfirmButton", _death_return_button_text(), "primary", 380.0, 56.0
			)
		],
		UIPalette.PRISM_DANGER,
		Vector2(760, 382),
		0.70
	)
	var overlay := spec["overlay"] as Control
	overlay.name = "DeathConfirmationDialog"
	overlay.z_index = 950
	var panel := spec["panel"] as Control
	$HUD.add_child(overlay)
	var confirm := (spec["buttons"] as Array)[0] as Button
	confirm.pressed.connect(_confirm_death_return)
	_death_dialog = overlay
	UIFX.pop_in_modal(panel)
	confirm.grab_focus()
	_sync_player_input_lock()



func _death_return_location_text() -> String:
	return "99F 基地中点"


func _death_return_button_text() -> String:
	return "确认结算并返回基地"


func _confirm_death_return() -> void:
	if _completed or not _death_animation_ready:
		return
	if _death_dialog != null and is_instance_valid(_death_dialog):
		_death_dialog.queue_free()
	_death_dialog = null
	_finish_run(false)


func _finish_run(success: bool) -> void:
	if _completed:
		return
	_completed = true
	if _encounter_event_director != null:
		_encounter_event_director.cancel_all("run_finished")
	for room_id in _wave_spawn_pending.keys():
		_cancel_room_wave_intermission(str(room_id))
	var inventory_before := _inventory.get_slots_snapshot()
	var insurance_before := _insurance.get_slots_snapshot()
	var quick_before := _quick_inventory.get_slots_snapshot()
	_close_inventory_for_modal()
	_sync_player_input_lock()
	extraction_panel.visible = false
	_run_loot = _collect_extracted_items(success)
	var settlement: Dictionary = {}
	if success:
		_death_settlement.process_extraction_settlement(_inventory, _insurance, _quick_inventory)
	else:
		settlement = _death_settlement.process_death_settlement(_inventory, _insurance)
		var quick_settlement := _death_settlement.process_death_settlement(_quick_inventory, null)
		(settlement.get("dropped", []) as Array).append_array(
			quick_settlement.get("dropped", []) as Array
		)
		settlement["total_lost"] = int(settlement.get("total_lost", 0)) + int(
			quick_settlement.get("total_lost", 0)
		)
		_run_loot = _collect_extracted_items(false)
	# 保底在提交**之前**判定并把补发物塞进 `_run_loot`，所以 summary 与状态行
	# 看到的是同一份结算物 —— 不能一处算总数、一处算不含补发的数。
	var pity_result: Dictionary = {}
	if not test_mode:
		# 先判保底再提交：补发物必须进本局结算物，件数与待领取栏才一致。
		# 只在成功撤离时判 —— 死在里面的局没有"带出"这回事。
		if success:
			pity_result = _plan_synthesis_pity_drop()
		var transaction_id := _get_run_settlement_transaction_id(success)
		var commit := BaseManager.commit_run_settlement({
			"transaction_id": transaction_id,
			"success": success,
			"kills": _kills,
			"extraction_points": _run_value if success else 0,
			"extraction_loot": _run_loot if success else [],
			"insurance_saved": settlement.get("insurance_saved", []) if not success else [],
			"return_checkpoint": _build_settlement_return_checkpoint(),
		}) as Dictionary
		if _absorb_duplicate_settlement(commit):
			# 本次行动已经结算过：内存里刚做的那套改动必须整体撤销，
			# 否则玩家会看到「行动失败」而档案其实是上一套结果。
			_inventory.restore_slots_snapshot(inventory_before)
			_insurance.restore_slots_snapshot(insurance_before)
			_quick_inventory.restore_slots_snapshot(quick_before)
			return
		if not bool(commit.get("success", false)):
			_inventory.restore_slots_snapshot(inventory_before)
			_insurance.restore_slots_snapshot(insurance_before)
			_quick_inventory.restore_slots_snapshot(quick_before)
			_completed = false
			status_label.text = "行动结算保存失败 · 请重试"
			push_error("[Dungeon3D] Run settlement failed: %s" % commit)
			if not success:
				_show_death_confirmation_dialog()
			return
		if not success:
			_insurance.clear_all()
		# 结算后的场景卸载不再回写旧运行态；保险/战利品已经进入长期事务。
		BaseManager.unregister_runtime_checkpoint_provider(self, false)
		_runtime_persistence_active = false
	# summary 只带结论，不带补发物本体（物品已在 `_run_loot` 里）。
	var pity_summary := pity_result.duplicate(true)
	pity_summary.erase("item")
	var summary := {
		"success": success, "kills": _kills, "value": _run_value,
		"loot": _run_loot.duplicate(true), "seed": run_seed,
		"theme_id": gameplay_theme.theme_id, "settlement": settlement,
		"inventory_capacity": _inventory.get_capacity(), "insurance_capacity": _insurance.get_max_slots(),
		"synthesis_pity": pity_summary,
	}
	# 终局已提交：返航窗口内玩家输入被锁、站着挨打，残留拦截怪能把他拖死，
	# 从而在已写盘的结果之上再叠一次死亡结算（或作废后以 hp=0 卡住）。
	if success:
		_hold_player_after_settlement()
	if success:
		var line := "撤离成功 · %d 击杀 · %d件物资" % [_kills, _run_loot.size()]
		# 保底补发必须说出来。玩家看不到"为什么多了一件"，就会当成掉落表的随机。
		if not str(pity_result.get("granted", "")).is_empty():
			line += " · 保底补给 1 件"
		status_label.text = line
	else:
		status_label.text = "行动失败 · 按原规则结算未保险物资"
	run_completed.emit(success, summary)
	if not test_mode:
		await get_tree().create_timer(0.18 if not success else 1.6).timeout
		var entry_request_id: int = _request_return_entry_context(success)
		await _return_to_scene_after_settlement(entry_request_id)


## 本局合成保底：判一次、必要时补一件。返回 `{granted, misses, threshold, item}`。
##
## 「这一局算不算一次机会」只看本局有没有真打死首领（`_boss_defeated_rooms` 非空）：
## 一个首领都没打就从撤离点走人，既不推进也不清零 ——
## 否则「进图二十秒 → 撤离」就能把保底刷出来，它就不再是运气下限。
##
## 补发物直接进 `_run_loot`：它随后既进待领取栏、又进状态行的件数。
## 只在成功撤离时调用（`_finish_run(true)`），死亡路径没有"带出"这回事。
func _plan_synthesis_pity_drop() -> Dictionary:
	var loot_ids: Array = []
	for raw_item in _run_loot:
		if raw_item is Dictionary:
			loot_ids.append(str((raw_item as Dictionary).get("id", "")))
	var result := BaseManager.plan_synthesis_pity(
		loot_ids, not _boss_defeated_rooms.is_empty()
	)
	var item := result.get("item", {}) as Dictionary
	if not item.is_empty():
		_run_loot.append(item)
	return result


## 「带物返航」路径（塔楼 / 远征成功撤离）的保底：只判定与记账，**不交付**。
##
## 这条路径把战利品原地留在背包里、不复制进待领取栏，所以补发物不能走
## `_run_loot`（那张表在这里是"只读参考"）。交付必须等存档事务提交成功之后
## 再做 —— 否则存档失败、玩家还在原地，背包里却已经多了一件保底物。
func _plan_synthesis_pity_carry() -> Dictionary:
	var loot_ids: Array = []
	for raw_item in _run_loot:
		if raw_item is Dictionary:
			loot_ids.append(str((raw_item as Dictionary).get("id", "")))
	return BaseManager.plan_synthesis_pity(loot_ids, not _boss_defeated_rooms.is_empty())


## 把保底物交给玩家。**必须在 `plan_synthesis_pity_carry` 的存档事务成功之后调用。**
## 背包塞不下时退回待领取栏 —— 保底物绝不能因为"格子不够"凭空消失。
func _deliver_synthesis_pity_carry(result: Dictionary) -> bool:
	var item := result.get("item", {}) as Dictionary
	if item.is_empty():
		return false
	if _inventory != null and _inventory.add_item(item, 1) > 0:
		BaseManager.save_base("synthesis_pity_carry")
		return true
	BaseManager.add_extraction_loot(item, 1)
	BaseManager.save_base("synthesis_pity_carry_overflow")
	return true


## 结算完成后的统一返航入口。子类可覆写读取页过场，但不能改变上层结算顺序。
func _return_to_scene_after_settlement(entry_request_id: int) -> void:
	var change_error: Error = get_tree().change_scene_to_file(return_scene_path)
	if change_error != OK:
		if entry_request_id > 0:
			GameEntryFlow.cancel_request(entry_request_id)
		push_error("行动结算后的场景返回失败：%s" % error_string(change_error))


func _get_run_settlement_transaction_id(_success: bool) -> String:
	# 一次行动共用一个结算事务 ID —— 成功与死亡必须撞同一个 ID，幂等才成立。
	# 原先按 run_success / run_death 生成两个 ID，`commit_run_settlement` 的
	# completed_transaction_ids 去重就形同虚设，同一次行动能被真写盘两次。
	# success 参数保留仅为兼容既有调用点，不参与 ID 生成。
	if _pending_run_settlement_transaction_id.is_empty():
		_pending_run_settlement_transaction_id = BaseShopService.generate_transaction_id(
			"run_settlement"
		)
	return _pending_run_settlement_transaction_id


## 幂等拦截：同一次行动的结算已经写盘过。数据以第一次为准，必须停手 ——
## 再 emit 一次 run_completed 会给出与档案相矛盾的第二套结算画面。
func _absorb_duplicate_settlement(commit: Dictionary) -> bool:
	if not bool(commit.get("duplicate", false)):
		return false
	push_error("[Dungeon3D] 行动结算已提交过，忽略重复请求：%s" % commit)
	# 这一局早就结算过了：刚才 `plan_synthesis_pity` 推进的那格计数必须退回。
	BaseManager.discard_synthesis_pity_plan()
	return true


## 结算已提交后保护玩家。返航/返回场景的窗口里（塔楼 0.8s、远征 0.8s）玩家输入
## 已被锁定、无法走位，残留拦截怪足以把他打死；一旦打死就会在已写盘的结算之上
## 再叠一次死亡，或者被防御性作废后以 hp=0 卡在原地。
func _hold_player_after_settlement() -> void:
	if player != null and is_instance_valid(player):
		player.hold_post_settlement_invulnerability()


func _build_settlement_return_checkpoint() -> Dictionary:
	return {}


func _request_return_entry_context(success: bool) -> int:
	# 独立副本虽然返回正式 BaseWorld3D，但仍必须登记99F基地出生契约；
	# 否则入口场景无法区分“撤退回基地”和普通冷启动，可能落入未包装的兼容空间。
	var is_base_return := return_scene_path == GameDesignConfig.MAIN_SCENE or return_scene_path == GameDesignConfig.BASE_SCENE_3D
	if not is_base_return:
		return -1
	var reason := (
		GameEntryFlow.REASON_SUCCESSFUL_RETURN_99F
		if success
		else GameEntryFlow.REASON_DEATH_RETURN_99F
	)
	return GameEntryFlow.request_gameplay_entry(reason, GameEntryFlow.SPAWN_BASE_99F)


func _collect_extracted_items(include_equipped_weapon := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if include_equipped_weapon and player != null:
		if player.has_method("get_equipped_backpack_item"):
			var equipped_backpack := player.call("get_equipped_backpack_item") as Dictionary
			if not equipped_backpack.is_empty():
				equipped_backpack["count"] = 1
				result.append(equipped_backpack)
		if player.has_method("get_equipped_weapon_item_for_slot"):
			for weapon_slot_index in range(2):
				var equipped := player.call("get_equipped_weapon_item_for_slot", weapon_slot_index) as Dictionary
				if not equipped.is_empty():
					equipped["count"] = 1
					result.append(equipped)
		elif player.has_method("get_equipped_weapon_item"):
			var equipped := player.call("get_equipped_weapon_item") as Dictionary
			if not equipped.is_empty():
				equipped["count"] = 1
				result.append(equipped)
	for slot in _inventory.get_occupied_slots():
		var item := (slot.get("item", {}) as Dictionary).duplicate(true)
		if item.is_empty():
			continue
		item["count"] = int(slot.get("count", 1))
		result.append(item)
	for slot in _quick_inventory.get_occupied_slots():
		var quick_item := (slot.get("item", {}) as Dictionary).duplicate(true)
		if quick_item.is_empty():
			continue
		quick_item["count"] = int(slot.get("count", 1))
		result.append(quick_item)
	for slot in _insurance.get_occupied_slots():
		var insured := (slot.get("item", {}) as Dictionary).duplicate(true)
		if insured.is_empty():
			continue
		insured["count"] = int(slot.get("count", 1))
		result.append(insured)
	return result


func _refresh_loot_label() -> void:
	if loot_label == null or _inventory == null:
		return
	loot_label.text = "金币 %d" % _run_value
	# 主人 2026-10-15：消费金币时的数字变化动画，获得金币时也要播。
	# 数值增加（捡币/赏金/退款）→ 播脉冲；减少（消费）→ 脉冲由
	# `_play_fate_balance_spend_feedback` 在购买事务里显式播，这里不重复。
	if _loot_readout_last_value >= 0 and _run_value > _loot_readout_last_value:
		_pulse_coin_readout()
	_loot_readout_last_value = _run_value
	_refresh_quick_item_hud()


func _room_status(type_id: String) -> String:
	return {
		"START": "废土入口已建立定位", "SCAVENGE": "搜索区：检查带提示的容器",
		"STORAGE": "大型库存区：注意占地与退路", "MERCHANT": "安全补给终端",
		"UPGRADE": "武器改造终端", "EVENT": "检测到可交互异常信号",
		"BASEMENT": "地下层：精英守卫与高价值搜索物资",
		"STAIRS_DOWN": "下行楼梯：通往地下层", "STAIRS_UP": "上行楼梯：通往二层",
		"ELEVATOR": "废土电梯：连接垂直探索层",
		"EXTRACTION": "撤离区：信标仍受 Boss 干扰",
	}.get(type_id, "区域暂时安全")


func get_generation_snapshot() -> Dictionary:
	var branch_types: Array[String] = []
	var size_counts := {"small": 0, "medium": 0, "large": 0, "arena": 0}
	var record_summary: Array[Dictionary] = []
	for record in _records:
		if not bool(record["main"]):
			branch_types.append(str(record["type"]))
		size_counts[record["size"]] = int(size_counts.get(record["size"], 0)) + 1
		record_summary.append({
			"id": record["id"], "type": record["type"], "size": record["size"],
			"position": record["position"], "main": record["main"], "parent": record["parent"],
			"index": record["index"], "vertical_level": record.get("vertical_level", 0),
			"custom_dimensions": record.get("custom_dimensions", Vector2.ZERO),
			"tower_role": record.get("tower_role", ""),
			"doors": (record.get("doors", []) as Array).duplicate(),
			"door_targets": (
				record.get("door_targets", {}) as Dictionary
			).duplicate(),
		})
	return {
		"theme_id": gameplay_theme.theme_id, "visual_theme_id": visual_theme.theme_id, "seed": run_seed,
		"room_count": _records.size(), "branch_count": branch_types.size(), "branch_types": branch_types,
		"required_branch_types": gameplay_theme.required_branch_types.duplicate(), "size_counts": size_counts,
		"records": record_summary, "has_extraction": _extraction != null, "is_3d": true,
		"room_dimensions": DungeonRoom3D.ROOM_DIMENSIONS.duplicate(true),
		"locked_edge_count": _open_edges.size(), "initial_room_keys": 1,
		"inventory_capacity": _inventory.get_capacity() if _inventory != null else BASE_INVENTORY_CAPACITY,
		"inventory_base_capacity": BASE_INVENTORY_CAPACITY,
		"equipped_backpack": get_backpack_equipment_snapshot(),
		"insurance_capacity": 2,
		"streaming_policy": "current_plus_open_neighbors",
		"minimap": minimap.get_snapshot() if minimap != null else {},
	}


func force_enter_room_for_test(room_id: String) -> void:
	var room := _room_by_id.get(room_id) as DungeonRoom3D
	if room != null:
		_on_room_entered(room)


func force_open_edge_for_test(a: String, b: String) -> void:
	var edge := _edge_key(a, b)
	if not _open_edges.has(edge):
		return
	_open_edges[edge] = true
	minimap.set_edge_open(a, b, true)
	_update_room_streaming(_current_room_id)
	_refresh_edge_visuals(a, b, true)


func get_runtime_snapshot() -> Dictionary:
	var active_rooms := 0
	var built_shells := 0
	var detailed_rooms := 0
	var active_lights := 0
	var active_ai := 0
	for room in _rooms:
		var snapshot := room.get_room_snapshot()
		if int(snapshot.get("stream_state", 0)) > 0:
			active_rooms += 1
		if bool(snapshot.get("shell_built", false)):
			built_shells += 1
		if bool(snapshot.get("detail_built", false)):
			detailed_rooms += 1
	for light in get_tree().get_nodes_in_group("wasteland_light_3d"):
		if light is WastelandLight3D and bool((light as WastelandLight3D).get_snapshot().get("illumination_active", false)):
			active_lights += 1
	for value in get_tree().get_nodes_in_group("enemy_3d"):
		if value is Enemy3D and (value as Enemy3D).is_runtime_ai_active():
			active_ai += 1
	var projectile_pool := get_node_or_null("ProjectilePool3D") as ProjectilePool3D
	var effect_pool := get_node_or_null("CombatEffectPool3D") as CombatEffectPool3D
	var vision := player.get_node_or_null("PlayerVision3D") as PlayerVision3D
	var unclaimed_key_count := 0
	for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
		if value is RoomKeyPickup3D and is_ancestor_of(value):
			unclaimed_key_count += 1
	return {
		"current_room_id": _current_room_id, "active_rooms": active_rooms, "built_shells": built_shells,
		"detailed_rooms": detailed_rooms, "total_rooms": _rooms.size(),
		"active_lights": active_lights, "active_ai": active_ai,
		"keys": _get_total_room_keys(), "inventory_used": _inventory.get_used_slots(),
		"inventory_capacity": _inventory.get_capacity(),
		"equipped_backpack": get_backpack_equipment_snapshot(),
		"spawned_key_room_count": _spawned_key_rooms.size(), "unclaimed_key_count": unclaimed_key_count,
		"open_edges": _open_edges.values().count(true), "total_edges": _open_edges.size(),
		"edge_states": _open_edges.duplicate(true),
		"wave_numbers": _room_wave_numbers.duplicate(true),
		"wave_totals": _room_wave_totals.duplicate(true),
		"resolved_event_rooms": _resolved_event_rooms.keys(),
		"event_combat_rooms": _event_combat_rooms.keys(),
		"extraction_types": _conditional_extractions.keys(),
		"extraction_defense_active": _extraction_defense_active,
		"projectile_pool": projectile_pool.get_snapshot() if projectile_pool != null else {},
		"effect_pool": effect_pool.get_snapshot() if effect_pool != null else {},
		"vision": vision.get_snapshot() if vision != null else {},
	}


func force_unlock_extraction_for_test() -> void:
	if _extraction != null:
		_extraction.set_locked(false)


func force_extract_for_test() -> void:
	force_unlock_extraction_for_test()
	if _extraction != null:
		_extraction.force_complete_for_test()


## — 手电筒电量 HUD —

func _update_battery_hud() -> void:
	if player == null:
		return
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	if flashlight == null or _hud_battery_cells.is_empty():
		return
	var ratio := clampf(float(flashlight.get_charge_ratio()), 0.0, 1.0)
	var tier := int(flashlight.get_tier())
	_apply_battery_fill_color(tier, ratio)
	_last_battery_tier = tier
	_refresh_battery_time_label(flashlight)


## 把"剩余秒数"格式化为 mm:ss 或 --:-- / OFF / FULL
func _refresh_battery_time_label(flashlight: Node) -> void:
	if _hud_battery_time_label == null:
		return
	if flashlight.is_in_facility():
		_hud_battery_time_label.text = "基地内暂停耗电 · %d%%" % int(round(float(flashlight.get_charge_ratio()) * 100.0))
		return
	var ratio := float(flashlight.get_charge_ratio())
	if ratio <= 0.0:
		_hud_battery_time_label.text = "00:00 · 耗尽"
		return
	if not flashlight.is_light_enabled():
		_hud_battery_time_label.text = "OFF · %d%%" % int(round(ratio * 100.0))
		return
	var secs := float(flashlight.get_estimated_remaining_seconds())
	if is_inf(secs) or secs <= 0.0:
		_hud_battery_time_label.text = "FULL"
		return
	var total := int(ceil(secs))
	var mm := total / 60
	var ss := total % 60
	_hud_battery_time_label.text = "%02d:%02d" % [mm, ss]


func _apply_battery_fill_color(tier: int, ratio: float) -> void:
	if _hud_battery_cells.is_empty():
		return
	var color := Color(0.94, 0.96, 0.42)
	match tier:
		0:
			color = Color(0.32, 0.92, 0.45)
		1:
			color = Color(0.94, 0.92, 0.34)
		2:
			color = Color(0.96, 0.62, 0.20)
		3:
			color = Color(0.96, 0.30, 0.18)
		_:
			color = Color(0.86, 0.20, 0.18)
	var active_cells := int(ceil(ratio * _hud_battery_cells.size())) if ratio > 0.0 else 0
	while _hud_battery_cell_prev_filled.size() < _hud_battery_cells.size():
		_hud_battery_cell_prev_filled.append(false)
	for index in _hud_battery_cells.size():
		var cell := _hud_battery_cells[index]
		var filled := index < active_cells
		var was_filled := _hud_battery_cell_prev_filled[index]
		var style := _make_prism_hud_card_style(
			Color(1.0, 1.0, 1.0, 0.30) if not filled else color,
			0.14 if not filled else 0.46,
			1,
			1
		)
		cell.add_theme_stylebox_override("panel", style)
		if filled != was_filled:
			_animate_battery_cell_transition(cell, was_filled, filled, color, index)
		_hud_battery_cell_prev_filled[index] = filled


## 电量格状态切换的视觉反馈：充电时一格一格闪烁变出，放电时闪一下再变空。样式保持原样。
func _animate_battery_cell_transition(cell: Panel, was_filled: bool, now_filled: bool, color: Color, position_index: int) -> void:
	if cell.has_meta("battery_anim_tween"):
		var old_tween: Variant = cell.get_meta("battery_anim_tween")
		if old_tween is Tween and (old_tween as Tween).is_valid():
			(old_tween as Tween).kill()
	var tween := create_tween()
	cell.set_meta("battery_anim_tween", tween)
	if now_filled and not was_filled:
		var stagger := float(position_index) * 0.12
		cell.scale = Vector2(0.45, 0.45)
		cell.modulate = Color(2.6, 2.6, 2.6, 1.0)
		tween.tween_interval(stagger)
		tween.tween_property(cell, "scale", Vector2(1.22, 1.22), 0.10)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(cell, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.18)
		tween.tween_property(cell, "scale", Vector2(1.0, 1.0), 0.10)
	elif was_filled and not now_filled:
		cell.modulate = Color(2.4, 2.4, 2.4, 1.0)
		cell.scale = Vector2(1.0, 1.0)
		tween.tween_property(cell, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.08)
		tween.tween_property(cell, "scale", Vector2(0.86, 0.86), 0.10)
		tween.tween_property(cell, "scale", Vector2(1.0, 1.0), 0.10)


func _on_flashlight_charge_changed(_ratio: float, _tier: int) -> void:
	_update_battery_hud()
	_persist_flashlight_state_to_checkpoint()


func _on_flashlight_state_changed(state_id: String, context: Dictionary) -> void:
	match state_id:
		"depleted":
			if status_label != null:
				status_label.text = "手电已耗尽,返回基地补给"
			if _hud_battery_panel != null:
				_flash_action_key(_hud_battery_panel)
			if AudioManager != null:
				AudioManager.play_sfx("flashlight_depleted")
		"restored":
			if status_label != null:
				var pct := int(round(float(context.get("amount", 0.0)) * 100.0))
				status_label.text = "电量 +%d%%" % pct
			if AudioManager != null:
				AudioManager.play_sfx("flashlight_charge_up")
		"facility_recharged":
			if status_label != null:
				status_label.text = "已回到99F基地 · 手电筒充满"
			if AudioManager != null:
				AudioManager.play_sfx("flashlight_charge_up")
		"consume_refused":
			if status_label != null:
				status_label.text = "电量耗尽,无法开启"
	_persist_flashlight_state_to_checkpoint()


## 行动检查点由其它局内系统决定何时创建；本模块只在已有检查点上补写自身状态。
func _persist_flashlight_state_to_checkpoint() -> void:
	var flashlight := player.get_node_or_null("PlayerFlashlight3D") if player != null else null
	if BaseManager != null and flashlight != null:
		BaseManager.patch_active_run_checkpoint({
			"flashlight_charge_ratio": flashlight.get_charge_ratio(),
			"flashlight_module_id": flashlight.get_module_id(),
		})
	_queue_runtime_autosave("flashlight_state")


## 物理 tick 推进电量闪烁 (低/临界/耗尽档 3Hz/5.5Hz)
func _tick_battery_blink(delta: float) -> void:
	if _hud_battery_panel == null:
		return
	_hud_battery_blink_accum += delta
	# 默认无闪烁
	var target_alpha := 1.0
	if _last_battery_tier == 3:
		# 3 Hz blink (0..1..0) on critical tier
		var phase := fmod(_hud_battery_blink_accum, 1.0 / 3.0) * 3.0
		target_alpha = 1.0 if phase < 0.5 else 0.45
	elif _last_battery_tier >= 4:
		# 5.5 Hz on depleted
		var phase := fmod(_hud_battery_blink_accum, 1.0 / 5.5) * 5.5
		target_alpha = 1.0 if phase < 0.5 else 0.30
	_hud_battery_blink_visible = target_alpha
	_hud_battery_panel.modulate.a = target_alpha
	# 倒计时每秒变化一次,但 2% 一格的耗电模式会让秒数频繁跳。
	# 这里用 process 帧频率刷新文本:消耗期间 mm:ss 走得很顺。
	if player != null:
		var flashlight := player.get_node_or_null("PlayerFlashlight3D")
		if flashlight != null:
			_refresh_battery_time_label(flashlight)
