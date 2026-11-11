# 宝箱聚光灯出现动画收口 · 2026-11-11

日期：2026-11-11；记录ID：`WORLD-LOOT-CHEST-SPOTLIGHT-APPEAR-20261111`；功能ID：`WORLD-LOOT`；工程版本：`0.1.0`。
设计依据与修订：[战斗奖励与物品流转设计 §表现层口径](../design/战斗奖励与物品流转设计.md#表现层口径-2026-11-10)，r6；代码基线：工作区当前基线（实现位于 `src/world3d/TreasureChest3D.gd`，专项验收位于 `tests/verification/verify_chest_appear_fx_prompt.gd`）；交付提交：提交前标记工作区。

## 变更与原因

用户要求宝箱光出现时必须有展开动画，不能突然亮起。本次在原有聚光灯上增加开启时间轴，更新设计、专项验收及道具账本，不新制光效资产。

- 主线程实现口径冻结为 `0.42s`、`SINE EASE_OUT`。
- 水平缩放从 `0.04` 展开到 `1`。
- 光柱透明度、地面光斑 alpha、真实聚光灯与补光亮度同步从 `0` 到正常值。
- 关闭优先于开启：关闭中断正在开启的动画，从当前进度收灯，不从头播放或突然切换到全亮。
- 读档状态已开箱时不闪亮、不创建或重播出现动画。
- 普通黄色与 advanced 酒红的颜色和来源档位不变；该动画不改变奖励、交互协议或存档语义。

账本同步定位于 `assets/registry/ledger_index.json` 的 `props` 域，即 `assets/registry/ledgers/ShellStorm2_道具账本_v001.xlsx`。只更新既有 `PRP-3D-REWARD-CHEST-NORMAL` 与 `PRP-3D-REWARD-CHEST-ADVANCED` 行的备注，并追加一条域变更日志；不新增 AssetID、不补录历史ID、不改 Prefab 分页、公式或其他资产行。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| 账本改前快照与 openpyxl 写回 | 工程外既有 `ShellStorm2-work/scratch/` | 已执行 | 账本备份与逐格对照记录在本次工作过程；目标差异限定为 Y48/Y49 与 `域变更日志` 新增一行 |
| 设计/开发文档链接与元数据 | 当前工程文档 | exit 1，11 条现存断链，本次新增页无断链 | `scripts/check_documentation_contracts.py` |
| `verify_chest_appear_fx_prompt.tscn` | Autoload 启动前用独立 APPDATA 隔离 | 输出 `CHEST_APPEAR_FX_PROMPT_OK`；两档初帧/中段/终态、中断收灯、读档不闪亮断言通过 | 同次启动存在非预期依赖编译错误：`Dungeon3D.gd:593` 缺失 `EncounterAlertOverlay` 类型，并连锁至 `FateCardGameBridge`；不能据 OK 标记宣称工程全绿 |
| 真实渲染 | 未执行 | 未验收 | 本轮仅 headless 时间轴和节点属性断言 |

## 遗留与状态更新

- 开启动画已经实现，专项新增断言覆盖两档开灯、中断收灯及已开箱恢复；首帧亮度在构建时置零，使用 deferred 启动避免读档空箱闪光。
- 开启/关闭共用进度写者，同步处理真实 SpotLight3D 与补光（也修正旧收灯只淡补光、未淡聚光灯的问题）。真实渲染未做，整体状态保持 partial。
- 工作区原有并行改动、历史账本红项和既有文档门禁问题不在本次范围内，不予吸收或修复。
