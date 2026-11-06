# 远征03木门v019与共享墙验收

2026-11-06，工程0.1.0。[交付记录](../../v0.1/development/2026-11-06_expedition03_wood_door.md)。

- [木门正面](optimized_front.png)、[木门背面](optimized_back.png)：同一公共色盘与固定验收灯光；深暗红主体、凸起木饰与有厚度的黄铜花纹。
- [正式场景正面关门](runtime_front_closed.png)、[背面关门](runtime_back_closed.png)、[开门净空](runtime_open.png)：Vulkan Forward+真实帧，保留游戏雾与材质；临时开启作者房间灯，隐藏HUD以便检查。灯光/雾未写回正式场景。
- [专项结果](runtime_report.json)：两个种子58扇普通木门，1767检查0失败；共享墙72/76组只显示一份，隐藏/卸载/重新加载交接通过。
- [源与优化的像素差异](fidelity.json)：四个固定视角平均通道误差均低于0.0001/255；[总母版锁区](master_sync.json)仅该门集合改变。

完整探针、导入日志和初次失败日志保留工程外会话目录。图示不是整关完成或性能验收。
