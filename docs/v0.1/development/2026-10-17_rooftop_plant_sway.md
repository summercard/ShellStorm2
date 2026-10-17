# 天台植物风摆（P2 第一阶段 · v2 加大幅度）

功能ID：`WORLD-AMBIENT-DYNAMICS` / 子项 `P2 植物风摆`。工程版本 0.1.0。
设计修订：`scene_ambient_dynamics.md` §4。日期：2026-10-17 建，2026-10-18 修订 v2。

业主原话（初版）：「先把天台的植物的轻微晃动的先做，用最省的方法实现，简单直接出效果的。」
业主原话（v2）：「幅度可以再大一些，不够明显，然后藤曼也要动」。
约束：不动 Blender / GLB、不重新导入、Godot 侧实现。

## v2 修订（2026-10-18）

| 参数 | 初版 | v2 | 理由 |
|---|---|---|---|
| 盆栽/花箱幅度 | 0.035 m | **0.120 m** | 1.62m 冠高上 2.2° 太弱，要盯着看才读得出 |
| 藤蔓幅度 | 0.020 m | **0.090 m** | 同上，且藤蔓观感更需要相对位移 |
| 权重指数 | `pow(h, 1.8)` | `pow(h, 1.5)` | 1.8 把位移全挤到尖端，中段叶片几乎不动 |
| 主频 | 1.35 rad/s | 1.55 rad/s | 周期 4.7s → 4.1s，稍快更"在动" |
| 藤蔓位移方向 | 仅本地 z（离墙扑动） | **本地 x 横向主导 + z×0.5** | 见下 |

**藤蔓「不动」的根因**：初版只做本地 z 的离墙扑动，理由是「横向会让叶片顺墙滑动」。
但墙面在 x-y 平面，z 方向位移在正面视角下几乎没有透视变化 —— 等于白做。
改为横向主导后正面帧差从 1.8% 升到 **13.3%**。横向不会穿墙（墙厚在 z 方向）。

**物理位移核算**（`A · w · G · s`，`G∈[0.24,1.0]`，`s` 峰值 1.0）：

| 类型 | 冠顶典型 | 冠顶最坏 | 半高典型 | 半高最坏 |
|---|---|---|---|---|
| 盆栽/花箱 | 5.4 cm | 12.0 cm | 1.9 cm | 4.2 cm |
| 藤蔓 | 4.0 cm | 9.0 cm | 1.4 cm | 3.2 cm |

**验证新增**：
- N6 几何级穿墙判定（44 件植物 × 24 面房间墙，最坏摆幅）→ 新增体积重叠 **0**。
  该判据有已知盲区（沿墙面的横向摆动），已在脚本注释与设计文档 §4.8 写明。
- 噪声基线（同静止状态连拍两帧）= **0**，用来证明颜色对照的差值不是 TAA 抖动。
- 17 帧 × 0.25s 连拍序列：盆体 17 帧内最大差 **1**（浮点量级），藤蔓固定端 **0**。
- 真实布局集成渲染（24 面墙 + 44 件植物）三个机位。

**v2 仍存 2 个像素差异**（N4）：定位在窗框边缘。窗墙 5m、玻璃 4.4m，
留给墙垛的只有 0.15m；藤蔓本来就贴墙外侧盘绕（静止时已与墙体重叠），
叶子横摆掠过窄墙垛属正确表现，量级是抗锯齿边缘（max 22/255）。

**踩坑记录（v2 新增）**：
- 静态共享材质必须在用例之间复位。第一版调幅脚本把 `sway_amplitude` 设 0 后没还原，
  下一个用例拿到同一份材质，`amplitude=0`，直接误判成「藤蔓不动」。
- 几何穿墙判据不能把整件 AABB 一起平移，否则不动的箱体也算进扫掠体积
  （误报「花箱新增重叠 0.74m³」）。必须先按 `foliage_base_y` 切出「会动的那部分」。

## 改动清单

**新增**

