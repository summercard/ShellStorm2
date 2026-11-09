# 1955 准星↔弹道对齐 + 弹体碰撞随视觉放大

## 业主两条口述

1. 「子弹的飞行轨迹和准星不对，会偏差。可能是因为准星在地上的原因」。
2. 「很多子弹视觉放大了 1.5 倍 / 两倍，但碰撞检测没放大 ⇒ 容易穿过去 / 打不到。
   **不是把视觉缩小，是把碰撞体也一起放大**」。

两条同根：看到的几何 ≠ 判定的几何。

## 一、准星 ↔ 弹道

### 根因（实测）

准星 = 射线与 `Plane(UP, 脚底 + 0.035)` 的交点（几乎贴地）；子弹从枪口（基准体型实测离地
**0.749m**）水平飞。两条线永不共线。

1080p / FOV 43 / 相机 (0,17.5,13) 俯 52° 实测偏差：近距斜向 **44px**、正前 7.2m **21px**。
44px ≈ 半个僵尸高。

### 改法

`Player3D.AIM_TARGET_HEIGHT = 0.75`（枪口实测高度取整）：
- 准星平面从「脚底+0.035」抬到「脚底+0.75」（鼠标/摇杆两条路径同高）
- 弹道方向改由 `_ballistic_direction(flat, 准星点)` 解算 = **枪口 → 准星**；自动射击走同一函数
- 近身 0.6m 内退回水平，避免 `normalized()` 放大噪声
- `aim_direction` 的水平语义 / 面朝向 / 伤害 / 射程 / 弹药全不变

**试错记录**：先试「方向仍取 aim_direction、只抬准星」⇒ 高差归零但横向残差 15px（枪口在角色
右前 0.7m）；再试「枪口→准星」⇒ 屏幕归零、但近距（<3m）大斜向会与枪管差 14°。最终保留
「枪口→准星 + 0.6m 退化」，因为业主首要诉求是「所见即所中」。

## 二、碰撞随视觉放大

`Projectile3D._collision_scale_factor()` 改为直接复用 `_visual_scale_factor()`
（原 2026-10-14 为守「纯视觉」把枪身档位剥出碰撞）。判定球 `0.12 ×` 视觉倍率：

| 来源 | 半径 |
|---|---|
| 中性 | 0.120 |
| 手枪 ×1.8 | 0.216 |
| 霰弹 ×2.0 | 0.240 |
| 榴弹/气球 ×1.55 | 0.186 |
| 命运 ×2 / 敌弹 ×2 | 0.240 |

代价：霰弹 5 发判定面 5×0.045㎡ → 5×0.181㎡。要回调只动 `shotgun.scale`（视觉+判定一起动）。

## 验收

| 用例 | 结果 |
|---|---|
| `verify_bullet_aim_alignment`（新增，20 samples） | OK |
| `verify_bullet_vfx_profiles`（碰撞断言反转） | OK，samples=70 |
| `verify_player3d_firing_motion` | OK，checks=376 |
| `verify_tower_descent_flow` | exit 0（已迁移，准星断言属死代码同步） |
| `check_documentation_contracts.py` | feature traceability 红项已消，仅剩既有 broken link + openpyxl 缺失 |

三个用例均 0 个 `SCRIPT ERROR` / `Parse Error`。

## 坑

- **反向对照的阈值要看实测**：同一「贴地准星 + 水平弹道」在正前 3.2m 只有 21px、近距斜向才有 44px。
  先按 44px 写成 >30 阈值，实测直接红 —— 阈值必须按所选测点取。
- **`Signal.connect()` 返回 Error 不是 Callable**（Godot 4）：`var c := sig.connect(fn)` 后
  `disconnect(c)` 会 Parse Error「argument 1 should be Callable but is int」。要先把 lambda 存成变量。
- 准星抬高后 `verify_tower_descent_flow` 那条 `+0.035` 断言要改读常量，直接硬编码新值会让
  下一次调高度时静默失效。

## 遗留

1. `AIM_TARGET_HEIGHT` 是常量，调试体型 10%~300% 下枪口会按比例变，准星仍 0.75 —— 常规体验无影响。
2. **未做真渲染主观验收**：像素差是 `unproject_position` 的几何量，准星从贴地光环变成悬空环的观感要真机看。
3. 敌弹判定球随 `visual_scale` 一起放大到 0.24，可躲性下降；按统一口径处理，未给敌弹豁免。

记录：`docs/v0.1/development/2026-11-09_aim_ballistic_alignment.md`
