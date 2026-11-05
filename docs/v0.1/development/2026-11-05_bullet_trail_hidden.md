# 2026-11-05 子弹尾迹先隐藏（不删实现）

日期：2026-11-05；记录ID：`2026-11-05_bullet_trail_hidden`；功能ID：VFX-POOL；
工程版本：0.1.0（`project.godot` 未改）。

## 1. 业主口径

> 「所有子弹特效那个后面有个小拖尾那个小尾巴帮我先去掉看看效果，啊先隐藏掉不要直接去删掉，
> 回头如果觉得不行的话再给它加回来。」

拆成三条硬约束：

1. **视觉上尾巴消失** —— 所有弹种、所有枪，实机看不到弹体身后那条渐缩锥。
2. **不许删实现** —— 几何、材质、构图参数、动画一律保留，随时可一键恢复。
3. **不改观感其它层** —— 弹芯、外壳、每弹一灯、脉动、枪身族尺寸档、生长包络全部逐字不动。

## 2. 改了什么

一个总开关 + 两处按开关赋值。**没有删掉任何一行建造代码。**

| 文件 | 改动 |
|---|---|
| `src/framework/GameDesignConfig.gd` | 新增 `const BULLET_TRAIL_VISIBLE := false`（紧邻渲染层/光照掩码常量），注释写明「只控可见性、改回 true 即恢复」 |
| `src/vfx/VfxBulletBody3D.gd` | ① `_build_trail()` 末尾按开关设 `_trail_root.visible`；② `activate()` 的 `set_trail_visible(true)` → `set_trail_visible(GameDesignConfig.BULLET_TRAIL_VISIBLE)`；③ `_animate_trail()` 在整组隐藏时早退（隐藏节点上的 transform 改动看不见）；④ 快照新增 `trail_visible` |
| `src/vfx/VfxBulletVisual3D.gd` | 同上②处：`_build_visual()` 按开关设 `_trail.visible`、`activate()` 按开关复位；快照新增 `trail_visible` |

覆盖范围：八弹种专属弹体（`VfxBulletStandard/Sticky/Bounce/Piercing/Explosive/Homing/Blackhole/Balloon`，
全部继承 `VfxBulletBody3D`）+ 未登记弹种回落的通用弹体 `VfxBulletVisual3D`。
`Projectile3D` 命中时的 `set_trail_visible(false)`（嵌墙/命中收缩表现）保持原样 —— 它本来就是在关尾巴。

**必须改 `activate()` 的原因**：原实现里复借一律 `set_trail_visible(true)`。只改建造期会出
「池里复用的子弹尾巴又冒出来」的间歇性 bug，这是本轮唯一的真陷阱。

## 3. 恢复方式

`src/framework/GameDesignConfig.gd` 一行：

```gdscript
const BULLET_TRAIL_VISIBLE := false   # 改回 true 即完整恢复，无需重建任何节点
```

几何一直在内存里（面数、`trail_parts`、`trail_is_behind`、`trail_local_z` 快照全部照旧），
所以恢复不需要重新跑资产链、也不涉及任何 `.tscn`/账本改动。

## 4. 验收

| 项 | 结果 |
|---|---|
| 语法（`--check-only`） | 三个改动文件均无解析错误 |
| `verify_bullet_vfx_profiles` | `BULLET_VFX_PROFILES_OK … (samples=69)`，与改前一致（尾迹段数硬编码表 1/4/3/2/4/3/3/1 全过 ⇒ 几何没动） |
| `verify_combat_vfx_toon_v002` | `COMBAT_VFX_TOON_V002_OK … (samples=16)` |
| `scripts/check_documentation_contracts.py` | 仅存量问题（断链、4 个未注册场景、缺 `openpyxl`），本事务文件不在其列 |

## 5. 真渲染取证（2026-11-05 追加）

业主「截个图我看一下，我要角色和怪物同时出现子弹的那个画」⇒ 新增一次性取证工具
`tools/_bullet_trail_shot.{gd,tscn}`，真实渲染出两张：

| 图 | 内容 |
|---|---|
| `outputs/bullet_trail_hidden_shot.png` | 全景三格：玩家角色 + 怪物 + 子弹在弹道 30% / 58% / 84% 三个位置同框 |
| `outputs/bullet_trail_hidden_ab.png` | 特写 A/B：同一颗子弹、同一机位，左＝尾巴关（当前产品状态），右＝尾巴临时点亮 |

跑法（**必须带窗口，`--headless` 出不了图**）：

```
godot --path . res://tools/_bullet_trail_shot.tscn -- res://outputs/bullet_trail_hidden_shot.png res://outputs/bullet_trail_hidden_ab.png
```

**真实性边界（写清楚，免得日后把工具图当实机图）**：

- 玩家是 `scenes/Player3D.tscn`、怪是 `Enemy3D`、枪是玩家 `Avatar.weapon_socket` 上那把
  （`start_with_weapon = true` 走真实装配）、开火走 `WeaponModel3D.try_fire()` ⇒ `Projectile3D`
  ⇒ `visual_id` 路由到 `VfxBulletBody3D` 子类。零伪造装配。
- 人为干预只有三处：① 开火后 `set_physics_process(false)` 并手动摆弹体位置
  —— 真实弹速 23 m/s，枪口到怪约 3 m 只要 0.13 s，60fps 下 8 帧，靠等帧抓不准；
  且 `_physics_process` 里 `velocity = direction * speed` 逐帧重算，改 `speed` 会被下一帧覆盖。
  ② 怪物 `set_physics_process(false)`（本工具不做 AI，只要站桩）。
  ③ 灯光/环境是本工具自建的干净棚拍（3800K 主光 + 双侧补光 + 0.5 辉光），**不是关卡内光照**。
- 特写右格把尾巴点亮只改**该实例的 `visible`**，不碰 `GameDesignConfig.BULLET_TRAIL_VISIBLE`（const，改了要重编译）。

实测读数（工具打印）：`尾巴可见=否`（全景三格）、弹道 2.19 m、枪口 `(0.273, 0.985, -2.081)`。
图中那颗白色小件就是弹体本体（4 边棱柱，4 面 + 外壳），**后面干净、没有锥形拖尾**。

## 6. 未做 / 待业主定夺

- **没做关卡内的实机截图**：上一节的证据是隔离工作台的棚拍，能看清「有没有尾巴」，
  但**看不出关卡里实际灯位下的观感**。若需要关卡内对照，得另走加载 `TowerDescent3D` /
  `TrainingRange3D` 的路径（要处理 autoload 与存档隔离），成本高得多，先问业主是否值得。
- **尾迹是否永久退役**：本轮按「先藏起来看看效果」的口径交付。业主确认不要之后，再决定是
  「永久保持 `false`」还是「直接删掉尾迹建造代码 + 同步收紧 `verify_bullet_vfx_profiles`
  的 `EXPECTED_TRAIL_PARTS` 与面数预算表」—— 后者才需要改验收与账本。
- **没动** `14.6_特效系统与制作规范.md` 与 `MODULE_INDEX.md`：尾迹的设计原文仍然成立（几何存在），
  只是当前不可见；等业主定稿再改设计正文，避免文档反复。
