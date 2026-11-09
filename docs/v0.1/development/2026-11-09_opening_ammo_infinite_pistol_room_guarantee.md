# 2026-11-09 开场弹药三项：取消保底备弹、豌豆手枪弹匣无限、远征01 前两房宝箱保底

> ⚠ **第 2 项已被同日晚上改判**：业主改为「弹夹保持 10 发，打完后备弹无限」⇒
> 弹匣回 10 发、字段改名 `infinite_reserve_ammo`、开火恢复扣弹。
> 本文件的第 1 项（取消开场备弹）与第 3 项（远征01 保底枪）**仍然有效**。
> 现行口径见 [2026-11-09 晚 弹匣 10 发、备弹无限](2026-11-09_pistol_infinite_reserve_ammo.md)。

> 业主三条（同一次对话，逐条确认）：
> 1. 「初始装备的那那个几百发的这个普通弹药，帮我去掉不要了」
> 2. 「豌豆手枪的子弹改成无限的」（形态确认：**弹匣无限、保留换弹**）
> 3. 「远征01 ……第一个房间的宝箱 / 第二个房间的宝箱，随机一个房间掉落」一把**最低品质**的霰弹枪或步枪，
>    并再掉**一组 100 发**普通弹药

---

## 1. 取消开场保底备弹

| 项 | 改前 | 改后 |
|---|---|---|
| `Dungeon3D.GUARANTEED_LOADOUT_AMMO_ROUNDS` | `300` | **常量删除** |
| `_setup_run_modules()` 里的发放调用 | `if not test_mode: _grant_guaranteed_loadout_ammo()` | **删除** |
| `_grant_guaranteed_loadout_ammo()` | 真发 300 发 `item_ammo_pack` | 恒返回 **0**，不改背包 |
| `get_guaranteed_loadout_ammo_rounds()` | 返回常量 | 恒返回 **0** |
| 入场主背包备弹 | 300 发 | **0 发** |

**为什么保留两个恒返回 0 的函数、而不是连函数一起删**：
`verify_guaranteed_loadout_ammo_flow` 与 `verify_opening_script_runtime` 都通过
`get_guaranteed_loadout_ammo_rounds()` 读「设计值」，测试里不写死数字。留着这个出口，
一旦有人把发放加回来，两条反向断言会立刻判红；纯删掉反而让门禁失去观察点。

## 2. 豌豆手枪弹匣无限

**落地方式**：枪身 `base_stats` 声明 `"infinite_ammo": true`（内容侧是唯一真源，
`WeaponModel3D` 里**不写枪名判断**）。`AssemblyNode._combine_stats()` 对 bool 走
「非数值类型直接覆盖」分支，所以混进装配树不会被当成数值相加。

| 行为 | 改前 | 改后 |
|---|---|---|
| 开火扣弹 | `current_ammo -= 1` | **不扣**（`fire_rate` 冷却照旧 ⇒ 射速 2.3 发/秒不变） |
| 空匣开火 | `current_ammo <= 0` 直接拒绝 | **放行**（`try_fire` 与 `_fire_now` 两处门槛都豁免） |
| 换弹 | 需要备弹，按缺口扣 | **仍需要换弹**、仍占 `reload_time = 1.4 s`，但**不向备弹提供者扣数** |
| 满匣时 `request_reload()` | 返回 false | 返回 false（没有缺口可填，语义不变） |
| HUD 当前弹数 | `12` | **`∞`**（`HUDPresenter3D` 新增结构化字段 `ammo_infinite`，`ammo_text` 老契约逐字不动） |

**为什么不做「跳过换弹」**：那会连带废掉换弹动作剪辑、换弹音效、
「换弹后首发强化」（`nth_after_reload`）与命运卡换弹相关构筑。无限弹匣只取消消耗，不取消节奏。

## 3. 远征01：第一或第二房的宝箱保底

配置在 `clear_drops.room_guarantees`，**权威源是**
`art_source/design/whitebox/tower_zones/expedition_01/v001/data/level_plan.json`；
`data/level_plans/expedition_01/level_plan.json` 只是 `scripts/sync_runtime_design_data.py` 的字节级投影。

