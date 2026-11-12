# 1100 推送帧优化批次 + 两个 git 环境坑

## 业主口述

> 「推送」

## 事实链

- 上一轮我只做了 `提交`（`bc903bb6`），没推。**每日自动提交随后把它连同 `98feb2c5`、`46a6ac1b`
  一起推走了** ⇒ 这次接手时 `HEAD == origin/0.2`，**没有任何待推送提交**。
- 工作区另有 31 项未提交改动（帧优化事务 + DSEG 字体），我按「上次说好等收工再提一次」的意思
  把它们提交成 `962927b3` 并推送：`46a6ac1b..962927b3`，31 文件 / +923 −324。

## 本批内容（六块）

| # | 块 | 落点 |
|---|---|---|
| ① | 开门与首怪 | 刷怪盒候选移到读条期；地砖 5 m 网格索引；一次同步编译复用阻挡采样 |
| ② | 进房存档 | `RunPersistenceService` 后台单写者，最多额外留一个待写档；强制保存/交易/复位留屏障 |
| ③ | 房间走廊流送 + 寻路 | 灯具登记复用；走廊仅状态变时更新；导航多边形读条期准备 |
| ④ | 旧基地四地牢统一读条 | `BaseWorld3D._load_dungeon()` 走 `IrisTransition` → `ExpeditionLoadingScreen` |
| ⑤ | 首弹/受击/首箱预热 | 读取页实绘池化弹体、受击、命中特效、首箱全组件；读条超时改判「无进展 vs 队列前进」 |
| ⑥ | 计时环换真字体 | `assets/ui/fonts/dseg/` DSEG7 Classic Bold Italic + Italic + OFL 许可；`EncounterCountdownRing` 直接用 FontFile 并加 assert |

## 两个 git 坑（本次实际踩到）

1. **`git add -A` 被 SIGTERM 打断会留下 0 字节 `.git/index.lock`。**
   之后所有写操作报 `Unable to create index.lock: File exists`，而 `git status` 正常。
   判据：0 字节 + 没有任何 `git add`/`commit` 进程在跑（用
   `Get-CimInstance Win32_Process -Filter "Name='git.exe'"` 看命令行，
   全是 `diff --numstat` 就没有写者）⇒ 可删。
2. **IDE 会为每个改动文件各起一个 `git diff <commit> --numstat` 子进程**，
   本次积了 115 个一直不退出。它们不写 index，但会拖慢 git 并把 `.git/index.lock`
   的归属判断搅浑。别急着判「有别的会话在提交」，先看命令行是什么。

## 门禁

| 门禁 | 结果 |
|---|---|
| `check_verification_registry` | **OK scenes=306** |
| `check_level_decoupling` | violations **0** |
| `check_asset_runtime_naming` | **OK** 289/13 未增 |
| `check_documentation_contracts` | 11 条断链，**全部既有** |
| `verify_ledger_split` | 红 **109**（与上提交一致，未变） |

## 未收尾（已在提交信息里写明）

`assets/ui/fonts/dseg/` 两个 ttf **没有 .import**，`.godot/imported/` 里只有两个
`.fontdata*.tmp` ⇒ 导入没走完。仓库惯常跟踪 `.import`；首次开编辑器会自动重导，
但 `EncounterCountdownRing` 的 `assert(font_error == OK)` 会在导入完成前失败。
**要验收计时环，先在编辑器里确认字体导入成功。**

## 仍然挂着的三个垃圾文件

`_probe_loop.txt`、`override.cfg.disabled_20261109`、`verify_main_story_boss_gate.report.json`
—— 未跟踪、不在 `.gitignore`，每次都要手动 `git reset` 排除，已经第四轮了。
