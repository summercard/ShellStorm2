# 远征关卡牌居中红锁、后排放大与主线资产补记

- 日期：2026-11-10；工程版本0.1.0；FeatureID：WORLD-ENTRY / BASE-FACILITY / WORLD-LOOT。
- 来源：用户要求锁头直接放在关卡图标中间且更大，后两关图标增大但不超过前两关；这轮新增道具/物品均登记账本。
- 主设计：[远征全息城市交互r9](../design/远征全息城市交互设计.md)；主线规则仍见[3.1—3.3与四钥匙设计](../design/主线剧情3.1至3.3与四钥匙设计.md)。本次不更改剧情台词、永久进度、关卡出发与存档语义。

## 1. 备份与边界

先备份最新UI源码、两份验收源码、设计、manifest、开发目录与日志，按原相对路径存于工程外 `ShellStorm2-backup/2026-11-10_082447766062_main_story_centered_locks/before_edits/` 独立时间戳事务；确切路径与7份逐文件SHA核对见工程外 `ShellStorm2-work/sessions/2026-11-10_centered_locks/backup.json`。账本另做独立备份 `ShellStorm2-backup/20261110_081614_246034_main_story_icon_ledger/before_edits/`，不覆盖此前主线制作备份。所有源均含本轮开始前未提交改动，未整树回退或覆盖。

本次运行、截图及最终汇总统一位于工程外 `ShellStorm2-work/outputs/2026-11-10_centered_locks/`。运行前进程级隔离APPDATA/LOCALAPPDATA，不使用正式用户存档。

## 2. 表现修改

- `src/ui/HologramCity3D.gd`：`LOCK_ICON_POSITION=(0,0,0.25)`，`LOCK_ICON_SCALE=1.30`，由右上小锁改为牌面居中大锁，保留红色几何、U形锁梁、扫描线及呼吸发光。
- 锁定状态名称移至局部y=-1.47，提示y=-1.95，编号y=1.40；锁头占牌面中间，不压名称。解锁后锁头隐藏，文字恢复原牌内位置。
- 后排破败旅馆 `expedition_02` 与未知区域 `expedition_04` 的marker_scale从0.78到0.95，线性增幅 `0.95/0.78-1≈21.8%`；前排数据库与公馆保持1.00。世界基准0.09、入口位置、楼群随机流、近景相机推进及悬停/点击曲线不变。
- 只读快照新增锁头中心、倍率和四牌基础倍率；不写永久进度，不修改 `RogueMapSelectMenu.gd` 的权限、命中和出发实现。

## 3. 资产登记核对与补记

| 资产 | 当前登记 | 本次动作 |
|---|---|---|
| 稀土钥匙 `ITM-MAIN-STORY-RARE-EARTH-KEY` / `mq_key_rare_earth` | 道具主表50、3D-物品29、物品道具《非背包与待设计》10 | 已完整登记，核对SHA/基线/内容导航，保留原行不重复新增 |
| 四槽台座 `PRP-BASE99-MAIN-STORY-KEY-PEDESTAL` | 场景主表1023、3D-设施64 | Y1023补四槽、槽灯、线路上扫、N/4环与脉冲均为父资产内嵌；旧ID差异已于v0.1.82修复；域日志v0.1.83 |
| 全息选关 `UI-SCREEN-LEVEL-SELECT` | UI主表13 | Y13补居中1.30倍大锁、后排0.95、扫描/发光为内嵌；域日志v0.2.6 |
| 既有高级科技箱 `PRP-3D-REWARD-CHEST-ADVANCED` | 道具主表49、3D-道具10、物品道具《非背包与待设计》8 | Y49及内容C8补主线3.2复用、首次指定箱禁拟态、额外key且保留普通奖励；域日志v0.1.108 |

前三把后续钥匙仍只是设计预留，未虚造已完成资产。钥匙/台座仍是“原型已接入”，无Blender/GLB正式母版；拿出、换手、插槽是同一钥匙表现，不拆成重复道具行。锁头与扫线等没有独立Prefab，记录到父资产，不伪造独立VFX或PRP。

