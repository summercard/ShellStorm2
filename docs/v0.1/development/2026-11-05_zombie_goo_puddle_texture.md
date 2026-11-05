# 2026-11-05 小僵尸死亡地面液体：纯色扁方块 → 贴图面片

## 业主口径

> 「那个小僵尸死亡特效，不是地上会有一个绿色方块的那个面片嘛，那个面片是用来替代用的，
> 帮我用 Image 2 做一张贴图，贴在这个方块上面，就是绿色的这个单张液体效果，
> 最好不要太写实，轮廓感强一些。」

拆成三条可验收的要求：

1. **只换「地上的液体」这一层**（`Puddle0..3`）。爆开的方块粒子、飞溅粒子不动。
2. **贴图要像一摊液体**（单张、绿色），不是一块纯色方块。
3. **不写实、轮廓感强** ⇒ 卡通平涂 + 粗描边，不能是有高光反射/噪声纹理/渐变湿漉感那种。

## 改了什么

| 位置 | 之前 | 现在 |
|---|---|---|
| `Puddle0..3` 的 mesh | `BoxMesh`，`scale = (side, 0.05, side)` | `PlaneMesh`（1×1，躺在 XZ），`scale = (side, 1, side)` |
| 材质 | `ToonVfx.toon_material(GOO_GREEN_DARK)` 纯色 | `ToonVfx.toon_texture_material(PUDDLE_TEXTURE)` 贴图 |
| albedo 染色 | 深绿 × `_goo_color`（0.7 混） | 白 × `_goo_color`（18% 混，`PUDDLE_TINT_BLEND`） |
| 深度写模式 | `DEPTH_DRAW_ALWAYS` | `DEPTH_DRAW_OPAQUE_ONLY` |
| 双面 | 默认（背面剔除） | `CULL_DISABLED` |

**没动的**：A 段 12 枚爆炸方块、B 段 14 枚飞溅方块、`TOTAL_LIFETIME = 1.35`、
`PUDDLE_HOLD_SEC = 0.50`、下沉 0.30m、四块错峰 0.025s、落点取飞溅真实落点的数学、
`GooLight` 的 0.34s 归零、`context.floor_y` 唯一真源。

## 贴图怎么来的（四步，每步都踩过坑）

产物 `assets/art/vfx/textures/vfx_zombie_goo_puddle_floor.png`（1024² RGBA），
原图与脚本在 `art_source/vfx/combat_3d/vfx_zombie_goo_puddle/source/v001/`。

1. **抠白**。生成器给的是**白底 RGB** —— `background=transparent` 没生效，整图 alpha 恒 255
   （`corner` 采样 `(254,255,253,255)`）。所以不能直接读 alpha 求包围盒，必须四边泛洪。
2. **阈值 80**。背景不是纯白，是一层**浅灰渐晕**：实测最暗 `207`，与 255 差 `48`。
   阈值取 40 时右上角留一片灰影；取 80 才盖住。绿色本体差 160+，浅色高光（`#A8F566`，差 87）
   虽低于阈值，但被绿色包着、泛洪打不进去，安全。
3. **剔灰孤岛**。渐晕被描边割开的小碎片泛洪进不去。按「低饱和（< 26）+ 高亮度（> 168）
   + 面积 < 1% 画幅」剔掉；绿色飞溅点与气泡高光不受这条规则影响。
4. **去白边（despill）**。alpha 羽化带按 `c_obj = (c - 255·(1-a)) / a` 反解，
   否则贴到深灰地板上会有一圈发光白晕。

### 「轮廓感」= 扩 24px 描边

生成图自带描边在源分辨率下约 12px。按 0.7m 面片在 960×600 视口里的实际占屏
（约 100~200px）换算后只剩 **2~3px**，被 mipmap 平滑成一片模糊绿 —— 第一版实拍就是这样，
业主说的「轮廓感」完全读不出来。

- 先加到 **10px**：实拍仍不可读。
- 加到 **24px**：实拍可读（`_scratch/goo_zoom_v3.png` 对照 `goo_zoom_final.png`）。

只**向外**扩、不向内侵蚀：内侵蚀会先吃掉那几颗 20~30px 的浅绿高光气泡，
而它们正是业主点名要留的「不写实」部分。描边色取原图最暗那批绿（实测 `#24500F`）再压暗到 `#1A3A0A`。

## 材质为什么要单开一个函数

