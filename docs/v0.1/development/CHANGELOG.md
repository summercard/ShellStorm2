# 游戏设计文档 v0.1 变更记录

## 2026-09-23｜开场掉枪改由剧情刷 + 剧情进度落档（跨局历史）

**动机（业主）**：「开场场地的枪，要做在剧情里头，刷一把枪出来，剧情编辑器需要能控制这个。然后剧情的桥段跟着存档走就可以了。」

**改动一：`scene.spawn_item` —— 剧情把物品刷到地面**
- `NarrativeAdapter3D` 新增 `scene.spawn_item`（`item_id` / `count` / `point_room` + `point_offset` / `spread`），与 `scene.spawn`（刷怪）同族、共用同一套房间相对锚法；与 `grant.item`（直接进包）的区别是**它落在地上**。锚点解析抽成 `_item_anchor()`，**强制要求 `point_room`**（地面物品必须挂进房间容器，否则离房即孤儿）。
- `Dungeon3D` 新增两个正门：`narrative_spawn_item(room_id, item_id, count, origin, spread)`（`item_id` 交奖励服务 `resolve_fixed_item` 解析，唯一真源）与 `narrative_spawn_loot(room_id, items, origin, spread)`（放现成 item 字典，供"把手上的那把原样丢下"）。
- **剧本 01 `nar_tower_opening_01_wake` 在 `at: 0.0` 用它刷出厂枪**（`weapon_sprinkler`，落点 = 办公室局部 `[5.3, 0.05, -0.7]`，`spread: false` 精确落地以便 `actor.face` 指得准）。
- `TowerDescent3D`：`_reset_new_game_opening_loadout()` → **`_clear_new_game_opening_loadout()`（只收回身上的枪，不再由代码掉枪）**，`_drop_new_game_opening_weapon()` 删除。`NEW_GAME_OPENING_DROP_OFFSET` 不再被生产代码消费，改为**剧本两处偏移的等值基准**（`verify_opening_script_runtime` 有等值断言）。

**改动二：剧情进度落档（跨局历史）**
- `BaseData.narrative_history`（照抄 `elite_archive_records` 形状，只放 JSON 安全字段；**不升 `SAVE_VERSION`**，旧档缺字段 = 空历史 ⇒ 已看过的 `run` 剧情重播一次，属既有声明）。
- `BaseManager`：`commit_narrative_completion(id, result)`（唯一写入权，写盘失败回滚内存）/ `has_narrative_completed` / `get_narrative_history[_snapshot]` / `replace_narrative_history_for_test`；常量 `COMPLETABLE_NARRATIVE_RESULTS = ["duration", "flow.end", "skip"]`。
- `NarrativeDirector3D`：`_try_fire` 的 `run` 档裁决改为 **本局内存态 ∪ 跨局档案**；`_finish` 新增唯一写入点 `_commit_history_if_completed()` —— **只有完整收口才写**，被抢占与 `abort:<reason>`（死亡/撤离/场景卸载/解析失败）**不写**，这正是"未达成条件的桥段下次仍会触发"的实现点；`forever` 档不写。历史读取**惰性**（autoload 的 `_ready` 不碰 `user://`）。
- ⚠️ **不跨模块读 autoload 常量**：`_commit_history_if_completed` 最初写 `reason not in BaseManager.COMPLETABLE_NARRATIVE_RESULTS`，实测让导演节点在编译期整体失效（剧情全部不起播）；改为本文件字面量 `COMPLETABLE_RESULTS`，两侧一致性由验收盯着。

**改动三：适配器绑定改为导演注入（顺带修掉的静默降级）**
- 适配器原先自己猜 `get_tree().current_scene` 找地牢；验收里场景是手动 `add_child` 进 root 的（`current_scene` 不是它）⇒ 所有 `scene.*` 指令**静默降级**（症状：剧情刷的东西一个都没出现 + 一行降级告警）。
- 新增 `NarrativeAdapter3D.bind_dungeon(node)`，由导演 `_bind_dungeon()` 同步注入；`room_node()` 的收集根也改为已绑定的地牢。
- ⚠️ 但**不抢已有绑定**：验收会把替身注入适配器，无条件覆盖会让首帧两条 `actor.say` 全部丢失（B1「同帧两条按书写顺序执行」变红，二分定位确认）。

**验证**（隔离 `APPDATA`；每个用例前清 `app_userdata`，因为历史落档会让**跨用例互相污染**）：
- `verify_opening_script_runtime` **OK/105 项**（含"办公室地上正好一件掉落物"= 剧情刷出的那把枪；等值断言全过）。
- `verify_narrative_timeline` **OK/110 项**（107 → 110：新增 C4b 两条 + 复位段一条契约），关键三条：**完整收口后必须落档** / **已有档案时不得再触发** / **复位存档后档案必须为空**。
- `verify_block00_floor98_assembly` **OK checks=230 失败 0**（K2 落点判据段仍绿）。
- 反向定位：去掉"不抢已有绑定"守卫 ⇒ B1 精确变红；恢复 ⇒ 全绿（逐次还原，`RESTORED=True`）。

**未变更**：未改剧情四档语义（`retry` / `never` 裁定待拍板）、未改内容数据库表格（剧情 sheet 待拍板）、未改资产与台账。

## 2026-09-23｜天台下线被当成「新游戏开场」（落 98F 办公室 + 收走武器）

**动机（业主真机报告）**：「新开存档进入游戏后，完成前期的剧情。来到天台，在天台的边缘下线后。再上线。会回到游戏初始的状态，身上没有武器。」业主的设计是「非战局内下线，上线都回 99F 基地中的固定出生位置」。

**根因（两处缺陷叠加）**：
- **开场判据复用了「从天台开始」的判据。** `TowerDescent3D._should_open_new_game_in_master_office()` 最后一行直接 `return _should_start_on_rooftop_for_entry()`，而后者在「基地快照 `scope=="base"` **且** `current_room_id=="start"`」（= 上次停在 100F 天台）时为真 ⇒ **每一次「在天台边缘下线」都被判成全新存档**：落 98F `floor_01_exit`，并由 `_reset_new_game_opening_loadout()` 用 `clear_all_equipped_weapons()` 把玩家身上的枪收走。两个函数本是「互为正反面」的假设在此崩塌 —— "上次在天台"是**中途下线的常态**，不是"全新存档"。
- **开场地上的枪不进存档。** `_drop_new_game_opening_weapon()` 把枪生成成运行时临时掉落物，`Dungeon3D.build_runtime_save_snapshot()` 只记 `equipped_weapon_items` ⇒ 没捡就下线的话，手上（`[{}, {}]`）地上都不会再有枪。

**实测（headless 隔离，快照只写内存）**：注入 `scope=base / current_room_id=start` ⇒ `should_open_master_office=true`、落点 `(−32.5, −23.97, 5.0)`（98F 办公室中心）、`weapon0/1` 均为空、且 `nar_tower_opening_01_wake` 照常起播。真机档核对：`tutorial_completed=true`、`equipped_weapon_items=[{}, {}]`。

**改动**（`src/world3d/TowerDescent3D.gd`）：
- `_should_open_new_game_in_master_office()` 判据改为 **教程未完成（`BaseManager.should_start_on_rooftop()`）且本档没有任何运行时快照**，不再复用「从天台开始」。选「没有快照」而不是新增「开过场」标记，是为了**零新增存档字段**；复位存档会清空快照 ⇒ 复位后重新开始仍看得到开场（与 `1848` 的归零需求一致）。
- `_should_start_on_rooftop_for_entry()` 的基地快照分支改为 `return BaseManager.should_start_on_rooftop()`：**非战局内下线（100F 天台与 99F 基地都算）一律回 99F 基地固定出生点**；`ROOFTOP_LOGOUT_SPAWN` 只剩「教程未完成的新手期出生」一个用途。
- 常量与函数契约注释同步；`docs/v0.1/09` §10.1 出生点口径同步（含废弃说明与原因）；`docs/v0.1/08` §13.8 记录本次修复。

**验证**：
- `verify_block00_floor98_assembly` 新增 **K2 段**：5 组判据（天台下线 + 教程已完成 / 99F 基地下线 / 塔内续局 / **全新档必须仍走办公室开场** / **教程未完成但已开过场不得重演开场**），`BLOCK00_ASSEMBLY_OK checks=230`、失败 0；`check_verification_log.py` exit 0。
- **反向对照三组**（每次注入后跑、跑完逐字节还原，`RESTORED_IDENTICAL=True`）：① 只把开场判据改回旧实现 ⇒ **恰好 1 条红**（「教程未完成但已开过场仍会重演开场」）；② 只把落点判据改回旧实现 ⇒ **恰好 1 条红**（「教程完成后天台上线没有回 99F 基地」）；③ 两处同时回旧（= 真机原状）⇒ **恰好 3 条红**（多出「天台上线被判成新游戏开场」）。证明 5 组断言各有分辨力，非假绿。
- 回归全绿：`verify_game_entry_flow`（OK）、`verify_opening_script_runtime`（OK/105 项）、`verify_pause_game_save_reset_flow`（OK）、`verify_narrative_timeline`（OK/107 项）。

**未变更 / 遗留**：未改剧情语义与触发档位、未改存档 schema（**零新增字段**）、未改资产与台账。**遗留**：开场地上的枪仍不进存档 —— 判据修好后正常玩家不会再被误收枪，但真新档玩家没捡枪就下线仍会丢；三个候选见 `design/2026-09-23_剧情触发语义规范与跨局历史_方案.md` §D.2（推荐把地面枪并入 `active_run_snapshot.world_drops[]`）。

## 2026-09-23｜P2 媒体资产与功能追溯链

- 将原 UI+音频合并账本拆为 UI 17、音效 48、音乐 9 三本独立账本，同步总目录、迁移清单、3 个专用 Skill 与专项门禁。
- 新增 `feature_registry.json` 与 `check_feature_traceability.py`，37 个功能全部具有 Owner、主设计、开发记录和已注册验收。
- 补 `RevivalPolicy` v0.1 空策略与契约验收；为既有 PostFX 脚本补验收场景并注册进 `core`。
- 详见 [P2 修复记录](2026-09-23_p2_media_and_traceability_repair.md)。

## 2026-09-23｜P1架构与事务收口

- 奖励搜索/击杀/清房/钥匙/保底备弹/剧情全部切到`RuntimeRewardCoordinator → RewardService`，删除`LootModule`两个旧抽表入口。
- 蓝图工坊升级改为一次原子、幂等、可回滚事务，并新增独立故障验收。
- 确认撤离/死亡结算已由`commit_run_settlement`收口；修正`MODULE_INDEX`过期事实。
- 到达门/隔离门改为写盘成功后开门，旧段卸载改为先保存提交意图再删节点，恢复会重放已卸载段。
- 精英档案、换装、基地/靶场查询改走`BaseManager`公开命令/快照，战斗调用者改走`VfxPool3D`公开查询/工厂；生产代码不再跨域访问这两处私有状态，6个原有专项回归通过，并新增`check_domain_boundaries.py`防回退门禁。
- 154 个验证场景实现唯一套件归属并新增注册门禁；删除 790 个一次性用户快照/根目录杂项（约691 MiB，已落在`c425b717`）。
- 完整范围、验收与剩余债务见 [P1记录](2026-09-23_p1_architecture_and_transaction_repair.md)。

## 2026-09-22｜撤离读条期间阵亡的终局归属修复（阵亡即中断读条 + 一次行动一个结算事务 ID）

**动机（业主指定）**：「检查一下游戏中死亡，撤离的各种流程是否健康。」

**根因（四时序实测全错，两处独立缺陷叠加）**：
- **撤离读条不看玩家死活。** `ExtractionBeacon3D._process` 只认 `_remaining <= 0` 就发 `extraction_completed`；撤离是 30s 长读条且分 5 阶段刷拦截怪，读条期间被打死是设计内场景，而死亡**不暂停场景树**（全工程 `get_tree().paused` 只在主菜单与暂停菜单置位）⇒ 尸体旁的读条照常走完、照常判「撤离成功」。`Dungeon3D._on_extraction_completed` 又只有「同一个信标」这一条守卫，既无 `_completed`、也无玩家存活判断。
- **终局复位把结算闸门重新打开。** `TowerDescent3D._return_successful_extraction_to_facility` 末尾 `_completed = false`（本意是「复位后本次行动可继续」）同时解除了 `_finish_run` 的 `if _completed: return`。而死亡动画 1.35s 比成功返航的 0.8s 窗口更长 ⇒ 死亡动画在复位**之后**才结束，于是「撤离成功」结算完再叠一次「阵亡」结算。
- **幂等失效**：成功用 `run_success`、死亡用 `run_death` 两个事务 ID，`BaseManager.commit_run_settlement` 的 `completed_transaction_ids` 去重拦不住，两笔都真写盘 ⇒ 同一次行动 `total_runs +2`、`successful_extractions +1`，且未保险物资被按 50% 扣损。

**实测四种时序（塔楼 / 独立副本 × 信标先/后）**：塔楼 ⇒ `success=true` 与 `success=false` 各一次（重复结算）；远征 ⇒ 只有 `success=true`，**死亡被完全吞掉**（违反文档 09 §5.1 与「重复请求不能重复发放或扣除」）。

**改动**（`src/world3d/Dungeon3D.gd`、`src/world3d/TowerDescent3D.gd`、`src/player3d/Player3D.gd`）：
- 新增 `_abort_extraction_on_death()`：HP 归零即作废进行中的信标。顺序是契约 —— **先清 `_active_extraction_beacon` 再 `abort()`**，让 `extraction_cancelled` 在「不再是当前信标」处直接返回，不要用「受击中断」文案顶掉死亡文案。
- 新增 `_is_player_dead()`（状态机 `dead` + `current_hp <= 0` 双判据，只查状态机会漏掉 HP 刚归零那一帧），`_on_extraction_completed` 追加 `_completed or _is_player_dead()` 守卫，并顺带作废信标。
- 新增**行动代际** `_run_generation` / `_death_recorded_generation`：复位 = 新一轮，代际 +1 使「返航窗口内阵亡、动画在复位后才结束」的那次死亡失效（`_on_player_death_animation_finished` 比对代际），并配 `_reset_death_settlement_state()` 清掉上一轮死亡框与就绪标志，保证新一轮阵亡还能重新弹框。
- `_get_run_settlement_transaction_id()` **不再按 success 分叉**，成功与死亡共用同一行动 ID；三处提交点补 `_absorb_duplicate_settlement()`，命中即撤销本次内存改动并停手，不再给出与档案矛盾的第二套结算画面。
- `Player3D` 新增 `hold/release_post_settlement_invulnerability()`：结算已提交到场景切走/复位完成之间（塔楼 0.8s、远征 0.8s）玩家输入被锁、无法走位，残留拦截怪足以把他拖死；`_update_invincibility` 尊重该标志、不参与倒计时。

**验证**：
- 新增专项 `verify_death_during_extraction_flow`（已登记进 `scripts/run_verification_suite.sh`）：4 种时序各断言「信标必须已中断 + 阵亡恰好结算 1 次 + 不得出现 success」；事务 ID 契约断言成功与死亡拿到同一 ID；4 条反向对照 —— ①健康玩家撤离仍恰好 1 次 success、②无撤离的阵亡仍恰好 1 次 failure、③返航复位后新一轮阵亡仍能弹框并结算、④结算后保护挡伤害且解除后能正常受伤。`DEATH_DURING_EXTRACTION_FLOW_OK` exit=0。
- **反向对照（会失败证明）**：同时禁用「阵亡中断」与「完成守卫」两道防线后复跑 ⇒ 四种时序全部变红（`塔楼·信标先读完：阵亡被判成撤离成功，结算序列 ["success"]` 等 8 条），断言有分辨力、非假绿。
- 回归：`verify_run_settlement_transaction`、`verify_tower_extraction_return_flow`、`verify_expedition_extraction_carry_return`、`probe_death_return_loadout` 全部 exit=0 且带原成功标记、零 ERROR。
- preflight（`verify_scene_preflight.gd`）对新场景退出码 0。

**未变更**：未改撤离时长/刷怪阶段/掉落与保险数值，未改安全房主动弃局（`_confirm_expedition_exit`）路径，未改任何资产/账本/设计源。**已知残留**：返航窗口内若玩家已被作废的阵亡拖到 hp=0，会停在基地原地（本次已由结算后保护前置规避，但未给 Player3D 加减伤免疫之外的复活路径）；`docs/v0.1/09` 与 `docs/v0.1/development/CHANGELOG.md` 已同步。

## 2026-09-22｜命运卡三选一界面接上手柄操控（默认焦点 + 环绕导航 + ui_cancel 放弃 + 同帧撞名修复）

**动机（业主指定）**：「命运卡片出现的那个界面，手柄不能操控。」

**根因**：命运卡三选一是 `Dungeon3D._build_door_fate_overlay()` **代码构造**的覆盖层，不在 `UiMenuFocus.ensure_focus` 覆盖的那批静态场景菜单里 ⇒ 从未 `grab_focus()`。而 Godot 4 的 `ui_left/right/up/down`（十字键/左摇杆）与 `ui_accept`（A 键）**都必须先有 gui focus owner 才会被派发** ⇒ 键鼠可用（鼠标点击不依赖焦点）、**手柄完全不能操控**。同批还有两处缺口：① 卡片按钮在翻转动画期间 `disabled = true`（防翻面前误点），禁用按钮不可聚焦、`UiMenuFocus.is_focusable` 也会排除它 ⇒ 焦点只能等翻转结束后再抓；② 放弃走的是**硬比 `KEY_ESCAPE`**，手柄 B（`ui_cancel`）到不了该分支。

**改动**（`src/world3d/Dungeon3D.gd` 6 处）：
- 新增 `_maybe_focus_fate_card()`：在 `_finish_reference_tarot_flip()` 解除 `disabled` 的那一刻抓默认焦点（三张卡翻转带 stagger，第一张最早解锁 ⇒ 焦点落在第一张卡）；**只在当前无焦点持有者时抓**，不抢玩家已用鼠标/手柄选中的卡。
- 新增 `_configure_fate_card_focus_navigation()`：显式指定三张卡的左右邻居并**首尾环绕**（逆位卡是整张旋转 180° 的实体卡面，自动 neighbor 推导依赖可见矩形方位、旋转后可能失准；自动推导也不做环绕，按到头就没反应）；上下接到同一组环绕，避免焦点被扔出弹窗。
- `_build_door_fate_overlay()`：收集三张卡按钮，交给上面的导航配置。
- `_unhandled_input()`：命运卡放弃改走 `event.is_action_pressed("ui_cancel")`（键盘 ESC 与手柄 B 共用）—— 与 0808 把 M/1/2/3/4 从硬比 keycode 改成 action 是同一类修正。
- `_close_door_fate_overlay()`：**先摘除再 `queue_free()`**（本轮检修出的第二个真实缺陷）。`queue_free()` 要到帧末才真正释放节点；同一帧内再次打开弹窗（连续两次命运卡流程 / 验收用例）时，新节点会与仍挂在树上的旧节点**撞名**、被引擎静默改名为 `DoorFateOverlay3D2`，此后所有按名查询（探针/验收里的 `HUD/DoorFateOverlay3D`）永远找不到这个弹窗。

**保持边界**：翻转动画、卡面美术、`tarot_face_ready` / `tarot_orientation` 元数据、三选一结算与满格转货币逻辑逐值不变；只在动画收尾补焦点、补邻居、换取消入口。

**验证**：
- `verify_dual_weapon_quick_map_fate_flow` 新增**手柄可操控契约**：等三张卡翻转完成后断言「弹窗节点存在 / 有 focus owner / focus owner 在弹窗内 / focus owner 是三张卡之一 / 卡有左右邻居」，再合成 `InputEventAction("ui_cancel")` 断言能放弃；复跑 `DUAL_WEAPON_QUICK_MAP_FATE_OK` exit=0。
- **反向对照 4 组**（`_scratch/fate_focus/negctl_fate_focus.py`，行级替换后逐行还原）：`no_focus` ⇒ 3 红、`no_neighbor` ⇒ 2 红、`hardcoded_esc` ⇒ 2 红、`no_detach` ⇒ 3 红，各自精准命中，`ALL_VARIANTS_HIT_EXPECTED`。
- 回归 `verify_gamepad_input_flow` `GAMEPAD_INPUT_FLOW_OK` exit=0。
- `verify_reference_hud_fate_visual` 在 `--headless` 下 4 条 `Could not capture` 红 —— **既有 headless 限制**（无渲染目标，该用例本就须带窗口跑），无新增断言失败。

**未变更**：未改命运卡内容 / 概率 / 结算，未改任何资产 / 账本 / 设计源；未提交（工作区混并行会话在制品）。

## 2026-09-22｜远征关卡01 Boss竞技场白模 v001（50×40m）：由局内01 竞技场派生并登记场景账本

**动机（业主指定）**：「把大小做成 1/3 的，复制一份过去给远征关卡01 用，作为远征01 的 boss 竞技场白盒，按照 skill 和规范存放到对应目录去。」

**口径修正（本轮的关键判断）**：**精确 1/3 无法落地** —— 来源竞技场 190×90m 的线性 1/3 为 **63.33×30m**，而 63.33 不是 5m 的整数倍。两条硬约束同时被踩：① 墙件契约要求「非整模数边缘只用 2.5m 收边」⇒ 63.33m 的边会长出 3.33m 非标件；② `create_floor_grid` 用 `round(width/5)` 铺砖 ⇒ 非整模数时地砖网格溢出包络，包络校验 `FAIL`。且上一版组件策略明令禁止缩放与合并（`no scaling or joining`）⇒「缩小 copy」本身无效。**故本资产是「1/3 意图」的合规解，不是精确 1/3**：经业主裁决取 **50×40m**（10×8 整槽，`FIXED_TRIM` 归零），实际轴比 X `0.2632` / Y `0.4444`。

**改动**：
- 新增资产 `ENV-EXPEDITION-L01-BOSS-ARENA`：`source/art/whitebox/tower_zones/expedition_01/v001/blender/远征关卡01_白模_Boss竞技场_50x40m_v001.blend`，**50×40×11.9m / 121 网格**（80 地砖 + 1 整板 + 38 实墙 + 2 门墙）。
- 新增 `scripts/blender/build_expedition01_whitebox_v001.py`（构建；`derivation.method = procedural_rebuild_on_5m_grid`，`scaled_in_blender = False`）、`scripts/blender/audit_expedition01_whitebox_v001.py`（**只读**探针）、`scripts/register_expedition01_boss_arena_ledger.py`（台账定点登记）。
- 台账 `ShellStorm2_场景账本_v001.xlsx`（改前已备份 `…bak_expedition01_boss_arena`）：**资产主表第 241 行**（状态 `Blender源已完成`）、**3D-场景通用第 147 行**（`白模源已完成；QA PASS`，与既有 17 行白模条目同口径）、**域变更日志第 18 行**（`v0.1.12`）、**总览 10 处统计区间 `$240 → $241`**（A6/C6/E6/G6/B10/C10/B11/C11/B12/C12）。第 18/19 列查重公式为行自引用，区间末端须覆盖新末行，故第 6–241 行整体重算（235 行，属范围扩张的必然结果）。
- 门：南 → `boss_prep`（净门心 +2.5m）+ 西 → `boss_exit`（−2.5m）；门位由来源门位**按墙面比例投影后吸附到净门心集合 `{±(2.5+5k)}`**。吸附到 2.5m 奇数倍是刻意的 —— 只有净门心落在该集合，门槽两侧才各剩整数个 5m 模数，`FIXED_TRIM` 才能归零。
- 来源对照差异两处需留意：① 来源仅西侧一组门，本资产**补了一扇南侧进场门**（来源 .blend 无可继承对应门）；② 地砖 684 → **80**（非 684/9≈76），因为砖数按新尺寸重算，不沿用来源砖数。

**验证**：
- Blender headless 构建 → `EXPEDITION01_WHITEBOX_V001_ASSET_OK` / `..._READY`，`failed_assets: []`；资产级 `PASS`（failures/warnings 均 `[]`）；台账级 `PASS`，`asset_count = 1`。
- 只读探针复核（重开 .blend 复测）：对象数 121、包络 `[-25,-20,0]..[25,20,11.9]`、最长墙件 **5.0m**（超 5m 件 0）、两门净跨均 **2.2m**、非单位缩放 `[]`、原点契约违规 `[]`。
- 结构门禁 `check_asset_registry.py --scope structure`：**与基线逐项一致**（`index_row_mismatch 1` + `invalid_status 5` = 6 项，均为历史既存：主账本第 11 行索引漂移 + 第 233–237 行「白盒组件」非法状态），`asset_count` 425 → **426** ⇒ **未引入新门禁问题**。
- 渲染口径：俯视图为正交、`ortho_scale = max(宽,深)×1.18`，11.9m 墙体几乎无侧影 ⇒ **俯视图只呈现地板足印**，与来源 v003 表现一致，非渲染缺陷；墙/门证据以探针实测与参考图为准。

**未接入（阻塞项，非本轮责任）**：远征01 设计源 `data/floors/floor_00.json` 只有 entry + room_01…05 + extraction 共 **7 房，无 BOSS 房席位**；`level_plan.json` 的 `room_templates` **无 50×40 房型模板**；`FloorPlanGenerator.gd` 的 `_expedition_rooms()`（第 403 行）是写死的 7 间排布，**无远征 Boss 房生成器**（塔楼走 `generate()` + `_boss_rooms()` + `ROOM_SIZES.BOSS_ARENA = 90×90`）。⇒ 本资产为**美术侧先行**，账本状态只写到「源已完成」，**未写** `原型已接入` / `正式美术已接入`。运行时接入需 A 段补 ① Boss 房记录 ② 房型模板 ③ 生成器产出 ④ 放置与门连通。

**未变更**：未导 GLB、未建 PackedScene、未制作碰撞、未改任何 `.gd` / `.tscn` / 设计源 JSON；塔楼 `BOSS_ARENA = 90×90` 与来源 190×90 的尺寸分歧（`docs/v0.1/05.2` 决策项 D2）**仍待裁决**，本资产不依赖该常量，未加剧分歧。

**回滚**：`restore …xlsx.bak_expedition01_boss_arena`；删除 `source/art/whitebox/tower_zones/expedition_01/v001/` 与三个新增脚本。

- 详见[交付记录](2026-09-22_远征01竞技场白盒.md)、[QA 报告](../../../source/art/whitebox/tower_zones/expedition_01/v001/QA_REPORT.md)。

## 2026-09-22｜弹壳停留时长再缩短 1 秒（4.7s → 3.7s）

**动机（业主指定）**：「弹壳的停留时长（再）缩短 1 秒。」—— 在上一版「+1.5 秒」的基础上回调 1 秒。

**口径**：弹壳可见时长 = `VfxShellCasing3D.DEFAULT_LIFETIME`；飞行 / 弹跳 / 滚动三段时长由物理常量与初速度决定、**不随寿命变化** ⇒ 寿命增减的部分**全部落在「落地静止后的停留」上**，故「缩短 1 秒」等价于 `DEFAULT_LIFETIME: 4.7 → 3.7`（累计：`3.2 →（+1.5）4.7 →（−1.0）3.7`）。实测（验收按 `1/60 s` 步进求静止时刻）：`t_settle = 1.15 s`、停留 `3.70 − 1.15 = 2.55 s`（上一版 `3.55 s`）。

**改动（单点）**：
- `src/vfx/VfxShellCasing3D.gd`：`DEFAULT_LIFETIME := 4.7 → 3.7`（注释块补两轮定档沿革与新的成本对照）。
- `tests/verification/verify_combat_vfx_toon_v002.gd`：`_check_shell_settled_hold()` 的常量组按「上一版 / 本轮缩短量 / 定档值」重排为 `EXPECTED_SHELL_LIFETIME_PREVIOUS := 4.7` / `EXPECTED_SHELL_DWELL_SHORTEN := 1.0` / `EXPECTED_SHELL_LIFETIME := 3.7`，并把原先被当作「增量」使用的那个数**独立成 `EXPECTED_SHELL_HOLD_FLOOR := 1.5`**（观感下限）。`samples=16` 不变。

**断言结构（本轮的重要修正）**：上一版把「停留 ≥ 1.5 s」这条行为断言写在了「增量」常量的前提上 —— 数值上恰好相等，但语义是错的（增量是 ±N 的**需求量**，下限是**可感知门槛**，两者碰巧都是 1.5）。本轮把两者拆成独立常量，并在注释里写明各自守什么：
- ① `lifetime == 3.7` —— 定档值（外部真源）；
- ② `4.7 − lifetime == 1.0` —— **本轮缩短量**（业主诉求本身；换方向时减号语义要同步翻）；
- ③ `lifetime − t_settle ≥ 1.5` —— **下限守卫**，守「飞行段被调长、把停留吃光」这类隐形退化；
- ④ `MAX_SECONDS` 内必须测到静止时刻（哨兵）。

**反向对照（两组，都精准变红后还原，`grep -rn "REVERSE-CONTROL" src/ tests/` 为空）**：
- **RC9**：`DEFAULT_LIFETIME` 退回 `4.7` ⇒ **精准 3 红**（`寿命不是定档值 3.70：4.700`、`实例寿命未按 DEFAULT_LIFETIME 初始化：4.700`、`停留缩短量不是 1.0s：上一版 4.70 − 寿命 4.70 = 0.00`），其余全绿、`EXIT=1`；还原后 `EXIT=0`。
- **RC9b（证明 ③ 是活的守卫，不是摆设）**：把 `ROLL_DAMPING: 3.4 → 0.2` 让飞行段吃满寿命 ⇒ ③ 精确命中 `弹壳落地静止后停留只有 1.23s（观感下限 1.5s）：t_settle=2.47 lifetime=3.70`。**这一步是必要的**：只跑 RC9 时 ③ 仍绿（`3.55 ≥ 1.5`），无法证明它被测到过。

**成本（随寿命同步下降，未做池化改动）**：`VfxPool3D` 对 active 实例**无上限**（`max_per_kind` 只管 inactive 回收桶）⇒ 射速 `1.0 ~ 12.0 发/s`（`BlueprintRegistry` 全体枪械）× `3.7 s` ⇒ 最坏同屏约 `44` 枚（v002.7 的 `4.7 s` 下约 `56` 枚、v002.2 的 `3.2 s` 下约 `38` 枚）。每枚 `3` 个 `MeshInstance3D`、`288` 三角面 ⇒ 约 `13k` 三角面、约 `130` 次绘制。

**未变更**：AssetID `VFX-SHELL-CASING-3D`、Prefab 路径与版本 `v001`、PBR 定档（`0.8 / 0.6`）、尺寸基准（`0.8`）、抛壳随机化幅度、`floor_y` 契约与「不接物理引擎」口径、探针四机位取景均未动 ⇒ **账本无需改动**。

**验证**：`verify_combat_vfx_toon_v002` → `COMBAT_VFX_TOON_V002_OK (samples=16)`（`EXIT=0`、0 ERROR，抽样 `lifetime=3.70 settle_at=1.15 hold=2.55`）；`verify_vfx_pool_lifecycle` → `VFX_POOL_LIFECYCLE_OK`；真渲染探针 → `SHELL_CASING_VISUAL_OK captured=4 skipped_headless=0`（散布判据 `off_line_residual=0.3393`，四机位全部重出图）。

<br>
## 2026-09-22｜右摇杆瞄准手感重做：瞄准辅助 + 响应曲线（业主选「2+1」）

**动机（业主指定）**：承接同日「左摇杆同控朝向改默认关」条目，业主确认「好，2+1调整一版」⇒ 采用候选方案 **2（瞄准辅助/磁吸）为主、1（响应曲线 + 幅度权威）为辅**。

**问题根因（复述同日勘察）**：`gamepad_aim_deadzone=0.20` 吃掉 20% 行程、`gamepad_aim_smoothing=0.35`（≈60ms 滞后）、`_update_aim()` **只取摇杆方向角、丢弃幅度**（无响应曲线）⇒ 死区边缘轻推也产生大角度偏转、且无法「轻推精瞄 / 重推快转」；摇杆边缘角度分辨率物理上限约 **1mm≈3~4°**；`aim_direction` 三用 ⇒ 瞄准精度 = 命中精度。

**改动 ①｜响应曲线 + 幅度权威**（`src/core/GamepadInput.gd`）：
- 新增纯函数 `resolve_aim_speed_scale(magnitude_after_deadzone)`：`shaped = clampf(t,0,1)^AIM_RESPONSE_EXPONENT(1.60)`，返回 `AIM_PRECISION_SPEED_SCALE(0.35) + (AIM_FLICK_SPEED_SCALE(1.60) − 0.35) × shaped`（`t=0` 刚出死区→精瞄端、`t=1` 推到底→甩枪端）。
- `_update_aim()` 的平滑率改为 `AIM_SMOOTHING_BASE_RATE × (1 − smoothing) × speed_scale`：**轻推慢转（精瞄）、重推快转（甩枪）**，把此前被丢弃的摇杆幅度重新纳入。
- 默认值再平衡（`InputSettingsManager.DEFAULT_SETTINGS`）：`gamepad_aim_deadzone 0.20 → 0.12`、`gamepad_aim_smoothing 0.35 → 0.15`（对应 `rate = 30 × 0.85 = 25.5`，滞后从 ≈60ms 降到 ≈40ms）。

**改动 ②｜瞄准辅助（磁吸，顶视角射击事实标准）**（新文件 `src/player3d/AimAssist3D.gd`，`class_name AimAssist3D`，`extends RefCounted` 纯静态）：
- `is_eligible(alive, illumination_state, distance, angle_deg, ...)`：**只吸附「存活 + 已照亮（非 `STATE_DARKNESS`）+ 射程内 + 锥内」**的敌人。硬约束：**绝不吸附黑暗中的敌人**（本项目敌人只在光照下可见，吸黑暗 = 透视挂）；已死、超射程（默认 26m）、锥外（默认 30° 扫描锥）一律不吸。
- `solve(aim_dir, candidates, options)`：取锥内**权重最大**的候选，`delta = clampf(angle_to, ±max_angle(默认 8°) × strength × weight)` —— **偏转有硬上限（不抢控制）**；无候选 / 强度 0 / 候选为空时原样返回，绝非「无脑吸附」。
- 权重 `_weight(...)` = `angle_factor² × distance_factor`（角度项取平方 ⇒ 偏好贴近瞄准轴的近敌）。
- `Player3D._collect_aim_assist_candidates()` 从 `enemy_3d` 分组收集候选（读 `current_hp` 与 `get_illumination_state()`），在 `_update_aim_from_mouse()` 的**移动端/手柄共用分支**对 `aim_dir_3d` 施加 `AimAssist3D.solve(...)` 后再赋给 `aim_direction`。