> ⚠ **踩过一次的坑**：本次先直接改了 `data/level_plans/…`，`--check` 立刻报
> `projection drift: …expedition_01\level_plan.json`；跑一次同步就把改动**整段覆盖回源**，
> 保底配置静默消失（`data/` 那个文件也不再出现在 `git status` 里）。
> 正确顺序永远是：改 `art_source` → 跑 `sync_runtime_design_data.py` → `--check` 归零 → 再跑用例。

| 项 | 值 |
|---|---|
| 候选房 | `f00_room_01` / `f00_room_02` |
| 选房 | `absi(hash("{run_seed}|exp01_opening_weapon_or_ammo|guarantee_room"))` 取模 ⇒ **稳定哈希**，同局读档/流送重建不换房 |
| 枪 | `weapon_shotgun` / `weapon_rifle` 二选一（另一条独立稳定哈希） |
| 品质 | **`blue`**（最低品质 = 伤害 ×1.00、命运槽 +0），走 `forced_grade`，**不参与** 70/25/5 随机品质 |
| 弹药 | `item_ammo_pack × 100` |
| 与普通奖励 | **额外追加**，不替换：该箱仍照常解析 `loot_floor_1_2` 的 2—3 件消耗品与 30% 命运卡掉落物 |

链路（三层，职责不混）：

```
level_plan.clear_drops.room_guarantees
  → ClearDropService.guaranteed_items_for_room()   决定「哪间房 / 哪把枪 / 多少发」
  → ClearDropService._build_chest()                 写进 chest_config["guaranteed_items"]
  → TreasureChest3D.configure() → get_reward_config()
  → ChestRewardService._resolve_guaranteed_items()   翻译成 grants，接在 _unit_grants() 之后
```

⚠ **一个必须记住的坑**：`ChestRewardService._unit_grants()` 会把每条 grant 的 `count` 拍成 1。
保底条目若在它**之前**合并，100 发会静默变成 1 发。实现上刻意放在 `_unit_grants()` 之后，
门禁 `verify_expedition01_room_guarantee` 的「100 发」判据就是盯这条。

⚠ **确定性**：`RewardService._roll_dropped_weapon()` 里新增的 `forced_grade` 采用
「**先抽后判**」—— 即使品质被指定，也照常消耗一次 `randf()`，保证同一局的其它随机掉落
不会因为「这一条强制了品质」而整体位移。

## 4. 验收

| 用例 | 结果 |
|---|---|
| `verify_expedition01_room_guarantee`（新，core） | `EXPEDITION01_ROOM_GUARANTEE_OK`，exit 0。8 个种子逐条验证：恰好命中一间 / 同 seed 恒定 / 内容=蓝枪+100 发 / 真进宝箱 grants / 清房箱档位仍 `normal`；反向对照「抹掉 `room_guarantees` ⇒ 零保底」通过 |
| `verify_guaranteed_loadout_ammo_flow`（改写为反向门禁） | `GUARANTEED_LOADOUT_AMMO_OK`，exit 0。开场 0 备弹、显式调用发放仍为 0、手枪 `infinite_ammo=true`、空匣可开火且不扣弹、无备弹可换弹且不产备弹、HUD 显示 `∞`、存档整格覆盖不叠加 |
| `verify_opening_script_runtime` | `verify_opening_script_runtime_OK checks=126`，exit 0（I 段改为「备弹应为 0」+ 源码守卫「入场流程不得再调用发放」） |
| `verify_finite_ammo_flow` | `FINITE_AMMO_FLOW_OK`，exit 0。⚠ 该用例原本拿出场手枪验「有限备弹按缺口装填」，手枪变无限后失真 ⇒ **样本枪换成步枪**（规则本身没改），并加两条断言：出场手枪必须 `infinite_ammo=true`、步枪必须不是 |
| `verify_starting_weapon_contract` | `STARTING_WEAPON_CONTRACT_OK`，exit 0 |
| `verify_3d_reload_state_flow` | `3D_RELOAD_STATE_FLOW_OK`，exit 0 |
| `verify_hud_presenter_3d` | `HUD_PRESENTER_3D_OK`，exit 0（新增字段没有破坏既有的逐字文本契约） |
| `verify_bullet_vfx_profiles` | `BULLET_VFX_PROFILES_OK`，exit 0 |
| `check_verification_registry.py` | `VERIFICATION_REGISTRY_OK scenes=293`（新场景已按 core 登记） |
| `verify_chest_reward_service` | `CHEST_REWARD_SERVICE_OK`，exit 0（先红后修：保底 grants 用 `as Array[Dictionary]` 强转在「空保底」时失败，改成无类型 Array） |
| `verify_expedition03_clear_drop_rooms` | `EXP03_CLEAR_DROP_OK`，exit 0 |
| `sync_runtime_design_data.py --check` | `{"files": 52, "issues": []}`（改的是 `art_source` 源 + 重生成投影，两边一致） |
| `check_level_decoupling.py` | `violations 0` |

