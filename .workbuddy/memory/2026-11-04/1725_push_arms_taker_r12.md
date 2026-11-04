# 17:2x 提交 + 推送 b6c2c3db（6 提交 / 106 项 → 落到 6 组）

判据：`HEAD == origin/0.1.2 == b6c2c3dbe8`，`git status -uall` 无输出。
远端起点 `3004502d`（另一会话 01:16 推的）。

## 6 个提交

| 提交 | 内容 |
|---|---|
| `18b3543b` | 收租人 v002：模型重定向（41 骨/18 段）+ 接地 1mm + 16 受击盒 + 步态校准 |
| `8ea87237` | 精英玩法：重击/屏幕放电/定身/隐匿/连遇 3–5 次/夺取 50%/独立清房 |
| `57636aff` | 99F 怪物档案室：42 号双屏终端绑定 + 档案页 3D 预览（UI v002） |
| `c2ea96e3` | 基地 NPC 迎宾节拍（BASE-NPC r5）：首遇收租人后绿苔站边上说两句 |
| `634623a8` | 远征03 刷怪防重只看本房敌群 + 精英独立随机序列 + 快照分开恢复 |
| `b6c2c3db` | 五本账本同步（1434→1436）+ 4 个新验收登记 + 索引 |

## 🔴 房间挂载门禁第三次救场（必须记）

`event_40x30_24e9d88c229b_a653bb` / `storage_40x30_ef3f827636f7_3e5f15` 被编辑器重存后
**丢了全部脚本挂载**：

| 房 | `script = ExtResource` | `.gd` ext_resource | 行数 |
|---|---|---|---|
| event_40x30 | 40 → **0** | 1 → **0** | 4278 → 1324 |
| storage_40x30 | 38 → **0** | 1 → **0** | 3746 → 1196 |

节点数**一个都没少**（270→270 / 249→249）—— 这就是为什么「只比节点数」会全绿。
已 `git checkout --` 还原，坏死版备份在工程外
`ShellStorm2-work/sessions/2026-11-04_commit_recovery/*_workspace_noscript.tscn`。

**这是 11-02 以来同一个坑的第三次**。`.workbuddy/tmp/check_room_script_mounts.py`
现在每次动 tscn 都跑，是唯一能挡住的闸。

## 数值口径（回读代码，别读 commit message）

| 项 | 值 | 来源 |
|---|---|---|
| 收租人体型系数 | **2.5**（1.6 → 2.0 → 2.5） | `EliteContentCatalog` |
| 血条尺寸 | **2.05 × 0.12 m**（原 0.23，收细 48%） | 同上 |
| 双脚受击盒 | 0.058×0.142 / 0.143×0.049（+14%） | `Enemy3D` |
| 连遇次数 | **3–5 次**，累计实伤达**最大生命 10%** 撤离 | `RoamingEliteRunDirector` |
| 初始生命 | 同配置 **×20** | 同上 |
| 夺取概率 | **50%**（30% → 50% 两轮） | `EliteRosterService` |
| 夺取货币 | 当前余额 **10%**，向下取整、正余额最少 1 枚 | 同上 |
| 放电冷却 | **8 s**（从发射母弹起算）；追击 **6 s** 未出手转隐匿，隐匿 **3 s** | `EliteArmsTakerCombat` |
| 放电距离 | 水平 **4–12 m**、高度差 ≤1.5 m | 同上 |

## 记忆/口径要点

1. **`narrative_history` 多了一个命名空间**：`npc_beat:<npc_id>:<beat_id>`。
   这张表原本只放剧本身份（`nar_*`），现在混入非剧本键 —— 09 号文档已登记，
   验收 S08 断言前缀。**以后往这张表加键必须登记，否则会和剧本 ID 撞。**
2. **气泡挂高 3.40 m 是业主三轮调出的「两行」值**，不要为长台词再抬。
   台词超 24 字就要拆句轮播（`wrap_width_px 560` ≈ 11 汉字/行）。
3. **营地 NPC 的 `_player` 是 1.5 m 热区引用**，判「走近」必须另取 `player_3d` 组。

## 门禁（我本轮独立复跑）

| 门禁 | 读数 |
|---|---|
| `verify_ledger_split` | OK **assets=1436** ledgers=9 failure_count=0 |
| `check_level_decoupling` | violations **0** |
| `sync_runtime_design_data --check` | `{"files": 42, "issues": []}` |
| 房间脚本挂载门禁 | 30+ tscn 全绿（挡下 2 间房） |

## 已知非阻断项

- `ledger_split_baseline.json` 的 `captured_at` 停在 `2026-11-04T01:16:18+08:00`，
  行内容已 1436 —— **又只刷行指纹没刷时间戳**。没去动全部 `column_digests`，
  因为会把同工作区别人的既有漂移一起吸收。
- `.xlsx.before_*` 快照已加 `.gitignore`（`assets/registry/ledgers/*.before_*`）：
  账本本体在库，改前版本随时能取回，快照纯冗余（单对 570 KB）。

## 未执行（本机）

`verify_arms_taker_*` / `verify_monster_archive_facility` / `verify_base_npc_story_beat`
全部**未在本会话跑过**，读数均来自并发会话日志（退出 0 / 日志门禁 0）。
真实渲染、目标设备矩阵、完整通关也未做。
