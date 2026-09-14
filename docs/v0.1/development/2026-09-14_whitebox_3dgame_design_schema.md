# 白模JSON对齐3Dgame-design

Battle v011与Stairs v012白模数据已改为`tools/3Dgame-design`当前v3场景格式。两份文件均声明Blender Z-up、米制距离、角度旋转，并以`groups`组织区块、以`components`保存可视白模组件。

ShellStorm2专属的AssetID、区块、楼层、正式源、运行状态和设计文档不混入组件字段，统一保存在`projectMetadata`。工具可忽略这些扩展字段；工程脚本从该对象读取生产合同。

本次只迁移数据格式。Battle仍是程序生成白盒，Stairs正式Blend仍以现有Godot GLB为几何真值，没有重新导入运行资产。
