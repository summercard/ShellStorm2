# 2026-09-29｜地面掉落散布范围与曲线 + 头顶名牌正对镜头

业主原话（两条独立诉求，同一次交付）：

> 「我掉落物品的范围和曲线还有上面的文字能调整吗？现在掉落物品的位置太集中了。但是也不要掉进阻挡里。」
> 「然后地上物品的头上的文字，不是对着镜头的，从上往下的摄像机会看不见。」

## 一、掉落物太集中 —— 根因与改法

**根因**：`Dungeon3D._spawn_loot_items` 的散布是一段写死的定值螺旋：

```
angle = index * 2.1 + 0.45          # 2.1 rad ≈ 120° 固定步进
radius = 0.7 + index * 0.18         # 每件只多长 0.18 m
```

两个问题：① **范围太小** —— 6 件的最外件只有 `0.7 + 5×0.18 = 1.60 m`；
② **曲线是错的** —— 半径随件数**线性**增长，落点只沿一条螺旋线往外爬，
既不铺面、也随件数变多越来越像一串糖葫芦。半径序列（6 件）：
`0.70 / 0.88 / 1.06 / 1.24 / 1.42 / 1.60`，相邻只差 0.18 m。

**改法**（`src/world3d/Dungeon3D.gd`）：换成「等面积半径曲线 + 黄金角错位」，
并把范围做成三个可调常量：

```
r_i     = lerp(LOOT_SCATTER_MIN_RADIUS_M, r_max, sqrt((i + 0.5) / N))
angle_i = i * LOOT_SCATTER_GOLDEN_ANGLE + 0.35        # 2.399963 rad = 137.5°
r_max   = clamp(LOOT_SCATTER_UNIT_RADIUS_M * sqrt(N), MIN, MAX)  再与 (房间半短边 - 1.2) 取小
```

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `LOOT_SCATTER_MIN_RADIUS_M` | 0.85 | 内半径：单件也离原点 0.85 m，不压在尸点上 |
| `LOOT_SCATTER_UNIT_RADIUS_M` | 0.95 | 单件基准半径，外半径按 `√N` 抬 |
| `LOOT_SCATTER_MAX_RADIUS_M` | 2.60 | 全局外半径上限 |
| `LOOT_SCATTER_GOLDEN_ANGLE` | 2.399963 | 逐件错位，件数少也不连成同向螺旋 |

**6 件、大房（44×34，半短边 17 m）的实算**：`r_max = 0.95×√6 = 2.327`（未触上限），
半径 `1.283 / 1.589 / 1.803 / 1.979 / 2.130 / 2.264`，最近件对间距 ≈ **1.5 m**
（旧值：最外 1.60 m、相邻 0.18 m）。**散布直径 1.60 → 4.53 m（≈2.8×）**。

`sqrt` 这条曲线不是装饰：半径若按**线性**取，单位面积上的件数外稀内密；
按 `r ∝ √(面积比例)` 取，单位面积件数才均匀 —— 这就是「铺满圆面」的那条曲线。

## 二、「不要掉进阻挡里」怎么保证的

原路径只有 `_find_supported_spawn_position`（从候选点上方 3 m 向下打射线找 `normal.y ≥ 0.55` 的支撑面），
**只判「脚下有没有地」，不判「头顶这段空间有没有被墙/家具横向占住」** ——
候选点若落在墙体正上方，射线命中的是墙顶面（`normal.y = 1`），道具会**落在墙上**。

新增 `_resolve_loot_spawn_position` / `_is_loot_landing_clear`：

1. 先按想要的位置**贴地校位**（沿用 `_find_supported_spawn_position`，不可省）；
2. 在**贴地之后**的位置上，用半径 0.30 m 的球、在离地 0.45 m 处做 `intersect_shape`
   （层 1、只查 body、排除玩家 RID）——撞到墙/箱柜/门框就判被占；
3. 被占则沿原点方向按 `LOOT_SCATTER_FALLBACK_SHRINK = [0.66, 0.33]` 收缩重试；
4. 都占着才回落到掉落原点本身 —— **宁可几件挤在一起，也不塞进阻挡里**。

⚠️ 顺序不能反：净空必须在**贴地之后**判。先判净空的话，地板自己就会把所有候选点判成「被占」。

## 三、头顶文字看不见 —— 根因与改法

**根因**：`GroundLootPickup3D` / `RoomKeyPickup3D` 的 `Label3D` 用的是**默认朝向**
（`billboard = BILLBOARD_DISABLED`）：文字躺在自己的 XY 平面上、只朝世界 `+Z`。
俯视镜头看到的是这张纸片的**侧面** —— 一个字都读不出来。位置和字号都没问题，纯粹是朝向。

