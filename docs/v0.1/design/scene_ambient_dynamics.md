# 99F 基地 / 100F 天台 环境动态元素方案（提案·未冻结）

功能归属：`WORLD-AMBIENT-DYNAMICS`（新，待入 `MODULE_INDEX`）。工程版本 0.1.0。
状态：**提案**——只定方案与数值，不动工程。所有改动均落在 Godot 侧（脚本 / TSCN / Shader），
不修改任何 `.blend`、`.glb`、不重新导入、不写存档。

来源：业主 2026-10-17「场景动态元素较少，显得呆板」；聚焦 99F 自发光灯具、天台植物、云，并补齐补充项。

---

## 0. 结论先行

四步走，前两步吃掉 80% 的「呆板感」，且都接近零性能代价：

| 阶段 | 内容 | 视觉收益 | 性能代价 | 风险 |
|---|---|---|---|---|
| P1 | 灯具呼吸 / 故障闪烁 / 霓虹抖动 | 高 | ≈0（只改已有材质的 uniform） | 低 |
| P2 | 植物风摆（顶点着色器） | 高 | 0 CPU，片元零增量 | 低 |
| P3 | 云：小云提速 + 云影压日光 | 中 | ≈0 | 中（云影影响全场亮度） |
| P4 | 浮尘 / 风带 / 通风口气流 / 窗外鸟影 | 中高 | <0.3ms | 低 |

**不建议做的**（见 §6）：把 `Environment` 改成 Sky、给每盏闪烁灯新增真实光源、
整体动画 155 个自发光材质、旋转植物节点。

---

## 1. 现状盘点（实测，非估计）

用只读探针 `_scratch/probe_base_ambient.gd`（headless 4.6.3）实测基地美术层：

| 项 | 实测值 | 含义 |
|---|---|---|
| `MeshInstance3D` 总数 | 692 | — |
| 运行期被接管的自发光材质 | **155** | `BaseFixtureGlow3D` 逐个 duplicate 后提亮到 HDR 2.35 |
| 其中「灯具级」材质 | 8 | 由 9 条 `FIXTURE_PROFILES` 匹配出来 |
| `OmniLight3D` 总数 | 11 | 8 盏代码补光（energy 2.40 / range 3.8）+ 3 盏手摆美术灯（energy 0.32~0.65） |
| 基地植物 | 3 株 + 1 处吊挂 | 东面植物组 3 个独立 mesh（y 0.13~2.45）；二楼吊挂 2 surface |
| 天台植物 | **44 件** | plant_large 6 / plant_small 6 / flowerbox 8 / ivy 16 / parapet_ivy 8 |
| 天台植物来源 | `data/layouts/rooftop_100f_decorated_layout.json` | 运行期由 `TowerFloorStage3D` 逐件实例化，20 件带碰撞代理 |
| 云 | 体积云海 + 24 块小云 | `flow_time` 每帧推进；风速 `(0.18, ·, -0.11) m/s` |
| 天空 | `BG_COLOR` 纯色 | 无 sky，无天空盒 |
| 层高 | 12.0m | 100F=0 / 99F=-12 / 98F=-24；云顶 = -13.5，低于 99F 地面 1.5m |

### 诊断：为什么「呆板」

不是缺动态系统，而是四条：

1. **唯一的一段动态只存在于开关那 5 秒。** `play_turn_on_sequence()` 播完就把 155 个材质
   钉死在原值，之后全场零变化。
2. **植物的顶点是刚性的。** GLB 里叶片是一整块网格，没有骨骼、没有 morph，Godot 侧也没有
   任何风摆；44 件天台植物等于 44 个雕塑。
3. **云在 145m 视距下几乎静止。** 0.18 m/s 的世界平移，在 99F 窗内 8 秒只走 1.4m，
   而云的海面在 13.5m 之下，投影位移更小 —— 玩家读到的就是"贴图"。
