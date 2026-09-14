# 3Dgame-design

ShellStorm2 场景白盒编辑工具。运行 `npm run dev` 后访问 `http://127.0.0.1:4173/`。

## 项目区块与场景

工具把项目区块作为场景的上层容器。区块列表不在工具内重复维护，而是在每次请求时读取
`docs/v0.1/05.1_关卡区块设计.md` 的“§3 四区块分布”表。按既有五列格式增加区块行后，刷新工具即可看到新区块。

新场景保存到 `save/blocks/<block_id>/<scene_name>/scene.json`。场景 JSON 的 `project` 字段同时保存
`blockId / blockName / blockNodePath / floorRange` 快照。既有平铺存档保留兼容，但不会混入项目区块场景列表。

组件库会始终显示角色、建筑两组通用组件，并根据当前区块追加专用组件：`battle` 显示家具、办公，`rooftop` 显示道具。专用组件标题使用项目文档同步的正式区块名。

## 验证

运行 `npm test` 和 `npm run build`。
