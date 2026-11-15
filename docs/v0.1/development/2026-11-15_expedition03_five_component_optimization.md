# 远征03 五组件面数优化（2026-11-15）

## 任务范围

用户指定五个远征03复古公馆组件：

| AssetID | 组件 | 原始三角 | 目标 |
|---|---|---:|---:|
| `ENV-EXP03-MANOR-RUG-LOUNGE` | 金边会客地毯8×10m | 87,128 | **<2,000** |
| `ENV-EXP03-MANOR-RECEPTION-DESK` | 弧形格栅接待台 | 26,928 | ≤5,385（原始/5） |
| `ENV-EXP03-MANOR-RUG-RUNNER` | 金纹走廊地毯2.4×5m | 14,040 | ≤2,808（原始/5） |
| `ENV-EXP03-MANOR-RUG-BEDROOM` | 卧室地毯3×4m | 13,648 | ≤2,729（原始/5） |
| `ENV-EXP03-MANOR-FLOWER-ARRANGEMENT` | 红花插花摆件 | 11,512 | ≤2,302（原始/5） |

范围外的另外 36 件远征03组件没有修改。

## 实施

- 新源批次：`art_source/.../common_components/v021/`。
- 五个独立 `.blend` 源副本，稳定运行 GLB 路径保持不变，只替换同名 GLB；Prefab `asset_version` 与 `source_blend` 同步到 v021。
- 地毯：原始网格每面都是独立 `PaletteUV` 岛，普通 Decimate 会被 UV 接缝卡在约 23,770 面。采用「矩形轮廓 + 薄厚包络 + 原色盘格采样 + 规则网格重建」，不是强行删除色盘边界。
- 接待台 / 插花：Collapse 减面；接待台减面后按原局部包络恢复尺寸。
- 所有输出保留公共色盘材质角色和 `PaletteUV`；GLB 导出 `images=0 / textures=0`。

## 最终结果

| 组件 | Blender 源后 | 正式 GLB 实测 | 减面率 | 包络 |
|---|---:|---:|---:|---|
| 金边会客地毯 | 1,978 | 1,978 | 97.73% | 8×10×0.053m，未变 |
| 弧形格栅接待台 | 5,384 | 5,384 | 80.01% | 5.580289×1.3175×1.266835m，未变 |
| 金纹走廊地毯 | 2,746 | 2,746 | 80.44% | 2.4×5×0.053m，未变 |
| 卧室地毯 | 2,634 | 2,634 | 80.70% | 3×4×0.053m，未变 |
| 红花插花摆件 | 2,302 | **2,280** | 80.20% | 0.497855×0.585129×1.166766m，未变 |

花卉 GLB 比源侧少 22 个退化三角，这是 glTF 导出器清理结果；仍满足 ≤2,302 目标。清单已写入 GLB 实测值 2,280。

## 自检

| 检查 | 结果 |
|---|---|
| Blender 源面数 / 目标面数 | **5/5 通过** |
| Blender 包络 | **5/5 通过**；最大误差 2.4e-7m |
| 材质角色 | **5/5 通过**；只含项目四角色中的既有子集 |
| PaletteUV | **5/5 通过**；活动层、渲染层、非零岛、单色格安全区 |
| 正式 GLB JSON | **5/5 通过**；面数、无图片、无纹理、UV primitive 存在 |
| 最小 Godot 工程真实加载 | **5/5 通过，exit 0**；无 `ERROR` / `SCRIPT ERROR` |
| 主工程 Godot 专项 | **未通过，原因不是资产几何**：主工程既有 UID duplicate 让全项目 Scan thread aborted，五个 GLB 的 `.godot/imported/*.scn` 缓存未生成，日志指向缓存缺失。最小隔离工程已证明五件正式 GLB 可被 Godot 正常加载。 |
| 固定镜头对比 | 已出五件前后图与 contact sheet；主体轮廓、颜色关系、包络无明显破面/穿插 |

主工程相关日志中还有既有 `uid://c8tfkc8nrnge7` 公共色盘 fallback 警告和多处 UID duplicate；它们没有改动，本轮不吸收。

## 证据

- `ShellStorm2-work/outputs/expedition03_five_optimization_20261115/optimization_report.json`
- `ShellStorm2-work/outputs/expedition03_five_optimization_20261115/comparison_contact_sheet.png`
- `ShellStorm2-work/outputs/expedition03_five_optimization_20261115/before/*.png`
- `ShellStorm2-work/outputs/expedition03_five_optimization_20261115/after/*.png`
- `ShellStorm2-work/outputs/expedition03_five_optimization_20261115/godot_probe/qa.log`
- `ShellStorm2-work/outputs/expedition03_five_optimization_20261115/import_v021_long.log`（主工程导入扫描既有问题）
- 改前备份：`ShellStorm2-backup/2026-11-15_expedition03_five_optimization/before_edits/`

## 未做与边界

- 没有修改 03 房间布局、实例数量、碰撞或房间 TSCN 摆位。
- 没有把这五件正式接入新的房间变体；现有 Prefab 路径保持复用。
- 主工程 `.godot` 缓存受既有 UID 扫描问题影响，不能把主工程正式场景专项签为通过；最小 Godot 隔离工程已通过。
