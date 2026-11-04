# 首遇收租人后基地 NPC 迎宾（一次性剧情节拍）

FeatureID：BASE-NPC / ELITE-ROSTER。工程 0.1.0，基线 `3004502d` 加本会话已有改动。设计修订 r5（[20 号基地NPC](../20_技术施工_基地NPC.md) §13 新增）。日期 2026-11-04。

## 用户要求与落点

主人原话：「我不是增加了一个收租人的精英怪吗，当我第一次遇到精英怪后，我再次回到 99F 基地，我 99F 基地的绿色 NPC，会站在边上，说：你遇到收租人啦？有没有被夺走东西呀？你可以去二楼的档案室里看看它的信息哦。需要按照正常的链路完成这个任务，并且更新设计文档和账本。」

拆成四条：条件（**真正遇见过**，不是这局抽到）、站位（回基地时站在归航点边上）、开口（走近就自动说，不用按 E）、一次性（跨存档只播一次）。不新建任务系统、不新增存档字段。

## 实现

新增 `src/npc/NpcStoryBeatService.gd`：节拍判定与落盘。只读 `EliteRosterService.get_record().encounter_count > 0`（预约不算），说过没有读 `BaseManager.has_narrative_completed("npc_beat:<npc_id>:<beat_id>")`。落盘复用 `BaseData.narrative_history` —— 不新开字段，代价是这张表混入非剧本键，因此键前缀 `npc_beat:` 是硬约定，验收 S08 专门断言。

`NpcCatalog` 新增 `STORY_BEATS`（npc_id → beat_id → 定义）。台词、触发事实、指路的设施 ID（`monster_archive`）全在内容目录，代码里没有台词字面量。`archive_facility_id` 不是装饰：验收 S12 拿它去基地里找那个设施，断言"让你去看的终端真的存在、真的在二楼"。

`NpcCharacter3D` 新增迎宾状态：`_story_standby` 时 `_tick_patrol` 直接 return（停巡）、持续对准玩家、玩家进 `HAIL_RADIUS 4.0m` 自动开口、逐句轮播、整段播完落盘、从最近的巡逻点恢复巡逻。找玩家**不能只看 `_player`** —— 那个引用由 1.5m 交互热区写入，只看它会退化成"必须贴脸才开口"；改为优先 `_player`、否则按 `player_3d` 组取。

`TowerDescent3D` 读新锚点 `99层基地NPC迎宾锚点` 传给 NPC；每次进入 `facility` 房间再求值一次（同一次运行里"出去打完再回来"不会重建 NPC，只在 `_ready` 判一次会漏）。

`zone_base.tscn` 新增作者锚点，局部 `(-3.2, 0, -0.2)` ⇒ 世界 `(-3.2, -12, 4.8)`：离归航点 3.2m（在 4m 招呼圈内）、在西侧设备墙外的走道一侧、不挡中央主通道；0.45m 球体物理查询重叠 0 件。

## 首轮实测推翻了一版做法

第一版把用户那句话当成**一个**气泡一次说完。真实渲染（玩家自带相机、站在归航点）拍出来：40 字在 `wrap_width_px 560` 下排 4 行，气泡世界高 1.81m，挂高 3.40m 时顶边顶到画面上缘**被裁掉**，第一行字只露半个。

挂高 3.40m 是业主 2026-11-02 三轮调出来的"两行口径"（`base99_npc_talk.png` 定标），不该为一句台词再抬（再抬就离开视线中心）。改为：内容按两句存、每句两行、**自动轮播**（上一句 6s 放完接下一句，玩家不需要按 E）。拼接全文与用户原话逐字一致，S01 比对全文 + 首句，并断言单句 ≤ 24 字（超过就会排到三行、把气泡顶出屏幕）。

另修一处假警告：`_ready()` 求值时 `set_standby_world()` 还没被调用，第一版会在每次开档打一条「缺少迎宾锚点」。改为第一帧之后再判、只警告一次；真正"锚点缺失"由 `TowerDescent3D` 报。

## 验收

Godot 4.6.3，Autoload 前设置隔离 APPDATA。真实渲染为 Windows Vulkan Forward+ / NVIDIA RTX 4060 Ti、1280×720。日志与截图在工程外 `ShellStorm2-work/sessions/2026-11-04_base_npc_greeting/`。

