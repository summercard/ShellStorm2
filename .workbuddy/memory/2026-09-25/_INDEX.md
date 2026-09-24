# 2026-09-25 事务索引

| 时间 | 事务 | 摘要 |
| --- | --- | --- |
| 0007 | [`0007_expedition01_footprint_data_gate.md`](0007_expedition01_footprint_data_gate.md) | 远征01 副线**数据层 + 门禁**：4 个非矩形外轮廓写进模板（`corridor_45x40` 的 `l_turn`/`u_turn`、`db_70x50` 的 `db_01`/`db_02`，挂 `variant_footprints`、顶点已归一 5m 网格）＋通道桥多层几何（`bridge_60x50` 的 `sunken_pit` 30×20 深 12 m / `bridge_span` 5 m / `lower_platform.accessible=false`）＋同步图集真源并重生成。新建门禁 `check_expedition_room_footprints.py` + 自测（对照 + 7 类不一致）。**钉死坐标系 `frame="bbox_nw_x_east_y_south"`（西北角原点、y 向南），并更正 2156 记的「西南角」**。回归：`LEVEL_PLAN_VALIDATE_OK checks=234 rooms=33`、资产状态 OK、文档总门禁 `issues:[]` |
