# ShellStorm Level Builder

Blender 4.3+ 关卡组件管理插件，当前在 Blender 4.5.0 验收。它复用 Blender 原生视图、移动、旋转、吸附、撤销和编辑模式，只补充 ShellStorm2 的组件库、锚点规范、吸附对齐、白盒预览、Collection 规范和磁盘资产包清单。

## 安装

```powershell
powershell -ExecutionPolicy Bypass -File tools/blender_addons/install_shellstorm_level_builder.ps1
```

打开 Blender 后，在 3D View 右侧边栏选择 `ShellStorm`。也可把 `shellstorm_level_builder` 文件夹复制到用户 Add-ons 目录后手动启用。

## 锚点规范

- 组件锚点指物体原点所在位置。默认 `底面中心`：X/Y 居中、Z 落在底面，和游戏内实墙 `env_tower_wall_solid_5m_top3d_v003.glb`（包围盒 Z 为 `0..11.9`）一致。
- 需要和 5m 地砖运行时包装完全对齐时，把“组件锚点”切换为 `对齐游戏资产`：地砖使用厚度居中原点（对应 `env_tower_floor_tile_5m_top3d_v002.glb` 的 Z 为 `-0.15..0.15`），其余组件仍是底面中心。
- 每个组件都是单个网格对象，直接进入编辑模式即可深化；`重设锚点` 可在不改变世界坐标的前提下把已有网格的原点移回锚点位置。

## 工作流

1. 选择区块、填写场景标识和版本，点击“建立规范集合”。该操作同时开启 Blender 原生吸附（顶点+增量、绝对网格）并把视口网格设为项目网格。
2. 从组件库添加白盒组件；新组件默认吸附到 `5m` 平面网格和 `0.3m` 标高步进。
3. 用 Blender 原生吸附摆放，或使用侧栏吸附按钮：
   - `吸附到网格`：把选中组件的底面中心对齐到项目网格和标高步进。
   - `贴齐到活动对象`：按 +X/-X/+Y/-Y/上方五个方向把选中组件贴到活动对象面上，另一轴居中、底面齐平。
   - `对齐轴`、`底面中心移到游标`：批量对齐或按游标落位。
4. 修改“组件参数”后可多选批量应用；生成的单网格仍可继续手改。
5. “预览与统计”提供白盒配色、线框描边、布局统计、顶视图标注（含 5m 模块网格底板与中文标签）和正交顶视图渲染。
   - 白盒配色与线框描边是即时开关，切换后立刻作用到全部插件组件；手动改过材质的对象用“刷新外观”重新覆盖。
   - “显示标注”只控制标注显隐；“生成标注/清除标注”负责创建与删除。标注为中文类型名 + 两行紧凑尺寸，字号随网格尺寸缩放。
6. 选择一个或多个对象，填写中文名、ASCII slug 和分类，点击“归入资产包”。
7. 先验证，再同步磁盘清单。每个末级资产包生成独立 `asset_manifest.json`，并生成总 `catalog.json` 与 `tree.txt`。

## 保护措施

- 清单同步要求先保存 `.blend`，避免写出指向临时路径的源文件；没有资产包或验证失败时直接拒绝写盘，不覆盖已有清单。
- 组件库扫描兼容本项目既有清单字段（`source_blend`/`source`、`blender_collection`/`collection`/`output_collection` 等），并按 Append 生成本地可编辑副本；扫描结果在面板上给出“可用 / 跳过（缺字段、源文件缺失）”诊断，便于定位清单问题。
- 插件不会自动导出 GLB、修改 Godot 引用或覆盖历史 `.blend`。

## 自测

```powershell
"D:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --background --factory-startup --python tools/blender_addons/test_shellstorm_level_builder.py
```
