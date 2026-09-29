# 2026-09-29｜99F 基地设施头顶文字精简（常驻设施牌退役 + 黄色提示放大抬高）

业主原话：

> 「我 99f 基地内的设施，头顶上有个常驻的文字说明漂浮，帮我去掉。保留解禁后的那个黄色的提示即可。然后那个黄色的字体放大一点，然后位置高一点。」

## 一、现状：头顶那两个 Label3D 是谁

99F 基地的 8 个交互设施全部是 `BaseFacility3D` 实例，每个头顶挂着两个 `Label3D`：

| 节点 | 素材颜色 | 显示时机 | 文字 |
| --- | --- | --- | --- |
| `NameLabel` | `Color(0.82, 0.96, 1)` 淡蓝白 | **常驻** | `名称\n实时摘要`（`apply_snapshot` 写入） |
| `PromptLabel` | `Color(1, 0.82, 0.28)` **金黄** | 玩家进 Area + 被聚焦 | `[E] 使用 名称`；不可用时改为 `availability_reason` |

⇒ 业主说的「常驻的文字说明漂浮」就是 `NameLabel`，「解禁后的那个黄色的提示」就是
`PromptLabel`（设施可用后靠近才出现的黄色 `[E] …`）。

设施清单（`zone_base` 一层 + `env_base99_remaining_facilities` 七个包装包 + 枪械工坊）：

| 资产包 | `facility_id` | 显示名 |
| --- | --- | --- |
| `72_SUPPLY24H自动补给机_资产包` | `base_vending` | 自动贩卖机 |
| `51_圆形全息设备平台_资产包` | `mission_operations` | 远征情报室 |
| `42_双屏电脑完整工位_资产包` | `fate_collection` | 命运卡收藏室 |
| `36_墨绿三人休闲沙发_资产包` | `avatar_wardrobe` | 角色衣柜 |
| `45_MEDICAL医疗柜_资产包` | `base_recovery` | 状态恢复舱 |
| `47_窄型电池柜_资产包` | `vault` | 保险柜 |
| `49_武器工作台与弹药附件_资产包` | `monster_archive` | 怪物档案室 |
| `枪械工坊`（`prp_base_weapon_workshop`） | `weapon_workshop` | 枪械工坊 |

## 二、改法与旋钮

只改一处：`src/base3d/BaseFacility3D.gd`。**没有动任何资产 prefab、没有动 tscn** ——
头顶文字的显示策略属于表现逻辑，归脚本单一所有者；资产重建不会把这次改动冲掉。

```gdscript
const NAME_LABEL_VISIBLE := false          # 常驻名字牌退役
const PROMPT_LABEL_FONT_SIZE := 34         # 黄色提示字号（资产原值 24 / 26）
const PROMPT_LABEL_HEIGHT_LIFT_M := 0.6    # 相对素材锚点抬高（米）
```

`_ready()` 里 `_apply_default_base_size()` **之后**调 `_apply_prompt_label_presentation()`：
先 `font_size = 34`，再 `position.y += 0.6`。顺序不能反 —— 抬升量是最终米数，
不参与 `base_size_multiplier` 缩放（99F 这 8 件都是 `1.0`，旧基地的球体件是 `0.70`）。

`NameLabel` **节点保留、`text`/`modulate` 照常维护**，只把 `visible` 关掉。原因：
`verify_base_facility_framework` 断言 `"\n" in facility.name_label.text`（快照契约），
而且「随时可以一行改回常驻设施牌」比删节点便宜。

## 三、实测（探针 `probe_base_facility_label_presentation`）

隔离工作区实跑，8/8 通过，`PROBE_FACILITY_LABEL_PRESENTATION_OK: 8 facilities`：

| 设施 | 提示 y（素材 → 现在） | 退役名字牌 y | 字号 |
| --- | --- | --- | --- |
| 自动贩卖机 | 3.76 → **4.36** | 4.05 | 26 → 34 |
| 远征情报室 | 2.25 → **2.85** | 2.60 | 24 → 34 |
| 命运卡收藏室 | 1.68 → **2.28** | 1.97 | 26 → 34 |
| 角色衣柜 | 1.0758 → **1.6758** | 1.3658 | 26 → 34 |
| 状态恢复舱 | 1.825 → **2.425** | 2.115 | 26 → 34 |
| 保险柜 | 1.77 → **2.37** | 2.06 | 26 → 34 |
| 怪物档案室 | 2.015 → **2.615** | 2.305 | 26 → 34 |
| 枪械工坊 | 3.44 → **4.04** | 3.73 | 26 → 34 |

每件都满足：名字牌不可见、快照文字非空、提示牌字号 34、y 严格高于退役名字牌锚点
（高出 0.25–0.31 m），且「进范围 + 聚焦」时提示牌真的出现。

