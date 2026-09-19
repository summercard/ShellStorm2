target = r"I:\工作项目\shellstrom2\.workbuddy\memory\MEMORY.md"

anchor = "- 门扇 / 门墙 / L 墙角 / 天台女儿墙的几何、朝向口径、原点契约、导出纪律 → playbooks。\r\n"
add = "- 天台女儿墙有**破损变种 3 件**（`ENV-ROOFTOP-REF-PARAPET-DMG-A/B/C` = 崩顶/贯穿/塌脚，约 1/4 随机排布，仅直段）；⚠️ **单 MultiMesh 只能装一个 mesh** → 变体排布 = 「完好 1 + 每变体 1」共 4 个 MultiMeshInstance3D；「能接起来」判据 = 端带 `|x|>=2.05m` 与直段逐比特一致。见 playbooks。\r\n"

with open(target, "rb") as f:
    b = f.read()
assert b.count(anchor.encode("utf-8")) == 1, b.count(anchor.encode("utf-8"))
b = b.replace(anchor.encode("utf-8"), (anchor + add).encode("utf-8"))
with open(target, "wb") as f:
    f.write(b)
print("ok crlf=", b.count(b"\r\n"), "lone=", b.count(b"\n") - b.count(b"\r\n"))