4. **没有空气介质。** 静物、镜头、光源之间没有浮尘、风带、气流把三者连起来，
   所以即使有局部动画，整体仍像模型展示台。

现有「活物」先例（可直接复用其生命周期口径）：`VfxEnvBirdsFlyby3D`（12s 演出 + 20s 静默，
隐藏期重置）、`RooftopGroundBirdFlock`（100F 落地走动）。

---

## 2. 设计原则（先立规矩，再谈效果）

1. **只动 Godot 侧。** 新增脚本、新增 Shader、改 TSCN 引用、改代码里喂给 Shader 的参数。
   不碰 `.blend` / `.glb` / 不重新导入。
2. **不参与玩法。** 所有动态只作用于 `BaseMaterial3D.emission_energy_multiplier`、
   普通 `OmniLight3D`（**不是** `WastelandLight3D`）、Shader 顶点位移、`GPUParticles3D`。
   `EnemyIllumination3D` 只认 `WastelandLight3D`，`PlayerVision3D` 只看可见性 ⇒ 两者都不受影响。
3. **暂停即冻结。** 所有时钟走 `_process(delta)` 累加，不走 Shader 的 `TIME`
   （`TIME` 在暂停时仍推进）。与 `VfxCloudSea3D` 的现有口径一致。
4. **画质可关。** 复用现有 `GraphicsSettingsManager` 的 `scene_particles` 键管 P4；
   新增 `ambient_motion` 键管 P1–P3。关掉后逐像素回到当前基线。
5. **确定性。** 所有随机（故障时刻、相位）由固定种子 + 实例名哈希生成，
   同场景同帧号必然同结果，可写断言。
6. **不新建光源。** Forward+ 下每盏灯都要过体积雾与阴影，闪烁靠"改已有灯的能量"实现，
   不 `add_child` 新灯。
7. **导入节点属性覆盖不可靠 ⇒ 一律用代码改写。** 已知坑（2026-10-12 实测）：
   对导入 GLB 内部节点写属性覆盖，导出转换会静默丢弃。因此材质替换必须走
   `MeshInstance3D.set_surface_override_material()` 这类运行期调用，不写进 `.tscn` 覆盖。

---

## 3. P1 · 99F 自发光灯具

### 3.1 目标

把「开关那 5 秒」扩成「一直有生命」，但**不抢戏**：玩家不盯着看不会注意，
一停下来看就觉得灯在呼吸。

### 3.2 三层叠加（同一处合成，永不互相覆盖）

当前 `BaseFixtureGlow3D` 有三处会写 `emission_energy_multiplier`：
`set_presentation_lighting_enabled()`（0 或原值）、`_set_material_energy_range()`（启动分批）、
以及 `_start_authored_art_light_delay()`（只动灯不动材质）。新增一层后必须收敛成**唯一写入口**：

```
energy_i(t) = base_i · seq_i(t) · motion_i(t)
```

- `base_i`：`_emission_energy_by_material` 已存的原始值（不动）。
- `seq_i`：启动序列的 0 / 0.16 / 1.0（现有）。
- `motion_i`：本方案新增的呼吸 × 故障包络。

改造点：把现有 3 处直接写 `material.emission_energy_multiplier` 改成写
`_seq_factor[id]`，再统一由 `_apply_energy(id)` 合成。
补光 `OmniLight3D.light_energy` 同样乘 `motion_i`（否则"灯在闪、地上光不动"，一眼假）。

> 也可以做成独立节点、靠 `process_priority` 抢后者，但那是"最后写入者赢"的隐式契约，
> 序列与呼吸同时触发时必出竞态。**推荐改控制器本体**，代价约 60 行。

### 3.3 呼吸（所有灯具）

```
ω_i  = 2π / T_i
B_i(t) = 1 + A_i · [ 0.62·sin(ω_i·t + φ_i) + 0.38·sin(0.41·ω_i·t + 1.7·φ_i) ]
T_i  = 4.8 + 2.4·hash01(fixture_name)          # 4.8 ~ 7.2 s
φ_i  = 2π·hash01(fixture_name + "_phase")
A_i  = 见表
```

