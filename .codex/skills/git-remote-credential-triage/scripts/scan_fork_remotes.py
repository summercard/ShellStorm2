import os, re, configparser, sys

toml = r"C:\Users\zhuangmenghong\AppData\Local\ForkData\repositories.toml"
paths = re.findall(r"path = '(.*?)'", open(toml, encoding="utf-8").read())

print(f"共 {len(paths)} 个仓库\n")
print(f"{'协议':<6} {'远程地址':<58} 路径")
print("-" * 140)

ssh_cnt = https_cnt = none_cnt = 0
for p in paths:
    cfg = os.path.join(p, ".git", "config")
    if not os.path.isfile(cfg):
        continue
    cp = configparser.RawConfigParser()
    try:
        cp.read(cfg, encoding="utf-8")
    except Exception as e:
        print(f"?? 解析失败 {p}: {e}")
        continue
    remotes = []
    for sec in cp.sections():
        if sec.startswith('remote "') and cp.has_option(sec, "url"):
            remotes.append(cp.get(sec, "url"))
    if not remotes:
        none_cnt += 1
        continue
    for url in remotes:
        if url.startswith("git@") or url.startswith("ssh://"):
            proto = "SSH"
            ssh_cnt += 1
        elif url.startswith("http"):
            proto = "HTTPS"
            https_cnt += 1
        else:
            proto = "OTHER"
        print(f"{proto:<6} {url:<58} {p}")

print("-" * 140)
print(f"\nSSH 远程 {ssh_cnt} 个 / HTTPS 远程 {https_cnt} 个 / 无远程 {none_cnt} 个")
