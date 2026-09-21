# -*- coding: utf-8 -*-
"""2024 事务：第二段触发进深（房间相对位置触发）+ 运镜平移过去看僵尸。"""
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory"
DAY = os.path.join(MEM, "2026-09-21")
TX = os.path.join(DAY, "2024_第二段触发进深与镜头平移.md")
IDX = os.path.join(DAY, "_INDEX.md")
PB = os.path.join(MEM, "MEMORY-playbooks.md")


def load(p):
    raw = open(p, "rb").read()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    assert crlf and crlf == lf, "行尾不纯 %s" % p
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(p, t):
    data = t.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(p, "wb").write(data)
    print("  wrote %s CR=%d LF=%d" % (os.path.basename(p), data.count(b"\r"), data.count(b"\n")))


BODY = """# 第二段：触发进深（房间相对位置触发）+ 运镜平移过去看僵尸

> 类型：体验修复 + 能力新增（触发源 + 运镜）
> 关联：**1911**（同一条 cue 的 `forward_m`）、**1946**（运镜枢轴 `pivot`）

## 需求（主人）
「顺手[用]在第二段；然后[角色进第二个房间]的第二段触发器往房间里挪一点，让角色进房间后**门关上**再触发剧情。」

## 根因（为什么"贴着门口"）
`room_entered` 在玩家**刚跨进房间矩形**那一刻就发 ⇒ 那一刻门还没关、玩家还站在门口。
剧本 02 里一切「基于玩家位置」的东西（`scene.spawn` 的队列站位、`camera.pan` 的绕玩家甩头）
全都建在**站在门口的玩家**上 ⇒ 观感就是「怪刷在门口、镜头也在门口」。这是 1911 那次"刷怪贴门"的**上游根因**。

## 改法
1. **触发器**：由 `kind: "event"` / `room_entered` 改成**位置触发**，且用**房间相对**写法：
   `"kind": "point"` + `point_room: "floor_01_main_02"` + `point_offset: [-14.0, 0.0, 0.0]` + `radius: 2.5`。
   - 新增 `point_room` / `point_offset`（`NarrativeScript3D` 校验 + 导演 `_resolve_point_origin`）：
     世界坐标 = `room_node(room_id).to_global(offset)`，由导演**惰性解析**（`arm()` 那一刻房间还不存在）并缓存。
   - **不写死世界坐标**：房间是运行时生成的，写死会在换布局 / 换楼层后**静默失效**（"剧情永不触发"）。
2. **运镜**：`camera.pan` 由「绕玩家右甩 26°」改成 `pivot: "last_spawn"` —— 机位**平移过去正对僵尸**；
   2.6s 再以 `pivot: "player"` 平移回来。（pivot 能力见 1946）

## 真机几何实测（`verify_opening_script_runtime` E 段，非推算）
```text
会议室中心 world = (-5.0, -24.0, 2.5)
第二段触发点   = (-19.0, -24.0, 2.5)     <- 房间中心 + point_offset(-14, 0, 0)
```
与布局源吻合（`x∈[-25,15]` 中心 -5；`z = -y_b + 5.0` 的平面平移；98F 楼面 y = -24），
且**全部由房间解出、零写死坐标**。E 段断言：触发点在**房间内部**、且**不在**上一个房间（办公室）里。

## 验收
- `verify_narrative_timeline`：**101 → 103 项**。
  - 阶段 A 触发断言放宽为「`event` 或 `point`，但必须**点名房间**」（写死世界坐标的退化写法会被挡）。
  - C2 从 `_emit_room` 改走**位置轮询**，并加**反向对照**「站在触发点外不触发」。
  - 构图断言按新镜头重定：`|偏角| < 6°`（镜头正对僵尸）+ 深度 4~10m +
    **机位到队列距离 == 接管前相机距离**（证明绕的是队列、不是玩家）。实测 **偏角 0.0°、深度 6.86m**。
- `verify_opening_script_runtime`：**25 → 29 项**（新增 E 段真机几何校验）。
- ⚠️ 两个**测试基建**坑（已修）：
  1. 假相机**不会**跟着假玩家走 —— 挪玩家时必须一起挪相机，否则接管瞬间抓到的「玩家→相机」位移
     会变成 25m，运镜断言全线失真。
  2. 测试里站到触发点后**必须离开** —— 否则 C5「复位存档」把 `once` 归零后，那一次点轮询会把它误触发。
- 文档 08 §4.1/§4.2 + 项数；skill 10 §4.1 + 说明段；四副本已同步（`skills=29 files=83 copies=3`）。

## 一句话
`room_entered` 太早（玩家还在门口）⇒ 第二段触发器改成**房间相对位置触发**（进门 6m）、
运镜改成**平移过去正对僵尸**；真机几何实测触发点 = `(-19, -24, 2.5)`，全部由房间解出、零写死坐标。
"""

