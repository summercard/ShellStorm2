# 2026-11-10 敌方子弹回退 3D 弹体 + 公告板保留（70%）

业主原话：

> 「回退到 3D 弹体，我印象中我只要求把接触体积和模型（被放大的）的体积做成一致，
> 没有要求做成公告板，总之公告板方式也保留吧。以后可供我选择，公告板的弹丸也太大了。
> 先缩小到 70%。」

## 1. 为什么默认回退

2026-11-09 那轮把敌弹从 3D 棱柱换成面向相机的 `QuadMesh` 图标（见
[2026-11-09_aim_ballistic_alignment.md](2026-11-09_aim_ballistic_alignment.md) §四之二与
`.workbuddy/memory/2026-11-09/2030_crosshair_bullet_billboard.md`）。
业主本次澄清**原始诉求只有一条**：判定体积要跟被放大后的模型体积一致
（那是 11-09 同批的 `_collision_scale_factor()` 改动，与公告板无关）。
公告板不是他要的形态，故降级为「可选实现」。

⚠ 但**公告板不是错的方向**：52° 俯视下 3D 棱柱只剩「一根短棍的顶面」，暗场景读不出威胁 ——
这条理由仍成立，所以实现一行不删，只把默认值改回 3D。

## 2. 落地清单

| # | 改动 | 文件 |
|---|---|---|
| ① | 新增总开关 `ENEMY_BULLET_BILLBOARD := false` | `src/framework/GameDesignConfig.gd` |
| ② | 新增图标尺寸倍率 `ENEMY_BULLET_ICON_SCALE := 0.70` | 同上 |
| ③ | `Projectile3D` 新增 `_billboard_override`（-1 跟随总开关 / 0 强制 3D / 1 强制公告板），来源 `projectile_config["billboard"]`；池化复借逐发重置 | `src/combat3d/Projectile3D.gd` |
| ④ | 切换出口单点化为 `_hostile_billboard_enabled()` | 同上 |
| ⑤ | 图标尺寸乘 `ENEMY_BULLET_ICON_SCALE`；快照新增 `icon_size_scale` | `src/vfx/BulletBillboardIcon3D.gd` |
| ⑥ | 两条弹体路由的快照透出 `icon_size_scale` | `VfxBulletVisual3D.gd` / `VfxBulletBody3D.gd` |
| ⑦ | `Projectile3D.get_orientation_snapshot()` 透出 `icon_size_scale` | `Projectile3D.gd` |
| ⑧ | 子投射物（环形爆散 / 地面爆散 / 子母弹）继承母弹的形态覆盖 `_inherit_billboard()` | `Projectile3D.gd` |

切换方式（三种，优先级从低到高）：

1. 改 `GameDesignConfig.ENEMY_BULLET_BILLBOARD = true` ⇒ 全局切公告板。
2. 单发 `projectile_config["billboard"] = true/false` ⇒ 覆盖全局（验收脚本与将来「按怪物选」）。
3. 不改代码，用上面两种组合做 A/B。

## 3. 70% 的语义变化（必须记住）

11-09 的契约是「图标核心直径 **严格等于** 判定球直径」（所见即所中）。
乘 0.70 后核心比判定球小 30%：

| 倍率 | 图标核心 | 语义 |
|---|---|---|
| 1.00 | = 判定球 | 所见即所中 |
| 0.70（现行） | = 0.7 × 判定球 | **所见小于所中**：不会误导成「打得到」，但会低估命中范围 |

判定球半径**不动**（`_collision_scale_factor()` 与 3D 弹体尺寸不受此倍率影响），
`verify_crosshair_billboard` 里有一条专门断言它没被带偏。

## 4. 验收

| 用例 | 结果 |
|---|---|
| `verify_crosshair_billboard`（31 → **37** samples） | OK |
| `verify_bullet_vfx_profiles` | OK，samples=70 |
| `verify_bullet_aim_alignment` | OK，samples=20 |
| `check_documentation_contracts.py` | 无新增红项（14 条 broken link 均为 10-18/10-19 存量） |
| `check_asset_runtime_naming.py` | `ASSET_RUNTIME_NAMING_OK`，欠账未增 |

新增的三条缺省哨兵（防「总开关被谁改回 true 也没人发现」）：

- 敌弹不传 `billboard` 时 `billboard` 必须为 false；
- 此时 3D 弹体必须可见；
- 此时图标必须不可见。

真机对照：`outputs/bullet_presentation_20261110/compare_3d_vs_billboard70.png`
（左列 3D 弹体、右列公告板 70%，三组同色同距）。
探针 `tools/_probe_bullet_presentation_compare.tscn`（真渲染，不能 `--headless`）。

## 5. 遗留

1. **公告板「看起来还是大」的主因是外晕，不是核心**：`halo_radius 0.50` 相对
   `core_radius 0.30` 是 1.67 倍，墨迹外沿比核心大 67%。要再收观感体积，
   应动 `halo_radius` / 外晕 alpha（`0.42`），而不是继续压 `ENEMY_BULLET_ICON_SCALE`
   —— 后者会连带把「所见即所中」的比例一起压坏。
2. 描边 `rim_half_width = 0.012` 在 20px 屏幕上不足 1px，被 `fwidth` 抗锯齿吃掉，
   公告板模式目前读不出深色轮廓。要恢复「实心弹」边界需改成像素恒定宽度。
3. `ENEMY_BULLET_ICON_SCALE` 是全局常量，尚未接到 `monster_rules` 的按怪物配置；
   真要「按怪物选形态」需在 `Enemy3D._launch_projectile()` 里透传 `billboard` 键
   （出口已备好，只差下发）。
