# ShellStorm2 项目长期记忆

## 工作区操作风险（2026-10-13 实测）
- **本仓库可能有多会话并发操作同一工作区**（同期既有改代码的会话，也有 Godot 编辑器常驻）。
  动手前先 `git -c core.quotePath=false status --porcelain -uall` 取真实状态，不要依赖上一轮快照。
- **`git reset` 会静默回退已跟踪改动**：2026-10-13 23:34:36 的一次 `reset: moving to HEAD`
  使「特效账本子弹特效大类」4 个已跟踪文件（特效账本 xlsx / 美术资产台账 xlsx / ledger_index.json /
  split_asset_ledger.py）回到改前，而未跟踪的备份与开发记录保留。
  ⇒ 改动前后都要核对 SHA，不要只看退出码 0 的门禁结果。
- **`git pull --rebase` 是第二种回退矢量**（2026-10-14 实测）：远端重放提交会与本地未提交改动「并」掉，
  已跟踪文件被冲回改前；未跟踪文件（`pull/rebase` 不触碰）完好。⇒ **已跟踪改动的「完成」必须以提交为准**，
  未提交随时可能被并行 `pull/rebase/reset` 覆盖。
- **改前备份约定**：`.workbuddy/backup/<YYYYMMDD>_<主题>/`（`before_edits/` 冻结原文件 +
  一键重放脚本）；按仓库约定这些**回退指针要入库**。
- **Godot 常驻会把 `.glb.import` 批量改写**（拉取后 1311 个文件新增
  `mesh_library/use_node_names_as_mesh_names` 等引擎默认键）——属引擎版本差异，**不是内容改动，不要提交**。
- **远端领先时的推送顺序（2026-10-14 实测）**：`git status -sb` 显示 `behind N` 时必须
  **先提交自己的改动 → `git fetch` → `git rebase origin/<分支>` → `git push`**；顺序颠倒
  （先 pull/rebase）会把未提交的已跟踪改动并掉。变基冲突面通常只在
  `.workbuddy/memory/<日期>.md`（各会话都往末尾追加）⇒ 解法是**两侧块都保留**、按时间排序
  （旧在前）、删掉 3 个标记行，再用 `git show <commit>:<file>` 逐块 diff 证明两侧逐字完整。
- **第二个高频冲突面＝`docs/v0.1/MODULE_INDEX.md` 的功能表格行**（2026-10-16 实测）：
  两个会话同时改相邻的 `| FEATURE-ID | … |` 行时，git 会把它们当成同一区块冲突，
  两侧各带 1 行自己的更新 ⇒ 解法是**逐行取各自较新的一侧**（不是整块取一侧），
  保持表格行数结构完整；判据＝`grep -c '^<<<<<<<'` 归零后逐行核对。
  同批 `assets/registry/ledger_split_baseline.json` 若只是两侧各自新增键/改 digest，
  git 通常能**自动合并**，但必须用 `git diff origin/<分支> -- <file>` 逐块确认两侧改动都在
  （本次保留远端 3 处 UI 摘要 + 本地 2 张特效，`asset_count` 1280→1282）。
- **门禁要取「合并前后同数值」为基线，而不是只看退出码**（2026-10-16 实测）：账本/命名/文档三条门禁
  本就常红（既有债务），判据是 **merge 前后逐项数值完全相同 = 本次 0 新增问题**。
  本机**没有 `timeout` 命令**（`command not found`），长命令别用它包裹；门禁需 `python3` 带
  `openpyxl` ⇒ 用 `/tmp/pyshim` 垫片（`#!/bin/sh` + `exec <venv>/bin/python "$@"`）前置进 PATH。
- **Godot `.gd.uid` 跨机器不一致**（2026-10-14 实测）：同一脚本在两台机生成的 uid 可能不同
  （`preview_debug_camera_fog_panel.gd.uid` 本机 `eoto4i6txytq` vs 远端 `eqgcha02lcka`）。
  **以仓库已跟踪版本为准**；本机那份是未跟踪产物，会让 rebase 报
  `untracked working tree files would be overwritten` ⇒ 先移走本机副本再拉取。
  判据：`grep -rl "<uid>"` 看有无 `.tscn/.tres` 引用；本项目 `.tscn` 多用 `path=`（不带 uid）
  引用脚本，故 uid 内容差异通常不影响任何引用。

- **「僵尸冲突态」：`UU` 残留但 `merge --abort`/`rebase --abort` 都报没有进行中的操作**（2026-10-16 实测）：
  表现为 `status` 有 `UU` 行、`.git/` 里躺着 `REBASE_HEAD` + `AUTO_MERGE`，却既无 `MERGE_HEAD`
  也无 `rebase-merge/`、`rebase-apply/` 目录（上次合并被别的会话/中断打断后留下的孤儿状态）。
  ⇒ 判据是 `git rev-list --left-right --count HEAD...origin/<分支>`：**`0  0` 说明 HEAD 已等于远端最新**，
  此时「拉取最新」无事可做，要清的只是本地残留 ⇒ 先备份涉及文件，再
  `git reset --hard HEAD`（HEAD 即线上版本）+ `rm -f .git/REBASE_HEAD .git/AUTO_MERGE`。
  未跟踪文件（本地新写的评审报告等）不受影响，会保留。
