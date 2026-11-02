# 远征03 敌弹：弹速全域 −1、弹体视觉逐只 1.30~1.80；玩家手枪弹体 ×2 → ×1.8

- 日期：2026-11-02
- 范围：`src/enemy3d/Enemy3D.gd`、`data/level_plans/expedition_03/level_plan.json`、
  `src/combat3d/WeaponModel3D.gd`、两个门禁探针、一项验收期望值
- 业主原话：「所有当弹速减1，子弹模型改成大小非统一的。帮我自行判断。改成1.3-1.8倍，
  按照怪物的体型和发射速率和伤害自行判断，不是原来的2倍。角色的子弹从原来的2倍改成1.8倍。」

## 1. 弹速：全域 −1.0 m/s

改的是 `Enemy3D.PROFILES` 里**每只怪自己的那一行**，没有动任何全局乘数
（弹速本来也不吃全局乘数，`_fire_projectile()` 直接取 `_active_profile["projectile_speed"]`）。

| 档 | 第四轮 | 第五轮（现行） | 谁 |
|---|---:|---:|---|
| 基准 | 6.0 | **5.0** | 28 只 |
| fast-moving | 7.5 | **6.5** | veteran_kin / hollowpoint / veteran_shotgun |
| 慢弹 | 4.5 | **3.5** | king_bullat |
| 吉吉的蛋 | 3.15 | **2.15** | gigi |

子机制里的独立弹速同步减 1（它们不在 `projectile_speed` 字段里，容易漏）：

| 位置 | 旧 | 新 |
|---|---:|---:|
| gun_nut `jammed.speed` | 4.875 | **3.875** |
| gun_nut `jammed.shatter_speed` | 4.5 | **3.5** |
| chain_gunner `orbit.speed` | 4.8 | **3.8** |
| cardinal `volley_alt.speed` | 3.9 | **2.9** |
| gigi `volley.speed` | 3.15 | **2.15** |

**没动的**：`suicide_rush.speed`（冲撞 9.5~10.5）、`leap.leap_speed`（扑击 8.0/9.5）、
`grab.dive_speed`（12.0）—— 这些是**本体位移**，不是子弹。

## 2. 弹体视觉：逐只 1.30~1.80

### 推导规则（先算成值，再写死进表）

```
v = 1.52 + 0.40 × (世界高 / 玩家 1.8 − 0.85) − 0.14 × clamp((密度 − 0.6) / 4, 0, 1)
密度 = 主攻击弹数 ÷ (cooldown + (弹数−1)×interval)，主/备攻击取更大者
```

三条含义：

1. **体型大 ⇒ 弹大** —— 同族一眼可辨（远程五兄弟 1.42→1.50 严格递增）。
2. **弹幕密 ⇒ 弹小** —— 高射速怪（空尖弹 3.03 发/秒、链枪手 5.29 发/秒）不让屏幕被糊满。
3. **伤害高 ⇒ 弹大** —— 威胁预警。**本层伤害统一 17**（自爆/冲撞类不开火），
   所以这一项在远征03 **恒为 0，是个保留位**；业主点名的三项里只有两项在起作用，
   这点必须写明，否则后人会以为漏实现。

取值**写成常量而不是运行时算**：数值要能被审阅、能被单条改（业主经常点名某一只）。
公式留在注释里作为"为什么是这个数"的依据，不作为运行时逻辑。

### 实测落点：19 档不同值，1.35 ~ 1.77

| 怪种 | 弹速 | 弹体倍率 |
|---|---:|---:|
| egt_hollowpoint | 6.5 | **1.35**（最小体型 + 最高射速 ⇒ 下沿） |
| egt_gun_fairy | 5.0 | 1.37 |
| egt_blobulin | 5.0 | 1.40 |
| egt_bullat | 5.0 | 1.40 |
| egt_keybullet_kin | 5.0 | 1.41 |
| egt_shotgat | 5.0 | 1.41 |
| egt_bandana_kin | 5.0 | 1.42 |
| egt_grenat | 5.0 | 1.42 |
| egt_chance_kin | 5.0 | 1.42 |
| egt_gigi | 2.15 | 1.43 |
| egt_red_shotgun | 5.0 | 1.44 |
| egt_veteran_kin | 6.5 | 1.44 |
| egt_spirat | 5.0 | 1.44 |
| egt_bullet_kin | 5.0 | 1.45 |
| egt_blobuloid | 5.0 | 1.45 |
| egt_nitra | 5.0 | 1.45 |
| egt_veteran_shotgun | 6.5 | 1.45 |
| egt_pinhead | 5.0 | 1.46 |
| egt_gripmaster | 5.0 | 1.47 |
| egt_king_bullat | 3.5 | 1.47 |
| egt_bookllet | 5.0 | 1.48 |
| egt_chancebulon | 5.0 | 1.48 |
| egt_cardinal | 5.0 | 1.49 |
| egt_blue_shotgun | 5.0 | 1.50 |
| egt_blue_bookllet | 5.0 | 1.50 |
| egt_blobulon | 5.0 | 1.51 |
| egt_green_bookllet | 5.0 | 1.51 |
| egt_gunjurer | 5.0 | 1.52 |
| egt_confirmed | 5.0 | 1.52 |
| egt_gunsinger | 5.0 | 1.56 |
| egt_chain_gunner | 5.0 | 1.60 |
| egt_mimic | 5.0 | 1.71 |
| egt_gun_nut | 5.0 | **1.77**（最大体型 + 低频 ⇒ 上沿） |