**开关与 UI**：新增 `InputSettings` 键 `gamepad_aim_assist`（**默认 `true`**）+ `is_aim_assist_enabled()`；ESC 暂停菜单「操作设置」页新增「瞄准辅助」`CheckButton`（节点 `Center/Panel/Margin/ControlsPage/AimAssist`）+ `PauseMenu3D._on_aim_assist_toggled()` 与同步（`L3B_IND` 类状态标签）。

**验收**（`verify_gamepad_input_flow`）：
- `_verify_aim_response_curve()`：精瞄端/甩枪端端点值、单调不减、中段必须「够慢」（低于线性中线）、越界与负值钳位。
- `_verify_aim_assist_solver()`：资格 5 条规则 + `solve` 空操作（无候选/强度 0/空数组）+ 锥外不吸 + 锥内偏转**有硬上限且非满偏** + 权重优先 + 距离衰减。
- `_verify_aim_assist_candidate_collection()`：**端到端**（真实 `Player3D` + `Enemy3D` 竞技场）A) 黑暗敌人 → 空候选；B) 太阳照亮 → 恰 1 候选、方向与距离(8.0m)正确；C) 关开关 → 空；D) 敌人在背后 → 空；E) 超射程(z=−40) → 空；F) 已死 → 空。
- **坑（新）**：`DirectionalLight3D` 默认朝 **−Z**，水平摆放时阳光射线从敌人射向太阳会被原点处的玩家挡住 ⇒ `sun_exposure_ratio` 恒 `0.0`、敌人一直停留黑暗态；**必须把太阳转成 `rotation_degrees=(−90,0,0)` 顶照**，才能造出「已照亮」样本。
- **反向对照 4 组**（`_scratch/gamepad_submenu/negctl_assist.py`）：`curve`（曲线失效）⇒ 5 红、`dark`（放行黑暗敌人）⇒ 1 红（「黑暗中的敌人进入了瞄准辅助候选」）、`cap`（去偏转上限）⇒ 2 红、`glue`（撤 `Player3D` 接线）⇒ 1 红；各自精准命中后还原复绿。
- 复绿：`GAMEPAD_INPUT_FLOW_OK`（`exit=0`）含新 OK 串「magnitude-authoritative aim response curve (slow precision / fast flick), aim assist pulls only lit living enemies within a hard deflection cap」。

**回归**：`verify_graphics_settings_ui_flow` / `verify_pause_game_save_reset_flow` / `verify_enemy_illumination_states` 三场景 `exit=0` + `*_OK`。**基线对照**：`verify_3d_enemy_behavior_flow` 报 7 条「Enemy damage does not create a 3D floating number」——把本次 5 个改动文件临时换成 `HEAD` 版重跑，**7 条错误逐字相同** ⇒ **既存红、非本次引入**（已记入已知基线红，非本特性回归）。

**未变更**：`aim_direction` 三用语义、`MobileInput` 触屏口径、键鼠路径、三档朝向机制与 `gamepad_left_stick_aim` 默认关、武器/弹药/伤害链路、账本。

<br>
## 2026-09-22｜「左摇杆同控朝向」改为默认关闭（保留能力）

**动机（业主实测反馈）**：「还是操控不是很舒服，不要这个设计，或者先保留，默认关掉。」并指出**原始右摇杆瞄准本身「转向不够精确、无法瞄准」**，要求参考顶视角游戏的右摇杆做法另给方案。

**改动（单点默认值，不撤功能）**：
- `InputSettingsManager.DEFAULT_SETTINGS["gamepad_left_stick_aim"]`：`true → false`；`is_left_stick_aim_enabled()` 的回落值同步 `true → false`。
- `PauseMenu3D._sync_input_controls()` 的读取回落值同步 `true → false`。
- `ui_pause_overlay_screen.tscn` 的 `LeftStickAim` 文案补「默认关闭。」
- 三档朝向机制（`FACE_SOURCE_AIM / MOVE / HOLD` + 死区滞回 + 平滑交接）**代码原样保留**，ESC 操作设置页开关仍在，需要时可自行打开。

**验收适配**：`verify_gamepad_input_flow` 原断言「开关初始 `button_pressed == true`」改为**同步断言**（`button_pressed != is_left_stick_aim_enabled()` 即红，与默认值解耦）+ 新增**设计锁**：断言 `DEFAULT_SETTINGS["gamepad_left_stick_aim"] == false`（打在外部真源上、不引用被测函数）。OK 串补 `(left-stick tier default OFF)`。

**反向对照**：默认值临时改回 `true` ⇒ **精准 1 红**（`「左摇杆同控朝向」的出厂默认不是关闭（业主指定默认关）`）、`exit=1`，其余断言全绿；还原后复绿。

**复绿**：`GAMEPAD_INPUT_FLOW_OK` / `GRAPHICS_SETTINGS_UI_OK` / `PAUSE_GAME_SAVE_RESET_OK`，三场景 `exit=0`、无新增红。

**后续（同日已施工）**：右摇杆瞄准手感（"转向不够精确、无法瞄准"）**已按业主选定方案落地**（瞄准辅助 + 响应曲线，见本文顶部「右摇杆瞄准手感重做」条目）。施工前勘察的现状：`gamepad_aim_deadzone = 0.20`、`gamepad_aim_smoothing = 0.35`（≈60ms 滞后），且 `_update_aim()` **只取摇杆方向角、丢弃幅度**（无响应曲线）；`aim_direction` 三用（面朝向 + 弹道 + 准星）使瞄准精度直接等于命中精度。

<br>
## 2026-09-22｜手柄左摇杆同控面朝向（三档优先级 + ESC 开关）

**动机（业主指定）**：「如果左摇杆在控制移动方向的时候，同时控制角色面朝向，然后右摇杆在动的时候面朝向才会优先右摇杆，这样会不会体验更好一些？」—— 勘察确认这不是新机制，而是**把手柄对齐触屏**：触屏 `MobileInput._emit_face_direction()` 早已是「右摇杆优先，否则左摇杆」；手柄此前只有两档（右摇杆 / 保持上次），**没有第二档**。

**关键事实链**：`GamepadInput` 的「瞄准」意图同时是**面朝向 + 弹道方向 + 准星位置**（`aim_direction` 三用）⇒ 改朝向 = 改弹道，落点只有 `_update_aim()` 一处。手柄**永不发零**（回中直接 `return` 保持上次），这是为**避免 `Player3D` 回落到鼠标射线导致准星瞬跳**、不是玩法选择 ⇒ 副作用是**纯手柄玩家若从未推过右摇杆，其朝向实际来自鼠标射线**（`_mobile_face_active` 恒 `false`），本次一并修掉。

**改动（三档朝向优先级）**：`src/core/GamepadInput.gd` 新增 `FACE_SOURCE_AIM` / `FACE_SOURCE_MOVE` / `FACE_SOURCE_HOLD` 三档与纯函数 `resolve_face_source(...)`：右摇杆跨过瞄准死区即抢回（`AIM`）> 左摇杆跨过移动死区且开关开启时接管（`MOVE`）> 否则保持上次（`HOLD`，**永不发零**）。两处守卫：① **死区 + 滞回**，升级需跨过该摇杆死区、降级需回落到 `死区 × STICK_HYSTERESIS_FACTOR(0.7)` 以下，防止摇杆停在死区边界时来回抢档抖动；② **档位交接复用现有 aim 平滑**（`AIM_SMOOTHING_BASE_RATE`），松开右摇杆切到左摇杆那一帧不瞬间转正（防甩枪）。另加测试注入口 `set_test_stick_axes()` 与只读访问器 `get_face_source()` / `get_face_direction()` / `is_aim_active()`。

**开关**：新增 `InputSettings` 键 `gamepad_left_stick_aim`（~~**默认 `true`**~~ **同日改为默认 `false`**，见本文上方「改为默认关闭」条目），可在 ESC 暂停菜单「操作设置」页的「左摇杆同控朝向」`CheckButton`（节点 `Center/Panel/Margin/ControlsPage/LeftStickAim`）切换；`PauseMenu3D` 增加 `_on_left_stick_aim_toggled()` 与同步。

**验证**：`verify_gamepad_input_flow` 增 `_verify_face_source_tiers()`（纯函数：右优先于左、左接管的边界、开关关闭不返回 `MOVE`、双中位 → `HOLD`、滞回不回弹、升/降档单次跃变与滞回宽度）与 `_verify_left_stick_face_flow()`（端到端按 `1/60 s` 步进 `_update_aim`：A 右摇杆抢朝向首帧不跳；B 松右推左 → `MOVE` 档首帧角度变化 `>0` 且 `≤45°`、60 帧收敛到 +y；C 右摇杆 `0.19↔0.21` 抖动仍锁 `AIM`；D 关开关 → `HOLD`、朝向不变、不发广播；E 纯手柄新手只推左摇杆即激活 `is_aim_active()`；F `_release_all()` 复位到 `HOLD`），含 `[samples]` 行与**截断哨兵**（`frames≥80` / `checks≥15`，防 SCRIPT ERROR 静默截断假绿）。**反向对照三组**（`_scratch/gamepad_submenu/negctl_face.py`）：`tier`（左档失效）⇒ 5 红、`hyster`（滞回置 1.0）⇒ 5 红 + 哨兵报「74 帧」、`smooth`（交接瞬转）⇒ 1 红（「一帧内跳了 90.0°」），各自精准命中后还原复绿。复绿：`GAMEPAD_INPUT_FLOW_OK`（`[samples] 85 帧 / 断言 15 条`）。**回归**：`verify_graphics_settings_ui_flow` / `verify_pause_game_save_reset_flow`（两者都实例化暂停界面、会走 `_ready → _setup_input_controls → _sync_input_controls` 读新节点）均 `exit=0` 且 `*_OK`，无新增红。

**未变更**：`aim_direction` 三用语义、`MobileInput` 触屏口径、键鼠路径、右摇杆死区/平滑既有取值、`Player3D` 的鼠标射线回落机制与 `default` 行走逻辑均未动。文档：本文 + `03_技术施工_玩家与操作.md` §3 输入动作契约表（「瞄准」→「瞄准/面朝向」，输入列补左摇杆）+ 表后新增已实装说明。

<br>
## 2026-09-22｜弹壳停留时长 +1.5 秒（3.2s → 4.7s）

**动机（业主指定）**：「弹壳的停留时长加 1.5 秒。」

**口径**：弹壳可见时长 = `VfxShellCasing3D.DEFAULT_LIFETIME`。其中飞行 / 弹跳 / 滚动三段的时长由物理常量与初速度决定、**不随寿命变化** ⇒ 寿命增加的部分**全部落在「落地静止后的停留」上**，故本诉求等价于「寿命 `3.2 → 4.7`」。实测（验收按 `1/60 s` 步进求静止时刻）：`t_settle = 1.15 s`、停留 `4.70 − 1.15 = 3.55 s`（上一版 `3.20 − 1.15 = 2.05 s`）。

**改动（单点）**：
- `src/vfx/VfxShellCasing3D.gd`：`DEFAULT_LIFETIME := 3.2 → 4.7`。
- `tests/verification/verify_combat_vfx_toon_v002.gd`：新增 `_check_shell_settled_hold()`（`samples=15 → 16`）与三个外部真源常量 `EXPECTED_SHELL_LIFETIME_PREVIOUS := 3.2` / `EXPECTED_SHELL_SETTLED_HOLD_DELTA := 1.5` / `EXPECTED_SHELL_LIFETIME := 4.7`（**刻意各自硬编码、不写成派生式** `3.2 + 1.5` —— 派生式会让改坏一处时三处一起跟随，断言自我印证）。

**三条互补断言**：① 寿命 = 定档值（外部真源硬编码，不引用被测常量）；② 增量 = 上一版 `3.2` + `1.5`（**业主诉求本身**的常量级钉子）；③ 行为级 —— 实测静止时刻后剩余停留 `≥ 1.5 s`（挡住「有人把初速度调大到飞行段吃掉这 1.5 s」这类隐形退化：那时 ①② 仍绿、只有 ③ 会红）。用例强制使用**新实例**（主用例那枚已被推进到 `1.94 s` 且早已 `SETTLED`，复用会让 `t_settle` 恒取第一个步长而失效），并带「未测到静止时刻」的防假绿哨兵。

**反向对照 RC8**：`DEFAULT_LIFETIME` 退回 `3.2` ⇒ **精准 3 红**（`弹壳寿命不是定档值 4.70：3.200`、`弹壳实例寿命未按 DEFAULT_LIFETIME 初始化：3.200（检查 _ready）`、`弹壳停留增量不是 1.5s：寿命 3.20 − 上一版 3.20 = 0.00`），其余断言全绿、`EXIT=1`；还原后 `EXIT=0` 复绿。**如实说明**：③ 在退回 `3.2` 时仍为真（`hold = 2.05 ≥ 1.5`）—— 它是**下限守卫**，「+1.5」这条诉求由 ①② 钉住，不是 ③。

**成本（如实核算，未做池化改动）**：`VfxPool3D` 对 **active 实例无上限**（`max_per_kind = 32` 只管 **inactive 回收桶**，见 `VfxPool3D.retire()`）⇒ 拉长寿命直接抬高同屏存活弹壳数：射速 `1.0 ~ 12.0 发/s`（`BlueprintRegistry` 全体枪械）× `4.7 s` ⇒ 最坏同屏约 `56` 枚（上一版约 `38` 枚，`+47%`）。每枚 `3` 个 `MeshInstance3D`、`288` 三角面（圆柱 `48` + 圆环 `192` + 球 `48`）⇒ 约 `16k` 三角面、约 `170` 次绘制，远低于预算。

**未变更**：AssetID `VFX-SHELL-CASING-3D`、Prefab 路径与根节点版本 `v001`、PBR 定档（`0.8 / 0.6`）、尺寸基准（`0.8`）、抛壳随机化幅度、`floor_y` 契约与「不接物理引擎」口径均未动 ⇒ **账本无需改动**。真渲染探针四个机位沿用不动（其步进按**绝对秒数**驱动、寿命经 `shell.lifetime` 动态读取，寿命变化不影响取景与判据）。

<br>
## 2026-09-22｜保底武装配套备弹 60 发 → 300 发

**动机（业主指定）**：游戏内保底装备的备弹从 60 发改成 300 发。

**改动**（沿用既有单一真源，未新增分支）：
- `src/world3d/Dungeon3D.gd`：`GUARANTEED_LOADOUT_AMMO_ROUNDS := 60 → 300`。发放链路 `_grant_guaranteed_loadout_ammo()` 与 `get_guaranteed_loadout_ammo_rounds()`（内容数值唯一出口）均未改动，只换常量值。
- `tests/verification/verify_guaranteed_loadout_ammo_flow.gd`：设计值哨兵 `expected_rounds != 60` → `!= 300`。

**占格影响**：`item_ammo_pack` 的 `stack_max = 999`、每堆叠单位 = 1 发真实备弹 ⇒ 300 发仍落在 1 格内，背包容量（`BASE_INVENTORY_CAPACITY = 12`）与堆叠口径均不变；换弹按弹匣缺口消耗的逻辑、HUD 备弹串格式（`%d备弹`）也不变。

**验证**：`verify_guaranteed_loadout_ammo_flow` 判据 `GUARANTEED_LOADOUT_AMMO_OK`（`test_mode = false` + 隔离存档跑真实发放路径）：真实入场主背包恰好 300 发且与 `_get_reserve_ammo_count()` 口径一致、HUD 真串含 `300备弹`、留 10 发缺口换弹后弹匣满且备弹精确扣到 290、`restore_slots_snapshot()` 后备弹等于存档值（证明入场发放不叠加）。**反向对照**：常量临时改回 60 ⇒ 该哨兵单点判红（`保底备弹发数变成 60，与设计输入 300 不一致`，且仅此一条），还原后复绿。

**未变更**：发放时机（`_setup_run_modules()` 内 `not test_mode` 边界）、与白送手枪共用的「每次装配场景」生命周期、`docs/v0.1/04_技术施工_战斗与局内成长.md` §6.6 记录的待裁决项（远征逐层逐次补发；98F 反向撤退不补）均未改变。**注意**：逐层补发的量级随本次调整放大 5 倍，该待裁决项的影响面需在下一次数值冻结前一并复核（已在 §6.6 就地标注）。

<br>
## 2026-09-22｜弹壳抛壳逐发随机化（方向 / 高度 / 前送 / 自旋 / 初始姿态）

**动机（业主指定）**：「飞出去的弹壳，方向，高度，初始旋转位置，落地后的范围，旋转，等数值都需要做一个随机。不然太整齐了。」—— 上一版弹壳的抛出量全为固定常量，连发时 8 枚弹壳沿一条齐整弧线排开（视觉证据：真渲染探针把同一条摆头轨迹下的落点连起来，**离最佳拟合线的最大垂直偏差仅 0.0114 m**）。

**随机化落点在调用方，不在特效脚本**。`VfxShellCasing3D` 保持**确定性**：给定同一 `context` 逐位可复现，`_on_activate` / `_on_tick` 内**不出现任何 `randf()`**。理由是它被逐帧断言驱动（`verify_combat_vfx_toon_v002` 与真渲染探针都手动步进到固定时刻再断言姿态与高度），一旦把随机数埋进特效脚本，这些断言会全部漂成随机红。逐发随机的职责交给 `WeaponModel3D._spawn_shell_casing`。

**施加口径**（全部按**枪械局部基** `right/up/forward`，与枪当前朝向无关；基准速度沿用上一版的固定值，即只把「点」摊成「一团」，手感中心不变）：

| 量 | 口径 | 幅度 |
|---|---|---|
| 右向速度 | `SHELL_EJECT_RIGHT_SPEED × randf_range(1−s, 1+s)` | `2.1 ±35%` |
| 抬升速度 | `SHELL_EJECT_UP_SPEED × randf_range(1−s, 1+s)` | `1.55 ±45%` |
| 前送速度 | `SHELL_EJECT_FORWARD_JITTER × randf_range(−1, 1)` | `±0.30`（绝对值抖动，可为负 ⇒ 也会落在枪身后方） |
| 自旋轴 | `(right + up × r(0.1,0.9) + forward × r(−0.4,0.4)).normalized()` | — |
| 自旋速度 | `SHELL_EJECT_SPIN_SPEED × randf_range(1−s, 1+s)` | `20 ±50%` |
| 初始姿态 | 绕**随机单位轴**旋转 `randf_range(−1,1) × SHELL_INITIAL_TILT_DEG` | `±45°` |

**落地散布推算**：重力 `9.8`、两次弹跳后切向速度乘 `GROUND_FRICTION² = 0.42²` ⇒ 滚动段位移可忽略 ⇒ 水平初速 `∈ [1.37, 2.84] m/s`，首次触地前约 `0.6 s` ⇒ 落点离枪 `0.9 ~ 2.5 m`、散布带约 `1.6 m`。实机量测（探针跑真实调用方路径）：8 发落点最大间距 `0.45 ~ 1.15 m`（逐批不同）、离最佳拟合线偏差 `0.37 ~ 0.45 m`。

**硬约束**：`SHELL_EJECT_RIGHT_SPREAD` 有上限 `0.523` —— 验收断言「每发弹壳仍从枪械右侧抛出」= 右向速度 `> 1.0 m/s`，即 `2.1 × (1 − s) > 1.0`。取 `0.35` 留 `0.35 m/s` 余量。**出生点仍精确取抛壳挂点**，扰动只作用于抛出之后的运动量（验收对出生点漂移的容差是 `0.001 m`）。

**契约扩展**：`VfxShellCasing3D` 新增 `context.initial_basis`（可选，缺省恒等）承接调用方传入的随机初始倾斜，写入前 `orthonormalized()`（根 basis 非正交会让旋转赋值报 `must be normalized in order to be casted to a Quaternion`）；`get_presentation_snapshot()` 增补自旋真值 `spin_axis` / `spin_speed` 与出生姿态 `spawn_basis` 供验收读取。

**验收扩展**（`verify_combat_vfx_toon_v002`，`samples=14 → 15`）：新增 `_check_shell_ejection_randomized` —— 走**真实调用方**路径连打 **24 发**（枪先偏航 `0.5 rad` 并搬到非原点，验证扰动确实施加在枪械局部基上），统计各分量极差与初始倾角峰值，并在最后做**反向对照**：显式 `context` 的速度 / 自旋 / 姿态必须与传入值**逐位相同**，证明随机化没有污染确定路径。真渲染探针新增第 4 机位 `shell_casing_spread.png`：连发 8 发（复刻业主截图里的后坐摆头 `±6°`）走真实调用方路径后俯视落点，判据 = 「落点离最远两点连线的最大垂直偏差」`> 0.10 m`；同批次 A/B 出图 `shell_casing_spread_ab.png` 供前后对比。

**反向对照**（全部精准变红后还原，`grep REVERSE-CONTROL src/ tests/` 为空）：RC7a 五个幅度常量清零 → 7 项统计断言 + 5 项常量断言全红（`24 发里只有 1 个不同速度`）；RC7b 掐断 `VfxShellCasing3D` 对 `context.initial_basis` 的采用 → 「初始倾角峰值 0.00° 不足 22.50°」单点命中；RC7c 探针侧关掉随机化重出散布图 → `off_line_residual=0.0114 m` 判据红。复绿：`COMBAT_VFX_TOON_V002_OK samples=15`、`VFX_POOL_LIFECYCLE_OK`、`SHELL_CASING_VISUAL_OK captured=4`，武器回归三条（`verify_dual_weapon_quick_map_fate_flow` / `verify_3d_inventory_weapon_flow` / `verify_unified_player_interaction_flow`）全绿。

**未变更**：AssetID `VFX-SHELL-CASING-3D`、Prefab 路径、版本号 `v001`、PBR 定档（`0.8 / 0.6`）与尺寸基准（`0.8`）均未动，**账本无需改动**。

<br>
## 2026-09-22｜弹壳改为纯程序化模拟碰撞 + 缩到 80%，并修复「弹壳特效消失」

**行为改造（业主指定：不要真实物理碰撞）**：`VfxShellCasing3D` 原先「优先物理射线打地板（collision layer 1）+ `context.floor_y` 兜底」的落地方案**整体作废**，改为**纯解析式越线判定** —— 弹壳中心 y 越过「地面高度 + 贴地半径」即视为碰撞。Prefab 无碰撞体、脚本内不出现任何物理查询 API（`intersect_ray` / `direct_space_state` / `RigidBody3D` …）。运动改为三阶段有限状态机 `FLYING → ROLLING → SETTLED`：抛物飞行与弹跳（恢复系数 `0.32`、地面摩擦 `0.42`、自旋保留 `0.68`、最多 2 次弹跳）→ 贴地指数衰减滚动（`v(t)=v₀·e^(−3.4t)`）→ `smoothstep` 过渡到长轴躺平；触地带 squash & stretch 挤压包络（压到 `0.72`、`0.14 s` 回弹）。手感参数全部收敛为脚本顶部一组常量。

**尺寸缩到原基准 80%**：`WeaponModel3D.SHELL_CASING_SIZE = 0.8`。

**修复实机缺陷「弹壳特效没了」（P0）**：`_spawn_shell_casing()` 把 `floor_y` 硬编码为 `0.0`。塔楼楼层是**向下**建造的（`stage.position.y = -FLOOR_HEIGHT_M(12.0) × floor_index`，98F ≈ **−1176 m**），于是弹壳出生点 y 就已「低于地面」，**第一帧即判定触地**、被夹到 `floor_y + 半径 ≈ 0.046` ⇒ 瞬移到世界原点附近、离玩家一千多米 ⇒ 实机完全看不见。改为由新增的 `WeaponModel3D._resolve_shell_floor_y(shooter)` 取**射击者站立面**世界 y（玩家胶囊底面恰在 `y=0`，原点即脚底行走面；射击者失效时回落枪自身 y，**不以 0 作通用兜底**）。`_spawn_shell_casing` 签名由 `(world: Node)` 改为 `(shooter: Node3D)` 以携带该信息。

**同时修正两处几何缺陷**（均由真渲染探针实测抓出，headless 数值全绿时掩盖）：① 贴地半径原取壳体 `0.045`，但躺平后触地的是**底缘** `TorusMesh.outer_radius = 0.058` ⇒ 弹壳整圈陷进地板 1.3 cm；改为常量 `0.058` 并支持 `_measure_radial_half_extent()` 运行时从已挂载 mesh 实测。② 0.8 尺寸下三件装配**裂开**：缩放原只作用子节点 `scale` 而漏掉其 `position`（底缘/底火仍停在 ±0.12）；改为**缩放三件子节点并同步缩放其偏移**，根节点保持纯旋转（不可缩放根节点 —— 根 basis 非正交会让旋转赋值报 `must be normalized in order to be casted to a Quaternion`）。

**验收扩展**（`verify_combat_vfx_toon_v002`，`samples=14`）：新增源码级**物理 API 静态门禁**（13 个禁用符号，行为层无法区分射线命中与解析越线，只有查源码看得住）、**逐帧最低点防穿地**（`min_y >= radius`，专防「终态贴地掩盖中间穿地」的假绿）、触地次数、装配随尺寸缩放、根节点恒单位缩放、**弹壳必须出生在枪械抛壳挂点上**、以及**非零楼层端到端**（把枪与射击者一起搬到 98F 开火，断言弹壳留在该层、精确贴该层地面、绝不出现于世界原点附近）。反向对照 RC1–RC6c 全部精准变红后还原，`grep REVERSE-CONTROL src/ tests/` 为空。新增真渲染探针 `probe_shell_casing_visual` 三个机位：阶段切片、0.8/1.0 尺寸同框（投影比 `0.7981`）、**深层楼 98F 贴地**（`gap_m=0.0000`）。

文档与台账：`docs/v0.1/14.6_特效系统与制作规范.md` §10 版本历史新增 v002.4 / v002.5；账本**未变更**（AssetID、Prefab 路径、版本号与 PBR 定档值均未变，仅行为与尺寸常量调整）。

<br>
## 2026-09-22｜新开枪反馈：弹壳抛出并落地（VFX-SHELL-CASING-3D），材质定档 金属度 0.8 / 反光度 0.6

`WeaponModel3D._fire_now()` 每次成功开火新增生成 **1 枚弹壳**（命运复制波次与霰弹多弹丸不额外重复抛壳）。弹壳脱离武器挂点进入世界空间：初速度 `v = 2.1·right + 1.55·up + 0.22·forward`（从枪械右侧抛出），受 `g = 9.8 m/s²` 下落，命中地板后**最多 2 次小弹跳**再静止，`lifetime 3.2 s` 回池；落地判定优先走物理射线（collision layer 1），无场景碰撞时用 `context.floor_y` 兜底以避免穿地。出生点取枪械 `EjectionSocket`，缺失时回落 `TacticalSocket`；近战武器不抛壳。

新增独立 Prefab `assets/art/vfx/combat_3d/vfx_shell_casing_root_top3d.tscn`（AssetID `VFX-SHELL-CASING-3D`，v001，黄铜圆柱 + 底缘环 + 底火，**纯视觉无碰撞体**）与脚本 `src/vfx/VfxShellCasing3D.gd`，注册为 `VfxPool3D.FX01_SHELL_CASING`（按 AssetID 路由，调用方禁裸字符串）。

**材质定档（业主指定）**：金属度 `metallic = 0.8`、反光度（roughness 通道）`= 0.6`，壳体 / 底缘 / 底火**三件统一**，各件仅保留基色差异；原先三件各自的分散数值收敛为单一常量组 `VfxShellCasing3D.SHELL_METALLIC` / `SHELL_ROUGHNESS`。

验收 `verify_combat_vfx_toon_v002`（`samples=12`）新增弹壳用例（AssetID/版本、主体 mesh、重力、右侧飞出、不穿地、最大弹跳、无碰撞体、真实开火接线）与 **PBR 真值断言**（读已挂载材质，期望值硬编码在验收侧以防止「期望引用被测常量」的自印证）；两轮反向对照均精准命中后还原：右向初速度归零 → 红（实测 0.000 m/s），PBR 改 0.5/0.2 → 红（实测 0.500/0.200）；`verify_vfx_pool_lifecycle` 同步复绿，两者 headless 退出码 0。

文档与台账：`docs/v0.1/14.6_特效系统与制作规范.md` §6.1 迁移表 + §10 版本历史 v002.2 / v002.3；`docs/v0.1/MODULE_INDEX.md` 的 `VFX-POOL` 行补弹壳与 PBR 口径；账本 `ShellStorm2_特效账本_v001.xlsx` 登记 `资产主表` row 22、`3D-特效` FX01-07、`域变更日志` v0.1.3 / v0.1.4，门禁 `check_asset_registry.py --ledger vfx` 无新增红项。

<br>
## 2026-09-22｜子弹默认最大存活时间 5 秒 → 1 秒

`src/combat3d/Projectile3D.gd`（`_physics_process`）：投射物超时回收的默认寿命由 `maxf(5.0, home_lifetime, 默认5.0)` 下调为 **1.0 秒**（`maxf(1.0, …, 默认1.0)`；同日先落到 1.5 秒，经实机手感复核后定为 1.0 秒）。按出厂弹速 23 m/s 计算，理论最大飞行距离由 ≈115 m 降为 **≈23 m**；室内场景实际有效射程仍由撞墙决定，变化主要影响开阔场景（天台、大房）的流弹残留时间与对象池回收节奏。命运卡注入的 `home_lifetime`（追踪弹等，预设值 5 秒）不受影响，`maxf` 下限语义保证只增不减。设计文档同步：`docs/v0.1/04_技术施工_战斗与局内成长.md` §11 开火流程新增「投射物生命周期」段落。验证脚本无任何对旧值 5.0 的断言（`tests/` 全文检索 0 命中），无门禁受影响。

<br>

## 2026-09-21｜五次修正 100F 天台装饰：绿化环背贴建筑外皮 + 天台不再生成室内照明设施

业主实机反馈两条：「花盆和花圃靠墙太远了，要挨着墙放，不然还有个空虚」「天台为什么还会刷一个电灯开关？帮我去掉」。**原地修正**（AssetID / layout_id / layout_version 不变）：

1. **绿化环贴墙**（`author_rooftop_decorated_layout_v001.py`）：旧版把整圈绿化压在**同一条「离墙中心线 2.15m」的环线**上（离外皮 2.00m），而三件绿化陈设的半进深只有 0.55~0.87m ⇒ 每件背后空出 **1.14~1.45m 的可见地砖带**（对比同墙空调是贴墙的，视觉上就是「悬空一截」）。现改为**逐件按自身半进深贴外皮**：件心到墙中心线 = `SHELL_WALL_T/2 − WALL_MOUNT_EMBED + half_depth`，即背面埋进外皮内 0.05m（与墙挂空调同口径，避免与墙皮共面 z-fighting）。三件进深不等 ⇒ **背面一条线齐平、正面自然错落**。新增 `wall_flush_pairs(half_depth)` 一处算四边，南/北/东/西各成对。
2. **朝向补齐**：三件 catalog 的 `front_direction` 均为 `−Y`，yaw 取 0 / π / +π/2 / −π/2 分别朝南 / 北 / 东 / 西。旧版**西侧花圃写成 +π/2（正面朝墙里）**，与同墙藤蔓的 −π/2 自相矛盾，一并修正。
3. **天台不再生成室内照明设施**（`DungeonRoom3D._build_content()`）：此前「清空屋顶设施」只把 `prop_count` 归零（清家具与可搜容器），**漏了照明** —— 露天甲板上仍会生成一盏玩法顶灯 `RoomCeilingLight` 与一个墙边**电灯开关** `RoomLightSwitch3D`（实测位于 `(-29.66, 0.0, 6.7)`）。天台自带室外光照（`TowerAtmosphere3D` 的天光反弹 `_rooftop_sky_bounce` + 太阳 + 城市背景），两者都是室内残留 ⇒ `size_class == "rooftop"` 时**顶灯与开关一并跳过**（`_room_lights` 留空、`_central_light` 保持 null、开关节点不实例化）。下游读取点全部已做保护：`get_debug_snapshot()` 的两个布尔位、`_apply_light_state()`、`_bind_facility_presentation_light_control()`、`_bind_light_switch_signal()`（后两者本就 `null` 早退）。

**重放实例数不变**：仍 **120 / 6 组**（空调与通风口 6 + 绿化 20 + 墙面藤蔓 16 + 女儿墙挂藤 8 + 水管 54 + 立管与支架 16），构件计数与 `blocking` 20 件全部不变 —— 本批只动**平面位置与生成条件**，不动数量。

验收与防再犯：布局 QA（`validate_rooftop_decorated_layout_v001.py`）新增**第 3e 组断言「绿化背贴外皮」** —— 按 depsgraph 实测包络判①沿墙法线跨度必须 = 2 × 半进深（顺带验证朝向没把长边转到法线上）、②背面埋进外皮量必须 = 0.05、③件心离外皮必须 = 半进深 − 0.05，并按 slug 清点件数（8/6/6）。**可反向对照**：把 `wall_flush_pairs` 换回「+2.15 环线」本组立刻变红。开关侧新建只读探针 `tests/verification/probe_rooftop_no_program_fixtures.{gd,tscn}` —— **改前实测为红**（`ROOFTOP_NO_PROGRAM_FIXTURES_FAIL rooftops=1 light=1 switch=1 furniture=0`，并打印开关样本路径与坐标），改后转绿（`..._OK rooftops=1 light=0 switch=0 furniture=0`）；探针自带**样本数哨兵**（必须找到 ≥1 个 rooftop 房间，否则判失效）。

门禁（全部实测、0 ERROR）：布局作者脚本 `ROOFTOP_DECOR_LAYOUT_V001_OK instances=482`；布局 QA `ROOFTOP_DECOR_LAYOUT_QA_OK instances=482 collection_instances=482 mesh_owned=0 godot_rect_violations=0 grounded={...} door_blocks=0 ivy_top_span=3.60m wall_mount_tipped=4 riser_runs=4 riser_bottom=0.000 riser_top=9.890 blocking=20 visual_only=462`；运行时 `probe_rooftop_decorated_stage_only`（`..._OK instances=120 blocking=20 visual_collisions=0`）、`probe_rooftop_decorated_layout`（`ROOFTOP_DECORATED_LAYOUT_RUNTIME_OK instances=120 groups=6 blocking=20 visual_collisions=0`）、`verify_rooftop_32x32_contract`（`ROOFTOP_WEST_EXPANSION_CONTRACT_PASS`）、`probe_rooftop_no_program_fixtures`（`..._OK`）。

账本（`assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx`）：《资产主表》row 240 同步重生成后的 `.blend` SHA-256 `de1d7ce6… → 7e8b2c51…` 并在备注列追加本批说明；《3D-场景通用》row 146 说明列追加贴墙口径，并把 11 行组件备注里**陈旧的「接入 100F 装饰布局＝99实例/7组/0启用碰撞」**修正为「120实例/6组（绿化20件blocking，其余visual_only）」；《域变更日志》追加 **v0.1.9**。`check_asset_registry --ledger scenes` **47 → 46（0 新增问题，顺手消掉 1 条陈旧 SHA 告警）**，`verify_ledger_split` 16 → 16（改前快照复跑对照，本批零增减）。旧账本留档 `ShellStorm2_场景账本_v001.xlsx.bak_rooftop_decor_greenery_flush`。

