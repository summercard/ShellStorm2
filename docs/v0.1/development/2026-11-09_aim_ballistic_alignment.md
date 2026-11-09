# 2026-11-09 准星↔弹道对齐 + 弹体碰撞随视觉放大

## 业主口述

1. 「子弹的飞行轨迹和准星不对，会偏差。可能是因为准星在地上的原因，帮我想个办法进行调整。」
2. 「我的很多子弹的视觉被我放大了，有些是 1.5 倍，有些是两倍，但是它的这个碰撞检测没有放大，
   所以会导致子弹容易穿过去 / 打不到。不是把子弹视觉缩小，而是把子弹的碰撞体也一起放大了。」

两个现象同根：**「看到的」和「判定的」是两套几何**。准星贴地而子弹在枪口高度飞；弹体视觉放大
而判定球没放大。

## 一、准星 ↔ 弹道

### 根因（实测，不是推断）

`Player3D._update_aim_from_mouse()` 求射线与 `Plane(UP, 角色脚底 + 0.035)` 的交点当准星，
即准星几乎贴地；`aim_direction` 只取水平分量，子弹从 `_muzzle.global_position`（基准体型实测离地
**0.749m**）沿水平方向飞 —— 两条线永不共线。

1080p / 43° FOV / 相机 `(0, 17.5, 13)` 俯 52° 实测：

| 情形 | 屏幕上「弹道 vs 准星」偏差 |
|---|---|
| 近距斜向（约 3m） | **44px** |
| 正前 7.2m | 21px |

44px ≈ 半个僵尸的高度。这就是「打不准」的观感来源。

### 改动

真源单点：`Player3D.AIM_TARGET_HEIGHT = 0.75`（= 枪口实测高度取整）。

| 项 | 改前 | 改后 |
|---|---|---|
| 准星平面 | 角色脚底 + 0.035 | 角色脚底 + 0.75 |
| 鼠标准星位置 | 交点 + 0.035 | 交点（不偏移） |
| 摇杆准星位置 | `角色 + 方向 × 3.2 + UP×0.035` | 同距离 + `UP×AIM_TARGET_HEIGHT` |
| 弹道方向 | `aim_direction`（水平） | `(准星点 − 枪口).normalized()`，统一走 `_ballistic_direction()` |
| 自动射击 | 水平指向敌人 | 同一函数，目标点 = 敌人 XZ + `AIM_TARGET_HEIGHT` |

近身保护：枪口到目标点 < 0.6m 时退回水平方向，避免 `normalized()` 把毫米级噪声放大成侧向偏转。

`aim_direction` 的水平语义 / 面朝向 / 枪口起点 / 伤害 / 射程 / 弹药全部不变。

### 验收

新增 `verify_bullet_aim_alignment`（20 samples）：

- 准星平面高度 = 角色脚底 + `AIM_TARGET_HEIGHT`（走真实摇杆瞄准分支）
- 弹道穿准星：世界 < 1mm、1080p 屏幕 < 1px（三个典型落点）
- 解算方向的水平分量不得与瞄准方向反向
- 内建反向对照：贴地准星 + 水平弹道必须偏 > 15px（实测 21px）—— 证明判据量得到旧缺陷
- 碰撞半径七组（见下）

## 二、碰撞体随视觉放大

### 根因

`Projectile3D` 有两个出口：`_visual_scale_factor()`（弹种 × 命运 × 枪身档位 × 敌弹倍率）
与 `_collision_scale_factor()`（只含弹种 × 命运）。2026-10-14 为守「纯视觉」把枪身档位剥出碰撞，
结果手枪 ×1.8 / 霰弹 ×2.0 的弹体只有 0.12m 判定球（≈ 视觉直径的 40%）。

### 改动

`_collision_scale_factor()` 直接复用 `_visual_scale_factor()` —— 视觉多大，判定球就多大。

| 来源 | 视觉倍率 | 判定球半径（0.12 ×） |
|---|---|---|
| 中性档 | 1.00 | 0.120 |
| 手枪 | 1.80 | 0.216 |
| 霰弹 | 2.00 | 0.240 |
| 榴弹 | 1.55 | 0.186 |
| 气球弹 | 1.55 | 0.186 |
| 命运 ×2.0 | 2.00 | 0.240 |
| 敌弹 `visual_scale=2.0` | 2.00 | 0.240 |

已知代价：霰弹 5 发弹丸判定面 5×0.045㎡ → 5×0.181㎡。这是「所见即所中」的直接结果；
若实战过强，应调 `shotgun.scale`（视觉与判定一起动），不要单独把碰撞拆回去。

### 验收

`verify_bullet_vfx_profiles` 的旧断言（霰弹 `collision_radius` 必须恒为 0.12）反转为
`0.24`，并新增手枪 `0.216`；`verify_bullet_aim_alignment` 覆盖七组来源。

## 三、文件

- `src/player3d/Player3D.gd`：`AIM_TARGET_HEIGHT`、准星平面、`_ballistic_direction()`、自动射击
- `src/combat3d/WeaponModel3D.gd`：`muzzle_global_position()`
- `src/combat3d/Projectile3D.gd`：`_collision_scale_factor()` 与视觉同源 + 三处注释口径
- `tests/verification/verify_bullet_aim_alignment.{gd,tscn}`：新增
- `tests/verification/verify_bullet_vfx_profiles.gd`：碰撞断言反转
- `tests/verification/verify_tower_descent_flow.gd`：准星高度断言改读常量（该用例已迁移，属死代码同步）
- `tools/_probe_aim_trace.{gd,tscn}`：偏差量化探针（可复跑）
- 设计：`03_技术施工_玩家与操作.md` §4.3（新增）、`04_技术施工_战斗与局内成长.md` §6.1、
  `14.6_特效系统与制作规范.md` §3.7

