# 2026-10-18 隐藏门正式美术资产（两件组件）

## 需求

Blender 做一个隐藏门原始资产：**只要一个门**、半掩着、里面透光出来，外面用木板钉住，木板可以打掉。**分成两个组件**制作，先在关卡里带进去。

## 交付

| 组件 | AssetID | 尺寸 | 说明 |
|---|---|---|---|
| `secret_door_leaf` | `ENV-EXPEDITION-SECRET-DOOR-LEAF` | 2.48 × 2.64m（门腔深 1.82m） | 门框 2.2×2.5 洞口 + 1.70m 门腔 + 单扇门半掩 45° + 腔内自发光 |
| `secret_door_boards` | `ENV-EXPEDITION-SECRET-DOOR-BOARDS` | 2.38 × 2.51 × 0.14m | 5 条横板 + 2 条交叉斜撑 + 19 枚铁钉，可整体打掉 |

- 源：`art_source/environments/tower_zones/expedition/source/secret_door/v001/secret_door_v001.blend`
- 构建脚本：`tools/blender/build_secret_door_v001.py`（headless 可重跑，`SECRET_DOOR_SKIP_RENDER=1` 可只出几何）
- 运行 GLB：`assets/art/environments/tower_zones/expedition/components/common_components/{secret_door_leaf,secret_door_boards}/`
- PackedScene：`.../runtime/common_components/{...}/*_root_top3d.tscn`
- 台账：《资产主表》967–968 行、《3D-场景通用》789–790 行、域变更日志 v0.1.40

## 尺寸契约的来源（不是拍的）

| 参数 | 值 | 依据 |
|---|---|---|
| 门洞净宽 | 2.20m | `office_room/door_wall/door_wall_root_top3d.tscn` 实测 `LeftJamb` at x=∓1.8、宽 1.4 ⇒ 净洞 2.2 |
| 门洞净高 | 2.50m | 同上，`Header` 在 y=7.2 之下 |
| 门框贴面深 | 0.12m | 位点 x 落在 5m 墙模块拼缝（模块中心 −47.5/−42.5），不能改网格模块，故用贴面门框 |
| 门腔深 | **1.70m** | 单扇 2.14m 开 45° 需 `2.14×sin45°≈1.51m` 行程 |

## 五处踩坑（都是渲染/验收一眼看出，靠肉眼猜会漏）

**① 先渲染、后保存 ⇒ 色盘全品红。**
贴图走 `//` 相对路径，`//` 只有在 `.blend` 存盘后才有基准。第一版先渲染再保存，渲染时贴图解析失败，整张图 `(255,44,255)`。
修法：`setup_materials()` 用绝对路径建图 → 存盘 → 渲染 → `relink_palette_relative()` 改回 `//` → 再存一次。现在 `main()` 就是这顺序。

**② 两个组件各自按包围盒居中 ⇒ 木板跑到门扇后面。**
规范要求输出 X/Y 居中，我照做了，但两件各自居中会**破坏前后叠放关系**。渲染出来木板在门后，直觉上完全说不通。
修法：改用**共享装配系** —— X 居中、Z 贴底，但 **Y 不居中**：`Y=0` 固定为房间侧墙面，木板朝 `+Y` 凸出、门腔朝 `-Y` 凹入。两件在同一原点实例化就自动叠对。

**③ 门腔 0.85m 装不下 45° 的门 ⇒ 门叶穿出腔体背面。**
第一次只做了 0.85m 腔（想着塞进 1.11m 墙厚）。包围盒立刻暴露：门叶 Y 伸到 `+1.447`，比腔体背面还远 0.6m。
四个位点朝外 3m 已被探针验证为空（见第一阶段记录），所以加深到 1.70m 不会插进隔壁房间。

**④ 在门洞平面放发光楔形当"光" ⇒ 读成"又一块黄门板"。**
试了两次，一次放铰链侧（挡住门框），一次放真实缝隙（正对相机的大黄板）。两次都不是"光"。
结论：光只能靠**看得到后面的发光体积**成立 —— 1.70m 门腔 + 后壁大面积自发光面板 + 板缝对齐。门洞平面里什么都不该放。

