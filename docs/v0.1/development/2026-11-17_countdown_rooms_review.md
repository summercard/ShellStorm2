# 远征01 五个倒计时房全量复核、三号房末批加量与六结果用例对齐

- 日期：2026-11-17；工程版本 0.1.0。
- FeatureID：`ENCOUNTER-EVENT / WORLD-PLAN / WORLD-LOOT / SAVE-RUN`。
- 来源：业主「关卡01的几个倒计时房间，都检查一遍，把剩下问题一并解决了。三号房第四批要调整。多出一些。」
- 主设计：[远征01 §11.1](../design/远征关卡01设计.md)、[触发器刷怪 §10.5.2](../design/触发器刷怪设计.md)、[关卡接入规范](../关卡接入规范.md)。
- 状态：五房全链通过（完整套件 **532 项 0 失败、退出码 0**）；三号房末批 8→12、cap 8→12；room_09 六结果用例从 54 条红项重写为 0；数据门禁、解耦、登记、文档门禁均通过（文档仍有 14 条既有断链，新增 0）。真实渲染与实机未验，不提升整档 partial。

## 1. 三号房第四批：8 → 12（业主指定）

改的是**末模板**（第 4 段、也是 `repeat_last_stage` 循环的那一段）：

| 项 | 改前 | 改后 | 依据 |
|---|---|---|---|
| 末模板编成 | 胖2 + 保2 + 小4 = **8** | 胖3 + 保3 + 小6 = **12** | 原模板 ×1.5，三类同步放大，保持「两胖两保四小」的配比意图 |
| `max_alive` | 8 | **12** | cap = 最大模板（stage3=9 ≤ 12）⇒ 每批整批派发，不再有 cap 截断余量 |
| 每轮模板 | 5/7/9/8 | **5/7/9/12** | 循环总量 29 → 33（+13.8%） |
| 实测批次 | 5/7/8/**1**/8 | **5/7/9/12/12** | 原第 4 批是 stage3 的 1 只余量；现每批都是完整模板 |

`max_alive` 不是随手抬的：`probe_expedition01_encounter_spawn_capacity` 在 6 m 安全距离下实测 room_03 可放 **24** 个合法落点，12 只用掉一半，留 2 倍余量。其余四房 cap 一个字没动（2026-11-16 冻结值），见 §3。

**为什么必须是「cap = 最大模板」而不是只改末模板**：stage3 是 9 只、cap 只有 8，派发到 8 只就停，剩下 1 只挂在 pending 里；玩家把 8 只一口气清掉（霰弹/连爆很常见），那 1 只才补出来 —— 这正是业主看到的「打完一堆突然只剩 1 只」。只把末模板改成 12 而不动 cap，尾巴还在。

## 2. 剩两个问题及处置

| # | 问题 | 根因 | 处置 |
|---|---|---|---|
| 1 | room_09「六结果」段落 54 条红项：`六结果遭遇启动失败`、`actual=0`、`未结算终端就放行` | 该段是 09 还是纯事件房时写的：直接调 `_start_room_encounter(room)` 而不给门位，玩家站在房心 ⇒ `door_entry_not_hit` 直接拒绝；后续全部断言连带失真。另有「48 只固定编排」硬期望，与 40 秒限时 + cap 21 完全不符 | 用例重写：用真实门位条带触发（与 03 同一条路），改为验证**新契约** —— 六结果不得改写派发序列、终端先结算不得提前清房/解封、终端后结算必须等残怪清零、重复交互幂等 |
| 2 | `旧档正式Boss实体未生成`（本轮新增红项） | 新增的 10 号房清房会顺着 flow 规则**自动推开门并预刷 Boss 房**；旧档用例随后进 Boss 房时命中「已刷过 ⇒ 只修进度」分支，考的不是它想考的东西 | 旧档用例进 Boss 房前先清掉预刷状态（`_spawned_rooms`/预约/波次账），把用例还原成「旧档恢复后重新生成 Boss」 |
| 3 | Runner 把 room_07 的存量容量告警算成「非预期错误」 | `preplaced_capacity_insufficient`（room_07 在 1.7 m 间距下少 2 个合法点）是**既有事实**，每次运行都会打印，之前被 54 条红项掩盖 | Runner 加**预期故障白名单**并单独计数：`预期故障 1 非预期错误 0`。不隐藏该缺陷，只不把它冒充成脚本错误 |

用例侧还有一处易踩的顺序坑：`enter(room)` 会从 `segment_runtime_state` 恢复房间快照里上一次的 `cleared/sealed`，所以「重置房间状态」必须放在进房**之后**，否则会被覆盖回去 —— 表现就是「已清房却还没结算终端」。两处重置都已改成进房后执行。

## 3. 另四房的检查结果：链路全通，cap 节流余量按设计保留

同一套 40 秒窗口逐房跑完（真实门位触发 → 冻结 → 首批 → 清批 → 截止关派发 → 残怪清零 → 自动落箱 → 存档恢复），四房全部 `cleared=true / sealed=false / chest=1`：

| 房 | 模板 | cap | 实测批次 | 截止前残怪 | 截止时已派发 | 6 m 合法落点 |
|---|---:|---:|---|---:|---:|---:|
| 04 | 6/6/9/6 | 6 | 6 / 6 / 6 | 3 | 21 | ≥64 |
| 06 | 10/11/16/15 | 13 | 10 / 11 / 13 | 3 | 37 | 46 |
| 09 | 15/19/24/27 | 21 | 15 / 19 / 21 | 3 | 58 | ≥64 |
| 10 | 13/15/18/15 | 13 | 13 / 13 / 2 | 13 | 41 | 53 |