双频叠加是为了避免"心电图式"的规则正弦；主频 1/5s、副频 1/12s，
肉眼读到的是"亮度在缓慢起伏"，不是"在闪"。

| 灯具 | 角色 | `A_i` | `T_i` | 附加 |
|---|---|---|---|---|
| BASE_CAMP 霓虹标识 | 招牌 | 0.08 | 5.1 | 霓虹抖动 |
| 二楼 GOOD_VIBES 霓虹 | 招牌 | 0.08 | 6.3 | 霓虹抖动 |
| 楼梯墙 STAY_CURIOUS 标识 | 招牌 | 0.07 | 5.7 | 霓虹抖动 |
| 33_暖橙床头灯 | 生活 | 0.05 | 7.2 | — |
| 梯下壁灯生活点缀 | 生活 | 0.05 | 6.6 | — |
| 84_东面圆形工业吊灯 | 工业 | 0.035 | 4.9 | 故障 |
| 61_仓库防爆吊灯组 | 工业 | 0.035 | 5.4 | 故障 |
| 62_主通道应急灯组 | 应急 | 0.045 | 3.9 | 故障 |
| 50_二楼分层照明支持 | 环境 | 0.03 | 7.8 | 无补光，只改材质 |

约束：`A_i ≤ 0.08`。超过 10% 的调制在暗部会被读成"闪烁"而不是"呼吸"。

### 3.4 故障闪烁（3 盏，泊松过程）

每帧判定，不是定时器：

```
p_i(dt) = 1 - exp(-dt / T_mean_i)
T_mean: 61→22s, 62→31s, 84→26s
```

事件包络（总时长 240ms，`τ` 为事件内时间）：

| τ | 系数 |
|---|---|
| 0 | 1.00 |
| 45ms | 0.18 |
| 85ms | 0.85 |
| 120ms | 0.12 |
| 170ms | 1.00（结束） |

硬约束（防频闪 / 防癫痫）：

- 单灯 8s 内最多 1 次；
- 全场任意两盏灯的故障起始间隔 ≥ 1.5s；
- 最低系数 0.12（不归零，保留灯具轮廓，避免"黑屏跳变"）；
- 单次事件内亮度方向变化 ≤ 3 次 ⇒ 峰值 12.5 次/秒，但每盏灯每秒最多触发 0.125 次，
  实际观感是"偶发跳一下"。

### 3.5 霓虹抖动（3 块招牌）

```
buzz(t) = 1 - 0.28 · step( value_noise(13·t + φ_i), 0.82 )   # 约 18% 时间处于掉电
shimmer(t) = 1 + 0.04 · sin(2π·3.1·t + φ_i)
motion = B_i(t) · buzz(t) · shimmer(t)
```

`value_noise` 用一维哈希 + smoothstep 插值，周期约 0.35s，读作"老霓虹管的不稳定"，
区别于工业灯的"啪一下灭"。

### 3.6 屏幕 / 面板扫描（可选，v2）

只对 4~6 个明确的终端面（不是全部 147 个微光面）：把该 surface 的材质换成
`ShaderMaterial`，复刻色盘查色 + 叠加一条竖直滚动亮带：

```
band = smoothstep(0.0, 0.06, 0.06 - abs(fract(uv.y*2.0 - t*0.18) - 0.5))  # 约 5.5s 扫一遍
emission *= 1.0 + 0.35 · band
```

风险：色盘材质是 `TEXTURE_FILTER_NEAREST` + `EMISSION_OP_MULTIPLY` + 无 repeat，
换 Shader 必须逐条复刻，否则颜色会变。**建议放到 P1 之后再评估**，不进首批。

---

## 4. P2 · 植物风摆 [已实现 2026-10-17]

### 4.1 目标

天台 44 件植物 + 基地 4 件植物全部有风，且**盆不动、枝叶动**。

