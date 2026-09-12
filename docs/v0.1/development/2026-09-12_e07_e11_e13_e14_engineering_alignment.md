# E07／E11／E13／E14 工程对齐开发记录

日期：2026-09-12。工程版本：0.1.0。范围：VFX池生命周期、行动身份、测试存档隔离与错误判定。
设计依据：[特效规范](../14.6_特效系统与制作规范.md)、[存档结算规范](../09_技术施工_存档结算与复活.md)、[测试与发布](../11_测试与发布.md)。

## 开发结果

- E07：`retired(effect)`只额外绑定`asset_id`，修复原三参数调用两参数回调；新增池内inactive计数，验证到期回收、同实例复用和退出清理。
- E11：`RunPersistenceService`分离`schema / run_id / checkpoint_id / layout_id`。新行动即使复用同一种子也生成不同`run_id`；旧v1/v2 schema占位身份自动迁移，重载保持稳定；精英遭遇改用`run_id + room_id`。
- E13：统一runner先创建临时项目壳，并在其`project.godot`中配置唯一自定义用户目录。预检和正式场景的所有Autoload均从第一帧使用隔离`user://`，退出时清理临时工程和用户目录。
- E14：runner捕获预检和场景日志。未声明`ERROR`或`SCRIPT ERROR`返回3，资源/ObjectDB泄漏返回4；故障注入的预期错误必须按场景登记正则，不能仅凭进程退出0签署通过。
- E15、E20按用户决定降为`P3暂缓／暂不处理`，本次没有修改渲染场景归类或设施材质。

## 对应文件

- `src/vfx/VfxPool3D.gd`
- `src/world3d/RunPersistenceService.gd`
- `src/world3d/Dungeon3D.gd`
- `scripts/run_verification_suite.sh`
- `scripts/check_verification_log.py`
- `tests/verification/verify_vfx_pool_lifecycle.gd/.tscn`
- `tests/verification/verify_verification_runner_contract.gd/.tscn`
- `tests/verification/verify_room_graph_persistence_services.gd`
- `tests/verification/expected_errors/verify_extraction_points_spend_transaction.txt`
- `tests/tooling/test_check_verification_log.py`

## 验证

- `verify_vfx_pool_lifecycle`：通过。
- `verify_room_graph_persistence_services`：通过，含跨局身份差异和重载稳定性。
- `verify_tower_runtime_restart_restore`：通过；测试退出前释放局部场景引用，严格日志检查下无资源泄漏。
- `verify_verification_runner_contract`：通过，确认Autoload的`OS.get_user_data_dir()`位于唯一隔离目录。
- `verify_extraction_points_spend_transaction`：通过，已声明的revision冲突错误被准确放行。
- `test_check_verification_log.py`：覆盖干净日志、预期错误、非预期错误和资源泄漏四种分类。
