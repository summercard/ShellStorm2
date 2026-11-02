# 23:35 推送 88fd67bc（清空工作区，业主「不要漏东西」）

判据：`HEAD == origin/0.1.2 == 88fd67bc68`，`git status -uall` 完全无输出。

## 两个提交

| 提交 | 内容 |
|---|---|
| `7ede4b54` | 两个改前快照入库：`2026-11-02_monster_hp_rename/before_edits/`（level_plan.json + 内容数据库.xlsx + 怪物掉落表.csv）、`2026-11-02_room01_entry_buffer/before_edits/floor_00.json.design_src` |
| `88fd67bc` | 4 篇孤儿开发记录 + `verify_enemy_action_recovery.*`（每篇顶部加了「未落地」状态标注） |

## ⚠ 这轮破了两条长期约定，都是业主当次授权的

1. **备份入库**：MEMORY.md 写「备份本身不入库」（2026-10-17 整批移出跟踪，HEAD 只留过 2 个）。
   业主明确「都要提交和推送，不要漏东西」⇒ 本次入库 4 个快照，commit message 已留痕。
   **实现补齐后要回头决定是否移出跟踪**，否则这条约定就默认失效了。
2. **提交了必红的验收器**：`verify_enemy_action_recovery` 测的实现不存在。
   `check_documentation_contracts` 会多报 1 条 `unregistered`。已入库并在文档标注，不是偷偷放绿。

## 「文档在、实现没」的完整形态（两次实测，同一根因）

被 tracked 的 `.gd` / `.json` 被 `git pull --rebase` 洗掉，untracked 的 md 幸存 ⇒
仓库里留下 4 篇"已完成"的假记录。**判据必须逐条敲，不能读文档下结论**：

| 文档 | 声称 | 判据 |
|---|---|---|
| pistol_damage_30 | damage 25→30 | `BlueprintRegistry.gd:531` 仍 25 |
| monster_hp_and_naming | 350→280 / 800→650 | level_plan.json 仍 350 / 800 |
| enemy_action_recovery | `_tick_action_state()` | grep 计数 0 |
| room01_entry_buffer | box 后移 | floor_00.json 坐标未变 |

**教训固化**：以后 `git pull` 前先 commit（哪怕 WIP），或至少 `git stash`。
`--rebase` 遇到脏工作区会拒绝，但如果本地改动已被 add 未 commit 且远端有同名文件变更，
rebase 过程中可能被覆盖 —— 这轮就是这么丢的。

## 上一轮遗留待办（未做）

4 件实现待补：手枪 damage 30、远征01 怪物 HP 280/650 + 改名、怪物技能恢复状态机、room_01 进场缓冲。
改前快照都在 `ShellStorm2-backup/`，重做后要复跑各自验收。
