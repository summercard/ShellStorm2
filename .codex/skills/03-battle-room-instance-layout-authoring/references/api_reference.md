# 具体房间差异布局字段速查

## 默认继承

```json
{
  "base_layout": ".../component_instances.json",
  "source_blend": null,
  "instance_overrides": [],
  "instances": []
}
```

仅在选择 JSON 初始化且默认布局适用时采用此格式，不复制 Blender 源。已有正式房间/变体 TSCN 时直接在 Godot 编辑，布局差异也不强制 Blender 差异文件。

## 覆盖动作

当前轻量 `instance_overrides[]` **仅实现 `remove`**（按 `instance_id` 移除默认实例）；未知 op 会失败。`room_03/04` 仍在 `FloorPlanGenerator.ROOM_INSTANCE_LAYOUT_SOURCES` 代码中注册，通用资源自动注册未完成。

新增、删除、变换、启用和灯光调整均可直接保存到正式 Godot TSCN；`add/transform/enable` 不得冒充已支持的 JSON op。源几何材质归 Blender，组件碰撞挂点归稳定 Prefab，正式布局归 TSCN。覆盖解析须得到唯一完整列表；组件定义不超 50，同族常规不超 3、有明确状态轴不超 5，实例数另计。新增造型回到 02。

JSON/Blender 清单仅初始化与追溯，不自动覆盖正式手改。组件重导保留实例覆写，几何/接口变化先核查影响；生成器没有自动合并保护，正式场景覆盖须备份、差异、保留/回填计划和授权。

## 坐标

布局必须携带 `coordinate_contract`。Blender 平面为 XY、垂直为 Z；历史 `rotation_y_deg` 在源端表示绕 Blender Z，进入 Godot 前只转换一次。
