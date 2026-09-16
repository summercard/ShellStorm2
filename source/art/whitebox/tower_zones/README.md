# 塔楼区块白盒

战斗区仍处于白盒阶段。`battle_level01/` 是局内关卡01（Battle）的唯一白盒根目录，`stairs/` 是楼梯间（Stairs）的唯一白盒根目录；不再以无区块含义的顶层版本号存放文件。每个白盒版本固定使用 `data/`、`blender/`、`renders/` 三类目录；正式 Blender 源不得放在这里。

```text
tower_zones/
├─ battle_level01/
│  ├─ v001/                 # 首批局内关卡01白盒
│  ├─ v002/                 # 当前台账登记的19个Blender白盒
│  └─ legacy/v011/          # 旧程序化Battle JSON，仅供回溯
└─ stairs/
   └─ v011/ … v015/         # 楼梯间白盒版本；v011文件名历史上含battle
```

- `data/`：可由 `tools/3Dgame-design` 直接读取的 v3 场景 JSON；固定使用 Blender Z-up、米、角度和 `groups/components`，项目追溯字段放在 `projectMetadata`。
- `blender/`：根据同版本 JSON 组装或迁移的白盒 Blender 文件。
- `renders/`：由该白盒输出的顶视图、无标注图、立面、剖面和效果图。

楼梯区正式源：`assets/art/environments/tower_descent_3d/source/stairs_12m/stairwell_art_v021/env_tower_stairwell_dual_art_source_v021.blend`。该文件只包含两套楼梯间资产包；白盒目录不替代正式美术源。