视觉取证：`outputs/rooftop_100f_decorated_layout_v001_{overview,closeup,top}.png` 重出，特写可直接看到花箱背贴墙皮、背后不再有空地砖带。

<br>

## 2026-09-21｜四次修正 100F 天台装饰：花盆 / 花圃加上物理阻挡（可挡住玩家）

业主实机反馈：「花盆和花圃没有阻挡」—— 走在天台上可以直接穿过长条花箱与大/小盆栽。根因：装饰布局的**所有**实例都被 `TowerFloorStage3D` 无条件关掉碰撞（原始设计是纯视觉装饰），而 `flowerbox / plant_large / plant_small` 三件 prefab 是**纯可视件**（`visual_only=true`、不带碰撞节点）⇒ 482 件装饰**全局零碰撞**，绿化自然拦不住人。

**修法：给布局源加「实例级碰撞策略」，只让绿化 20 件 `blocking`**（原地修正，AssetID / layout_id / layout_version 不变）：

1. **布局源**（`author_rooftop_decorated_layout_v001.py`）：`add()` 新增 `collision` 参数（默认 `visual_only`），词表 `{visual_only, blocking}` 并硬断言白名单；绿化 6 处调用点（8 花箱 + 6 大盆栽 + 6 小盆栽）传 `blocking`。导出时写 `scene.collision_policy = "per_instance:visual_only(default)+blocking(greenery)"`，`design_intent` / `validation` 记 `blocking_collision_count=20` / `visual_only_collision_count=462`，并自检声明白名单 == 实际 blocking slug。
2. **运行时**（`TowerFloorStage3D.gd`）：新增 `_apply_rooftop_collision_policy(instance, slug, policy)` —— 不论策略**先关**组件自带碰撞（沿用旧行为），`blocking` 时用 **`TowerGeometry3D.resolve_visual_bounds()`** 量出该实例的**实测可视包络**，挂一个 `StaticBody3D`（名 `BlockingCollision`，`collision_layer=1`、`mask=0`、`PROCESS_MODE_ALWAYS`）+ 子 `CollisionShape3D`（`BoxShape3D`，尺寸 = 包络 size、位置 = 包络中心）。**碰撞盒尺寸随美术走、不写死常量**；`mask=0` 是因为玩家（`scenes/Player3D.tscn`，`layer=1/mask=1`）需要「撞得到」它，它自己不需要检测别人。未知策略值 → `push_error` 并跳过。候选根 meta 增 `collision_policy=per_instance` / `blocking_collision_count`。
3. **校验器**（`validate_rooftop_decorated_layout_v001.py`）新增**第 5 层断言**：策略值必须在词表内、`blocking + visual_only == 482`、blocking 的 slug 集合必须 == 白名单、blocking 计数必须 == 8+6+6、`visual_only == 482-20`，且**清单的 `design_intent` / `validation` 与 .blend 实测交叉一致**。
4. **两个运行时探针**（`probe_rooftop_decorated_layout.gd` / `probe_rooftop_decorated_stage_only.gd`）：绿化件必须**恰好 1 个启用碰撞形状**、且其 `BoxShape3D.size` / 中心必须与再算一遍的**实测可视包络**吻合（`BLOCKING_BOX_TOL=0.01`）、body 必须 `layer=1/mask=0/ALWAYS`；非绿化件必须 **0** 启用碰撞形状。

**反向对照（改坏→变红→还原→逐字节一致）**：把 20 件绿化翻回 `visual_only` ⇒ ① 两份运行时探针 `exit 1`（`blocking INST_368_flowerbox enabled shapes=0 expected=1` …）；② 直接在 `.blend` 侧翻坏 ⇒ 布局 QA `ROOFTOP_DECOR_LAYOUT_QA_FAIL` 报 3 条（`blocking slugs=[] / blocking instances=0 / manifest blocking_collision_count=20, actual 0`）。还原后 `.blend`（sha256 `de1d7ce6…`）与 `.json`（sha256 `fcf892d7…`）与快照**逐字节一致**、三类验收全绿。

门禁：`check_asset_registry --ledger scenes --scope full` 维持 **46**（**不新增资产、不新增条目**；布局 .blend 重生成 ⇒ 同步 row 240 的 SHA `09e9a917… → de1d7ce6…`）；场景账本 row 240 状态列 `static / visual_only → static / per_instance(visual_only+blocking)`、规格列 `0启用碰撞 → 20启用碰撞（绿化）`，`3D-场景通用` row 146（碰撞开关 未创建→开、碰撞归属 `引擎（visual_only）→ 引擎（per_instance：默认 visual_only，绿化 blocking）`、碰撞方式 → BoxShape3D 实测包络代理）与域变更日志 **v0.1.8** 同步；运行时清单 `rooftop_100f_decorated_runtime_manifest.json` 的 `collision_policy / enabled_collision_shapes(0→20) / collision_owner` 同步。**8/8 屋顶验收全绿 0 ERROR**：`probe_rooftop_decorated_layout`（`ROOFTOP_DECORATED_LAYOUT_RUNTIME_OK instances=120 groups=6 blocking=20 visual_collisions=0`）/ `probe_rooftop_decorated_stage_only`（`…_OK instances=120 blocking=20 visual_collisions=0`）/ 布局 QA（`…_QA_OK instances=482 … blocking=20 visual_only=462`）/ `verify_rooftop_32x32_contract` / `verify_rooftop_door` / `verify_base_rooftop_transit_door_motion` / `verify_rooftop_railing` / `verify_tower_grid_component_alignment` / `verify_rooftop_floor_facade_components`。

<br>

## 2026-09-21｜三次修正 100F 天台装饰：立管接到地板、墙挂空调 90° 倾倒让风扇朝外

业主实机看截图反馈两条：「水管可以接下来一些，接到地板 上面基本看不到的」「空调机的在墙上的状态，需要 90 度旋转，让风扇朝外」。全部**原地修正**（AssetID / layout_id / layout_version 不变）：

1. **立管落地**：`pipe_riser` 件高 **4.945m**、原点在**管底**、顶端是朝 +X 的鹅颈出水口。旧版放 `h=5.8` ⇒ 管底**悬空 5.8m**。现每处摆**两段、两段的 h 都是 4.945**：下段 `rotation_x_deg=180` **倒装**（几何绕原点翻到下方 ⇒ 包络 0~4.945m，原点即上端；鹅颈转到贴地 0.095m，读作立管底部的泄水口）、上段正装（4.945~9.89m，鹅颈仍在顶 9.795m），合成一根 **0~9.89m 连续落水管**；与 10.65m 环管之间残留 **0.76m**，由环管本体与支架轨遮住 ⇒ 达成业主「上面基本看不到」。支架同时补一段低位（1.5m）与原有 7.0m 位，覆盖 1.56~10.64m。立管 4 处 → **8 段**、支架 4 → **8 件**。
2. **墙挂空调倾倒 90°**：新增实例朝向分量 **`rotation_x_deg`**（绕自身 X 轴的「倾倒」，此前 `add()` 只会绕 Z 轴转平面朝向）。组件 `hvac_small` 的**顶面**（Blender 局部 +Z）自带出风风扇、**前面**（局部 −Y）自带进风格栅 —— 落地摆放时风扇朝上是对的，**一挂到墙上风扇就朝天**。故 4 台墙挂机统一 `rotation_x_deg=90`，风扇转成朝墙外（南墙 → +Z、东墙 → +X、西墙 → −X）。⚠️ **欧拉序契约**：Blender 默认 XYZ 序（矩阵 = `Rz·Rx·Ry`）、Godot 默认 YXZ 序（矩阵 = `Ry·Rx·Rz`），**只有 `rz` 分量为 0 时** `Rz@Rx` 与 `Ry@Rx` 才同序、角度才可逐值搬运 ⇒ 布局源只用 `rotation_x_deg` + `rotation_y_deg` 两轴，**禁止同时给 ry 与 rz**。两个引擎分别取过真值矩阵验证，映射 `(bx,by,bz)→(bx,bz,−by)` 下等价。
3. **6 个墙挂件贴墙**：4 空调 + 2 通风口的后背统一埋进墙外皮内 **0.05m**，不再悬空（旧版通风口后背离墙 0.63m）。立管与支架按各自墙面给 yaw（旧版立管一律 0 ⇒ 东西墙鹅颈朝墙里）。

**运行时重放实例 112 → 120**（`pipe_risers` 8 → 16）：空调与通风口 6 + 绿化 20 + 藤蔓 16 + 女儿墙挂藤 8 + 水管 54 + 立管/支架 16；结构壳体（234 地砖 / 68 件女儿墙 / 楼梯与碰撞）与玩法不变。

验收与防再犯：布局 QA（`validate_rooftop_decorated_layout_v001.py`）新增**第 4 层断言** —— ① 墙挂空调「倾倒后包络轴交换」：沿墙法线进深必须 = 原**高度** 1.87、竖向高度必须 = 原**进深** 2.365，且机背埋进外皮 0.05m；② 立管两段接地：下段 `rotation_x=180` 且**管底 z=0**、顶 z=4.945，两段合成顶 z=9.890。运行时探针 `probe_rooftop_decorated_layout.gd` 新增 `_check_fan_outward()`（**风扇轴必须指向该墙外法线**，外法线由 30×30 壳体中心推得、不查表）与 `_check_riser_runs()`（按**实测可视包络**判两段连成 0~9.89m、最低点落 y=0；⚠️ 倒装件原点在上端，**不能用 `position.y` 判落地**）。**两层断言都做了反向对照**（`HVAC_SMALL_TIP`、`PIPE_RISER_LOWER_TIP` 双双改 0 → 重生成 → 两侧同时变红：QA 报 14 条、运行时报 12 条；还原后 .json 与基线**逐字节一致**）。⚠️ 本轮还修掉探针自身的**判据错误**：风扇在 Blender 局部 +Z，经 glTF Y-up 导入 Godot 后是**局部 +Y**，原来读 `basis.z` 会恒判「没朝外」（改用 `basis.y`）。

门禁：`check_asset_registry --ledger scenes --scope full` 维持 **46**（布局 .blend 重生成 ⇒ 同步 row 240 的 SHA `96f914c5… → 09e9a917…`）；账本 row 240（112/6 组 → 120/6 组）与域变更日志 **v0.1.7** 同步；运行时清单 `assets/art/environments/tower_zones/rooftop/runtime/rooftop_100f_decorated_runtime_manifest.json` 112 → 120。8/8 屋顶验收全绿 0 ERROR：`probe_rooftop_decorated_layout`（`ROOFTOP_DECORATED_LAYOUT_RUNTIME_OK instances=120`）/ `probe_rooftop_decorated_stage_only` / `verify_rooftop_32x32_contract` / `verify_rooftop_door` / `verify_base_rooftop_transit_door_motion` / `verify_rooftop_railing` / `verify_tower_grid_component_alignment` / `verify_rooftop_floor_facade_components`。视觉取证：`probe_rooftop_decor_fix_shots.{gd,tscn}` 扩到 **14 机位**（新增立管南/西落地侧视、俯视「上面看不到」、空调南/东正视图，并自加补光灯）→ `_scratch/rooftop/decor_fix_shots/*.png`。旧布局源码留档 `_scratch/rooftop/green_baseline.{blend,json}`、旧账本 `ShellStorm2_场景账本_v001.xlsx.bak_rooftop_decor_third_fix`。

<br>

## 2026-09-21｜修正 100F 天台装饰细节：竖向基准、挡门件、藤蔓错落与新增女儿墙挂藤

业主实机看截图反馈四条：「花圃花盆这些在地面的会悬空」「藤蔓可以有的延展高一点。有的可以高一些，高低错落」「99-100 基地出口的藤蔓和花盆挡住门了，往北移动一些」「我有栏杆的藤蔓组件，帮我适当加进来」。全部**原地修正**（AssetID / layout_id / layout_version 不变）：

1. **悬空根因：竖向基准写错一层**。运行时天台承重面是 **y=0**（`TowerFloorStage3D._floor_visual_origin_y()` 把地砖可视顶面对齐到 Y=0），而布局源把落地装饰写在 `h=0.3`（= 它自己那块地砖的顶面），偏偏地砖组 `rooftop_base` **不在** `ROOFTOP_LAYOUT_REPLAY_GROUPS` 里 ⇒ 实机花草整块砖厚悬空 0.30m、藤蔓 0.35m。修法：新增竖向基准常量 `GROUND_H=0.0` 与 `TILE_H=GROUND_H−0.30`，全部落地件（花箱 / 大小盆栽 / 藤蔓基座 / 女儿墙挂藤）统一 `h=GROUND_H`；自持参照地砖改 `h=TILE_H`，使**砖顶面落回 0.0**（Blender 侧校核图仍然贴地）。
2. **基地东门净空**：东门净宽 2.2m（`Base100UpperShell3D.DOOR_CLEAR_WIDTH`）⇒ 门洞世界 `gz∈[−3.6,−1.4]`。东墙藤蔓 `gz −5.0 → −8.5`（原叶面包络 `gz∈[−7.13,−2.87]` 已盖进门洞）、东侧大盆栽 `−4.0 → −6.2`；另把**正插在门洞正中**的东墙立管 `gz −2.0 → +5.5`（连带其固定支架）。判据按**旋转后包络**，不只看中心点。
3. **藤蔓高低错落**：运行时禁非单位缩放（重放遇 `scale≠1` 直接 `blockers++`），故不能用 scale 拉高 ⇒ 改为**叠件**：11 个基座全部落地，另在 5 个位置叠一层上层藤蔓，叠高 2.0 / 2.4 / 2.6 / 3.2 / 3.6m ⇒ 顶高 **5.80 ~ 7.40m**。
4. **新增「女儿墙挂藤」**（业主提供的组件）：从 v002 主库导出 GLB `env_rooftop_ref_parapet_ivy_top3d.glb`（5.004×0.814×2.009m，原点在底面），生成运行时 prefab `parapet_ivy.tscn`，绑定色盘 post_import，注册进 `ROOFTOP_DECOR_SCENES` 与 `ROOFTOP_LAYOUT_REPLAY_GROUPS`，摆 **8 件**贴天台外圈女儿墙中心线（南 / 北 / 东 / 西各 2）；因挂藤件与 5m 直段同宽，四角让给 `parapet_outer` 转角件。

**运行时重放实例 99 → 112（5 组 → 6 组）**：空调与通风口 6 + 绿化 20 + 藤蔓 16 + **女儿墙挂藤 8** + 水管 54 + 立管支架 8；结构壳体（234 地砖 / 68 件女儿墙 / 楼梯与碰撞）与玩法不变。

验收与防再犯：布局 QA（`validate_rooftop_decorated_layout_v001.py`）**新增第 3 层断言**——① 落地件按 **depsgraph 真实几何包络**（不读 `location`，避免「摆放点对、渲染点错」的自欺）断言底面 `y=0`，并按组数出落地件数（greenery 20 / ivy 11 / parapet_ivy 8）；② 自持地砖**顶面**必须落 0.0；③ 东门净空按旋转后包络判侵入（门洞 gz 窗 + 门高 z∈[0,2.5] + 东侧 5m 通道）；④ 挂藤必须贴女儿墙中心线；⑤ 藤蔓顶高至少 5 档、落差 ≥3.0m。运行时探针 `probe_rooftop_decorated_layout.gd` 同步新增「落地件 y≈0」计数断言。**两层断言都做了反向对照**（改坏即红、还原即绿）：QA 侧把承重面基准改成 0.30 → 落地件全红、地砖顶面全红；把东门净空窗挪到 `gz∈[−7.2,−5.3]` → 抓出 `plant_large` 与 `ivy` 挡门；运行时侧把 greenery 落地数改成 21 → 立刻 exit 1。另新增视觉探针 `probe_rooftop_decor_fix_shots.{gd,tscn}`（9 机位，非 headless）出图逐条复核。

门禁：`check_asset_registry --ledger scenes --scope full` 维持 **46**（无新增类别、无新增 `duplicate_asset_id`；布局 .blend 重生成后同步 row 240 的 SHA）。账本《资产主表》row 238（组件库：16 → 17 件导出、11 → 12 类装饰接入）与 row 240（布局：99/5 组 → 112/6 组）同步，域变更日志追加 **v0.1.6**。旧布局源与旧 prefab 留档 `_scratch/rooftop_ivy/backup_{components,runtime}`。


## 2026-09-21｜修正 100F 天台装饰布局：坐标契约、装饰外皮与重复层

业主实机反馈「天台的装饰坐标偏移了，范围也错了，没有和顶部的 99 层基地正上方的墙壁是一体的，目前围起来的整体偏小还往北偏了一点」。三处根因，全部**原地修正**（AssetID / layout_id / layout_version 不变）：

1. **缺一步坐标换算**：布局源按 Godot 世界平面口径书写（x=+东、gz=+南），而项目约定 Blender 侧 `world.z = −by`（见 `Block00MasterOfficeLayout3D.gd` 的坐标契约注释：Blender X=东 / Y=北，Godot +z=南），作者脚本却直接 `by = gz`。于是整份布局在 Godot 里**南北镜像、整体偏北 10m**：地砖落在 z∈[−42.5, 32.5]、女儿墙 z∈[−44.75, 34.75]，而天台壳体是 z∈[−35, 45] ⇒ 北侧溢出边界、南侧缺 10m。修法：作者脚本新增 `gz_to_by(gz) = −gz`，摆位参数一律保持 Godot 口径，写入 Blender 时一步换算。
2. **房屋 footprint 与所在建筑不符**：布局里的「房屋」不是独立小屋，而是 `Base100UpperShell3D`（30×30、世界 y=0..12）的外皮 —— 资产件契约写死 `metadata/collision_owner = "Base100UpperShell3D"`，`prp_rooftop_roof_full_5m.tscn` 明写「只用在 6×6 网格的 4×4 内圈 16 格」、封顶碰撞 `RoofCollision` 为 30×0.30×30。原 20×20（4×4 网格）既小 10m 又偏北 3m ⇒ 「偏小还往北偏」。改为 **6×6 = 30×30、同心于世界 (0, 5)、东墙门段对齐 `EAST_DOOR_CENTER_Z`（本地 −7.5 ⇒ 世界 z=−2.5）**；周边装饰（空调 / 花圃 / 藤蔓 / 水管）随之外扩贴到 30×30 墙皮，水管直段每边 8 → 12 段（2.5m 间距不变）。
3. **重复层**：`env_base100_upper_shell_30x30_h12_root_top3d.tscn` 自 2026-09-20 起已自带 24 块墙 + 36 格封顶，布局源里同名 60 件若重放会**逐面 z-fighting**。这 60 件改名 `shell_reference`，只作 Blender 侧参照；`ROOFTOP_LAYOUT_REPLAY_GROUPS` 收为 5 组（hvac_wall / greenery / ivy / pipe_loop / pipe_risers）。**运行时重放实例 113 → 99**，结构壳体（234 地砖 / 68 件女儿墙 / 楼梯与碰撞）与玩法不变。

验收与防再犯：布局 QA（`validate_rooftop_decorated_layout_v001.py`）新增「换算后必须落在 `ROOFTOP_WORLD_RECT` 内」「地砖 / 女儿墙贴边界」「墙中心线 / 门段 / 6×6 封顶网格对齐 Base100UpperShell」「不得出现 house_shell / house_roof 组名」四组断言；`TowerFloorStage3D._build_rooftop_authored_layout()` 同步加「越界即 blocker」的运行时断言 —— 旧算法在旧数据上会红，可反向对照。门禁 `check_asset_registry --ledger scenes` 维持 **46**（无新增、无新增类别）；`verify_ledger_split` **15 项与改前逐项一致**（含既有的 `ENV-ROOFTOP-DECOR-LAYOUT-100F` extra；用改前账本快照复跑对照确认，本批零增减）。账本《资产主表》row 240 与《3D-场景通用》11 行同步，域变更日志追加 **v0.1.5**；渲染预览重出 `outputs/rooftop_100f_decorated_layout_v001_{overview,closeup,top}.png`。旧布局源留档 `_scratch/rooftop_decor_fix/layout_before.{blend,json}`。

## 2026-09-21｜100F 天台按组件库完成装饰布局并接入 Godot，场景账本同步跟进

- 用户要求「用组件库里可装饰的组件装饰天台：墙上放空调、房子周围放花圃、加藤蔓、把水管接起来」。落地为**独立布局源 + 运行时重放**：Blender 侧新增 `source/layouts/100f_decorated_v001/rooftop_100f_decorated_layout_v001.{blend,json}`（469 个 Collection Instance，布局集合自身 0 Mesh、全部缩放 1）；Godot 侧由 `TowerFloorStage3D` 读清单重放 **113 个装饰实例**（房屋墙体 16 + 屋顶 16 + 空调与通风口 6 + 绿化 18 + 藤蔓 11 + 水管 38 + 立管支架 8，共 7 组）。
- 组件几何**不改**：11 类装饰（`ENV-ROOFTOP-REF-HVAC-SMALL/VENT`、`PIPE-STRAIGHT/ELBOW/TEE/RISER/BRACKET`、`IVY`、`FLOWERBOX`、`PLANT-LARGE/SMALL`）从 v002 主库逐件导出 GLB 到 `tower_zones/rooftop/components/`，并生成运行时 PackedScene `tower_zones/rooftop/runtime/<slug>.tscn`；11 件 `.import` 全部绑定 `tools/asset_pipeline/scene_facility_shared_palette_post_import.gd`（否则白板且不触发任何 `*_OK` 门禁），并把天台组件目录加入 `.gitignore` 的 `.import` 白名单。
- 结构壳体不重复生成：234 块 5m 地砖、64 段女儿墙直段 + 4 个外角、楼梯与碰撞仍由 `TowerFloorStage3D` 负责；装饰件全部 `visual_only`，启用碰撞 0、非单位缩放 0。坐标转换固定 `Godot = (Blender X, Blender Z, -Blender Y)`。
- 账本（`assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx`）：《3D-场景通用》**11 行**由「Blender源已完成」→「正式美术已接入」，补 runtime PackedScene / GLB 路径、功能脚本 `src/world3d/TowerFloorStage3D.gd`、碰撞归零与实测记录；**专页与《资产主表》各新增 1 条** `ENV-ROOFTOP-DECOR-LAYOUT-100F`（100F 天台装饰布局，SHA 指向布局 Blend）；《资产主表》row 238 库行刷新为 **47 包** + 方案A 0.80m + SHA `ca091c6d… → d9e96fa1…` + 更新时间 2026-09-21；域变更日志追加 **v0.1.4**。遵守 README「AssetID 已存在 → 升级既有行」：11 类装饰**未新增任何组件 ID**。
- 扩容连带：新增主表行后，查重公式、数据校验、条件格式与筛选范围由 `$R$6:$R$239` 统一扩到 `$R$6:$R$240`，`总览` 10 格统计公式同步；旧范围 CF 条目已清理，不留重复范围。
- 门禁：`check_asset_registry --ledger scenes --scope full` **47 → 46**（`sha_mismatch` 24 → 23，恰为库行；`invalid_status` 5 / `path_not_found` 18 不变，**无任何一类增加**、无新增 `duplicate_asset_id`）；`verify_ledger_split` 13 → 14，**唯一新增**为 `asset_not_in_baseline: ENV-ROOFTOP-DECOR-LAYOUT-100F`（本次有意新增条目，与上一批 `ENV-TOWER-DOOR-LEAF-5M` 同类），历史行**零丢失、零改写**（GONE=∅，`missing` 仍是既有的两条 shelter）。
- 文档：`docs/v0.1/design/rooftop_component_library.md` 同步（女儿墙 1.8m → 0.80m 方案A、库内 47 包、「未接入」陈述改为「已按装饰布局接入」、接入边界改为装饰层 `visual_only`）。
- 旧账本留档：`ledgers/ShellStorm2_场景账本_v001.xlsx.bak_rooftop_decor_ledger`。

## 2026-09-20｜100F 上层围护东西南三面与 24m 封顶换成天台参考组件库 v002（房间墙 + 房顶模块）

- 按用户口径「把天台参考组件库里的房间墙体、门与房顶做成正规 prefab，拼装到 100F 上层围护」落地。`env_base100_upper_shell_30x30_h12_root_top3d.tscn` 的 **24 块墙 + 36 格封顶**重新装配：东西南三面 **17 块**换 `ENV-ROOFTOP-REF-ROOM-WALL`（`prp_rooftop_room_wall_5x12.tscn`），24m 封顶 **36 格**换 `ENV-ROOFTOP-REF-ROOF-{CORNER,EDGE,FULL}`（角 4 + 边 16 + 内圈 16）。
- **北面大窗与东面门洞槽保留 base99**（2 普通墙 + 4 窗墙 + 1 门墙）。原因：东面 `z=-7.5` 门洞槽是 100F **唯一外梯过场门**，由 `TowerDescent3D._install_base_rooftop_transit_door()` 挂 `RoomDoor3D`，净尺寸写死 `TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M/HEIGHT_M = 2.2×2.5`（`TowerGeometry3D`）；换 v002 门洞墙的 **3.80×6.80** 洞 = 改全游戏所有门。用户决策「东门不动，新门只入库」。
- ⚠️ **朝向差 180°（本批最大的坑）**：天台 v002 件外法线朝**局部 +Z**，99F/基地系 base99 件朝**局部 -Z**，同一条边 rotation 差 180°。对照（三方互证：facade 环注释 / `reference_assembly.json` / 场景实测包络）：**南 max z** → v002 `0°`（base99 `180°`）；**北 min z** → v002 `180°`（base99 `0°`）；**东 max x** → v002 `+90°`（base99 `-90°`）；**西 min x** → v002 `-90°`（base99 `+90°`）。全部只用 `rotation_y`，不做 z 翻转。
- 房顶模块收口在**局部 +Z 与 -X**：6×6 角格 `(min x,max z)→0°` / `(max x,max z)→+90°` / `(max x,min z)→180°` / `(min x,min z)→-90°`；边格按所在边 `max z→0°` / `min z→180°` / `max x→+90°` / `min x→-90°`；内圈 `0°`。封顶摆 `y=24`（占 24.00..24.30），墙视觉高 `11.9m` 顶面 23.9，留 0.10 给封顶。
- 场景由 `_scratch/task_house/gen_h12_scene.py` 重生成，自校验 `COUNTS {'1_plain':2,'2_window':4,'5_room_wall':17,'3_door':1,'8_roof_corner':4,'7_roof_edge':16,'6_roof_full':16}`、`SELFCHECK_OK walls=24 roof=36`。⚠️ **CRLF 归一必须整体 `.replace("\r\n", "\n").replace("\n", "\r\n")`** —— 拼接 parts 内的注释串含裸 `\n`，只 `join` 不够（初版实测 `bare_LF=237`）。
- 运行时快照 `DungeonRoom3D.get_room_snapshot()` 新增 4 键：`base100_rooftop_room_wall_count` / `base100_rooftop_roof_{corner,edge,full}_count`（按 `asset_id` 元数据统计节点数）。`verify_base99_wall_visual_replacement` 的 `base100_wall_plain_instance_count` 断言 **19 → 2**（换墙后 base99 普通墙只剩北面 2 块），并新增 4 条 v002 计数断言（17 / 4 / 16 / 16）。**反向对照**：临时把 17 改 18 → 变红、exit 1、报错精确，已还原。
- 只读探针 `probe_h12_house` 实测：`wall_children=24`、`roof_children=36`；4 件数量全 OK；rotation 全符合；`palette_bound=73 / palette_wrong=0 / no_material=0`；首个实例世界包络正确（ROOM-WALL `(10,12,14.85)..(15,23.9,15.15)`；ROOF-CORNER `(-10,24,-15)..(-15,24.3,-10)`）。
- **11 个正式 prefab**（`assets/art/props/dungeon_3d/prp_rooftop_*`）+ 11 GLB（`tower_zones/rooftop/components/`）建立；其中 `prp_rooftop_room_door.tscn` / `prp_rooftop_room_door_leaf.tscn` 是**全新**件（v002「门与暖灯_主体」528 顶点焊接网格按 5 制作件 AABB 无损二分：130 面 → 门扇、418 面 → 门组件）。门两件与挂藤三件**只入库、不摆放**。
- 台账（`ShellStorm2_场景账本_v001.xlsx`）：《3D-场景通用》9 行（106-111 / 136-138）`Blender源已完成 → 正式美术已接入` 并补 prefab/GLB/碰撞/尺寸/朝向；新增 2 行（144 `ENV-ROOFTOP-REF-ROOM-DOOR`、145 `-DOOR-LEAF`）；《资产主表》row 108 `ENV-BASE100-UPPER-SHELL-30X30-H12` **v002 → v003**、SHA 刷新 `3c44b2bd… → 376d1620…`。遵守 README「AssetID 已存在 → 升级既有行，不新增行」。
- 门禁：`check_asset_registry --ledger scenes --scope full` issue **47 → 46**（`sha_mismatch` 24 → 23，恰好是上层围护行；`invalid_status` 5 / `path_not_found` 18 不变，**无任何一类增加**、无新增 `duplicate_asset_id`）；`--scope structure` 仅剩 5 条既有 `invalid_status`（`ENV-TOWER-STAIR-*` / `ENV-TOWER-CORNER-COLUMN-05M` 的「白盒组件」）。跑绿：`verify_base99_wall_visual_replacement`、`verify_base99_structural_asset_integration`、`verify_rooftop_floor_facade_components`、`verify_rooftop_32x32_contract`、`verify_base_rooftop_transit_door_motion`、`verify_base99_door_visuals_v021`、`verify_arrival_gate_floor_bundle_flow`、`verify_tower_extraction_return_flow`、`verify_base99_modular_room_visual`。`verify_base_overhaul_flow` 为**基线红**（用改动前旧场景反向复跑，同样的 4 条 ERROR 与 `Invalid call. Nonexistent 'float' constructor.` 完全一致，与本批无关）。
- 文档：`assets/art/environments/base_facility_3d/基地99层美术场景编辑说明.md` 第 30 / 31 / 35 / 39 行同步（`H9 → H12`、`9→18m → 12→24m`、`18m 封顶 → 24m 封顶`、`36 块基地地板 → 36 块 v002 房顶模块`、`19 普通墙 → 2 普通墙 + 17 v002 房间墙`），并把 180° 朝向差写进编辑器说明。

## 2026-09-19｜关卡设计源支持房间级覆盖：刷怪计划 `enemy_spawn_plan` 与首领指派 `boss_content_id`

- 背景：关卡设计源（L2 `floors/floor_NN.json`）此前只能定**几何与内容类型**，控制不了「这一间房刷什么」和「这一间 Boss 房出哪个首领」。本次给房间加两个**可选**字段，让设计源能覆盖这两件事，同时**不新增任何数值真源**。
- `enemy_spawn_plan`（房间级刷怪计划）：写了就由设计源全量接管该房的**波次数 / 每波数量 / 怪物组合**，`desired = 4 + floor*2` 公式、COMBAT 波次表 `[1,2,2,3]`、主题权重池 `enemy_pool` 一律不参与；**单只怪的数值仍由 `MonsterInjector` 出**（主题倍率 + 楼层缩放照常生效），设计源只写「要谁、几只」。硬上限波数 ≤ 6 / 单波 ≤ 24 / 全房 ≤ 64。`monsters[].type` 只能取 `BASE_ENEMY_TYPES` 去掉 `boss` 的 6 个值。
- `boss_content_id`（房间级首领指派）：只指定本 Boss 房出场的**是哪一个**首领，其余（显示名 / 正式模型 / 竞技场资产 / 阶段技能袋 / 强调色）全部由名册 `BossContentCatalog` 决定 —— **设计源绝不写竞技场或技能袋**，否则会与名册形成两份真源。当前可填 3 个（`boss_abyss_archivist_95` / `boss_furnace_warden_90` / `boss_hollow_choir_85`）。
- **口径统一（新增两条唯一真源函数，禁止在别处复刻表）：**
  - `GameDesignConfig.is_spawn_plan_authorable_room(content_type)` = 房型属于 `ROOM_TYPES_WITH_HOSTILES` **且不是 `BOSS`**。原 `SPAWN_PLAN_FORBIDDEN_ROOM_TYPE` 常量被 `BOSS_ROOM_TYPE` / `BOSS_ROOM_ROLE` 取代。
  - `GameDesignConfig.is_boss_room(content_type, role)` = `content_type == "BOSS"` **或** `role == "boss"`。两者都要认，因为 `FloorPlanGenerator._assign_content_types_data_driven` 会把 `role == "boss"` 的房间**钉成** `type = "BOSS"`；只看 `content_type` 会让这种房间绕过静态校验。
  - `BossContentCatalog.resolve_profile(authored_content_id, floor_number)` 是首领身份的**唯一解析口径**：①写了 ID 就用它，层号取内容**固有层号**；②没写则按房间所在层号取名册条目（塔楼 95/90/85 照旧）；③两层都取不到（**单层关卡没写**）→ **本房不出 Boss**；④写了但名册里没有 → **返回空、绝不静默换人**。
- **「没写 boss 就是没有 boss」落地为合法空房**（用户确认口径）：单层关卡的 Boss 房若未指派首领，`Dungeon3D._spawn_room_enemies` 走专门的空房分支 —— 清房放行、状态栏「首领房未指派首领 · 区域已放行」，**不 `push_error`**（必须早于通用「敌群生成失败」分支，否则会误报并刷屏）。`MonsterInjector.generate_enemies` 的 `"boss"` 分支同时改为**空字典不入列**，与 `"elite"` 分支一致。
- **校验新增两条错误码：** `enemy_spawn_plan_on_boss_room`（Boss 房不归设计源管）、`boss_content_id_on_non_boss_room` / `boss_content_id_unknown`（首领指派填错位置或指向名册外内容）。
- **透传链路是「四道白名单」，四处都补齐：** `LevelPlanLoader.normalize_floor`（源→规范化层）→ `FloorPlanGenerator.room_from_source`（规范化层→运行时计划，本次**从 `generate_from_level_plan` 的循环体抽成独立函数**以便直接驱动）→ `TowerDescent3D._append_plan_room_record`（计划→塔楼 record）→ 两处 `configure({...})`（record→房实例）。`Dungeon3D` 的 BOSS 分支把 `room.get_meta("boss_content_id")` 传进刷怪入口。**两个字段都刻意不进 `layout_id`**（存档指纹），改它们不会让既有存档失配。
- **门禁：** 四项全绿 —— `verify_level_plan_design_source`（`LEVEL_PLAN_VALIDATE_OK` + `LEVEL_PLAN_RUNTIME_GUARD_OK`，现在多打一个 `boss_ids=` 样本计数）、`verify_test_level_99_flow`（`TEST_LEVEL_99_FLOW_OK`，新增 `_verify_boss_identity`）、`verify_expedition_level01_flow`、`verify_floor_plan_generator`（`layout_ids=100` 不变，证明未动存档指纹）。回归：`verify_unique_boss_content_flow` / `verify_three_segment_tower_generation_flow` / `verify_tower_descent_flow` / `verify_tower_floor_room_authority` 全绿，塔楼 95/90/85 首领照常出场。
- ⚠️ **两处「空跑门禁」已识别并处理：** ①`LEVEL_PLAN_RUNTIME_GUARD_OK` 新增 `boss_ids=` 计数，并在为 0 时另打一行 `LEVEL_PLAN_RUNTIME_NOTE` 声明「暂无 `boss_content_id` 样本」，避免 0 样本伪装成通过；②透传侧改由**手写 patch 探针**直接驱动 `FloorPlanGenerator.room_from_source` 覆盖（当前没有任何关卡在数据里写该字段，纯读现成关卡会退化成 0 样本）。
- **反向对照（防假绿）两次实测通过：** 把 `resolve_profile` 的「按 ID 指派」分支临时屏蔽 → `verify_test_level_99_flow` 报 3 条错、0 个 `*_OK`、exit 1；把 `room_from_source` 的 `boss_content_id` 键临时改名 → 报 `FloorPlanGenerator 未把 boss_content_id 透传进运行时房间`、exit 1。两条断言都**真会红**，已还原。
- 文档：`05.2` §3.3 关键点新增第 5、6 条并扩了 JSON 示例；skill `09-level-plan-authoring` 修正了原先「`enemy_spawn_plan` 必须属于 `ROOM_TYPES_WITH_HOSTILES`」的**错误口径**（正确口径是 `is_spawn_plan_authorable_room`，即**排除 BOSS**），并新增「第 2 步补充二 · 首领指派」与两条已知坑（四道白名单 / 编辑必须串行且回读）。

