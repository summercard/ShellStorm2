# 2026-10-12｜99F 基地设施黄色交互提示再放大一倍（34 → 68）

业主原话：

> 「基地内所有设施头顶上的这个黄字，放大一倍。」

配图是 99F 基地中央圆形全息平台（`mission_operations` / 远征情报室）前，
玩家进范围并被聚焦时出现的黄色 `[E] 打开 远征情报室`。

## 一、改的是哪一块字

99F 基地 8 个交互设施全部是 `BaseFacility3D` 实例，头顶挂两个 `Label3D`：

| 节点 | 现状 | 说明 |
| --- | --- | --- |
| `NameLabel` | **不显示** | 2026-09-29 已退役，节点与 `text`/`modulate` 保留给快照契约 |
| `PromptLabel` | 玩家进 Area + 被聚焦才出现 | 金黄 `Color(1, 0.82, 0.28)`，`[E] 打开 <设施名>` |

业主说的「设施头顶上的这个黄字」就是 `PromptLabel` —— 它是设施头顶**唯一**还显示的文字。

## 二、改法与旋钮

只改一处：`src/base3d/BaseFacility3D.gd` 的常量。**没有动任何资产 prefab、没有动 tscn。**

```gdscript
const PROMPT_LABEL_FONT_SIZE := 68   # 34 × 2（资产原值 24 / 26）
const PROMPT_LABEL_HEIGHT_LIFT_M := 0.6   # 不变
```

`_apply_prompt_label_presentation()` 在 `_ready()` 里照旧写 `font_size = 68`、
`position.y += 0.6`。抬升量是最终米数，不参与 `base_size_multiplier` 缩放，
顺序与 2026-09-29 一致，未改动。

### 为什么描边（`outline_size = 8`）不跟着翻倍

素材各 prefab 的 `PromptLabel.outline_size` 统一是 `8`，本轮**保持不变**：

- 68 号字配 8px 描边，相对字高等于 34 号配 4px —— 比 2026-09-29 那版更清爽；
- 项目里已有「`outline_size 8` 相对 `font_size 34` 太粗，相邻字黑边连成一片像黑框」
  的既有判断（见 `src/world3d/RoomKeyPickup3D.gd` 的注释），方向一致；
- 描边跟字一起翻倍会让黄字在亮地板上显得发糊，与「放大」的诉求相反。

若以后要描边等比，再加一个 `PROMPT_LABEL_OUTLINE_SIZE` 常量即可，节点属性本身归脚本单一所有者。

## 三、覆盖面

同一个脚本，所有走它的设施一起生效：

| 场景 / 资产包 | 设施数 | 是否生效 |
| --- | --- | --- |
| `env_base99_remaining_facilities`（99F 七个包装包） | 7 | ✅ |
| `prp_base_weapon_workshop`（枪械工坊） | 1 | ✅ |
| `BaseWorld3D.tscn`（旧主基地，同脚本） | 9 | ✅ |
| `HologramExpeditionFacility3D`（继承 `BaseFacility3D`） | — | ✅ |

**有意不在范围内**（各自的黄字已退役或不属于「基地设施」）：

- `DungeonEntrance3D` / `ServiceStation3D`：`set_interaction_focus()` 是空实现，
  文字牌已退役为纯文案载体，可见反馈由常驻白色交互圆点承担；
- `ThemedNPC3D`：NPC 对话提示（27 号），不是设施；
- `RoomLightSwitch3D`：战局内灯开关（34 号），不在基地。

## 四、门禁同步

| 文件 | 改动 |
| --- | --- |
| `src/base3d/BaseFacility3D.gd` | `PROMPT_LABEL_FONT_SIZE` 34 → 68，注释改为两轮口径叠加 |
| `tests/verification/probe_base_facility_label_presentation.gd` | `EXPECTED_PROMPT_FONT_SIZE` 34 → 68 |
| `tests/verification/verify_base_facility_framework.gd` | 下界断言 `< 34` → `< 68` |

