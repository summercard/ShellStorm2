# 工程文档入口

美术制作前另读 [美术制作源与运行资产目录](ART_SOURCE_LAYOUT.md)：当前源统一进入 `art_source/` 并参与 Git/LFS；正式导入文件保持原路径，过程产物写入工程外工作目录。

当前工程版本为 **0.1.0**，版本文档位于 [v0.1](v0.1/README.md)。完整复评原基线为 `a419bc6a`；功能关系计划已对齐新拉取基线 `622d6c4a`（2026-09-23）。文档整理不代表新游戏版本发布。

开始开发依次阅读：

1. [文档驱动开发规范](DOCUMENTATION_STANDARD.md)：如何先确定设计，再实施、验证、记账。
2. [工作区与目录规范](WORKSPACE_LAYOUT.md)：工程根、工程外产物出口与备份的稳定约定；**动手写任何产物前先读这一篇**。
3. [当前功能与契约索引](v0.1/MODULE_INDEX.md)：确定模块所有者、设计依据、数据、接入和验收入口。
4. [游戏设计](v0.1/README.md)及[功能设计目录](v0.1/design/README.md)：先确认目标玩法，再读索引列出的技术施工与当前差距。
5. [2026-09-24全局验收](v0.1/audits/2026-09-24_global_acceptance.md)及[37项逐项验收表](v0.1/audits/2026-09-24_global_feature_matrix.md)：当前工作区的架构、设计、资产、运行验收与磁盘情况；[9月23日复评](v0.1/audits/2026-09-23_full_project_reassessment.md)保留原时点证据。

功能之间的输入、状态Owner、交接与文档补全顺序见[功能关系计划](v0.1/FEATURE_RELATIONSHIP_PLAN.md)和[37项跟踪表](v0.1/FEATURE_RELATIONSHIP_MATRIX.md)。完整复评保留原时点结果；后续实测以开发记录及跟踪表为准。

0.2 的修改登记入口见[0.2 版本计划·变更登记册](v0.2/PLAN.md)：按模块归属追加记录，只登记、不定稿，不提升 `project.godot` 版本号。

旧主题文件路径继续保留以免旧链接失效，但已建立功能设计页的规则主源在 `design/`；未迁移功能在跟踪表标记。开发记录已实际迁入 [development](v0.1/development/README.md)；原变更日志、推送摘要、成品化验收页只保留导航。

`archive/` 仅供回溯。`docs/art/` 保存具体资产批次的验收证据，不能覆盖版本设计。工程**外**的产物一律走 `ShellStorm2-work/`（出口与分目录见[工作区与目录规范](WORKSPACE_LAYOUT.md)）；工程内不留 `outputs/`，必须长期追溯的审计摘要放入版本的 `audits/`。

外部作品的公开资料整理放 [v0.1/reference](v0.1/reference/README.md)：只作写设计页时的**对照样本**，没有 FeatureID、不进 `MODULE_INDEX`、不被 `data/` 或 `src/` 引用，与本工程设计页冲突时一律以设计页为准。