## 2026-09-19｜删除旧聚落天台资产（ENV-ROOFTOP-SHELTER-90X80 整体移除）

- 按用户要求「先把旧的那套删除」，把旧聚落天台整条链路从仓库移除：`assets/art/environments/rooftop_shelter_3d/`（609 MB / 329 文件）、`rooftop_shelter_diorama_3d/`（83 MB / 45 文件，**全项目零引用**）、`source/art/blender/environments_v01/rooftop_shelter_50m/`（57 MB / 15 文件），**合计 749 MB / 389 文件**。前序 [天台运行设施清空](2026-09-17_rooftop_facilities_removed.md) 只摘了运行引用，本次把资产本体一并删除。
- 同步删除专用件：`zone_rooftop.tscn`（唯一运行时 PackedScene 入口）、`src/world3d/RooftopAmbience3D.gd`（删入口后成孤儿）、`verify_rooftop_shelter_asset_contract.gd/.tscn`、`tools/asset_pipeline/` 下 3 个天台专用脚本。
- **两个工具刻意保留**：`export_godot_rooftop_reference.gd`（导出 Godot 原生 100F 对照，与旧资产无关，输出路径改到新建的 `tower_zones/rooftop/references/`）；`build_rooftop_shelter.py`（`build_british_corner_bookshop.py` 靠 `exec` 复用其通用构建函数，英伦街角书店仍活跃，24 文件）。
- 清理引用：`.gitignore` 3 条 `!*.glb.import` 例外、`verify_tower_level_blocks.gd` 的 `zone_rooftop` 存在性断言、`classify_asset_repository.py` 的 50M 分支、`tower_zones/rooftop/README.md`（重写）、`05.1_关卡区块设计.md`（目录树 + 区块表 + 正文两处）。历史记录（既有批次文档 / CHANGELOG 旧条目 / `audits/evidence/` 取证 / `outputs/` 日志）与参考组件库 `qa/` 里登记 v021 源 SHA-256 的验收证据**一律不改**——源移除后不再可复算，保留原样用于回溯。
- **台账**：场景账本《资产主表》删 117/118 行（`ENV-ROOFTOP-SHELTER-50M-3D`、`ENV-ROOFTOP-SHELTER-90X80`）、《3D-场景通用》删 61 行，并解除 `ENV-ROOFTOP-REFERENCE-COMPONENT-LIBRARY` 指向已删条目的「变体父ID」——**新参考组件库自此为独立顶层库**。派生列公式 / DV / 条件格式 / autofilter / 总览跨度一律 `import split_asset_ledger`，不另抄一份。
- **顺带修复**：原账本 236 行派生列公式是畸形写入（单元格存成 `==LOWER(...)`，多一个等号，Excel 里是 `#NAME?` 级错误），重建后转为 `=LOWER(...)` 正确形态。
- 门禁：`check_asset_registry` issue **539 → 65**（`dedupe_key_formula_wrong` / `dedupe_result_formula_wrong` 各 236 → 0，`invalid_status` 6→5、`path_not_found` 26→25、`sha_mismatch` 35→35 持平，**无任何一类增加**），资产条目 425 → 423。`verify_ledger_split` failure_count **475 → 8**；其中 4 项是本次删除的直接后果（2×`asset_lost` + `moved_sheet_mutated` 3D-场景通用 + 参考组件库 `row_content_mutated`），另 4 项既有（塔楼门墙 / L 墙角内容变更、`ENV-TOWER-DOOR-LEAF-5M` 不在 2026-09-18 基线内）。⚠️ 该守卫是**拆分无损回归守卫**、**没有「已知移除」白名单**，`missing = 2` 属如实反映而非回归；若要它重新全绿需加白名单机制（本次未做）。
- 回滚锚点 `git tag pre-old-rooftop-removal`（`73e3fac6`，分支 `0.1.2`）。当前 100F **无 PackedScene 入口**：整层由 `TowerFloorStage3D` 程序化装配（18×16 格 / 90×80m / 234 块地砖 / 68 段围护 / 承重 + 四边碰撞），地砖与女儿墙的**外观件**仍是 Blender 导入的 GLB（`visual_only`）由系统按网格摆放；现行替代为天台参考组件库 v002（44 包 / 10 类，仅 Blender 源，未导出 GLB、未接入）。
- 细节见 `docs/v0.1/development/2026-09-19_old_rooftop_removal.md`。

## 2026-09-19｜门墙改双面装饰（v005）：装饰面镜像到走廊侧，同一件资产两侧都有效果

- 按用户反馈「我发现这个墙会连着走廊，做成两面都有效果的，直接复制一个镜像一下，在blender里头制作，完成后重新导入」落地。范围经确认**只做门墙**——实心墙与 L 墙角保持单面（它们本来就不夹在走廊两侧）。`ENV-TOWER-WALL-DOOR-5M` 由 `v004` 升到 `v005`，稳定路径 `assets/art/environments/tower_descent_3d/components/env_tower_wall_door_5m_top3d.glb` 原地覆盖，**不增加件数**（门禁仍 `PREFAB_CONTRACT_OK count=6`）。
- **问题定性**：v004 只有房内侧（Godot `+Z`）有装饰，走廊侧（`−Z`）是一块平整结构背。门墙夹在**房间与走廊之间**，两侧都会被玩家看到——8.7 的画面探针当时已经把它量出来了（内外细节能量比 **4.247**），只是判据写成了「房内侧 ≫ 外侧」，等于**在给缺陷留位置**而不是验收合格。
- **做法：只镜像装饰面，不镜像整物体。** 派生脚本新增 `mirror_decoration()` 阶段（在 yaw 烘焙与三角化**之后**、朝下剔面**之前**）：复制网格 → 在副本上删掉 `y > −(0.15 + 0.002)` 的面，只留结构面前侧的装饰面 → 加 **Mirror 修改器**绕 `y = 0`（网格中心线 = 基准面）翻转 → 应用后与原网格 `join`。**整物体镜像不可行**：门洞隧道与背壳横跨 `y=0`，整物体镜像会与保留几何**共面闪烁**并把门洞复制成两条。Mirror 必须 `use_mirror_merge=False` / `use_clip=False`（开合并会把跨平面的面粘到基准面、开裁剪会把它们钉死），两项都关掉后修改器**自动翻转绕向**，镜像面法线朝外，无需手工 flip。v004 那次「把 Blender `+Y` 搬到 Godot `+Z` 的 180° yaw 烘焙」保持不变，所以镜像是**真镜像（z → −z）**而非旋转复制。
- **门洞绝不能被镜像面堵死**：门洞判据从两向扩到**三向**，新增 `±Y` **贯穿厚度**射线。实测 `ray_plus_y = null`、`ray_minus_y = null` → `clear_through_thickness = true`（厚度方向没有任何面横在洞里）；`±X` 净宽 **2.2**、`+Z` 净高 **2.5** 与 `TowerGeometry3D.DOOR_CLEAR_*` 及 `DungeonRoom3D._add_tower_wall_collision()` 脚本碰撞代理逐值一致，**运行时代码一行未改**。
- **⚠️ 镜像对称性不能用面的「色心」去比（float32 陷阱）**：初版按色心排序后逐项 `zip` 比对报了 **911 条不对称**，改用容差桶贪心匹配仍报 **29 条**；逐条对拍发现**两侧顶点位置多重集完全相同（差异 0）**，未匹配行的最近邻 `dpos = 0.000000`。根因是镜像顶点以 **float32** 存盘，色心/法线差约 **1e-5**，5 位小数处一翻转排序就整体错位，而容差桶贪心匹配本身不保证传递性。改用两个对 float32 **逐位稳定**的不变量：① **顶点位置键多重集**（镜像只翻 `abs(y)`，逐位精确）② **向量面积相对偏差**（抓绕向反转——面反了法线朝内、背面渲染不可见，但面积绝对值一样，只有有向面积能抓到）。实测 `mirror_position_key_mismatches = 0`、`mirror_vector_area_relative_delta = 0.0`。
- **⚠️ 退化面会让「朝下面」计数在存盘/重载之间翻转**：源含 **24 个零面积面**（`area < 1e-9`），零面积面的法线是数值垃圾，用它分类会让「朝下面」计数在 **1367/1368** 之间摆动，造成门楣保留断言偶发假红。新增 `DEGENERATE_AREA_M2 = 1e-9` 让所有朝下统计跳过退化面并单独报告 `degenerate_zero_area_faces = 24`；门楣保留断言加 `DOWN_FACE_COUNT_TOLERANCE = 4` 容差——**门楣存在性由门洞射线测出 `clear_height_m = 2.5` 精确证明，不靠计数**。朝下面仍只剔贴地那一层（保留 **2734** 个、删 **200** 个）。
- 几何实测：装饰面/侧 **7883**（剔贴地面后 **7799**），镜像新增 **7883**（与装饰面 **1:1**），未参与镜像的结构面 **168**；包络 Blender `y ∈ [−0.3415, +0.3415]`（Godot `z` 同值）**关于 `z=0` 对称**；**跨侧共面孪生 = 0**（源本身有 132 组薄片双面写法，镜像后恰好 2× = **264**，**新增为 0** 才不会 z-fighting）；`faces_after_optimize = 15734`。GLB **1,147,372 B**（v004 为 581,392 B）/ `sha256 = 473a2d18…`；4 个材质角色全保留、无空槽。
- prefab 声明：`asset_version = v005`、`visual_bounds_size_m` `(5,11.9,0.4915) → **(5,11.9,0.683)**`（`z ∈ ±0.3415`）、新增 `metadata/double_sided = true`；`bounds_size_m` 仍 `(5,11.9,0.3)`——8.4 定下的「结构 / 可视两个字段刻意分离」再次兑现：**装饰加厚只动可视字段**。
- **探针判据跟着改向**（这是 8.7 留下的坑）：`probe_door_wall_visual` 的单面判据 `DETAIL_RATIO_MIN = 1.5` 正式退役，改为 `SIDE_DETAIL_MIN = 0.0010`（**两侧都**必须达装饰级——素结构背实测 0.0004，过不去）+ `SIDE_RATIO_MIN/MAX = 0.5/2.0`（两侧能量比必须回到 1 附近）。另三个探针的期望包络由 `0.4915` 改 `0.683`，并新增「关于 `z=0` 对称」与「prefab 声明 `double_sided`」两条断言。
- 门禁全绿：`PREFAB_DOOR_WALL_OK`、`PREFAB_CONTRACT_OK … count=6`、`TOWER_PALETTE_VISIBLE_OK`、`TOWER_GRID_COMPONENT_ALIGNMENT_OK`、`DOOR_WALL_RUNTIME_OK`（递归探针实测 **120** 个模块中塔楼 A 套 **118** 个全部 `pos=(-2.5,0,-0.3415) size=(5.0,11.9,0.683)`、4 表面）、`DOOR_WALL_VISUAL_OK captured=4`，`ERROR` 行数 0。
- **画面取证（v004 → v005）**：房内侧 **7 层 / 0.0015 不变**；走廊侧 **2 层 / 0.0004 → 6 层 / 0.0018**（×4.5）；两侧能量比 **4.247 → 0.829**。像素比对（`scripts/png_diff.py`，中央 3/4 区域 140,256 采样点）：房内侧 v004 vs v005 **平均通道差 0.04/255、明显不同 0.2% → 「几乎同一画面」**（房内侧原封不动）；走廊侧 **1.98/255、12.5% → 「不同画面」**（只改了走廊侧，正是「镜像装饰面」应有的效果）。镜像性对拍（`_scratch/flip_compare_door_wall.py`，把走廊侧图水平翻转后再比）：v005 `1.59 → **0.96**/255`（翻转后更接近房内侧），v004 基线 `2.75 → 2.73`（素背板翻转等于没翻）。肉眼也可直接看：走廊侧图上 **B1 标牌、警示三角、门楣黄黑警示条全部左右翻转**——这是「镜像」而非「两面各画一遍」的直接证据。（残差 0.96/255 来自键光 1.1 与补光 0.5 的**照明不对称**，不是几何差异。）`aperture` / `lintel_up` 两张仍分别为 7 层 / 12 层，门洞通透、门楣底面仍在。
- 台账《资产主表》**仍是升级既有第 57 行**（AssetID 已存在，新增行会报 `duplicate_asset_id`）：只动 **M / N / P / T / W / Y** 六格（`O` 稳定路径未变、原样回写故字节相同），M=`v004→v005`、T=`d5fd5a75… → 473a2d18…`、W=「Blender 派生（自 v007 通用门墙组件）→ …，v005 双面」、Y=追加本次说明段。范围引用一律不动（表仍 `6..241`、`dimension=Y241`）；补丁后复核（`_scratch/verify_ledger_door_row57_v005.py`）`LEDGER_ROW57_PATCH_OK = True`——zip 26 条目逐字节只有 `sheet3.xml` 变、变化的单元格**恰好** `M57 N57 P57 T57 W57 Y57`、`R57/S57` 原样、`T57` 与磁盘 GLB 哈希逐字符一致。
- 分账门禁 `failures` **仍是 475，本次 +0**（`row_content_mutated = 3`：第 55 行 8.4 墙 + 第 69 行 8.6 L 角 + 第 57 行 8.7/8.8 门墙）。**第 57 行本来就已在名单里**，重复改同一行不再累加——与第 10 节「每次有意变更恰好 +1」不矛盾：**+1 是「某行第一次被改」时记的账**。
- 细节见 `docs/v0.1/development/2026-09-19_关卡通用物体资产契约对照.md` §8.8。

## 2026-09-19｜门墙换正式美术：自战局通用组件 v007 派生 v004，退役最后一处塔楼程序生成方块

- `ENV-TOWER-WALL-DOOR-5M` 的可视本体由**塔楼旧套件的程序生成方块**换成正式美术（`assets/art/environments/tower_descent_3d/components/env_tower_wall_door_5m_top3d.glb`，稳定路径原地覆盖），prefab 仍是 `assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn`（`DungeonRoom3D.TOWER_WALL_DOOR_PREFAB`）。来源为战局通用组件库 v007 的 `wall_door_5m_通用包`（根件 `ROOT_wall_door_5m_通用组件`，主体 4410 面 + UI 灯光 182 面）；选 v007 而非 v006 是因为 v007 的 ROOT 就在世界原点，省掉一次 recenter。派生脚本 `.../tower_descent_3d/source/wall_height12/export_env_tower_wall_door_5m_v004.py`（与实墙同目录、同 `derive|export` 两段式）。
- **确认用户判断属实**：旧 v003 确实是程序生成的方块门墙 —— GLB 仅 **41,760 B**（新 **581,392 B**）、出自 `env_tower_descent_kit_top3d_v007.blend` 的 `10D_MOD_WALL_DOOR_5M_U01` 集合、**没有 PaletteUV**、`.import` 里 `import_script/path=""` + `embedded_image_handling=1`，游离在共享色盘体系之外（同批的实墙 / 门扇 / L 墙角都已绑定）；台账 `W` 列原值也正是「程序生成 Blender 源集合」。这类失效**不触发任何 `*_OK` 门禁**，只有画面能看见。
- **本件是六件里唯一不能照搬实墙优化的**：门墙有门楣，门楣**底面朝下且位于净高 2.5m 处**，是玩家站门里抬头唯一能看到的朝下面。照实墙「全剔朝下面」会把门洞上方打穿。改判据为**只剔贴地那一层**（`|z| ≤ GROUND_BAND_M = 0.05`）：实测剔掉 **116** 个贴地封口面、**保留 1376** 个高于地面的朝下面；派生脚本内建 `lintel underside was culled` 断言 + 导出阶段第二道复核挡回退。顺序仍是「先三角化再剔面」（4592 n-gon → 7935 三角面）。
- **门洞净空用射线从门洞内部实测复核**，不采信源文件自报包络：`±X` 命中 ±1.1 → 净宽 **2.2**；`+Z` 命中 z=2.5 → 净高 **2.5**。与 `TowerGeometry3D.DOOR_CLEAR_*` 及 `DungeonRoom3D._add_tower_wall_collision()` 的脚本碰撞代理逐值一致，**碰撞侧一行未改**。这也是门墙与实墙的一个差别：门墙**没有** `source_visual_version` 的运行时三处纪律（那条只属于被 `TowerDescent3D` 直接 preload 裸 GLB 的实墙），版本串只有 prefab `metadata/asset_version = v004` 一处。
- 包络：结构 **5 × 11.9 × 0.30** 不变；可视 **5 × 11.9 × 0.4915**（装饰面朝房内 Godot `+Z` 凸到 `+0.3415`、结构背 `−0.15`）。旧 v003 的装饰门框会向下探出楼面 0.14m（旧可视包络 5 × 12.04 × 0.43），**v004 不再下探**。四材质角色 01/02/03/04 **全部有面**（与实墙 / L 角的「3 角色 + 丢弃空槽 03」不同），`dropped_empty_material_slots = []`。
- **门扇随重导出消失**：v007 门墙包本就不含门扇。旧 v003 自带的那片 `visible=false` 的 `DoorLeaf_OPEN`（即 3.3 第 1 项「首 mesh 漂移」的来源）不再存在，prefab 里的对应 override 段一并删除。**连带修好一条会骗人的断言**：`qa/probe_tower_palette_visible.gd` 原断言「必须存在隐藏门扇且 `visible=false`」，在**正确**的新资产上反而 FAIL —— 已反转为「门墙子树里不得出现任何名字含 `DoorLeaf` 的节点」（出现即说明换回了旧资产）。
- 新建两条画面/运行时探针：`probe_door_wall_visual`（`DOOR_WALL_VISUAL_OK`，四机位 room_side(+Z) / outer_side(−Z) / aperture / **lintel_up 仰视门楣底面**；「非空白」判据放宽到 2 层亮度分层因为结构背本就是纯平板，判别力改由细节能量比承担 —— 实测 `room/outer = 4.247`，仰视图细节 0.0070 为四张最高，是「门楣没被打穿」的直接证据）与 `probe_door_wall_runtime`（`DOOR_WALL_RUNTIME_OK`，递归核对运行时**118 个塔楼门墙模块**全部 4 表面 / AABB=5×11.9×0.4915 / 装饰面朝 `+Z`；**必须按 `asset_id` 过滤**，节点名前缀 `Imported_DoorWall5M_*` 与基地 99 层设施房的 `ENV-BASE99-WALL-DOOR-5X12` 共用，不区分会量出假失败）。
- 门禁全绿：`PREFAB_DOOR_WALL_OK`、`PREFAB_CONTRACT_OK … count=6`、`TOWER_PALETTE_VISIBLE_OK`（118 模块全部 `override=null` / `doorleaf=none`）、`TOWER_GRID_COMPONENT_ALIGNMENT_OK`、`DOOR_LEAF_PLACEMENT_OK`（换墙未影响 8.5 的门扇贴地）、`DOOR_WALL_VISUAL_OK captured=4`，`ERROR` 行数 0。顺带修掉探针里一处 GDScript 陷阱：`var node := stack.pop_back()`（`Variant` 配 `:=` 在「警告视为错误」下编译失败）→ `as Node`。
- 台账《资产主表》**升级既有第 57 行**（AssetID 已存在，新增行会报 `duplicate_asset_id`）：M=`v003→v004`、N=新包络与门洞口径、O=稳定 GLB 路径、P=派生链路、T=`a78cbb01… → d5fd5a75…`（磁盘实测）、W=「程序生成 Blender 源集合 → Blender 派生（自 v007 通用门墙组件）」、Y=追加本次说明段。范围引用一律不动（表仍 `6..241`、`dimension=Y241`）；补丁后复核 `zip test` 干净、`T57` 与磁盘 GLB 哈希逐字符一致。
- 分账门禁 `failures 474 → **475**`，**恰好 +1**（就是第 57 行的 `row_content_mutated`），红项构成 = 既有 470 条场景账本 R/S 派生列公式红项 + 既有 1 条门扇行 `asset_not_in_baseline` + 既有 1 条 `moved_sheet_mutated` + 第 55/69/57 行三条有意变更。判据仍是「红项 ⊆ 基线 ∪ 本次有意变更」。**核对方式提醒**：`verify_ledger_split.py` 的 JSON 只保留 `failures[:40]`，直接看会把红项误读成「只有 40 条」且看不到本次那一条 —— 拿全量须重放行级检查（`_scratch/ledger_split_audit.py`）。
- 同时修掉两处随换版失效的**代码注释**（`src/world3d/TowerGeometry3D.gd`）：「首 mesh 漂移」与「网格自身 AABB 需累积变换」两处举例用的是旧 v003 门墙，事实已不成立，改为「当时（v003）…该资产已换 v004」并保留原结论。
- 细节见 `docs/v0.1/development/2026-09-19_关卡通用物体资产契约对照.md` §8.7。塔楼 A 套四件（实墙 / 门墙 / 门扇 / L 墙角）至此**全部**走完跨套迁移范式，旧塔楼程序生成资产在这四件上已无残留。

## 2026-09-19｜塔楼通用物体第六件：L 型转角换 A 套正式美术（含同日朝向修正）

- `ENV-TOWER-CORNER-L-5M` 的可视本体由程序化 BoxMesh 占位换成塔楼 A 套正式 GLB（`assets/art/environments/tower_descent_3d/components/env_tower_corner_l_5m_top3d.glb`），prefab 仍是稳定路径 `assets/art/props/dungeon_3d/prp_corner_l_5m.tscn`（`DungeonRoom3D.TOWER_CORNER_L_PREFAB`）。**不单独建模**：取与实心墙同源的 v007 通用墙包，Stage 1 先优化一次（triangulate→删朝下面，断言 5319 面），再刚性复制两次摆位 —— 长臂 `T(+2.5,0,0) @ Rz(+180°)`、短臂 `T(0,+2.5,0) @ Rz(+90°)`，L 合计 10638 = 2×5319，与直墙逐面一致。Stage 1/2 必须分离，否则二次 `transform_apply` 的 float 舍入会翻转 7 个临界朝下面。
- 新增第四个原点契约 `bottom_corner`（原点 = 转角、两臂向 `+X`/`−Z` 伸出，**禁止重新居中**，否则所有房间角错位）；本件是六件里唯一自带碰撞的件（两个 `StaticBody3D` `WallCollisionLong`/`WallCollisionShort` 是 `_configure_corner_camera_collisions()` 的镜头下压契约，改名即回归）。统一契约门禁 `verify_tower_module_prefabs.gd` 目标 5→6 件，判据 `PREFAB_CONTRACT_OK count=6`。
- **同用户反馈修正朝向**：「L 型墙壁的组合资产中有一面墙的装饰正面跑到外侧了，房间里本该朝向玩家的那面变成了背面」。根因不是几何而是**「哪一侧算房间内」被写错**：两臂沿 `+X`/`−Z` 伸出时凹象限是 `+X`/`−Z`，而 prefab 注释、探针机位与导出断言当时都按 `−X`/`−Z` 写，于是「错标号 + 顺着标号写的断言」互相自洽、一路绿灯。正确口径只认运行时（`_spawn_room_corner()` 注释 + `_build_corner_aware_wall_run()` 的南墙 `rotation_y=PI` / 西墙 `+PI/2`，A 套直墙装饰面永远朝房内）。修正后长臂装饰面朝 Godot `−Z`（房内）、短臂 `+X`（房内），外侧只剩结构背。
- 新增 `ARM_FACING_GODOT` 逐臂断言（报 `CORNER_ARM_FACING_WRONG`）：拿「装饰面凸 0.3175 / 结构背 0.15」这条美术不对称当朝向指纹逐臂比对自身 AABB。**包络、三角面数、材质角色、原点约定四类既有断言全都抓不到朝向** —— 长臂反 180° 后仍是 10638 面、角色不变、`bottom_corner` 仍成立，只有 `z_max` 从 0.3175 悄悄变 0.15。
- `probe_corner_l_visual.gd` 机位改为按真实房间内侧取景，并新增**逐面朝向判据** `FACE_GAUGES` + `_measure_faces()`：把长臂装饰面（房内 `z=−0.3175`）与结构背（外 `z=+0.15`）的世界四角用 `Camera3D.unproject_position()` 投影到屏幕取矩形裁剪，量高通能量（积分图盒式模糊半径 6，与离线脚本同口径）；判据 `room/outer ≥ 1.6`，机内实测 **3.220**（`0.02099/0.00652`），**反向对照**（两个取样面互换机位）得 0.149 → `exit 1`，判别力约 21×。
- 重导出实测：GLB 751852 B / `sha256=451ba73e…`；包络 `5.15 × 11.9 × 5.15`、最小角 `(−0.15, 0, −5.0)`；`PREFAB_CONTRACT_OK count=6`（0 ERROR）、`CORNER_L_VISUAL_OK captured=4`；4 张画面里 interior 两臂装饰面在角上相接、exterior 两面平整结构背。
- 台账《资产主表》**升级既有第 69 行**（AssetID 已存在，新增行会报 `duplicate_asset_id`）：N 列包络改 5.15、T 列哈希 `297ffb52… → 451ba73e…`、Y 列追加同日朝向修正 + 判据固化说明。范围引用一律不动（表仍 6..241、`dimension=Y241`）。分账门禁 `failures=474 / missing=0 / extra=1`（红项 ⊆ 基线 ∪ 本次有意变更）。
- 细节见 `docs/v0.1/development/2026-09-19_关卡通用物体资产契约对照.md` §8.6。

## 2026-09-19｜保底武装补配套弹药：入场即给 60 发通用备弹

- 按用户要求「保底武装的配套逻辑……改成多加60发的通用子弹」落地。先厘清现状：**原先不存在任何配套逻辑**。白送手枪的唯一来源是 `Player3D.start_with_weapon`（`src/player3d/Player3D.gd:62`，`_ready()` 里 `_ensure_weapon_tree()` → `BlueprintRegistry.get_starting_weapon_tree()` → `bp_pistol + mod_bullet_sticky`），它每次装配场景都给枪，但**备弹恒为 0**；备弹只能靠掉落、下局带入（`pending_loadout`）或精英保底掉落。
- 后果是一条玩家可见的断链：死亡返城/新开局时手上那把枪打空 12 发弹匣后，若没捡到弹药就再也打不响，而 HUD 只显示 `12 / 12 · 0备弹`。
- 新增 `Dungeon3D.GUARANTEED_LOADOUT_AMMO_ROUNDS := 60`（`src/world3d/Dungeon3D.gd`，内容数值唯一出口，测试用 `get_guaranteed_loadout_ammo_rounds()` 读取）与 `_grant_guaranteed_loadout_ammo()`；在 `_setup_run_modules()` 里与 `BaseManager.consume_pending_loadout()` 同一条边界发放（`not test_mode`），与白送手枪共用「每次装配场景」的生命周期。
- **不引入重复累计**：`_setup_run_modules()` 先于 `_runtime_restore_snapshot` 分支执行，续档恢复由 `InventoryModule.restore_slots_snapshot()` 整格清空再回填，入场发放会被存档快照覆盖；`verify_tower_runtime_restart_restore` 保持全绿即为该不变式的实测证据。
- 新建门禁 `verify_guaranteed_loadout_ammo_flow`（`test_mode = false` + `BaseManager.save_path` 隔离存档，跑真实发放路径）断言四件事：真实入场主背包恰好 60 发且与 `_get_reserve_ammo_count()` 口径一致；HUD 真串含 `60备弹`（驱动 `ammo_changed` 后读真值，不手推字符串）；留 10 发缺口换弹后弹匣满、备弹恰好 50（证明可消耗而非只写数字）；`restore_slots_snapshot()` 后备弹等于存档值（证明不叠加）。判据 `GUARANTEED_LOADOUT_AMMO_OK`，**已注册进 `core`**。
- 回归全绿（含两条 `test_mode = false` 的真实存档路径）：`FINITE_AMMO_FLOW_OK`、`ARRIVAL_GATE_FLOOR_BUNDLE_OK`、`TOWER_RUNTIME_RESTART_OK`、`TOWER_EXTRACTION_RETURN_OK`。
- 未决（已写入 04 §6.6 待裁决块）：①该发放按「每次装配场景」生效，远征逐层（每层一个独立场景）都会补 60 发，是数值影响，需拍板是否按局只发一次；②98F 反向撤退走 `_discard_run_carry_for_retreat()` 会清空背包且不补保底武装，与死亡返城「补枪 + 补弹」行为不一致，动 `RevivalPolicy` 之前应先统一。

## 2026-09-19｜远征关卡01 干净场景改造：移除塔楼残留与隐形阻挡

- 按用户要求「新增加的远征关卡应该是一个干净的场景，只会保留游戏基础逻辑和新的关卡」，清理远征关卡01 场景里的三处塔楼残留。
- **修复（隐形阻挡 / 主因）**：`Blocks/Base/Art`（99F 基地美术：卷帘主门、补给机、工作台、枪械工坊等约 **1200 节点**）此前在 `_ready()` 里只被置 `visible = false`，**碰撞体仍留在物理空间**。塔楼流程会把它 `reparent` 到 99F `facility` 房（降到 y = −12），而远征没有 `facility` 房、`_install_facilities()` 直接 early-return，美术就原地留在 **y ≈ 0**，正是远征的行走平面——表现为入口安全房北侧 6.3/6.4/7.8m、走廊中点 23.1/25.0m、`room_02`/`room_03` 西侧 32.6/67.6/102.6m 均有「看不见却撞得到」的阻挡（命中坐标 `(2.87, 0, −31.35)` 与场景里「枪械工坊」作者坐标吻合）。新增 `TowerDescent3D._remove_tower_base_art()`：`remove_child` + `queue_free` 整棵摘除，并清空 `Blocks/Base` 上的 `asset_ids`/`source_blends`，避免台账从远征场景读出「有基地美术」的假信息。
- **修复（隐形挡墙）**：`TowerFloorStage3D._outer_visual_transform()` 把 `floor_index == 0` 当成天台女儿墙判据，对远征也施加 **0.5 纵向缩放**，外墙可视高度 5.95m 而碰撞盒 12m → 上沿 6m 是隐形挡墙。改挂 `_uses_rooftop_profile()`，并把实测值回填快照字段 `outer_visual_scale_y` 供门禁断言（正常层与远征恒 `1.0`，只有真正的 100F 天台是 `0.5`）。
- **改造（楼面/外墙按内容外框收缩）**：楼面与外墙此前铺满塔楼整块 250×250，远征内容只占一角，远处空地上立着一圈没有内容的墙。新增 `TowerFloorStage3D.configure()` 第 6 参 `content_bounds` + `_has_content_bounds`，非空时 `_floor_grid_dimensions` / `_floor_world_rect` / `_outer_grid_dimensions` / `_outer_world_rect` 一律以它为准；由 `TowerDescent3D._expedition_content_world_rect()`（7 房实际包围盒外扩一格 5m 并对齐 5m 网格）计算传入。实测外框从 `Rect2(-125,-125,250,250)`（50×50）收缩为 `Rect2(-10,-50,135,70)`（27×14 格），地砖数 2500 → **369**，场景总节点 ≈2744 → **1544**。默认值为空 `Rect2()`，塔楼逐值不变。
- **改造（走廊归位）**：新增 `_connector_block()`（远征 → `Blocks/Expedition`，塔楼 → `Blocks/Battle`），水平走廊改走它；此前 6 条 `Corridor_00..05` 都挂在 `Blocks/Battle` 下，远征的通道被算作塔楼内容。垂直楼梯走廊**有意不改**（只在塔楼生成，且 `_connector_block()` 在塔楼返回 `Battle`，改了会把楼梯走廊挪出 `Blocks/Stairs`，破坏 `verify_tower_level_blocks`）。
- 改造后塔楼四区块在远征中**子节点全为 0**，`Blocks/Expedition` 有 14 个子节点（7 房 + 6 走廊 + 1 楼面舞台）。`Blocks/Rooftop|Base|Battle|Stairs` 四个空容器有意保留：`_block()` 会 `push_error` 兜底，删除它们会波及塔楼共用代码，且空容器无碰撞无渲染。
- 门禁补充：`verify_expedition_level01_flow` 增 `_verify_clean_scene()`（`Blocks/Base/Art` 不存在、四区块子节点为 0、`Blocks/Base` 不声明塔楼资产、每条走廊父节点为 `Blocks/Expedition`）；`_verify_level_enclosure()` 由硬编码 250×250 改为内容外框口径（外框对齐 5m 网格、完整包住 7 房、`floor_world_rect == content_world_rect`、`outer_visual_scale_y == 1.0`）。判据仍为 `EXPEDITION_LEVEL01_FLOW_OK`。
- 回归全绿（塔楼路径未受影响）：`ROOFTOP_WEST_EXPANSION_CONTRACT_PASS`、`TOWER_LEVEL_BLOCKS_OK`、`FLOOR_PLAN_GENERATOR_OK`、`ARRIVAL_GATE_FLOOR_BUNDLE_OK`、`TOWER_FLOOR_ROOM_AUTHORITY_OK`、`TOWER_EXTRACTION_RETURN_OK`、`TOWER_JOURNEY_POLISH_OK`、`LEVEL_PLAN_VALIDATE_OK`。
- 详见[远征关卡01制作记录 §7](2026-09-19_expedition_level01_buildout.md)。

