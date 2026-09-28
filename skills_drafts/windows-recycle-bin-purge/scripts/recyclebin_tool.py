# -*- coding: utf-8 -*-
"""Windows 回收站审计 / 清空 / 核验三合一工具（无第三方依赖）。

用法:
  python recyclebin_tool.py scan  [-o 报告路径]   # 只读审计，出报告
  python recyclebin_tool.py purge                # 调 SHEmptyRecycleBinW 逐盘清空（不可逆）
  python recyclebin_tool.py verify               # 列出残余条目（盘/SID/原路径/大小/删除时间）

关键事实（踩过的坑）:
* $I 元数据布局 (version=2):
    0x00 i32 version | 0x08 i64 逻辑大小 | 0x10 i64 删除时间(FILETIME)
    0x18 i32 路径字符数 | 0x1C UTF-16LE 原路径
  → 路径偏移是 **0x1C**，从 0x18 起解会得到单字符垃圾；FILETIME 要减 116444736000000000 再除 1e7。
* SHEmptyRecycleBinW(hwnd, root, flags) 是官方清空接口；带 SHERB_NOCONFIRMATION|
  NOPROGRESSUI|NOSOUND=0x7。它是**异步**的：返回 S_OK 后后台仍在删，别立刻下结论。
* 该 API 只清当前用户 SID；别的 SID 目录（含 2019 年那种历史账户残留）需要管理员权限。
* E:/G:/H: 这类（无回收站配置 / 纯空盘）调用会抛 OSError(22, '灾难性故障', -2147418113)，
  属正常现象，不是脚本 bug。
* 拦截式沙箱里 os.remove 会被改成"移到回收站"，清回收站要用 kernel32.DeleteFileW 兜底。
* 清空的**必须在资源管理器里肉眼复核**，不要只信脚本计数。
"""
import os
import sys
import time
import struct
import ctypes
import argparse
import datetime
import collections

FILETIME_EPOCH_OFFSET = 116444736000000000
SHERB_NOCONFIRMATION = 0x00000001
SHERB_NOPROGRESSUI = 0x00000002
SHERB_NOSOUND = 0x00000004


def drives_with_bin():
    try:
        mask = ctypes.windll.kernel32.GetLogicalDrives()
        cand = [chr(65 + i) + ":\\" for i in range(26) if (mask >> i) & 1]
    except Exception:
        cand = [c + ":\\" for c in "CDEFGHIJKLMNOPQRSTUVWXYZ"]
    return [d for d in cand if os.path.isdir(os.path.join(d, "$Recycle.Bin"))]


def human(n):
    if n is None or n < 0:
        return "?"
    f = float(n)
    for u in ["B", "KB", "MB", "GB", "TB"]:
        if f < 1024:
            return "%.1f %s" % (f, u)
        f /= 1024
    return "%.1f PB" % f


def parse_meta(data):
    if len(data) < 32:
        return None
    size = struct.unpack_from("<q", data, 8)[0]
    ft = struct.unpack_from("<q", data, 16)[0]
    plen = struct.unpack_from("<i", data, 24)[0]
    raw = data[28:]
    if 0 < plen * 2 <= len(raw):
        path = raw[:plen * 2].decode("utf-16-le", errors="replace")
    else:
        path = raw.decode("utf-16-le", errors="replace").split("\x00")[0]
    dt = None
    if ft and ft > 0:
        try:
            dt = datetime.datetime.fromtimestamp((ft - FILETIME_EPOCH_OFFSET) / 1e7)
        except Exception:
            dt = None
    return (size if size > 0 else 0), dt, path


def walk_items():
    """遍历所有盘有余回收站 -> [(drive, sid, logical_size, ondisk_size, dt, path)]"""
    items = []
    for d in drives_with_bin():
        rb = os.path.join(d, "$Recycle.Bin")
        try:
            sids = os.listdir(rb)
        except Exception:
            continue
        for sid in sids:
            sd = os.path.join(rb, sid)
            if not os.path.isdir(sd):
                continue
            try:
                names = os.listdir(sd)
            except Exception:
                continue
            for nm in names:
                if not nm.startswith("$I"):
                    continue
                full = os.path.join(sd, nm)
                try:
                    meta = parse_meta(open(full, "rb").read())
                except Exception:
                    continue
                if not meta:
                    continue
                size, dt, path = meta
                rpath = os.path.join(sd, "$R" + nm[2:])
                try:
                    osz = os.path.getsize(rpath) if os.path.exists(rpath) else -1
                except Exception:
                    osz = -1
                items.append((d, sid, size, osz, dt, path))
    return items


def count_i():
    n = 0
    for d in drives_with_bin():
        rb = os.path.join(d, "$Recycle.Bin")
        for sid in os.listdir(rb):
            sd = os.path.join(rb, sid)
            if os.path.isdir(sd):
                try:
                    n += len([x for x in os.listdir(sd) if x.startswith("$I")])
                except Exception:
                    pass
    return n