### 4.2 关键事实（实测，决定了实现方式）

| 资产 | 顶点坐标系 | 能否旋转节点 |
|---|---|---|
| 基地 `east_plant_group`（3 株） | **世界坐标烘焙**，节点 transform 为原点 | ❌ 旋转 = 绕世界原点甩飞 |
| 基地 `loft_hanging_plant` | 同上 | ❌ |
| 天台 5 种植物 prefab | **本地原点居中**，node transform 由 JSON 摆位 | ⚠️ 可转，但盆会跟着摆 |

⇒ 统一走**顶点位移**，不用节点旋转。

### 4.3 三条不能省的约束（都由实测逼出来）

**① 花盆与叶片共用同一个 surface。**
原始 GLB 只有两张面：「`01_精工金属_紫色骨架`」与「`02_细腻哑光_青绿大面`」。
按 5cm 分箱实测顶点：

| 资产 | 盆/箱体 | 枝叶起点 | 枝叶顶 |
|---|---|---|---|
| plant_large | 0 ~ 1.10（盆顶金属环 1.15） | 1.15 | 2.77 |
| plant_small | 0 ~ 0.65 | 0.85 | 1.50 |
| flowerbox | 0 ~ 1.10（金属绑带最低 0.08，故不能用金属底） | 1.15 | 2.13 |
| ivy | 无盆，整片贴墙 | 0 | 3.80 |
| parapet_ivy | 无盆，整片挂墙 | 0 | 2.01 |

⇒ 必须有 `foliage_base_y`，且**按 prefab 逐个指定**，不能默认 0。默认 0 会让整只花盆跟着摆。

**② 金属骨架必须一起摆。**
只摆哑光叶片的话，3.5cm 的叶片位移会让叶子脱离枝干（4m 尺度肉眼可见）。
⇒ 两张面都套同一个 shader，各自保留自己的 albedo / metallic / roughness，表现不变。

**③ 藤蔓的固定端在上，且位移方向要选对。**
`ivy` / `parapet_ivy` 是顶部固定在墙上、向下垂挂 ⇒ 权重方向要反过来（`sway_from_top`）。
位移方向踩过一次坑：初版只做本地 z 的离墙扑动（理由是「横向会让叶片顺墙滑动」），
结果**正面完全看不出在动** —— 墙面在 x-y 平面，z 方向位移在该视角下没有透视变化。
现改为**横向主导（本地 x）+ 离墙扑动 0.5 倍**：横向不穿墙（墙厚在 z 方向），
且正面可见；离墙分量保留起落感，不会像整块贴图平移。

### 4.4 算法（已实现 v2）

```
h     = clamp((VERTEX.y - foliage_base_y) / foliage_span, 0, 1)   # 向下垂时取 1-h
w     = pow(h, 1.5)
phase = dot(world_xz, vec2(0.31,0.47)) + dot(local_xz, vec2(0.21,0.33))
s     = 0.72·sin(1.55τ + phase) + 0.28·sin(2.65τ + 1.7phase)      # 周期 ≈ 4.1s
G     = 0.62 + 0.38·sin(0.21τ + 0.13phase)                        # 阵风包络 0.24~1.0

offset = A · w · G · s
  ├ 盆栽/花箱：VERTEX.xz += normalize(wind_dir) · offset   （wind_dir 与云海同向）
  └ 藤蔓：    VERTEX.x += sign(wind_dir.x) · offset        （沿墙面横向，正面可见）
              VERTEX.z += sign(VERTEX.z) · offset · 0.5    （离墙扑动，给起落）
```