四份工作簿值差异仅25格：4个备注＋3条域日志各7格。两条已有目标资产行基线v更新，九域列摘要重算；其余资产v、所有受保护Prefab分页摘要、公式/DV/表格/筛选和已有样式保留。高级箱旧缺SHA及未入基线不在本次偷偷接纳。`asset_manifest.json`补高级箱复用与内嵌表现覆盖，定点刷新UI源码/设计附属hash；主Prefab路径和SHA不变。

工程外完整逐格/门禁证据：`ShellStorm2-work/20261110_081614_246034_main_story_icon_ledger/result.json`、`asset_registration_matrix.json`、`issues_before_after.json`。账本门禁前后完整issues集合比较新增0、消失0，旧红项保留：structure224、props5、scenes2、ui5、split227；这些门禁exit1，命名exit0，不能写资产全局全绿。

## 4. 测试问题及修正

使用既有 `verify_main_story_navigation` 增加中心/倍率、锁定文字让位、解锁恢复断言及可选真实渲染双状态捕获；不新增平行UI或运行入口。

初轮视觉测量错误使用已被菜单接管的原玩法相机，导致屏幕命中断言失败；改为菜单正式近景相机。随后中心投影比较没有统一深度，透视导致1—2逻辑像素差；改为同一牌中心深度比较，仍保留小于1像素中心误差约束，未放宽阈值。

原 `verify_expedition_hologram_city` 在1080×608窗口注入鼠标时直接使用1280×720视口逻辑坐标，`canvas_items`伸缩令事件错位。只修改测试：先以 `get_final_transform()` 将逻辑坐标转为窗口坐标，再 `Input.parse_input_event`；逐帧等待并记录pick/selection/requests，鼠标、Enter、手柄和关闭恢复断言均保留。不改生产输入实现、不删覆盖。

## 5. 最终实际运行

最终证据在 `ShellStorm2-work/outputs/2026-11-10_centered_locks/final/`，初轮失败报告保留，不覆盖为通过。所有Godot进程自然退出，无超时杀进程。

| 项目 | 实际结果 | 证据 |
|---|---|---|
| 导航/锁定/倍率/恢复无头专项 | exit0，MAIN_STORY_NAVIGATION_OK | `navigation/process_result.json` |
| 真实Forward+双状态与中心/大小/命中 | exit0，MAIN_STORY_NAVIGATION_OK | `visual/process_result.json`、`visual/visual_report.json`及0/4、1/4截图 |
| 原全息菜单输入/锚点/动画/关闭恢复回归 | exit0，EXPEDITION_HOLOGRAM_CITY_OK anchored=true controls=0 input=passed restore=passed | `input_regression/process_result.json` |

Forward+ / Vulkan / Windows原生1080×608窗口。报告使用伸缩前逻辑像素：前排牌宽约115.3/105.4，后排约81.5/88.2，符合后排不大于前排；相同深度锁头中心误差0。原生截图已逐张查看，0/4三锁、1/4两锁，公馆解锁名称回牌内，未见严重重叠、裁字；新后排牌及锁头明显增大。

预期故障注入：本轮无；最初几轮FAIL为测试测量/坐标错误，已修后重跑，不归为预期成功。最终三场ERROR/SCRIPT ERROR/FAIL均空；资源invalid UID按文本路径回退仍有，完整原日志保留，不称零warning。本次仅UI表现/导航回归，没有重跑主线三场全文、Boss战或全关贯通，不能用本轮替代那些验收。

## 6. 静态复核

交付前执行文档契约、验收登记、功能追溯、运行资产命名、52份运行数据投影与git diff空白检查；逐项真实退出码及完整输出保存在上述outputs根的 `static_checks.json`。文档旧14断链与资产历史红项单列，不因本次UI通过写为全工程通过。
