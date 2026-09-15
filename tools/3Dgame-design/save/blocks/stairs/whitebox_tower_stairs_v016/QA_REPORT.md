# 楼梯间 v016 美术验收报告

- 源文件：`whitebox_tower_stairs_v015/whitebox_tower_stairs_v015.blend`
- 新版本：`whitebox_tower_stairs_v016/whitebox_tower_stairs_v016.blend`
- 参考图：`codex-clipboard-c1394193-0fa3-4111-af45-f2dc0fbf44d8.jpg`
- 范围：保留 v015 的楼板、墙壁、双跑楼梯、平台与栏杆接口；在原位新增工业装甲墙板、结构框、管线、灯带、踏步导光、控制盒、楼层标识、海报和绿植。
- 展示剖切：参考镜头仅隐藏近侧与右侧遮挡墙，不删除源几何；完整墙体仍保留在输出包中。

## 锁区与资产包

- v015 锁定网格：97。
- 修改前签名：`9022cd1c6e5d51c71a0a5556c06e88600d254ff8a25ba3beb68b978712b9adaf`。
- 修改后签名：`9022cd1c6e5d51c71a0a5556c06e88600d254ff8a25ba3beb68b978712b9adaf`。
- `locked_match=true`；锁定网格的对象名、父级、世界矩阵、尺寸及顶点/边/面计数未改变。
- 5 个末级资产包，全部非空；包内对象数分别为 97、57、41、25、22；未发现对象多包归属。
- 磁盘清单：5 个 `asset_manifest.json`，另有 `catalog.json` 与 `tree.txt`。

## 材质与 UV

- 材质数：4，且仅使用项目规定的四种共享材质角色。
- 公共色盘：`assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`，外链、未打包、`Closest` 插值。
- Blender 严格验证：`passed=true`，输出网格 339，面数 10,429，有效色格内 UV 岛 10,429/10,429。
- 所有输出网格均只有活动/渲染层 `PaletteUV`；无跨格面、单点岛、额外 UV、混合自发光或命名不合规对象。

## 视觉输出

- `楼梯间_v016_参考镜头_最终.png`：固定高位斜俯视剖切全景。
- `楼梯间_v016_俯视结构.png`：俯视结构与双跑关系。
- `楼梯间_v016_楼梯近景.png`：踏步、栏杆、导光与下层标识近景。
- 视觉方向：深蓝/蓝灰工业面板为主，青色轮廓灯建立层级，暖橙只用于局部焦点，紫粉用于标识与踏步节奏。

## 验证记录

- `python3 scripts/check_documentation_contracts.py`：退出码 0，`issues=[]`。
- `validate_game_prop.py --all-meshes`：退出码 0，全部 17 项检查通过。
- 第一次验证发现 12 个默认 `UV 贴图` 层与 56 个自发光命名不合规对象；已删除额外 UV、统一追加 `UI灯光` 语义并复跑通过。
- 制作中一次安全导向标脚本因辅助函数漏返回对象而报错；已删除该批次残留、重建并保存，最终后台验证未出现资产脚本错误。
- 未执行：GLB 导出、Godot PackedScene 导入、碰撞/LOD 与运行时替换；本次交付状态仅为 Blender 源场景与美术预览完成。