save(TX, BODY)

ROW = (
    "| 20:24 | [第二段触发进深（房间相对位置触发）+ 运镜平移过去看僵尸](2024_第二段触发进深与镜头平移.md) "
    "| **体验修复 + 能力新增** "
    "| 主人：「触发器往房间里挪一点，让角色进房间后**门关上**再触发剧情」。根因：`room_entered` 在玩家**刚跨进门**"
    "那一刻就发（门没关、人还在门口）⇒ 一切基于玩家位置的刷怪/运镜都贴着门口，这也是 1911「刷怪贴门」的**上游根因**。"
    "改法：① 触发改**房间相对位置触发**（新增 `point_room`+`point_offset`，`room.to_global()` 运行期惰性解析，"
    "**不写死世界坐标**）；② `camera.pan` 改 `pivot: \"last_spawn\"` ⇒ 机位**平移过去正对僵尸**再回来。"
    "**真机实测**：会议室中心 `(-5,-24,2.5)` + offset `[-14,0,0]` ⇒ 触发点 `(-19,-24,2.5)`（进门 6m）。"
    "验收 101→**103 项**（构图重定为「正对僵尸」偏角 0.0°/深度 6.86m，含反向对照）+ 真机 **25→29 项**（E 段几何校验）。"
    "⚠️ 修掉两个测试基建坑：假相机不跟假玩家、站触发点上不离开会被 C5 复位后的轮询误触发 |"
)
t = load(IDX)
assert sum(1 for l in t.split("\n") if l.startswith("| 20:24 |")) == 0
out, hit = [], 0
for l in t.split("\n"):
    out.append(l)
    if l.startswith("| 19:46 |"):
        out.append(ROW)
        hit += 1
assert hit == 1, "19:46 锚点 %d" % hit
save(IDX, "\n".join(out))

NOTE = """### 剧情 · 触发时机（`room_entered` 太早）+ 房间相对位置触发
- `room_entered` 在玩家**刚跨进房间矩形**那一刻发 ⇒ 门还没关、人还站在门口。一切「基于玩家位置」的
  刷怪站位与运镜都会**贴着门口**（第二段"怪刷在门口"的根因）。
- 要「进门之后（门关上）再演」：`trigger` 换成 `kind: "point"` + **房间相对** `point_room` + `point_offset`
  （相对**房间中心**，运行期 `room.to_global(offset)` 惰性解析并缓存）。**⛔ 别写死世界坐标** ——
  房间是运行时生成的，写死在换布局/换楼层后会**静默失效**（症状是"剧情永不触发"）。
- 实测（`floor_01_main_02`）：房间中心 `(-5, -24, 2.5)` + offset `[-14, 0, 0]` ⇒ 触发点 `(-19, -24, 2.5)` = 进门 6m。
  真机几何由 `verify_opening_script_runtime` **E 段**守（触发点在房间内 + **不在**上一个房间内）。
- ⚠️ 测试基建两坑：① 假相机**不跟**假玩家走 —— 挪玩家必须一起挪相机，否则接管前位移变成 25m、运镜断言全崩；
  ② 测试里站到触发点后**必须离开**，否则「复位存档把 `once` 归零」后的那一次点轮询会误触发。"""
t = load(PB)
save(PB, t.rstrip("\n") + "\n\n" + NOTE + "\n")

print("ALL_DONE")
