import json, collections, sys
txt = open(sys.argv[1], encoding="utf-8").read()
i = txt.find("{")
data, _ = json.JSONDecoder().raw_decode(txt[i:])
def walk(node):
    if isinstance(node, dict):
        if isinstance(node.get("kind"), str):
            yield node
        for v in node.values():
            yield from walk(v)
    elif isinstance(node, list):
        for x in node:
            yield from walk(x)
issues = list(walk(data))
print("total issues:", len(issues))
for k, v in collections.Counter(x["kind"] for x in issues).most_common():
    print("  %-44s %d" % (k, v))
print()
print("== 与天台/女儿墙相关的条目 ==")
n=0
for x in issues:
    s = json.dumps(x, ensure_ascii=False)
    if any(k in s for k in ("rooftop","ROOFTOP","parapet","PARAPET","女儿墙")):
        n+=1; print("  ", s[:200])
print("  count =", n)
