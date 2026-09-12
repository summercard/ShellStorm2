# 验证测试

开发与证据记录遵循[文档驱动开发规范](../docs/DOCUMENTATION_STANDARD.md)。当前套件风险与实际结果见[2026-09-12工程审计](../docs/v0.1/audits/2026-09-12_engineering_audit.md)：现有runner尚未统一隔离user://，`full`的真实渲染分类也有遗漏，不应把下面运行模式说明当作已完全实现的保证。测试执行前必须隔离用户存档；设计标准与每次执行结果分别记录。

`verification/` 中每个 `.tscn` 都是可独立运行的 Godot 回归入口，对应脚本同名。测试不得写入存档或正式资产；截图统一输出到 `outputs/verification/`。

常用命令：

```bash
./scripts/run_verification_suite.sh smoke
./scripts/run_verification_suite.sh core
./scripts/run_verification_suite.sh full
./scripts/run_verification_suite.sh visual
./scripts/run_verification_suite.sh scene verify_tower_descent_flow
```

`smoke`、`core` 与 `full` 使用无窗口逻辑回归；`visual` 使用真实渲染器生成截图。选择单个视觉场景时，`scene` 会自动切换到真实渲染模式。

新增测试时使用 `verify_<领域>_<行为>.tscn`，避免阶段号、日期和临时修补名。