**改法**：与项目内既有口径**完全一致**地改成 billboard（`Enemy3D` 血条、`CombatDamageNumber3D`
早就这么做了）：

```gdscript
_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
_label.no_depth_test = true
```

用 `BILLBOARD_ENABLED` 而不是 `BILLBOARD_FIXED_Y`：后者只绕 Y 转、保持纸片竖直，
**正上方俯视时仍然是侧面** —— 那正是本次要修的症状。

**可调旋钮提成常量**（`GroundLootPickup3D` 顶部，业主问的「上面的文字能调整吗」）：

| 常量 | 值 | 想改什么 |
| --- | --- | --- |
| `LABEL_HEIGHT_M` | 1.05 | 文字离物品原点多高 |
| `LABEL_FONT_SIZE` | 30 | 字号（字形分辨率） |
| `LABEL_PIXEL_SIZE` | 0.010 | 世界尺寸/像素比（嫌小抬这个） |
| `LABEL_OUTLINE_SIZE` | 8 | 黑描边宽度（嫌糊抬这个） |

文字内容仍在 `_build_visual` 里拼（物品名；武器追加 `#实例ID · 构筑 n/8`）。

## 四、门禁判据（`verify_3d_combat_progression_flow`）

新增 `_verify_ground_loot_scatter` 与两处名牌断言：

- **名牌**：`GroundLootPickup3D.get_model_snapshot()` / `RoomKeyPickup3D.get_pickup_snapshot()`
  新增 `label_camera_billboard` / `label_no_depth_test` / `label_height_m` / `label_text`
  （与 `Enemy3D.overhead_health_camera_billboard` 同一口径），断言前两项为真。
  **反向对照**：把 `billboard` 改回默认，这两条必红。
- **散布曲线**：逐件半径必须**严格单调张开**、内件不低于 `MIN_RADIUS`、最外件 `≥ 1.8`、
  任意两件间距 `≥ 0.5 m`。最外件那条是**反向对照**：旧螺旋 6 件最外 1.60 m，必红。
- **真实落地**：房间中心真放 6 件，要求全部落在房间足迹内（`|local| ≤ 半边长 - 0.5`）、
  每件 `_is_loot_landing_clear` 为真、最远件 `≥ 1.9 m`。
  这条是**不回归护栏**，不是本次改动的独立证据 —— 把 `_resolve_loot_spawn_position`
  换回直调 `_find_supported_spawn_position`，它仍有概率绿（外侧候选点落在房外无支撑时
  本来就会回落原点）。

## 五、验收状态：**未执行**（环境阻塞）

- `python3 scripts/check_documentation_contracts.py` → **exit 1**，唯一 issue 是
  `unregistered: verify_pushable_base_chairs`。该文件（连同 `.tscn`/`.uid`）是**上一次会话
  留下的未跟踪文件**（mtime 10:54–10:59，早于本次改动），**不是本次引入的**。
- `bash scripts/run_verification_suite.sh scene verify_3d_combat_progression_flow` → **没跑起来**：
  C 盘写满（`No space left on device`），运行器把工程连 `.godot/imported` 一起复制到
  `%TEMP%\shellstorm-verification.*` 时中途失败。
  现场 `%TEMP%` 下至少还留着 5 份历史副本：
  `shellstorm-verification.{RjNaxh, 464ll4, Zk0KTo, ae5sx1, 1iWWX9}`。
  **清掉这些副本后必须重跑本项验收**，本记录不能当成「已验证」。

## 六、同一类缺陷的存量清单（本次**未改**，待业主裁定）

所有运行时创建的 `Label3D` 里，只有 8 个文件设了 billboard。同类的「[E] 提示 / 目标文字」仍是
默认朝向，俯视镜头下同样读不到：

| 文件 | 标签 | 备注 |
| --- | --- | --- |
| `world3d/RoomDoor3D.gd` | `DoorPrompt`「[E] 使用房间钥匙」 | `visible=false`，靠近才显示 |
| `world3d/ExtractionBeacon3D.gd` | 撤离点提示 | 同上 |
| `world3d/ServiceStation3D.gd` | `[E] 结算房间事件` / 事件目标 | 同上 |
| `world3d/RoomFurniture3D.gd` | `[E] 搜索 · SIZE` | 同上 |
| `world3d/RoomLightSwitch3D.gd` | 灯开关提示 | 已设 `no_depth_test`，只缺 billboard |
| `combat3d/CombatEffect3D.gd` | 实效数值文字 | 已设 `no_depth_test`，只缺 billboard |

改法一致（一行 `billboard`），但属于**业主没点的范围**，故只登记不动手。
