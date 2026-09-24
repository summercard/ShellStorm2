---
name: blender-mcp-bridge
description: 从 WorkBuddy 会话直接驱动正在运行的 Blender（BlenderMCP 插件直连桥）——执行任意 bpy 代码、读写当前 .blend 会话内的对象/骨骼/修改器/材质，并用 Rigify 给非人形生物绑骨架（摆 metarig→生成→自动权重蒙皮→验证）。当需要"帮我去掉骨骼 / 帮我绑骨架 / 重新绑定蒙皮 / 改这个模型 / 看看 Blender 里现在是什么 / 在 Blender 里批量处理"但宿主没有 mcp__blender__* 工具时使用。不用于无 GUI 的批量资产生产（那种走 headless + --background）。
agent_created: true
---

# BlenderMCP 直连桥（会话内驱动正在跑的 Blender）

## 何时用

业主要求**改动他此刻正开着的那个 Blender 会话**（"帮我删掉骨骼""把这几盏灯调暗""看看场景里有什么"），
而且宿主里**没有** `mcp__blender__*` 工具。

## 铁律

1. **先确认服务真的在跑，不要假设。** 见「第一步」。
2. **动手前先存副本**：`bpy.ops.wm.save_as_mainfile(filepath=<副本>, copy=True)`。
   `copy=True` 不改会话 filepath，是纯粹的安全网。
   **不要用"反正能 Ctrl+Z"当兜底** —— 纯 `bpy.data.*` API 改动是否压 undo 栈并无保证。
3. **覆盖写入业主的资产前必须先问**（保存路径/命名涉及版本规范）。破坏当前场景内数据可以直接做（可重跑），
   覆盖磁盘文件不行。
4. **破坏性脚本必须幂等**：执行到一半抛异常是常态，重跑要能补齐而不是二次破坏。

## 第一步：确认 MCP 服务在跑

BlenderMCP 插件（ahujasid/blender-mcp，bl_info name = `Blender MCP`）
**装在**：`%APPDATA%\Blender Foundation\Blender\<ver>\scripts\addons\addon.py`
**但不会自动启动**。必须在 Blender 里：3D 视图按 `N` → `BlenderMCP` 侧栏 → 点 **「Connect to MCP server」**
（operator `blendermcp.start_server`，端口取 Scene 属性 `blendermcp_port`，默认 **9876**）。

判定命令（bash）：

```bash
netstat -ano | grep 9876          # 期望看到 LISTENING
tasklist | grep -i blender        # 拿到 PID，再对 netstat 的最后一列
```

### 🔴 头号误判：60600 / Tripo3D 不是 MCP

`Tripo3d_Blender_Bridge` 会在 blender.exe 里跑一个 **WebSocket** 服务（`core/ws_server.py` 写死 `_port = 60600`）。
它在 netstat 里长得像 MCP，**但只认 `handshake` / `ping` / `file_transfer`，不能跑 bpy 代码**。

**识别信号**：拿 WebSocket 连上发 `{"jsonrpc":"2.0","method":"tools/list"}`，若回
`{"type":"default","data":<你刚发的那条消息>}` —— 那是它的 `_default` 回显处理器，
**说明"这不是 MCP"**，别去猜方法名。

## 第二步：桥（本机已备）

`I:\工作项目\shellstrom2\tools\blender_bridge.py`（零依赖，仅标准库 socket）

```bash
export PATH="/c/Program Files/Git/usr/bin:$PATH"
cd "I:/工作项目/shellstrom2/tools"
PY="C:/Users/zhuangmenghong/.workbuddy/binaries/python/versions/3.13.12/python.exe"

"$PY" blender_bridge.py get_scene_info
"$PY" blender_bridge.py get_object_info '{"name":"Armature"}'
"$PY" blender_bridge.py --code-file my_script.py
```

退出码：`0` 成功 / `1` 命令返回 error / `2` 连不上或超时（带中文提示）。

## 协议（已对 addon 源码核准，别自己猜）

- **裸 TCP，不是 WebSocket**。无长度前缀、无换行、无握手字节。一个连接一个 JSON 对象。
- 请求 `{"type": "<cmd>", "params": {...}}`，响应单个 JSON。
- 命令：`get_scene_info` / `get_object_info` / `get_viewport_screenshot` / `execute_code`
  （另有 polyhaven / hyper3d / sketchfab / hunyuan 等联网资产命令，一般用不到）。
- 🔴 **`execute_code` 的返回契约：只回 stdout。**
  `{"executed": true, "result": "<脚本的 stdout 文本>"}`，异常抛 `Code execution error: ...`。
  ⇒ **所有结论必须 `print()` 出来**，靠局部变量/返回值是拿不到的。建议最后 `print(json.dumps(...))`。
- 代码经 `bpy.app.timers.register(..., first_interval=0.0)` 在**主线程**执行
  ⇒ **Blender 里弹着模态对话框 / 正在拖拽时，命令会排队不返回**（表现为超时，不是桥坏了）。
