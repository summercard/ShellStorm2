# 四孔钥匙嵌件与对白两段推进（2026-11-10）

业主当轮两条原话：

1. 「对话过程中按空格可以快速播放，按一下快速播放，再按一下下一个对话。」随后追加「鼠标左键也可以快速对话。」
2. 「钥匙版不要在这里新作一个模型，放到后面这个台子上，斜着往里头差，有四个插孔，直接做一个新模型嵌在上面 不用改原模型。」

规则主源：[主线3.1至3.3与四钥匙设计 §5.1/§5.2](../design/主线剧情3.1至3.3与四钥匙设计.md)；
输入细节见[对话与战斗信息呈现设计](../design/对话与战斗信息呈现设计.md)与[18 号技术施工](../18_技术施工_UI与对话系统.md)。
本轮只做这两件，不改章节时长、不改永久事务、不改原台柜模型。

## 1. 结论

| 项 | 结果 |
|---|---|
| 四孔嵌件 | 已入库并接入 3.3，摆位落在主门下方低柜台面 (5, 1.38, -3.77)，原台柜 GLB/TSCN/碰撞/两侧设备零改动 |
| 旧立式台座 | 已撤除（`MainStoryPedestal3D` 不再建底座/立柱/槽面/竖排线路/核心六棱柱） |
| 对白空格／左键 | 两段语义已接入双载体与自由 NPC；实体屏障、事务、Boss 真实激活不可跳过 |
| 账本 | 新增一行 `PRP-BASE99-MAIN-STORY-KEY-INSERT`（主表 1024、3D-设施 65、域变更日志 v0.1.84 建行 / v0.1.85 补分页） |
| 验收 | 表演专项 52 项 exit 0；3.3 原生 Forward+ 27 项 exit 0；对白相关四份专项见 §5 |

## 2. 嵌件资产

| 项 | 值 |
|---|---|
| AssetID | `PRP-BASE99-MAIN-STORY-KEY-INSERT` |
| 制作源 | `art_source/props/main_story/key_insert/prp_base99_main_story_key_insert_source_v001.blend` |
| 优化源 | `art_source/props/main_story/key_insert/export/v001/…_optimized_v001.blend`（独立另存、重开后才导出） |
| 稳定 GLB | `assets/art/props/main_story/components/key_insert/prp_base99_main_story_key_insert_visual_top3d.glb` |
| Wrapper | `assets/art/props/main_story/runtime/key_insert/prp_base99_main_story_key_insert_root_top3d.tscn` |
| 尺寸 / 原点 | 2.28 × 0.58 × 0.24 m；Godot XZ 居中、底面 Y=0、前向 +Z |
| 四孔 | 真实矩形孔（孔唇 + 轴向内壁 + 60 mm 暗槽），孔心 x = −0.69 / −0.23 / +0.23 / +0.69，孔距 0.46 m |
| 孔轴 | `(0, −0.9397, −0.3420)`，即 20° 朝台内（−Z）下插 |
| 槽灯 | `SocketGlow_0..3` 四块独立网格，运行期复制私有材质后逐孔换色 |
| 材质 | 四张共享色盘材质，GLB 内 images=0 / textures=0，导入用 Nearest |
| 面数 | 320 → 304 tri（仅清理四个槽灯的共面反向片，主体零减面，附逐物体理由） |
| 碰撞 | 无；站立与行走全部由原台柜 `SourceObjectBox_000` 负责 |

摆位依据是实测而非估：`main_door_low_storage_cabinet` 的顶板碰撞盒 `SourceObjectBox_000` 中心 (5, 1.3, −3.77)、高 0.16，故台面 y=1.38；左右两枚既有设备在 x=3 与 x=7.1，嵌件占 x 3.86–6.14 不重叠。

## 3. 运行接线