| 验收入口 | 引擎退出码／脚本错误 | 结果 |
|---|---|---|
| `verify_base_npc_story_beat`（新增） | 0／0 | S01–S12 全通过：未遭遇不触发；**仅预约不成立**、首次生成确认后成立；回 99F 站到锚点（与锚点误差 < 0.05m）、1s 不漂移；玩家进 4m 自动开口、首句逐字一致、面向玩家；第一句放完自动接第二句；整段说完才落盘（`npc_beat:` 前缀 + `has_narrative_completed`）；播完恢复巡逻；重进基地不再重复；二楼档案终端存在（离地 7.56m）且已遭遇列表含收租人 |
| `verify_base_npc_flow`（回归） | 0／0 | A01–A26 全通过，含 A19 设施净空与 A13b 体型同口径 —— 新增迎宾锚点未打断原巡逻与交互 |
| `verify_tower_base_facility_persistent_flow`（回归） | 0／0 | 99F 基地 8 个设施与阻挡件在布置层新增锚点后仍全部存活、阁楼路线可用 |
| `verify_base_facility_interaction_zones`（回归） | 0／0 | 作者变换保留、设施热区仍可用（新增的是 Marker3D，不带碰撞） |
| `capture_base99_npc_greeting`（真渲染） | 0／0 | 两张图：`base99_npc_greeting_standby.png`（合成机位，NPC 站在走道一侧等、未开口）、`base99_npc_greeting_talk.png`（玩家相机，气泡完整在画面内、两行、未遮角色） |

日志中无非预期脚本错误；`未设置迎宾站位` 警告 0 条、`缺少迎宾锚点` 0 条。既有资源 UID 路径回退警告仍在（与本次无关）。

未执行：`core`/`full` 全套件；真实存档跨进程读档（用内存态 + 一次落盘断言代替）；多节拍排队；中途打断后重播的人工确认。

## 文档与账本

- [20 号](../20_技术施工_基地NPC.md) 升 r5：新增 §13（目标/所有权/内容契约/判定/落盘/站位与气泡/失败收口/新增步骤）、§11.1 验收、§10 迎宾锚点行、§4.2 命令查询事件、§4.3 快照键。
- [09 号存档](../09_技术施工_存档结算与复活.md)：`narrative_history` 键空间登记第二方 `npc_beat:`，写明为什么不开新字段。
- [06 号精英](../06_技术施工_怪物精英与Boss.md) §5.2.1：`encounter_count` 的下游用途多加一条，并声明精英侧不拥有这句提醒。
- [收租人契约](../design/精英02收租人状态与动作契约.md) r10 → r11：「血条与档案显示」补一段首遇提醒，指向 20 号 §13。
- [MODULE_INDEX](../MODULE_INDEX.md)：BASE-NPC 行加节拍与第二个验收入口，附注加一条。
- `docs/v0.1/feature_registry.json`：BASE-NPC 加 `verify_base_npc_story_beat` 与本记录。

账本：本轮**没有新增美术源、没有新增 AssetID**。角色账本 `CHR-PLY-BUNNY01-NPC-GREEN` 行属能力扩展（台词/行为变化，几何、动画、Prefab 路径与 SHA 不变），只补备注，日志 `v0.1.29`；场景账本 `ENV-BASE99-ART-LAYOUT-3D` 行因 `zone_base.tscn` 增加作者锚点，SHA `0c35b1c7…` → `65d6222e…`，日志 `v0.1.70`。基线的逐行指纹只刷新这两个 ID；**没有重算 `column_digests`** —— 那张表是全表口径，重算会把同一工作区里其他批次留下的 17 处既有 SHA 漂移一起吸收，等于替别人的改动背书。

门禁：`check_asset_registry.py`（full）17 条 SHA 漂移，全部为本轮之外的既有项（改前 18 条，本轮把自己那一条修掉了）；`check_documentation_contracts.py` 仍为 15 条既有断链，新增链接可解析；`check_asset_runtime_naming.py` 0；`check_level_decoupling.py` 0；`check_feature_traceability.py` 0（45 功能）；`check_domain_boundaries.py` 0；`check_verification_registry.py` 只剩 4 条既有未登记（`verify_base_lamp_dynamics` / `verify_base_lamp_visual` / `verify_enemy_action_recovery` / `verify_stairwell_turn_rail`），本轮新增入口已登记。两份验收日志过 `check_verification_log.py` 均为 0。

## 遗留

- 节拍是"一句话提醒"，不是任务系统：没有接取、没有追踪、没有奖励、没有任务面板。若以后要做成任务，需要新 FeatureID，不能往这里长。
- 多条节拍共用同一个迎宾锚点；需要专属站位时要加锚点（§13.8 第 3 条）。
- 玩家在半路按 E 聊天会暂停轮播，聊完继续；这条路径没有单独断言。
