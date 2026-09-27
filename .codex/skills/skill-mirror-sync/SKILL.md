---
name: skill-mirror-sync
description: 把 ~/.workbuddy/skills（唯一正本）全量镜像到项目内 skills_drafts、项目 .codex/skills、用户级 ~/.codex/skills 三处副本，并校验逐文件 sha256 一致与 CRLF 行尾纯度。用于「skill 改了要同步到各处 / 四副本是否一致 / 副本缺哪个 skill / 行尾被谁改乱了」这类问题。不用于 skill 内容本身的编写与评审。
agent_created: true
---

# skill 四副本镜像同步

## 唯一正本

`~/.workbuddy/skills/`（下称 A）。其余三处都是副本 —— **任何内容改动只在 A 做，然后向下同步**。

| 代号 | 路径 | 性质 |
|---|---|---|
| A | `C://Users//zhuangmenghong//.workbuddy//skills` | **正本 / 唯一真源** |
| B | `I://工作项目//shellstrom2//ShellStorm2//skills_drafts` | 项目内草稿区 |
| C | `I://工作项目//shellstrom2//ShellStorm2//.codex//skills` | 项目 Codex 技能区 |
| D | `C://Users//zhuangmenghong//.codex//skills` | 用户级 Codex 技能区 |

## 用法

```bash
python scripts/sync_skill_mirrors.py --sync    # 以 A 为准全量重建 B/C/D
python scripts/sync_skill_mirrors.py --check   # 只读校验
```

`--sync` 对 A 拥有的每个 skill：先 `rmtree` 目标目录再整树复制，**杜绝残留旧文件**；排除 `__pycache__`。

⛔ **本机（Windows + Safe-Delete 守卫）不要跑 `--sync`**：守卫会拦下 `rmtree` 的 trash 操作，
`--sync` 会在**中途**抛 `OSError: [safe-delete] 操作失败: ... Some operations were aborted`，
而**已经 rmtree 掉的目录不会被重建** —— 2026-09-21 实测把 `skills_drafts/game-character-model-pipeline`
整目录删空（含 `SKILL.md` / `agents/` / `references/`），必须从 A 手动 `cp` 补回并逐文件校验 sha256。

本机替代流程（等效且安全，只增不删）：

```bash
A="C:/Users/<user>/.workbuddy/skills"; B="<项目>/skills_drafts"; C="<项目>/.codex/skills"; D="C:/Users/<user>/.codex/skills"
for t in "$B" "$C" "$D"; do mkdir -p "$t/<skill>" && cp -rf "$A/<skill>/." "$t/<skill>/"; done
sha256sum "$A/<skill>/SKILL.md" "$B/<skill>/SKILL.md" "$C/<skill>/SKILL.md" "$D/<skill>/SKILL.md"  # 四行必须同哈希
python scripts/sync_skill_mirrors.py --check                                                       # --check 只读，安全
```

⚠️ `cp -rf "$A/<skill>/." "$t/<skill>/"` 会把 A 里的 `scripts/__pycache__/*.pyc` **一并带过去**（`--sync` 原本会排除它）⇒ 复制后清一次副本里的 `__pycache__`：**只删 `.pyc` 再 `os.rmdir` 空目录，别整目录 rmtree**（守卫同样会拦它，且可能留下半删状态）。
⚠️ 替代流程做的是「覆盖 + 补齐」，**不清理副本里的多余文件**。若某个 skill 在 A 里删过文件，副本会留下孤儿文件 ⇒ 那种情况要人工删副本里的孤儿（单独删那一个文件，别整目录 rmtree）。

⚠️ **不要把临时文件写进 skill 目录（`~/.workbuddy/skills/<name>/`）。** 那里是正本，
任何临时日志都会被当成 skill 内容同步到 B/C/D —— 实测把 `_sync.log` 重定向进
`skill-mirror-sync/` 后，`--check` 立刻报 `diff=['skill-mirror-sync/_sync.log', ...]`
外加 `A has 1 non-CRLF file(s)`。临时输出一律落在 skill 目录**之外**（如 `%TEMP%` 或项目
`_scratch/`）；若已写进去，从 A 删掉再跑一次 `--sync` 即可用全量重建清掉副本里的残留。

