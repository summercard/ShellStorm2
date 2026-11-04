# 15:5x 基地 NPC 首遇收租人迎宾（BASE-NPC r5）

主人要求：首遇收租人后回 99F，绿苔「站在边上」说一句话并指路二楼档案室；按正常链路做完、更新设计文档和账本。

## 做成什么

`NpcCatalog.STORY_BEATS`（台词/条件/指路设施）＋ 新 `src/npc/NpcStoryBeatService.gd`（判定+落盘）＋ `NpcCharacter3D` 的迎宾状态（站定→进 4m 自动开口→逐句轮播→说完回巡逻）＋ `zone_base.tscn` 新锚点「99层基地NPC迎宾锚点」(-3.2,0,-0.2)。

## 三条踩出来的经验

1. **40 字整句放不进现有气泡口径**。`wrap_width_px 560` ≈ 11 汉字/行 ⇒ 40 字排 4 行、世界高 1.81m，挂高 3.40m 时顶边被画面上缘裁掉（真渲染实测）。挂高是业主三轮调的"两行"值，不该为台词再抬。⇒ 台词拆两句、每句 ≤24 字、自动轮播（玩家不用连按 E）。验收加了"单句 ≤24 字"这条守门。
2. **`_player` 是 1.5m 热区口径，不能用来判"走近"**。迎宾要 4m ⇒ 必须另取 `player_3d` 组。只看 `_player` 会退化成"必须贴脸才开口"。
3. **`_ready()` 里求值节拍会拿到假"缺锚点"**：那时 `set_standby_world()` 还没被调用。改成第一帧后再判、只警告一次。

## 存档口径（重要）

复用 `BaseData.narrative_history`，键 `npc_beat:<npc_id>:<beat_id>`，**不新增字段**。09 号文档已登记这个第二命名空间。只在**整段播完**时写；半路被打断不算说过。

## 账本

无新增 AssetID。角色账本 NPC 行补备注（v0.1.29）；场景账本 `ENV-BASE99-ART-LAYOUT-3D` SHA 换新 + 备注（v0.1.70）。基线只刷这两个 ID 的逐行指纹，**没重算 column_digests**（否则会把同工作区里别人的 17 处既有漂移一起吸收）。

## 环境提醒

- 工作区是**多会话并发**的：`run_verification_suite.sh` 在我这轮前后有 4 行差异，其中 3 行是别的会话加的（`verify_arms_taker_roaming` / `verify_monster_archive_facility` / `verify_arms_taker_tactics`）。别把它们的功劳/锅算到本轮。
- `check_documentation_contracts.py` 用裸 `python` 跑，缺 openpyxl ⇒ 「Media asset domains invalid」是环境问题；用 `~/.workbuddy/binaries/python/envs/default/Scripts/python.exe` 单独跑该门禁是 0（213 资产）。
