import io
SKILL = r"C:\Users\zhuangmenghong\.workbuddy\skills\10-narrative-timeline-authoring\SKILL.md"
raw = open(SKILL, "rb").read().decode("utf-8")
text = raw.replace("\r\n", "\n")
print("CRLF:", "\r\n" in raw)
print("LF:", text.count("\n"))

cands = [
    "**用户如果要求",
    '**用户如果要求"击败某个 Boss 后演一段"**',
    '**用户如果要求"击败某个 Boss 后演一段"**：',
    "\[\] ",
    "如实说明当前买不到这个事实",
    "**不要假装已经支持**",
    '打任何 Boss 都触发"的错误行为。',
]
for c in cands:
    print("count=%d :: %r" % (text.count(c), c))

# dump the raw bytes of line 247 (1-based) to see quote chars
lines = text.split("\n")
for i, ln in enumerate(lines, 1):
    if "击败某个 Boss" in ln:
        print("--- line %d repr ---" % i)
        print(repr(ln))