def cmd_scan(out_path):
    items = walk_items()
    L = []
    w = L.append
    w("=== 回收站只读审计 (%s) ===" % time.strftime("%Y-%m-%d %H:%M"))
    w("")
    agg = collections.OrderedDict()
    for d, sid, size, osz, dt, path in items:
        a = agg.setdefault(d, [0, 0, 0])
        a[0] += 1
        a[1] += size
        a[2] += osz if osz >= 0 else 0
    w("[按盘]")
    w("盘符\t条目数\t逻辑大小\t实际占用")
    for k, v in agg.items():
        w("%s\t%d\t%s\t%s" % (k, v[0], human(v[1]), human(v[2])))
    w("合计\t%d\t%s\t%s" % (len(items),
                            human(sum(i[2] for i in items)),
                            human(sum(i[3] for i in items if i[3] >= 0))))
    w("")
    agg2 = collections.OrderedDict()
    for d, sid, size, osz, dt, path in items:
        a = agg2.setdefault(sid, [0, 0])
        a[0] += 1
        a[1] += size
    w("[按所有者 SID]")
    for k, v in sorted(agg2.items(), key=lambda x: -x[1][1]):
        w("%s\t%d\t%s" % (k, v[0], human(v[1])))
    w("")
    now = datetime.datetime.now()
    bkt = collections.Counter()
    bsz = collections.Counter()
    for d, sid, size, osz, dt, path in items:
        if not dt:
            k = "未知"
        else:
            days = (now - dt).days
            k = ("24小时内" if days <= 1 else "1-7天" if days <= 7 else
                 "8-30天" if days <= 30 else "31-365天" if days <= 365 else "1年以上")
        bkt[k] += 1
        bsz[k] += size
    w("[按删除时间]")
    for k in ["24小时内", "1-7天", "8-30天", "31-365天", "1年以上", "未知"]:
        if bkt[k]:
            w("%s\t%d\t%s" % (k, bkt[k], human(bsz[k])))
    w("")
    w("[体积 TOP 20]")
    for it in sorted(items, key=lambda x: -x[2])[:20]:
        d = it[4].strftime("%Y-%m-%d %H:%M") if it[4] else "?"
        w("%10s  %-16s  %s" % (human(it[2]), d, it[5]))
    w("")
    topdir = collections.Counter()
    for it in items:
        parts = it[5].replace("/", "\\").split("\\")
        topdir["\\".join(parts[:4]) if len(parts) >= 4 else it[5]] += it[2]
    w("[来源目录 TOP 15]")
    for k, v in topdir.most_common(15):
        w("%10s  %s" % (human(v), k))
    txt = "\n".join(L)
    txt = "".join(ch if ch in "\t\n" or ord(ch) >= 32 else " " for ch in txt)
    if out_path:
        open(out_path, "w", encoding="utf-8").write(txt)
        print("报告已写入: %s" % out_path)
    print(txt)


def cmd_purge():
    print("=== 清空回收站 (不可逆) %s ===" % time.strftime("%H:%M:%S"))
    before = count_i()
    print("清空前 $I 条目数: %d" % before)
    shell32 = ctypes.windll.shell32
    shell32.SHEmptyRecycleBinW.restype = ctypes.HRESULT
    shell32.SHEmptyRecycleBinW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint32]
    flags = SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND
    for d in drives_with_bin():
        try:
            hr = shell32.SHEmptyRecycleBinW(None, d, flags)
            print("  API %s -> 0x%08X (%s)" % (d, hr & 0xFFFFFFFF, "OK" if hr >= 0 else "失败"))
        except Exception as e:
            print("  API %s -> 异常 %r" % (d, e))
    # 异步：等后台删完再统计
    for _ in range(30):
        time.sleep(2)
        n = count_i()
        if n == 0:
            break
    print("清空后 $I 条目数: %d" % count_i())
    print("提示：SHEmptyRecycleBinW 是异步的，且只清当前用户 SID；残余请 verify 后处理。")


def cmd_verify():
    items = walk_items()
    if not items:
        print("回收站已空。")
        return
    print("残余 %d 条：" % len(items))
    for d, sid, size, osz, dt, path in sorted(items, key=lambda x: x[0]):
        t = dt.strftime("%Y-%m-%d %H:%M") if dt else "?"
        print("  %s [%s] %10s  %s  %s" % (d, sid[:20], human(size), t, path))


def main():
    ap = argparse.ArgumentParser(description="Windows 回收站审计/清空/核验")
    ap.add_argument("cmd", choices=["scan", "purge", "verify"])
    ap.add_argument("-o", "--out", default=None, help="scan 报告输出路径")
    a = ap.parse_args()
    {"scan": lambda: cmd_scan(a.out), "purge": cmd_purge, "verify": cmd_verify}[a.cmd]()


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    main()
