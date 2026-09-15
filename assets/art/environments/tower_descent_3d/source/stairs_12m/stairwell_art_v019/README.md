# 塔楼楼梯间美术源 v019

此目录是当前可维护的 Blender 美术源单元，不是 Godot 运行时导入目录。

```text
stairwell_art_v019/
├─ env_tower_stairwell_art_source_v019.blend   # 唯一 Blender 源
├─ asset_manifest.json                          # 源单元台账
├─ component_packages/                          # 10 个输出组件包的镜像清单
├─ renders/                                     # 总览与局部验收图
└─ qa/                                          # 范围锁定与验收报告
```

当前美术输出共 301 个网格，保留墙、地板、楼梯三个通用组件及七类装饰组件。运行时 GLB、碰撞、LOD 和 PackedScene 尚未更新。
