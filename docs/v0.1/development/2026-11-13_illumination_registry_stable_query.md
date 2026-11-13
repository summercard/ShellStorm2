# 稳定空间查询与照明广播发现去重

- FeatureID：PERFORMANCE-RUNTIME / ENEMY-AI
- 工程版本：0.1.0
- 来源：用户批准修复注册表 Owner 漏项 bug，不放宽比较。
- 状态：Owner 修复与发现去重已实现，本轮无头专项和真实路线通过，明显收益已证实并保留；GPU/人工整关/发布验收留主线程。
- 主契约：`../13_技术施工_性能优化与热管理.md` §13；受光意图：`../06_技术施工_怪物精英与Boss.md` §7。

## 授权与设计核对

`query_radius` 在扫描范围内完整返回满足距离、kind、room 条件的有效登记节点；待释放/已释放弱引用应被剔除，不得让同桶其余有效节点被跳过。原共享字典边遍历边删除违背该意图。保持 floor/x/z 桶顺序、桶内插入顺序、16m 桶、原半径和过滤规则；使用键快照保证剔除不影响迭代。

受光仍认真实显式登记光源、太阳优先、身体采样和物理遮挡。不得减少光数、画质、阴影、采样频率或射线预算。禁止 batch 合并通知；所有手动开关同步完成。同步受光 signal 重入保护、独立 force_refresh 完整发现和 legacy group fallback 保留。

## 实施范围与比较基线

Owner：`src/core/GameplaySpatialRegistry3D.gd`、`src/enemy3d/EnemyIllumination3D.gd`、`src/world3d/WastelandLight3D.gd`。不修改 Dungeon/Tower/Room 流送。新触及 registry 备份到 235110 before_edits，已有备份不覆盖。

旧错误候选 count 变化明确记为 bugfix，不宣称与错误查询 snapshot 全同。发现去重验收用“旧逐敌发现＋稳定查询”对“新广播发现＋稳定查询”；另用不调用被测查询的朴素枚举 oracle 验证完整有效项及顺序，执行 old-old control。性能采样与 oracle 分离，真实03 cr00/cr05 有明显收益才保留优化。

## 验收与证据

证据根目录：工程外 `../ShellStorm2-work/sessions/2026-11-12_expedition_finish/illumination_stable_registry/`（相对工程根），含 Runner、fixture、query_oracle、report.html、summary.json、各运行输入hash/结果/日志及Job Object进程退出记录。Godot 4.7.2 stable，全部 headless；用户目录在Autoload前隔离，资源/缓存只读链接、源码外部副本，无GPU实例。

| 验收 | 结果 |
|---|---|
| registry_stable | 172项通过；local_light/enemy/sun/connector四类同桶12项各含5 stale，首次完整同序返回7有效项；每类prune精确+5、合计20，重复查询不重计；混合kind/room、跨桶及半径边界通过 |
| registry_rawquery（预期负向） | exit1，无引擎错误；旧共享字典遍历首次返回0而应7，prune和过滤稳定性多项失败，证明测试能捕获Owner bug，不计入成功数 |
| fixture_stable / fixture_queue_lamps | 229次逐变化快照、候选状态/计数、cache_age、信号历史严格相等；稳定广播4灯只注册4次；手动toggle、重显、太阳混合、同帧移动、独立强刷、重入与嵌套开关通过；多stale夹有效灯仍立即受光，全部有效灯queue_free后立即恢复黑暗 |
| fixture_tick | 原229加120步×12接收者，共1669次比较通过；短程锁步tick，不代表长时整局回放 |
| new_route_eq | 正式03原15步路线365次旧stable对新once快照/候选/信号严格比较，365次独立朴素枚举完整灯集合与顺序比较通过；沿途4次状态信号payload相等 |
| old_route_eq | 同前态old-old控制，365次及独立完整灯比较通过 |
| fixture_fallback / regression_stable | 无注册表替身及既有verify_enemy_illumination_states退出0、0引擎错误 |
| domain / level-decoupling / diff | 全通过 |
| classname unique | exit1：5组既有副本重复（ItemRegistry/MonsterInjector/RewardPoolRegistry/RuntimeRewardCoordinator/TreasureChest3D），缓存指向src，本轮不处理 |

## 真实03 benchmark与保留决定

seed41021，正式 `ExpeditionLevel03_3D`、test_mode=true、原15步路线；基线双方都使用稳定query，仅发现策略不同。按 old_bench1 → new_bench1 → new_bench2 → old_bench2 串行采集，无oracle计入；四次退出0、0引擎错误，输入hash在每次运行内稳定。计时是外部副本包装的同步CPU墙钟，不是GPU、P95或统计显著性结论。

| 指标（ms，注册次数除外） | cr00旧两次 | cr00新两次 | cr05回程旧两次 | cr05回程新两次 |
|---|---|---|---|---|
| 完整enter | 54.718 / 57.781 | 38.250 / 28.803 | 91.470 / 96.784 | 56.924 / 61.588 |
| enter均值 | 56.250 | 33.527（-40.4%） | 94.127 | 59.256（-37.0%） |
| 广播累计均值 | 48.069 | 25.308（-47.4%） | 64.466 | 28.226（-56.2%） |
| force_refresh累计均值 | 47.843 | 25.082 | 70.588 | 34.759 |
| 广播/强刷次数 | 4 / 39 | 4 / 39 | 4 / 57 | 4 / 57 |
| 灯注册通知次数 | 6228 | 480 | 9197 | 1141 |

两热点有明显收益，保留稳定query＋广播发现去重。没有batch，没有删灯或降低任何采样/光影规格。计时作用域包含关系不可相加，完整enter仍有其它成本；cr05均值59ms仍超过50ms，不能据此宣布整关事件帧预算通过。

## 语义与撤回边界

上一轮queuedreceiver/queuedlamp回退本轮删除；上一轮局部桶重登记方案保持撤回，本轮未引入。错误查询的候选count不保持，完整有效候选为修复目标。被漏灯若原本足以照亮敌人，修复应恢复真实受光，不能以维持旧黑暗作为等价要求。kind/room/distance及受光算法本身未改。

`register_node.node_registered` 是操作通知，重复lamp次数减少已明确；现有唯一生产订阅者PlayerVision3D仅处理enemy注册，不依赖重复lamp通知。同步受光信号不合并。独立oracle不调用生产query/_resolve，而复制记录/桶后朴素枚举；旧stable与新once比较保持完整snapshot/射线/信号严格，不放宽字段。

keys快照带来数组分配，但不扩大扫描范围；本轮总成本由真实enter对照证明改善。短程稳态锁步不等于长时回放；真实route仅4次状态信号，不能替代全玩法系统回放。任意第三方接收者无信号私改灯仍非已证明路径。本记录不提升全工程完成状态。GPU、画面、人工整关、长时浸泡及发布验收由主线程协调。
