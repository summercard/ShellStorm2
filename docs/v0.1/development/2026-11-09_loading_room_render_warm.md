# 加载页逐房渲染预热：把「推开一道门顿一下」编译在黑屏里

日期：2026-11-09。功能：WORLD-ENTRY / PERFORMANCE-RUNTIME。
关联：[关卡进入与冷启动预热设计](../design/关卡进入与冷启动预热设计.md) r2、[远征03 落点归因](2026-11-08_expedition03_hitch_trace.md)、[性能优化与热管理](../13_技术施工_性能优化与热管理.md)。

业主：「好，先做加载页预载。」

---

## 零、先纠正一个方向：不是「预加载资源」

上一轮把跨门卡顿归到「首进某房要 load 0.4~0.9 s」，业主也据此同意做资源预载。
真去量了才发现这个判断是错的：

```
跨门那一帧  wall=1331 ms  gpu=7.7 ms  draw=939→939
            OBJECT_RESOURCE_COUNT 3984 → 4013 （Δ29，全程 3928~4276 波动）
            OBJECT_NODE_COUNT     26701 → 26512
```

**资源计数不涨、draw call 不变、GPU 只跑了 7.7 ms，主线程却停了 1.3 秒。**
资源早在装配期 `_build_room_shell_for_loading()` 逐房建壳体时就全 load 完了。

那这 1.3 秒是什么？两条证据指向同一个答案：

1. 同一间房走第二遍，p95 从 354 ms 降到 191 ms —— 一次性开销，不是每次都要付。
2. 用独立相机把每间房各画一帧之后再走，跨门 p95 从 543 ms 降到 273 ms。

⇒ **渲染管线第一次遇到这间房的材质组合时的同步编译。** 它不体现在
`render_cpu`（那是命令提交）、也不体现在资源计数里，只体现为墙钟。

所以正确的做法不是 `ResourceLoader.load()`，是**画一次**。

---

## 一、做法

预热分两段，顺序固定：

| 段 | 内容 | 集合 | 实测成本 |
|---|---|---|---:|
| A（既有，11-07） | VFX 11 件 + 怪 3 基类 | 与关卡无关 | 415~421 ms |
| B（本轮） | 逐房各画一帧 | 按本局房间表 | **1170 ms**（27 间） |

B 的实现只有一份：`Dungeon3D.warm_room_materials(parent, view_size, frames_per_room, budget_ms)`。
加载页 `ExpeditionLoadingScreen._warm_room_materials()` 只负责时机与预算，验收探针
（`tools/_exp03_hitch_trace.gd --warm`）调的是同一个函数 —— 探针里另写复制品的话，
量到的就不是正式路径了。

取景与预算：480×270、每房 1 帧、房心 +2.6 m、俯 12°、偏 35°、预算 4000 ms。

**为什么这么抠参数**（都是量出来的，不是拍的）：

- 480×270 与 720p 的收益差在噪声内，成本差一倍多 —— 管线编译与分辨率无关。
- 每房 1 帧与 2 帧的收益差也在噪声内 —— 第 1 帧就把管线编译掉了。
- 多建一次 `RuntimeDetail` 再画一遍（让陈设也上一次屏），只把跨门 max 再压 40 ms，
  但要多付 280 ms 加载时间，且把"卸载重建"重新拉回主线程 —— 不值，不做。

**为什么不动玩家**：B 用独立 `SubViewport` + 临时 `Camera3D`，`own_world_3d = false`
继承根视口，画的就是关卡本身。全程不碰玩家位置 ⇒ 不触发 `_on_room_entered`、
不建 `RuntimeDetail`、不刷怪、不动 `_spawned_rooms`。玩法时序一个字节都没改。

---

## 二、收益

同一进程内、预热前后各走一遍全图（25~27 次跨门），720p / Forward+ 高档 / `--disable-vsync`：

