# 远征03 复刻怪：族内变种区分（2026-10-29）

## 1. 业主指令与问题本质

> 每个族群的变种帮我用不同方式进行区别，比如体型大小

这句话背后是一个**可读性缺陷**，不是审美偏好：

上一批 12 只复刻怪为了不改美术，全部借用现有 3 只怪（保安僵尸 / 小僵尸 / 炸弹果）的资产。
结果 5 只远程怪是**同一个模型、同一个体型 1.0、同一个颜色** ——
玩家在实战里无法分辨"三连发"和"预判弹"该用不同躲避方式。

这一批改动的全部目的：**让玩家不看名字也能分辨同族的变种。**

## 2. 每族选一个主区分维度（不是所有族都堆体型）

玩家战斗中只有三条读怪通道：轮廓/体型（远距可读）、颜色（中距可读）、行为/弹色（开打才知道）。
所以按「这一族的差异本质」选主维度：

| 族 | 差异本质 | 主维度 | 副维度 |
|---|---|---|---|
| 远程族（5） | 打什么弹 | **染色 = 弹色** | 体型阶梯 0.86→1.18 |
| 分裂族（3） | 同一个东西越裂越小 | **纯体型阶梯** 1.00→0.62→0.40 | 血条宽度 |
| 爆炸族（3） | 三种不同引爆方式 | **色温**（橙→黄绿→亮黄） | 体型 |
| 辅助族（1） | 独苗，非威胁但必须优先 | **放大 1.30 + 唯一紫色** | 血条最宽 |

## 3. 落地位置

| 内容 | 文件 / 常量 |
|---|---|
| 体型倍率 | `Enemy3D.BODY_SCALE_BY_KIND`（12 只逐只显式登记） |
| 血条宽度 | `Enemy3D.HEALTH_BAR_SIZE_BY_KIND` |
| 程序化外壳颜色 | `EnemyAvatar3D.COLORS` |
| **正式 GLB 染色** | `EnemyAvatar3D.FORMAL_MODEL_TINT`（新增） |
| 染色实现 | `EnemyAvatar3D._apply_formal_tint()`（新增） |

## 4. 三个真踩的坑

### 4.1 `COLORS` 对远程 5 只**一行都不生效**

`melee_chaser` / `ranged_caster` / `fat_zombie03` 三个基类挂的是**正式 GLB 模型**
（`FORMAL_NORMAL_SCENES`），`_load_formal_normal_model()` 里会把
`_shell.hide() / _core.hide() / _appendages.hide()` —— `COLORS` 只作用于这些被隐藏的外壳。

第一版只改了 `COLORS`，出图后 5 只远程**完全没变**，才定位到这里。

修法：新增 `FORMAL_MODEL_TINT` 通道（`albedo_color *= tint`）。
不复用 `COLORS` 而另开一张表，是因为两者语义不同：
`COLORS` 是"壳的底色"，`TINT` 是"贴图的色相偏移系数"，混用会让参数含义不可读。

### 4.2 GLB 材质在实例间共享，必须 `duplicate()`

第一版直接 `material.albedo_color = ...`，改一只会把**场上所有借同一模型的怪**一起染色。
现在逐 MeshInstance3D、逐 surface `duplicate()` 后再 `set_surface_override_material()`。

### 4.3 `exploder` 基类 0.78，若靠别名回退会让 pinhead 比 nitra 更小

`BODY_SCALE_BY_KIND` 查表会回退到借用资产的体型（`kind_table_lookup()`）。
若 pinhead 靠回退拿到 `exploder` 的 0.78，而 nitra 显式写 0.90，
就出现「血更多(38>31)、威胁更大反而更小」的倒挂。

⇒ 这批 12 只**必须逐只显式登记，不能靠回退**。

## 5. 探针设计上的两次自我纠错

这两条要记下来，因为都是"检查本身写错了"，不是数值错。

### 5.1 第一版用「跨族体型随血量单调」当判据 → 判失败 2 条

报的是：`bullet_kin`(hp=42,体型0.86) 比 `pinhead`(hp=38,体型1.00) 更强却更小。

**这是我的检查设计错了**，不是数据错。体型在**族内**表达强度排序，
在**跨族**表达形态体积 —— 两者是不同语义：

- `bullat` 14 接触伤害却只有 0.55 体型：它是一只**活体子弹**，体型表达形态；
- `blobulin` 体型由分裂层级决定，与血量无关；
- `gunsinger` **刻意最大**，让玩家一眼锁定"先杀它"；
- `bullet_kin` 是远程族入门怪，**刻意最小**。

把跨族也压成单调曲线，会毁掉全部形态语言。
改为：**跨族只查「同形状 + 同颜色不得跨族」** —— 长得一样却属不同族才是真事故。

### 5.2 第二版用 `ROLE_SIZED_EXCEPTIONS` 白名单 → 依然是错的判据

