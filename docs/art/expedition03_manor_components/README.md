# 远征03复古公馆组件验收

[Blender最终顶视](manor_final.png) · [前台与会客近景](manor_detail.png) · [斜视](manor_oblique.png) · [Godot隔离重放](godot_replay.png) · [优化前后四视角](optimization_comparison.png)

40个组件、同族最多3个、140条集合实例。原始文件与独立优化文件分别保留。`blender_package_validation.json`、`master_validation.json`、`anchor_validation.json`、`godot_verification.json`记录本批专项检查；`final_gate_exits.json`记录全库门禁退出码，全库既有问题见开发记录。

## 状态（2026-10-31 更新）

**可在远征03 场景工坊里拼装房间，含 6 件结构件。** 这批资产已进库并提交，其它机器拉取即可用。

- 40 件全部有：Blender 源（`art_source/…/v017/component_packages/`）、优化 GLB、Godot 运行包装（`runtime/common_components/manor_*/`）、组件目录登记（`shell_component_catalog.json`）、资产账本行（`ENV-EXP03-MANOR-*`）。
- **结构件是远征03 的例外**：护墙 / 门墙 / 地砖默认会被剥离（墙与门属于玩法几何），本关放行，按**实际覆盖**接管程序化地板与墙面。详见[组件制作规范](../../v0.1/design/远征03复古公馆组件制作规范.md)《在远征03 拼装房间》。
- 装配时必须用 `manor_wall_door` 占门位，不能用实心护墙 —— 实心件带碰撞，压住门洞会挡路。

## 复核探针

```
godot --headless --path . --script res://tools/_manor_batch_probe.gd       # 206 条：网格/尺寸/原点/碰撞/分类
godot --headless --path . --scene  res://tools/_exp03_manor_art_probe.tscn # 美术层放行与接管（铺满 vs 只摆一件）
```

`_manor_batch_probe` 结论：40 件网格均非空（43 个 MeshInstance3D）、声明 `bounds_size_m` 与实测包围盒逐件吻合（容差 0.12m）、`bottom_center` 契约成立、6 件结构件带碰撞 / 34 件陈设为 `visual_only`。

`_exp03_manor_art_probe` 结论：铺满时保留 45 件结构（25 地砖 + 19 护墙 + 1 门墙）、跳过程序化地板与四面墙、门扇仍在；只摆 1 件时程序化壳体原样保留。