| 类型 | `A` | `foliage_base_y` | 方向 | 典型位移 / 最坏 |
|---|---|---|---|---|
| plant_large | 0.120 m | 1.15 | 向上长 | 5.4cm / 12.0cm |
| plant_small | 0.120 m | 0.65 | 向上长 | 5.4cm / 12.0cm |
| flowerbox | 0.120 m | 1.15 | 向上长 | 5.4cm / 12.0cm |
| ivy | 0.090 m | 3.80 | 顶部固定下垂（横向扑动） | 4.0cm / 9.0cm |
| parapet_ivy | 0.090 m | 2.01 | 顶部固定下垂（横向扑动） | 4.0cm / 9.0cm |

幅度演进（业主两轮反馈）：

| 日期 | 盆栽 | 藤蔓 | 反馈 |
|---|---|---|---|
| 2026-10-17 | 0.035 | 0.020 | 「轻微晃动」初版 |
| 2026-10-18 | **0.120** | **0.090** | 「幅度再大一些，不够明显」「藤蔓也要动」 |

同时把权重指数从 1.8 降到 1.5：指数过高会把位移全挤到尖端，中段叶片几乎不动，
读起来像只有最上面几片在抖；1.5 让整层枝叶一起走，根部仍是 0。

**藤蔓「不动」的真因**：初版只做本地 z 的离墙扑动。墙面在 x-y 平面，
z 位移在正面视角下几乎没有透视变化，等于看不出来。改为横向主导后，
正面帧差从 1.8% 升到 13.3%（`outputs/rooftop_plant_sway_v002/compare_ivy_front.png`）。

### 4.5 落地方式（未改核心代码、未改 Blender/GLB）

`PlantSway3D.gd` 挂在 5 个天台 prefab 的根节点上，`_ready()` 遍历子树，
把色盘角色的 surface 换成共享 `ShaderMaterial`（`src/world3d/foliage_wind.gdshader`）。

```
assets/art/environments/tower_zones/rooftop/runtime/plant_large.tscn     foliage_base_y=1.15
assets/art/environments/tower_zones/rooftop/runtime/plant_small.tscn     foliage_base_y=0.65
assets/art/environments/tower_zones/rooftop/runtime/flowerbox.tscn       foliage_base_y=1.15
assets/art/environments/tower_zones/rooftop/runtime/ivy.tscn             base=3.80 sway_from_top wall_mounted
assets/art/environments/tower_zones/rooftop/runtime/parapet_ivy.tscn     base=2.01 sway_from_top wall_mounted
```

`TowerFloorStage3D.ROOFTOP_DECOR_SCENES` 本来就按 slug 取这 5 个 prefab ⇒
**不需要改 `TowerFloorStage3D.gd`，也不需要改 JSON 布局**。已用
`ROOFTOP_DECOR_SCENES` 常量表反查验证（5/5 命中，参数一致）。

### 4.6 颜色逐像素不变（两条坑）

换 shader 后必须与内建材质**逐像素相同**，为此踩了两个坑：

1. **色盘采样器要带 `source_color`**。不写这个 hint，纹理会按线性解读，
   暗通道被抬亮（实测花盆 RGB 从 `(123,64,25)` 变 `(166,119,64)`）。
2. **`albedo_tint` 必须传 `albedo_color` 原值**。采样器已经做了 sRGB 解码后，
   若再手动 `srgb_to_linear()` 会多转一次，整株偏暗约 12%（实测 108 vs 123）。

修正后实测：44 件天台植物冻结风摆 vs 原始 GLB，**max=0，差异像素 0**。

### 4.7 性能

- 44 件实例共用 **10 份** `ShaderMaterial`（按「材质角色 × 固定端 × 区间 × 方向」分档）。
- 顶点总数 < 3 万，顶点位移是 2 次 `sin` + 1 次 `sin` 包络 ⇒ CPU 0。
- 只有一个实例 `set_process(true)` 当时钟源，每帧写 10 次 `wind_time`。
- 时钟源离场（换 prefab / 场景重载）时把时钟移交下一个存活实例 ——
  否则其余实例早就在 `_ready` 里 `set_process(false)`，整片天台会停在最后一帧。
- 未新增任何 `Light3D`（实测场景内光源数 = 1，只有太阳）。

