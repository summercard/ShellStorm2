import io

# 1) 当日日志追加「沉淀」
log = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-19.md"
with io.open(log, "ab") as f:
    f.write("""
### 沉淀
- 新建技能 `scene-art-damage-variant-kit`（「模块化构件破损变种 + 随机排布」全链路：端带逐比特锁定 → 每变体一个 MultiMesh → 确定性 seed → 槽位真源探针 → 门禁 / 台账 / 反向对照）。四副本已同步：`SKILL_MIRROR_CHECK_OK skills=26 files=78 copies=3`。
- 记忆：本节细则进 `MEMORY-playbooks.md`「破损变种 3 件 + 随机排布」；`MEMORY.md` 的「资产与命名」加一行硬约定（⚠️ 单 MultiMesh 只装一个 mesh）。
""".replace("\n", "\r\n").encode("utf-8"))
print("log appended")

# 2) MEMORY.md 技能链路补一行
mm = r"I:\工作项目\shellstrom2\.workbuddy\memory\MEMORY.md"
b = open(mm, "rb").read()
old = "- 场景美术 00\u201304；道具武器 05\u201308；关卡设计源 09；镜像走 `skill-mirror-sync`。".encode("utf-8")
assert b.count(old) == 1, b.count(old)
new = "- 场景美术 00\u201304；道具武器 05\u201308；关卡设计源 09；构件破损变种 `scene-art-damage-variant-kit`；镜像走 `skill-mirror-sync`。".encode("utf-8")
open(mm, "wb").write(b.replace(old, new))
print("MEMORY.md patched")