- `exec(code, namespace)`，namespace 预置 `bpy`；顶层 `import` 可用，**`__name__` 不存在**。

## 第三步：独立复核

跑完别只看自己脚本的"成功"输出。用探针脚本从**另一条路径**查真实状态
（`tools/blender_scene_probe.py`：物体列表 / 网格统计 / `bpy.data` 数据块计数 / `filepath` / `is_dirty`）。
自己的脚本里写的校验块可能和它的 bug 一起错。

## 本机必踩的坑

- **工作区根 `inspect.py` 遮蔽标准库 `inspect`** ⇒ venv 里跑会报 `No module named 'bpy'`
  （因为 `inspect.py` 第一行就是 `import bpy`）。**Python 必须在项目子目录（如 `tools/`）里以 cwd 相对路径运行。**
- bash 里 `cd <中文绝对路径>` 静默失败 ⇒ 用 `cd "I:/工作项目/shellstrom2/tools"` 这种带引号的形式，
  且 `export PATH=...` 必须写在**同一条命令的开头**。
- 内联 `python -c "...反引号..."` 会被命令替换吃掉 ⇒ 长脚本一律先 Write 成文件再跑。

### 🔴 bpy 专属陷阱：`remove()` 之后不能碰那个指针

```python
# ✗ 抛 StructRNA of type ArmatureModifier has been removed
for mo in [x for x in obj.modifiers if x.type == "ARMATURE"]:
    obj.modifiers.remove(mo)
    print(mo.name)                     # 已经失效

# ✓ 先存名字
for mo in [x for x in obj.modifiers if x.type == "ARMATURE"]:
    mo_name = mo.name
    obj.modifiers.remove(mo)
    print(mo_name)
```

同样适用于 `bpy.data.objects.remove()` / `bpy.data.armatures.remove()` / `bpy.data.actions.remove()`。
**这个错误会让脚本在中途死掉，留下半成品状态** ⇒ 幂等设计是硬要求。

## 后端没有 mcp__blender__* 工具的排查清单

1. `~/.workbuddy/mcp.json` 是否存在（自定义 MCP 配置就在这，**不是** `.mcp.json`）
2. `~/.workbuddy/connectors/<uid>/connector-states.v3.json` 的 `enabled` 是否为空数组
3. `~/.workbuddy/connectors/default/mcp.json`、`~/.workbuddy/connectors/<uid>/mcp.json` 里 grep `blender`
4. 其他客户端的配置：`~/.cursor/mcp.json`、`~/.codex/config.toml`、`~/AppData/Roaming/Claude/claude_desktop_config.json`

以上全空 = 确实没接 ⇒ **走本技能的直连桥**，不要再无谓地找 MCP 工具。

## 用 Rigify 给「非人形生物」绑骨架（已跑通的完整流程）

### 选 metarig：生物一律用 Basic Human

| metarig | 骨数 | 有面部？ | 有手指？ | 用途 |
|---|---|---|---|---|
| `armature_human_metarig_add`（Human） | **159** | ✅ 整套（鼻/唇/眼睑/眉/耳/齿/舌） | ✅ 5 指 × 3 | 只有真做人形脸才用 |
| `armature_basic_human_metarig_add`（Basic Human） | **29** | ❌ | ❌ | **生物/怪兽首选**，干净 |
| `armature_wolf/cat/horse/shark/bird_metarig_add` | — | ❌ | ❌ | 真四足骨架 |

⚠️ **注意：如果目标骨架有既定骨名契约（比如项目要求 36 骨含手臂+手指），
Basic Human 没有手指骨** ⇒ 需要后续在 metarig 上加手指链再 Re-Generate。
Rigify 的设计就是「metarig 是唯一真源，随时 Re-Generate 免费」，所以先出可用 rig 不算白做。

### 流程（每步都要独立验证，别一把梭）

1. **加 metarig**（幂等：先删同名旧对象，否则会叠出好几个）。
2. **从网格几何算出摆骨坐标**，不要肉眼摆：
   - 脚 = 最低 5% 高度带的顶点，用 XY 网格 + 洪水填充做连通聚类 ⇒ 每只脚的 `center_xy` / `radius`。
   - 腿柱高度：以脚心为轴、半径 0.06~0.10 的圆柱内按 z 分箱数顶点，**柱子在哪一层断掉**就是腿的顶端。
   - 躯干中轴：只取 `|x| ≤ 0.07` 的中线柱按 Y 切片求 z 质心（含腿/头会把质心拉歪）。
   - 尾巴/头：按 Y 端 25% 切片另算。