`toon_material()` 用的是 `DEPTH_DRAW_ALWAYS`。对**实心方块**没问题（整块不透明，写不写深度都一样），
但对带透明边的贴图面片会出事：透明像素照样写深度 ⇒ 四块液体互相之间、以及被它们盖住的其它
地面件会被裁掉一块**方形空洞**，贴图的方形包围盒直接「显形」。

所以 `toon_texture_material()` 用 `DEPTH_DRAW_OPAQUE_ONLY`，并加 `CULL_DISABLED`
（单层平面从下方/斜掠视角不该整片消失）。

⚠ **没有改 `toon_material()` 的深度模式**。它被全部已有特效共用，改它会波及整条特效链。

## 验收

`verify_zombie_goo_death_vfx` 新增 `_check_puddle_texture`，`samples` **16 → 17**：

| 判据 | 为什么需要它 |
|---|---|
| 材质上真的挂了贴图 | 只看「有 `Puddle0`」会假绿 —— 换回纯色方块它也在 |
| 四角 alpha ≤ 32 | 贴图若满幅不透明，「轮廓感」无从谈起 |
| 边缘平均亮度 < 中段 × 0.75 | 「有描边」的可量化形态 |
| 四块共用同一张贴图 + 路径是约定的那一张 | 防止「只有第一块有贴图」或偷偷换图 |
| 深度模式 = `OPAQUE_ONLY` | 透明区写深度会裁穿地面 |
| mesh 是 `PlaneMesh` | 面片不该退回方块 |

**两个坑（都记在这里，别重犯）**：

- **不能用 `texture.get_image()` 读像素**。`--headless` 下它会去等渲染线程回读像素，
  实测把用例挂死 **8 分 17 秒**以上（本仓经典假死形态）。改成 `FileAccess.get_file_as_bytes`
  + `Image.load_png_from_buffer` —— 与运行时同一份数据，不依赖 GPU。
- **不能用「离中心的固定半径」量边缘**。图形占满整幅（content 横跨 71..955 / 1024），
  0.44~0.50 半径的环带落在**填充内部**，量出比值 0.95、判据恒假。改成按「离透明区的距离」
  定义边缘（探测距离 = 短边 × 2.5%，约 26px，略大于 24px 描边）。

### 反向对照（两组，均精准变红后还原复绿）

1. 退回纯色方块（`toon_material` + `_add_cube`）⇒ 红 **1** 条：
   「Puddle0 材质上没有贴图 —— 地面液体退回纯色方块了」
2. 深度模式改回 `DEPTH_DRAW_ALWAYS` ⇒ 红 **4** 条（四块各一条）。

## 运行结果

```
ZOMBIE_GOO_DEATH_VFX_OK: fx01-19 goo death pass (samples=17)   exit 0
DEATH_BLAST_VFX_OK: fx01-17 blast + fx01-18 zone pass (samples=12)   exit 0
```

胖子僵尸那条（`VfxDeathBlast3D`）共用同一段身体 ⇒ 自动同步换成贴图，验收复跑仍绿。

真渲染证据：`outputs/zombie_goo_death/frame_*.png`（9 帧，0.00 / 0.06 / 0.14 / 0.24 /
0.34 / 0.50 / 0.85 / 1.15 / 1.34）。

## 门禁

| 门禁 | 结果 |
|---|---|
| `check_runtime_texture_policy.py` | 新贴图 **0 error**（`size_limit=1024`、导入 1024² 未超限）；全表 9 条均为**既有**问题 |
| `check_asset_runtime_naming.py` | `ASSET_RUNTIME_NAMING_OK`，欠账未增减（贴图不在该门禁口径内，只认 `.glb`/`.tscn`） |
| `check_art_source_layout.py` | 唯一 issue 是 6 个既有 `.blend1`，与本次无关 |

## 遗留 / 提醒

- `GOO_GREEN_DARK` 现在**代码里没有使用点**了（深绿已画进贴图）。保留它作为
  「描边该是什么绿」的代码侧基准 —— 重做贴图时照它校色，别改成别的绿，
  否则贴图与 A/B 两段的方块粒子会分裂成两套配色。
- 想再调「轮廓感」，改的是 `build_puddle_texture.py` 里的 `OUTLINE_OUT_PX`（源图像素），
  不要靠调材质或加后处理 —— unshaded 面片没有边界可描。
- 贴图占屏尺寸与「四块位置」沿用既有口径（`PUDDLE_SIDE_BASE = 0.72` × size）。
  业主这次只提了换贴图，没提改大小，所以没动。
