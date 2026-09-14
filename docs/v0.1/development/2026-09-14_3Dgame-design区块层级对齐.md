# 3Dgame-design 区块层级对齐

## 目标

让白盒编辑工具使用“项目区块 → 场景”的层级，并直接对齐关卡区块设计文档。

## 实施结果

- 新增项目区块接口，运行时读取 `05.1_关卡区块设计.md` §3 表格。
- 顶栏可选择四个当前项目区块。
- 新建、保存、读取、AI 编辑和实时预览均携带 `block_id`。
- 新存档进入 `save/blocks/<block_id>/<scene_name>/scene.json`，旧平铺存档保持原位。
- 场景 JSON 增加 `project` 区块对照快照。
- 组件库增加通用与区块专用两层：角色、建筑为通用；家具、办公归 `battle`；道具归 `rooftop`，标题使用文档正式区块名。
- 保存链路调用本机 Blender 4.2，把网页组件、分组和变换写入同场景目录的 `.blend`；JSON仅作为网页可逆编辑伴随数据，生成失败时不提交新版本。
- 增加当前场景 `.blend` 下载入口；不触发 Godot 或生产 GLB 流程（楼梯双向实验会生成仅供网页显示的预览 GLB）。
- 楼梯双向实验读取正式源的两个资产包根和真实网格；网页变换写回工作副本，重新刷新可从 Blend 恢复根变换，正式源不覆盖。
- Blender 打开入口已通用化：在楼梯区通过浏览器文件选择器打开 `env_tower_stairs_12m_source_v001.blend`，工具按文件名建场景并识别 `Stair_A / Stair_B` 两个资产包；同一入口适用于其他区块和 Blend 文件。
- 楼梯白盒母版清理：`whitebox_tower_battle_stairs_v011.blend` 从567个对象删除450个非楼梯白盒，只保留 `02_STAIRWELLS` 的117个对象；清理前备份为 `/tmp/whitebox_tower_battle_stairs_v011.before_stairs_only_cleanup.blend`。先前误清理的正式楼梯导入工作副本已恢复。

## 验收

- `npm test`、`npm run build` 与项目文档契约检查要求退出码为 0。
- Blender 4.2 后台生成专项：API 保存一块 5×5m 地板，生成 839KB `.blend` 与伴随 JSON；重新打开后场景名、2个对象和米制单位均正确。验收临时场景已移至 `/tmp/3dgame-design-api-acceptance-latest`，未留在正式区块存档。
- 楼梯双向专项：正式源的两个资产包成功导出为网页真实网格；将 `Stair_B.position.x` 从35写为40后重新打开工作 Blend，根对象X为40；随后恢复为35并再次刷新，网页与Blend均保持35。原正式源未修改。
