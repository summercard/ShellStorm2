# 99F 基地 NPC r4：气泡抬高 + 半透明底板 + 白点彻底移除

工程 0.1.0 / FeatureID `BASE-NPC` / 设计修订 **r4**。
设计文档 `docs/v0.1/20_技术施工_基地NPC.md`，开发记录 `docs/v0.1/development/2026-11-02_base99_npc_green.md`。

## 三条口径

| 原话 | 改法 |
|---|---|
| 对话框会遮住整个角色，往上放一些 | 气泡中心 2.05 → 2.80 → **3.40**（两轮才够） |
| 黑色背景半透明 | `fill_color` → `Color(0.012,0.018,0.026,0.55)` |
| 这个白色的交谈和白点不要了 | NPC 列进 `DOT_EXCLUDED_PROVIDER_SCRIPTS` ⇒ 控制器**不建**圆点节点 |

## 四个必须记住的坑

1. **俯视角下"抬 1 米"只等于屏幕上 0.6 米**。基地相机俯角 53°，`cos53° ≈ 0.60`。
   2.05（世界间隙 0.23m）⇒ 屏幕 3~4px，糊在头上；2.80（0.98m）⇒ 实拍只有 **0.34 个角色高**，仍压头顶；
   3.40（1.58m）⇒ 气泡底边 y=289px、角色头顶 y=322px，**间隙 33px ≈ 0.7 个角色高**。
   ⇒ 经验值：世界间隙至少 ≈ **1.3 倍角色身高**。**验收按屏幕等效量守门（≥0.45 个角色屏幕高），别只比米数。**

2. **半透明底板的连锁反应：文字必须改走透明队列**。
   `Label3D.alpha_cut = ALPHA_CUT_DISCARD` 原是为了让文字进不透明管线拿运动矢量防 TAA 拖影，
   但**不透明永远先渲染** —— 底板一半透明就叠在字上，0.55 的黑把白字压到 45% 亮度。
   正解：`ALPHA_CUT_DISABLED` + `render_priority`（底板 0 / 文字 2）。

3. **估透明度不能单点算**。`result=(1-a)·bg+a·fill` 两个未知量，要两个不同亮度背景点联立。
   单点会得 `a≈0.12` 的错论（把 fill 误当近黑）。实测：`bg/result = 78/59` 与 `54/46` ⇒ `fill≈36`、`a≈0.46`（配置 0.55，差值是 tonemap/glow）。

4. **"淡出"不等于"没有"**。`is_interaction_dot_visible()=false` 只是插值淡出，期间白点和白色「(e) 交谈」会**闪**
   —— 业主两轮都在说这个。正解：脚本路径进 `DOT_EXCLUDED_PROVIDER_SCRIPTS`，**根本不建节点**（基地设施同路）。
   顺带：说话时黄色提示也要收，条件必须 `_talk_engaged or _dialogue_visible` ——
   `advance_dialogue()` 能绕过 `perform_interaction`（剧情/测试路径），光看 `_talk_engaged` 会让提示压在气泡下缘。

## 环境坑

**截图脚本必须 `APPDATA=<临时目录>` 隔离**。正式档有另一进程在写 `BaseManager` revision，
抢写触发 `Refusing stale save` 并把截图进程**卡死到超时**（本轮卡了两次，各十分钟）。

## 验收

- `verify_base_npc_flow` **exit 0**（新增 A14b 屏幕间隙、A24c 三条半透明、A20c 改判为"圆点快照为空"）
- `verify_speech_bubble_3d` **exit 0**（口径改写：`TRANSPARENCY_ALPHA` + `ALPHA_CUT_DISABLED` + 底板 priority < 文字；
  另记：断言要读 `fill_color.a` 而非材质 `albedo_color.a` —— 后者 = 配置 × 淡入进度，pop-in 瞬间是 0，会假红）
- `verify_interaction_dot_presentation` **exit 0**
- 文档契约 exit 1，17 条全是既有红项，**无一条**指向 NPC 文件

## 证据

`docs/v0.1/audits/evidence/2026-11-02_base99_npc/`：新增 **`base99_npc_talk.png`**（说话帧），重拍 noon / night / prompt。
截图脚本三个：`capture_base99_npc.gd`、`capture_base99_npc_prompt.gd`、`capture_base99_npc_talk.gd`、`capture_base99_npc_nobubble.gd`（A/B 对照用）。
都**不要**套 `timeout`（本机 Git Bash 的 timeout 会吞 `NPC_SHOT_*` 环境变量）。
