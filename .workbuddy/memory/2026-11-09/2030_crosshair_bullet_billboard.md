# 2030 准星图标化 + 敌方子弹 billboard

## 业主口述

「准星重新设计，设计成准星的图标，一直面对摄像机的公告板。敌方子弹也一样。」

## 一、准星：从 3D 实体 → 面向相机的图标

| 项 | 改前 | 改后 |
|---|---|---|
| 形态 | `TorusMesh`(环) + `CylinderMesh`(点) | 单个 `QuadMesh` + SDF shader |
| 构图 | 环 + 点 | 外环(0.205) + 四向刻度(0.255~0.355) + 中心点(0.040) |
| 朝向 | 平躺地面（未定向） | 基向量 = 相机 basis |
| 尺寸 | 固定世界 0.42m 外径 | 恒定屏幕占比 6.2%（1080p ≈48px） |
| 可见性 | 深度测试（会被角色/墙埋掉） | `depth_test_disabled` |

**为什么不用 `BaseMaterial3D.billboard_mode`**：Godot 的 billboard 只绕 Y 轴，本作相机俯视
52°，面片被压成 sin(52°)≈0.79 椭圆 —— 项目里 `RELOAD_RING` 和 `SpeechBubble3D` 都记过这坑。

**尺寸补偿**：`world = 屏高 × 0.062 × 2·d·tan(fov/2) / 屏高`，d 取**沿光轴深度**不是欧氏距离
（欧氏在偏轴时偏大 8%，16m 处 48px vs 目标 44.6px）。

## 二、敌方子弹：同一个共用节点

`src/vfx/BulletBillboardIcon3D.gd`（`QuadMesh` + `enemy_bullet_icon.gdshader`），
`Projectile3D._bullet_visual_context()["billboard"] = hostile` 下发。

⚠ **改对地方**：`Enemy3D._launch_projectile()` 不填 `visual_id` ⇒ 敌人子弹实际走
**通用弹体 `VfxBulletVisual3D`**，不是八弹种 `VfxBulletBody3D`。首版只改后者，探针实测
`billboard=false` —— 改错了。现在两处共用一个节点，靠节点复用防漂移。

核心直径严格 = 判定球直径（`CORE_UV_RADIUS=0.30` ⇒ 面片边长 = 直径/0.6），延续「所见即所中」。
玩家子弹保持 3D 弹体 + 尾迹（要表达「我的弹道往哪飞」，方向感是信息本身）。

## 三、四个实拍踩坑

1. **`ALBEDO` 超 1 就被钳白**：首版 `glow 1.25 + 核心 0.9 = 2.15×`，紫弹核心实测
   RGB≈(1.9,1.46,2.15) ⇒ 三发不同弹色在屏幕上全读成白点。改 `glow 0.95 + core_boost 0.18`，
   核心用 `core_whiteness 0.35` 与弹色**混色**而非纯白。
2. **反算局部基要用父节点基**：`self.global_transform.basis.inverse() × wanted` 里 self 已含
   本节点上一帧旋转 ⇒ 算出 identity ⇒ 下一帧又被拉回，两帧一次振荡，朝向余弦卡在
   cos45°≈0.707 不动。换 `parent.global_transform.basis` 后 1.0。
3. **钳制上限会吃掉恒定像素**：`AIM_CURSOR_MAX_WORLD_M=1.10` 在 16m 处把图标截成 32.8px
   （目标 44.6px）。深度测试已关，面片穿墙不再是顾虑 ⇒ 放宽到 2.5m。
4. **面片尺寸 ≠ 图标墨迹尺寸**：占屏比是**面片**口径，墨迹只铺到 0.355 UV（约 71%），
   写常量时两者要分清，否则「48px」实际只有 32px。

## 四、验收

| 用例 | 结果 |
|---|---|
| `verify_crosshair_billboard`（新增，31 samples） | OK |
| `verify_bullet_vfx_profiles`（面数全表 +2） | OK，samples=70 |
| `verify_bullet_aim_alignment` | OK，samples=20 |
| `verify_player3d_firing_motion` | OK，checks=376 |
| `check_documentation_contracts.py` | 无新增红项 |

四例均 0 个 `SCRIPT ERROR` / `Parse Error`。三组反向对照均精准变红：
① `billboard=false` → 「未开启 / 图标不可见 / 3D 弹体仍可见」三条；
② 准星退化成 Y-billboard → 「朝向余弦 0.6157 / 丢了俯仰分量」两条；
③ 去掉深度补偿 → 「近 44.8px / 远 48.0px」。

真机证据 `outputs/crosshair_billboard/crosshair_billboard_preview.png`：准星环+四刻度+中心点齐备、
圆形未压扁、绘制在遮挡板之上；三发敌弹（红/紫/橙）颜色可辨。

## 五、遗留

1. 准星恒在前景（`depth_test_disabled`），也会画在墙前。若要做「被墙挡住⇒变灰/缩小」，
   需脚本射线检测传 shader 参数，别开回深度测试。
2. 敌方子弹图标按**世界尺寸**画（核心=判定球），远距离会变小；准星是屏幕恒定。
   两者口径不该统一：准星是 HUD 指示器，敌弹是世界物体。
3. `AIM_TARGET_HEIGHT` 仍是常量，调试体型 10%~300% 下枪口按比例变、准星仍 0.75m。

记录：`docs/v0.1/development/2026-11-09_aim_ballistic_alignment.md`（§四之二）
设计：`03_技术施工_玩家与操作.md` §4.4、`14.6_特效系统与制作规范.md` §3.8
