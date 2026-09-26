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

具体房间与房型默认布局一致时采用此格式，不复制 Blender 源。

## 覆盖动作

`instance_overrides[]` 只允许：

- `add`：新增 catalog 内组件实例；
- `remove`：按 `instance_id` 移除默认实例；
- `transform`：只改位置、绕垂直轴旋转、单位缩放；
- `enable`：切换实例启用状态。

覆盖解析后必须能得到唯一完整实例列表；不得引用 catalog 外组件，不得超过房型 50 个唯一组件预算。新增造型必须回到 02。

## 坐标

布局必须携带 `coordinate_contract`。Blender 平面为 XY、垂直为 Z；历史 `rotation_y_deg` 在源端表示绕 Blender Z，进入 Godot 前只转换一次。