- `TowerDescent3D.get_main_story_insert_transform()` 从美术布置层 `to_global()` 换算承载点，`get_main_story_pedestal()` 暴露表现节点；`MainStoryPedestal3D.setup(host)` 不再吃 facility，改挂 `Art` 布置层，跟随房间流送。
- `MainStoryPedestal3D` 只读 `BaseManager.get_main_story_snapshot()`：按 `deposited` 亮对应孔槽灯、摆已安装钥匙、点 N/4 环；`get_anchor()` 给孔口／台前地面／对焦三个锚点，`get_insert_params()` 给孔轴 basis 与柄偏移。
- `MainStoryKeyVisual3D` 的 insert 段改为沿孔轴进给：手跟着握把抬升，超过 `手部静止高度 + 0.45 m` 后停止跟随，剩余行程由钥匙单独完成。
- `MainStoryChapter3D` 的 `deposit.key_insert` 合并 `get_insert_params()`，不再用竖直插入。
- 链路上没有任何一处写存档；安装成功仍只由 `BaseManager.deposit_main_story_key()` 决定。

### 3.1 已知表现限制（不改设计口径，如实记录）

绿苔身高约 1.2 m、手部静止高度约 0.55 m，而孔口在 1.51 m。当前是「抬臂 + 钥匙吸进孔内」的程式化表演，没有 IK、没有踏台、没有放大角色。俯视玩法镜头下这段行程约 10 px，观感可接受；要严格物理就得加踏台或把孔位下移，属于改设计，另行立项。

## 4. 对白两段推进

- 首次按键/点击：当前句立即全显，句号与标点不变；当前句已全显后再按：进入下一句。
- 空格与鼠标左键同语义；纯底栏场景保留 Enter；`skip` 仍是整场终止，两者不混用。
- 只压缩「文字停留」，不压缩实体进度：NPC 跑动、拿出、交接、斜插、Boss 真实 6.4 秒激活、领取与安装事务全部照旧走实体屏障，cue 顺序与剧情 JSON 时长不变。
- 被对白消费的左键一直持有到释放，不顺带开火、不触发 NPC／设施交互；无对白时左键仍是原玩法输入。失焦或漏 release 由真实输入轮询校正，不会永久锁死开火。
- 暂停期间不处理；按住、同事件重发、同帧双击都不重复推进。

## 5. 验收

命令与证据均在工程外 `I:/工作项目/shellstrom2/ShellStorm2-work/`。

| 项 | 结果 | 证据 |
|---|---|---|
| 实体表演专项（含本轮新增 9 条嵌件断言） | `checks=52 failures=0`，exit 0，自然退出 | `outputs/main_story_031_033/key_insert_final/performance/` |
| 3.3 原生 Forward+ 章节捕获 | `checks=27 failures=[]`，exit 0，自然退出 | `outputs/main_story_031_033/key_insert_final/033/` |
| 3.3 近景（交接／斜插／安装／环） | 已逐张查看：嵌件平贴台面、钥匙斜插第一孔、1/4 环平铺在台面 | `probes/main_story_performance/key_insert_shot3/shots/04_insert.png`、`05_deposited.png` |
| 空格专项 | 41 → 44 项，exit 0 | `verification/dialogue_space_20261110/` |
| 鼠标左键专项 | 51 项，exit 0 | `verification/dialogue_mouse_20261110/` |
| 鼠标恢复（失焦／漏 release／暂停） | 79 项（51 + 28），exit 0 | `verification/dialogue_mouse_recovery_20261110/` |
| 底栏／气泡／旧无空格时间轴回归 | 21 / 81 / 113 项，全 exit 0 | 同上两目录 |

新增断言里带牙齿的几条：嵌件真实实例化且用正式 AssetID、四个槽灯可独立取到、嵌件挂在 `Art` 布置层、承载点与台面对齐误差 < 5 cm、绿苔站位回到地面、孔轴 `basis.z.y > 0.3`（即斜孔而非竖直）、柄偏移把钥匙抬到孔口上方。

改完嵌件后整体回收主线五专项与业务集成，确认没有把别处弄坏（均在 `outputs/main_story_031_033/key_insert_v2/`）：

| 专项 | 结果 |
|---|---|
| 业务集成 `verify_main_story_integration` | 98 项，exit 0（4 段预期注入） |
| 叙事基地 `verify_main_story_narrative`（base） | 328 项 + 运行时，exit 0（4 段预期注入） |
| 叙事 Boss（boss） | 320 项 + 运行时，exit 0 |
| 永久进度 `verify_main_story_progress` | exit 0；日志里 `Refusing stale save: memory revision 0 < disk revision 3` 是该用例**刻意**写旧快照验证「不得反向覆盖权威档」 |
| 导航 `verify_main_story_navigation` | exit 0 |
| Boss 门闩 `verify_main_story_boss_gate` | 20 项，exit 0 |

