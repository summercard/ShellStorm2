# 审计证据

对应[2026-09-12工程审计](../2026-09-12_engineering_audit.md)，基线`31ed360644768808e6faef5cd3b341b731888625`。证据中的`res://`相对隔离项目，但代码/资源链接同一工作区。存档目录在Autoload启动前由project.godot覆盖，仅导入缓存共用。无全新缓存导入或真实GPU验收。

| 文件 | 内容 |
|---|---|
| [evidence_manifest.json](evidence_manifest.json) | 基线、环境、范围限制、结果摘要及其他证据SHA-256 |
| [source_inventory.json](source_inventory.json) | 全src文件规模、符号依赖数量、Autoload、测试清单和原文档检索情况 |
| [core_output.txt](core_output.txt) / [core_results.json](core_results.json) | 核心61项逐场景原始输出与退出/错误摘要 |
| [failure_probes.txt](failure_probes.txt) / [探针源码](failure_probe_source.gd.txt) | 强制写盘失败时扣款接口与到达门结果；源码保存为txt避免Godot导入 |
| [runtime_autosave.txt](runtime_autosave.txt) / [runtime_restart.txt](runtime_restart.txt) | 普通行动自动保存与重载通过记录 |
| [music.txt](music.txt) | 音乐用例退出0、预期未知ID拒绝及未签署的资源泄漏告警 |
| [postfx_missing_scene.txt](postfx_missing_scene.txt) / [postfx_temporary_scene.txt](postfx_temporary_scene.txt) | 正式验收缺tscn；临时包装后脚本通过 |
| [content_parity.json](content_parity.json) | 内容表行号、字段差异、设计条目、ID与运行数量；null缺省需按语义解释 |
| [asset_registry_check.json](asset_registry_check.json) | 418条资产的检查结果及214条哈希差异 |
| [content_formula_scan.txt](content_formula_scan.txt) / [assets_formula_scan.txt](assets_formula_scan.txt) | 只读公式错误搜索，各匹配0条，不等于原生Excel重算或数据一致 |
| [commit_trace.json](commit_trace.json) | 修改src的35个提交与docs共改情况，不能独立证明设计先行/缺失 |
| [history_migration.json](history_migration.json) / [migration_verification.json](migration_verification.json) | 17处历史迁移清单，链接重定位之外的内容17/17保留 |

复现核心套件时，先创建项目设置壳，设置`application/config/use_custom_user_dir=true`和唯一`application/config/custom_user_dir_name`，其余代码/资源引用当前工程；再从该壳的scripts路径运行`run_verification_suite.sh aggregate core`。不要直接在玩家正式用户数据目录中复跑故障探针。

故障探针只验证已经指出的两个handler级问题，不替代真实键盘交互、磁盘满、进程崩溃、并发保存和目标设备测试。原始临时提取脚本不作为生产代码提交。
