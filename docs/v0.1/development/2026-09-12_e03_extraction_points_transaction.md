# E03资源扣款失败回滚

日期：2026-09-12；记录ID：E03-FIX-20260912；功能ID：BASE-SHOP / SAVE-PROFILE；工程版本：0.1.0。
设计依据与修订：[存档结算与复活](../09_技术施工_存档结算与复活.md)现行强一致规则；设计语义未改变。
代码基线：`31ed360644768808e6faef5cd3b341b731888625`；交付提交：工作区，提交后补充。

## 变更与原因

原`BaseManager.spend_extraction_points`先扣内存余额，忽略`save_base`结果并固定返回成功。强制写盘失败时会出现内存430、磁盘500却向调用者报告成功。

- 扣款金额必须大于0，余额不足、零数和负数均拒绝且不提交。
- 扣款只在写入及回读成功后返回`true`；失败恢复本次事务对象的旧余额。
- `save_base`因磁盘存在较新revision而重新加载数据时，不再用旧实例余额覆盖权威档案。
- 新增独立事务专项并加入core清单。工坊仍将扣款和蓝图解锁分为两次保存，属于E04，不在本次冒充完成。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| `verify_scene_preflight.gd -- verify_extraction_points_spend_transaction.tscn` | Godot 4.6.2；审计专用custom user dir | 退出0 | 场景及脚本预加载通过 |
| `verify_extraction_points_spend_transaction.tscn` | Godot 4.6.2 headless；测试文件`user://extraction_points_spend_transaction_probe.json`，结束清理 | 退出0 | 正常500→430落盘；强制失败内存/磁盘保持430；非法输入拒绝；旧实例冲突重新加载620 |

旧实例冲突用例预期触发一条`[BaseManager] Refusing stale save`错误日志，随后专项输出`EXTRACTION_POINTS_SPEND_TRANSACTION_OK`并退出0。该日志属于本用例主动覆盖的拒绝分支。

## 遗留与状态更新

E03已实现并通过专项。E04工坊组合事务、E05/E06结算事务及AtomicJsonStore完整文件故障矩阵未改变。未执行full、真实进程竞争或断电测试；本次变更不据此签署整个存档系统完成。