### 4.8 验收

`tests/verification/verify_rooftop_plant_sway.gd`（真渲染，Forward+）：

| 项 | 判据 | 实测 |
|---|---|---|
| N1 覆盖 | 44 件植物 + 24 面房间墙；88 面全替换，0 漏换 | 88 / 0 ✅ |
| N2 材质共用 | 实例数远小于面数 | 10 ✅ |
| N3 无新增光源 | Light3D 计数 = 1 | 1 ✅ |
| N4 颜色不变 | 冻结后 vs 原始 prefab 逐像素 | max=22，**2 点**（见下）✅ |
| N5 时钟推进 | 0.5s 后 clock 递增 | 0.940→1.457 ✅ |
| N6 穿墙 | 最坏摆幅下与墙体新增体积重叠 | 0 ✅ |

**N4 那 2 个像素**：噪声基线（同静止状态连拍两帧）差值为 **0**，所以不是 TAA 抖动。
定位在**窗框边缘** —— 窗墙 5m 宽、玻璃 4.4m，留给墙垛的只有 0.15m；
藤蔓本来就贴在墙外侧盘绕（静止时已与墙体重叠），叶子横摆掠过这块窄墙垛属正确表现，
不是穿模。量级是抗锯齿边缘（max 22/255）。

**N6 的已知盲区**：沿墙面的横向摆动。植物整体落在墙的 x 范围之内时（藤蔓就是：
4.26m 宽落在 5m 墙里），横向多扫 7.6cm 不改变「与墙 AABB 的相交体积」，判据会报 0。
这种情形只能靠像素级证据（即上面那 2 点）兜底。

真渲染另有单类对照与连拍序列（`outputs/rooftop_plant_sway_v002/`）：

| 资产 | 摆动前后帧差 | 冻结 vs 原始 |
|---|---|---|
| plant_large | 0.89% | max=0 |
| plant_small | 2.63% | max=0 |
| flowerbox | 1.61% | max=0 |
| ivy（3/4 侧） | 7.44% | max=0 |
| ivy（正面平视） | **13.27%** | max=0 |
| parapet_ivy（正面） | 6.34% | max=27，1 点 |

17 帧 × 0.25s 连拍（`seq/strip_large.png`）：冠部逐帧偏移清晰，盆体区域 17 帧内
最大差 **1**（浮点量级）、藤蔓固定端 **0**。

headless 跑到 N4 会以 **exit 2** 明确报「视觉对照未执行」，不代签。

---

## 5. P3 · 云

云已经会动，问题是"动得太慢、且只有这一种动法"。两处改动，都不动 Shader 源码。

### 5.1 小云单独提速（零 Shader 改动）

`VfxCloudSea3D._sync_dynamic_materials()` 是**逐 volume 各自 set 参数**的，
且每个 volume 的 material 在 `_ready()` 里已 duplicate 过 ⇒ 可以给 `AirWisps` 喂
不同的时钟：

```
Ocean/薄雾：flow_time = t
AirWisps  ：flow_time = t · 1.8
```

24 块小云因此比云海快 80%，近景有明确的相对位移，远处仍稳。
可选再给 3 块"近景小云"`·2.4`。

### 5.2 云影压日光（最能立刻解决"贴图感"）

`TowerAtmosphere3D._process()` 已有每帧逻辑，加一个乘子：

```
E_sun(t) = E_solar · (1 - 0.10 · n(t))
n(t) = 0.62·noise(t/28) + 0.38·noise(t/11 + 7.3)      # 0~1
```

周期 28s / 11s 双八度 ⇒ 读作"云在天上慢慢过，太阳时明时暗"，
而不是"性能抖动"。幅度 ±10%，不改变色温。

风险与收口：

- `TowerAtmosphere3D.get_presentation_snapshot()["sun_energy"]` 会随之抖动 ⇒
  相关验收断言必须改成**区间断言**，不能等值。
