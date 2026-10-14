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
- **Godot `.gd.uid` 跨机器不一致**（2026-10-14 实测）：同一脚本在两台机生成的 uid 可能不同
  （`preview_debug_camera_fog_panel.gd.uid` 本机 `eoto4i6txytq` vs 远端 `eqgcha02lcka`）。
  **以仓库已跟踪版本为准**；本机那份是未跟踪产物，会让 rebase 报
  `untracked working tree files would be overwritten` ⇒ 先移走本机副本再拉取。
  判据：`grep -rl "<uid>"` 看有无 `.tscn/.tres` 引用；本项目 `.tscn` 多用 `path=`（不带 uid）
  引用脚本，故 uid 内容差异通常不影响任何引用。

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

