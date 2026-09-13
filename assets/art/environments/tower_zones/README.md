# 塔楼区块资产目录

本目录只管理塔楼四区块的 Godot 入口和对照说明。Blender 源文件与已导入 GLB 保留原生产目录，避免仅因管理重排触发模型重新导入。

```text
tower_zones/
├─ rooftop/runtime/   天台区 PackedScene
├─ base/runtime/      基地区 PackedScene
├─ battle/runtime/    战斗区程序生成入口说明
└─ stairs/runtime/    楼梯区运行时资产映射说明
```

统一规则：区块目录小写单词；Godot 文件采用 `zone_<block>_v###.tscn`；AssetID 不随目录变化；原始资产通过 PackedScene 元数据、各区块 README 和资产台账追溯。完整契约见 `docs/v0.1/05.1_关卡区块设计.md`。
