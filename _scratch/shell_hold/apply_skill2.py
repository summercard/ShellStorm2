# -*- coding: utf-8 -*-
"""skill-mirror-sync 自身的小改进：D 副本无 git ⇒ 用 difflib 判纯增量；改 A 当轮必须同步。"""
import sys

SKILL = r"C:\Users\zhuangmenghong\.workbuddy\skills\skill-mirror-sync\SKILL.md"

OLD = "`removed=0` 说明只补了内容、没丢东西。\n"

NEW = """`removed=0` 说明只补了内容、没丢东西。

⚠️ **D（用户级 Codex）不在任何 git 仓库里** ⇒ 对 D 的落后只能用 difflib 逐行比，`git diff` 够不着：

```bash
python - <<'PY'
import difflib, os
A = r"C:\\Users\\<user>\\.workbuddy\\skills"; B = r"<项目>\\ShellStorm2\\skills_drafts"
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
"""

data = open(SKILL, "rb").read()
o = OLD.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")
n = NEW.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")
found = data.count(o)
if found != 1:
    print("FAIL 命中 %d 处（期望 1）" % found)
    sys.exit(1)
open(SKILL, "wb").write(data.replace(o, n))
chk = open(SKILL, "rb").read()
print("OK   skill-mirror-sync 补丁  crcrlf=%d lone_lf=%d"
      % (chk.count(b"\r\r\n"), chk.count(b"\n") - chk.count(b"\r\n")))
