# 2026-10-11 工程瘦身执行记录

FeatureID：ASSET-PIPELINE / WORLD-BLOCKS。游戏版本0.1.0，Git分支0.1.2，实施前HEAD `5ab18194`。用户授权两阶段一起执行，制作源分别保留最新版本，旧版移到上层备份。工程契约见[资产目录规范](../../../assets/art/3D模型资产目录与命名规范.md)，原计划见[瘦身计划](../audits/2026-10-11_development_workspace_slimming_plan.md)。

## 结果

| 项目 | 整理前 | 整理后 |
|---|---:|---:|
| ShellStorm2工程根（不跟随目录链接） | 59.481 GiB / 337,563文件 | 约12.69 GiB / 100,283文件 |
| 工程根扣除导入缓存 | — | 约12.06 GiB |
| `.godot`缓存 | 6.86 GiB | 约0.63 GiB |
| 实测Windows PCK | 1,973.90 MiB / 34,828项 | 502.73 MiB / 7,450项 |

工程根缩小约78.7%，导出包缩小74.53%。以上是普通文件大小合计，链接目标不重复计算；后续编辑器导入和新资产会使数字变化。所有Git历史继续保留（约5.92 GiB），没有提交、改写历史或重置用户原有改动。

上层备份约47.54 GiB，审计工作区约0.50 GiB。**这是同盘迁移，不是释放I盘空间**。旧缓存已移出工程根，自动审批拒绝永久删除该缓存，故仍在备份中；本轮未永久删除原始制作源、文档或历史产物。

## 现在的目录职责

> 本节是该时点的布局快照。**常驻规范已独立成文：[工作区与目录规范](../../WORKSPACE_LAYOUT.md)** —— 后续布局以那一篇为准，本节只在回溯本轮瘦身时参考。

```text
shellstrom2/
├─ ShellStorm2/                       唯一Git + Godot工程根
│  ├─ src/、scenes/、data/             正式代码、场景、运行数据
│  ├─ assets/art/**/components/       正式GLB/贴图；路径保持稳定
│  ├─ assets/art/**/runtime/          正式Godot包装与布局
│  ├─ assets/art/**/source/           当前可编辑母版，Godot忽略导入
│  ├─ source/                         设计白模、布局、找回的独有源；忽略导入
│  ├─ assets/registry/                九分账本、当前源索引、旧源归档索引
│  ├─ docs/、scripts/、tools/、tests/  文档、必要工具与验收入口
│  └─ .godot/                         本机可重建缓存
├─ ShellStorm2-backup/2026-10-11_slimming/
│  ├─ original_tree/                  按原工程相对路径保留迁走的文件
│  ├─ before_edits/                   本轮改动前代码、文档、账本和本机导出配置
│  └─ management/                     搬迁日志、校验、基线与恢复清单
├─ ShellStorm2-work/                 导出包、隔离验证、日志、会话临时产物
└─ 结构打包审计_20261011/            原始审计与候选分析
```

`outputs`、`_scratch`、旧build、日志与会话临时目录完整归档。469份旧版Blender源、自动备份、制作预览与渲染产物移到备份；当前共1,102份独立制作源保留在工程内，其中3份从临时目录找回到 `art_source/intake_recovered/2026-10-11/`。模型、动画、组件、优化件分别判断版本，不能按整个资产目录的最高版本号删除其余文件种类。源内容未改写；共5份母版含外链，所有库依赖仍存在。另补齐两处相对色盘依赖的小文件副本，其中一处为原有错误路径，未改写Blender母版。

九分账本只调整88个旧源路径单元格，AssetID、状态、版本、哈希与公式保持；历史记录指向归档文件，不升级为当前资产。18个文档链接同步指向归档，历史设计与正文保留。账本登记的一份正式预览图继续留在原路径，并用 `.gdignore` 禁止导入。

## 运行数据和打包边界

39份设计JSON由 `scripts/sync_runtime_design_data.py` 原样投影到 `data/level_plans/` 与 `data/layouts/`。设计原件继续是唯一编辑源；同步工具不改变参数、拓扑、坐标或怪物规则，`--check`核对完整内容与SHA-256。LevelPlanLoader、办公室布局、房型布局和天台读取路径改为运行数据目录。解决原先 `source/.gdignore` 使三处必需JSON缺席发行包的问题。