3. **按 SPEC 表重摆**（`tools/blender_rigify_fit.py` 是现成模板）：
   `{骨名: (head, tail, use_deform, roll_align向量)}`，`.L` 写一条、`.R` 由 X 取反镜像。
   无意义骨（breast / pelvis / toe）塞进体腔 + `use_deform=False`。
   🔴 **两个必踩的坑**：
   - **改 head 前先 `use_connect = False`**，否则改 head 会被父级拉走；
   - 🔴 **改完必须把原本 connected 的链重新连上**，否则 Rigify 报
     `RIGIFY ERROR: Bone 'upper_arm.L': Input to rig type must be a chain of at least 3 bones`。
     对照 metarig 的原始 `use_connect` 值逐一恢复：手臂链是 **upper_arm → forearm → hand 三根都要连通**，
     腿链是 **shin → foot → toe**，脊柱是 spine.001/002/003/005。
     **漏连一根就整条链失效**（这一坑实测浪费了一整轮）。
4. **摆位验收两件套**：
   - 数值：对每根骨 head/tail 做内外判定 ——
     `ok, loc, nor, _ = mesh.closest_point_on_mesh(mesh.matrix_world.inverted() @ pt)`，
     `(pt - loc_w).dot(nor_w) < 0` 即内部。**要求 `inside_fail == 0`**。
     注意脚趾之间有缝，`foot/toe` 末端容易落进缝里 ⇒ 收短 + 抬高。
   - 肉眼：**骨骼不会被渲染出来**（armature 只是视口叠加层，`bpy.ops.render.render()` 里根本不存在）。
     要么把骨骼生成薄盒几何当临时网格渲染，要么用 Workbench 的 `shading.show_xray=True` + `xray_alpha≈0.15`。
5. **生成**：`bpy.ops.pose.rigify_generate()`（metarig 需 active、OBJECT 模式）。
   成功标志是 Blender 打印 `信息: 成功生成: "rig"`。失败时**必须把 `bpy.ops` 包在 try 里并抓
   `traceback`**，否则只能看到一句 `Code execution error` 而看不到 Rigify 的具体抱怨。
6. **蒙皮**：mesh 选中 + rig 激活 → `bpy.ops.object.parent_set(type="ARMATURE_AUTO")`。
   验收：`顶点组数 == deform 骨数`，且**两份名字集合完全相等**（不多不少）；
   再统计有权重的顶点数应等于总顶点数。
7. 🔴 **功能性验证要摆对控制层**：
   - **`*_fk.*` 骨转了没用** —— Rigify 腿默认 IK 生效，FK 被覆盖，改成 0 位移；
   - **`ORG-*` 骨也转了没用** —— 它们被 rig 的约束驱动；
   - 要验就得动 **`hips` / `foot_ik.L` / `hand_ik.L` / `head`** 这类真控制骨。
     判据：`hips` 转 14° 应带动上千顶点、最大位移厘米级；恢复后残差必须 **0.0**。
   - 实测参考：`hips` RX 14° + 两侧 IK 抬腿 + head RZ 20° ⇒ 2634 顶点位移 >1mm、max 0.139 m。

### 生成物规模（要提前告知业主）

Basic Human / 29 骨 metarig 生成出的是 **219 骨 rig（34 DEF + 77 MCH + 79 CTRL/NOPREFIX）
+ 79 个 `WGT-*` widget 对象 + 一个新 collection**。
**游戏导出只能要 DEF 层**（其余 `use_deform=False`，按 deform 过滤导出即可）。
项目若有「骨骼数」门禁（如 Godot 侧核对 36 骨），**必须再做一步 DEF-only 剥离 + 改名**，
不能把 Rigify 全量骨架直接导出。

## 已做过的具体案例（可直接复用）

`tools/` 下现成脚本（都通过 `blender_bridge.py --code-file` 跑）：
- `blender_rigify_fit.py` —— 按 SPEC 把 Basic Human metarig 摆到四足几何上（幂等，含重连逻辑）
- `blender_rigify_generate.py` —— 生成 Rigify 骨架（幂等，抓 Rigify 的具体报错）
- `blender_rigify_skin.py` —— 自动权重蒙皮 + 顶点组/deform 骨逐一比对
- `blender_deform_probe.py` —— 量化「哪个控制层真能带动网格」
- `blender_bone_inside_probe.py` —— 骨内外判定 + 骨骼薄盒可视化渲染
- `blender_rig_dump.py` —— 读 .blend 骨架结构（独立 headless，不碰业主会话）
- `blender_views_headless.py` —— headless 渲侧/正判体型，支持网格名过滤
- `blender_unrig.py` + `blender_unrig_run.py` —— 「去掉骨骼、准备重新绑定蒙皮」：
  删 Armature 物体 + armature 数据块 + 孤立 action，删 Armature 修改器，`vertex_groups.clear()`，
  挂骨架的网格**先存 `matrix_world` 再解父子**再写回（保世界坐标）。
  开关通过 `_UNRIG_OVERRIDES` 字典外部覆盖（干跑不必改文件）。