- 必须只乘 `_sun.light_energy`，**不碰** `ambient_light_energy` 与 `_rooftop_sky_bounce`
  （那两处承担夜景保底）。
- 现存 `_sun.light_energy` 只在 `solar_state_changed` 里写（第 378 行），
  改为存 `_solar_sun_energy`、每帧合成，冲突面只有一处。

### 5.3 暂缓：天空穹顶 / 窗外云丝

- **天空穹顶**：`Environment` 现在是 `BG_COLOR` + 世界时间标定，
  云的 `daylight` 归一化也吃这套值。换成 Sky 会同时打乱日光、云色、雾色三处标定，
  收益（窗外的天空不再是纯色）不抵风险。**建议单独立项，不在本轮。**
- **窗外云丝（billboard）**：云海已经是 `depth_test_disabled` 的代理体积，
  再叠一层透明面片，排序与穿插的调试成本远高于收益。**暂缓。**

---

## 6. P4 · 补充项（我加的）

### 6.1 99F 室内浮尘（性价比最高的一项）

```
GPUParticles3D：220 粒，AABB 28×7×28，寿命 18~30s
速度：(0.02~0.06, 上浮) + 水平 0.03，受风 0.2
尺寸：1.2~3.0cm，alpha 0.04~0.10，additive，unshaded
```

一盏灯不够亮时灰尘看不见，灯一亮就在光柱里浮起来 —— 这是把"静物"和"光"连起来最便宜的手段。
1 个 draw call，只在 99F 可见时启用（用现有 `visible` 分层，不加逻辑）。

### 6.2 天台风带

60 片拉伸面片，长 6~14m、宽 0.05m，速度 1.8~3.2 m/s（与 §5.1 云速同向），
alpha 0.02~0.05，Y ∈ [0.2, 2.5]。作用不是"看见风"，而是让 §4 的植物摆动有因果 ——
玩家会读成"今天风大"，而不是"这棵树在抖"。

### 6.3 通风口气流

`hvac_vent` 2 台 + `hvac_small` 4 台，每台 20 粒向上 0.35 m/s、寿命 2.5s、alpha 0.03。
天台从"摆件"变成"有设备在运行的屋面"。

### 6.4 窗外鸟影

复用现有 `vfx_env_birds_flyby_root_top3d.tscn`，在 99F 窗外 80m 处加一条轨迹，
间隔 45s。零新资产，只加一个实例 + 2 个 export 参数。

### 6.5 通风机叶片旋转（**做不了，明确不列**）

实测 `env_rooftop_ref_hvac_vent_top3d.glb` / `hvac_small` 都是单个 `主体` 节点、
叶片与外壳合并在同一 mesh，没有独立可转节点。要做只能改 Blender 源 ⇒ 本轮排除。

---

## 7. 明确不做（附理由）

| 不做 | 理由 |
|---|---|
| 整体动画 155 个自发光材质 | 每帧 155 次 uniform 写入 + 画面到处在抖 = 噪声，不是生命感。只取 8 灯具 + ≤6 屏幕 |
| 给每盏闪烁灯新增真实 `OmniLight3D` | Forward+ 逐灯过体积雾，8 盏变 20 盏的代价远高于收益；改已有灯能量即可 |
| 旋转植物节点 | 基地植物顶点是世界坐标，旋转会绕世界原点甩飞；天台会连盆一起摆 |
| 改 `stylized_cloud.gdshader` | §5 的两项都能在 GD 侧喂参数实现，不必承担重验云海的风险 |
| 改 `Environment` 成 Sky | 打乱日光/云色/雾色三处标定（见 §5.3） |
| 碰 `.blend` / `.glb` / 重新导入 | 业主明确要求 |
| 碰存档、碰撞、`WastelandLight3D`、`PlayerVision3D` | 纯表现层，越界即事故 |

---

## 8. 验收方案

每条都要有"会失败的断言"，不能只靠截图看着像。

### 8.1 无头探针（headless 4.6.3）

