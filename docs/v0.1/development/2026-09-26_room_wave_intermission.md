# 整波清空与2秒间歇修复

- 工程版本：0.1.0。
- FeatureID：WORLD-PLAN、ENEMY-AI、UI-HUD、FATE-RULES。
- 来源：用户要求整波清空后等待完整2秒再生成下一整波，禁止局部击杀提前推进或无限刷怪。
- 状态：实现及两项headless回归通过；不代表全项目或真渲染验收通过。
- 边界：仅修改 Dungeon3D 运行编排、必要测试及契约；不修改 DungeonRoom3D、Enemy3D、资产、正式存档，不提交。

## 根因与证据

1. 原波间等待为1.2秒；修复入口可直接调用下一波生成，绕过完整间歇；旧超时没有切房/卸载代际隔离。
2. 原死亡处理先移除引用、发布 kill_recorded，再扣存活数。同步订阅者重入修复时可能重算后再扣；重复死亡/逃脱回调也没有场景端幂等保护。
3. 原修复只数已实例化节点，会覆盖 deferred 召唤/命运增援的预约数；卸载的空节点表也不能视为全清。
4. 首轮实际专项日志抓到 MapFateTriggers 的累计3击杀触发 fate_reinforce，冷却后再次触发。原 trigger_extra_wave 直接预约并即时补兵，确实可以在当前波尚未清空时追加敌人；只修改波次timer无法解决这一来源。用户现场具体房间未复现，不把静态推断称为现场复现。

## 实现

- Dungeon3D 独占波次队列和2.0秒暂停感知timer；token抵御过期/重复超时，推进前复核当前房、流送、清房、存活成员及预约。
- 离场以已登记成员资格幂等，成员移除与计数扣减先于击杀事件/奖励发布，保留死亡召唤先预约再死亡的顺序。
- 召唤预约保存配置和可JSON序列化的坐标；卸载不落地，恢复后落地，不丢失预约。
- 命运增援每房最多入队一次，追加总波数，整波全清并等待2秒后生成，清房后拒绝，快照保存追加标记。保留命运阈值本身，不改 MapFateTriggers。
- HUD 独立波次栏持续显示当前/总数、间歇和肃清，不由临时status消息驱动。
- 快照恢复用 Array.assign 恢复类型化队列批次，兼容JSON往返后无类型Array。
- 专项注册 core。基础用例隔离命运触发配置；命运专项另走真实击杀信号与阈值，再重复触发验证每房幂等。

## 验证记录

- PowerShell 工具前台stdout存在空输出，因此所有Godot验证显式重定向日志；运行使用指定 `_console.exe` 绝对路径。
- Autoload启动前设置隔离 APPDATA/LOCALAPPDATA 到 `.tmp/wave-*`；不使用正式用户目录。
- 先执行 `--headless --editor --quit --import`。导入日志无SCRIPT ERROR/ERROR，存在既有色盘UID回退WARNING。
- 首轮专项未通过：暴露默认命运增援干扰、JSON波次Array类型错误，以及测试退出前尚有deferred奖励。已分别调整正式生成端、类型恢复和测试退出顺序，保留首轮失败事实。
- 最终 `verify_dungeon_wave_intermission` 退出0，输出 `DUNGEON_WAVE_INTERMISSION_REGRESSION_OK`；覆盖单死、重复死亡/逃脱、同步重入、同帧全杀、1.9秒未推进/2.15秒整批生成、终波、正式切房、卸载、JSON快照、死亡召唤、真实命运阈值、退出场景、HUD文本。
- 最终 `verify_3d_combat_progression_flow` 退出0，输出 `3D_COMBAT_PROGRESSION_FLOW_OK`。
- 文档契约首次因新测试未注册失败；注册core后复验退出0。
- 资产运行命名门禁退出0，未调整欠账基线。
- 最终日志 `.tmp/wave-final.log`（UTF-8）包含两项真实进程退出码；`check_verification_log.py` 退出0，无非预期SCRIPT ERROR/ERROR、无退出资源泄漏。无预期故障豁免；既有GLB色盘UID回退WARNING保留。
- 新增文本统一CRLF；未改 DungeonRoom3D 与远征关卡01设计页。

## 落点合并补验（同日）

- 复核落点代理的 DungeonRoom3D：无候选返回 Vector3.INF；Dungeon3D仅一处直接调用，首波/后续波/剧情/预约召唤/撤离防御共用批量入口。
- 整批落点预检先于实体创建，非有限点返回内部失败码-1；首波保留含首波的全部队列、波号0，后续波不消费队首并回滚波号，预约请求与计数保留。剧情接口仍返回非负实际生成数，失败为0。
- 本房失败锁随运行快照保存，修复/超时/回房不自动重试、不假清房；HUD显示无合法落点。没有更改合法落点算法与成功批次行为，没有修改落点代理文件。
- 失败测试覆盖批次后段INF（此前合法成员也不实例化）、真实无候选首波/后续波/预约、快照保留、反复修复无重试、全部敌人transform有限。
- 本轮先import，退出0但日志有一条 `Blender path is invalid or not set` ERROR；不签署无错误导入，也未修改资产/全局设置。
- 合并后波次专项退出0，`DUNGEON_SPAWN_FAILURE_OK` 和 `DUNGEON_WAVE_INTERMISSION_REGRESSION_OK` 均出现；仅3条注入产生的无落点ERROR，精确预期模式已登记，日志门禁退出0。
- 落点代理原探针复跑退出0：52房/3168点、桥房两姿态、39房跨种子变化、旧算法234不安全点反向对照、真实8/24只批次，failures=0；日志门禁退出0。
- 日志：`.tmp/spawn-merge-import.log`、`.tmp/spawn-merge-wave.log`、`.tmp/spawn-merge-spawn.log`（转为UTF-8）。
- 实际累计HEAD差异：Dungeon3D +250/-66；DungeonRoom3D +123/-73（落点代理所有，本次只读）。本次开始前Dungeon3D共260行改动，本次后316行；新失败测试并入原未跟踪专项文件。

## 未执行与限制

- headless仅验证状态和HUD文本，不声称字体、遮挡、真渲染或真人操作验收通过。
- 未跑完整core/full或用户现场远征房综合验收。
- 工作区存在其他代理/用户修改，包括存档、技能及资产目录；不清理、不回滚，不归入本次变更。
