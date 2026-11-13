# 读取页灯色逐关化：01 灰蓝 / 02 淡黄 / 03 玫红

- FeatureID：UI-HUD / WORLD-ENTRY
- 版本：0.1.0
- 来源：业主 2026-11-13 —— 「loading的这个灯的颜色，根据不同的关卡使用不同的颜色。01使用灰蓝色，02使用淡黄色，03使用玫红色。」
- 状态：实现与无头/真渲染专项通过；真实关卡进出流程未重跑，整体沿用现有 partial。
- 主契约：`scenes/ExpeditionLoadingScreen.gd` 的 `CIRCLE_COLOR_LEVEL_*` 与 `light_color_for_level()`；`assets/shaders/loading_circle.gdshader` 只保留兜底默认值。

## 改动

| 文件 | 改动 |
|---|---|
| `scenes/ExpeditionLoadingScreen.gd` | 新增 `CIRCLE_COLOR_LEVEL_01/02/03` 三档常量、`static light_color_for_level(level_id)`、实例方法 `_circle_light_color()`；`_build_circle()` 由写死 `CIRCLE_COLOR` 改为 `_circle_light_color()` |
| `assets/shaders/loading_circle.gdshader` | 只改注释：说明 `light_color` 的默认值现在只是「没有关卡上下文」时的兜底，逐关配色由脚本写入 |
| `tests/verification/probe_expedition_loading_iris.gd` | 新增 `_check_light_colors()`（见下） |
| `tests/verification/probe_loading_lamp_colors_shot.gd/.tscn` | 新增真渲染截图探针，四档（01/02/03/99 兜底）各出一张 |
| `docs/v0.1/design/UI与UX全局设计及全界面清单.md` | UI-02 补「逐关灯色」一条 |

## 数值推导（数值必须给公式）

灯是 `render_mode blend_add` 的纯色片，`light_color` 是**加色量**而非成品色，所以配色必须反过来算：

```
底色 INK = (0.031, 0.055, 0.086) = rgb(8, 14, 22)
单灯成品 = INK + light_color
交叠成品 = INK + 2 × light_color      # 两枚圆各加一次
⇒ light_color = 单灯成品 − INK
```

| 关卡 | 单灯成品 T | light_color = T − INK | 交叠（2×） |
|---|---|---|---|
| 01 灰蓝 | rgb(110, 127, 150) | `(0.400, 0.443, 0.502)` | rgb(212, 240, 255) |
| 02 淡黄 | rgb(196, 185, 110) | `(0.738, 0.670, 0.345)` | rgb(255, 255, 198) |
| 03 玫红 | rgb(199, 92, 122) | `(0.749, 0.306, 0.392)` | rgb(255, 170, 222) |
| 兜底金 | rgb(118, 103, 30) | `(0.435, 0.349, 0.031)` | rgb(229, 191, 38) |

判色相看**增量**比值，不看成品比值（成品被底色抬起，B 通道尤其失真）：

- 01 增量 `G/R=1.11`、`B/R=1.25` —— 冷，蓝是最高通道；
- 02 增量 `G/R=0.91`、`B/R=0.47` —— 暖，蓝最低；
- 03 增量 `G/R=0.41`、`B/R=0.52` —— 红最高、绿最低。

02/03 的交叠在亮通道上会顶到 255（加色饱和）。这是「更亮的同族色」，不是换了颜色；为了让交叠不溢出而压低单灯，只会把淡黄退成橄榄、把玫红退成暗红 —— 那才是丢了目标色。

## 归属判定：基地往返不借用 01 的颜色

`_circle_light_color()` **不能**调 `_destination_level_id()`：该函数会把空 id 悄悄收敛成 01（`default_expedition_level_id()`），于是「回基地」也会被染成 01 的灰蓝，而玩家并没有走进任何一关。因此先判 `_is_base_destination(_target_scene)`，基地/塔楼往返直接走兜底金；其余按 `_level_id`（选关菜单写入的待进入关卡 id）取色。

未登记关卡（当前只有 `99` 测试关，以及未来新增但尚未配色前的关卡）一律兜底金 —— 新增一关要改颜色，必须回来加一条 `match` 分支，不会「悄悄继承上一关」。

## 验收

| 项 | 结果 |
|---|---|
| `probe_expedition_loading_iris`（无头） | `PROBE_OK expedition_loading_iris`，exit 0；新增 `_check_light_colors()` 断言：三关互不相同、01 蓝通道最高、02 是 R≈G 且都高于 B、03 是 R>B>G、99 与空串兜底一致、兜底不等于任何一关 |
| 反向对照 | 临时把 02 改成 03 的值 ⇒ `PROBE_FAILED 2`（「逐关灯色存在重复」「02 灯色不是淡黄」），证明这组断言会红；跑完已还原（`0.738, 0.670, 0.345` 在场，SHA 与改前一致） |
| 真渲染截图 `probe_loading_lamp_colors_shot` | 四张 `_scratch_logs/loading_lamp_{01_grey_blue,02_pale_yellow,03_rose,99_fallback_gold}.png`，`SHOT_OK` ×4、`SHOT_DONE`，0 `SCRIPT ERROR` / 0 `ERROR`；逐张目视：01 冷蓝片、02 淡黄片、03 玫红片、99 仍是原金 |

断言刻意查**色相关系**而不是抄一份 RGB：抄数字的门禁只会在「有人调了色」时无条件变红，反而逼人改测试；这里守的是设计意图（三关一眼可区分、每关落在自己的色相家族、99 与基地不借用任何一关的颜色）。

## 未做 / 保留

- **真实关卡进出未重跑**：本轮只验颜色取值与渲染结果，未跑 99F → 三关的完整读取流程；灯色取的是 `_level_id` 字段，而该字段由选关菜单在切场景前写入，这条链路是既有实现、非本轮新接线。
- **`verify_test_level_99_flow` 仍 exit 1，三条红均为既有**：`两座楼的目的关卡ID映射错误`（断言 `menu.LEVEL_IDS == ["expedition_01","99"]`，而情报室现在是 4 个入口）、`城市缺少两座入口楼`、`未指定关卡时读取界面标题被改变：CloseAI数据库`（断言常量仍是 `DEFAULT_DISPLAY_NAME = "远征关卡01"`，清单里 expedition_01 已改名「CloseAI数据库」）。改前 `git show HEAD:` 版本跑同一场景得到**同一份日志、同样三行、同样行号 1618/1624/1630、同样 exit 1**，故与本轮灯色无关，不并入本次结论。
- 其余关卡（`expedition_04 未知区域`）业主未给色，当前兜底金；给了色再回来加分支。
- 截图探针用 `_resource_warmup_active = true` 掐掉真实读取来保住画面，因此它**不能**当作读取流程的功能验收。