**怎么读这组数**：四房的模板总数大于 cap，所以一批会拆成「cap + 余量」（例如 10 号的第二批 15 = 13 + 2）。这是设计写死的节流语义（「额度不足保留 pending、不重掷、不丢怪」），不是掉怪，**且只在玩家把整批一口清光时才读成两小波**；逐只击杀时补位是连续的，房间不会空。三号房之所以要改，是因为它的余量恰好是 1 只 —— 1 只单独出现已经不像「一波」，而像 bug。

要不要把四房也统一成「cap = 最大模板」是**数值设计决策**，本轮没有擅自改：那会把同屏压力抬到 9/16/24/18，跟 2026-11-16「cap 不提高」的冻结口径正面冲突。数据留在这里，一句话就能改。

## 4. 改动文件

| 文件 | 改动 |
|---|---|
| `data/level_plans/expedition_01/floors/floor_00.json` | room_03：`max_alive` 8→12；末模板 2/2/4→3/3/6（4 行） |
| `art_source/design/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json` | 设计源副本，与运行时**逐字节一致**（源码投影门禁要求） |
| `data/runtime_design_data_manifest.json` | floor_00.json 的 sha256 同步（`5ffbf70e…` → `5eef1ffe…`） |
| `tests/verification/verify_expedition01_spawn_ramp.py` | `WAVES['room_03']` → `[5,7,9,12]`；新增 `TERMINAL_TEMPLATE_OVERRIDE` / `MAX_ALIVE_OVERRIDE`，只有 room_03 走授权分支，其余四房仍逐字比对冻结值 |
| `tests/verification/verify_expedition01_flow_integration.gd` | 03 断言改成严格 5/7/9/12/12 与 45/12/12；新增四房完整窗口用例 `verify_countdown_room()`；六结果段落重写；旧档 Boss 预刷复位；重置顺序修正 |
| `tests/verification/run_expedition01_flow_integration.py` | 预期故障白名单 + 计数 |
| 设计与索引 | 远征01 §11.1 表与正文、触发器 §10.5.2、接入规范、MODULE_INDEX 的 03 模板/cap 同步 |

## 5. 验收

| 编号 | 命令 | 隔离 | 结果 | 退出码与证据 |
|---|---|---|---|---|
| E1 | `python _scratch/run_countdown_rooms.py c2 --room03-timed-only` | `shellstorm-verification.countdown-c2` | 通过 141 项 0 失败；批次 `5/7/9/12/12`、`spawned=45 peak=12` | exit 0；`ShellStorm2-work/verification/shellstorm-verification.countdown-c2/run.log` |
| E2 | `python _scratch/run_countdown_rooms.py c3 --countdown-rooms-only` | `…countdown-c3` | 通过 262 项 0 失败；04/06/09/10 四房 `cleared=true sealed=false chest=1` | exit 0；`…countdown-c3/run.log` |
| E3 | `python tests/verification/run_expedition01_flow_integration.py verify_expedition01_flow_integration --standard-isolation` | 标准套件隔离目录 | **通过：`FLOW_INTEGRATION_OK checks=532 failures=0`**；`预期故障 1 非预期错误 0` | exit 0；`_scratch/full_suite_c8.log` |
| E4 | `python -B tests/verification/verify_expedition01_spawn_ramp.py` | 标准隔离 | 通过：`EXPEDITION01_DATA_OK`，五房模板/ cap 逐房核对，真实 Validator exit 0 | exit 0；`_scratch/ramp_c8.log` |
| E5 | 反向对照：修复前（cap8/末批8）跑 03 段 | 同上 | 按预期变红：第 4 批只 1 只 | 见 `2026-11-17_room03_encounter_settle.md` |
| E6 | `python scripts/check_level_decoupling.py` | 7 个通用机制容器 | 通过：0 violation | exit 0 |
| E7 | `python scripts/check_verification_registry.py` | 313 场景 | 通过：smoke6/core246/visual42/manual19 | exit 0 |
| E8 | `python scripts/check_documentation_contracts.py` | 605 文档 | exit 1，14 条断链，**新增 0**（11 条旧债 + 3 条并行会话引用的 `2026-11-17_small_zombie_v007_eyes_head.md`） | exit 1 |
| E9 | `git diff --check` | 本轮补丁 | 通过 | exit 0 |
| V1 | 真渲染 / 实机 | 未执行 | 待验收 | 不以 headless 代签 |

## 6. 遗留

1. 四房 cap 节流余量保留（§3），是否统一放大待业主裁定。
2. room_07 `preplaced_capacity_insufficient`（少 2 个合法点）是存量缺陷，本轮只做白名单计数，未修。它属于非倒计时房，需另立事务。
3. 三号房末批 12 只意味着同屏 12 个敌人，只在 headless 逻辑下验证过放置与结算，**真渲染帧率与画面拥挤度未验**。
4. `docs/v0.1/README.md` 仍写着「2026-11-12 最新裁定：60 秒」，与 11-16 的 40 秒冻结冲突；属于旧的概览叙述，本轮未改（历史记录不改写），以设计页与 MODULE_INDEX 为准。
5. 五房 HUD 倒计时环在 `cleanup` 阶段的文案与颜色未在真窗口核对。
