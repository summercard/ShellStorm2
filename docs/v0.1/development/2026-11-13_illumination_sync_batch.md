# 同步装配事务照明 final-state 提交

- FeatureID：PERFORMANCE-RUNTIME / ENEMY-AI
- 版本：0.1.0
- 来源：用户明确批准必要工程语义改进，不把Scene/Room半装配中间灯态当权威。
- 状态：同步事务实现及本轮无头专项通过，真实enter ABBA有明显收益，保留生产改动；非GPU/整关发布签署。
- 主契约：`../13_技术施工_性能优化与热管理.md` §13。

## 范围与备份

只改 EnemyIllumination3D 静态begin/end/dirty、Wasteland通知入口、Dungeon3D._update_room_streaming与DungeonRoom3D.ensure_detail_built指定方法。registry不改，Tower override不扩大范围，主线程spawn helper不改。最新含既有修改文件独立备份到外部 `illumination_sync_batch/before/`，不覆盖235110。

## 批准的语义变化

同步无yield装配期间不运行AI/物理帧；中间灯态dirty合并，最外边界返回前刷新一次。玩家手动开关不在该scope内仍即时；显式force在scope内独立完整采样，末尾继续提交。signal reentrant即时。嵌套成对关闭、already-built早退在begin前，无dirty无广播。Tower super后操作继续即时，不包复杂_on_room_entered。

旧逐灯的中间signalhistory及其AI黏性副作用不再要求严格旧值，须列exactdifferences；final snapshot、AI/信号末态按最终世界光照意图验证，不能伪全等价。光数、阴影画质、受光tick及每次射线预算不降。

## 验收

证据目录：工程外 `ShellStorm2-work/sessions/2026-11-12_expedition_finish/illumination_sync_batch/`。包含 before（最新含existingmods）、frozen_src、Runner/fixture、scope_audit、delivery_source_audit、report.html、summary.json及各运行原始日志/结果/Job Object进程退出记录。未覆盖235110，未建任务/插件或提交，未启动GPU。

| 验收 | 结果 |
|---|---|
| fixture_batch / fixture_real_ai | 12接收者、36次事务final完整快照/候选比较通过；nested内层不提交、最外提交一次、空scope不广播；scope显式force即时、dirty仍在末尾提交；signalreentrant改灯即时；移动/queued灯正确；最终scope栈为空 |
| 精确signal差异 | 每敌亮→暗→亮：旧3次信号，新1次，final相等；亮→暗：旧2次，新0次，final暗相等；不再伪称旧signalhistory全相等 |
| 生产Enemy3D AI | 最终暗保持runtime AI inactive且0状态信号；最终亮返回前active、1信号、人工光move multiplier=0.4；alreadybuilt早退不泄漏scope |
| legacy229 | 非batch路径原229次逐变化完整快照/候选/信号严格比较通过，仅证明普通路径不退化 |
| registry_regression | 原多stale夹有效项172检查通过；registry本轮零改动 |
| new_route_oracle2 | 真实15步路线actual dirty提交边界82次完整snapshot对最终世界传感器oracle零差异，0引擎错误 |
| regression_batch | 既有verify_enemy_illumination_states exit0、0错误 |
| scope静态审计 | 两授权methods本体无await，各1 begin/end，begin后无return；Room已建早退位于begin之前 |
| 源码审计 | 两methods去掉scope行与最新备份逐字相同；测试frozen与生产方法一致，illum/Wasteland/registry与frozen一致，不覆盖主线程spawn helper |
| domain / level-decoupling / diff | 通过；既有unique五组重复此前记录保留，本轮未引入class_name |

### 失败与修正记录

首轮真实oracle对所有流送边界强制比较：280检查110差异，其中96涉及旧缓存采样位置、51涉及候选计数（重叠）。原因包括无dirty流送原本不刷新，测试不能把无dirty缓存要求为即时新采样。失败保留，不算通过。修正测试为仅在实际发生同步广播的dirty提交边界比较，仍比较所有snapshot字段，没有删除字段或放宽数值；82次通过。此处不宣称所有低频缓存随任何流送调用都刷新。

### ABBA真实enter（相对上一轮发现once，不是原N×M）

Godot4.7.2 headless，正式ExpeditionLevel03_3D、test_mode、seed41021原15步路线；冻结同一src，old仅还原本轮Owner改动。old→new→new→old串行，oracle不计时，四次exit0/0引擎错误。

| 指标 | cr00旧 | cr00新 | cr05回程旧 | cr05回程新 |
|---|---|---|---|---|
| 完整enter两次ms | 29.012 / 30.367 | 15.350 / 15.139 | 60.724 / 56.736 | 36.531 / 36.946 |
| enter均值ms | 29.690 | 15.245（-48.7%） | 58.730 | 36.739（-37.4%） |
| 实际广播累计均值ms | 21.600 | 7.007 | 29.359 | 10.184 |
| force_refresh累计均值ms | 21.399 | 6.902 | 35.087 | 15.141 |
| _notify入口/实际广播 | 4 / 3 | 4 / 1 | 4 / 3 | 4 / 1 |
| force_refresh次数 | 39 | 13 | 57 | 23 |
| 灯注册操作通知 | 480 | 161 | 1141 | 817 |

四次notify入口并非四次有效树内广播，旧版实际3次；新notify约0.01ms仅标dirty，不是照明总成本。提交成本包含在streaming/enter内，不通过移走计时冒充零成本。cr05仍有独立强刷，保留原行为。

明显收益成立，保留。两样本不等于统计显著性/P95或GPU改善；不能与上一轮不同冻结基线跨轮相减当合并收益。GPU/视觉、人工整关、长时浸泡和发布验收留主线程。Tower super后的即时改灯仍未合并；异常/脚本错误不属于正常scope关闭保证。