## 2026-09-19｜新关卡「远征关卡01」落地：单层 7 房 + 读取界面 + 独立区块

- 按用户要求**完全替换**旧独立副本关卡：删除 `scenes/RogueMap01TowerSegment3D.tscn` 与 `standalone_rogue` / `rogue_map_id` 旧分支，新建 `scenes/ExpeditionLevel01_3D.tscn`（`expedition_mode = true`、`expedition_run_id = "expedition_01"`）。
- 关卡形态：单层 **7 房** = 入口安全房 15×15m + `room_01`…`room_05` 各 **25×25m** + 撤离房间 25×25m。**房型表按 25×25 走 `FloorPlanGenerator.generate_expedition()/validate_expedition()` 独立分支**，不挤进塔楼通用房表（通用 `validate()` 硬拒 `minf < 25`）。
- 5 个内容房房型从 `COMBAT / COMBAT / SCAVENGE / STORAGE / EVENT` 池洗牌分配；排列由 seed 决定（4 种旋转 + 可选 Z 镜像，`0x45585031`），格步 35m、网格原点 2.5m。96 seed 全部合法且至少 4 种排列，随机性成立。
- 新增第五个区块根 `Blocks/Expedition`（`block_id = expedition`，显示名「远征关卡01」，设定名「远征前哨站」）；`_room_block_for_floor()` / `_block_id_for_floor()` 与房间 `block_id` 元数据统一路由到该区块。塔楼主场景仍只有四区块。
- 新增读取界面 `scenes/ExpeditionLoadingScreen.tscn`：面包屑「远征情报室 → 远征关卡01」+ 步骤文案 + 进度条；无头/编辑器跳过延时。入口链路变为 99F基地 → 远征情报室 → 菜单 → **读取界面** → 关卡。
- 撤离房间常驻 `STANDARD`（非锁定、随时可用）撤离信标，沿用 `prp_extraction_beacon_root_top3d.tscn`；不刷怪、不计入必经主路。死亡/撤离/安全房弃局统一走 `Dungeon3D._finish_run()` 返回 `return_scene_path`（BaseWorld3D）。
- **修复**：`_runtime_scope_for_save()` 对 `is_expedition()` 直接返回 `combat`，否则入口安全房（`floor_index = 0`）会被判成 `base` 作用域，导致进图快照不可续局。
- **修复**：`_instantiate_dynamic_room` 的 `block_id` 元数据改为取 `_block_id_for_floor()`，不再硬编码 rooftop/base/battle 三分支。
- **修复（关卡包围）**：远征是单层关卡，唯一层的 `floor_index` 也是 0，被 `TowerFloorStage3D` 当成 100F 天台，静默继承了窄轮廓 `Rect2(-50, -35, 90, 80)`（18×16 格）、99F 中庭贯通洞与 0.75m 女儿墙。后果是 `start` 落在中庭洞里、`room_03/04/05` 与 `extraction`（x ≥ 55、z ≤ −45）落在窄矩形外，**6/7 房间既没有 `FloorSupport` 承重楼面也没有外圈墙**，玩家踩空掉出关卡（即用户反馈的「房间没有阻挡」）。新增 `TowerFloorStage3D.force_standard_map`（`configure()` 第 5 参数），由 `_rebuild_floor_stage()` 以 `is_expedition()` 传入，强制标准 250×250 网格 / 12m 整墙 / 不挖中庭洞 / 不做女儿墙纵向缩放；默认 `false`，塔楼与真正的 100F 天台逐值不变。<span style="color:#777777">（同日后续再收缩为**内容外框** `Rect2(-10,-50,135,70)`，见上方「干净场景改造」条目。）</span>
- 门禁补充：`verify_expedition_level01_flow` 增 `_verify_level_enclosure()` —— 断言楼面舞台快照（标准网格、无中庭洞、整墙高、`block_id=expedition`）、7 间房逐房脚下楼面与四向墙体物理射线、以及每条走廊「开门后可见 + 两侧 3.5m 处命中侧墙」。走廊代码本身经实测无缺陷（隐藏/碰撞卸载由 `_update_corridor_streaming()` 按门开状态管理，开门后即可见可撞），本轮未改动；新增只读诊断探针 `probe_expedition_walls`。
- 基础玩法全部承载：内容房刷怪+清房门锁、穿门命运卡牌三选一、可搜索容器（`RoomFurniture3D.searchable` + `searched` 信号）、撤离信标。
- 门禁：新建 `verify_expedition_level01_flow`（覆盖 入口→菜单→读取界面→关卡、单层、区块、25×25 版图、v007 安全房、门口命运三选一、刷怪+搜索、撤离契约、弃局返航、96 seed 扫描、默认塔楼不变）并**注册进 `core`**；删除 `verify_rogue_map_segment_flow`、`verify_rogue_retreat_return_to_base`、`probe_rogue_resume_exit_flow` 三个旧场景。原「门禁缺口」条目就此消除。
- 详见[远征关卡01制作记录](2026-09-19_expedition_level01_buildout.md)。

## 2026-09-19｜关卡四类通用物体统一契约（地板 / 墙壁 / 墙壁门 / 门）

- 建立唯一视觉解析入口 `TowerGeometry3D.resolve_visual_node/_mesh/_bounds/origin_offset_y`；退役三份重复的「递归取第一个 MeshInstance3D」（`DungeonRoom3D`、`TowerFloorStage3D`、`TowerDescent3D`），改按资产声明的 `metadata/visual_node_name` 解析。该隐式约定已被实测打破：`prp_tower_wall_door_5m` 的第一个 MeshInstance3D 是 `visible=false` 的门扇。
- 四件套补齐同一套 11 项契约字段：`asset_id / asset_version / origin_contract / forward_axis / bounds_size_m / visual_bounds_size_m / visual_node_name / visual_only / collision_owner / preserve_authored_palette / runtime_instantiation`。新增 `visual_bounds_size_m` 是因为实测门墙**结构包络 5×11.9×0.3 ≠ 可视包络 5×12.04×0.43**（装饰门框下探楼面下 0.14m）。
- 装配基准从「网格 AABB 反算」改为「读 `origin_contract` 声明」。旧注释「通用旧墙以几何中心为原点、需抬高半层」经实测为过时描述（v003 与基地墙 AABB 底面均在 y=0，反算恒为 0）。数值行为不变。
- 移除 `prp_tower_wall_door_5m` 内与脚本代理逐值重叠的内嵌碰撞（门柱 2 + 门楣 1），碰撞责任单一化。
- `verify_tower_module_prefabs.gd` 从「只 print」升级为 8 项断言门禁，判据 `PREFAB_CONTRACT_OK`。
- **明确否决**「墙/地砖逐 prefab 实例化」：实测 `initial_world` 余量仅 205 节点（2195/2400），实墙逐实例化净增 2038、地砖净增 45026。按房级只改墙也不可行（419 个墙节点全属房间墙）。门扇接美术同样超预算（114 扇 × 3 = +342）。
- 回归全绿：`verify_tower_grid_component_alignment`、`verify_tower_lighting_wall_combat_regressions`、`probe_safe_room_v007_integration`、`verify_base99_floor_player_collision_flow`、`verify_base99_wall_visual_replacement`、`probe_tower_palette_visible`。
- 详见[契约对照与实施记录](2026-09-19_关卡通用物体资产契约对照.md)。未决：普通战斗房门扇美术选型；基地家族 `dimensions_m`/`center_bottom`/`-Z` 命名漂移未迁移。

## 2026-09-18｜关卡传送入口确立为主线，塔楼连续爬楼转为隐藏关卡

- 按用户设计修订关卡入口：99F基地中央远征情报室选关后“传送进入副本”＝切换地图，进入独立关卡。<span style="color:#777777">（**已被 2026-09-19「远征关卡01」条目完全替换**：关卡已改名为远征关卡01，入口新增读取界面，单层化与撤离房间已完成交付。）</span>
- 独立关卡定位为单层完整肉鸽关卡，新增加撤离房间与撤离信号塔（**待施工**）；当前实现仍为四层。<span style="color:#777777">（**2026-09-19 已完成**：单层 7 房 + 撤离房间 + `STANDARD` 撤离信标。）</span>
- 塔楼连续爬楼（100F→98F→…→85F、95→94唯一电梯、隔离间卸载）整体保留为后续隐藏关卡，本轮不改动行为与数字。
- 原“禁止以传送或地图按钮替代”类条款改为按“关卡内部 / 关卡入口”分域限定，消除与实现的明文冲突。
- 登记门禁缺口：`verify_rogue_map_segment_flow` 未注册进 `core` 套件。<span style="color:#777777">（**2026-09-19 已消除**：该场景被删除，替代门禁 `verify_expedition_level01_flow` 已注册 `core`。）</span>
- 详见[独立记录](2026-09-18_level_teleport_entry_and_standalone_map.md)。

## 2026-09-17｜天台运行设施清空

- 按用户要求移除屋顶设施美术、碰撞和附属效果，并关闭随机家具生成；保留结构与通行。
- [独立记录与验收限制](2026-09-17_rooftop_facilities_removed.md)。

## 2026-09-17｜天台挂藤组件与厚门口 v002

- 根据追加要求增加7个挂藤墙体变体，达到44个独立包；门柱/门楣/门槛具有1.10/1.16/1.55m实际进深。
- 保留36个既有组件的完整源/输出签名；外墙结构与逻辑高度不变。更新Blender组件源、预览和台账，未导入Godot。
- 详见[独立记录](2026-09-17_rooftop_ivy_thick_door_v002.md)。

## 2026-09-17｜天台参考组件库 v001

- 按用户组件图制作37个独立包，包含参考图九类内容和两种标准外墙；外墙实测5×0.30×11.9m，逻辑/未来阻挡12m。
- 四共享材质、38个输出网格，保留166个制作网格；独立目录、清单、固定镜头与局部预览齐备，既有源文件和游戏布局不变。
- 本批为Blender制作交付，未生成GLB、PackedScene或游戏碰撞。验收与限制见[独立记录](2026-09-17_rooftop_reference_components_v001.md)。

## 2026-09-16｜局内关卡01白模墙体模块修复 v003

- 保留地板、房间包络与门中心基线，将跨房间长墙拆为419个固定5m实墙件；非整模数边缘使用30个固定2.5m收边件，墙体Scale均为1。
- 32个带门位置全部改为完整5m门墙槽，每槽由左右门柱与门楣三件组成；19/19 Blender与材质/网格专项通过。
- 同步白模资产台账并补登记走廊5m实墙；主路内容房02继续使用正式机房美术源。未导出GLB或接入Godot。
- 详见[独立记录](2026-09-16_battle_level01_whitebox_wall_modules_v003.md)。

## 2026-09-16｜战局区块最小通用组件库 v003

- 按用户逐组指定的序号清理v002重复项；04首件摆正，01保留正常/损坏各一，06仅留一件。
- 墙体仅保留一个5×0.3×11.9m标准墙，不保留横向拉伸墙；地板仅保留前两个5m组件。
- 最终23包、9类、39个输出网格；组件、四材质、逐面PaletteUV、朝向、墙体尺寸和台账验收通过，未接入Godot。
- 详见[独立记录](2026-09-16_battle_common_component_library_v003.md)。

## 2026-09-16｜战局区块通用组件库朝向、去重与墙地扩充 v002

- 有正面语义的组件统一朝本地+Y，规范化后合并4个完全相同的旋转副本；真实造型与地砖细节变体保留。
- 加入墙壁7包和地板30包，地砖按6×5阵列陈列；房间专属30×25m整块底板不进入通用库。
- 最终77包、9类、143个输出网格；组件、四材质、逐面PaletteUV和台账验收通过，未接入Godot。
- 详见[独立记录](2026-09-16_battle_common_component_library_v002.md)。

## 2026-09-16｜战局区块通用组件库 v001

- 从主路内容房02数据机房抽取43个设施与环境支持包，建立独立 Blender 组件库并按7类展开陈列；每包具有独立局部原点。
- 四共享材质、逐面PaletteUV、包归属和磁盘清单验收通过；新增资产台账条目，未导出GLB或接入Godot。
- 详见[独立记录](2026-09-16_battle_common_component_library_v001.md)。

## 2026-09-16｜主路内容房02数据机房美术 v003

- 依据用户参考图完成 Blender 机房包装，39件原白盒结构和39件原制作源保持几何与变换；82个独立资产包同步磁盘清单。
- 四共享材质与逐面 PaletteUV 验收通过；同步该房间台账，未导出 GLB 或接入 Godot。
- 详见[独立记录](2026-09-16_main_room_02_data_room_art_v003.md)。

## 2026-09-16｜局内关卡01与楼梯间白盒目录归类

- 依据资产台账 `3D-场景通用` 的 `ENV-BATTLE-L01-*` 条目，确认 `battle_level01/v002` 的19个 Blender 白盒属于局内关卡01；保留 v001 与旧程序化 v011 JSON 作为回溯资料。
- 将原本无区块归属的 `v011` 至 `v015` 全部迁入 `source/art/whitebox/tower_zones/stairs/`；v011 的历史文件名虽包含 `battle`，但其 Blend 和数据均为楼梯间回滚内容。
- 同步区块设计、台账根条目、工具/校验路径与目录 README；未修改 Blender 几何、未导出 GLB、未改变 Godot 接入。

## 2026-09-15｜楼梯间复制、反向装配与99→98层对应摆放 v021

- 将v020完整楼梯间组织为100→99层装配体，并生成独立网格复制件作为99→98层楼梯间；两个装配体按区块合同相差180°摆放。
- 保持三个通用组件与七个装饰集合不变；A/B各382个输出网格，382组几何、材质、UV、局部矩阵及集合归属专项通过。
- 四材质与154,947面严格PaletteUV验收通过，双体与单体实景验收图已保存；未重新导入Godot。
- 详见[独立记录](2026-09-15_stairs_dual_assembly_v021.md)。

## 2026-09-14｜楼梯间墙地与墙面配件深化 v020

- 在v019模型上按参考图重做主墙管线、电箱、海报、标牌、百叶与灯具，深化墙板和地板分缝、紧固、检修盖及喷印。
- 保持三个通用组件与七个装饰集合，117个锁定对象及65个结构对象几何检查通过；382个输出网格与10个磁盘清单对应。
- 四材质及85,744面严格PaletteUV验收通过，源文件使用原生压缩保存；五个验收镜头及两张同镜头旧版对比图已保存。未重新导入Godot。
- 详见[独立记录](2026-09-14_stairs_wall_floor_detail_v020.md)。

## 2026-09-14｜楼梯间 Blender 美术源目录规范化 v019

- v019 当前美术源整理为 `assets/art/environments/tower_descent_3d/source/stairs_12m/stairwell_art_v019/`：唯一 Blend、源单元 manifest、组件清单、验收图和 QA 分目录存放。
- 原工具目录只保留工作台回滚快照；v001 保留为 Godot 现有 GLB 的几何基线。未改动运行时 GLB、碰撞、LOD、PackedScene 或 Godot 引用。
- 新路径下的范围锁定、组件清单和 Blender 材质/PaletteUV 专项均通过。

## 2026-09-14｜楼梯间对面留空墙位纠正 v019

- 按用户补充截图纠正 v018 的墙位误判：恢复右侧一、二楼结构墙、装甲板和边框，将连续双层开口改到对面的左侧首跨。
- 左侧三根横框收口到 `Y=2.50m`，右侧横框恢复至 `Y=-2.20m`；主墙海报、楼板栏杆、二楼墙高和既有组件分类保持不变。
- v019 共 301 个输出网格；290 个未授权对象与 v018 完全一致，Blender 材质、PaletteUV 和组件清单专项通过，未执行 Godot 接入。

## 2026-09-14｜楼梯间主墙、删墙、栏杆贴边与二楼墙高修复 v018

- 将 `WORK TOGETHER` 主海报迁到用户指定的二楼墙面；标注位置的一楼和二楼墙段及附属装甲/骨架不进入 v018 输出，相邻横骨架收口到新开口。
- 二楼楼板边缘新增 14 个栏杆网格并归入通用地板组件，底脚与楼板顶面形成 0.02m 咬合；剩余 14 块二楼装甲墙板统一为 `Z=-9.00–2.30m`。
- v018 共 299 个输出网格，继续使用三个通用组件与七类装饰组件；262 个未授权对象与 v017 完全一致，Blender 材质与 `PaletteUV` 专项通过，未执行 Godot 接入。

## 2026-09-14｜楼梯间通用组件重整与栏杆修复 v017

- 墙、地板、楼梯分别收口为唯一通用组件，v016 原集合与 242 个对象作为锁定制作源完整保留；238 个非栏杆对象只复制归类，几何、世界矩阵和组合关系无差异。
- 墙面深化、地面导光、管线、发光几何、标识、控制盒和固定绿植按内容拆成七个装饰组件，10 个末级组件均同步磁盘清单。
- 旧四块错误 `Guard` 不进入 v017 输出；两跑栏杆按每跑 20 级踏步的实际边界重建，共 52 个网格。Blender 材质与 `PaletteUV` 严格验证通过，未执行 Godot 接入。

## 2026-09-14｜楼梯间参考图美术深化 v016

- 基于当前打开的 v015 楼梯白盒原位深化，锁定 97 个源网格的世界变换、尺寸与拓扑计数，新增工业装甲墙板、框架、管线、标识、控制盒、灯带、绿植与冷暖灯光。
- 参考镜头使用非破坏展示剖切；完整墙体仍保留。新建 5 个独立资产包及磁盘清单，四共享材质与公共色盘 `PaletteUV` 严格验收通过。
- 输出参考全景、俯视结构和楼梯近景；本次只完成 Blender 源场景和美术验收，不包含 GLB、碰撞、LOD、PackedScene 或运行时替换。

## 2026-09-14｜楼梯区专用组件与通用拐角柱

- 3Dgame-design的楼梯区组件库新增下层楼板、中层楼板、上层楼板和唯一一套12m U形双跑楼梯；规格写入v013白盒组件清单。
- 通用建筑组件新增0.5×0.5×12.9m拐角柱；通用墙壁同步采用5×0.3×12.9m，新建地板采用5×5×0.3m。
- 组件保存到JSON和Blend时保留稳定AssetID与规格；本次不重新导入Godot。

## 2026-09-14｜楼梯白盒导入粒度修正

- v012按整个楼梯间生成组件，网页仍无法分开选择楼板、墙壁和楼梯；v013将楼梯间改为网页分组，将三个分类Collection分别映射为组件。
- 当前导入结果为两个楼梯间分组、六个组件；每个分类增加独立Empty根用于双向变换写回，所有Mesh继续保持独立。
- Blender导入后的吸附、贴地和碰撞仍默认关闭，本次没有重新导入Godot。

## 2026-09-14｜楼梯白盒组件包与导入安全开关

- 从楼梯白盒v011生成规范化v012，旧版保留；两个楼梯间各自作为组件包，并在包内按楼板、墙壁、楼梯三个Collection分类。
- Blender导入器优先读取组件包标记，一个楼梯间生成一个网页组件，内部对象与父子层级不执行Join。
- Blender导入场景自动关闭吸附、贴地和碰撞，开关状态随场景JSON保存，仍可在网页设置中手动开启。

## 2026-09-14｜楼梯白盒母版清理

- 清理 `whitebox_tower_battle_stairs_v011.blend`，只保留两个楼梯间及其内部结构。
- 删除450个天台、基地、战斗区、模块库、运行同步和展示白盒对象；文件由567个对象降至117个。
- 先前误清理的正式楼梯导入工作副本已由备份恢复；正式楼梯源始终未修改。

## 2026-09-14｜Blender 打开入口通用化

- 删除楼梯专用打开按钮，改为所有区块共用的“打开 Blender”。
- 用户选择区块与任意 `.blend` 后，工具自动建立区块场景并识别资产包或顶层网格根。
- 楼梯继续作为双向读存验收样本，不再成为工具流程中的硬编码交互。

## 2026-09-14｜楼梯 Blender 双向读存实验

- 楼梯正式源的两个资产包以 `Stair_A / Stair_B` 根组件导入网页，真实网格通过GLB预览。
- 网页根组件的移动、旋转、缩放和删除写回工具工作副本 `.blend`；刷新可重新读取 Blend 根变换。
- 正式楼梯源保持不变，首次工作布局将 `Stair_B` 沿X偏移35m便于并排编辑。

## 2026-09-14｜3Dgame-design 统一 Blender 场景保存

- 保留网页组件拖放、变换、分组、参数编辑、AI 编辑和读档能力，每次保存后台生成可直接打开的 `.blend`。
- `.blend` 成为场景最终文件，JSON仅作为网页恢复编辑的同目录伴随数据；Blend失败时不覆盖上次可用场景。
- 增加 `.blend` 下载入口；本链路不修改 Godot、GLB或运行时引用。

## 2026-09-14｜3Dgame-design 组件库按区块归类

- 组件库区分通用组件与区块专用组件；角色、建筑归通用。
- 家具、办公归 `局内关卡01-顶部数据库`，道具归 `天台区`；专用标题从区块设计文档同步。
- 切换区块时同步刷新可用组件，不改变已有场景组件数据。

## 2026-09-14｜3Dgame-design 区块层级对齐

- 工具增加“项目区块 → 场景”层级，区块目录从 `05.1_关卡区块设计.md` 自动同步。
- 区块场景改存到 `save/blocks/<block_id>/`，并更新新建、读取、AI 编辑与预览链路。
- 设计契约与独立开发记录已同步。

## 2026-09-14｜白模JSON对齐3Dgame-design v3

- Battle与Stairs白模数据改为工具可直接读取的`version=3`场景文档，统一Blender Z-up、米、角度及`groups/components`结构。
- 墙、地板和楼梯分别使用工具支持的`surfaceSettings/stairSettings`；项目追溯合同集中到`projectMetadata`。
- 正式楼梯Blend生成器改读新合同位置；不重新导入Godot或修改现有GLB。

## 2026-09-14｜局内关卡编号与设定名分离

- 98–95F统一显示为`局内关卡01-顶部数据库`；稳定编号为`局内关卡01`，可变设定名为`顶部数据库`。
- 编号统一采用`局内关卡`加两位数字；Godot节点、`block_id`、AssetID和文件路径不使用可变设定名。
- 同步白盒数据、Battle区块说明、场景元数据和资产账本，并纠正Battle/Stairs源文件元数据对调。

## 2026-09-14｜楼梯间 Godot 反推与正式 Blender 源

- 以当前两份12米楼梯间GLB为几何真值，新增v012反推白盒合同并纠正旧9米楼梯规范。
- 生成只含100→99与99→98两套楼梯间的正式Blender源，删除战斗区、基地、天台和展示模型；旧v011白盒保留回滚。
- 本轮不重新导入Godot，运行时继续引用原GLB；详见[专项记录](2026-09-14_stairs_formal_blender_from_godot.md)。

## 2026-09-14｜Battle 与 Stairs 白盒目录归一

- 98–95F战斗区和楼梯区明确为白盒阶段，不再将塔楼v011母版描述为正式美术源。
- 白盒目录统一为 `data/`、`blender/`、`renders/`，现有v011母版迁移到白盒目录且不重新导入GLB。
- 同步区块设计、Godot元数据、构建脚本、导入清单和资产台账；详见[专项记录](2026-09-14_battle_stairs_whitebox_relocation.md)。

## 2026-09-13｜WORLD-BLOCKS 四区块场景树

- 塔楼主要场景树整理为 `Rooftop`、`Base`、`Battle`、`Stairs` 四区块，楼层、房间、楼梯、走廊和电梯使用短名。
- 活跃天台与基地 PackedScene 迁入统一 `tower_zones/<block>/runtime` 目录，保留 AssetID 与 GLB，不重新导入。
- 新增区块设计文档，Blender 源补 Godot 映射，资产台账同步路径、源文件和哈希；详见[专项开发记录](2026-09-13_world_level_blocks.md)。

## 2026-09-13｜玩家默认镜头与80%体型

- 塔楼默认相机固定为旧位置连续按15次`'`后的精确位置：局部Y=10.719009m、后移4.037671m，焦点、俯视角和FOV不变。
- 玩家默认倍率由旧资产0.70改为0.80，视觉、挂点和玩法胶囊同步；怪物、设施和世界掉落物尺寸不变。
- 墙边相机收镜阈值、探针高度/起点/长度/横向采样与楼梯斜板探针起点同步重标定。
- 详见[玩家默认镜头与80%体型调整](2026-09-13_player_camera_height_and_scale_08.md)。

## 2026-09-13｜WORLD标准层高改为12米

- 标准层高改为12米，玩法墙高12米、可见墙高11.9米；门净空、5米平面网格和房间平面规则不变。
- 塔楼、基地墙体、转角、上层围护、24米封顶及跨层楼梯资产同步升级，楼层判断统一读取几何常量。
- 详见[塔楼层高调整为12米](2026-09-13_world_floor_height_12m.md)。

## 2026-09-12｜SAVE-RUN重登出生点

- 有效战局快照重登后保留同楼层世界与物品进度，但角色改生于该层入口安全房间中心；不再恢复战斗房精确坐标。
- 100F、99F基地快照改为最后下线楼层标记：无可续局行动时分别进入天台固定点、基地中心。旧档没有基地快照时继续按新手完成状态兼容。
- 详见[重登出生点策略调整](2026-09-12_save_reentry_spawn_policy.md)。

## 2026-09-12｜G02–G04独立功能文档

- 独立训练场拆为测试类功能文档，功能版本1.0标为已完成，并登记独立场景、59种组合、三类靶标和长期数据隔离验收。
- 枪械工坊与局内商人分别建立玩法文档，按当前工程记录已有链路，状态保持开发中。
- 功能索引和差异清单同步：G02关闭，G03/G04从文档缺失转为开发中·部分完成。

## 2026-09-12｜E18–E24与D02–D11设计对齐

- 新建开发中的独立电力系统设计，纳入基地电力与手电电力；基地灯光和设施负载标为待完善。
- E19性能验收与E21基地表现暂缓，待首个完整版或表现版本冻结后签署标准。
- 当前资产清单与运行布局作为E22–E24权威基线，旧节点、坐标与数量标为（旧资产）。
- 弹药现行堆叠999归入枪械设计并标为设计中；补齐断刃、战斧、普通房间钥匙价格和小电池子类。

本文件为独立开发日志，规则读取[主设计](../README.md)，开发顺序读取[文档规范](../../DOCUMENTATION_STANDARD.md)。旧条目保留原貌，仅代表当时交付记录。

## 2026-09-13｜3D场景美术生产流程

- 新增概念、白盒规范、白盒组装、顶视风格稿、Blender制作、优化导入和正式验收的阶段流程表。
- 白盒交付使用简单JSON和标注图片，记录场景尺寸、模块、组合、名字、接口、净空及设计来源；Blender和Godot阶段直接标注两项现有Skill。
- 整个场景美术流程新增区块、楼层、范围、场景设计文档和资产台账定位；区块设计文档按天台、基地、战斗区、楼梯区建立美术流程与资产账本挂钩。
- 本次只补文档契约与导航，不修改游戏版本、代码、模型、场景或资产台账；详见[专项开发记录](2026-09-13_3d_scene_art_pipeline.md)。

## 2026-09-12｜E07/E11/E13/E14工程对齐

- 修复新VFX池回收信号参数，专项验证回收、复用、计数与清理。
- 运行快照分离schema、行动、检查点和布局身份，旧占位字段兼容迁移，精英遭遇改用行动ID。
- 统一runner在Autoload前隔离`user://`，并按场景拦截非预期错误与资源泄漏；E15、E20降为P3暂缓。
- 差异清单更新为16项已处理、28项未处理；详见[专项开发记录](2026-09-12_e07_e11_e13_e14_engineering_alignment.md)。

## 2026-09-12｜E05/E06行动结算单次事务

- 成功撤离与死亡结算统一进入`BaseManager.commit_run_settlement`，统计、魂、战利品／保险中转、幂等日志和行动档清理只写盘一次。
- 写盘失败恢复长期档和场景背包／快捷栏／保险格，提交成功后才发送完成事件和切换场景；同一事务重试或重载重放不会重复结算。
- 差异清单更新为12项已处理、32项未处理；专项见[E05/E06开发记录](2026-09-12_e05_e06_run_settlement_transaction.md)。

## 2026-09-12｜7项内容文档对齐工程

- D01、D03–D07、D13已完成：弹药名称、两类电池、三档手电模块和基地商店总说明与当前运行工程一致。
- 内容数据库同步正式ID、运行字段和已实装状态；玩家手电章节同步ID与验收勾选，不修改游戏代码。
- 差异清单更新为10项已处理、34项未处理；详见[专项开发记录](2026-09-12_d01_d03_d07_d13_document_alignment.md)。

## 2026-09-12｜差异清单补充处理状态字段

- 44项跟踪统一增加`是否已处理（是／否）`，与具体`处理状态`分列；当前3项已处理、41项未处理。
- 文档逐项清单扩展为全部44项，已处理项同样保留处理结果和对应文件，避免只能从描述推断完成状态。

## 2026-09-12｜差异表区分开发进度与事实不匹配

- 按用户已说明的状态规则，将“开发中／部分完成”从工程文档错误中独立出来；未开发完整不再自动判定为不匹配。
- 44项跟踪重新分为：3项已一致、15项开发中·部分完成、8项工程/文档不匹配、12项待设计／核验、6项文档缺失；214条资产明细保持独立展开。
- 同步文档驱动开发规范、结构化差异源和Excel判定列；原整改方向继续保留，用于安排后续施工。

## 2026-09-12｜E01/E02按工程调整设计口径

- 用户决定保留当前运行行为：FloorBundle生成/验证/登记后直接开到达门；隔离前门交互先关闭后侧路线、卸载旧段，再继续开门。
- 两条链路不等待快照写盘，重载使用最后成功快照；02、05、09、11、模块索引、完成度、审计状态和差异表已同步。
- 本次只改文档和差异表，没有修改游戏代码、场景或测试。详见[E01/E02开发记录](2026-09-12_e01_e02_document_alignment.md)。

## 2026-09-12｜E03资源扣款失败回滚

- `BaseManager.spend_extraction_points`改为仅在写盘及回读成功后返回成功；保存失败恢复余额，revision冲突保留重新加载的权威档案。
- 拒绝余额不足、零数和负数；新增`verify_extraction_points_spend_transaction`并加入core清单。
- 工坊扣款+解锁、撤离/死亡结算及底层文件故障矩阵仍是独立遗留。详见[E03开发记录](2026-09-12_e03_extraction_points_transaction.md)。

## 2026-09-12｜工程与文档差异表

- 记录ID：DOC-DIFF-20260912；保留44项差异跟踪、214条资产明细和9项上一轮已对齐记录；E01、E02、E03后续已关闭，当前未闭环41项。
- 当前方向为16项改工程、7项改文档，另18项先确定设计或核验版本；E01/E02标记文档已对齐工程，E03标记工程已对齐文档。
- 统计、状态及导出内容已核对。详见[差异表交付记录](2026-09-12_discrepancy_table.md)。

## 2026-09-12｜工程健康审计与设计/开发记录分离

- 记录ID：DOC-AUDIT-20260912；工程0.1.0；代码基线`31ed360`；本次交付尚在工作区。
- 建立模块/功能契约索引，迁移17处历史章节/整页并保留导航；修正文档中确定过期的实现描述。
- 核心61项：49退出0、11失败、1超时；持久化故障探针复现两个问题，资产台账214项SHA不同步。
- 详见[本次开发记录](2026-09-12_documentation_audit.md)与[审计报告](../audits/2026-09-12_engineering_audit.md)。不宣称代码缺陷、数据库或资产差异已经修复。

## 2026-09-12｜99层设施功能资产转移与0.8m交互包装

- TowerDescent99F完成六项设施资产迁移：`base_vending → 72_SUPPLY24H自动补给机`、`vault → 47_窄型电池柜`、`monster_archive → 49_02_游戏输出_整合模型_v020`、`fate_collection → 42__02_游戏输出_整合模型`、`base_recovery → 45_MEDICAL医疗柜`、`avatar_wardrobe → 36_墨绿三人休闲沙发`。
- 六项均新增独立`BaseFacility3D`包装Prefab；包装根以源资产碰撞包围盒中心为原点，`SourcePackage`反向偏移以保持原世界坐标、模型和碰撞不变。交互区统一为包围盒每侧外扩0.8m，并锁定，防止通用正面交互配置再次覆盖。
- 原菜单、商店交易、恢复、换装、存档和`facility_id`逻辑均未改写；独立的`BaseWorld3D`保留旧赛博储物站、复古电视站和自动贩卖机映射，TowerDescent99F切换到新资产。
- 99F常驻设施由7项更新为8项，新增怪物档案室实体入口。更新Excel美术资产台账、全局资产导入账本、99F优化包账本和v022更新账本；通过`verify_tower_base_facility_persistent_flow`、`verify_tower_facility_inventory_binding`、`verify_formal_asset_placement_visual`和Godot无头编译。
## 2026-09-06｜天台至98F场景与体验成品化

- 100F/98F接入Blender工业地砖v002；保留5米网格、承重面和MultiMesh，新增面板、压边、紧固与检修细节，台账纠正旧GLB/BoxMesh引用差异。
- 全塔减轻双层雾幕，基地中央主灯改为中性冷白，19个既有模型补齐公共色盘导入契约；原122模型353材质验收通过。
- 后续实机调整将距离雾定为0.030、体积雾定为0.009；基地53个既有自发光表面采用分级HDR表现，9组霓虹/灯具强化光晕，7盏无阴影环境局部灯提供墙面与周围受光，冷色适度去饱和，暖灯保留橙色温度。塔楼辉光强度设为0.86、HDR阈值设为0.90。
- 天台29组已制作环境动画正式同步播放，离层停算；原串灯增加3盏昼夜暖光。恢复时间同步太阳，基地恢复正式基地配乐。
- 目标提示读取真实房间状态，移除98F电梯误导与开发尺寸；增加非阻塞楼层进入演出及120ms冲刺末尾输入缓冲，输入锁立即取消旧请求。
- 修复独立基地TSCN注释吞掉卡牌收藏室节点并覆盖保险柜属性的问题；交互初始化不再等待音乐延迟，实体8项/目录9项的当前规则保持。
- 详细范围、资产链、验收与未完成项见`17_天台至98层成品化验收.md`。

## 2026-08-31｜天台v017仅设施接入与原生地板恢复

## 2026-08-31｜天台v019北侧布局、楼梯衔接与阻挡同步

- `ENV-ROOFTOP-SHELTER-90X80`升级至v019：水塔退出广播高台下方，南侧菜园转移至北侧西缘，棚屋与通信高台维持北侧布局。
- 广播高台楼梯重新对接南侧平台边缘；Blender与Godot均采用连续倾斜坡面阻挡，避免逐级碰撞造成无法上台或卡边。
- `TowerFloorStage3D`正式引用v019设施包装；Godot原生100F地板、围栏、门洞和外围碰撞继续保持不变。
- 资产记录补充v019 GLB SHA-256与`collision_layout_v019.json`，源文件仍为可维护的`env_rooftop_shelter_90x80m_top3d_v017.blend`。

