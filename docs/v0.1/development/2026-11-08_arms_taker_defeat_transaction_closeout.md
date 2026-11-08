# 收租人最终战败事务与运行警告收口

日期：2026-11-08；记录ID：arms_taker_defeat_transaction_closeout；功能ID：ELITE-ROSTER / ENEMY-AI / ASSET-PIPELINE；工程版本：0.1.0。
设计依据：[精英02收租人状态与动作契约](../design/精英02收租人状态与动作契约.md) r13；施工入口：[怪物精英与Boss](../06_技术施工_怪物精英与Boss.md) §5.7。
代码基线：分支 `0.1.2`、HEAD `2a1a1aa66`；交付提交：工作区，尚未提交。工作区存在其他会话改动，本记录不将整文件 diff 全部归入本任务。

## 1. 范围与结论

本轮只收口两项：真实渲染覆盖 `Dungeon3D.commit_arms_taker_defeat()` 最终提交；清理漫游专项的 imported resource invalid UID、material null、body-space null。不是十二精英名册或全仓验收完成声明。

- 最终真实渲染：`ARMS_TAKER_REVISION_VISUAL_DONE checks=472 failures=0`，`ARMS_TAKER_REVISION_VISUAL_OK checks=472`。
- 最终漫游：`ARMS_TAKER_ROAMING_OK checks=1929`，实际现身4次，最大生命4740、剩余2844。
- 两个最终专项的目标三类警告、脚本/解析/调用/编译错误、ObjectDB/resource 泄漏摘要均为0。
- 色盘门禁789消费者，缺失缓存0、陈旧缓存0；789消费者 fresh-load 全部成功。

## 2. 正式战败事务与回滚

`tests/verification/verify_arms_taker_revision_visual.gd` 新阶段实例化正式 `ExpeditionLevel03_3D.tscn` 并设为 `SceneTree.current_scene`。真实玩家、背包、保险与关卡初始化完成后，经 `RoamingEliteRunDirector` 预约、正式 injector/`_spawn_enemy_batch()` 生成收租人；实际扣除81%最大生命，由敌人自然物理回调执行 kneel、提交和释放。未在外层fixture伪造 `commit_arms_taker_defeat` 返回值，也未使用空玩家/空checkpoint替代真实存档。

| 用例 | 初始库存计数 | 实际掉落总数 / 节点数 | 自然终态 | 活体重复提交 |
|---|---|---|---|---|
| success | 1+1+1+1+1 | 3 / 3 | Defeated，实体释放 | 已验证幂等 |
| rollback_retry | 1+1+1+1+1 | 3 / 3 | 故障解除后自然重试并释放 | 成功后立即释放，不宣称另验活体重复提交 |
| stacked | 2+3 | 3 / 2 | Defeated，实体释放 | 已验证幂等 |
| single | 1 | 1 / 1 | Defeated，实体释放 | 已验证幂等 |

掉落以总库存数量 `ceil(total/2)` 计算，不按库存行数计算。pending pickups 提交前隐藏、停止监测和process，但保留 `ground_loot_3d` 以进入正式 runtime snapshot；成功才开放，失败移出组并释放，不留下可拾取残留。

故障用例连续保存失败约2.9667秒，超过2.6秒跪地时长仍在场。逐项检查档案、runtime checkpoint、save revision、journal、runtime cache、成员原顺序与alive恢复，无战败/死亡/撤离终态事件或失败掉落。生产 `Dungeon3D.commit_arms_taker_defeat()` 保存原 `previous_member_index`，失败 `insert()` 原位恢复，修复旧 `append()` 会改变成员顺序的问题；哨兵成员用于保证这个断言不是单成员空检查。

四例成功后均只发一次 defeated，状态为 `defeated` / 档案 `Defeated`、defeat_count增加1、清除预约；不发 killed/escaped，不增加普通击杀，不污染普通alive、清房和开门账。checkpoint包含完整掉落，不再包含已战败persistent_id；重新 `load_base()` 后完整档案与掉落按存储语义一致，武器实例ID、弹药、配件、耐久和自定义metadata逐项保留。

测试存储比较复用 `ProfileSaveService.checksum_payload({"value": value})` 的 canonical JSON，不使用原始Variant深层 `==` 误判JSON读盘的 int→float；未修改生产存档格式迁就测试。成功后还等待真实抛落/弹跳动画结束，再检查 visible、monitoring、process与 `is_pickup_available()`，不将“提交完成”混同于“掉落动画完成”。

## 3. 三类警告的原因和修复边界

### 3.1 imported resource invalid UID

源文件 `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import` 与 `scripts/shared_palette_uid_contract.json` 最终统一为 `uid://cc0hgbbwh4cb7`，契约消费者数更新为789。原HEAD中源 `.import` 和契约UID本来就不一致，不能描述成单一旧UID的简单替换。保持无损、无mipmap、512×512、size_limit512、禁止3D自动转VRAM的既有色盘契约。

在工程外实体副本完成导入，处理789个消费者，再以精确清单合并1581个导入相关文件，其中789个 `.scn` 更新，mtime按清单保持；未停止用户编辑器，也未整份覆盖主工程 `uid_cache.bin`。fresh-load789成功、invalid UID为0。`.godot/imported` 属本地忽略缓存，不作为业务源码提交；需要审查的源配置是上述 `.import` 与契约JSON，不把上千个无关引擎默认键漂移归入本修复。

### 3.2 material is null