1. **灯具曲线**：`t=0,2,4,6,8,10s` 采样 8 个灯具材质的 `emission_energy_multiplier`，
   与 §3.3 公式逐点比对，容差 ±1%（浮点）。
2. **故障约束**：模拟 300s，断言「单灯 8s 内 ≤1 次」「任意两灯起始间隔 ≥1.5s」
   「每个事件时长 ≤250ms」。
3. **植物命中率**：断言 44 + 4 件植物的绿色 surface **全部**被替换，
   金属/花盆 surface **全部未**被替换；替换后 `albedo` 采样值与替换前逐像素一致（颜色不变）。
4. **开关收口**：`set_presentation_lighting_enabled(false)` 后，
   所有 `motion_i` 参与的能量必须归零，不得有残留呼吸。
5. **无新增光源**：`find_children("*","Light3D")` 计数与基线 11 一致。

### 8.2 真渲染（必须 Forward+，不能用 headless 代签）

6. **同机位 0.4s 帧差**：99F 站桩固定机位拍两张。
   - 叶片区像素差 > 阈值（有动）
   - 花盆/金属区像素差 ≈ 0（盆没动）
   - 灯区亮度差 ∈ [1%, 10%]（在呼吸，但没在闪）
7. **暂停冻结**：暂停 3s，前后两帧像素差 = 0（含植物、灯、云、粒子）。
8. **开关回退**：`ambient_motion=false` + `scene_particles=false` 后，
   与改动前基线逐像素差 < 1%。

### 8.3 性能

9. 99F 站桩 60s，`high/balanced/low` 三档：
   - 灯 + 植物增量 < 0.3ms/帧
   - 浮尘 < 0.15ms/帧
   - 天台 44 件植物全开时，`low` 档不得跌破既有基线帧率

### 8.4 回归面

- `verify_outdoor_clouds`：云的 `flow_time`、`rejected_count`、`sea_count` 不得变化
  （§5.1 只改喂给 AirWisps 的系数，不改 volume 集合）。
- `audit_base99_v022_lighting`：导入灯光数仍为 0。
- 存档读写路径不涉及，但需确认启动序列时长仍为 4.2s、手摆灯延迟仍为 2.0s。

---

## 9. 落地清单（按阶段）

| 阶段 | 新增 | 修改 |
|---|---|---|
| P1 | `src/world3d/BaseLightMotion3D.gd`（或并入现控制器） | `src/world3d/BaseFixtureGlow3D.gd`（收敛能量写入口 + `_process`） |
| P2 | `src/world3d/PlantSway3D.gd`、`src/world3d/foliage_wind.gdshader` | 7 个植物 prefab 各加一行 `script` |
| P3 | — | `src/vfx/VfxCloudSea3D.gd`（AirWisps 时钟系数）、`src/world3d/TowerAtmosphere3D.gd`（日光乘子） |
| P4 | 粒子用 `.tres` ×3（浮尘/风带/气流） | `zone_base.tscn`（浮尘）、`TowerDescent3D.tscn`（风带 + 鸟影）、`GraphicsSettingsManager`（`ambient_motion` 键） |

无新增资产、无重新导入、无 XLSX 变更。

---

## 10. 待业主拍板的 5 个点

1. **灯呼吸幅度**：主照明 3.5%（克制，我推荐）/ 6%（更明显）？霓虹 8% 是否接受？
2. **云影压日光 ±10%** 是否接受？它会让全场亮度缓慢起伏，也会让 `sun_energy` 读数抖动。
3. **浮尘**常开，还是只在 99F 室内可见时开？
4. **天台风带**要不要？它不显眼，但会把"植物在抖"翻译成"今天有风"。
5. **故障闪烁**只给 3 盏工业/应急灯，还是也要给一块霓虹招牌做"整块掉电 0.6s"的桥段？

拍板后我按 P1 → P2 → P3 → P4 顺序落，每阶段单独出验收证据，不一次性铺开。