- **`.git/index.lock` 陈旧锁会潜伏到第一次写操作**（2026-10-15 实测）：当天 08:44 中断遗留的锁，
  直到中午 `git add` 才报 `Unable to create index.lock`（只读的 `status/diff/fetch` 从不撞它）。
  ⇒ 删除前必须两条同时成立：无 `git`/`git-lfs`/`ssh` 进程，且 `status --porcelain` 第一列全空
  （index 无残留暂存）。确认后再 `rm -f .git/index.lock`。
- **`Uploading LFS objects: 100% … done` 不等于推送成功**（2026-10-15、10-17 两次实测，
  已升级为规律：**本次含新的大 LFS 对象时，第一次 push 几乎必定「传完就断」**）：
  长传之后 GitHub 会 `Connection to github.com closed by remote host`，LFS 对象全上去了、
  但 ref 没更新（远端仍停旧提交、本地仍 `ahead N`）。
  ⇒ **推送唯一判据**：`git fetch` 后 `git rev-parse HEAD` 与 `git rev-parse origin/<分支>`
  逐字相同。不符就原样重跑 `git push`（已传 LFS 不重传，第二次几十秒完成）。
  ⇒ 推送流程固定为「push → 复核 SHA → 不符原样再 push 一次」，**不要只信一次退出码**。
  ⇒ 排期参考：本机到 GitHub LFS 上行 46–515 KB/s；472 MiB（67 个 blend）约 1h16m，
  单个 512 MiB 的 blend 约 20m（峰值 515 KB/s）。大批 blend 按小时排窗口。
  ⇒ 月度流量：10-15（498 MB）+ 10-17（538 MB）已 ≈1.01 GB，越过 GitHub Free 的 1 GB/月
  额度线，**时间点与「传完必断」吻合**。动画源策略待定（建议只留当前版进 LFS，
  历史版归档本地/NAS）—— 拍板后再写成硬约定。

## 本机环境
- 只有 `Documents/ShellStorm2` 一个 Git 工程根；`ShellStorm2-work/`、`ShellStorm2-backup/`
  不存在（`WORKSPACE_LAYOUT.md` 按 Windows `I:/工作项目/` 布局写）⇒ 文档里指向 `../ShellStorm2-backup/`
  的链接必然断。
- 系统 `python3` 缺 `openpyxl`；`check_documentation_contracts.py` 用**裸 `python3`** 起子检查，
  故 `check_media_asset_domains.py` 会 ModuleNotFoundError。修法是造 ASCII 目录放 `python3`
  wrapper（`exec <venv>/bin/python "$@"`）前置进 PATH；`ln -s` 指向 venv python 无效。
- 账本类门禁：`scripts/check_asset_registry.py`（只读《资产主表》）、
  `tools/asset_pipeline/verify_ledger_split.py`、`scripts/check_asset_runtime_naming.py`；
  基线 `ledger_split_baseline.json` 每次新增资产后需按 `refresh_current_baseline` 口径重建。
## 引擎/玩法约定（踩出来的，别重犯）
- **敌人的「受击体积」绝不能挂在敌人自己的 `CharacterBody3D` 上**。
  受击盒要贴模型，就会伸进地面（坐地/倒地）和墙里（扑砸/甩击）；挂在本体上时
  `move_and_slide` 会把它们当承重面，把怪**顶起来/推开**（2026-10-14 实测：显示器Boss 坐地被抬 0.417 m、
  砸地被推开 0.26 m）。正确做法＝另起一个 `StaticBody3D` 被动体（`collision_layer` 与本体同层、
  **`collision_mask = 0`**），逐帧跟骨姿态，命中的伤害转发回本体。参考 `src/enemy3d/EnemyHitVolume3D.gd`。
  ⚠ 转发清单是**隐形契约**：子弹拿到的 `collider` 是代理，漏转发就会静默不掉血。
  ⇒ 必须有一条断言逐条盯着转发面（见 `verify_monitor_boss_flow`）。
- **用实测 AABB 当碰撞盒时，盒子不能切得刚刚好**：表面顶点恰好落在边界上，浮点舍入会把它们判到盒外
  （2026-10-14 实测残余 1.85%）。每轴外扩 3 cm 后归零。
- **求动画包络必须逐帧**，抽帧会漏极值（11 帧/剪辑 ⇒ 盒子偏小）；
  且「单骨但权重未归一」的顶点会被蒙皮按权重缩放，不能当刚性顶点一次算完。