既有入树前预置 `enemy_kind` 优化造成 `_ready()` 先走 `apply_profile()` / `avatar.configure(egt_*)`，此时完整 `configure_from_enemy_data()` 字段尚未就绪，产生空surface override。并发性能会话真实渲染对照为开预置12条、关预置0条；该优化已回退，当前正式生成仍为先 `add_child()` 再用完整spawn_data配置。本轮最终漫游和真实事务复验均未再现。

这不是新增材质系统重写，也不应把收租人kneel/HitFlash表现改动误写为该警告根因。当前净diff主要保留安全顺序和原因注释，不能仅凭净diff判断临时优化的会话归属。

### 3.3 body->get_space() is null

`verify_arms_taker_roaming.gd::verify_health_potion()` 的塔祖先被 `PROCESS_MODE_DISABLED` 后，测试仍手动调 `_physics_process()`，默认body可能已经离开physics space。只围绕这两次手动tick临时设置 `CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE`，先检查RID space有效，结束恢复原disable_mode。新增两条断言，漫游1927→1929项。

未对生产 `Enemy3D` 添加全局保活或提前return。真实事务阶段另行断言enemy自然physics开启且RID space有效，避免以手动fixture掩盖正式运行链问题。

## 4. 验证环境、取证干预与证据

真实渲染为 Godot 4.7.2.stable / Windows DisplayServer / NVIDIA GeForce RTX 3060 / Forward+ / 1280×720 / `--disable-vsync`。漫游为headless逻辑回归，不能冒充真实渲染。每次启动前隔离 APPDATA / LOCALAPPDATA，`ELITE_QA_DIR` 只承载工程外输出；未使用用户正式存档。

观察fixture明确干预：冻结玩家输入、战斗与自身process并移远以防自动拾取；局部暂停 `PlayerVision3D` 可见性刷新，防止观察相机不等于玩家视线而把actor/loot隐藏；真实哨兵仍留在成员列表，停止其自身process并隔离网格视觉。收租人、掉落、正式房间与保存链不因此停用。截图仍有少量哨兵眼部/阴影残余，物品名称标签有重叠，数量和实例身份以真实节点、checkpoint与完整字段断言交叉确认。

最终真实渲染目录：

```text
F:/wxgame/ShellStorm2-work/qa/arms_taker_closeout/visual_final_20261108_143029/run/
  console.log
  godot.log
  evidence/report.json
  evidence/08_transaction_rollback_kneel.png
  evidence/09_transaction_committed_kneel_drops.png
  evidence/10_transaction_finished_real_drops.png
```

共11张代表帧；实际查看上述三图，分别确认保存失败仍留场且无掉落、成功留场并有3件真实掉落、实体自然消失但3件掉落保留。既有双枪实际命中玩家33点、双方请求治疗23但实际恢复7的绿色 `+7`、租物8段拖尾和约2.20m跨度、门边完整teleport-out同步通过。

最终漫游日志：`F:/wxgame/ShellStorm2-work/qa/arms_taker_closeout/roaming_final_20261108_135037/run/{console.log,godot.log}`。
UID证据：`F:/wxgame/ShellStorm2-work/qa/arms_taker_closeout/palette_uid_20261108_131235/` 中 `fresh_load_evidence.json`、`merge_result.json`、`acceptance.json` 与 `final_scope_check.json`。

## 5. 登记、账本与未执行边界

`scripts/run_verification_suite.sh` 将 `verify_arms_taker_equipment`、`verify_elite_rent_transfer` 补登记core，`verify_arms_taker_revision_visual` 补登记visual，并为后者设置工程外 `ELITE_QA_DIR`。功能注册表 `ELITE-ROSTER` 同步三入口和本记录。本次为直接Godot运行，runner只完成语法和登记静态检查，未宣称完整suite已执行。

账本真源遵循 `assets/registry/ledger_index.json`。前轮敌人账本 A78:G78 v0.1.36、特效账本 A47:G47 v0.1.38 已保存回读且保持partial/development。本轮仅事务、测试与共享资源导入契约收口，没有新增或替换收租人/特效资产，故不重复新增资产行、不改资产SHA或把账本整体提升为完成。武器、物品道具、道具三本也不虚增验收记录。`ELITE-ROSTER` 仍partial，十二名册仍只有两只投放。

最终静态门禁输出位于 `F:/wxgame/ShellStorm2-work/qa/arms_taker_closeout/final_gates_20261108_145727/`：

| 门禁 | 实际结果 |
|---|---|
| verification registry | 通过，286场景；smoke6/core232/visual42/manual6 |
| feature traceability | 通过，45功能、159场景引用、12命令引用，issues为空 |
| runner `bash -n` | 通过；不等于完整suite已执行 |
| level decoupling | 通过，0违规 |
| shared palette UID | 通过，789消费者，缺失/陈旧均0 |
| `git diff --check` | 通过 |
| documentation contracts | 仍失败：旧44项（43断链+1登记错误）→42项既有断链；本任务收租人链接及包含3孤儿入口的登记错误已消失 |
| asset runtime naming | 仍失败：8个既有rooftop shelter版本路径，与旧清单完全相同 |

对比 `gates_20261108_142428`，仅忽略Markdown源行号偏移，文档门禁无新增问题；精确比较写入 `baseline_comparison.json`。未批量修无关历史文件或绕过门禁。

设计、施工、MODULE_INDEX、CHANGELOG、development目录与feature_registry同步最新结论；保留旧报告当时未覆盖和警告未清的历史事实。本轮源码和记录尚在工作区，未执行提交或推送。
