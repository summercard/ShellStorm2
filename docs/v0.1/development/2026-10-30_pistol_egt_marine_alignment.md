# 豌豆手枪对齐《挺进地牢》：弹匣 12→10、弹速 23→25 m/s

- 日期：2026-10-30
- 触发：业主「帮我调整豌豆手枪的数值，子弹速度和弹夹数量对标挺进地牢的手枪角色的。」
- 影响文件：`src/base/BlueprintRegistry.gd`、`src/weapons/AssemblyNode.gd`、
  `src/combat3d/WeaponModel3D.gd`、`tests/verification/verify_starting_weapon_contract.gd`、
  内容表 `武器` 行 `bp_pistol`、[04 技术施工 §6.1](../04_技术施工_战斗与局内成长.md)、
  [参考页：初始手枪数据](../reference/挺进地牢/初始手枪数据.md)

## 1. 定了对标对象

《挺进地牢》没有叫「手枪」的角色，四个可玩角色各配一把手枪，弹匣与弹速差得很开
（详见[参考页 §2](../reference/挺进地牢/初始手枪数据.md)）：

| 枪 | 角色 | 弹匣 | 弹速 |
|---|---|---:|---:|
| Rusty Sidearm | 猎人 | 6 | 16 |
| **Marine Sidearm** | **陆战队员** | **10** | **25** |
| Rogue Special | 飞行员 | 8 | 22 |
| Budget Revolver | 罪犯 | 5 | 23 |

业主在四选一里选了**陆战队员 · 军用佩枪 `Marine Sidearm`**（弹匣 10 / Shot Speed 25）。
另外提醒过一句：名字最像的 `Pea Shooter`（"豌豆射手"）**不是任何角色的初始枪**，是教学通关
解锁的普通枪（弹匣 6 / 弹速 20），没被采用。

## 2. 只改业主点名的两项

| 项 | 改前 | 改后 |
|---|---:|---:|
| `magazine_size` | 12 | **10** |
| 弹速 | 23 m/s | **25 m/s** |

伤害 25 / 射速 3.5 发每秒 / 换弹 1.5 s / 扩散 0.03 / 射程 15 m **一律不动** ——
业主只说了弹匣和弹速，顺手把伤害往原作 5 点靠会把本作整条伤害刻度打乱
（本作豌豆手枪是 25，EGT 是 5，两者本来就不同标尺）。

## 3. 真正的坑：枪身声明弹速会被子弹节点覆盖

第一次改完，"数据看起来对、弹药打出来还是 23 m/s"。原因是**两条数值合并路径**：

| 路径 | 谁在用 | 实现 | `bullet_speed` 语义 |
|---|---|---|---|
| `WeaponAssemblyTree.get_computed_stats()` | 正式装配（`Player3D.equip_weapon` → `configure_from_tree`） | `AssemblyNode._combine_stats` | 子弹节点**直接覆盖**枪身 |
| `WeaponModel3D.configure(gun, bullet)` | 预览 / 测试 / 训练场直配 | `gun_stats.merged(bullet_stats, true)` | 子弹节点**直接覆盖**枪身 |

两条路径都会让 `Bullet_Standard` 的 `bullet_speed = 1.0` 把枪身写的 `25/23` 冲掉 ——
而数值检查、倍率显示、日志全都"正常"，只有实际飞行速度不对。以前没人踩到，是因为
**枪身从来不声明弹速**（只有子弹模块声明）。

修法是把 `bullet_speed` 从「覆盖」改成「相乘」：

- `AssemblyNode._combine_stats`：拆开 `bullet_damage`（仍覆盖）与 `bullet_speed`（改为相乘），
  枪身缺键时取 1.0 ⇒ 既有枪身行为逐字不变。
- `WeaponModel3D.configure()`：字典合并后补乘一次，与上一条同口径。

公式落成 `弹速 = 23 m/s × 枪身倍率 × 弹种倍率 × 命运倍率`，23 m/s 就是原作的
Shot Speed 23，所以**枪身只写倍率 `25/23 ≈ 1.0870`，不写 m/s**。

## 4. 门禁：三层哨兵 + 反向验证

`verify_starting_weapon_contract` 新增 `_check_pistol_egt_baseline`：

1. 枪身 `base_stats`：`magazine_size == 10`、`bullet_speed ≈ 25/23`；
2. 装配树（挂 `mod_bullet_standard`）算出的实际弹速 == 25 m/s —— 专防上面那条覆盖；
3. `WeaponModel3D.bullet_speed / magazine_size` 实际值 —— 防"数值改了但没接线"。

**反向验证**（把这两项改回 12 发 / 不声明倍率）五条断言同时报红：

```
ERROR: 豌豆手枪的弹匣是 12，期望 10（对标《挺进地牢》军用佩枪 Magazine 10）
ERROR: 豌豆手枪的枪身弹速倍率是 1.0000，期望 1.0870（= 25/23）
ERROR: 豌豆手枪挂标准弹后的弹速是 23.00 m/s，期望 25.0 m/s（枪身弹速倍率被子弹节点覆盖了）
ERROR: 豌豆手枪的 WeaponModel3D.bullet_speed 是 23.00 m/s，期望 25.0 m/s
ERROR: 豌豆手枪的 WeaponModel3D.magazine_size 是 12，期望 10
```

还原后 `STARTING_WEAPON_CONTRACT_OK`，退出时无 ObjectDB 泄漏（装配树与节点不是
`add_child` 进来的，探针里逐个 `free()`）。

## 5. 回归

| 场景 | 结果 |
|---|---|
| `verify_starting_weapon_contract` | 绿（含新增 5 条断言） |
| `verify_3d_reload_state_flow` | 绿（换弹用例按 `magazine_size` 动态取值，未写死 12） |
| `verify_3d_combat_progression_flow` | 绿 |
| `verify_bullet_vfx_profiles` | 绿 |
| `verify_synthesis_catalog` | 绿 |
| `verify_3d_inventory_weapon_flow` | **12 条红，与本次改动无关**：把豌豆手枪改回 12 发再跑，红项数与文案逐条相同（`does not render at the 96x96 projection budget` 等，headless 下 SubViewport 投影预算判定），属既有环境红项 |

## 6. 未做的

- 没动 `WeaponAssemblyTreePanel` 里子弹节点显示 `stats.get("speed")`（恒 1.0）的既有笔误 ——
  子弹节点存的是 `bullet_speed`，这个面板本来就显示不出真实值。与本轮无关，记账不顺手改。
- 没给其它枪身加弹速倍率：业主只点了豌豆手枪。