## 判据

- 每个 skill 的全部文件 sha256 与 A 逐字节相同
- 行尾全为 CRLF（无 lone LF、无 bare CR）
- 退出码 0 = 一致；1 = 有差异

## 新增 skill

1. 内容写在 A 里（`~/.workbuddy/skills/<name>/`）。目录名必须与 SKILL.md 的 `name:` 完全一致。
2. **先过行尾关再同步**：`--check` 要求 A 里**每个文件**都是 CRLF —— 包括 `assets/*.json`、`references/*.md`、`scripts/*.py`。用别的工具生成的模板常是 LF，不转就 `SKILL_MIRROR_CHECK_FAIL ... A has N non-CRLF file(s)`。
3. 跑 `--sync`，再跑 `--check`。`--sync` 会 `rmtree` 重建，所以新 skill 的副本一定干净。

若 skill 原本只存在于**项目级** `{workspace}/.workbuddy/skills/`，那处不在这四副本里、也不由本脚本管理 —— 要推广到各处，必须先把目录复制进 A，再 `--sync`。

## 改名 skill 的坑

`--sync` 只按「A 当前拥有的名字」写入，**从不删副本里的多余目录**；`--check` 也只遍历 A 的名字，**不会报告副本里多出来的旧目录**。所以给 skill 改名（例如加 `00-` 前缀）后：

- A 里的旧名目录要自己删；
- B/C/D 里若曾同步过旧名，旧名目录会**静默留存**，改完必须人工核对目录清单，别只看 `--check` 的 OK。

改名后要同步改的位置：目录名、SKILL.md 的 `name:`、以及所有引用该 skill 名字的地方（其他 skill 的路由表、项目文档、交付 zip）。

## 顺便发现：副本落后于正本

`--sync` 是全量重建，会把**所有** skill 的最新内容带过去，包括与本次任务无关的。若某副本此前落后，事后 `git diff` 会看到它的改动 —— 属正常补齐，不是误改。可先确认是纯增量：

```bash
git diff --unified=0 -- <copy>/<skill>/SKILL.md | grep -E '^[-+][^-+]' | awk '{substr($0,1,1)=="+"?a++:d++} END{print "added="a" removed="d}'
```

`removed=0` 说明只补了内容、没丢东西。

⚠️ **D（用户级 Codex）不在任何 git 仓库里** ⇒ 对 D 的落后只能用 difflib 逐行比，`git diff` 够不着：

```bash
python - <<'PY'
import difflib, os
A = r"C:\Users\<user>\.workbuddy\skills"; B = r"<项目>\ShellStorm2\skills_drafts"
for s in ["<skillA>", "<skillB>"]:          # 也可换成「--check 输出里报 diff 的那些」
    ta = open(os.path.join(A, s, "SKILL.md"), encoding="utf-8").read().splitlines()
    tb = open(os.path.join(B, s, "SKILL.md"), encoding="utf-8").read().splitlines()
    d = [l for l in difflib.unified_diff(tb, ta, lineterm="", n=0)
         if l[:1] in "+-" and l[:3] not in ("+++", "---")]
    print(s, "add=%d rem=%d" % (sum(l[0] == "+" for l in d), sum(l[0] == "-" for l in d)))
PY
```

`rem=0`（或 rem 仅为同一行被**改写**的 description）⇒ 纯补齐，可放心覆盖。

⛔ **改完 A 必须当轮同步**：2026-09-22 实测 `godot-runtime-probe` 与 `godot-verification-suite-triage`
的副本分别落后正本 `+13/-0` 与 `+59/-1` 行 —— 都是**上一轮改了 A 却没同步**留下的。
副本落后不会自己报警，只会在下次 `--check` 时冒出来；`--check` 一旦是红的，
「本次改动是否已同步」这个判断就失效了（红里混着历史欠账）⇒ 改完就同步，让 `--check` 保持 0。

## 「整目录缺失」的真凶：A 里那件是 LF

