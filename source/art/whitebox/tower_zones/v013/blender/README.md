# 楼梯区白盒 Blender v013（已由v014替代）

当前编辑入口已迁移至 `../../v014/blender/whitebox_tower_stairwell_components_v014.blend`。本目录只用于回退与追溯。

当前网页可编辑层级：

```text
楼梯间A_组件包
├─ 01_楼板（组件）
├─ 02_墙壁（组件）
└─ 03_楼梯（组件）
楼梯间B_组件包
├─ 01_楼板（组件）
├─ 02_墙壁（组件）
└─ 03_楼梯（组件）
```

每个分类Collection持有独立Empty根节点，分类内Mesh保持独立。3Dgame-design导入后生成两个网页分组与六个可编辑组件，保存时把六个组件根变换写回Blender，不执行Join。