| 项 | 预热前 | 预热后 |
|---|---:|---:|
| 跨门 p50 | 21.4 ms | 20.5 ms |
| **跨门 p95** | **368.0 ms** | **257.2 ms** |
| 跨门 max | 1723.9 ms | 1254.3 ms |
| 稳态 p50（房内） | — | 6.6~8.4 ms |
| 开火 300 帧 p50 / p95 | — | 11.1 / 27.3 ms |
| 加载页增量 | — | **+1.17 s** |

p95 降 30%，max 降 27%。剩下那 250 ms 不是管线编译，见 §四。

---

## 三、验收

| 项 | 命令 | 结果 |
|---|---|---|
| 入口链（headless） | `probe_expedition03_entry_chain` | `ENTRY03_CHAIN_OK`，`room_warm={skipped:true,truncated:"headless"}` |
| 入口链（真渲染） | 同上 + `--disable-vsync` | `ENTRY03_CHAIN_OK`，`room_warm={rooms:27,total:27,elapsed_ms:1170}` |
| 阴影预算（回归） | `_exp03_shadow_budget_probe` | `SHADOW_BUDGET_OK`（shadow_lights=4 / data_only_shadow=0） |
| 跨门帧时间 | `tools/_exp03_hitch_trace.tscn -- --warm` | 见 §二 |

⚠ **探针假红记一笔**：加 B 之后 `probe_expedition03_entry_chain` 第一次跑报
`玩家脚下没有地面`。不是玩家卡在空中 —— 交接前读取页把目标树 `process_mode` 设成
`DISABLED`，而 Godot 的 `CollisionObject3D.disable_mode` 默认是 `REMOVE`，碰撞体
此刻不在物理空间里。预热 A 只有 400 ms，探针等 20 物理帧刚好躲过去；B 有 1.17 s，
就撞上了。已把探针改成先等 `can_process()` 再判落地（规则 8.1）。

**远征01 的既有红项**：`verify_expedition_level01_flow` 仍报 `room_10 south 侧格心那面墙
没有碰撞体`、`north_server_00 / north_broken_core 元数据 collision_shape_count=1 与实测 2
不一致`。这三条属房间几何与元数据，headless 下预热整段 skipped、`DungeonRoom3D` 零改动
（`git diff` 为空），与本轮无关。

---

## 四、还没解决的

| 项 | 量级 | 说明 |
|---|---:|---|
| 跨门剩余 | p95 250 ms | `RuntimeDetail` 重建（均值 30 ms、最贵 97）+ 释放旧房（`queue_free` 落帧末）+ 物理空间同步 + 少量未覆盖的材质组合 |
| 首次进某些房的额外加载 | 0.4~0.9 s | 奖励房 / 商店在进房那一帧还会 `OBJECT_RESOURCE_COUNT +253`；预热 B 不解决这类，需要按房间资源清单预载 |
| 首波怪同帧整批 | ~166 ms | 未动，会改出现时机 |

**试过但放弃的**：`DungeonRoom3D.keep_detail_resident`（离开房间只隐藏、不释放
`RuntimeDetail`）。跨门 max 从 461 降到 344，但 p95 不动，而且保留的家具碰撞会让
"隔壁房间的子弹打在看不见的椅子上"，交互组也会串房。改动已回退，`DungeonRoom3D`
本轮零改动。

---

## 五、口径备忘

1. **管线编译是"进程级一次性"的**：拿两次独立启动比，第二次天然好看（着色器缓存）。
   对照必须在同一进程内做「预热前走一遍 / 预热后走一遍」。
2. **`OBJECT_RESOURCE_COUNT` / `OBJECT_NODE_COUNT` 不能逐帧读**：遍历对象池，实测把
   p50 从 10.4 抬到 33.1。只在跨门那几帧读。
3. **同机不能并行跑第二个 Godot 渲染会话**：实测 p50 从 10.4 抬到 16.1、p95 从 16.4 抬到 72.8。
4. 预热 B 的截断不要写进 `loading_warmup_completed` —— 那是预热 A 的判据，是既有验收的牙齿。
