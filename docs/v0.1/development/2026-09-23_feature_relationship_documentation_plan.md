# 功能关系与文档对齐计划交付记录

日期：2026-09-23；记录ID：DOC-RELATIONSHIP-r1；功能ID：37项功能的横向治理；工程版本：`0.1.0`。
设计依据与修订：[文档开发规范](../../DOCUMENTATION_STANDARD.md)、[模块索引](../MODULE_INDEX.md)、[游戏主循环](../README.md)；代码基线：当前工作区；交付提交：工作区。

## 变更与原因

建立[功能关系计划](../FEATURE_RELATIONSHIP_PLAN.md)和[37项跟踪表](../FEATURE_RELATIONSHIP_MATRIX.md)：逐项登记上游、状态Owner、下游、解耦程度、文档缺口与优先级。完成标准改为“关系、交接和验收可查”，不要求所有功能成为独立服务。统一主题设计章节字段和过期事实处理方法。

按当前正式远征主线修正[主设计](../README.md)的一句话愿景；连续向下爬塔保留为用户目标和后续隐藏路线。按本次账本实测把[模块索引](../MODULE_INDEX.md)的资产现状更新为 409 项、9 本分账本、0 异常。历史[完整复评](../audits/2026-09-23_full_project_reassessment.md)添加后续事实提示，原时点结果保留。

## 验证结果

| 命令/核对 | 环境及存档隔离 | 结果 | 证据 |
|---|---|---|---|
| 37项注册表与跟踪表ID双向对照 | 只读文档 | 通过；37/37，无缺失与重复 | 本次核对输出 |
| `python3 scripts/check_documentation_contracts.py` | 只读静态检查 | 通过；119份文档、574本地链接、37功能、0问题 | 本次命令输出 |
| `python3 scripts/check_feature_traceability.py` | 只读静态检查 | 通过；37/37，0问题 | 本次命令输出 |
| `python3 scripts/check_asset_registry.py --scope full` | 只读资产检查 | 通过；409项、0异常 | 本次命令输出 |
| `python3 tools/asset_pipeline/verify_ledger_split.py` | 只读资产检查 | 通过；409项、0漂移 | 本次命令输出 |
| `python3 scripts/check_asset_runtime_naming.py` | 只读资产命名检查 | 通过；无新增债务，历史债务仍为289文件/13目录/1备份 | 本次命令输出 |
| 游戏运行与真实渲染 | 未执行；本次只修改文档 | 未执行 | 保留前次 Core 129项中15项失败的事实，不据此签署新验收 |

## 遗留与状态更新

`GRAPHICS-POSTFX` 独立主设计、商人事务与独立验收、对话契约六处差异、主线场景编排、UI跨域访问、真实渲染和设备验收仍待跟踪表逐项关闭。本文档修正的是当前事实口径和治理计划，未改变 `feature_registry.json` 的实现状态。

后续新拉取 `622d6c4a` 使敌人账本增加1项，当前总数为410/0；本记录中的409/0保留为拉取前的实测。新基线下的关系更新与冲突处理见[后续记录](2026-09-23_feature_relationship_pull_alignment.md)。
