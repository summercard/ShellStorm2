# E18–E24与D02–D11设计对齐记录

日期：2026-09-12。工程版本：0.1.0。记录ID：`POWER-ASSET-CONTENT-ALIGN-20260912`。

## 设计依据

- E18建立独立电力系统设计，以当前游戏内手电与基地能源行为为现行事实；基地灯光、应急照明及设施负载保留为待完善设计。
- E19等首个完整版完成后再冻结性能验收标准；E21基地表现目标不清晰，与E15/E20同列灰色暂缓。
- E22–E24以当前资产清单、运行布局与账本为权威来源，被替换基线标为（旧资产）。
- D02归入枪械设计并标为设计中；D08–D10补价格设计；D11确认`battery`子类。

## 本次变更

- 新建[电力系统](../15.1_技术施工_电力系统.md)，登记`POWER-SYSTEM`的所有者、命令、查询、事件、数据和失败语义。
- [战斗与局内成长](../04_技术施工_战斗与局内成长.md)新增弹药堆叠与基地成交价格设计；内容库同步弹药999、断刃165/83、战斧240/120、普通房间钥匙40/20。
- `ItemRegistry`为普通房间钥匙补参考价40，为小电池补`subtype=battery`；商店专项核验派生出售价格与子类。
- [资产与内容规范](../10_资产与内容规范.md)冻结当前资产来源优先级；结构、墙面、剩余设施专项改为核验现行布局及嵌套设施包装。
- [性能规范](../13_技术施工_性能优化与热管理.md)和[基地设施](../07_技术施工_基地设施.md)登记E19/E21暂缓条件。

## 状态结果

| 项目 | 结果 |
|---|---|
| E18 | **开发中**；独立设计已建立，基地用电表现待施工 |
| E19 | 灰色暂缓；首个完整版后定义验收标准 |
| E21 | 灰色暂缓；等待基地表现设计冻结 |
| E22–E24 | 已按当前资产账本修改验收并通过 |
| D02 | 现行999已对齐；最终平衡继续标为**设计中** |
| D08–D11 | 已设计、同步并验证 |

## 验证记录

| 命令／入口 | 结果 |
|---|---|
| `bash scripts/run_verification_suite.sh scene verify_base99_structural_asset_integration` | 退出0，当前结构基线通过 |
| `bash scripts/run_verification_suite.sh scene verify_base99_wall_content_v021` | 退出0，当前v022坐标通过 |
| `bash scripts/run_verification_suite.sh scene verify_base99_remaining_facilities_v021` | 退出0，45包/35实体阻挡及嵌套包装通过 |
| `bash scripts/run_verification_suite.sh scene verify_base_shop_save_flow` | 退出0；预期故障日志由runner声明，价格、交易与子类断言通过 |
| `bash scripts/run_verification_suite.sh scene verify_3d_flashlight_charge_flow` | 退出0，现行手电耗电、基地暂停、电池、模块、存档与HUD共13项通过 |
| `bash scripts/run_verification_suite.sh scene verify_tower_lighting_wall_combat_regressions` | 退出0；手电灯节点按当前公开参数验收，基地顶灯恢复输出保留为`POWER_SYSTEM_PENDING`诊断 |
| `bash scripts/run_verification_suite.sh scene verify_base_overhaul_flow` | 退出1；命中E21已暂缓的旧基地表现基线，并有旧`float`构造脚本错误；不作为本轮关闭依据 |
| `python3 scripts/check_documentation_contracts.py` | 交付前执行，结果见本轮最终记录 |

运行时仍报告公共色盘UID回退警告，属于已暂缓E20，本次没有批量接受或修改资产哈希。
