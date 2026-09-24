# 2026-09-24 全局验收证据

基线：`bda2c82883091501e57b21d7343e02b0d0d7297b`。总报告见[全局验收](../../2026-09-24_global_acceptance.md)，功能明细见[37项功能表](../../2026-09-24_global_feature_matrix.md)。

| 文件 | 说明 |
|---|---|
| [snapshot.json](snapshot.json) | 时间、提交、功能注册状态、维护边界计数 |
| [static_checks.json](static_checks.json) | 十项静态检查的命令、实际退出码和完整stdout/stderr |
| [registered_tests.json](registered_tests.json) | 当前Runner的场景分类，不把登记当通过 |
| [runtime_results.json](runtime_results.json) | 冷导入阻断与热缓存运行分别记录；每场景退出码、预期故障、非预期错误、脚本错误、跳过标记与结果摘录 |
| [core_failure_comparison.json](core_failure_comparison.json) | 与9月23日§6.3的15项失败集合逐项对比，不以数量相同代替集合相同 |
| [asset_domains.json](asset_domains.json) | 九分账本条目/制作状态、责任Skill存在性与源路径缺失明细 |
| [content_workbook.json](content_workbook.json) | 内容数据库8页/122公式的缓存检查，未重算或签署数值一致 |
| [disk_inventory.json](disk_inventory.json) | 各目录文件内容字节、文件数、Git跟踪数；缓存和输出会动态改变 |
| [old_blender_versions.json](old_blender_versions.json) | 122个旧版候选、按编号最新文件、大小；不是自动删除清单 |
| [feature_matrix.csv](feature_matrix.csv) | 功能逐项表，可筛选Owner、设计状态、优先级与本轮测试 |
| [cleanup_candidates.csv](cleanup_candidates.csv) | 样例/个人文件/未接入素材及待核备份逐文件建议；不同建议不能合并成“可直接删除” |

原始套件日志在忽略目录 `outputs/global_acceptance_20260924/`；摘要保存其SHA-256与失败上下文，避免清理临时产物后只剩“通过/失败”结论。采集脚本也在该临时目录；不会修改游戏源码、账本或资产。

静态门禁只证明其声明的范围。`check_asset_registry --scope full`不检查全部源字段，额外源路径扫描只提取主表O/P/Y列中显式写出的Blend路径，不涵盖任意自然语言、Blender内部链接或所有manifest。未扫描到不等于不存在缺失。
