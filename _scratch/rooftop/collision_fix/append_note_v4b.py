"""向事务记录追加「收尾补记 2」——CRLF 安全（二进制追加）。"""

NOTE = r"I:/工作项目/shellstrom2/.workbuddy/memory/2026-09-21/1631_天台装饰四次修正_花盆花圃碰撞.md"

BLOCK = """
## 收尾补记 2（同会话收尾）

- **反向对照脚本已加锁**：`_scratch/rooftop/collision_fix/flip_blend_policy.py` 会直接改写真实 `.blend`（git 未跟踪、无法回滚），已改成
  「必须显式 `ALLOW_REVERSE_CONTROL=1` 才执行，否则 `REFUSED` + 退出码 2」，并在 docstring 里写明跑完必须从
  `layout.green.before_validator_reverse.blend` 还原。防止日后误跑把正式布局打回 `visual_only`。
- **顺带发现一条环境坑**：`res://` 内的 `.blend` 快照会被 Godot 自动走 scene 导入器 —— 生成 `*.blend.import`、在 `.godot/imported/`
  落一份 `.scn`、并注册一个全局 `uid`（`_scratch/` 下实测共 8 处，含本轮新增的 1 处）。纯 `.before` 后缀不会被导入。
  已把该条补进 `MEMORY-playbooks.md` 的「环境 · 脚本快照纪律」小节（仅作提示，未去批量清理既有 8 处，避免动别的会话的物证）。
"""

with open(NOTE, "rb") as f:
    raw = f.read()

if raw.count(b"\n") - raw.count(b"\r\n") != 0:
    raise SystemExit("ABORT: note is not CRLF-pure")

blob = BLOCK.replace("\n", "\r\n").encode("utf-8")
if "收尾补记 2".encode("utf-8") in raw:
    raise SystemExit("ABORT: already appended (idempotent guard)")
if not raw.endswith(b"\r\n"):
    blob = b"\r\n" + blob

with open(NOTE, "ab") as f:
    f.write(blob)

with open(NOTE, "rb") as f:
    chk = f.read()
assert chk.count(b"\n") - chk.count(b"\r\n") == 0, "lone LF introduced"
print("APPEND_OK bytes %d -> %d" % (len(raw), len(chk)))