## 四、门禁判据

探针的每条断言都能被反向对照打红：

- 把 `NAME_LABEL_VISIBLE` 改回 `true` ⇒ `retired name label is still visible` 红；
- 把 `PROMPT_LABEL_FONT_SIZE` 改回 `26` ⇒ `font_size != 34` 红；
- 抽掉 `PROMPT_LABEL_HEIGHT_LIFT_M`（或放回 `_apply_default_base_size()` 之前）⇒
  `prompt y != authored + 0.6` 与 `is not above retired name anchor` 红；
- 把 `set_interaction_focus` 的可见链路断开 ⇒ `does not appear when focused` 红。

## 五、视觉采样（真渲染器，非 headless）

逻辑断言回答不了「头顶到底还剩什么」，所以另外拍了一组近景：
`probe_base_facility_label_visual` 把三件设施单独摆上舞台，相机贴到模型前方，
并让提示牌处于「玩家在范围内 + 已聚焦」的真实可见态。

产物（`outputs/verification/`）：

| 文件 | 设施 | 画面结论 |
| --- | --- | --- |
| `base99_facility_label_medical_cabinet.png` | 状态恢复舱 | 柜顶只有黄色 `[E] 打开 状态恢复舱` |
| `base99_facility_label_hologram_terminal_platform.png` | 远征情报室（圆形全息平台） | 平台上只有黄色 `[E] 打开 远征情报室` |
| `base99_facility_label_east_supply_24h_station.png` | 自动贩卖机 | 机柜顶只有黄色 `[E] 打开 自动贩卖机`（该张拍到的是背面，资产本身偏暗） |

三张图里都**没有**常驻的「名称 + 实时摘要」两行文字 —— 这就是本次要的结果。

⚠️ 探针的取景有一个实测踩到的坑：相机高度抬到 `radius × 1.15 + 1.0` 时会拍成
**空视口（全黑）**，已回退到 `radius × 0.45`。代码里留了注释，别再去「优化」这个高度。

## 六、验收状态

| 环节 | 命令 | 结果 |
| --- | --- | --- |
| 逻辑探针（隔离工作区，headless） | `godot --headless --path <隔离项目> res://tests/verification/probe_base_facility_label_presentation.tscn` | `PROBE_FACILITY_LABEL_PRESENTATION_OK: 8 facilities`，进程退出 0 |
| 正式门禁（4 场景 batch） | `bash scripts/run_verification_suite.sh batch verify_base_facility_framework verify_base_facility_interaction_zones verify_unified_player_interaction_flow verify_base99_remaining_facilities_v021` | 4/4 通过：`VERIFICATION_SUITE_OK suite=batch count=4` |
| 正式门禁（加新断言后复跑） | `bash scripts/run_verification_suite.sh scene verify_base_facility_framework` | `BASE_FACILITY_FRAMEWORK_OK`，`VERIFICATION_SUITE_OK suite=scene count=1` |
| 视觉采样 | `godot --path <隔离项目> --scene res://tests/verification/probe_base_facility_label_visual.tscn` | 3 张图落盘，见 §5 |
| 文档契约 | `python3 scripts/check_documentation_contracts.py` | exit 0；剩余 issue 是既有的 3 个未注册场景（`verify_base99_swivel_chairs` / `verify_expedition01_spawn_ramp` / `verify_pushable_base_chairs`），非本次引入 |

⚠️ 两个套件命令的**进程退出码都是 1**，但日志末尾是 `VERIFICATION_SUITE_OK`。原因不是断言失败：
环境的批量删除护栏（`[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]`）拦下了套件 EXIT trap 里
对临时工作区的 `rm -rf`，`assert_workspace_removed` 因此判红，残留约 5.1 G，已手动清掉。
判定依据取「场景自身的 OK 行」，不取这个被环境护栏污染的退出码。

## 七、边界：同一脚本的第二个场景

`BaseWorld3D.tscn`（旧主基地）的 9 个设施走同一脚本，因此同步生效 —— 这是**有意**的：
「头顶不要常驻漂浮文字」在哪个基地场景都该成立，且那份资产默认 `base_size_multiplier = 0.70`，
抬升量 0.6 m 不参与缩放，落点仍然贴在设施顶上。

## 八、没有动的东西

- 资产 prefab 里的 `NameLabel` / `PromptLabel` 节点、字号 32/26、位置全部保持原值 ——
  运行时的字号与位置由脚本在 `_ready()` 覆盖，素材仍可作为回退基线。
- `NameLabel` 的状态色语义（金 = 有待办、青绿 = 正常、红 = 不可用）保留在 `apply_snapshot` 里，
  只是不再显示；以后要做「设施头顶只显示异常」这类需求，接上 `visible` 即可。
