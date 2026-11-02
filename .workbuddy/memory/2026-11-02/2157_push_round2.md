# 21:57 推送 1c14dc1b（6 提交 / 166 项 → 落到 148 项）

判据：`HEAD == origin/0.1.2 == 1c14dc1b88`。push 一次过，未用代理（remote 是 SSH `git@github.com:...`，
不走 `http.proxy`；本次 fetch/push 都直连通）。

## 提交拆分（按事务，不 `git add -A`）

| 提交 | 内容 |
|---|---|
| `ccd6379f` | 枪械开火反馈（后坐回弹 + 弹性压扁），复用上一会话已 staged 的 13 项 |
| `558cf6ac` | 远征03 陈设缩放定稿 + 地毯亚光 + 灯具暖光，21 间房重烘焙 + 51 张对照图 |
| `02bbfa15` | 99F 基地 NPC「绿苔」+ 苔绿作业服 + 气泡 r4 |
| `bae2561b` | 易碎陈设掉币 10% / 1–10 枚 / 落地锁 0.5 s |
| `1c14dc1b` | 账本三件 + MODULE_INDEX + CHANGELOG + feature_registry + 今日记忆 |
|（此前）| `a5b975f0` 角色随身三盏灯配色与能量定稿 |

## 推送前必跑的房间挂载门禁（新增脚本）

`.workbuddy/tmp/check_room_script_mounts.py`：对每个已改动的 `.tscn`，
比 HEAD 与工作区的 `nodes` / `script = ExtResource` / `ext_resource *.gd` 三个计数。
**任一计数下降即退出 1**。本次 30 个 tscn 全绿（21 间房 script 挂载全部持平）。

> 为什么必须有这条：2026-11-02 两次实测「编辑器重存房间丢 BreakableClutter3D 挂载」
> （storage_25x25 丢 23 个、另外 4 间丢 179 个）。只比 nodes 不变会全绿，必须比 script 计数。

## ⚠ 4 篇开发记录是孤儿：文档写了、代码没落地

`git status` 里这 4 篇 `docs/v0.1/development/*.md` 是 untracked，但**它们声称的改动在工作区里不存在**。
逐条实测（2026-11-02 22:00）：

| 文档 | 声称 | 实测 |
|---|---|---|
| `2026-11-02_pistol_damage_30.md` | 枪身 `damage` 25→30 | `BlueprintRegistry.gd:531` 仍是 `"damage": 25` |
| `2026-11-02_monster_hp_and_naming.md` | 小僵尸 350→280、胖子 800→650 | `data/level_plans/expedition_01/level_plan.json` 仍是 350 / 800；`git status -- data/` 空 |
| `2026-11-02_enemy_action_recovery.md` | 新增 `Enemy3D._tick_action_state()` | 全文 grep 计数 **0** |
| `2026-11-02_expedition01_room01_entry_buffer.md` | 后移 box 拉进场缓冲 | `data/` 零改动 |

配套的 `tests/verification/verify_enemy_action_recovery.*`（3 个文件）同样未提交 ——
它测的实现不在，提交进去就是一条必红的验收，且会让 `check_documentation_contracts`
多一条 `unregistered` 红项（当前已因它多报 1 条）。

改前快照还在：`ShellStorm2-backup/2026-11-02_monster_hp_rename/before_edits/`（json + xlsx + csv）、
`ShellStorm2-backup/2026-11-02_room01_entry_buffer/before_edits/floor_00.json.design_src`。
⇒ 重做可行，但要按文档重跑一遍并复验，别直接信文档里的"已通过"。

**成因推测**：CHANGELOG 里已写明本轮「17:07 一次 `git pull --rebase` 把上一轮未提交的 `.gd` 改动
连同 README 索引、CHANGELOG 条目一起冲掉（开发记录 md 是 untracked，反而幸存）」——
同一形态：untracked 的 md 活着，被跟踪的 `.gd`/`.json` 改动被洗掉了。

## 顺手修的两处文档矛盾（已进 `1c14dc1b`）

- CHANGELOG 金币条目里「**平衡**：535×60%≈1766 枚、29 倍」旧段与新的「平衡（10%）」并存 ⇒ 删旧段。
- `.workbuddy/memory/2026-11-02/_INDEX.md` 第一条 `1521_expedition03_seat_rug_scale.md` **文件不存在**
  ⇒ 删死链行（该事务的记录没有落盘，同日 17:35 那篇覆盖了同一主题）。

## 门禁读数

- `verify_ledger_split.py` → `LEDGER_SPLIT_VERIFY_OK assets=1418 ledgers=9 failure_count=0`（1417→1418，+1 NPC）
- `check_level_decoupling.py` → violations 0
- `check_documentation_contracts.py` → 487 文档 / 2585 本地链接；15 条断链全是既有旧文档，
  本次新增文档零断链；`unregistered` 4 条 = 既有 3 条 + 孤儿 `verify_enemy_action_recovery`
- 裸 `python3` 无 `openpyxl` ⇒ 用 `~/.workbuddy/binaries/python/envs/default/Scripts/python.exe`（3.1.5）