**⑤ `material_override` 做受击提亮 ⇒ 钉子变成木头。**
`material_override` 是整件覆盖，不看 surface。木板层有两个 surface（哑光木板 + 金属钉子），一覆盖全变成同一个材质。
修法：`duplicate()` mesh，逐 surface 复制材质，只把索引 0 那份交出去改色。

## 光怎么透（这是需求的核心，单独说明）

```
门腔后壁  1.80×2.17m 自发光面板        ← "里面有房间"
  ↑ 前面    4 条更亮的自发光条          ← 纵深
  ↑ 地面    1 道溢光                    ← 地面反光
  ↑ 木板    横向缝隙 0.10–0.14m         ← 缝高与自发光条对齐，光物理穿过
```

木板缝隙**故意做成不均匀**（5 条板端点参差 ±0.05m、钉入深度 0~0.008m 各异）。整齐的缝隙看起来像百叶窗，不像随手钉的。

## Godot 接入

`SecretDoor3D` 从「一块程序化 Box」改成两层宿主：

```
SecretDoor3D (StaticBody3D，只持木板层碰撞)
├─ DoorLeaf   常驻 PackedScene
├─ Boards     可打掉 PackedScene
└─ BoardsShape 碰撞，破板时 set_deferred("disabled", true)
```

- 破板只拆木板层，**门叶留在原地** —— 这是与上一版的关键语义差别。
- 原点在地面门洞中心，所以 `_build_door` 不再 `+HEIGHT_M*0.5`；朝向改为 `rotation.y = atan2(-normal.x, -normal.z)`（让资产 `-Z` 对齐 outward 法线）。
- 传送门 `_build_gate` 相应补 `+DOOR_HEIGHT_M*0.5` 并跟随同一旋转。
- 资产缺失时退回程序化单板（`_build_fallback_panel`），关卡不会因为缺件开不了。

## 验收

| 项 | 结果 |
|---|---|
| `validate_game_prop.py`（单资产模式） | **passed: true**，3 网格 / 584 面全部为有效色格内 UV 岛；`extra_uv_layers: {}`；`packed_palette_images: []`；`non_shared_palette_images: []` |
| GLB | `images: 0`（不内嵌色盘）；材质 = 4 角色；`export_image_format=NONE` |
| 色盘绑定（Godot 侧） | 逐 surface 检查：`palette_bound=true`、`filter=0`(NEAREST)、`emission_op=1`(MULTIPLY) |
| 包围盒 | 门叶 2.48×2.64×1.82 @ (−1.24, 0, 0)；木板 2.38×2.51×0.14 @ z(−0.142→0) —— 木板在墙外侧、门腔在墙内侧，方向正确 |
| `verify_secret_branch_flow` | **通过**（含新增 A14：破板后门叶仍可见、木板已隐藏、碰撞已关） |
| A14 反向对照 | 把门叶一起隐藏 ⇒ A14 变红；还原后复绿 |
| `verify_expedition_level01_flow` | 通过，13 房 / Boss / 撤离 / 塔楼未改动 |
| `check_asset_registry.py --ledger scenes` | 本次两行通过；**仅剩第 962 行既有错配**（`ENV-OPENWORLD-UNDERGROUND-STREET`，备份账本里就已不符，与本次无关） |

## 未做

- 未清房时木板不可破（现在无条件可破）
- 撤离门按 `ceil(总内容房×0.4)` 解锁
- 撤离信标与结算、子图刷怪与掉落加成
- B1–B3 跳跃边界运行时断言

验收脚本里以上仍以 `[UNIMPLEMENTED]` 显式打印，没有伪装成全绿。

## 一个状态提醒

账本 xlsx 现在同时含**天台批次（未提交）**与**本次隐藏门两行**。二进制文件无法合并，提交时要么一起提交，要么先把天台那批的账本改动单独落地。本次改动前的账本已备份到：
`ShellStorm2-work/sessions/2026-10-18_secret_door_art/ledger_before_secret_door.xlsx`