- 修正v016整块基础环境被一并接入100F的问题：v017正式运行包装只包含68个设施组件及其39组/82形状阻挡，排除Blender地板、建筑围护、灯光、植被、VFX和远景。
- `TowerFloorStage3D`恢复并持续显示原有Godot地砖、围栏和西侧门洞；原承重面与外围边界碰撞继续保留，不再由导入资产覆盖。
- 设施布局整体下移0.34米，对齐原生地面Y=0；新增回归断言，要求正式包装为`facilities_only`、不得存在`BaseEnvironment`，并要求原生地砖、围栏、门洞均可见。
- `outputs/.gdignore`阻止Godot扫描文档工具目录及其`node_modules`链接，消除每次启动重复导入字体/SVG/BMP和重复UID警告；同时清除主塔楼场景中已移除设施的失效实例覆盖，消除中文NodePath的Latin-1连锁报错。

## 2026-08-31｜天台v016可编辑组件布局与组合碰撞

- `ENV-ROOFTOP-SHELTER-90X80`升级为v016：通信高台移至东北角，生活棚在其西侧贴北边缘并留2米间距，种植区继续向西移动；黄色门口行走动线仍保持零阻挡。
- Godot包装场景不再只实例化整块场景。基础环境与68个语义组件分别导出GLB，并在`布局_可手动编辑`下按生活棚与家具、生存日常、能源供水、种植、通信高台五组展开；编辑组件父节点时，其视觉与阻挡同步移动。
- 设施阻挡由v015的36个单Box升级为39个组件级`StaticBody3D`、82个贴合形状。沙发、桌椅、棚架、高台和栏杆采用组合碰撞，圆形设备采用圆柱，温室仅保留立柱，太阳能板改为薄斜面，消除装饰空隙中的空气墙。
- `TowerFloorStage3D`正式引用v016；专项验收覆盖68个可编辑节点、39个阻挡组件、82个形状、关键物体射线、公共色盘、棚屋/高台分离与黄色动线净空。

## 2026-08-31｜天台标注分区与抬高生活棚

- `ENV-ROOFTOP-SHELTER-90X80`升级为v015，按标注图重排：黄色门前通道保持零阻挡；生活棚最终向北推进至木平台贴合天台边缘；种植留在左后蓝色区；通信平台移到棚屋正南相邻区域。
- `TowerFloorStage3D`正式接入v015包装场景；100F隐藏旧程序化地砖/围栏视觉但保留承重、门洞及外围碰撞，避免双层网格闪烁。主天台测试同时检查v015版本和36个独立阻挡已进入正式Stage。
- 生活棚新增由20条独立木块组成的0.5米高平台、三块可见小木踏步与一个连续斜坡阻挡；原沙发、床铺、工作台、餐桌、卷筒桌和桌面收音机随棚屋整体迁移。
- 棚屋新增高出屋面的彩色旋转小风车、棚内摆动风铃，并重新集中晾晒、盆栽、餐具及生活杂物；Blender语义目录增至68个，待归类对象为0。
- 独立阻挡增至36项；自动验收新增黄色动线零阻挡、红/蓝/通信分区边界、0.5米平台与连续楼梯坡面检查。18×16/234地砖、基地中庭和西楼梯净空保持不变。

## 2026-08-31｜天台部件细分与独立阻挡

- `ENV-ROOFTOP-SHELTER-90X80`升级为v014，v013完整保留回滚；东侧生活聚落的位置和比例不变。
- Blender输出从功能大组细化为64个语义组件目录：双人沙发、电缆卷筒圆桌、桌面老式收音机、桌面散件、公共餐桌/长凳/餐具以及每组能源、储水、种植和通信设施均可独立选取。
- 新增`03_阻挡代理_不导出`，保存34个独立线框阻挡代理；运行GLB明确不携带代理，Godot包装场景按同一清单创建34个独立`StaticBody3D/CollisionShape3D`。沙发、桌子和桌面收音机分别拥有独立阻挡。
- 自动验收新增组件目录数量、零待归类对象、独立阻挡数量/ID唯一性及碰撞代理不混入GLB检查；原18×16/234地砖、两块净空、东侧聚落与公共色盘契约保持通过。

## 2026-08-31｜天台东侧生活聚落集中布局

- `ENV-ROOFTOP-SHELTER-90X80`升级为v013；v012完整保留回滚。生活棚、种植、能源、供水、通信和相关杂物全部集中到用户标注的东侧区域，不再散布于整片天台。
- 聚落按“南部能源供水—中部棚屋餐食—北部种植通信”规划，新增连续木板路、公共餐桌与长凳、碗杯、鞋、洗衣盆、香草晾晒架、串灯和盆栽，强化有人长期居住和共同生活的痕迹。
- 新增东侧规划区`Rect2(15.25,-31,24,67)`自动AABB门禁；生活类资产越界、基地中庭穿插或西侧楼梯间穿插均会直接阻止Blender生成脚本交付。

## 2026-08-31｜基地设施交互、设施精简与天台资产对齐

- 修复99F远征情报室和枪械工坊的正面交互盒反向问题：热区现位于截图黄框所在的房间中心侧；两件设施原有位置、旋转和缩放未改动。
- 从正式目录、99F美术布置层和旧主基地场景移除`fate_divination`命运占卜屋与`base_console`基地管理终端；正式目录现为9项，99F实体设施为8项，旧存档字段和独立菜单资源保留兼容。
- 天台庇护所升级为`ENV-ROOFTOP-SHELTER-90X80` v012：18×16个5米格，按游戏同坐标扣除36格基地中庭和18格西楼梯开口，实有234块地砖。生活、种植、能源、通信和杂物重新分区，两块玩法净空AABB为零穿插。
- 新增v012 Blend、无内嵌图片GLB、Godot包装场景、资产清单、布局验收报告和`verify_rooftop_shelter_asset_contract`；v011保留回滚。

## 2026-08-31｜返城外观、命运卡、仓库、HUD与有限弹药修复

- 正式玩法场景在热返99F时直接从`BaseData.avatar_customization`恢复角色外观，不再依赖主入口界面；死亡、撤离和普通恢复后配件不会临时复位。
- 命运门改为选牌完成后才流送并生成目标敌对房；“下一个房间”的增援、敌血、敌伤和魂倍率准确落在刚开启房间。“下一个箱子”的品质和额外候选由真实容器搜索消费。
- 长期保险柜基础容量从2格提升为20格，保留设施等级追加和旧档兼容；界面使用4列滚动网格。
- 中央状态提示移到左侧目标卡下方；枪械与快捷栏缩至原尺寸60%，右下动作键不缩小。主HUD及公共面板/按钮/槽位底板统一约50%透明。
- 通用弹药堆叠数量改为真实备弹发数。换弹按缺口精确扣除背包/快捷栏备弹，允许部分装填，空备弹不启动；修复切枪往返把旧枪弹匣回满。普通怪有34%独立弹药掉落，精英与Boss必掉8—16发。
- 新增`verify_finite_ammo_flow`与`verify_avatar_return_persistence_flow`，并扩展`verify_celestial_fate_scope_flow`覆盖真实下游结算。
- 完整`core`回归57/57通过；Metal真实渲染`verify_reference_hud_fate_visual`通过并输出新版战斗HUD、塔楼HUD、全层地图和命运三选一截图。

## 2026-08-30｜清房开门与信标返航新战局生命周期修复

- 修复战斗房清空后开启下一扇门会重置当前房的问题：房间运行快照现在只在 `DATA_ONLY` 房间真正重新载入时回灌，普通开门触发的 ACTIVE/SHELL_READY 流送刷新不再用战斗中的旧快照覆盖 `cleared`、房间灯与敌人计数。
- 修复信标成功返航后再次探索仍复用上一局路线和小地图路径的问题：返航/确认撤退现建立新的 `run_seed` 与全套楼层规划，重置战利品/怪物/命运随机流、局内计时，清除已卸载战斗房运行快照、流送状态和雷达探索集合；玩家已带回的背包、武器、快捷栏与保险格继续保留。
- `verify_tower_extraction_return_flow` 新增两项生命周期回归：构造战斗中旧快照后清房开门，验证房间不会复活；成功返航后验证种子、98F `layout_id`、小地图与房间缓存换代。

## 2026-08-30｜塔楼楼梯围护与基地北侧空气墙门禁修复

- 复核发现楼梯Blender v009迁移对两个变体的共享Mesh重复写入，导致围护墙被拉伸到约17米，通用楼梯还保存了重复`EnclosureWall_Far.001`。现从最后干净v008重建v010：所有编辑网格先转单用户，通用/楼顶两套均严格保留四面围护、`-9.0..-0.1m`可见高度、15×30米占地、下平台顶面`-8.9m`和未改动的上平台；导出GLB升级v003，旧v009/v002保留回滚。
- `TowerDescent3D`、两个兼容PackedScene、导入清单和资产台账已切到v003；Godot仍从可见`Walkable`与四面围护生成同形碰撞，共享色盘后处理与无内嵌贴图导入契约保持不变。`verify_tower_grid_component_alignment`与楼梯围护综合碰撞回归通过。
- 基地北侧旧空气墙射线的终点实际进入可见`SouthWarehouseBlocker`约0.17米，属于测试误判，不能删除正式仓库墙。探针现截止于可见墙前通行带；`verify_base99_mezzanine_underdeck_blocker`继续独立验证南/西/东三面可见墙的永久实体碰撞。修复后aggregate core为55/55。
- 修复计划第8步`QA-01`按项目指示归入忽略的美术模块；太阳能量超过旧阈值时只记录`TOWER_ART_SUN_ENERGY_IGNORED`，光照层、阴影遮罩、手电筒和墙体功能契约仍严格验收。

## 2026-08-29｜楼梯间5m白模与下层楼板闪面修复

- 通用楼梯间与楼顶专用楼梯间的历史外廓约为14.3×27.2米，并含0.001/0.1203米级遗留偏移；现从Blender v008母版生成v009，将两套白模外廓统一为15×30米（3×6个5米模块），上下门槽、两跑楼梯、折返平台及门前路线坐标保持不变。
- 四面围护统一收敛到一层9米合同，视觉高度范围为`-9.0..-0.1m`；GLB升级为通用/楼顶v002且不嵌入图片。运行时与两个兼容PackedScene已全部切换到v002，围护和可行走面继续由真实Mesh生成同形碰撞。
- 上层落地楼板保持v008几何与`0m`顶面不变；下层15×30米落地楼板顶面从`-9.0m`抬至`-8.9m`，与下层地板形成0.1米高度差，消除共面闪烁。网格专项新增逐段资产版本、外廓、围护高度、上下楼板和碰撞合同验收。

## 2026-08-29｜3D玩家交互统一与99F普通门命运误触修复

- 新增`PlayerInteractionController3D`作为3D玩法唯一`interact`输入所有者。塔楼/副本世界、基地设施、副本入口、事件终端、撤离信标、搜索家具、灯开关、NPC及训练场货架/出口全部移除各自的E键监听，统一提供候选、聚焦和执行协议；同一世界只选择一个目标，按关键流程、门、设施/NPC、灯、家具的优先级后再按距离决胜，输入锁定时不执行世界交互。
- 修复复位新档后从100F下降、站在99F楼梯下端门前仍保持`current_room=start`时，旧入口用“当前房间+门目标”拼出`start|start`并落入通用战局门命运逻辑的问题。基地门绑定现显式携带`owner_room_id / target_room_id / edge_key`，99F下端普通门始终走`start|facility`的普通门组件，不触发命运、钥匙、清房或FloorBundle。
- 门提示不再由房间每0.08秒独立扫描，所有交互提示由统一焦点控制。新增`verify_unified_player_interaction_flow`并纳入核心套件，覆盖唯一输入所有者、重叠候选优先级、输入锁、新档100→99真实门链以及不存在`start|start`假边；现有基地、训练场、到达门和普通门测试已迁移到统一入口。

## 2026-08-29｜走廊墙统一8.9米视觉高度

- 修复100F经过99F楼梯下端接驳走廊上方时，两侧墙顶闪面的问题。该走廊此前直接实例化9米原始GLB，墙底位于`Y=-9m`、墙顶正好到`Y=0m`，与100F地板完成面共面；普通水平走廊虽另有运行时缩放，但两条生成链没有共用同一高度合同。
- 塔楼墙Blender母版升级为`env_tower_descent_kit_top3d_v008.blend`，墙顶倒角簇从9米原生下移至8.9米，底边和对象缩放`(1,1,1)`保持不变；输出升级为`env_tower_wall_solid_5m_top3d_v002.glb`，不包含图片或纹理。普通水平走廊与楼梯上下端接驳走廊统一直接使用v002，不再依靠运行时纵向缩放。
- 所有走廊墙视觉保持8.9米，顶部相对下一层地面预留0.1米；连续墙体碰撞仍为9米，不改变角色、子弹、光照射线或摄像机阻挡。网格组件专项现同时验证原生8.9米GLB、100/99F接驳墙世界顶面`Y=-0.1m`和9米连续碰撞。

## 2026-08-29｜100F天台西侧扩展2格

- 100F保留原16×16格主区，只向西追加2列5米地砖，最终结构轮廓为18×16格（90×80米）；西边界由`x=-40m`移至`x=-50m`，东、南、北边界及99F基地位置保持不变。
- 地板可视网格、承重碰撞、矮墙栏杆、门洞墙和外边界碰撞统一读取矩形尺寸合同，不再假定天台四边等长。西侧栏杆/碰撞中心移至`x=-49.85m`，与100→99F西侧楼梯外廓的`x=-45m`边缘保留约4.7米净空，不再插入楼梯间。
- 西侧楼梯的15×30米开口现在完整落入100F地板范围；专项验证18×16尺寸、234块有效地砖、68个周长模块、门洞替换以及西侧碰撞不侵入楼梯。此次为程序化关卡布局修正，不修改Blender设施母版或99F/战斗层几何。

## 2026-08-29｜ESC复位存档修订号冲突修复

- 修复ESC暂停页确认“复位游戏存档”后没有生效的问题。按钮与确认框输入正常，失败根因是新`BaseData`从修订号0开始，而通用写盘保护会拒绝它覆盖磁盘中的较高修订号。
- 复位现在只清空玩家档案内容，继续沿用内存档与磁盘档中的最大修订号作为基线，再由正常原子写盘递增一次。并发旧实例防回滚保护、写后回读、失败回滚以及`.bak/.tmp`清理规则保持不变。
- `verify_pause_game_save_reset_flow`新增“已有多次存档后仍可复位”及复位前后内存/磁盘修订号必须单调递增的断言。

## 2026-08-29｜100/99F四扇普通交通门统一

- 新增`SimpleTransitDoor3D`普通交通门组件，统一管理100F西侧楼梯上端门、99F西侧楼梯下端门、99F东侧下行楼梯上端门和99F阁楼东侧外梯门。四门统一使用`ENV-BASE99-DOOR-LIFT-22X25`模型、0.72秒升降动画、门板同步碰撞、E键开启及离开2.85米后延迟0.40秒自动关闭。
- 四扇门不再拥有手动E键关闭、清房、钥匙、命运、FloorBundle或撤退玩法。已开启或正在开启时不会再次成为交互候选；自动关闭过程中重新交互会反向开启。每扇实体门独立开关，不再因刷新同一垂直路线而远程联动另一端门。
- 98F下端到达门生成、首循环封闭及更深战局路线继续由塔楼/到达门系统负责，普通门组件不拥有玩法进度。读档恢复行动状态也不会重新打开四扇实体门。专项现在逐扇验证组件、模型、动画、移动碰撞、自动关闭及跨重启关闭状态合同。

## 2026-08-29｜移除100F↔99F西侧楼梯授权

- 100F↔99F西侧楼梯改为永久存在、永久拓扑连通的固定建筑，不再等待任何门写入`start|facility`授权才加载模型、碰撞或楼梯内侧交互。
- 99F阁楼东侧外梯门及西侧上下端普通门只控制各自实体门板，均不读写西侧楼梯状态；开启东侧门不会再隐式激活或改变西侧路线。
- 旧行动档若保存了`start|facility=false`，恢复时自动迁移为永久连通，但四扇普通门仍保持实体关闭。98F下端到达门、首循环封门和更深楼层路线不受影响。

## 2026-08-28｜98F安全屋严格归属与到达门实机E键修复

- 修复角色仍在98F安全屋外的楼梯平台时，实时位置权威错用“读档可向房外放宽2米”容错范围，提前把`current_room_id`切到98F安全屋的问题。该错误会让E键落入普通房门分支：文字报告线路已开，但下端到达门独立状态仍关闭，门板和碰撞因此继续阻挡。
- 新增`DungeonRoom3D.contains_world_position()`作为普通房间唯一严格内部体积，RoomTrigger、实时房间权威和保存房间归属共用该契约。读档容错仍独立保留，不再参与实时/保存归属；楼梯和门槛无房间时保留最后一个合法房间，不再按最近房间猜测。
- 到达门和Boss隔离门改为“开门不等于进房”；角色中心真正跨过墙体内沿后才切换房间。`verify_arrival_gate_floor_bundle_flow`已改为在98F门外发送真实E键事件，并验证门板、碰撞、门外归属和跨门后归属。
- 修复撤退返回99F、重建98F入口后第二次进入安全屋时，房间流送先停用重建触发区，导致只依赖`RoomTrigger.body_entered`的首门封闭事件丢失、门保持开启的问题。首门封闭现归入严格物理房间切换事务，并在`room_transition`行动快照写入前提交；Area信号仅作幂等补充。专项已移除第二轮手动封门测试捷径，真实覆盖“进入→撤退→再开门→再次进入”，同时断言快照中的路线、sealed与到达门状态一致。

## 2026-08-28｜启动主页与死亡返城链路分离

- 新增进程级`GameEntryFlow`，以一次性入口意图区分冷启动、显式返回主页、新档重启、死亡返城和普通场景恢复；`TowerDescent3D`不再因主场景被加载就无条件实例化`MainEntryScreen3D`。
- 死亡确认后保留原失败结算、保险返还和检查点清理，再显式分流到99F基地玩法入口；该契约强制99F出生、恢复HUD与控制，不经过开始界面。新档复位作为真实的重新开始，仍显示启动主页。
- 新增`verify_game_entry_flow`并纳入核心回归，覆盖主页唯一触发、死亡返城禁止主页、99F出生和场景切换失败的意图撤销。

## 2026-08-28｜场景与固定设施单一公共色盘

- 场景模块、基地设施和固定装饰统一使用`assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`；35份Blender母版的141个图像节点全部改为外链该文件，母版不再打包或私存色盘。
- 44个历史/当前GLB已物理移除嵌入的`images/textures/samplers`与图片字节；Godot导入统一丢弃模型贴图并由`scene_facility_shared_palette_post_import.gd`绑定公共色盘。44份GLB导入契约和1份公共色盘导入契约已加入版本控制白名单，清缓存或换机器也不会丢失。删除组件和旧源目录中的51份重复PNG，不改网格、PaletteUV、材质参数、碰撞、Prefab或玩法逻辑。
- 两项场景设施资产Skill已把“公共色盘唯一事实源、GLB禁止嵌图、Godot统一后导入绑定、组件目录零重复贴图”设为强制规则；新增44 GLB/144材质的自动验收并纳入核心测试入口。

## 2026-08-28｜99F阁楼平台闪面与下方门板碰撞源资产修复

- 从Blender母版确认闪面根因：旧阁楼整块承重板与南/北/东/西四根边梁在外缘同面且高度重叠，运行时产生Z-fighting；不是材质或Godot灯光问题。`ENV-BASE99-MEZZANINE-20X10-Z5`升级为v003，母版升级为`env_base99_modular_room_assets_clean_v005.blend`，将承重皮向四边内收0.15米并保留5米完成面、灯带、护栏和既有独立承重/护栏碰撞，验证结果为660/660面PaletteUV有效、边缘共面数0。
- `ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER`同步升级为v003；横向门板由`env_base99_mezzanine_underdeck_blocker_source_v003.blend`重新导出，PackedScene显式保存南/西/东三块与模型对齐的永久Box阻挡。碰撞顶面4.95米，不穿入5米阁楼行走面；六条高低位物理射线均命中专属阻挡，旧版动态生成仅作为历史场景兼容回退。
- 基地正式布局、导入清单、美术资产台账、专项测试与核心回归入口统一切换至v003；v002源文件、GLB和包装场景保留用于回滚，不做覆盖式修改。

## 2026-08-28｜99F楼层权威、天台阁楼门与太阳间接漫反射

- 修复从100F天台经阁楼门落到99F后，角色已站在99F基地地面但HUD/战术地图仍显示100F的问题。根因是物理高度已算出99F后，同层刷新因楼层索引未变化提前返回，遗留`current_room=start`；现在同层也会重新核对角色是否进入99F基地完整空间体积，并直接同步小地图楼层高度。该修复只校正塔楼的物理楼层、房间权威和地图显示，不改变设施自身交互、战斗层生成或跨层电梯规则。
- 修复100F天台到99F阁楼的特殊滑升门一直保持开启、门板动画与实体阻挡不同步的问题。该门以0.72秒完成开/关过程，门板与`CollisionShape3D`同步移动；门实体使用`PROCESS_MODE_ALWAYS`，不会再因99F房间尚未激活而失去阻挡。**其中“门自身监听E键、再次按E关闭”的旧实现已在2026-08-29被`PlayerInteractionController3D + SimpleTransitDoor3D`替代；当前口径为统一交互选中后开启、离开2.85米且持续0.40秒后自动关闭。**
- 太阳与天空的动态间接漫反射改为始终开启。视频设置将旧`SDFGI`开关替换为低/中/高三级质量：分别使用2/3/4级联与90/140/204.8米覆盖，高档保持原Godot基线；天台兼容补光同步使用36/44/52米范围。旧配置`sdfgi=true/false`自动迁移为高/低档，设置仍独立保存于`user://graphics_settings.cfg`，不影响玩法受光判定或存档。
- 新增`verify_tower_floor_room_authority`和`verify_base_rooftop_transit_door_motion`，并扩展`verify_graphics_settings_ui_flow`、`verify_tower_descent_flow`：覆盖阁楼双向跨层、同层房间纠偏、小地图同步、门动画中间帧、碰撞同步、开启过程与自动关闭，以及间接漫反射三档始终开启和实际环境参数写入。

## 2026-08-27｜屋顶栏杆浮空修复

- **Bug**：100 楼屋顶边缘的栏杆浮空（`RooftopRailLower` 下沿在 Y=0.56，`RooftopRailUpper` 上沿在 Y=1.30，但地板面在 Y=0、`post` 顶部在 Y=1.32）
- **原因**：`_build_rooftop_railing()` 使用了硬编码绝对坐标 `center.y = 0.62 / +0.62`，未与 `ROOFTOP_FACADE_HEIGHT` / `post_height` 联动
- **修复**：以 `RAIL_THICKNESS=0.12` 与 `POST_HEIGHT=1.32` 为常量计算 `RAIL_LOWER_CENTER_Y=0.06`（底贴地板）、`RAIL_UPPER_CENTER_Y=1.26`（顶贴 post 顶），`POST_CENTER_Y=0.66`（底贴地板）；保证栏杆贴在地板面、顶到 post 顶

## 2026-08-27｜交响管弦配乐与音乐系统接入

- Suno.cn 生成 4 首纯器乐交响（base_passion / rooftop_relax / descent_suspense / boss_intense），每首 A/B 两版，由 `MusicCatalog.selection_mode=random` 随机播放。
- 新增 `src/audio/MusicCatalog.gd`（静态资产注册表）、`MusicManager.gd`（autoload 单例：play / push_and_play / restore / pause / stop）、`MusicTrigger.gd`（触发点组件）。音乐逻辑与场景代码完全解耦，新增曲目只需在 Catalog 加一行。
- 接入触发点：BaseWorld3D 进入基地 → base_passion；TowerAtmosphere3D.set_floor_number(≥100) → rooftop_relax；普通楼层 → descent_suspense；95/90/85F Boss 房 → boss_intense（压栈）。
- `MusicManager` 注册成 autoload：`project.godot` [autoload] 区段新增 `MusicManager="*res://src/audio/MusicManager.gd"`。
- 8 个 mp3 由 Godot 自动 importer 生成 `.import` 文件与 `.godot/imported/` 产物。
- 新增验收场景 `tests/verification/verify_music_system.tscn`：4 music_ids + A/B 资源加载 + autoload 接入 + 未知 music_id 拒绝。
- 文档：`docs/v0.1/14.8_音乐系统与配乐资产.md`（架构、清单、触发点、扩展方式、已知限制）。

## 2026-08-27｜99层楼中楼下方工业仓库挡板

- 新增独立环境组件`ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER`：Blender源文件、GLB、PackedScene、预览图、导入清单与美术资产台账均已登记。当前`v002`视觉为冷灰横向仓库分板、浅灰横向分隔条和规律的竖向钢架；保留`v001`紫色/青绿竖向波纹版本供回滚。
- 挡板作为二层楼中楼楼板的子实例，随楼板位置与旋转同步；三面相对外层铁架向内收0.55米，北侧继续由基地外墙封闭，不影响西侧L型楼梯登上5米平台。
- PackedScene持有三个`PROCESS_MODE_ALWAYS`实体阻挡，碰撞顶面为4.95米，不穿入5米行走面且永久禁止角色进入夹层底部。新增专项回归与实际基地视觉验收，Blender逐面PaletteUV与三材质验证通过。

## 2026-08-25｜基地衣柜界面收敛与真实3D配件预览

- 衣柜开启时保存并隐藏父场景正式`HUD`，关闭时恢复原可见状态；世界、角色与衣柜专属补光继续保留，避免玩法主界面穿透到试衣间。
- 左侧“当前穿搭”六个槽位改为可点击的唯一分类导航，右侧移除重复分栏按钮；右栏从526像素收窄为392像素并改为两列选项，为中央实际角色预览释放空间。
- 衣柜选项复用背包`ItemModelIcon3D`的SubViewport、正交相机和单帧渲染链；每个缩略图从正式Bunny角色PackedScene应用对应换装值生成，不再使用纯色方块代替配件模型。
- 新增衣柜布局视觉验收，并扩展衣柜补光与基地总流程检查，覆盖主HUD隐藏/恢复、左栏导航唯一性、右栏宽度和真实3D网格非空。既有基地商店3D图标回归通过。

## 2026-08-21｜99层铆钉地板突出细节恢复

- 确认原GLB没有丢失几何：普通板与铆钉板共用0.30米结构顶面，铆钉板的铁皮压条/铆钉另外突出0.095米，使整件AABB高度达到0.395米。
- 修复运行时误用铆钉板AABB最高点对齐、导致整件下沉0.095米的回归；现在两种板按共同0.30米结构面统一摆放，突出铁皮保持在地板上方。
- 未修改GLB和现有`TowerFloorStage/FloorSupport`承重碰撞；铆钉、压条等突出细节继续只产生表现和投影，不生成额外阻挡。专项验收增加“结构面同高＋0.095米突出仍可见＋统一平面碰撞未变”检查。

## 2026-08-21｜99层设施取消房间激活依赖

- 移除99层十个普通基地设施随“是否位于一楼地面”整批切换`process_mode / monitoring / monitorable`的全局判定；模型、交互Area和实体阻挡改为常驻，是否能使用继续由设施自身Area、功能脚本及业务校验决定。**设施自身监听E键的历史描述已在2026-08-29统一交互改造后失效；当前仅由`PlayerInteractionController3D`读取`interact`。**
- 实体`StaticBody3D`明确使用`PROCESS_MODE_ALWAYS`，避免角色从阁楼门进入时因99F房间尚未切为Active而穿过设施；跨楼层电梯保留原访问房间和楼层加载判定。
- 新增`verify_tower_base_facility_persistent_flow`，复现“阁楼入口已显示99F但current_room仍为start”的稳定路径，并验证十个设施的Area、统一交互候选、全部实体碰撞及PhysicsServer注册不受房间流送影响。原设施框架、交互区域、商店存档、保险柜/背包绑定和角色DIY回归通过。

## 2026-08-21｜99层正式地板与角色承重面对齐

- 99层普通板与铆钉板GLB均采用底面原点，两者共用0.30米结构板；铆钉板的0.395米AABB高度包含0.095米纯表现铆钉/压条，不代表可行走面。
- 99层地板MultiMesh按共同0.30米结构顶面计算Y偏移，不再按各模型AABB最高点独立下压。承重继续由原`TowerFloorStage3D/FloorSupport`的统一平面负责，不修改角色胶囊、碰撞层、楼梯或100层地板。
- `verify_base99_floor_player_collision_flow`覆盖普通/铆钉地板结构面同高、铆钉板0.095米突出表现仍可见、与100层表现高度一致，以及99层中心统一承重碰撞存在且永久驻留。

## 2026-08-21｜ESC全档复位与安全重启

- 共用暂停资产`UI-SCREEN-PAUSE-3D`新增“复位游戏存档”及二次确认；三张3D地图沿用同一按钮，不建立重复UI资产。
- 新增`BaseManager.reset_game_save()`唯一复位入口：先断开旧运行态快照提供者，再写入并回读校验全新`BaseData 2.0`封套；成功后删除旧`.bak/.tmp`，防止主档异常时恢复到复位前进度。写入失败会恢复原内存档和自动存档状态。
- 确认复位后同步清理世界时间、关卡选择、局内命运和空间注册运行态，并返回正式主场景；基地、蓝图、物品、角色外观、时间及当前行动全部归零，独立画面设置保留。
- 新增`verify_pause_game_save_reset_flow`，使用专用测试路径覆盖确认框、Esc优先取消、合法新封套、默认数据、旧备份清除及强制写盘失败回滚，不读写正式存档。

## 2026-08-21｜兔子手枪枪口轴、可见握把与待机姿势

- 修复子弹按真实 `aim_direction` 飞行、枪模却因待机旋转和两层角度后坐向上/向外偏斜的问题：手枪待机取消整枪俯仰/偏航/侧滚；开火时枪身只沿枪轴平移后坐，枪型角度参数继续用于手腕和躯干，不再改变 `MuzzleSocket -Z`。待机与最大后坐帧实测枪口轴—弹道夹角均为0.000度。
- 修复吹风机可见扳机/握把没有落在右手掌球上的问题：从 v003 Blender 源模型读取握把连通件中心，运行 Prefab 将 `VisualRoot` 与全部非Grip语义挂点统一校正 `(0,-0.122838,-0.168785)`；根 `GripSocket`、AssetID、GLB和角色模型均复用。
- 按侧视美术标注纠正右手枢轴：右手模型局部校正后，大球中心、`HandJointR` 与枪械 `GripSocket` 三点重合；圆环仅保留为近端腕部造型。手枪与长枪持枪态均以真实握把坐标刚性对齐，专项测得掌球—骨骼、掌球—握把偏差均为0.00mm。
- 修正 `bunny01 v006` 手枪待机时枪口正对面罩、右手未贴紧握把、左手停在身体下方的问题；`sidearm_hold` 保持胸前右侧低位警戒位置，枪管改为与真实瞄准方向同向。
- 右手继续以现有 `GripSocket` 为唯一主握把；左手从垂落位前伸到胸前，但仍保持自由手和单手枪握持计数。吹风机枪 GLB、角色 GLB、AssetID 与运行时场景均复用，不创建重复资产。
- 仅修改 `PlayerAvatar3D` 表现姿势、右手模型子节点枢轴和对应验收；射击、弹药、伤害、枪口事实源、碰撞、DIY材质与顶层状态机不变。专项覆盖待机、单/双手武器姿势、DIY继承、碰撞隔离及真实 GPU 正面/三分之四/严格侧视骨骼近景。

## 2026-08-20｜基地五米楼中楼、物理楼层、世界时间、恢复与角色衣柜

- 修复L型楼梯v003误删主体几何：新增`ENV-BASE99-STAIR-L-Z5`的`v004`表现输出，从v002的91个可编辑组件重新生成完整踏步、斜梁、平台和导光条，只替换四根转角长扶手并移除四根冲突端柱；不再编辑已合并主体网格。Godot行走碰撞同步收敛为单一`StaticBody3D`下的“斜坡＋平台＋斜坡”，三段顶面齐平并在接缝处重叠0.04米，消除断口和卡人端面。
- 修复基地阁楼东门开启后仍被透明阻挡：根因是5→9米外梯在门槛前仍为上升坡面，角色胶囊会提前撞上完整9米高的99层普通墙碰撞顶沿。现仅在2.2米门洞净宽内将下墙碰撞顶高调整为8.45米，门洞两侧、门扇开关和全部既有门逻辑保持不变；新增真实角色胶囊穿门回归。
- 东侧100F门洞组合既有`RoomDoor3D`和基地滑升门视觉，纳入原有提示、开门、碰撞放行与路线授权链；基地壳体内（含5米楼中楼和外梯内侧）优先判定99F，门槛外天台仍判定100F。
- 基地楼中楼完成面从7米调整为5米；L型楼梯改为`0→2.5→5m`连续双坡面，外门小楼梯改为`5→9m`连续坡面并将中心校正到`x=10.78m`，使坡顶对齐东墙`x=15m`门槛。踏步只负责表现，角色行走由平滑坡面承担；楼梯扶手与平台栏杆增加独立实体阻挡和摄像机净空语义。
- 新增三件v002结构资产与独立运行包装：`ENV-BASE99-MEZZANINE-20X10-Z5`、`ENV-BASE99-STAIR-L-Z5`、`ENV-BASE99-STAIR-EXTERIOR-H4`。没有对旧模型做纵向整体缩放；GLB只负责表现，碰撞与规则继续由Godot包装场景所有。
- 楼层权威从“经过某扇门”改为角色世界高度：`floor_index=max(0, round(-global_y/9))`。门触发继续只处理门和生成事务；从基地阁楼、天台、坠落等非门路径跨层时，HUD、太阳作用域、房间上下文与存档楼层都会按物理位置同步。
- 新增`GameTimeManager + WorldTimeDomain`：游戏从2075-01-01 17:00开始，20个真实分钟为一个24小时游戏日；日期时间显示在雷达下方，太阳方向、昼夜颜色与能量共用同一权威快照，太阳峰值能量为1。
- 基地新增`base_recovery`状态恢复舱与`avatar_wardrobe`角色衣柜，正式设施目录由9项扩为11项。恢复舱按缺失比例消耗基地能源恢复HP和手电；手电在基地只暂停耗电，不再自动充电。基地能源以游戏时间每小时4点恢复，并提供周期扩展接口。
- 新增同场景启动主页：使用当前实际角色与同一玩法Camera做初始正面近景；展示期间锁定移动、战斗和交互，但保留鼠标驱动的角色转向；点击开始后1.15秒无缝拉回玩法镜头，不切场景、不复制角色。主页展示期间完整隐藏玩法HUD，并在角色正上方启用带阴影的冷白聚光灯；点击开始即熄灭该开场专用灯，镜头归位后恢复玩法HUD、原输入锁状态与正常灯光系统。衣柜提供身体、头部、手部、脚部、帽子、眼镜六类方形选项，每类至少3项，纯表现换装即时写入基地存档。
- 调整开场角色控制：开场仍锁定移动、战斗与交互，但不再每帧强制覆盖`aim_yaw`；角色可继续跟随鼠标转向，开始游戏后保留当前朝向。太阳改为同一盏正式`DirectionalLight3D`按时间快照实时更新角度、亮度和颜色；日落由18:00调整为20:00，12:00峰值保持1，17:00仍有明显黄昏直射光，清晨/正午/黄昏分别过渡为橙/白/红色温。
- 修复衣柜显示已保存但重启恢复默认外观：根因是`canonical_json_v2`直接摘要写盘前Variant，武器装配整数槽位键及少量高精度数值经JSON序列化后改变表示，导致整档写入成功却无法通过重载校验。封套升级为`canonical_json_v3`，写盘前统一JSON键并先做内存JSON往返；武器实例入档时同步规范装配槽位；`save_base()`新增写后回读与revision验收。可精确复算旧缺陷校验值的v2档优先定向迁移；其余仅在封套/载荷元数据完全互证且核心类型完整时升级，截断、非SHA-256格式或元数据不一致的损坏档仍拒绝。
- 最终验收：完整非浸泡逻辑集`full 62/62`与Metal/Forward+真实渲染集`visual 17/17`通过；基地模块、100层封顶、灯光关后重开、正式设施摆放与楼梯机位均已覆盖，Godot编辑器解析、启动场景和差异格式检查通过。
- ESC菜单新增“返回基地中心”；仅角色处于99/100层基地安全体积且不在过渡事务时可用，战局中明确禁用。传送复用既有基地出生点与房间进入链，不新增战局逃生功能。
- 99层五件正式设施（远征终端、枪械工坊、保险柜、命运收藏室、自动贩卖机）的表现倍率与场景根缩放恢复为1；交互范围、功能脚本和玩法所有权不变。
- 新增1.50米角色Blender制作母版、九挂点和七槽位规格；迭代两份项目资产Skill，并新增未安装的`player-avatar-asset-standard`草案。3D资产台账新增Skill清单与本轮资产记录。
- 新增`verify_base_overhaul_flow`覆盖结构高度、平滑楼梯、栏杆、物理楼层、时间、能源、恢复、换装、主页和脱困合同；既有基地、塔楼、存档、灯光、相机与3D流程继续参与回归。

