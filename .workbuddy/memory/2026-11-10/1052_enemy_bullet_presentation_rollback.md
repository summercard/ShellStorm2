# 1052 敌方子弹回退 3D 弹体，公告板保留且缩到 70%

## 业主口述

> 「回退到 3D 弹体，我印象中我只要求把接触体积和模型（被放大的）的体积做成一致，
> 没有要求做成公告板，总之公告板方式也保留吧。以后可供我选择，公告板的弹丸也太大了。先缩小到 70%。」

## 事实链（回答上一轮「什么时间改的」）

- 11-09 20:13:19 建 `BulletBillboardIcon3D.gd` → 20:13:46 `VfxBulletBody3D` 接入 →
  20:14:08 `VfxBulletVisual3D`（真正生效的路由）→ 20:19:43 shader 定稿。
- 触发是 11-09 19:5x 那句「准星重新设计…**敌方子弹也一样**」。
- git 只有 `d4cc5a21`（11-10 04:03 每日自动提交）—— 那天之前工作区没提交过，没有中间 diff 点。
  以后查这类"什么时候改的"，**先看文件 mtime**，别指望 git log。

## 改了什么

| # | 改动 | 文件 |
|---|---|---|
| ① | `ENEMY_BULLET_BILLBOARD := false` | `src/framework/GameDesignConfig.gd` |
| ② | `ENEMY_BULLET_ICON_SCALE := 0.70` | 同上 |
| ③ | `Projectile3D._billboard_override`（-1 跟总开关 / 0 强制 3D / 1 强制公告板），来源 `projectile_config["billboard"]`，池化逐发重置 | `src/combat3d/Projectile3D.gd` |
| ④ | 切换出口单点 `_hostile_billboard_enabled()` | 同上 |
| ⑤ | 图标尺寸乘倍率 + 快照 `icon_size_scale` | `src/vfx/BulletBillboardIcon3D.gd` |
| ⑥ | 两条路由 + `Projectile3D` 快照透出 `icon_size_scale` | `VfxBulletVisual3D/VfxBulletBody3D/Projectile3D` |
| ⑦ | 测试/探针显式传 `billboard: true` | `verify_crosshair_billboard.gd`、`_probe_billboard_icons.gd`、`_probe_billboard_shot.gd` |
| ⑧ | 新对照探针（3D vs 公告板 70% 同屏） | `tools/_probe_bullet_presentation_compare.gd/.tscn` |
| ⑨ | 子投射物（环形/地面爆散、子母弹）继承母弹形态 `_inherit_billboard()` | `src/combat3d/Projectile3D.gd` |

## 语义变化（记住）

11-09 契约「图标核心 == 判定球直径」，乘 0.70 后核心比判定球小 30%
⇒ **所见小于所中**：不会误导"打得到"，但会低估命中范围。判定球半径不动，有断言盯着。

## 验收

- `verify_crosshair_billboard` 31 → **37 samples** OK（新增三条缺省哨兵：缺省必须 3D / 弹体可见 / 图标不可见）
- `verify_bullet_vfx_profiles` 70 OK、`verify_bullet_aim_alignment` 20 OK、`verify_player3d_firing_motion` 376 OK
- `check_documentation_contracts.py` 无新增红项（14 条断链是 10-18/10-19 存量）
- `check_asset_runtime_naming.py` OK，欠账未增（289/13）
- 真机对照 `outputs/bullet_presentation_20261110/compare_3d_vs_billboard70.png`

## 遗留（已告知业主）

1. **公告板「看着大」的主因不是尺寸倍率，是外晕**：`halo_radius 0.50 / core_radius 0.30 = 1.67`，
   墨迹外沿比核心大 67%。再压 `ICON_SCALE` 会连"所见即所中"的比例一起压坏，
   要收观感应动 `halo_radius` 与外晕 alpha（0.42）。
2. 描边 `rim_half_width 0.012` 在 20px 屏幕上 < 1px，被 fwidth AA 吃掉 ⇒ 公告板没有实心轮廓。
3. `ICON_SCALE` 是全局常量，未接 `monster_rules` 按怪物配置（出口已备，只差 `Enemy3D._launch_projectile` 透传）。

## 文档

- 开发记录 `docs/v0.1/development/2026-11-10_enemy_bullet_presentation_rollback.md`（+ README 索引首条）
- 设计 `docs/v0.1/14.6_特效系统与制作规范.md` §3.8 改写为「3D 默认 / 公告板可选」+ 尺寸表
- `docs/v0.1/03_技术施工_玩家与操作.md` §4.4 门禁描述同步
- `feature_registry.json` WEAPON-COMBAT 加开发记录