正式运行GLB、TSCN、贴图、音频路径保留，现有玩家production/v021等必要运行依赖未因“只留最新制作源”被搬走。旧运行包装和动画回退资源与旧Blender制作文件是不同层，不能按版本号一起删除。

本机Windows、Android Debug/Release导出配置排除文档、测试、工具、脚本、账本、QA和原始参考目录，默认成品落到上层 `ShellStorm2-work/build/`。`export_presets.cfg`依旧不入Git；新机器创建本机preset后执行 `python scripts/configure_export_boundaries.py`恢复共享边界，签名设置保留。

## 验证及限制

- Godot4.6.3全新导入退出0，无SCRIPT ERROR/ERROR；当前源结构头检查1,102份，5份外链源全部依赖存在；五份外链母版用Blender4.5.3实际打开。二进制图像路径扫描不等于全量逐个材质视觉验收。
- 正式运行资源3,449份内容哈希完全未变。源归档逐文件SHA-256前后相同，目录搬迁核对文件数/大小并登记链接，不跟随junction。
- 分账本无损门禁0失败：1,062资产、9账本；完整资产检查仍有原来的514项sha_mismatch，按归档路径归一后问题逐项完全一致，没有新增缺失文件。
- 楼层生成4,000计划/1,000种子；设计源3关卡/33房间/18模板；玩家方向270、射击373、换枪96、换弹225项检查通过。
- 最终验证runner专项退出0，`VERIFICATION_SUITE_OK suite=scene count=1`；隔离目录已清理。Windows隔离使用原生junction，避免Git Bash `ln -s`静默复制整工程；安全清理只删除链接本身，不穿透真实工程。异常退出后的陈旧工作区也按工程外边界清理。视觉输出通过环境变量固定到上层work目录。
- PCK目录实测开发区违规项0；39份投影JSON逐字节一致；独立空工程挂载PCK后的40项JSON检查全部通过。PCK SHA-256 `6c38ee99c2f38d659b06e7fae20535c97ea718adb4b82c772d7d2c5a62ff3bad`。
- 完整游戏流程仍失败：初始霰弹枪不能进入12格背包、玩家八态白名单、原型节点预算（2,805）。用本轮编辑前src和独立存档复跑，三项错误及节点数完全一致，不提升总体游戏验收状态。
- 命名门禁保留整理前的14文件/3目录新增欠账、TSCN引用93→98及9个GD引用欠账；没有扩大豁免或批量接受哈希漂移。
- 文档门禁仍有原有缺失的Boss002记录链接、6个未登记验证用例；本机python3缺openpyxl导致媒体域检查无法运行。新产生的18个归档断链已修复。全局红项不在本轮瘦身范围内。
- 最初batch在结束处因实施期间改写runner触发脚本读取偏移错误；当前文件bash语法检查及重新执行的runner专项均通过。此项没有作为测试通过依据。
- 未做Android APK实际打包、手机运行或全场景真实渲染；历史作者脚本保留作追溯，重新生成旧版本时需先恢复其旧源输入，部分旧探针仍含工程内输出路径，运行后卫生检查会提示。

## 日常操作与恢复

编辑设计JSON后先运行 `python scripts/sync_runtime_design_data.py`；提交前运行其 `--check`、`python scripts/check_workspace_hygiene.py`以及相应验收。新增制作源按资产家族更新账本和当前源索引，旧版在最新文件及外链验收后再归档；保持运行稳定路径。临时产物用 `scripts/workspace_paths.py` 的work_path或验证统一出口，避免新建工程内整项目副本。

当前源索引：`assets/registry/current_source_index.json`（路径、字节数、SHA-256）。旧源索引：`assets/registry/source_archive_index.json`。完整迁移记录位于上层备份 `management/moves.jsonl`，每条含原位置、新位置、理由和校验结果。历史脚本要重跑旧制作批次时，先按索引将所需旧源恢复至原相对路径，使其库路径继续相对真实工程解析；不要直接批量覆盖现在的source目录。

回滚本轮路径/配置改动时，以 `before_edits/` 为本轮开始时的副本，逐个比对后恢复相关文件；迁走的源和证据从 `original_tree/` 按原路径恢复。最新源与运行资产完整留在工程；完整Git历史可另行取回已跟踪旧文件。不要用整树覆盖覆盖后续制作进展。

详细日志：上层备份management与work的 `sessions/2026-10-11_slimming/`。本轮未执行Git提交。
