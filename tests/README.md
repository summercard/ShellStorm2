# 验证测试

开发与证据记录遵循[文档驱动开发规范](../docs/DOCUMENTATION_STANDARD.md)。当前套件风险与实际结果见[2026-09-12工程审计](../docs/v0.1/audits/2026-09-12_engineering_audit.md)。统一runner现在会在Autoload启动前建立独立项目壳与唯一`user://`；`full`的真实渲染分类仍由E15暂缓项跟踪。设计标准与每次执行结果分别记录。

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

runner会检查每个场景的完整日志。故障注入确实需要产生`ERROR`时，在`verification/expected_errors/<场景名>.txt`登记最窄可识别正则；未登记脚本错误返回3，资源或ObjectDB泄漏返回4，均不能凭Godot退出0计为通过。`verify_verification_runner_contract`验证预检与Autoload使用隔离用户目录。

资源扣款事务使用 `verify_extraction_points_spend_transaction.tscn`：覆盖正常持久化、强制写盘失败回滚、余额/参数拒绝和旧revision实例重新加载权威档案。revision冲突分支会产生一条预期的`Refusing stale save`错误日志，验收记录必须与非预期脚本错误分开。

行动结算事务使用 `verify_run_settlement_transaction.tscn`：覆盖成功撤离与死亡结算的一次提交、强制写盘失败整体回滚、故障解除后重试、同事务重复请求及重新加载后的幂等重放。
