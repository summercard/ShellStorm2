# 验证测试

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
