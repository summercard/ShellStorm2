# 六关命运投放设计落档与功能/感知复评

日期：2026-10-18；FeatureID：FATE-RULES、WORLD-PLAN；工程版本：0.1.0。
基线：`ff45ceb03`；交付：文档工作区，未提交。来源：用户确认上一轮六关方案，要求写入设计并检查功能与视觉完善程度。
主设计：[六关投放](../design/命运卡六关投放设计.md)；审计：[全部78张逐卡评估](../audits/2026-10-18_fate_readiness.md)。

## 改动

- 固定01首批21张（12枪械/6角色/3房间收益），六关新增21/12/12/12/12/9，累计21/33/45/57/69/78；登记每张稳定ID。
- 01/02仅正位、回玩仍受限、后关继承、关内随机入口一致、按兑现机会过滤；03—05逆位具体概率/权重保留待调，不擅填50%。
- 写入前两门主轴教学、来源武器、报价可负担与后期过滤要求，指出当前稀有度经济冲突。规则Owner/数据schema/事务/旧局迁移/独立验收已写目标契约。
- 同步01/02关设计、14与04施工页、设计目录、MODULE_INDEX、feature_registry及关系矩阵。修正14皇后表格的多件表述为现有候选择优单件，其他未核实的数量语义在审计保留缺口。
- 全78张评估分清48运行身份/30仅设计；21首批都有预设。逐项记录视觉潜力与缺口，不给伪精确完成率。
- 本轮未改玩法、掉落配置、稀有度、卡牌资产或内容XLSX；六关投放明确待实现，不伪报已上线。无新增VFX资产，制作建议需后续按账本流程落地。

## 本轮验证

工具：Godot 4.7.2；独立工程在Autoload前设custom_user_dir_name=ShellStormFateAudit20261018，世界/集成复跑使用独立后缀。Windows路径断言另提供工程外APPDATA/LOCALAPPDATA；不是仅靠test_mode隔离。
首次复用旧类缓存出现Training相关解析错误，停止该轮，隔离工程重新import（退出0）后复跑；初次失败不算通过。导入给55个.import附加新引擎默认参数，逐文件确认仅此变化并恢复原字节，正式资源无剩余变动。

| 检查 | 退出码 | 结果/边界 |
|---|---:|---|
| 名单语义检查 | 0 | 78唯一ID，六组数量正确，01全21有运行预设；累计运行21/31/35/39/44/48；48牌面＋1卡背 |
| verify_tarot_fate_runtime | 0 | 目录/正逆现行规则通过；验证的是旧50/50实现，不是新六关策略 |
| verify_fate_weapon_completion | 0 | 通过，无SCRIPT ERROR |
| verify_star_physical_mounts | 0 | 69项通过，无SCRIPT ERROR |
| verify_fate_character_completion | 1 | 129项中1项失败：旧“第二张魔术师拒绝”断言与当前叠加契约冲突；无SCRIPT ERROR |
| verify_fate_world_completion 初跑→复跑 | 1→0 | 初跑环境路径字串不符；复跑113项全过，无SCRIPT ERROR |
| verify_fate_integration_completion 初跑→复跑 | 1→0 | 同上；复跑729项全过，无SCRIPT ERROR |
| verify_fate_card_purchase_flow | 0 | 购卡事务通过，无SCRIPT ERROR |
| OpenGL Compatibility真实渲染 | 0 | STAR_VISUAL_OK，已查看图片；仅独立展示，携枪弹人为放大2.2倍、碎裂冻结相位 |

正式专项最终运行日志无ERROR或SCRIPT ERROR；有旧UID回退警告，Compatibility另有TAA不可用警告。未进行故障注入，预期故障注入项为无；上述测试失败并非预期故障。没有运行新关卡策略验收（尚未实现）、跨进程续局、全量full、正常战局输入/21卡连续体验及性能压测。

## 门禁

- `python3 scripts/check_documentation_contracts.py`：改前/改后均退出1、28项；归一化行号后无新增问题。其中包括既有失效链接及当前Python缺少openpyxl导致媒体域子检查无法完成，不能称全部文档验证通过。
- `python3 scripts/check_asset_runtime_naming.py`：退出1，既有带版本运行资产路径债务；本次没有新增/修改运行资产。
- `git diff --check`：退出0。
- 名单语义检查独立通过；门禁不代替设计语义或运行体验。

## 证据与后续

日志、results.json、rerun.json、semantic_check.json、star_physical.png位于工程外`ShellStorm2-work/probes/2026-10-18_fate_audit/`。修改前副本：`ShellStorm2-backup/2026-10-18_fate_progression/before_edits/`。
优先接入投放/教学支付，再补力量正位收益、连锁电弧、火冰状态、触发预告；最后扩展后关未实现牌。当前不签署全部卡牌体验完成。

临时验证工程在收尾移除，保留运行日志、展示脚本与截图。仅清理本轮明确创建的自定义测试用户目录，不触及正式用户档。