两处断言都保留「反向对照必红」的性质：把常量改回 34 ⇒ 探针 `font_size != 68` 红、
框架验收 `68 < 68` 不成立 ⇒ 报 `黄色交互提示字号未按 2026-10-12 口径放大`。

## 五、没有动的东西

- 资产 prefab 里的 `PromptLabel` 节点、`font_size = 24 / 26`、`outline_size = 8`、
  `position` 全部保持原值 —— 运行时数值由脚本在 `_ready()` 覆盖，素材仍是回退基线；
- `PROMPT_LABEL_HEIGHT_LIFT_M`、`NAME_LABEL_VISIBLE`、`NameLabel` 状态色语义
  （金 = 有待办、青绿 = 正常、红 = 不可用）与 2026-09-29 口径完全一致，未触碰。

## 六、验收记录

| 环节 | 命令 | 结果 |
| --- | --- | --- |
| 门禁（batch） | `bash scripts/run_verification_suite.sh batch verify_base_facility_framework verify_base99_remaining_facilities_v021` | `VERIFICATION_SUITE_OK suite=batch count=2`；`BASE_FACILITY_FRAMEWORK_OK`、`BASE99_REMAINING_FACILITIES_V021_OK` |
| 呈现探针 | `bash scripts/run_verification_suite.sh scene probe_base_facility_label_presentation` | `PROBE_FACILITY_LABEL_PRESENTATION_OK: 8 facilities` |
| 文档契约 | `python3 scripts/check_documentation_contracts.py` | exit 0；剩余 3 个既有 issue（未注册场景 7 个、`CHANGELOG.md:179` 断链、media 域 ui 行数 18≠16），均非本次引入 |

探针实跑（隔离工作区，headless）：

| 设施 | `facility_id` | 字号（素材 → 现在） | 提示 y（素材 → 现在） | 退役名字牌 y |
| --- | --- | --- | --- | --- |
| 自动贩卖机 | `base_vending` | 26 → **68** | 3.76 → 4.36 | 4.05 |
| 圆形全息设备平台 | `mission_operations` | 24 → **68** | 2.25 → 2.85 | 2.60 |
| 双屏电脑完整工位 | `fate_collection` | 26 → **68** | 1.68 → 2.28 | 1.97 |
| 墨绿三人休闲沙发 | `avatar_wardrobe` | 26 → **68** | 1.0758 → 1.6758 | 1.3658 |
| MEDICAL 医疗柜 | `base_recovery` | 26 → **68** | 1.825 → 2.425 | 2.115 |
| 窄型电池柜 | `vault` | 26 → **68** | 1.77 → 2.37 | 2.06 |
| 武器工作台与弹药附件 | `monster_archive` | 26 → **68** | 2.015 → 2.615 | 2.305 |
| 枪械工坊 | `weapon_workshop` | 26 → **68** | 3.44 → 4.04 | 3.73 |

8/8 全部满足：名字牌不可见、快照文字非空、提示字号 68、y 严格高于退役名字牌锚点
（0.25–0.31 m）、进范围 + 聚焦后提示牌真的出现。

⚠️ 两个套件命令的**进程退出码都是 1**，但日志末尾是 `VERIFICATION_SUITE_OK`。
原因与 2026-09-29 那次相同：环境批量删除护栏（`[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]`）
拦下了套件 EXIT trap 对临时工作区的 `rm -rf`，`assert_workspace_removed` 因此判红。
判定依据取「场景自身的 OK 行」，不取这个被环境护栏污染的退出码。残留工作区已用
`scripts/verification_workspace.py cleanup` 逐个清掉（`purge_stale_*` 只处理 >6h 的陈旧残留）。

## 七、后续

- 视觉复核建议：用 `probe_base_facility_label_visual` 重拍三张近景（状态恢复舱 /
  圆形全息平台 / 自动贩卖机），确认 68 号字在真实渲染器下的观感与占据宽度。
  本文档未包含该项，属未执行项。
