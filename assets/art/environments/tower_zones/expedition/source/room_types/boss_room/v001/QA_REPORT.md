# 远征区块 Boss 房种类美术源 QA

- 资产：`BOSS_ROOM_DATACORE_50X40`
- 版本：`v001`
- 源文件：`Boss房种类_故障数据库_50x40m_v001.blend`
- 房间类型：`BOSS_ROOM`
- 区块：`expedition`
- 白盒来源：`source/art/whitebox/tower_zones/expedition_01/v001/blender/远征关卡01_白模_Boss竞技场_50x40m_v001.blend`

## 视觉实现

- 深灰金属墙地、分格地板、红色警报灯与定位灯。
- 北墙大型 `DATABASE OFFLINE` 故障屏，包含警告三角、裂纹几何和故障 UI。
- 服务器机柜、工作站、档案货架、通风格栅、纸张、电缆、箱体和少量固定绿植。
- 中央保持开阔战斗区；四面墙完整保存在源文件中，切角隐藏仅用于参考渲染。
- 所有设施按结构、地面、固定设施、环境支持拆为语义资产包，没有把整屋焊成单一网格。

## 接口与结构验收

- 房间包络：`50.0 × 40.0 × 11.9m`。
- 白盒锁定对象：242 个；锁定包络：`[-25,-20,0] .. [25,20,11.9]`。
- 南门与西门保留原白盒门洞；门墙仍由左右门柱与门楣组成，净跨 2.2m、净高 2.5m。
- 网格对象无非单位缩放；最长基础墙件为白盒的 5m 模块。
- `scope_lock.json`：`locked_match=true`。
- 源白盒 SHA-256：`7a5018a8f1112c3625d83838ffbb5294738d938f3eca46a9cbb4f21b227d92f5`。

## 材质与 UV 门禁

标准 `validate_game_prop.py` 结果：`PASSED`。

- 输出网格（全场景审计）：1204
- 多边形：73202
- PaletteUV 合法面：73202 / 73202
- 使用材质：4 个共享材质角色
- 公共色盘：`assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`
- 非法额外 UV、非公共色盘、材质超预算、混合自发光、未命名自发光：均为 0

## 范围与后续

本版本是 Blender 房间种类美术源，只完成美术源、可拆解包、参考渲染和验收。未导出 GLB，未创建 Godot PackedScene，未制作碰撞，未修改玩法、房间生成器、门状态机、敌人、掉落、存档或设计源。`runtime_connected=false`，可交给 `02-battle-room-component-decomposer` 做组件拆解；接入运行时前仍需补远征01 Boss 房席位、房型模板和生成器路径。

## 渲染说明

参考渲染使用 Cycles 8 samples、1000×1000、关闭 OpenImageDenoise，仅为适配本机内存上限。源文件几何、材质和灯光未因该验收配置降级。