仍然在判"跨族倒挂"，只是允许有理由的例外。这等于承认判据本身没意义。
删掉白名单，换成撞车检查。

## 6. 出图工具踩的四个坑

`tools/_egt_variant_render.gd` + `tools/compose_egt_variant_lineup.py`

| # | 坑 | 后果 | 修法 |
|---|---|---|---|
| 1 | 透视相机 + 沿 Z 排四行 | 后排被透视压缩，几乎与前排重叠 | 改正交投影 |
| 2 | 正交 + 四行同图 | 前排标签压在后排怪身上 | 一族一图，Python 拼合 |
| 3 | `Label3D` 放怪脚下 / 放地面下 | 压在怪身上 / 落到视锥外被裁掉 | 文字全交 Python 在 2D 画 |
| 4 | Python 按"画布宽÷成员数"算列中心 | 图注横向偏移最多近 200px | 见下 |

第 4 条值得单独说：

- 第一次：Python 按画布均分 → 与 Godot 的世界坐标均分不是同一套换算，逐行偏移；
- 第二次：在 `_build_row()` 里调 `unproject_position()` → 全部挤在 x≈0，
  因为**新建节点当帧相机矩阵尚未解析**；
- 最终：构建只记世界 x，**拍照那一帧**再投影。

> 屏幕坐标只有一个真源 —— 相机本身。任何"按比例推算"都是在制造第二个真源。

另外两个小坑：
- `_row` 初值写成 `-1`，GDScript 负索引把 `LAYOUT[-1]` 解析成最后一族 → 辅助族拍两次、顺序全乱；
- 头顶血条是**世界尺寸** billboard，在正交近景里比怪还大还挡脸，且上面那个光照图标糊成噪声 → 出图时 `_hide_overhead_bar()`，血条宽度改写在图注里。

## 7. 验收

| 项 | 命令 / 场景 | 结果 |
|---|---|---|
| 数据层探针 | `tools/_egt_variant_visual_probe.tscn` | **`EGT_VARIANT_VISUAL_PROBE_OK`** —— 四族族内体型不重复、颜色不重复（分裂族豁免）、族内体型与血量同序、跨族无同形同色撞车、正式模型染色配方齐全 |
| 目视出图 | `tools/_egt_variant_render.tscn` + `tools/compose_egt_variant_lineup.py` | `outputs/verification/egt_variant_lineup.png`（1500×1320） |
| 回归：敌人行为流 | `verify_3d_enemy_behavior_flow.tscn` | **exit 0**，`3D_ENEMY_BEHAVIOR_FLOW_OK`（9 项行为全过，含"缩放血量/受击体积"这两条依赖体型表的） |
| 回归：强化怪专项 | `verify_strong_variant_monsters.tscn` | **exit 0**，ERROR 0 |
| 回归：真实刷怪链路 | `tools/_egt_runtime_probe.tscn` | **exit 0**，`EGT_RUNTIME_PROBE_OK` —— 进 `fireplace_room_inj2` 刷出 8 只，**8 只全是 `egt_*`**（veteran_kin 2 / bandana_kin 2 / blobuloid 1 / blobulin 1 / bullat 1 / gunsinger 1） |
| 文档契约 | `check_documentation_contracts.py` | 本次改动文档无断链（报的 3 条 unregistered 是既有灯具/楼梯栏杆） |

**未执行 / 未验证项**：

- **实战可读性未验**。只验到"数据上可区分 + 静帧上能分开"。
  真机跑动中（怪在移动、在攻击、有粒子光效）能否 0.3 秒内分辨，必须真打一局才知道。
- **分裂体染色是否有必要**：现在分裂族刻意同色。若实战中发现玩家把 blobuloid 当成新怪，
  可考虑给二阶/三阶加一点色相偏移。**这是待观察项，不是待办项**。

## 8. 改动文件

| 文件 | 改动 |
|---|---|
| `src/enemy3d/Enemy3D.gd` | `BODY_SCALE_BY_KIND` 补 12 只逐只登记；`HEALTH_BAR_SIZE_BY_KIND` 补 12 条 |
| `src/enemy3d/EnemyAvatar3D.gd` | `COLORS` 补 8 只外壳色；新增 `FORMAL_MODEL_TINT`；新增 `_apply_formal_tint()`；`_rebuild()` 颜色改为 `COLORS.get(enemy_kind, COLORS[_base_kind])` |
| `tools/_egt_variant_visual_probe.gd/.tscn` | 新增，族内区分度断言 |
| `tools/_egt_variant_render.gd/.tscn` | 新增，分族真实渲染 |
| `tools/compose_egt_variant_lineup.py` | 新增，拼合 + 绘图注 |
| `docs/v0.1/design/怪物设计.md` | §T3 重写为 T3.1~T3.7（区分体系、落地数值、染色陷阱、验收、替换约束） |
| `outputs/verification/egt_variant_lineup.png` | 交付图 |
