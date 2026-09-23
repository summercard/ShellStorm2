# 新拉取后的功能关系复核与文档冲突处理

日期：2026-09-23；记录ID：DOC-RELATIONSHIP-r2；功能ID：`NARRATIVE-TRIGGER`、`WORLD-LOOT`、`REWARD-SERVICE`、`SAVE-PROFILE`、`SAVE-RUN`、`ENTRY-AVATAR`、`ASSET-PIPELINE`；工程版本：`0.1.0`。
拉取基线：`622d6c4a`；交付提交：工作区。

## 变更与原因

拉取后 `development/CHANGELOG.md` 出现唯一三方冲突：上游新增“剧情刷枪/跨局历史”和“天台下线”两段，本地新增功能关系计划段。合并时保留三段完整内容，已移除冲突标记并标记该路径已解决；没有改动上游代码或二进制表格。

按新代码与剧本更新[关系计划](../FEATURE_RELATIONSHIP_PLAN.md)、[37项跟踪表](../FEATURE_RELATIONSHIP_MATRIX.md)及[模块索引](../MODULE_INDEX.md)：

- 纯新档在98F办公室进入开场；已有非战局档从天台/基地下线后回99F基地。
- `scene.spawn_item` 经 `NarrativeAdapter3D → Dungeon3D → RuntimeRewardCoordinator.resolve_fixed_item` 生成房间地面物；开场枪的内容、落点、时机现在由剧本控制。
- `once=run` 完整收口由 `NarrativeDirector3D → BaseManager.commit_narrative_completion → BaseData.narrative_history` 落长期档；中断和抢占不写。导演把绑定的地牢传给适配器，避免场景根识别失败。
- `retry`/触发条件强校验、剧情内容表仍是提案；未拾取剧情地面物跨重启恢复仍有缺口，不能因跨局剧情历史完成而关闭。
- 新拉取后账本为410项、9本分账本、0完整性问题、0拆账漂移，较拉取前新增1项敌人资产。

主设计08的旧“`run`只在本局生效”“剧情系统不写盘”“跨局历史未施工”等现行口径已修正；13.7/13.8历史施工段保留并添加后续实现提示。存档设计09 §10.1的现行出生规则已收成一组明确条目。未获确认的剧情新档位提案没有升级为正式设计。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 证据 |
|---|---|---|---|
| 三方冲突标记与未合并索引检查 | Git工作区 | 通过；无未合并路径 | `git diff --name-only --diff-filter=U` |
| `python3 scripts/check_asset_registry.py --scope full` | 只读资产检查 | 通过；410项、0异常 | 本次命令输出 |
| `python3 tools/asset_pipeline/verify_ledger_split.py` | 只读资产检查 | 通过；410项、0漂移 | 本次命令输出 |
| `python3 scripts/check_documentation_contracts.py` | 只读文档检查 | 退出码0；121份文档、584个本地链接、37功能、0问题 | 本次命令输出 |
| `python3 scripts/check_feature_traceability.py` | 只读功能追溯 | 退出码0；37/37、0问题 | 本次命令输出 |
| `python3 scripts/check_asset_runtime_naming.py` | 只读运行资产命名检查 | 退出码0；无新增债务 | 本次命令输出 |
| 5场景批次：剧情、开场、98F、入口、存档复位 | Runner按批次隔离Godot用户目录与导入缓存 | 退出码1；4通过、开场1失败 | 剧情用例先写入开场的跨局历史，后续开场剧本被档案挡住 |
| `verify_opening_script_runtime`单独运行 | 独立Runner用户目录 | 退出码0；105项通过 | `VERIFICATION_SUITE_OK suite=scene count=1` |

## 遗留与状态更新

`feature_registry.json` 仍为37项、原实现状态未变；新拉取没有让整个剧情或存档模块达到完全解耦。Runner场景间用户数据污染需要独立修复并复跑批次，不能把单场景通过记作批次通过。`retry/never`提案、开场地面枪恢复、跨域历史通知及真实渲染证据继续在跟踪表中管理。