| 文件 | 作用 |
|---|---|
| `src/world3d/foliage_wind.gdshader` | 顶点位移风摆；不动材质表现（albedo/metallic/roughness 全从原材质读入） |
| `src/world3d/PlantSway3D.gd` | 挂 prefab 根；换 surface 材质、分档缓存、单时钟源 |
| `tests/verification/verify_rooftop_plant_sway.gd` | 44 件布局级验收（覆盖/共用/无新光源/颜色/时钟） |

**修改**（只加 3~5 行 `script` + 参数，未动节点结构与元数据）

```
assets/art/environments/tower_zones/rooftop/runtime/plant_large.tscn
assets/art/environments/tower_zones/rooftop/runtime/plant_small.tscn
assets/art/environments/tower_zones/rooftop/runtime/flowerbox.tscn
assets/art/environments/tower_zones/rooftop/runtime/ivy.tscn
assets/art/environments/tower_zones/rooftop/runtime/parapet_ivy.tscn
```

未改：`TowerFloorStage3D.gd`、`data/layouts/rooftop_100f_decorated_layout.json`、
任何 `.blend` / `.glb` / `.import`、碰撞、玩法光、存档。

## 实现要点（三条实测约束）

1. **花盆与叶片共用 surface** ⇒ 按 prefab 指定 `foliage_base_y`
   （large 1.15 / small 0.65 / flowerbox 1.15 / ivy 3.80 / parapet_ivy 2.01）。
   默认 0 会让整只花盆跟着摆。
2. **金属骨架必须一起摆** ⇒ 两张色盘面都套同一 shader，各用自己的材质参数。
   只摆叶片会让叶子脱离枝干。
3. **藤蔓顶部固定、且不能沿风向平移** ⇒ `sway_from_top` 反转权重；
   `wall_mounted` 改走本地 z 的离墙扑动 + `sign(z)`，否则叶片顺墙横滑并推进墙里。

## 验收

真渲染（Forward+，RTX 4060 Ti）：

| 项 | 结果 |
|---|---|
| 44 件 × 2 面 = 88 面替换，漏换 0 | ✅ |
| 共享材质实例数 | 10 |
| 新增 Light3D | 0（场景光源数 1，只有太阳） |
| 冻结风摆 vs 原始 prefab 逐像素 | **max=0，差异 0 点** |
| 摆动前后冠部差异 | 0.56%~3.42%（五类） |
| 盆体区域摆动差异 | 仅叶影边缘细线，盆体本体 0 实心差 |
| 时钟推进 | 0.980 → 1.484（0.5s 内） |

`godot --path . --script res://tests/verification/verify_rooftop_plant_sway.gd` → exit 0；
`--headless` → exit 2（明确「视觉对照未执行」，不代签）。

## 踩过的坑（留给以后）

1. **`source_color` 采样器**：不写 hint，色盘按线性解读，花盆 `(123,64,25)` 变 `(166,119,64)`。
2. **`albedo_tint` 不能二次 sRGB→linear**：采样器已解码，再转一次整株暗 12%。
3. **顶点函数里不能 `return`**（Godot 4.6）：报「Using 'return' in the 'vertex' processor is incorrect」。
4. **验证脚手架要保光**：对照帧把 `Light3D` 一起 free 掉，第二遍只剩环境光，
   会误判成「着色器改坏了颜色」（当时 max=123 / 5001 点）。
5. **冻结必须遍历场景，不能读静态缓存**：缓存可能漏掉本次新建的档，
   且金属/叶片是两份材质，只冻一份会让另一半继续摆。
6. **静态变量类型推断**：`var x := _ticker.get_ref()` 在 warning-as-error 的工程里会直接编译失败，
   要写 `var x: Object = ...`。

## 遗留（本阶段未做）

- 基地 4 件植物（`east_plant_group` 3 株 + `loft_hanging_plant`）未挂脚本 ——
  它们的顶点是世界坐标烘焙，需要单独测 `foliage_base_y` 语义（局部 y 仍是 0 起算，
  但 `foliage_span` 要用世界高度）。留到 P2 第二阶段。
- 「玩家跑过带一下植物」（`push` 项）未做。
- 切换画质档关闭 `ambient_motion` 的开关未做（当前常开，代价已接近 0）。
