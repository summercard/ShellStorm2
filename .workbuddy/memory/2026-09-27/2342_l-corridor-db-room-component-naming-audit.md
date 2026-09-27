# L 型走廊与数据库房型组件类别/命名审计

## 范围
- `l_corridor/v003/L型走廊种类_数据连廊_45x40m_v003.blend`
- `db_room/v002/数据库房间种类_数据机房_40x30m_v002.blend`
- 对应正式归并库：L 型 `common_components/v012`，数据库 `common_components/v014`。

## 结论
- 两个房型原始 Blender 的视觉拼装正常，顶层类别划分基本符合结构/地面/设施/环境支持的生产分类。
- L 型原始源含 121 个槽位资产包（42 floor、32 architecture、17 facilities、30 support），其中 113 个正式 package_id 带网格坐标、方位或槽位序号；Collection Instance=0，属于历史“一槽一包”的制作/溯源结构，不能把这些名称当通用组件定义名。
- 数据库原始源含 86 个本地包（44 floor、28 facilities、14 support），另有 28 个来自办公室源的 Library Link 墙实例；链接复用方式正确，但 42 个派生地砖和多组设施仍使用坐标/方位/序号型包名，64 个 slug 命中位置型命名，不适合作为正式通用组件名。
- 后续正式归并库命名已规范化：L 型 v012 为 27 个组件/13 族，数据库 v014 为 35 个组件/24 族；两库 slug 均无方位、坐标和槽位编号，例如 `wall_5m_a`、`floor_tile_5m_b`、`server_rack`、`service_cart`、`repair_island`、`wall_screen`。
- 因此准确口径：原始 Blender 内的类别可作为生产分区；原始槽位包名只作 source_package/instance 追溯；真正的通用组件类别和正式命名以 v012/v014 的 component_catalog 为准。