**未执行**：真实远征01 跑图开箱（本机只跑纯服务层与既有场景用例）；真渲染；手感。

**对照结论（既有红项，非本批引入）**：`verify_expedition_level01_flow` 仍报「缺少两个立体入口 / 读取界面标题不是远征关卡01 / 怪物掉落表应有 13 行实际 11 / room_06、room_07 若干格心无碰撞」。
已用 `git show HEAD:` 对比权威源确认：本批对 `expedition_01/level_plan.json` 的改动**只有 `clear_drops` 一个键**
（`monster_drop_table` 11 行、`monster_rules`、几何全部与 HEAD 逐字相同），故上述红项属工作区既有问题，
不归因于本轮。`verify_reward_service_flow` 未跑。

## 5. 文档同步

- `docs/v0.1/04_技术施工_战斗与局内成长.md`
  - §6.1 现行值表新增 `infinite_ammo` 一行；
  - §6.6 整节重写为「保底武装与开场弹药口径（2026-11-09 起不再发放备弹）」，旧的 60/300 沿革折叠进 `<details>`；
- `docs/v0.1/08_技术施工_剧情触发.md`：开场武装那一行改为「身上没有枪、也没有备弹」并注明原因；
- `docs/v0.1/design/远征关卡01设计.md`：新增 2026-11-09 保底段（含候选房、稳定哈希、`forced_grade=blue`、100 发、与普通奖励的关系、三层实现分工、门禁）；
- `docs/v0.1/关卡接入规范.md` §3.1.2：`clear_drops` 能力新增 `room_guarantees` 契约行 + JSON 样例 + 边界说明（候选房必须真有 `clear_drops` 箱）；
- `docs/v0.1/MODULE_INDEX.md` 顶部索引新增本条；
- `docs/v0.1/development/CHANGELOG.md` 新增本条；
- `.codex/skills/08-items-weapons-code-integration/SKILL.md` 与 `skills_drafts/…`：出厂枪说明改为「弹匣无限 + 不再发备弹」。

## 6. 未做 / 风险

- **真实关卡未跑**：远征01 的保底箱是否落在玩家实际会经过的房间，取决于该局 `f00_room_01/02` 是否都被清——
  两间都是主路内容房，正常推图必清；但「跳房 / 只清一间」的打法下保底可能拿不到，属预期。
- **拟态箱**：如果那只箱子掷成拟态（20%），保底奖励跟着箱子进战斗，击杀后才发——没有单独绕开。
- **弹药经济缺口**：开场不再给 300 发，除手枪外的枪只靠掉落/宝箱/关卡保底供给。是否够用未实测。
- **半自动与无限弹匣叠加**：`semi_auto` 标签仍在、代码无按 tag 限速，2.3 发/秒要求每秒点 2.3 次；
  无限弹匣让玩家没有「打空停下」的自然节奏断点，长时间连点疲劳风险比之前更高，需实机确认。