## 四、验收结果

| 用例 | 结果 |
|---|---|
| `verify_bullet_aim_alignment` | `BULLET_AIM_ALIGNMENT_OK`（samples=20） |
| `verify_bullet_vfx_profiles` | `BULLET_VFX_PROFILES_OK`（samples=70） |
| `verify_crosshair_billboard` | `CROSSHAIR_BILLBOARD_OK`（samples=31） |
| `verify_tower_descent_flow` | exit 0（该用例已迁移到 arrival-gate 流程） |
| `check_documentation_contracts.py` | 无本次新增红项（既有 broken link 未变） |

## 四之二、第二轮：准星与敌方子弹改成公告板（同日）

业主：「准星重新设计，设计成准星的图标，一直面对摄像机的公告板。敌方子弹也一样」。

### 准星

| 项 | 改前 | 改后 |
|---|---|---|
| 形态 | `TorusMesh`（环）+ `CylinderMesh`（点）两个 3D 实体 | 单个 `QuadMesh` + SDF shader（外环 / 四向刻度 / 中心点） |
| 朝向 | 平躺在地面（未定向） | 基向量 = 相机 basis（俯仰分量完整保留） |
| 尺寸 | 固定世界尺寸（0.42m 外径） | 恒定屏幕占比 6.2%（1080p 可见 ≈48px） |
| 可见性 | 深度测试（会被角色/墙遮挡） | `depth_test_disabled`（永远看得见） |

真机实拍两轮调整：① 中心点 0.028 → 0.040（原尺寸在 1080p 只有 2px，像脏点）；② 占屏比 0.044 → 0.062（首版可见直径只有约 32px，读不出刻度）。

### 敌方子弹

共用节点 `BulletBillboardIcon3D`（`QuadMesh` + `enemy_bullet_icon.gdshader`），由 `Projectile3D` 按 `hostile` 下发 `billboard` 标志。玩家子弹保持 3D 弹体 + 尾迹。

⚠ **主战场是 `VfxBulletVisual3D`（通用弹体），不是 `VfxBulletBody3D`（八弹种）**：`Enemy3D._launch_projectile()` 不填 `visual_id` ⇒ 敌人子弹落到通用弹体 Prefab。首版只改了八弹种那个类，探针实测敌方子弹 `billboard=false` —— 改错地方了。现在两条路由共用一个节点，不会再漂。

图标核心直径 = 判定球直径（`CORE_UV_RADIUS = 0.30`，面片边长 = 直径 / 0.6），延续「所见即所中」。

### 两个实拍踩坑

1. **`ALBEDO` 超过 1 就被钳白**：首版 `glow 1.25 + 核心 0.9`，紫色弹核心实测 RGB ≈ (1.9, 1.46, 2.15)，三发不同弹色的敌弹在屏幕上全读成「白色圆点」。改为 `glow 0.95 + core_boost 0.18`，核心用 `core_whiteness 0.35` 与弹色混色。
2. **反算局部基必须用父节点基**：`self.global_transform.basis.inverse() × wanted` 里 `self` 的基已含本节点上一帧的旋转 ⇒ 算出 identity ⇒ 下一帧又被拉回，两帧一次来回振荡（实测朝向余弦卡在 cos45° ≈ 0.707 不动）。改用 `parent.global_transform.basis` 后为 1.0。

### 面数预算 +2

每发子弹新增 1 个图标 `QuadMesh` = 2 三角面（玩家子弹也建、只是隐藏，池化安全）。`verify_bullet_vfx_profiles` 的 `EXPECTED_TRIS` 全表 +2（44→46 等），仍在 100 面预算内。

### 真机证据

`outputs/crosshair_billboard/crosshair_billboard_preview.png` —— 三发不同弹色（红 / 紫 / 橙）可辨；准星环 + 四向刻度 + 中心点齐备；遮挡板测试确认准星绘制在前景之上。

## 五、遗留

1. **`AIM_TARGET_HEIGHT` 是常量**：调试体型（10%~300%）下枪口高度会按比例变，准星仍停在
   0.75m。常规体验不受影响；若要支持调试体型下的精确对齐，需要改成读 `visual_root` 的目标缩放。
2. 敌弹判定球随 `visual_scale` 放大到 0.24m 后，可躲性会下降（原来视觉大、判定小）。
   本轮按业主「碰撞体也一起放大」的统一口径处理，未单独给敌弹开豁免。
3. **准星恒在前景**：`depth_test_disabled` 让它也会画在墙前。这是 HUD 惯例的取舍（准星是
   「我在瞄哪」的指示器），但如果后面要做「准星被墙挡住 ⇒ 转为灰色/缩小」的表达，
   需要改成在脚本里做射线检测再传 shader 参数，而不是开回深度测试。
4. **敌方子弹图标不随距离缩小**：它按世界尺寸画（核心 = 判定球），所以远距离敌弹会变小。
   这与准星（屏幕恒定）口径不同 —— 准星是 HUD 指示器，敌弹是世界物体，两者不该统一。
