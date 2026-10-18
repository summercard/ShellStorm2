# 2026-10-18 合成保底接进掉落结算（`synthesis_pity.bp_charge` 真正落地）

功能 ID：`RUN-SYNTHESIS`。设计主源：[07.3 §5.2 硬保底](../07.3_玩法系统_合成目录与兴趣曲线.md)。

## 业主口径

> 先把功能做掉。

上一轮收口时我问「先接保底还是先做配方行 3D 图标」，业主选功能。所以本轮只做**逻辑落地**，配方行仍然是纯文字行。

## 落地前是什么状态

`SynthesisCatalog` 里只有三个纯函数：`pity_should_grant` / `pity_record_miss` / `pity_record_drop`，外加 `PITY_THRESHOLD = 3` 和 `PITY_KEYS = ["bp_charge"]`。

也就是说：**规则写好了，但没有任何地方调用它们**。没有存档字段、没有结算触发点、没有补发通道。玩家的体感与没有保底完全一致 —— 这是最坏的一种"做完了"：单测绿、可玩性为零。

## 三个必须先回答的问题

### 一、什么算"一次机会"

文档写的是「连续 3 次通关 `boss_floor_2`」。落地必须把它变成代码能判的谓词。

候选三个：

| 判据 | 后果 |
|---|---|
| 进过 boss 房 | 玩家进图先跑去 boss 房门口站一下再撤，也能记一次 → **保底可刷** |
| 击杀 boss | 击杀即记，但死在撤离路上也算 → 玩家的体感是「我明明打过了，怎么还是没出」 |
| **击杀 boss + 成功撤离** | 结算那一刻才算 → 与"带出的东西"对齐 |

选第三个。理由：保底兜的是「打了很多次终局目标还是拿不到」的绝望，而**打过了没带出来**不属于这个范畴 —— 那是一次失败，失败本来就没有产出。

### 二、为什么不能"进图就算"

`_boss_defeated_rooms` 非空才算。这一条挡掉的正是「进图 → 走到撤离点 → 二十秒速撤」：能刷的话，保底就从"运气下限"退化成"可计划的进度条"，而那恰恰是 §5.2 明确要避免的东西（「保底是兜住运气的下限，不是消灭运气」）。

反向的一条同样重要：**本局真的带出了 `bp_charge` 就清零，哪怕这局没打 boss**。事实优先于计数 —— 拿到了还留着旧进度，下一次保底会提前触发，等于白送。

### 三、补发物从哪条通道出去

项目里有两条完全不同的成功结算路径：

| 路径 | 战利品怎么走 | 保底物必须怎么走 |
|---|---|---|
| `Dungeon3D._finish_run(true)` | 复制进 `extraction_loot`（待领取栏） | 追加进本局结算物，件数才对得上 |
| `TowerDescent3D._finish_expedition_successful_extraction()` | **保留同一批运行时实例，`extraction_loot` 传 `[]`** | 直接进背包；背包满则退回待领取栏 |

第一版我把判定塞进 `commit_run_settlement` 内部、直接 append 到传入的 `extraction_loot`。写完才意识到：**带物返航那条路径传的是字面量 `[]`**，append 上去会写进一张「99F 没有入口」的表 —— 保底物凭空消失。这正是"在错误的位置做正确的判定"。

## 最终结构：plan → commit 两段式

```
调用方（Dungeon3D / TowerDescent3D）
   ├─ 结算物已确定
   ├─ plan_synthesis_pity(loot_ids, boss_cleared)   ← 记账（改内存）+ 产出真物品
   ├─ 自己决定怎么交付（进结算物 / 进背包）
   └─ commit_run_settlement(...)                    ← 计数随事务落盘
          └─ 失败 = 计数整体退回 plan 之前
```

- `BaseManager.plan_synthesis_pity()`：先快照 `synthesis_pity`，再调 `SynthesisCatalog.resolve_settlement()` 就地记账，然后按 `granted` 造一件**真物品**（`ShopService.ensure_item_instance`，带 `item_instance_id`）。同一次结算重试会命中缓存，**不二次记账**。
- `BaseManager.commit_run_settlement()`：`old_synthesis_pity` 取自快照（而不是当前值 —— 当前值已经被 plan 改过了）。写盘成功清快照；写盘失败把计数恢复成快照。
- `BaseManager.discard_synthesis_pity_plan()`：结算被判为重复提交时调用，把计数退回。挂在 `Dungeon3D._absorb_duplicate_settlement()` 里。

## 改动的文件

| 文件 | 改动 |
|---|---|
| `src/weapons/SynthesisCatalog.gd` | 新增 `resolve_settlement` / `pity_progress` / `_pity_bucket`。三分支顺序写死：已拿到 → 清零；没拿到且打了 boss → 达阈值补发否则 +1；没拿到且没打 boss → 不动 |
| `src/base/BaseData.gd` | 新增 `synthesis_pity: Dictionary`（`{物品id: {misses:int}}`），`_to_dict` / `from_dict` 双向；坏形状视为"没记过账"，不把写坏的值当成既成事实 |
| `src/base/BaseManager.gd` | `plan_synthesis_pity` / `discard_synthesis_pity_plan` / `get_synthesis_pity_misses`；`commit_run_settlement` 的快照与回滚 |
| `src/world3d/Dungeon3D.gd` | `_plan_synthesis_pity_drop()`（补发物进 `_run_loot`）、`_plan_synthesis_pity_carry()` / `_deliver_synthesis_pity_carry()`、状态行「保底补给 1 件」、`summary["synthesis_pity"]` |
| `src/world3d/TowerDescent3D.gd` | 两条成功返航路径接入：判定在 commit 前、交付在 commit 后、交接快照在交付之后 |
| `src/ui/WorkbenchPanel.gd` | 目录页被保底的那一行显示「保底 n/3」 |
| `tests/verification/verify_synthesis_catalog.gd` | 断言 31 → 36 条，新增 `_case_pity_settlement()`（含端到端事务与失败回滚） |