## 2026-08-18｜基地99层九件模块正式接入与低楼板摄像机净空

- 按开启的Blender母版补齐基地100层上层围护：本地9—18米使用19块普通墙、北侧中间4块窗墙、东侧1块门墙；其余方向不放窗墙。
- 新增独立可编辑组合Prefab `ENV-BASE100-UPPER-SHELL-30X30-H9`，24块围墙均为稳定子Prefab；18米封顶复用两种5米地板组成6×6共36块，不恢复已移除的99/100层中间楼板。
- 上层组合根生成连续墙体、东侧2.2×2.5米门洞框和屋顶结构碰撞；墙、屋顶、地板、门、楼板、楼梯及基地设施模型统一启用真实投影，99层原有门、设施功能、碰撞及楼层流程不变。
- 从干净Blender母版独立导出两种5米地板、普通墙、带门墙、带窗墙、滑升门、7米楼中楼楼板、7米L型楼梯和2米外门小楼梯，共9个稳定GLB/PackedScene。
- 按Blender母版复核并纠正轴向：楼板、L梯和外门小梯进入基地美术布局 `.tscn`，可像设施一样直接摆放；初始坐标分别为 `(5,0,-10)`、`(-9.58,0,-9.15)`、`(12.74,7,-7.5)`。
- 99层基地为6×6地板网格、14段普通墙、0段窗墙、2段带门墙；窗墙保留为100层专用资产。门只替换动画视觉，锁定、提示、碰撞、寻路和信号继续由原Godot节点负责。
- 100层正对基地的6×6、共36块地砖及承重碰撞已移除，形成99/100层贯通中庭；99层自身地面不受影响。
- 基地结构视觉统一接收光并产生投影；楼板与楼梯Prefab使用随实例移动的简化承重面，L梯两段坡面均低于角色44度上限，避免逐级Trimesh阻挡。
- 楼板和楼梯底部登记`camera_stair_slab`，复用99→98层楼梯间摄像机垂直净空规则；下方立即压低、离开平滑恢复。基地房间触发体同步覆盖二层高度。
- 3D Prefab台账升级至v0.1.16：纠正99/100层使用位置、可编辑结构Prefab和简化坡面碰撞归属；公式错误扫描和全分页渲染复核通过。
- 专项模块、真实楼板下方摄像机、99→98层楼梯摄像机、基地设施框架、设施交互区、Godot导入解析与Metal整体布置截图均通过。

## 2026-08-14｜Forward+高档画质、ESC画面设置与0键性能监视

- 正式桌面渲染器由Compatibility切换为Forward+；高档默认启用TAA、克制Bloom、SSAO、SSIL、SSR、SDFGI、体积雾、距离雾、高质量动态阴影和电影色彩分级。
- ESC共用暂停层新增独立画面设置页；8项纯视觉效果提供独立开关，抗锯齿提供关闭、FXAA、MSAA 2×/4×/8×和TAA六档，设置实时生效并保存到`user://graphics_settings.cfg`。
- 动态阴影与受光玩法强绑定，不提供关闭：保留现有4096图集与滤波为“高”档，并向下提供2048“中”档和1024“低”档；三档始终保留太阳、手电和当前房主灯投影，旧版关闭值强制迁移为高档。
- 新增`0`/小键盘`0`性能监视面板，4Hz显示FPS、帧预算、脚本/物理、渲染CPU/GPU、Draw Call、对象、节点、内存、渲染器和当前AA；不可取得的GPU时间明确显示N/A。
- 高档参数按顶视角战斗可读性调校：辉光不吞UI、AO保留暗部层次、体积雾只建立纵深、TAA抑制移动闪烁；塔楼、基地、独立关卡与训练场共享同一设置服务。
- 针对Forward+重新校准99F单主灯的渲染能量补偿，不改玩法层照明能量与判定；真实30×30m九点覆盖仍为9/9，关灯与重开明暗关系稳定。
- 新增逻辑专项与真实Forward+截图验收；30怪15秒开发预检通过，帧时间P95 20.14ms、渲染CPU P95 0.55ms、Draw Call P95 547、稳定内存跨度1.5MB。完整60分钟Forward+发布候选浸泡仍须重新执行，旧Compatibility长测不得代替。

## 2026-08-13｜第二保险格取出修复与真实物品栏拖拽审计

- 根因确认：物品格刷新通用函数只读普通背包的 `slot`，保险条目却使用 `insurance_slot`；因此第二保险格每次显示电池后都会被改成索引0，点击或拖拽实际去取空的第一格。现按集合类型保留 `slot / insurance_slot`，不再覆写真实索引。
- 将战术物品栏专项从“直接调用移动函数”升级为真实 `ItemSlot` 路由：读取源格索引与 `drag_payload`，执行目标 `_can_drop_data / _drop_data`，再由实际信号进入玩法事务。覆盖背包、两个保险格、两个快捷栏、主副武器、装备背包、配件位与红色世界丢弃区的索引契约。
- 真实重现“小型电池在第二保险格”，验证拖回指定背包格、再拖回第二保险格、右键取出三条操作均成功。
- 同轮修复主动丢弃物与玩家胶囊同帧重叠后立即自动捡回的问题；玩家主动丢弃的地面物获得0.65秒拾取保护，不影响自然掉落物。

## 2026-08-13｜死亡保险物原格返回99F与旧档找回

- 根因确认：死亡结算已把保险物写盘，但错写到只在独立 `BaseMenu` 显示的 `extraction_loot`；正式死亡返城实际重载 `TowerDescent3D` 99F，不会打开该领取面板，新基地运行快照又是空保险格，所以物品存在存档里却表现为消失。
- `BaseData` 升级至1.8，新增专用 `pending_insurance_slots`。死亡时保留原保险格索引、完整物品实例、堆叠数和整枪构筑；99F生成时自动放回原金色格。
- 中转集合的清空与包含恢复格的 `runtime_player_state_v2` 必须同次原子写盘；强制写盘失败时两侧都回滚，下次进入99F可重试，不丢也不复制。
- 兼容1.7旧档：带 `returned_by_insurance` 标记但隐藏在撤离待领取集合中的物品会自动迁入专用中转，在下次基地启动时恢复。
- 最终验收：死亡返还专项通过，完整非浸泡 `full 59/59` 与Metal/OpenGL真实渲染 `visual 15/15` 通过。遵循当前边界，没有启动几十分钟挂机性能浸泡或GPU Profiler。

## 2026-08-13｜掉落物补齐70%基准、武器命运锁定当前尺寸语义

- 根因确认：角色、怪物、设施及角色挂点已经迁移到旧资产70%，但 `GroundLootPickup3D` 仍直接使用历史武器0.82/其他0.72，导致地面物保持旧尺寸。现保留历史常量，并统一乘0.70得到当前武器0.574、其他0.504。
- 自动拾取0.82m触发半径、标签高度和物品所有权事务不随模型缩小，避免为了视觉尺寸降低可拾取性。
- 武器命运表现明确拆为“当前挂点基础 × 命运本地倍率”；“巨大化”2.0在新版等于旧资产140%，不允许重建武器时覆盖挂点回到旧版尺寸。运行快照新增本地/世界尺寸与相对挂点标记，防止后续回归。
- Godot脚本解析、`verify_3d_combat_progression_flow`和`verify_3d_fate_weapon_flow`短专项通过；本轮未运行长测。

## 2026-08-13｜背包与身上装备全交互审计、快捷栏改为真实物品槽

- 根因确认：旧快捷栏只保存物品ID引用，拖入后真实物品仍留在背包原格；快捷槽又被设置为禁止拖出，I界面点击也未接使用入口，因此表现为落点不对应、不能拖回。现废止引用模型，3/4改为两个保存完整物品与堆叠数量的真实槽。
- 背包整组物品会准确移动到指定快捷槽并清空来源格；可在两快捷槽间换位、拖回指定背包格、移入保险格或主动落地。I界面槽、主HUD槽和键盘3/4共用使用入口，效果成功才从快捷槽扣1，失败不扣。
- 运行快照新增 `quick_item_slots[2]`；旧 `quick_item_ids[]` 档首次恢复时从背包原子迁入，避免重复。成功撤离保留真实槽，98F反向撤退清空，死亡按普通未保险携带物结算。
- 同轮审计补齐已安装配件拖红区/界面外落地；主副武器、配件和装备背包的装备、换位、卸回、使用、丢弃与回滚均通过短专项。退出存档时敌人已离树仍读取全局坐标的Godot报错也改用安全本地坐标兜底。

## 2026-08-13｜随身保险格恢复拖拽并明确位置保留契约

- 修复I键战术背包只支持右键保险、却拒绝把物品拖入金色保险格的问题；背包物现在可拖入空保险格，保险物也可拖回空背包格。
- 保险拖拽采用独立来源路由，保险槽索引不再误操作普通背包；保险物可以自由回背包、直接进入兼容装备/快捷栏，也可由玩家主动丢到红色世界区或界面外。
- 保险定义为位置保护而非物品锁：仍在保险格时死亡转基地待领取、98F反向撤退不清除、普通成功撤离原样保留；主动转出成功后立即按新位置规则处理。
- 每次转出使用背包、快捷栏与保险快照，目标不兼容、容量不足或落地失败时完整回滚。短专项覆盖真实UI信号链、回包、装备、快捷栏、主动世界丢弃和所有权守恒；既有撤离/死亡专项继续覆盖长期返还与堆叠数量。

## 2026-08-13｜99F基地照明收敛为单灯

- 根因确认：Compatibility默认每个Mesh最多接收8盏OmniLight；99F旧配置由4盏开关顶灯、3盏美术灯、3个通用设施信标和1个电梯信标形成至少11盏候选，关后重开时灯表排序变化会让主顶灯被地板丢弃。
- 99F改为一盏位于中心的可控投影顶灯，铁境主题能量8.1、范围28.05m，覆盖30×30m主体区；3盏旧美术灯保留历史节点和参数但默认停用，设施及99F电梯信标关闭真实OmniLight、保留自发光外观。没有提高全局灯光上限。
- 真实场景专项取代旧隔离平面测试，断言基地活动OmniLight严格为1、范围≥28m；30×30m九点全部明显增亮（9/9），平均亮度为开灯0.2891、关闭0.2396、重开0.2891。基地设施交互与关卡灯光短回归同步通过。

## 2026-08-13｜天台门可从楼梯内侧开启

- 定位到99F基地门自动关闭后，角色反向爬楼时仍处于99F房间上下文；原交互只查询当前房间门表，无法发现楼梯另一端的天台门，因而形成单向阻挡。
- 为所有已授权垂直楼梯补充反向上端门查询：角色靠近楼梯上端时可看到提示并按 `E` 独立开启；不联动重开基地侧门，不消耗钥匙、不触发命运，也不提交FloorBundle。
- `verify_arrival_gate_floor_bundle_flow` 新增“99F侧门已自动关闭、当前房间仍为99F、从楼梯内侧开启天台门”的专项断言。

## 2026-08-13｜角色体型加减调试入口

- 全局实体尺寸基准调整：角色、全部普通怪/精英/Boss和主基地/99层基地交互设施统一以旧资产尺寸的70%作为新100%；角色完整含耳高度由1.50m变为1.05m。怪物继续叠加物种和变体倍率，基地设施继续保留原世界坐标与朝向。
- 正式3D角色新增 `+ / -` 体型调试键：每次固定按初始基础尺寸增减10个百分点，连续两次放大为120%，不会把当前110%再次乘1.1得到121%；小键盘加减号同样支持，按键长按回声不重复触发。
- 体型变化同步作用于完整角色视觉、武器/背包挂点和独立胶囊碰撞；胶囊中心随高度同比移动，底部继续贴地。玩家根、镜头、准星、手电筒、移动速度和其他玩法数值保持原值。
- 当前调试安全范围为基础尺寸的10%—300%，默认100%，不写入存档；后续转为正式功能时复用 `set_debug_scale_step()` 入口，并另行定义成长来源、持久化与数值平衡。
- 新增 `verify_player3d_debug_scale_flow` 并纳入核心套件，覆盖100→110→120线性档位、减号、键盘回声过滤、上下限、视觉/碰撞同步与镜头隔离。
- 怪物行为专项现覆盖70%全局尺寸与七类相对体型/世界碰撞；主基地9项设施及99层正式设施专项覆盖模型和实体碰撞缩放，并确认交互范围、灯光数值、坐标与功能没有随之改变。
- 尺寸调整登记为 `entity_size_baseline_v1 → v2` 参数迁移；玩家文档保留旧版1.50m/胶囊0.34m与新版1.05m/0.238m，怪物文档保留七类旧有效倍率和70%后的有效倍率，基地文档保留模型、碰撞、交互、标签与灯光的前后倍率。历史值作为回退依据，不得被后续当前值覆盖。

## 2026-08-13｜基地灯关闭后重开不再照亮地板回归修复

- 确认复发原因是性能优化把运行房间内关闭的 `WastelandLight3D` 改成 `visible=false`，覆盖了此前的Compatibility后端规避措施；重新显示后能量、范围和阴影属性虽已恢复，实际地板光照集群可能仍停留在关灯帧。
- 恢复双生命周期策略：用户开关只把灯光能量归零并保留渲染实例；只有房间流送停用时才隐藏灯具。重开继续恢复原能量、范围和阴影，不删除或重建节点。
- 新增Compatibility真实渲染专项 `verify_facility_light_retoggle_visual` 并纳入visual套件，固定地板采样结果为初始0.6454、关灯0.0000、重开0.6454；塔楼灯光综合、塔楼流程和性能运行时短回归同步通过。
- 基地设施摆放权威同步修正：移除运行时重新挂载后对美术布置层的单位Transform重置；设施根的作者位移、旋转和缩放全部保留。验收不再强制根缩放为1或自动面向房间中心，改为逐项比较场景作者Transform在运行前后没有变化。

## 2026-08-13｜楼板、关卡墙与塔楼外墙永久驻留

- 用户反馈50×50m局部楼板仍会产生玩法与受光边界问题，因此停用局部补丁，不再按楼层隐藏任何完整楼板。
- 所有已生成楼板、关卡房间墙体/地面/门框和塔楼外围一圈墙永久可见、投影并保留结构碰撞；房间流送只卸载怪物、家具、灯、交互与其他高成本细节。
- 怪物太阳直射继续使用物理射线，但遮光几何与物理碰撞现在永久一致，避免画面处于阴影而AI误报太阳照射。
- 正式美术替换冻结为双层资产策略：视野内显示正式高模，视野外隐藏高模并使用当前低模建模做代理；低模结构代理、阴影和碰撞不得隐藏。
- 正式高模的视野外显隐必须只作用于高模子层，禁止向父节点传播并连带隐藏低模结构代理。
- 楼板专项改为验证“任何显隐调用都无法关闭完整楼板/外圈墙、局部补丁始终关闭”，并新增 `DATA_ONLY` 下生成墙 Mesh、投影和碰撞逐项检查；塔内真实60°太阳新增上层楼板遮挡怪物受光回归。
- 后续分钟级/小时级浸泡与目标设备GPU Profiler移至独立发布/CI步骤异步执行；交互开发任务不再启动或持续轮询长测，只运行短专项、核心回归与性能预算。
- 修复98F阴影中怪物误显示“太阳”并执行持续伤害：太阳判定改为身体中心必须直达太阳且三点中至少两点暴露；单点斜射线穿过楼梯洞、门洞或碰撞接缝不再误触。没有增加任何按楼层禁用太阳的规则，其他楼层开窗、破墙和露天井的真实太阳仍可生效，并以“两点穿窗”专项锁定该玩法契约。
- 继续以玩家实测种子定位最终根因：性能流送曾把非当前楼层stage父节点设为Disabled，造成楼板Mesh继续显示/投影、子级静态碰撞却退出物理空间。楼板承重体、外墙和房间结构PhysicsBody现固定为`PROCESS_MODE_ALWAYS`；远层继续停用脚本与高成本细节，不牺牲结构遮光。原回归也已修正为真正进入98层后检查紧邻99层楼板，避免楼顶碰撞兜底造成假通过。
- 修复敌人死亡碎片复用投射物时，上一任已释放发射者在碰撞例外列表中留下null占位并触发`body is null / rp_node is null`运行报错。
- 清理再次残留的退役2D `TrainingRange.tscn / Bullet.tscn`及Godot自动恢复的旧2D场景标签；前者引用已删除的`TrainingRange.gd / Player.tscn`，会在保存时触发“实例或继承场景依赖存在问题”弹窗。编辑器恢复入口现只保留正式`TowerDescent3D.tscn`，3D-only结构门禁重新通过。

## 2026-08-13｜唯一精英、三套Boss与发布缺口收口

- 新增全局`EliteRosterService`并把存档升级至`BaseData 1.7`：固定12只稳定唯一精英，建立跨局预约/确认/结算、陈旧预约清理、成长、逃脱、死亡、悬赏与夺械内容转译的服务层骨架；12套`elite_behavior_id`进入通用行为专项。当时尚未代表12只均已完成正式游戏内逃脱与成长闭环，首只闭环于2026-08-27补齐。
- 95/90/85层分别接入“深渊档案官 / 熔炉狱监 / 空洞合唱团”独立内容ID、正式GLB、三阶段技能袋、竞技场GLB及8/6/5组匹配掩体碰撞。修复后续Boss仍复用95F `extraction` 房间ID、导致跨层走廊连回旧竞技场的问题；95F保留兼容ID，90/85F使用逐层唯一ID。
- 新增真实塔楼三区段验收：连续提交98—95、94—90、89—85全部物理层，核对三套Boss内容后按6/11/16边界顺序释放旧段；不再只用首段推断后续区段。
- 补齐`flashlight_charge_up / flashlight_low_battery / flashlight_depleted`三条44.1kHz双声道OGG及WAV母版；运行音效合同现为36/36、无缺失、无非OGG、`mobile_safe=true`。
- 修正99F基地自动贩卖机、远征情报终端和枪械工坊朝向，Metal正式摆放验收通过。
- 修复`WeaponInstance.from_item()`只释放装配树根、遗留未入SceneTree子弹节点的问题；改为递归释放整棵`AssemblyNode`数据树，复跑退出日志不再出现ObjectDB/resource清理提示。
- 资产台账新增3 Boss、3竞技场、3手电筒音效共9条稳定AssetID、哈希和版本记录，公式错误扫描为0；Boss与音频均先通过四键查重门禁再制作。
- `verify_ai_performance_soak`发布候选默认时长由30分钟提高到60分钟，并连续切换98—95/94—90/89—85三套Boss内容；兼容层Metal无GPU时间戳时继续如实输出`gpu_timing_available=false`，不以CPU或墙钟伪造GPU数据。
- 60分钟RC已完整执行：墙钟P95 19.84ms、渲染CPU P95 2.52ms、内存稳定跨度7.9MB，但单区段节点跨度66超过64门槛，故报告保持失败而不伪造通过；目标设备GPU门禁脚本会在GPU时间戳缺失时直接失败。
- 最终核心套件40/40通过；另修复`ItemUseHandler`静态Node未进入SceneTree导致的最后1个ObjectDB/resource退出残留，详细退出复验已清零。
- 用户在约6分钟时人工中止补充长测；复核残留测试进程为0，但没有落盘中间采样报告，因此该次不判通过或失败，既有1800秒正式浸泡结果不变。

## 2026-08-13｜怪物AI与运行时性能模块收口

- 完成统一怪物AI调度：视觉/近距/声音/受击/手电/房间灯/太阳/盟友事件进入有界刺激记忆；目标按房间、楼层和生命合法性筛选，并以15%迟滞稳定切换。
- `Enemy3D`收敛为12态执行器，加入ACTIVE房导航面、按需`NavigationAgent3D`、本地避障和0.8秒卡住恢复；近战/远程每目标各2个攻击令牌，30怪每16ms最多8次重感知、110ms缓存错峰。
- 六种普通怪专项行为完成：近战突进、远程三连/后撤/横移、召唤+最低血盟友治疗、正面护盾、主动爆炸与死亡碎片分离、真实光照/近距揭示和暗处重新埋伏；通用Boss使用确定性技能袋并保存阶段/技能进度。
- 新增16m空间桶弱引用注册表，统一AI、局部灯、太阳与连接器近场查询；释放节点自动注销，避免历史楼层全表扫描和freed-object引用。
- 房间接入`DATA_ONLY / PREFETCHING / SHELL_READY / ACTIVE / HIBERNATING`五态；远房怪物与地面物转纯数据，稳定ID、HP、伤害、AI/Boss状态、灯/容器状态和掉落可无复制恢复并写入JSON行动检查点。
- 新增运行时性能管理：前台60FPS、失焦15FPS，`high / balanced / low`控制雾、太阳/房间阴影距离与手电采样；塔楼平时只渲染当前物理层，楼梯过渡最多上下两层，关闭局部灯从渲染列表移除。
- `ItemModelIcon3D`移除冗余WorldEnvironment/填充灯/包装节点，预览节点23→11；基地根去除冗余节点，初始世界节点和完全探索节点均显著低于预算。
- 新增`verify_monster_ai_system_complete`、`verify_performance_runtime_complete`与默认30分钟的`verify_ai_performance_soak`；当前核心36/36、Metal/OpenGL可视14/14与运行时主体1800秒30怪正式浸泡通过，收尾修复由最终专项和15秒真实渲染回归覆盖。正式长测墙钟P95 19.75ms、渲染CPU P95 1.87ms、稳定期内存跨度3.6MB、节点跨度18；Compatibility-over-Metal未提供GPU时间戳并已如实标记unavailable。
- 修正测试套件的renderer场景分类，避免资产截图场景误入headless；运行时存档读取房间灯状态改为O(1) getter，不再在退出边界调用重量级整房快照。
- 受光传感器跳过typed缓存中的已释放太阳对象；测试看门狗同步回收内部sleep，专项退出不再等待完整超时或留下孤儿等待进程。
- 同步AI、性能、测试、完成度与怪物施工文档；明确P0/P1 AI运行时已完成，12只唯一精英跨局服务、逐五层独立Boss内容和发布候选级60分钟/连续3区段Profiler仍是后续项目。

## 2026-08-12｜战斗楼层跨重启恢复与种子校验

- 运行态快照升级为 `runtime_player_state_v2`，新增 `tower_world_state_v1` 保存已提交楼层、布局ID、门和房间访问/清理进度；恢复时先按原种子重新提交 `FloorBundle`，再恢复房间与玩家位置。
- 修复场景初始化先落到99F、恢复时只标记楼层生成却没有实例化房间，以及场景退出阶段读取失效世界变换覆盖正确快照的问题。
- 保存时用实际楼层高度和房间范围校正旧房间标签；房间与坐标矛盾时回退安全点，不再把角色放入99F空旷区域。
- `FloorPlanGenerator` 的1000种子×4层确定性测试和真实98F磁盘重载恢复共同验证同一行动种子生成相同 `layout_id`。

## 2026-08-10｜楼梯间上下楼板相机避让

- 通用与屋顶楼梯导入碰撞将 `UpperFlight_Walkable / LowerFlight_Walkable` 明确标记为上下两块相机楼板；角色行走碰撞保持原样。
- 固定斜俯视镜头新增楼梯专用垂直净高探针：期望位置碰到任一斜楼板时立即向下夹紧到楼板下方，离开后平滑恢复；水平后移、朝向、FOV和既有南墙收镜逻辑不变。
- 普通房间楼板、走廊、门与未标记碰撞不会触发下压；结构、动态隔离、真实楼梯相机与Metal/OpenGL楼梯画面回归通过。

## 2026-08-10｜基地初级棒球棍与统一枪械配件槽

- 基地自动贩卖机新增45魂初级近战“废土棒球棍”，具备独立WeaponInstance、1.48m程序模型、三段快速挥击及第三段强化反馈；固定货架扩为7件，小型电池稳定ID同步为`item_battery_s`。
- 主/副武器装备栏各显示固定六槽：瞄具、枪口、弹匣、枪托、战术、特性。所有枪位置一致，仅开放兼容子集，不支持位置保留并禁用。
- 普通配件支持背包拖入、点击或拖回拆卸、原子替换与失败回滚；非激活副武器可独立管理且不会强制切枪。
- 整枪进入背包、落地、保险或存档时，完整`assembly_snapshot`和全部配件继续跟随同一`weapon_instance_id`；WeaponInstance升级到schema v2并迁移v1旧`MOUNT`普通配件。
- 普通可拆配件与命运递归附件分层校验，塔罗“配件寄生”继续走卡牌指定内部槽，不受公开枪型兼容矩阵影响。
- 新增`verify_weapon_attachment_inventory_flow`，训练场扩为18货架/59组合；资产台账v0.1.8和内容数据库同步完成，公式错误扫描与渲染复核通过；`core` 32/32通过。

## 2026-08-10｜大型近战武器与三段动作状态机

- 新增巨型工业断刃与攻城裂甲斧两把大型近战武器，复用正式 `WeaponInstance`、主/副武器槽、背负、地面物、背包、商店/保险与存档链路；近战根不再自动挂标准子弹。
- 玩家八态移动机保持不变，新增 `ready → windup → active → recovery` 近战动作子状态机。两把武器均有三段不同前摇/命中/后摇，支持输入缓存和第三段终结。
- 近战命中统一执行距离、水平扇区、墙体遮挡和单攻击目标去重；伤害、暴击与击退走目标公开接口，受伤、冲刺、坠落、锁定、死亡和换武器会可靠取消。
- 从资产台账检索并复用 `VFX-COMBAT-KIT-3D`，扩展无碰撞、对象池化的 `slash / melee_impact` 两类参数化表现；三段连击按方向、尺寸和颜色递进，第三段反馈最强。
- 新增 `melee_swing / melee_impact` 两组44.1kHz母版与版本化OGG。每段主动窗口只播放一次挥砍音，每个目标生成命中特效；一次挥砍命中多目标时冲击主音只播一次，敌人受击/暴击层仍逐目标保留。
- 新增两件版本化程序原型资产、重型双手持握与三阶段动作表现，并同步游戏内容数据库、资产台账、状态/动画表、测试与完成度文档。
- 新增 `verify_3d_melee_combat_flow`、`verify_3d_melee_feedback_flow` 与真实渲染的 `verify_3d_melee_combat_visual`，并将近战实例、状态、命中、中断、VFX/音频去重和大型模型尺寸纳入核心回归；随后加入棒球棍与配件专项，3D训练场最终扩展为18个货架、59种合法远程/近战组合，`core` 32/32通过。
- 完成 3D-only 结构收口：删除最后两个已退役的 `Bullet.tscn` 与 `TrainingRange.tscn` 2D 场景，3D 子弹和训练场不受影响。

## 2026-08-07｜魂经济与怪物血条同步

- 玩家可见货币名称统一为“魂”：基地、99层、贩卖机、撤离结算和局内 HUD 不再显示“基地币”。`extraction_points` 继续作为旧档兼容字段名，成功撤离将拾取的魂写入该持久化余额。
- 怪物死亡不再直接增加货币或弹出黄色数字；基础掉落、精英悬赏和额外货币均装入死亡点的魂球，只有拾取魂球才入账。清房也不再额外直接发魂。
- 修复房间生命修饰器只提高最大生命却未同步当前生命/头顶血条的问题；修饰器现在保持生命比例并立即刷新血条。
- 深度修复头顶血条生命周期：怪物读取真实种类后重建相应宽度，防止默认怪条宽残留；专项验收覆盖满血、半血、生命修饰器和怪物转身后仍然独立面向摄像机。
- 血条渲染收敛为单一 Sprite3D 纹理：底框和填充同图重绘，移除两个独立 Billboard 平面，杜绝红色填充在镜头转向时越出框体。

## 2026-08-07｜基地边界与敌人战斗反馈

- 99层基地的西、东交通门改为按 `E` 独立开启，角色完全跨出门槽后自动关闭门板与碰撞；路线授权不随门板回关撤销，楼梯下端到达门仍能正常交互。
- 开火锁定从房间进入事件中拆出，按基地真实室内空间持续判定：只有99层基地屋内不能开火；楼顶、楼梯、入口大厅和所有战斗区均可开火。
- 全部3D怪物新增头顶血条，并将体型按物种明确分层；视觉、碰撞和血条锚点同步缩放，Boss仍保留更宽的头顶条与屏幕总血条。
- 新增3D伤害飘字：普通/重击/暴击分别使用珊瑚红、暖橙与金黄星标，采用HUD同系深蓝描边、弹出上浮淡出动态；未实际扣血的格挡不显示数字。
- `verify_arrival_gate_floor_bundle_flow` 现覆盖基地双门、自动关门与路线授权分离、室内禁射边界；`verify_3d_enemy_behavior_flow` 覆盖种类体型、普通怪血条与伤害飘字。
- 根据实机反馈，敌人根缩放收敛为小型0.8、普通1.0、大型1.2、Boss1.5；伤害飘字取消固定屏幕尺寸，改用高分辨率字形与较小世界像素比例，避免放大后模糊和过大。
- 敌人头顶血条改为短款圆角条，世界坐标锚定且每物理帧朝向摄像机，不再继承怪物转向。
- 伤害飘字换为粗等宽的终端科技字体（SF Mono，跨平台回退 Menlo/monospace），普通/重击/暴击字号统一提升至上一版的150%，并保持高分辨率 MSDF 字形以避免放大模糊。
- 头顶血条收敛为与角色 HUD 一致的简洁深色底框 + 红色填充平面，移除圆角端帽与强调线；根节点脱离怪物旋转层级，平面材质永久朝向摄像机。

## 2026-08-07｜界面、音效、搜刮、出生与死亡体验统一

- 将基地可开枪范围回写为正式空间契约：仅99F室内禁射，门外/走廊/楼梯/天台/关卡均可开枪，门表现与禁射逻辑彻底分离。
- 全部基地设施和局内管理界面统一到主HUD设计语言；角色包裹保持正方形图标格，贩卖机改为商品卡网格并与I键背包同源。
- 核对提供的音效源文件，新增31个版本化OGG运行资产；桌面/Android统一路径，禁止回退旧合成音与WAV。
- 搜索改为有进度、可离开取消；容器/怪物非货币物品最多单件且地面`count=1`，击杀魂只生成地面魂球。
- 道具按功能类型使用高辨识度固有色；新档首次天台、完成新手后基地中心出生，BaseData升级1.4并兼容旧档。
- 新增死亡受击方向击飞、一次落地回弹、侧倒和点击确认返基地流程。
- 新增`verify_requested_experience_upgrade_flow`并复验背包、贩卖机、保险柜、FloorBundle和运行安全。

## 2026-08-06｜成功撤离返航99层并保留全部战利品

- 修复塔楼普通撤离点成功后重载 `TowerDescent3D`，导致角色回到100层天台且当前背包清空的问题。
- 成功撤离现在保持同一运行场景和所有权实例：I键背包、主副武器、装备背包、快捷栏与保险格不清空、不复制；本轮战斗楼层复位后角色进入99层 `facility` 基地房间。
- 死亡、98F反向撤退、普通成功撤离拆为三套明确结算；只有死亡和反向撤退应用各自损失规则。
- 修复死亡保险格只有“判定保留”却没有长期落点的问题；保险物原子写入基地待领取集合，写盘成功后才清空运行时保险格，完整枪械实例ID与构筑保持不变。
- 修复堆叠物存入保险格后数量退化为1的问题；保险槽现在保存完整堆叠数量，取回背包空间不足时整笔回滚。
- 新增 `verify_tower_extraction_return_flow`，覆盖成功返航位置、背包/装备/保险实例守恒，以及死亡时保险物保留、未保险物掉落和长期返还。

## 2026-08-06｜修复99层设施与I键背包数据源分离

- 修复保险柜和贩卖机错误读取 `pending_loadout_items`，导致 I 键当前背包已有物品但两个设施显示为空的问题。
- `TowerDescent3D` 打开设施菜单时显式注入当前 `_inventory`；保险柜右栏逐格读取真实槽索引，贩卖机购买/出售也直接作用于同一个 `InventoryModule`。
- 独立主基地没有行动库存时仍安全回退为“下局带入”，界面明确区分两种所有权，不再都叫随身背包。
- 新增完整格位快照/恢复用于交易回滚；`verify_tower_facility_inventory_binding` 按“先在I键背包放两件，再依次打开保险柜和贩卖机”的玩家路径通过。

## 2026-08-06｜保险柜格子转移、无限库存连续购买与魂显示

