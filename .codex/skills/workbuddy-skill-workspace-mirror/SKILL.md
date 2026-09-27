---
name: workbuddy-skill-workspace-mirror
description: 把某个仓库里的「agent 指令目录」（如 .agents/skills/、CLAUDE.md、AGENTS.md 之类）迁成 WorkBuddy 能发现的 skill，并采用「工作区级正本 + 仓库内镜像」双副本布局。当用户说「把这个工程的循环/agent 换成 workbuddy」「让 workbuddy 能发现这个项目的 skill」「skill 要跟着仓库走版本管理」「两份 skill 是否一致」时使用。含幂等同步脚本、sha256 断言、CRLF 与相对链接两个必踩的坑。
agent_created: true
---

# 项目级 skill：工作区级正本 + 仓库内镜像

## 0. 什么时候用

- 仓库自带 agent 指令（`.agents/skills/`、`.claude/`、`AGENTS.md`…），要迁到 WorkBuddy。
- 想让 skill **既能被 WorkBuddy 发现**（只有工作区级才被发现），**又能进 git 版本管理**（仓库内）。

## 1. 核心约束（决定一切）

| 约束 | 后果 |
|---|---|
| WorkBuddy 只发现 `<workspace>/.workbuddy/skills/` | 正本必须放**工作区根**，不能在仓库子目录里 |
| 版本管理要跟仓库 | 必须有一份**仓库内镜像** |
| 两者目录深度不同 | ⇒ **Markdown 相对链接必然有一份失效**，见 §3 |

反之，如果工作区根**就是**仓库根（`git rev-parse --show-toplevel` == 工作区），
就没有双副本问题 —— 直接放 `.workbuddy/skills/` 并入库即可，**不要多余地做镜像**。

## 2. 布局与同步

```
<workspace>/
├── .workbuddy/
│   ├── skills/<name>/SKILL.md      ← 正本（WorkBuddy 从这里发现）
│   └── tools/sync_skills.py        ← 同步 + 校验
└── <repo>/
    └── .workbuddy/skills/<name>/SKILL.md   ← 镜像（git 管理）
```

同步脚本三件事：**统一 CRLF → 写镜像 → 校验 sha256 逐字节相等**。必须**幂等**
（先 `\r\n`→`\n` 再 `\n`→`\r\n` 归一，否则第二次跑会 CRCRLF 或断言炸）。
`shutil.copyfile` 而非文本模式写入（避免平台自动换行二次污染）。

## 3. 两个必踩的坑

### 坑 1：相对链接在双副本下必然一份失效

正本在 `<workspace>/.workbuddy/skills/x/`，镜像在 `<workspace>/<repo>/.workbuddy/skills/x/`，
深度差一层 ⇒ `../../docs/a.md` 在两个位置解析到不同地方。

**解法**：skill 内**不用 Markdown 相对链接**，改成「**相对项目根**」的纯文本路径
（如 `docs/06-development/DEV-04.md`），并在正文里用一行说明"本 skill 内所有路径都相对项目根"。
同级兄弟链接（`../other/SKILL.md`）**是安全的**（两边同层），但也建议统一成纯文本以求逐字节一致。

### 坑 2：`os.path.relpath` 在 Windows 返回反斜杠

任何「按 `/` 写死的字面量」去比 `rel()` 结果的代码（白名单、路径片段匹配）
在 Windows 上会**静默失效** —— 不报错、只是永不命中。

**解法**：加一个归一函数，所有比较都过它：

```python
def norm(p):                      # 相对 ROOT，统一正斜杠
    return os.path.relpath(p, ROOT).replace("\\", "/")
```

必须**双向**归一：写 `referenced.add(norm(target))`，读侧也 `norm(d)`。

## 4. 必须有一条会失败的断言盯着

跨目录复制是隐形契约 —— 光靠注释，几个月后必然漂移。**在仓库审计里加一条**：

```python
canon = os.path.normpath(os.path.join(ROOT, "..", ".workbuddy", "skills"))
if os.path.isdir(canon):                       # 正本不在 = 单独 clone，跳过
    for n in NAMES:
        a, b = canon/n/"SKILL.md", ROOT/".workbuddy/skills"/n/"SKILL.md"
        if sha256(a) != sha256(b): FAIL.append(f"正本≠镜像: {n}")
```

条件化（正本缺失就跳过）是关键：否则把仓库单独 clone 走时审计会红。

## 5. 交付前的验证清单

- [ ] 审计全绿，且**负向测试过**：故意制造一个孤儿/禁用词，确认审计真的会红（证明不是"绿因为废掉"）
- [ ] 幂等：同步脚本连跑两次都退 0
- [ ] 行尾：全仓（含新镜像）逐字节检查，无孤立 LF / 孤立 CR —— **别用 `grep -c $'\r$'`**（shim 下会假绿），用 Python 读 bytes 数 `\r\n`
- [ ] frontmatter：`name` == 目录名；`description` 是**触发条件**（写"当用户说 X / 要 Y 时使用"），长度 < 1024
- [ ] 删旧目录的同时，同步改**审计脚本里的必需件清单**与**所有文档链接**，否则链接检查会红
- [ ] 历史记录（裁定日志、过往报告）里的旧平台字样**不要改** —— 改了就是篡改记录；只加"迁移说明"标注

## 6. 常见反模式

| 反模式 | 问题 |
|---|---|
| 只做镜像不写同步脚本 | 手抄必然漂移 |
| 用软链接代替镜像 | Windows 无权限 / git 存成文本指针 |
| 把 `description` 写成功能说明 | WorkBuddy 靠它做**匹配**，要写触发条件而非能力描述 |
| 删了旧目录但没改审计必需件清单 | 门禁红，且容易被误判成"改脚本弄绿" |