### 优先级与关卡值

`Enemy3D._effective_projectile_visual_scale()` 三级：**逐只档 → 关卡缺省档 → 1.0**。

关卡 `monster_rules.projectile.visual_scale` 从"统一 ×2.0"**降级为缺省档 1.52**，
只服务本关没有逐只值的怪（当前仅理论上存在的 Boss 链）。写成一函数而不是在开火处内联，
是为了让"谁生效"只有一处可查，验收也直接调它、不复刻优先级。

### 边界：仍是纯视觉

判定半径恒为 `Projectile3D` 的 **0.12 m** 基准球，不随本键变化。
放大判定会把远征03 顺手变难、把 `_egt_dodgeability_probe` 的可躲性判据一起改掉。

## 3. 玩家枪：手枪弹体 ×2.0 → ×1.8

`WeaponModel3D.BULLET_GEOMETRY_BY_GUN_TAG["pistol"].scale`。只一条。

**霰弹仍是 ×2.0**：那是 2026-10-14「子弹太小了，出生和结束都增加 2 倍」的**另一条裁定**，
本次没点名，不动。副作用与上次相同：霰弹弹体仍比手枪大。若业主要求"玩家子弹整体 1.8"，
改 `shotgun` 那一行即可（同时 `grow_from 0.42` 是比例，不用跟着调）。

## 4. 验收

| 用例 | 结果 |
|---|---|
| `tools/_egt_enemy_projectile_look_probe` | **OK** —— 逐只 1.30~1.80、**19 档不同值**、33 只全覆盖；逐只档压过关卡档；判定半径 0.12 |
| `tools/_egt_dodgeability_probe` | **OK** —— 18 只开火怪全有解（5 m/s 时 8 m 处可横移 6.8 m，原 5.48 m） |
| `tools/_egt_bullet_visual_probe` | **OK** —— 33 只存在/可见/有射程 |
| `tests/verification/verify_bullet_vfx_profiles` | **OK** —— `BULLET_VFX_PROFILES_OK`（samples=69），pistol 期望值已改 1.80 |

**门禁阈值同步（不是"为了全绿放宽"）**：
`_egt_bullet_visual_probe` 的弹速下限 4.0 → **3.0**。理由与第四轮同一条：
业主点名把弹速整体降档，旧下限会把**慢弹档本身**（king_bullat 3.5）判红。
取 3.0 = 慢弹档之下留余量，仍能抓住"漏配 ⇒ 落默认 7 m/s"那类问题。

`_egt_enemy_projectile_look_probe` 由"断言统一 2.0"改为三条：
① 33 只全部有逐只值且在 [1.30, 1.80]；② 至少 10 档不同值（**这就是本轮改动的存在理由**，
退回统一值必须判红）；③ 抽样硬编码 5 只（区间两端 + 三个中间档）并验证逐只档压过关卡档。

## 5. 已知未做

- 伤害项在远征03 恒为 0（本层伤害统一 17）。若将来给某只怪单独的伤害，
  公式里的伤害项需要从 0 变成实际系数 —— 现在的实现只按"体型 + 密度"两项取值，
  没有留运行时伤害项。
- 霰弹枪弹体仍是 ×2.0（见 §3）。
- 未做真渲染手感复核：本轮只有 headless 逻辑验收，**弹体在画面里的大小观感仍需业主人眼确认**。
  5.0 m/s 的弹速同理，可躲性数值上变宽松了，手感是否"太慢"要上手看。