- 保险柜改为“长期保险柜 / 12格随身背包（下局带入）”左右格子界面；空格、物品落点和容量均可见，单击与拖拽共用同一个双集合转移事务。
- 转移时消耗品优先按 `stack_max` 合并，枪械和装备保持独立实例；目标容量不足或写盘失败时两侧同时回滚，不复制、不丢失。
- 自动贩卖机购买默认进入随身背包，不再受2格保险柜限制；五类货物均为无限库存，可连续购买，治疗药水连续购买会形成5+1等可见堆叠。
- 出售栏同时列出随身背包与保险柜并标明来源；堆叠物按整组数量结算，枪械保留二次确认。
- `extraction_points` 保留为兼容存档字段，玩家显示名统一为“魂”；余额在贩卖机、主基地HUD和塔楼主HUD常驻显示，并在成功撤离时承接局内拾取的魂。
- `verify_base_shop_save_flow` 与 Metal/OpenGL 实际界面检查覆盖连续购买、堆叠、双向转移、保存失败回滚、货币显示和格子布局。

## 2026-08-06｜存档封套、自动贩卖机与基地货物清单

- `BaseData`升级为1.3；基地档新增revision、保存原因、canonical JSON SHA-256校验、128笔有界事务日志与已验证行动检查点槽，1.2裸档及开发期旧摘要封套可受限迁移。
- `AtomicJsonStore`读取新增内容验证器；主档可解析但checksum错误时继续尝试`.bak`，避免把损坏内容当有效档，也避免静默空档覆盖。
- 内容数据库的`武器/掉落物品`新增基地买价、卖价、上架、库存规则、货架顺序；新增`基地商店`货物清单，5个货架条目用公式回查物品事实源。
- 基地增加第九设施`base_vending`：常备豌豆手枪、散射喷壶、步枪、2格轻型腰包和治疗药水。购买生成独立物品ID，枪械另生成永久枪械ID；当前版本默认进入随身背包，出售按数据库卖价与稳定实例移除。
- 购买/出售以事务ID幂等提交，资源、物品所有权和日志只保存一次；模拟写盘失败会完整回滚，重复事务不重复扣款、发物或收款。
- 新增左右买卖双栏商店UI，商品预览复用背包`ItemModelIcon3D`；枪械出售二次确认，资源与保险柜容量常驻，Esc退出。
- 自动贩卖机使用程序基础网格制作长方体机柜，含实体碰撞、正面货窗/屏幕、青色灯带和橙色取货口；主基地与99层基地均固定在出口侧墙边并避开门洞。
- `verify_base_shop_save_flow`、`verify_base_vending_visual`、九设施框架与基地流程通过；内容数据库和资产台账完成查重、公式错误扫描及修改后渲染复核。

## 2026-08-06｜可装备背包、动态容量与背部表现

- 新增轻型腰包、战术背包、远征背包3件独立装备，分别提供2/4/8个扩展格；进入搜索、精英和Boss掉落权重，内容数据库同步为35项正式物品加1项Boss专用钥匙。
- I键角色装备页新增专用背包槽；背包可左键或拖拽装备，可拖回基础空格、拖到丢弃区或界面外。容量显示为基础12加装备容量，扩展格使用独立青绿色边框。
- 更换或卸下背包时按旧格序稳定保留容量内物品，超出容量的整格物品逐项生成在当前房间；专项验证20→14→12缩容、物品总量守恒，无复制和静默删除。
- 玩家视觉根新增独立 `BackpackSocket`；2/4/8格背包以代码Mesh占位并区分体积、颜色与附袋数量，与地面物和3D图标复用同一模型工厂，不增加玩法碰撞。
- 美术资产台账新增 `CHR-PLY-CAPSULE01-BACKPACK-SOCKET-3D` 与 `ITM-EQUIPMENT-BACKPACK-3D`，角色组件表同步挂点路径；后续正式模型可替换程序占位而无需改动玩法ID或容量事务。
- 成功撤离会带出已装备背包本体；98F撤退会清除它并把容量恢复为基础12格。新增专项进入core；本轮 `core` 22/22、`full` 56/56及背包装备真实渲染场景均通过。

## 2026-08-06｜98F撤退后的关卡与到达门完整复位

- 修复撤退后二次进入98F时“门存在且已开启，但门洞仍有空气墙”：重建入口壳体前先重新规划基地与入口共享的5m门槽，再据此创建墙体、碰撞和楼梯接驳，避免新门使用默认偏移而实体墙仍留在规划通道。
- 到达门专项新增二次重建的接驳点/实体门洞坐标一致性检查，并在开门后的物理帧直接射线穿越门洞；门碰撞、错位墙模块和旧楼梯围护任一残留都会使验收失败。
- 修复确认撤退只传送回99F并清物品、却保留98F FloorBundle和 `_vertical_arrival_open` 的问题；该残留会让玩家再次从基地返回时看到下端到达门已开启，并跳过首次进入封门。
- 撤退现在销毁首门开启后生成的98–95F房间、走廊、Stage、敌人、掉落、门状态和运行缓存，恢复楼顶/基地/98F入口壳体3房、2段楼梯及未提交楼层状态；保险格继续保留。
- 再次返回98F时下端门关闭，重新交互才提交98F FloorBundle，进入安全屋后首门再次关闭；`verify_arrival_gate_floor_bundle_flow`已增加完整的“进入→撤退→回基地→再次进入”循环断言。

## 2026-08-06｜48张命运塔罗运行时与正逆位翻牌

- 修复正式卡池仍显示旧功能名的问题：现有48张可玩卡按稳定ID迁移为对应塔罗名，旧名只作为存档迁移别名；所有选卡、占卜、工作台、收藏和枪械悬停共用同一套名称。
- `FateCard`新增阿尔卡那、花色、正/逆位、方位随机值和效果快照；每个卡位独立50%/50%判定，正逆位共享卡名、稳定ID、稀有度与作用域。
- 正式3D三选一使用纯代码卡背与分段翻面：0.10秒起按卡位错峰，薄边时换面；按最新规则，逆位整张正面卡牌连同边框、图案、卡名、说明和全部布局共同旋转180°，说明内容替换为逆位效果；完成前禁止点击，Esc和减少动效路径可用。
- 局前占卜、工作台、旧房间模式和通用命运面板同步接入方位；局前保留卡与枪械永久命运槽保存方位、随机值及应用时效果参数，换枪/背包/存档不丢失。
- 新增`verify_tarot_fate_runtime`并加入core；48张正逆位双向执行、100000次概率分布和Metal/OpenGL翻牌视觉通过。78张目标中的新增30张仍不进入可玩池，避免出现只有文字没有玩法的假卡。
- 最新自动化结果为 `core` 21/21、`full` 55/55；Godot编辑器解析、工作簿公式错误扫描与代码差异检查均通过。

## 2026-08-06｜主副武器背部挂点分离

- 将原本位于背部中线的单一动态收纳位置拆成两个稳定语义挂点：主武器槽0位于角色左背，副武器槽1位于右背；切枪后非激活枪自动回到其所属侧。
- 背包与两把武器现使用三个同级独立挂点：背包居中，主武器竖挂左侧、副武器竖挂右侧；枪口统一朝下、枪身朝后，挂点下移并向背后推出，避免占用背包空间或挂到耳朵位置。
- 不新增枪械资产，不改变 `WeaponInstance`、伤害、碰撞或切枪事务；复用 `CHR-PLY-CAPSULE01-WEAPON-SOCKET-3D`，资产台账补充两个子挂点和v0.1.1记录。
- 双枪逻辑、角色DIY、动画、持枪碰撞、1.5m轮廓共5项专项通过；Metal/OpenGL背面固定机位截图通过。

## 2026-08-06｜I键背包恢复与全工程深度回归

- 修复背包快捷键长按回声事件重复触发：`I/Tab` 一次按下只切换一次，不再出现界面刚打开又被键盘重复事件关闭；打开/关闭继续与玩家输入锁成对同步。
- 背包专项改为真实发送 `I/Tab` 按键，并验证普通地牢、塔楼、长按重复、二次关闭和玩家控制恢复；战术装备页以真实I键打开并完成Metal/OpenGL截图复核。
- 同步修复三类过期验收：物品格模拟点击补齐按下+释放、探照灯按实际低能耗配置验收、塔楼相机/视觉用例先经到达门生成98F并只在95→94楼梯间采样唯一电梯。
- 本轮结果：`core` 20/20、`full` 54/54、`visual` 13/13；脚本解析和差异检查通过。退出阶段仍有单个资源引用告警，已记录为非阻断清理技术债，等待长时热浸泡专项定位。

## 2026-08-06｜78张命运塔罗与正/逆位设计

- 命运卡目标总量冻结为78张：22张大阿尔卡那 + 56张权杖/宝剑/圣杯/星币小阿尔卡那。
- 星星/月亮/太阳仍是枪械/角色/世界所有者，目标分布为36/21/21；阿尔卡那与花色是内容编组，不取代作用域。
- 现有48个效果迁移为对应塔罗卡的正位基线，新增30张补齐宝剑、圣杯和星币牌组；旧存档按稳定ID迁移为正位，不重投。
- 78张卡每次出场独立50%正位/50%逆位，同名同ID；方位由行动种子和选择事务确定，关闭重开不重投。
- 本条最初规定逆位只倒置图案/框体并保持文字正向；同日后续用户确认改为“整张正面卡牌连同文字与布局共同倒置，说明内容替换为逆位效果”，最终规则以上方运行时条目和牌组文档为准。
- 新增[命运塔罗牌组](../14_技术施工_命运塔罗牌组.md)，内容数据库同步全78张正/逆位功能、概率、翻转UI与施工状态；本轮不将未施工内容标记为可玩。

## 2026-08-06｜双武器、快捷物品、大地图与98F循环边界

- 命运三选一新增Esc放弃；星星卡目标枪满槽时改为同卡二次点击确认兑魂，普通/稀有/史诗/传说/神秘分别兑20/40/70/120/180魂，不写入枪械。
- 所有楼层到达门不再触发命运选择。98F首门在玩家实体进入后关闭；从安全屋反向离开为撤退，二次确认后清空背包、主枪、副枪与快捷引用，保险格保留。
- 装备系统扩展为左主枪/右副枪两个独立 `WeaponInstance`；1/2切换，弹药与构筑随实例回写，非当前枪以同源 3D 模型挂在角色背后。
- I界面新增两个主动物品快捷槽；3/4使用，HUD复用背包的 `ItemModelIcon3D`显示图标与数量，效果成功才扣数量，空槽不创建3D SubViewport。
- K键武器装配图改为屏幕居中；M键新增全层大地图，以整层坐标显示已探索房间、通道和玩家位置，M/Esc关闭。
- 新增 `verify_dual_weapon_quick_map_fate_flow` 并纳入core；到达门专项增加不弹卡、首门封闭和撤退清空验收；正式 HUD/命运/大地图真实渲染通过，core 20/20、性能预算通过。

## 2026-08-06｜到达门逐层生成、95→94唯一电梯与区段隔离设计

### 基地门、敌人数值与玩家中心雷达修复

- 修复100→99基地入口被误送入战斗FloorBundle校验的问题：普通基地交通门不再读取物理层1规划；Boss上端门也不再提前提交下一层。
- 门用途统一归纳为基地交通、楼层到达、普通进度、Boss下行、隔离前门和普通垂直交通六类，并把分类计数写入塔楼诊断快照。
- 普通怪最终生命统一×3，Boss最终生命×10；所有怪物移动速度降至旧值70%；Boss在原体型上再×2，碰撞同步，并新增头顶3D生命条。
- 圆形雷达改为玩家固定中心、地图随玩家反向移动；删除玩家方向延长线与扫描射线，房间、通道、敌点按圆形内容边界隐藏或裁切。
- 到达门、敌人行为/数值、战术小地图专项及真实渲染小地图截图通过；整体smoke 5场景通过。

### 施工与验收完成

- `TowerDescent3D` 改为真正的按需节点生命周期：启动仅有楼顶、99F基地和98F入口壳体3房；到达门提交当前层、下一真实楼梯和下一入口壳体，不再隐藏预建98–95F。
- 95F Boss 后增加独立15×15下行大厅、专用下行权限、95→94唯一楼层电梯和15×15双门隔离间；确认框默认取消。
- 跨过隔离前门后卸载98–95F共65个房间及相关走廊、楼层壳、碰撞、敌人、掉落和房间运行缓存；专项验证未拾取地面物销毁且玩家钥匙保留。
- 新增 `verify_arrival_gate_floor_bundle_flow` 并纳入core；结果为初始3房、首段生成69房、6段垂直连接、旧段卸载65房。`smoke` 5场景与 `core` 19场景全绿，4000份纯数据计划性质测试通过。
- 尚未完成行动快照跨重启恢复、连续3区段RSS/热浸泡和真实渲染人工巡检，文档不把这些项目标为完成。

- 冻结新的逐层运行循环：初始只常驻99→98楼梯、98F安全屋壳体和到达门；交互N层到达门时，在门保持关闭的前提下生成并验证N层整层、N→N-1真实楼梯和N-1入口安全屋壳体，成功持久化后才开门。
- 明确98–95F为开局特殊Boss区段；后续94–90F、89–85F等按五个战斗楼层构成Boss区段，Boss仍出现在楼层号为5的整数倍的楼层。
- 全游戏关卡内电梯唯一固定在95→94楼梯间；普通楼层、房间、安全屋、支路及其他Boss后的楼梯间均不得生成电梯，99F基地接口不计入该规则。
- 95→94楼梯后增加15×15m双门隔离间；后续90→89、85→84等Boss区段边界复用相同隔离提交结构但不带电梯。两门硬互锁，玩家完整入内且后门关闭锁定后才进入不可逆区段提交；生成、保存或卸载失败时前门保持关闭并可重试。
- 隔离前必须二次提示“无法返回、旧区段未拾取物永久丢失”，默认选择暂不进入。提交后销毁自然掉落、玩家主动丢弃物、已生成未拾取容器物和未领取奖励；装备、背包、保险格中的物品保留。
- 区分房间流送与区段卸载：提交后98–95F的Node、碰撞、导航、敌人、掉落、门、VFX/音频、小地图缓存和运行引用必须彻底释放，不能只隐藏Stage。
- 本条是该日上午的设计冻结记录；同日后续施工已由上方“施工与验收完成”条目取代其未施工状态。
- 本条取代2026-08-04/05记录中“每个Boss后都有阶段电梯”及“安全屋前门作为最终seed gate位置”的未来目标；那些条目只保留为当时实现历史。

## 2026-08-05｜性能发热现场检查与优化文档

- 新增独立[性能优化与热管理](../13_技术施工_性能优化与热管理.md)，建立 CPU/GPU、物理查询、刷新频率、长时热浸泡和工具进程退出契约。
- 实机发现14个已运行约4天21小时的孤儿 Godot `diag_wall_v2/diag_test` 进程，合计约71% CPU；正式调试游戏停止后编辑器仅约0.7% CPU，确认工具进程泄漏是本次发热首因。
- 用户确认后精确清理14个孤儿PID；清理后及core结束后诊断/测试残留均为0，未影响Godot编辑器。
- 塔楼流送新增O(1)状态接口与加载集合脏标记，普通帧不再扫描完整房间快照或重写66房/Stage状态。
- 视野表现采样15Hz、目标显隐25Hz，删除不绘制近距圆盘的29条无输出射线；镜头平滑保持60Hz，物理探针为移动60Hz/静止30Hz；计时1Hz、小地图15Hz、门提示12.5Hz。
- 关灯时停止三盏随身灯的逐帧变换写入；开启瞬间同步并恢复逐帧跟随。项目显式锁定60FPS和VSync。
- 测试套件增加180秒看门狗与退出/中断精确子进程回收；性能专项为`16.69ms/18ms`的60FPS墙钟节拍、稳定120帧视野重建0次，core 18/18通过。
- 五层Stage/阴影/雾质量档、失焦15FPS、真实GPU P95和30/60分钟热浸泡保留为性能第二阶段。
- 本轮只完成诊断和文档，不擅自停止用户进程或实施玩法代码优化；P0施工顺序已加入完成度清单。

## 2026-08-05｜EVENT 空房锁门与透明阻挡修复

- 修复 EVENT 房无怪却显示“战斗未结束/先清理房间”的状态误判；未结算事件现在明确引导玩家前往紫色光柱按 E 使用终端。
- 必做事件终端由贴墙位置移至房间中部安全区，增加纯代码地标、光柱和常驻目标标签；事件终端取消角色实体碰撞，只保留交互范围，避免不可见模型形成透明阻挡。
- 增加目标完整性修复：事件终端节点丢失自动重建；仍无法实例化时安全解锁；非战斗事件已记录结算但清场位丢失时自动恢复；诅咒/召唤事件单独进入事件敌群修复链。
- `verify_door_passability` 现为15项通过：130扇门基础契约不回退，并新增 EVENT 可见目标、无透明阻挡、错误提示、节点丢失与状态自愈验收。
- `core` 18/18通过；塔楼闭环保持3505节点，性能专项完全探索场景`3550/3600`、持续帧耗时约`6.88ms/16ms`。

## 2026-08-05｜楼层、关卡模块施工与验收

- 新增纯数据 `FloorPlanGenerator`，与场景树解耦；按种子、楼层、入口侧和Boss规则输出稳定 `layout_id`、房间树、房型、面积预算和验证报告。
- 正式98–95F普通层改为14个内容房：10房必经主路、两条奖励支线/4个支路房，另有15×15m入口/出口安全屋；种子选择南/北外围空间排列，并组合30×25、40×25、30×40、35×30、40×35房型。
- 当时实现为每层安全屋前门接入 `floor_seed_gate`；该门位已被2026-08-06的“楼梯间到达门”目标取代，但作为实现历史保留。
- 面积预算纳入250×250m总面积、0.30m外墙、65m核心、楼梯/设施禁建、房间内墙与走廊；普通层计算目标为14个内容房。
- 95F改为11房预热/整备路线后进入不可绕过的90×90 Boss区；普通层移除跳关电梯房。Boss专钥匙、Boss后楼梯/阶段电梯仍未施工。
- 新增 `verify_floor_plan_generator` 并加入core：1000种子×4层共4000计划通过；塔楼组件验收覆盖66房、60水平通道，完整爬楼/Boss撤离专项本次3505节点。
- 行动中途持久化与跨重启恢复、seed gate提交后才创建Node、90F/85F更深场景仍列为未完成。

## 2026-08-05｜面积预算、多房型与必达下行路线设计

- 冻结“上层下行楼梯→15×15m 入口安全屋→`floor_seed_gate`”的入层逻辑；首次交互门才生成当层，已提交布局不重随机。
- 房间数改为先计算整层总面积、结构/楼梯/电梯禁建区与真实墙、碰撞、门、走廊占位，再按可用面积配置主路和支路。
- 所有内容房不小于 30×25m，新增标准、宽型、纵深型、中型、大型和竞技场房的 5m 网格尺寸组合；15×15m 仅作为安全屋/楼梯大厅等交通空间。
- 安全屋到下行楼梯的最短路径必须经过至少 10 个内容房，支路不能形成下楼捷径；支路按剩余面积生成并要求可读回报。
- 显示楼层号每逢 5 的整数倍（95F、90F、85F……）必然生成不可绕过 Boss；Boss前整备、专钥匙、专用门和真实下行楼梯保留。当时“每个Boss区段后电梯”的设想已被2026-08-06“仅95→94存在电梯”取代。
- 增加确定性重试、预验证安全模板、钥匙流、无回报死路、跨层锚点、原子提交/快照和至少 1000 种子性质测试要求。
- 此条已由上方“楼层、关卡模块施工与验收”取代：正式3D已迁移至纯数据规划器，不再使用固定12房构建路径。

## 2026-08-05｜正式主 HUD 与命运三选一纯代码重制

- 按参考构图重排正式 3D HUD：左上角色状态与红色生命、顶部行动语境、右上圆形战术地图/楼层/计时、底部枪械实例/弹药/命运槽、右下操作键块。
- 门后命运选择改为三张竖向发光卡，完整展示太阳/月亮/星星专名、卡名、稀有度、作用对象、枪械下一槽、效果与不可逆/不占槽提示；失败保留选择层并显示原因。
- 新增纯代码 `CodeHUDGlyph` 与 `NeonFrameControl`，头像、操作图标、切角、扫描线和辉光均由 Godot 绘制，不导入参考图或新增位图 UI 依赖。
- 战术地图改为圆形雷达外壳，继续使用真实房间比例、玩家位置/朝向与怪物红点；原战术背包拖拽、装备卸下和单悬停卡专项回归通过。
- 新增 `verify_reference_hud_fate_visual`，以 Metal/OpenGL 截图验证正式主 HUD、命运三选一与塔楼当前信息布局。
- 根据实机反馈将正式 HUD 与命运卡整体缩小 20%；塔楼当前信息下移并删除重复灰色 HP 条；底部枪械占位图改为背包同源 `ItemModelIcon3D` 3D 渲染，普通弹药变化不会重建模型。
- 增加塔楼紧凑 HUD 截图；性能更新为世界 `3397/3500`、UI 壳 `129/140`、3D 预览 `17/20`、总量 `3548/3600`，持续帧耗时约 `6.91ms/16ms`。

## 2026-08-05｜太阳/月亮/星星命运与20张新牌

- 冻结玩家端专名：`WORLD = ☀ 太阳命运`、`CHARACTER = ☾ 月亮命运`、`WEAPON = ★ 星星命运`；所有正式卡面同时显示符号、专名、中文目标和是否占武器槽。
- 新增 10 张月亮命运与 10 张太阳命运，正式卡池从 28 张扩展为 48 张，当前分布为星星 22、月亮 12、太阳 14。
- 月亮牌由 `Player3D` 本局规则状态独立结算；太阳牌由 `Dungeon3D` 世界规则独立结算；两类均不写入 `WeaponInstance` 的永久命运槽。
- 门后三选一、占卜、收藏、工作台、通用卡片控制器和枪械悬停接入天体专名；战术背包左栏常驻显示已生效的月亮/太阳牌名与短效果。
- `verify_fate_card_pool` 通过 48/48；新增 `verify_celestial_fate_scope_flow` 覆盖 20 张牌执行、三作用域隔离和 UI 可观察并加入 `core`；核心回归 17/17 通过。
- 内容数据库 `命运卡` 表扩展到 48 行，更新 `总览` 计数；唯一 ID、22/12/14 数量和公式错误扫描通过并完成渲染复核。

## 2026-08-05｜角色装备、战术背包与小地图重制

- 交互复验修正：原自动化只检查 `tooltip_text` 和直接调用放置回调，不能证明玩家实际看见悬停/拖拽；现改为独立构筑悬停卡、拖拽状态条、黄色来源和蓝/绿/红目标高亮，并以真实鼠标事件完成换位、换枪、丢弃三条路径。
- 修复装备枪无法卸下：装备位成为合法拖拽来源，可卸回指定空背包格或直接落地；卸装、目标写入和落地组成可回滚事务，不覆盖已有格位。
- 修复悬停信息重叠：关闭正式背包的引擎默认 Tooltip，只保留单一 `ItemHoverCard`；相邻格快速切换以最后进入者为准，并将详情卡放到来源格外侧。

- 新增 PUBG 式双栏角色装备页：左侧显示红色生命与当前主武器实例/构筑，右侧重新编排 12 格背包、2 格保险、整理按钮和明确地面丢弃区；尚未开放的防具/战术/护符槽如实标注。
- 背包物品支持真实数据层移动/交换与稳定整理；枪械可拖到主武器位执行整枪换装，物品拖到红区或面板外会把同一完整实例生成在当前房间，失败执行回滚。
- 枪械悬停逐槽列出命运卡名称和最多 10 个汉字的功能简述，并保留实例尾号、命运槽占用与装配不占槽说明。
- 主 HUD 生命条改为固定红色；战术地图按房间真实宽高绘制矩形和边界走廊，玩家标记使用实时世界位置/朝向，当前房存活怪物显示红点。
- 完整装备页改为首次打开时创建，保留轻量真实物品格信号，兼顾既有装备路径与节点预算；同时清理小地图中的已释放敌人引用。
- 新增 `verify_tactical_inventory_minimap_flow` 和可视验收场景；`core` 16/16 通过，Metal/OpenGL 真实渲染截图通过，性能预算完全探索节点 `3475/3500`、持续帧耗时约 `6.90ms/16ms`。

## 2026-08-05｜战斗、构筑与武器系统施工验收

- 新增持久化 `WeaponInstance`：每把枪具有永久唯一实例 ID、稀有度、完整装配、当前弹药和线性永久命运槽，可作为独立物品在装备、背包、地面、商店、保险、撤离与存档间移动。
- 正式 `Player3D` 与兼容 `Player` 改为投影实例构筑；换枪不再搬运模块，原枪连同其构筑完整入包，重新装备后恢复。
- 28 张命运卡补齐稳定 ID 和 `WEAPON / CHARACTER / WORLD` 作用域；武器卡按槽序永久写枪，角色卡与世界卡不占枪槽，满槽原子拒绝。
- HUD、背包、地面、商店、保险柜、命运选卡和武器表现页接入实例短 ID、命运槽与装配提示；3D/背包预览显示可更换装配与最多 8 个命运纹章。
- `BaseData` 升级到 `1.2` 并迁移旧枪；增加重复实例拒绝和保险柜实例确认出售。
- 新增 `verify_weapon_instance_fate_ownership_flow` 并加入 `core`；本轮脚本解析通过、核心回归 15/15、28 张命运卡池验证通过。
- `full` 集仍在既有探照灯阈值用例停止，与本轮武器改动无关；该灯光参数问题保留为独立事项。

以下“表现页设计”和“独立实例设计”两节保留施工前审计记录；其“尚未实现”描述已由本节的完成记录取代。

## 2026-08-05｜武器功能可感知性与表现页设计

- 冻结“功能、UI、战斗表现共同验收”：选择前可预判、执行时有确认、战斗中能识别、事后可追溯。
- 新增统一武器表现页，覆盖实例身份、真实装配预览、基础/当前属性来源、线性命运轨道、可更换装配和触发链。
- 明确命运选卡显示作用域、目标枪、下一槽、不可逆警告和准确失败原因；失败不得消费选择或自动关闭可修正页面。
- 为 7 枪身、8 子弹、6 配件和 28 张命运卡建立逐条 UI/表现字段与验收要求。
- 核对当前 UI：弹药/换弹、背包模型、已装备标签、装配树原型和通用命运通知可复用；实例身份、命运轨道、目标预览、作用域和事务反馈尚未实现。

## 2026-08-05｜独立枪械实例与命运槽设计

- 冻结“构筑跟随枪械而非角色”：每把枪拥有永久唯一 `weapon_instance_id`，可装备、进包、丢弃、出售、保险、撤离与存档。
- 普通枪械基础为 8 个永久命运槽；武器命运卡依次追加、不可逆，配件与子弹模块可更换且不占槽。
- 命运卡新增 `WEAPON / CHARACTER / WORLD` 作用域，与原有八种效果类型正交。
- 核对当前代码：基础装配、换枪和配件换装可复用；枪械实例、随枪构筑、永久槽、作用域路由与存档迁移尚未实现。
- 同步更新主设计、战斗施工、内容数据库规则、架构、玩家、精英、基地、存档、资产、测试与完成度清单。

## 2026-08-04｜文档体系重构

### 主设计

- 将旧 `README`、游戏愿景与核心循环、系统设计整合为一份主 [游戏设计文档](../README.md)。
- 以七大核心系统重新定位整个游戏：玩家、战斗与成长、关卡与爬楼、怪物/精英/Boss、基地、剧情、存档/复活。
- 建立绿色 `[已实装]`、蓝色 `[用户设计]`、橙色 `[Codex补充]` 三色规则。

### 用户设计设定

- 固定全游戏 12 只唯一精英：独立档案、成长、随机出现、夺取玩家枪械、同名唯一。
- Boss 击败后签发专用下行钥匙；特殊门可位于随机地图最终下行路线。
- 当时规则为电梯只出现在Boss层后的下行楼梯间；现已收紧为全游戏关卡内仅95→94楼梯间存在一个电梯，不再作为每层或每Boss区段通用设施。

### 内容数据库

- 新建 Excel 游戏内容数据库，包含武器、命运卡、怪物与 Boss、精英怪、掉落物品及字段字典。
- 从当前正式代码导入 7 枪身、8 子弹、6 配件、28 命运卡、7 怪物/Boss 模板和 32 物品记录。
- 建立 12 精英初始名册、Boss 专用钥匙和稳定内容 ID 规则。

### 技术施工

- 新建七份系统施工文档，明确所有者、输入、事件、数据、失败语义、阶段与验收标准。
- 新建技术架构总则、资产与内容规范、测试与发布规范。
- 建立全游戏完成度清单，每个系统不超过 10 个主 Checklist，并按 P0–P3 排序。

### 历史归档

- 重构前文档原样备份至 `docs/archive/v0.1_pre_framework_2026-08-04/`。
- 归档只用于追溯，不再作为当前设计、数值或技术实现依据。
## 2026-09-14｜Blender 原生关卡搭建插件 r1

- 新增 Blender 4.3+ `ShellStorm Level Builder` Add-on，复用原生视图、变换、吸附和编辑模式。
- 提供组件库、参数化白盒、规范Collection、项目资产包扫描/Append、对象唯一归包及manifest/catalog/tree同步。
- Blender 4.5后台端到端验收与已安装插件启用检查通过；当前不执行GLB导出或Godot接入。

## 2026-09-14｜Blender 原生关卡搭建插件 r2

- **组件结构与锚点**：白盒组件由 Mesh+子层级改为单一 Mesh；锚点默认底面中心，地砖按运行时 GLB 采用厚度居中，并新增重设锚点算子与锚点守恒自测。
- **吸附修复**：r1 从未打开 `use_snap` 导致吸附不可用；新增一键配置原生吸附、5m 网格吸附、五向贴边、单轴/多轴对齐与移动到游标。
- **预览增强**：按类型白盒配色（开关即时生效）、线框描边、布局统计、两行中文顶视图标注（字号随网格缩放）与正交顶视验收渲染。
- **可用性与安全**：按分组+搜索的组件库、单网格重建（支持多选）、manifest 字段别名兼容扫描与可用/跳过诊断、同步前要求已保存且拒绝空包、未归包对象报告、预览开关即时生效；版本升至 `0.2.0`。
- Blender 4.5 后台自测通过（`{"ok": true, ...}`）；仍未导出 GLB、未改动 Godot 引用。

## 2026-09-14｜楼梯间原位拼装 v015

- 按v013原位置恢复两个楼梯间，130个组件以固定墙板拼接，楼梯使用高度/坡度联动，禁止缩放。
- 当前源、网页预览和组件追溯更新为v015；详见[原位拼装记录](2026-09-14_楼梯间原位组件拼装.md)。

## 2026-09-14｜楼梯间白盒组件化 v014（由v015修正）

- 当前楼梯间Blender白盒改为单套装配，旧重复楼梯间不进入v014编辑源。
- 直梯只保留一个母组件，第二跑引用同一组件并旋转180°；网页工具支持水平长度与坡度联动重建。
- 同步楼梯区组件合同、资产台账和区块文档；本次不重新导入Godot。

## 2026-09-15｜楼梯间正式美术接入 v002

- 从v021双装配源分别导出100→99与99→98楼梯间GLB v002，运行时各优化为3个网格。
- 新增两份PackedScene v002并替换`TowerDescent3D`旧临时GLB引用；共享色盘后处理与每套2个同形碰撞源生效。
- 组件对齐、下降流程、楼层区块及Forward+真实渲染退出0；同步资产清单与XLSX台账。
- 仅在Godot恢复墙体与楼板/楼梯摄像机碰撞语义，并以连续坡面/平台替代离散踏步的角色阻挡，修复高差卡住；Blender和GLB不变。
- 后续按用户红线将内部承重收口为一个共顶点封闭模型，覆盖整块楼板与折返平台；48,245个表面采样及胶囊双向通行专项通过。
- 楼梯摄像机碰撞收敛为仅下跑一块camera-only坡面，上跑/北向台阶面不再触发动态镜头；两跑左右侧补齐4段实体栏杆阻挡，上层楼板边缘按模型两段栏杆补齐阻挡并保留中间楼梯入口。仅改Godot运行包装，Blender与GLB保持不变。
- 连续承重面上抬0.18米，避免角色陷入可见踏步并误入楼梯下方逻辑；修正栏杆阻挡误用4米端部留空的问题，四条梯跑栏杆现覆盖完整行程并各端重叠0.20米，折返楼道栏杆保持15米全宽。
- 撤销误放在折返中心线、会封住通行的15米整宽阻挡；依据v021可见模型重建两段上层楼板边缘栏杆阻挡，中间保留4.88米楼梯入口，角色胶囊可抵达折返中心并横向转弯。
- 深度入口扫描确认整面卡住来自承重面整体抬升造成的0.18米入口竖边，而非栏杆；抬升现仅作用于梯跑中段，首末各1米平滑回接原楼板。99→98上口使用正式角色胶囊横跨5个位置均可通过，楼板边缘栏杆按6米梯跑净宽退让。
- 楼梯角色阻挡最终收敛为每跑一张坡脚直达坡顶的连续斜坡面，删除回接分段和逐级碰撞；楼板栏杆按v021可见扶手中心闭合转角并搭接0.15米，修复图示约0.85米漏口，同时保留中央楼梯入口。两套楼梯共24组坡脚/中段/坡顶栏杆胶囊穿越回归通过；Blender与GLB未改。
- Blender v021实测可见扶手距梯跑中心2.15米，旧运行阻挡误放在3.12米承重面外缘，造成约0.97米视觉栏杆可穿区域；两套楼梯、两跑、左右侧四类阻挡全部校正至±2.15米，并以正式玩家胶囊完成8处横向冲撞验收。
# 2026-09-23｜战斗区 L 型走廊房间种类美术源 v001

- 依据用户参考图制作 10m 宽、5m 网格拼接的 L 型走廊 Blender 源，28 块独立地砖、88 个可拆解资产包，交付全景/俯视/近景与严格 PaletteUV 自检。
- 无现成白模；推定长度与门位已明确标在 manifest，暂不接入 Godot。详见[独立开发记录](2026-09-23_battle_l_corridor_room_type_v001.md)。
# 2026-09-23｜战斗区 L 型走廊美术源 v002

- 按两张局部参考图补齐维修推车和高细节终端，沿走廊约 7m 高处加入三道管线及五组下垂粗电缆；保留 v001 可回溯。详见[独立开发记录](2026-09-23_battle_l_corridor_room_type_v002.md)。
# 2026-09-23｜战斗区 L 型走廊美术源 v003

- 走廊改为 15m 宽、三块 5m 地砖并列；以通用地砖和实墙网格构建新版，留出中间及参考图对应的门墙/门通用组件槽位，设施移至墙边。详见[独立开发记录](2026-09-23_battle_l_corridor_room_type_v003.md)。