## 踩到的坑

1. **`summary` 的构建时机**：原代码在 commit **之前**拼 `summary`。保底物是在 commit 前追加进 `_run_loot` 的，但如果 summary 先拼好，就会出现「状态行写 5 件、summary.loot 只有 4 件」。把 summary 移到 commit 之后再拼。
2. **重复结算会把计数吃掉**：`_absorb_duplicate_settlement` 命中时，plan 已经记过账了。必须 `discard_synthesis_pity_plan()` 退回，否则重放一次结算就白推进一格。
3. **`commit` 里的回滚快照不能取当前值**：plan 之后 `data.synthesis_pity` 已经是新值，回滚等于不回滚。必须取 plan 之前的快照。
4. **别在 commit 内部 append 到 `extraction_loot`**：带物返航路径传的是 `[]`，append 出去的东西没人接。
5. **背包满**：`_deliver_synthesis_pity_carry` 里 `add_item` 失败时退回 `extraction_loot`。保底物不能因为"格子不够"消失。

## 验收

`verify_synthesis_catalog` 36 条断言全绿。新增的 22 / 23 条是**落地**断言，不是规则断言：

- `plan_synthesis_pity` 必须产出一件 `id == "bp_charge"` 的真物品（不是只返回一个 ID）；
- 同一结算重试拿到同一份结论（不二次记账）；
- `commit_run_settlement` 之后物品进入 `extraction_loot`、计数清零；
- 用独立 `save_path` 反序列化重载后 `synthesis_pity` 仍在 —— 证明它真的进了存档；
- `force_save_failure_for_test` 下提交失败，计数退回记账前。

### 回归（4 绿 1 红，红与本轮无接触点）

| 场景 | 结果 |
|---|---|
| `verify_synthesis_catalog` | **exit 0**，36 条全绿 |
| `verify_run_settlement_transaction` | **exit 0**（`commit` 被改，必跑） |
| `verify_expedition_extraction_carry_return` | **exit 0**（带物返航路径被改，必跑） |
| `verify_death_during_extraction_flow` | **exit 0**（`Dungeon3D._finish_run` 死亡分支被改） |
| `verify_tower_extraction_return_flow` | **exit 1**，7 条红，**全部落在 `_verify_real_99f_spawn_restores_insurance_slots`** |

那条红的根因是 `combat_room.get("_light_switch")` 为 null（「清房开门回归房没有可控灯光」），随后连锁出保险格夹具失败。`RoomLightSwitch3D` 与 99F 灯光是**并发会话正在改的资产**（`BaseLampDynamics3D` 接管 7 通道那一条），本轮没有触碰 `scenes/`、`assets/` 或任何房间装配代码，所以不在此处修 —— 修别人的活红会把两边的改动搅在一起。

需要在本轮之外确认：那条红在本轮改动前后**是否一致**（我没做 A/B，工作区同时有多个会话的未提交改动，切基线不安全）。

### 顺带补掉的两笔注册债

上一轮落地 `verify_weapon_forge` / `verify_synthesis_catalog` 时没把场景登记进套件，导致 `check_verification_registry.py` 一直报 `unregistered`：

- `scripts/run_verification_suite.sh` 的 `core_scenes` 追加两行；
- `feature_registry.json` 的 `RUN-SYNTHESIS` 从 `designed` 改 `partial`，补两条开发记录；`RUN-FORGE` 的 `design_docs` 补上 MODULE_INDEX 里引用但注册表缺失的 `UI风格规范_棱镜线框.md`。

现在 `check_feature_traceability.py` → `FEATURE_TRACEABILITY_OK features=41`。`check_verification_registry.py` 仅剩 `verify_base_lamp_dynamics` / `verify_base_lamp_visual` 两条未登记，属灯具那条线。

### 一条已登记的无渲染器噪声

`tests/verification/expected_errors/verify_synthesis_catalog.txt` 登记了 `^ERROR: Parameter "material" is null\.$`：端到端事务断言要往盘面投料 → `GridInventoryBoard.render_items` 建 `ItemModelIcon3D` 的 SubViewport → headless dummy renderer 取不到材质。真实渲染下没有这条。**它只盖住这一条 C++ 层消息，不代签任何视觉结论。**

## 未做

- 配方行的 3D 图标与动效（仍是纯文字行，等美术）。
- 保底在 UI 上只有「保底 n/3」一行小字，没有"再打一次必得"的强调动效。
- `boss_floor_2` → "任意首领"的口径放宽已写进 07.3 §5.2.1，但没有反向监控（例如某张图没有 boss 房时保底是否永不触发）。

