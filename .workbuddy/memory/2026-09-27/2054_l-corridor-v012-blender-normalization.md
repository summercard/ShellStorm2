# L 型走廊 v012 Blender 组件规范化

- 以 `l_corridor/v003/L型走廊种类_数据连廊_45x40m_v003.blend` 和历史组件库 `common_components/v002` 为输入，按 Skill 02 的历史整屋兼容归并流程生成新库 `common_components/v012`；未覆盖 v003 房型源和 v002 历史库。
- v002 的 121 个包 `source_world_origin_m` 均为空，正式归并改用 `_scratch/corridor_db_plan/corridor/old_lib` 中由源 blend 按包围盒底部中心实测补齐的摆位数据，禁止零坐标猜测。
- v012 结果：27 个唯一组件、13 个组件族、121 条实例、27 个独立组件 blend；实例引用 unresolved=0，coverage=true，旋转为绕 Blender Z 的 0°/90°。
- 地砖族 42 个实例收敛为 3 个结构状态；墙族保留 4 个真实几何状态，其中 1.35m 展示剖切低墙声明为 `structure_state=cutaway_low`；吊缆族 5 个真实结构状态均补齐变体契约。
- `l_turn` 与 `u_turn` 继续共用同一组件库；v012 的 121 条默认实例对应 `l_turn`，`u_turn` 后续只通过实例差异布局表达，内墙岛复用 `wall_5m` 族，不另立组件集。
- 门禁通过：`PLAN_COMPONENTS_OK`；命名违规 0、front_axis 非枚举 0、旋转锁死 0、缺少变体契约 0、绝对上限违规 0；文档契约检查 issues=[]。
- 已同步 `docs/v0.1/design/远征关卡01设计.md` 为 v012 Blender 组件库已规范整理、尚未导出 GLB/PackedScene。账本仍保持已登记未导出状态，本阶段不转正运行时状态。