预期故障与真实错误分开记账：表演专项里的 `deposit_save` 保存失败是刻意注入；旧时间轴的 `player.teleport` 缺参数是既有用例故意写错；进度专项的 stale save 拒绝也是刻意注入。三者都不是本轮新增缺陷。

## 6. 账本与文档

- 场景账本新增 1 行：资产主表 1024（日志 v0.1.84）、3D-设施 65（日志 v0.1.85）。基线只更新该资产记录、`column_digests`、`category_counts`（场景道具 50→51）与 `3D-设施` 分页摘要，并追加一条 `targeted_updates`；其余 17 个分页摘要与全部既有资产记录逐项断言不变。
- **一次自查纠错，记录在案**：第一版登记脚本在写分页行时，append 落在临时加载的工作簿对象上，随后又用「重新读盘」的副本保存，导致 3D-设施 第 65 行**没有真正落盘**、分页摘要也没变。复跑门禁时发现「分页摘要与改动前完全一致」这个不可能成立的现象才定位到它；已用独立事务补写（备份 `ShellStorm2-backup/2026-11-10_141004_453095_key_insert_page_fix`），补后分页摘要 `0e69cdf9…` → `676b365b…`，`full --ledger scenes` 复跑该资产 0 问题。
- 基线侧另做了两项硬核对，确认没有顺手把历史漂移洗进基线：① 把本次新增行排除后重算 25 个内容列的列摘要，与 git HEAD 的旧值**逐列完全相同**；② 新增资产记录 1 条、删除 0 条、修改 0 条，其余分页摘要全等。
- 登记工具：`tools/asset_pipeline/register_key_insert_asset.py`（幂等，重跑只核对不重复追加；写前对账本与基线做哈希并发护栏，写后校验 xlsx 完整性）。
- 同步文档：本文件、主线设计与剧本、节点表、20 号技术施工、design 目录页、MODULE_INDEX、feature_registry（NARRATIVE-TRIGGER / BASE-NPC / DIALOGUE-UI 三处挂本记录）、development README/CHANGELOG、`assets/art/props/main_story/asset_manifest.json`。

## 7. 未闭环

门禁实跑（`outputs/2026-11-10_key_inset/gates/`）：

| 门禁 | 结果 |
|---|---|
| 关卡解耦 / 验收注册 / 功能追溯 / 资源命名 | exit 0 |
| `verify_ledger_split` | exit 1，227 条既有失败：脚本只打印前 40 条，全是 `dedupe_key_formula_wrong`（enemies 域 `==LOWER` 双等号）与 `dedupe_result_formula_wrong`（数组公式）及 1 条 `row_content_mutated`（`ENM-TRAP-SPIKEWORM01`）；`extra=2` 是两只 `PRP-3D-REWARD-CHEST-*` 长期未入基线的既有欠项。**没有任何一条指向本次新增资产**（三份门禁 JSON 里都检索不到该 AssetID） |
| 资产结构 `scope=structure` | exit 1，4 类既有问题（107+107 同上的公式问题、2 条 `invalid_status`、8 格 vfx 总览过期公式），均非本资产 |
| `full --ledger scenes` / `props` | exit 1，分别为 2 条与 5 条既有 SHA 欠项/漂移，均非本资产 |
| 文档门禁 | exit 1，14 条既存断链（与本轮新增文档无关，新文档链接可解析） |
| 工作区卫生 | exit 1，3 条既有 `outputs` / `_scratch` / `Godot` 目录（历史遗留） |

其余未闭环：

- 旧 Boss 综合回归仍有三项冲突（三波遭遇、期望 52000 HP 当前 18000、几何中心期望与设计局部 `[0,-22.5]`），未擅自改数值或删测试，也未补到能证明「非本轮引入」的改前实跑基线。
- 资源 UID 回退与退出时 ObjectDB 残留告警未清零。
- 未做人工从纯新档贯通整关的验收；本轮仍是章节 fixture + 真实业务集成。
- 插入表演未做 IK（见 §3.1），若要严格物理需改设计。
- 后三个 Boss、其余三把钥匙与中心主塔最终战未实现。
