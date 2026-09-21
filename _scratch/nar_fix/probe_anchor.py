t = open(r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\08_技术施工_剧情触发.md", "rb").read().decode("utf-8").replace("\r\n", "\n")
for cand in [
    "**结论（影响范围，请作者知悉）**：`08` 旧版 §9 承诺的三条垂直切片里，\n",
    "**结论（影响范围，请作者知悉）**",
    "`08` 旧版 §9 承诺的三条垂直切片里",
    "三条垂直切片里",
]:
    print(repr(cand[:40]), "->", t.count(cand))
line = [l for l in t.split("\n") if "影响范围" in l][0]
print("LINE repr:", repr(line[:60]))
print("TARGET repr:", repr("**结论（影响范围，请作者知悉）**：`08` 旧版 §9 承诺的三条垂直切片里，"))
