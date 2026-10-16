# 伤害飘字「黑色描边」修复：MSDF `msdf_pixel_range` 太小把描边截断了

用户指令（原文）：「**腰带黑色描边**」→ 追问后澄清：「**要带黑色描边，我说的是伤害飘字。我打错了**」
（「腰带」是「要带」的错字。教训：这条指令里的名词在工程内零命中时，先问再动 —— 我当时搜遍了
`腰带` / `belt` / `带`，工程里**根本没有**叫这个的东西，问一句就省下了瞎猜的方向。）

## 一、现象与第一次误判

上一轮（v003.9，2026-10-16）刚把描边定到 26 / 30 / 34（≈ 字高的 22%），但从实拍预览里量，
描边只有 **1~2 px**（≈字高的 2%）。第一反应会以为是"比例不够"，于是上轮把 19% 抬到 22%
—— **实测证明这一步在视觉上零变化**。

## 二、根因（Godot 官方口径 + 实测坐实）

Godot 文档「Using Fonts → Font outlines and shadows」与
[issue #70211](https://github.com/godotengine/godot/issues/70211) 明确：
**MSDF 字体下描边可达上限 ≈ `msdf_pixel_range / 2`；默认 `msdf_pixel_range = 16`，只够描边到 8。**
我们的 26 / 30 / 34 **远超 8** ⇒ 描边被**提前截断**。

**铁证**：`_scratch/probe_outline_calibration.gd` 里把同一字形的 `outline_size` 取 26 与取 **116**，
两张 PNG **逐像素完全相同**（`ImageChops.difference(...).getbbox() is None`）—— 值根本没被用上。
（`SystemFont.msdf_pixel_range` 是存在且可读可写的，回读 `set == read`。）

## 三、定档（换成数字）

换算口径：距离场里 1 纹素 = `font_size / msdf_size` 个字形像素 ⇒
需求 `range = 2 × max(描边 × msdf_size / 字号)` = 2 × (34 × 128 / 152) ≈ **57.4**。

近距离定尺实测（字形高约 108 px，`probe_outline_calibration2/3.gd`）：

| range | 声明描边 26 @ 字号 116 的实画宽 |
|---|---|
| 16（Godot 默认） | **6 px** —— 截断，等于没有 |
| 48 | 21 px —— 仍被轻微截断 |
| **64 / 80** | **26 px** —— 足额 ✅ |
| 96 | **左右不对称**，一侧描边整条丢失 ⇒ 距离场精度不够，**过大反而崩** |

⇒ 取 **64**，并设**上界护栏 80**（不是为了省，是实测结论）。

## 四、修法（改动面前所未有地小）

`src/vfx/DamageNumberStyle.gd`（飘字字体与样式的**单一真源**）：
1. 新增 `const MSDF_PIXEL_RANGE := 64`；
2. `make_font()` 里加 `font.msdf_pixel_range = MSDF_PIXEL_RANGE`。

三条链路（`VfxDamageNumber3D` / `VfxHealNumber3D` / 独立兜底 `CombatDamageNumber3D`）**都经这个
字体工厂**取字体（全工程只有这里 `SystemFont.new()`）⇒ **改一处全覆盖**。
AssetID / Prefab 路径 / `.tscn` / `VfxPool3D` 注册表**一律未动**（纯脚本侧）。

## 五、验收（新增一条守隐形契约的不等式）

`tests/verification/verify_damage_number_style_flow.gd` 新增：
1. 常量钉子 `MSDF_PIXEL_RANGE == 64`；
2. **下界不等式** `MSDF_PIXEL_RANGE ≥ 2 × max(描边 × msdf_size / 字号)`，算式用**验收侧硬编码的
   期望值**算（不读被测常量，否则「常量改小、需求跟着变小」= 自印证）；
3. **上界护栏** `≤ 80`；
4. 逐档断言**实机实例上的 SystemFont 真的带了这个值**，且该档自己的需求被覆盖。

**反向对照三组**（全部精准变红后还原复绿）：
| 对照 | 期望 | 实测 |
|---|---|---|
| `MSDF_PIXEL_RANGE = 16` | 下界红 | ✅ `needs >= 57.4` |
| `MSDF_PIXEL_RANGE = 96` | 上界红 | ✅ 提示单边崩坏 |
| **删掉 `make_font()` 里那行赋值** | 实例断言红 | ✅ 报 `is 16, expected 64` + 逐档需求红 |

第三组是**本次的静默失败模式本身**：常量对、实例没赋上 ⇒ 不报错、不变量、只是"看不清"。

**实机距离 A/B**（同相机、同散布，`_scratch/preview_damage_number_style.gd`）：
描边像素 **160 → 13,421（×83.9）**。`outputs/outline_before_*.png`（修前）vs
`outputs/damage_number_style_*.png`（修后）。

## 六、回写

- `docs/v0.1/14.6_特效系统与制作规范.md` §3.8：字体表加「距离场宽度」行；新增
  **「⚠️ MSDF 描边上限」**一节（开篇写死 Godot 口径 + 定档表 + 两头都要盯）；改写原来那条
  基于误判的「19% → 22%」说明；验收段补新断言与三组对照；版本历史 **v003.10**。
- `docs/v0.1/MODULE_INDEX.md` 的 `VFX-POOL` 行：验收清单与现状说明补本轮。
- 账本 `ShellStorm2_特效账本_v001.xlsx`：《3D-特效》FX02-01/02 升 **v003**（col12 尺寸列补
  `msdf_pixel_range 64`）、备注追加标记 `【2026-10-17 勾边修复】`；域变更日志追加 **v0.1.25**。
  回写脚本 `_scratch/update_ledger_outline_fix.py`，幂等（标记串 + 版本号判重），复跑无脏写。

## 七、门禁

`ASSET_REGISTRY_CHECK_OK scope=full assets=37 ledgers=1`，`issue_counts: {}`；
`verify_damage_number_style_flow` / `verify_3d_enemy_behavior_flow` / `verify_vfx_pool_lifecycle`
均 `exit 0`。

## 八、可迁移的教训（这条值得进 skill）

1. **Godot 里凡「设了值但画面没变」，先怀疑"值被引擎上限截断"，而不是"值不够大"。**
   本轮 19% → 22% 的调整就是被这条坑掉的：两版都被截到同一个上限，所以视觉零变化。
2. **验证"参数有没有被用上"，最狠的办法是把它改成一个荒谬值再看渲染是否变化**
   （26 vs 116 逐像素相同 = 铁证）。比读文档快、比猜准。
3. **调参不能只盯下界。** range 96 的崩坏是"越保险越坏"—— 护栏要双向。
4. **跨文件/跨层的隐形契约必须有一条会失败的断言盯着。** 这里契约的两端是
   `*_OUTLINE_SIZE`（本文件上方）与 `msdf_pixel_range`（`make_font()` 里），
   中间没有任何编译期约束 —— 现在由一条不等式 + 一条实例断言绑住。
5. **别把"顺手调大一点"当作保险。** 本轮上界护栏就是为这句话设的。

## 九、环境

仓库根 = `I:/工作项目/shellstrom2/ShellStorm2`。定尺拍摄必须**不用 `--headless`**（headless 不渲染）；
本机无 `timeout` 命令。`_scratch/` 已 gitignore，探针与回写脚本都放那里。