- **层语义（3D）**：layer 1 = 静态世界/玩家；layer 3（值 4）= 敌人；layer 4（值 8）= 投射物。
  玩家子弹 `collision_mask = 1|4 = 5`；**敌人/玩家/怪的移动掩码都是 1** ⇒ layer 3 的唯一消费者是玩家子弹。
  所有视线/遮挡射线（`_has_line_of_sight` / `MonsterVisionSystem3D` / `EnemyIllumination3D`）掩码都是 1，
  所以给敌人加受击形状**不会**影响任何视线判定。

## 定时自动化（2026-10-14 建立）
- **每日 04:00「回收站清空 + git 提交推送」**（id `ffe9a3c7-9988-4d1c-a54b-91f236d720e8`，
  cwd `I:\工作项目\shellstrom2`）。**硬顺序：先 git 提交并推送，再清空回收站** ——
  不可逆操作必须排在「成果保险」之后，顺序不许颠倒。
- 同域自动化形成接力：**23:50 每日工作总结（写记忆文件）→ 04:00 本次提交推送 → 05:00 每日打包并发布**。
  前一步的产物正是后一步的输入，改时间要一起看。
- 仓库是 `I:\工作项目\shellstrom2\ShellStorm2`（工作区根目录下的子目录），
  远程 `git@github.com:summercard/ShellStorm2.git`，**主干分支是 `0.1.2` 不是 main**。
  LFS 已启用：`.blend` / `.psd` / `art_source/**/*.mp4` 走 LFS，运行资产（如 8 MB 的
  `assets/movie/opening_mv.ogv`）保持普通文件。

### 回收站清空的实测口径（2026-10-14 23:59 首跑）
- 战果：**5.3 GB / 64883 条 → 残余 70 个实体 / 0.96 MB**。
  来源几乎全是本机自动产物：`ShellStorm2-work`（Godot 验证临时工程整包副本，占 4.1 GB）、
  `AppData\Roaming\ShellStorm2*Probe`、`_manual` 整包副本、导出的
  `outputs\daily_release\ShellStorm2.exe`（368 MB）、`scratch\ffmpeg_btbn\btbn.zip`（191 MB）。
- `purge` 无参数即逐盘清；`E:/G:/H:` 报 `OSError(22, 灾难性故障, -2147418113)` 属**正常**
  （这些盘没配回收站），不是脚本故障。
- **清空后残余永远不为 0，不要判失败**：本机有常驻 Godot 探针（`ShellStorm2OpeningMovieProbe`、
  `弹壳风暴2` 等），每写一次档就把上一份 `base_save.json.bak` 丢进回收站 ⇒ verify 里会出现
  一路推进到当前分钟的时间戳。那是活水，不是残余没清掉。
- `scan -o <中文路径>` 在本机曾无声 SIGTERM（exit 1，报告没落盘）；不带 `-o` 直接跑 stdout 正常
  ⇒ 审计报告宁可走 stdout 重定向，别依赖 `-o`。

## 引擎/玩法约定（踩出来的，别重犯）· 续
- **敌人的「受击体积」绝不能让老碰撞体继续留在子弹层**。2026-10-14 显示器 Boss 两轮才修对：
  第一轮只补了跟骨走的受击盒，但根节点那个固定圆柱**还留在子弹层**，它比可见模型宽得多
  （半径 2.016 m vs 屏幕半宽 0.85 m），子弹在屏幕**前方 1.0–1.3 m** 就被它吃掉 ——
  诊断方法：把 `collision.get_collider()` 的名字打出来，一眼就能看出是谁拦的。
  ⇒ 补受击盒的同时，**必须把老碰撞体移出子弹层**（`collision_layer = 0`）。
  安全检查：自身移动只看 `collision_mask`，所以移出层不影响走位/阻挡；
  第 3 层（值 4）的消费者全工程只有玩家子弹（掩码 5）与回旋镖返航（掩码 4）。
- **「全动画并集」算骨局部盒子会撑胖**：权重被混合（如 0.6/0.4）的顶点会在骨局部空间
  随动画漂移（实测 `hand.L` 体积达几何的 **9.5 倍**）。**只用「单骨且权重恰 1.0」的刚性顶点**定尺寸。
  例外：本就沿骨轴伸缩的弹簧/伸缩件（顶点在骨局部空间里真的会动），取并集才对。
- **验收探针要冻结被测对象**：`set_runtime_active(true)` 会把 `_physics_process` 重新打开，
  怪物会一边挨打一边走位，量出来的误差能假红到 3 m 以上。手动调 `_process` 同步 + `set_physics_process(false)`。
- **量「命中精度」要瞄看得见的模型顶点，不要瞄碰撞盒中心**：倾斜姿态下盒中心可能悬空中，
  那是过度悲观（也过乐观）的测法。判据用**中位数**（真回归会整体位移），尾部另查明来源。