`--check` 报 `!! <copy> missing skills: [...]` + 同时 `A has N non-CRLF file(s)` 时，
**两件事其实是同一件**：那批 skill 在 A 里是 LF 行尾，行尾关长期拦着它们，
于是历史上每次同步都被跳掉 ⇒ 副本里从来没出现过。2026-09-27 实测 4 个 skill
（`doc-coverage-audit` / `git-remote-credential-triage` / `windows-cli-tool-provisioning` /
`workbuddy-skill-workspace-mirror`）就是这样静默缺了很久。

⇒ **别只盯着 `diff=` 看**：`miss=`（缺文件）与 `missing skills`（缺目录）同样要追到底，
先按 §新增 skill 第 2 步把行尾转了，再同步，一次性补齐。

## 工作区级正本不在四副本内

若工作区根 ≠ 仓库根（如 workspace=`I:\...\shellstrom2`、repo=`...\ShellStorm2`），
还存在 `<workspace>/.workbuddy/skills/` —— 那是 **WorkBuddy 真正发现 skill 的地方**，
但**不在本脚本的 A/B/C/D 四副本里，本脚本管不到它**（见 `workbuddy-skill-workspace-mirror`）。

⇒ 改完 A 要**单独回灌**一次：把 A 里同名的项目 skill 覆盖过去并逐文件校验 sha256。
否则 `--check` 全绿，WorkBuddy 在本项目里跑的却还是旧版。实测 02/04 曾落后 A 各 29/20 行。
方向判定：以 A 为准（比 mtime + diff：`add>0 / rem=0` 就是纯补齐，可放心覆盖）。

### 回灌脚本（常驻）

`scripts/sync_workspace_skills.py` 专管 A→W：

```bash
python scripts/sync_workspace_skills.py --check                        # 只读校验（W 现有 skill）
python scripts/sync_workspace_skills.py --sync                         # 以 A 为准回灌 W 现有 skill
python scripts/sync_workspace_skills.py --sync --add NAME [NAME ...]   # 顺带把 A 里的 NAME 拉进 W
```

默认**只处理 W 里已存在的 skill**，不会把 A 的 38 个全灌进去；要扩面必须显式 `--add`
（2026-09-27 首次扩面：W 由 5 个战局房间 skill 增至 **11 个** = 00–04 战局房间链路 + 场景制作 6 件）。
脚本逐文件 sha256 比对、`shutil.copyfile` 字节复制（不做文本模式写入，杜绝换行二次污染）、
顺手清副本 `__pycache__`（只删 `.pyc` 再 rmdir）；并断言 **A 侧行尾必须 CRLF**。退出码 0 = 一致。

⚠️ **这条约定会被反复违反，别信「上次刚同步过」。** 2026-09-27 当天两次踩坑：15:45 刚回灌过 02/04，
同日 23:51 又发现 **02/03/04** 落后于 A（A 侧是当天 19:59 新落的 `ROOM_FRAME` /
`room_local_transform = inverse(ROOM_FRAME_world) @ source_instance_world_transform` 契约，W 侧还是旧表述），
根因是中间 16:07 / 19:59 两次改 A 都没回灌。⇒ **凡本轮改了 A 里任何 W 已有的 skill，收尾必须跑一次 `--sync`**，
让 `--check` 保持在 0；否则 `--check` 一旦是红的，「本次改动是否已同步」这个判断就失效了（红里混着历史欠账）。

## 边界

- **绝不反向**：不从副本同步回 A。副本行尾被污染时，修副本、不修 A。
- **不删副本里 A 没有的 skill**：D 中另有若干其他项目的 skill（`match3-ui-art-qa`、`wechat-minigame-submission`、`sausage-character-asset-maker` 等），不属于本套，保留不动。
- A 根部的 `.disable_to_model_invocation_migration.json` / `.model_invocation_to_override_migration.json` 是 WorkBuddy 引擎标记文件，**不是 skill，不参与同步**。
- 副本本来就是子集，**不要假设到处都有某个 skill** —— 这正是本 skill 存在的原因。
