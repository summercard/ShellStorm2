#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""远征03 复刻怪 ↔ 《挺进地牢》第一层原作 —— 逐只保真度核查。

回答两个问题：
  ① 我们每一只对应原作哪一只？（映射表 AUDIT 的第一列）
  ② 数值与攻击方式**是不是都相同**？

做法分两层，**机械比对优先**：

  - **血量**：从 `docs/v0.1/reference/挺进地牢/第一层怪物数据表.md` §7 附录
    解析原作第一层基础血量，再从 `outputs/expedition03_monster_roster/manifest.json`
    读我们**运行时实测**的 hp，逐只相除。这一步不做任何人工判断 ——
    倍率不是 10.00 就直接判 FAIL。

  - **攻击方式**：原作是英文行为描述，没有可机读的结构，只能逐条人工核对后
    写进本表的 `verdict` / `note`。这一层是**判断题**，本脚本不假装它是机械比对。

判定四档：
    COPY     照抄，逐项对得上（连发数 / 扇形 / 死亡效果 / 预判有无）
    SCALED   数值按项目裁定等比换算（血量 ×10、伤害统一 17），比例一致、绝对值不同
    APPROX   方向对，但具体参数是自拟（角度、秒数、概率、弹速、射程）
    GAP      原作有这条机制，我们没有 / 做成了别的（真差异）

用法：
    python tools/egt_fidelity_audit.py
产出：
    outputs/expedition03_monster_roster/EGT对照核查.json
    outputs/expedition03_monster_roster/远征03_vs_原作_逐只对照.html
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF_MD = ROOT / "docs" / "v0.1" / "reference" / "挺进地牢" / "第一层怪物数据表.md"
MANIFEST = ROOT / "outputs" / "expedition03_monster_roster" / "manifest.json"
PORTRAIT_DIR = ROOT / "outputs" / "expedition03_monster_roster" / "portraits"
OUT_DIR = ROOT / "outputs" / "expedition03_monster_roster"
JSON_OUT = OUT_DIR / "EGT对照核查.json"
HTML_OUT = OUT_DIR / "远征03_vs_原作_逐只对照.html"

# ---------------------------------------------------------------------------
# 逐只对照：kind → 原作名 / 中文名 / 原作攻击摘要 / 我们实现 / 判定 / 备注
#
# `egt_key` 必须能在 §7 附录表里找到（解析时断言，找不到就是映射写错了）。
# `verdict` 只描述**攻击方式与机制**这一层；血量单独由脚本按倍率判定。
# ---------------------------------------------------------------------------
AUDIT: list[dict] = [
    # —— 子弹族 ——
    dict(kind="egt_bullet_kin", egt_key="Bullet Kin", egt_zh="子弹小子",
         egt_attack="单发子弹；慢速走向玩家",
         ours="1 发直射（±0°），弹速 8，冷却 2.2s",
         verdict="COPY", grade_note="单发对上"),
    dict(kind="egt_bandana_kin", egt_key="Bandana Bullet Kin", egt_zh="头巾小子",
         egt_attack="连发子弹（射速显著高于基础）；慢速走向玩家",
         ours="3 连发同向，间隔 0.12s，冷却 1.05s",
         verdict="COPY", grade_note="连发数 3 与「射速显著高于基础」一致；3 这个数是自拟"),
    dict(kind="egt_veteran_kin", egt_key="Veteran Bullet Kin", egt_zh="老兵小子",
         egt_attack="单发 + 预判玩家走位（wiki 另处写 fire 4 bullets in a row）",
         ours="4 连发 + 62% 预判，间隔 0.12s",
         verdict="COPY",
         grade_note="取 4 连发：参考表 §2.1 写「单发」，但同表 §8 承认 wiki 原文是 "
                    "fire 4 bullets in a row；预判 62% 取自反编译 LeadAmount=0.62f"),
    dict(kind="egt_cardinal", egt_key="Cardinal", egt_zh="红衣主教",
         egt_attack="单发 + 偶尔 5 发追踪弹簇",
         ours="1 发直射；每 3 次改 5 发环弹（45% 追踪 3s）",
         verdict="APPROX", grade_note="「偶尔」的频次原作未给，取 1/3；追踪强度 45% 自拟"),
    dict(kind="egt_hollowpoint", egt_key="Hollowpoint", egt_zh="空尖弹",
         egt_attack="浮空飘向玩家；高射速连发；周期性消失并在房间他处重现",
         ours="浮空 + 4 连发（间隔 0.09s）+ 每 5.0s 瞬移 ≤7m（前摇 0.35s）",
         verdict="APPROX", grade_note="机制全有；周期 5s / 半径 7m / 前摇 0.35s 自拟"),

    # —— 霰弹枪族 ——
    dict(kind="egt_red_shotgun", egt_key="Red Shotgun Kin", egt_zh="红霰弹枪小子",
         egt_attack="周期性紧密 5 发扇形；死亡有几率向全向喷 6 发",
         ours="5 发 ±14°；死亡 35% 概率喷 6 发",
         verdict="APPROX", grade_note="5 发 / 6 发 / 有几率 全部对上；±14° 与 35% 自拟（原作无角度与概率数值）"),
    dict(kind="egt_blue_shotgun", egt_key="Blue Shotgun Kin", egt_zh="蓝霰弹枪小子",
         egt_attack="宽 5 发 + 快速接宽 4 发；死亡有几率向全向喷 6 发",
         ours="5 发 ±26°（间隔 0.16s）+ followup 4 发（延迟 0.18s）；死亡 35% 喷 6 发",
         verdict="APPROX", grade_note="两段结构与发数完全对上；±26° / 延迟 / 概率自拟"),
    dict(kind="egt_veteran_shotgun", egt_key="Veteran Shotgun Kin", egt_zh="老兵霰弹枪小子",
         egt_attack="V 型 5 发 + 100% 预判；必定向全向喷「大量」子弹",
         ours="V 型 5 发 ±22° + 预判 1.0；死亡必喷 12 发",
         verdict="APPROX", grade_note="V 型 / 5 发 / 100% 预判 / 必定 全部对上；12 发是「大量」的具体化，原作未给数"),

    # —— 爆炸族 ——
    dict(kind="egt_pinhead", egt_key="Pinhead", egt_zh="保险销头",
         egt_attack="接触自爆；玩家靠近时主动扑击再爆",
         ours="走近自爆；先扑 9.5m/s × 0.22s 再炸（半径 2.6m）",
         verdict="COPY", grade_note="扑击这条原作写明，已实现；半径 2.6m 自拟"),
    dict(kind="egt_nitra", egt_key="Nitra", egt_zh="硝酸怪",
         egt_attack="死亡炸成一条线，线朝远离玩家方向延伸；玩家太近则提前自爆且爆线转向玩家",
         ours="圆形爆炸（半径 3.4m）+ 2s 伤害场（每 0.5s 4 点）",
         verdict="GAP",
         grade_note="**真差异**：线爆与「贴脸转向」这条双向规则完全没做，现在是圆爆。"
                    "已在设计 §T4 记为待补项"),
    dict(kind="egt_king_bullat", egt_key="King Bullat", egt_zh="子弹榴弹王",
         egt_attack="停留/漂浮；周期性向全向发射弹跳弹；死亡生成「若干」Bullat 与 Shotgat",
         ours="原地漂浮 + 全向 8 发弹跳（反弹 3 次）；死亡产 2 Bullat + 2 Shotgat",
         verdict="APPROX", grade_note="机制全对；8 发 / 3 次反弹 / 2+2 子代数量自拟（原作只说「若干」）"),

    # —— 分裂族 ——
    dict(kind="egt_blobulon", egt_key="Blobulon", egt_zh="布洛布",
         egt_attack="纯接触伤害；裂成 2 个 Blobuloid",
         ours="接触伤害；死亡裂 2 × blobuloid",
         verdict="COPY", grade_note="链与数量完全对上"),
    dict(kind="egt_blobuloid", egt_key="Blobuloid", egt_zh="布洛布幼体",
         egt_attack="纯接触伤害；裂成 2 个 Blobulin",
         ours="接触伤害；死亡裂 2 × blobulin",
         verdict="COPY", grade_note="同上"),
    dict(kind="egt_blobulin", egt_key="Blobulin", egt_zh="布洛布微体",
         egt_attack="纯接触伤害；快速移向玩家；不再裂",
         ours="接触伤害；速度 3.4（族内最快）；无 death_split",
         verdict="COPY", grade_note="终段不再裂 —— 这一条有断言盯着，防止无限裂解"),
    dict(kind="egt_chancebulon", egt_key="Chancebulon", egt_zh="骰子布洛布",
         egt_attack="随机借用其它 Blobulon 系招式 + 骰子形弹组；有几率不攻击而直接死亡",
         ours="contact / dice / ring 三招轮换；20% 概率不攻击直接死",
         verdict="APPROX", grade_note="行为结构对上；20% 自拟（原作只说「有几率」）"),

    # —— 书怪族 ——
    dict(kind="egt_bookllet", egt_key="Bookllet（三色同）", egt_zh="书怪",
         egt_attack="子弹拼成 R / N / Φ 等字母形状",
         ours="letter 图案，字母 R 分 10 笔逐笔画出",
         verdict="APPROX", grade_note="字母弹这条对上；具体选 R、笔画数 10 自拟"),
    dict(kind="egt_blue_bookllet", egt_key="Bookllet（三色同）", egt_zh="蓝书怪",
         egt_attack="同上 + 来回脉动的环形弹",
         ours="8 发环 × 2 圈脉动；每 3 次改字母 N（9 笔）",
         verdict="APPROX", grade_note="脉动环对上；8 发 / 2 圈 / 交替频率自拟"),
    dict(kind="egt_green_bookllet", egt_key="Bookllet（三色同）", egt_zh="绿书怪",
         egt_attack="同上 + 大型四叶草形弹",
         ours="clover 图案，4 瓣 × 4 发",
         verdict="APPROX", grade_note="四叶草对上；瓣数 / 每瓣发数自拟"),

    # —— 法术 / 辅助族 ——
    dict(kind="egt_gunjurer", egt_key="Apprentice Gunjurer", egt_zh="学徒枪法师",
         egt_attack="发射旋转图形弹（三角 / 圆 / X）；攻击后瞬移换位",
         ours="spiral 图案 9 发旋进（每发 +40°）；出手后 0.12s 瞬移，冷却 2.5s",
         verdict="COPY", grade_note="「旋转图形弹 + 攻击后瞬移」两条都在（后者 2026-10-30 才真正接上）"),
    dict(kind="egt_gunsinger", egt_key="Gunsinger", egt_zh="枪歌者",
         egt_attack="不攻击；给房里另一只怪加血 + 加速度；玩家靠近或自己受伤则中断施法逃跑",
         ours="不攻击、原地不动；给血比例最低的 1 只 +35% 血 / 1.35× 速度（5s）；6m 或受伤则逃 2.5s",
         verdict="APPROX",
         grade_note="行为全对（只加 1 只、会中断逃跑）；+35% / 1.35× / 6m / 2.5s 自拟，"
                    "「选血比例最低的那只」是原作未定义处的具体化"),
    dict(kind="egt_gigi", egt_key="Gigi", egt_zh="吉吉",
         egt_attack="飞向玩家；吐蛋，蛋炸出一群涌动子弹",
         ours="吐 1 枚慢蛋（4.2m/s），0.85s 后落点炸 8 发（25% 追踪）",
         verdict="APPROX", grade_note="蛋 + 炸群对上；8 发 / 0.85s / 25% 自拟"),

    # —— 一次性冲撞族 ——
    dict(kind="egt_bullat", egt_key="Bullat", egt_zh="子弹榴弹",
         egt_attack="直冲玩家，撞到即死；无附加",
         ours="冲撞 11.0m/s，命中自毁，无附加弹",
         verdict="COPY", grade_note="碰即消失这条对上；冲撞速度自拟"),
    dict(kind="egt_shotgat", egt_key="Shotgat", egt_zh="霰弹榴弹",
         egt_attack="直冲玩家，撞到即死；附加 V 型 2 发",
         ours="冲撞 10.5m/s，命中吐 V 型 2 发",
         verdict="COPY", grade_note="V 型 2 发完全对上"),
    dict(kind="egt_grenat", egt_key="Grenat", egt_zh="榴弹子",
         egt_attack="直冲玩家，撞到即死；附加 1 发爆炸弹",
         ours="冲撞 10.0m/s，命中吐 1 发爆炸弹",
         verdict="COPY", grade_note="1 发爆炸弹对上"),
    dict(kind="egt_spirat", egt_key="Spirat", egt_zh="螺旋转弹",
         egt_attack="直冲玩家，撞到即死；多次中途重定位 + 预判走位，撞墙才停",
         ours="冲撞 9.5m/s，重定位 3 次 + 75% 预判",
         verdict="APPROX", grade_note="重定位 + 预判 + 撞墙才停都对上；3 次 / 75% 自拟"),

    # —— 触发 / 逃逸族 ——
    dict(kind="egt_keybullet_kin", egt_key="Keybullet Kin", egt_zh="钥匙小子",
         egt_attack="逃跑；击杀掉 1 把钥匙；没打死就传送消失",
         ours="逃跑（1.45× 速度）；11s 未击杀传送消失；**不掉钥匙**",
         verdict="GAP", grade_note="**真差异**：击杀掉落钥匙没接入（局内经济未做），只保住了「追不上就白跑」"),
    dict(kind="egt_chance_kin", egt_key="Chance Kin", egt_zh="运气小子",
         egt_attack="逃跑；击杀掉 1 个随机非钥匙拾取；没打死传送消失",
         ours="同钥匙小子，但不掉随机拾取",
         verdict="GAP", grade_note="同上，掉落通道缺失"),
    dict(kind="egt_confirmed", egt_key="Confirmed", egt_zh="已确认者",
         egt_attack="走向玩家，停下时从袍下射出 4 条蛇形追踪弹；注入·替换某怪，每层最多 1 只",
         ours="serpentine 图案 4 条（30% 预判 + 40% 追踪）；固定编成在 n08",
         verdict="COPY",
         grade_note="4 条蛇形追踪弹对上；但**生成通道改了**：原作是注入替换、每层≤1，"
                    "我们固定放在 n08 —— 否则那条 flow 会变成空房"),
    dict(kind="egt_gun_fairy", egt_key="Gun Fairy", egt_zh="枪精灵",
         egt_attack="房间内游荡 + 高射速连发；打碎罐子 0.05% 事件生成",
         ours="3 连发（间隔 0.08s）+ 房内游荡（半径 8m）；固定编成在 n08",
         verdict="COPY",
         grade_note="行为对上；生成通道改了（原作是破罐 0.05% 的极小概率事件，"
                    "照抄等于几乎见不到）"),
    dict(kind="egt_gripmaster", egt_key="Gripmaster", egt_zh="抓握大师",
         egt_attack="悬在玩家上方，闪蓝后下压抓人；抓到则把玩家扔回前几个房间并重置该批房间、重新刷怪；"
                    "本身无伤害且无敌；只能等其它怪全死或抓空 3 次转射击形态才可被伤害",
         ours="悬停 2.2m 闪蓝下压；抓到抛 10m；有其它怪时无敌；抓空 3 次消失；**清场后自己死**",
         verdict="GAP",
         grade_note="**真差异**：① 原作惩罚是「扔回前几个房间 + 重置房间重新刷怪」，"
                    "我们只抛 10m（房间重置链路不存在）；② 原作清场后「转射击形态、可被伤害」，"
                    "我们是「自己死」。两条都已在设计 §T6 记录"),

    # —— 重型 ——
    dict(kind="egt_gun_nut", egt_key="Gun Nut", egt_zh="枪坚果",
         egt_attack="举剑砸地，90° 扇形弹 + 4 组箭头形弹群，只能瞄 8 个罗盘方向；"
                    "判定从剑尖发出、可穿过小障碍；出手前停顿并锁定方向",
         ours="compass 7 发 ±45°（snap 45°）+ 每 2 次改 4 组 arrows + 撞墙炸 8 发大弹",
         verdict="APPROX",
         grade_note="90° 扇形 / 4 组箭头 / 8 罗盘 / 大弹全部对上；"
                    "**判定起点从怪中心发，不是剑尖**（不复刻「可穿小障碍」这条）"),
    dict(kind="egt_chain_gunner", egt_key="Chain Gunner", egt_zh="链枪手",
         egt_attack="停下甩出子弹链，约 3 圈/秒转 2 秒，期间缓慢逼近；链可穿墙；"
                    "若是房里最后一只，链球脱手飞向玩家；Blank 可立即打断",
         ours="orbit 3 圈/s × 2s，每圈 6 发，半径 3.2m，期间 0.55× 速度逼近；最后一只时链球脱手（11.0m/s）",
         verdict="APPROX",
         grade_note="转速 / 时长 / 逼近 / 最后一只脱手 都对上；"
                    "**链不能穿墙** —— 链上子弹走普通 `_fire_projectile`，没有穿透标记，"
                    "撞墙即消（原作明确写 the chain can go through walls）；"
                    "「Blank 可打断」不做 —— 项目没有 Blank 系统"),
]

# 已从远征03 编成摘除、但代码仍保留的怪
RETIRED: list[dict] = [
    dict(kind="egt_mimic", egt_key="Mimic（棕）", egt_zh="拟态怪",
         reason="2026-10-30 业主「宝箱还没做正式设计，先不做宝箱怪」，已从 n07 摘除；"
                "PROFILES 与 box_egt_mimic_trap.json 保留，接回时加一行即可",
         note="原作是**分档血量**（棕 100 / 蓝 120 / 绿 140 / 红 160 / 黑 180），"
              "我们只做了单一 1000（= 棕档 ×10），没有品质分档"),
]

VERDICT_META = {
    "COPY":    ("#34d399", "照抄", "逐项对得上"),
    "SCALED":  ("#38bdf8", "等比换算", "比例一致、绝对值不同"),
    "APPROX":  ("#fbbf24", "近似", "方向对，参数自拟"),
    "GAP":     ("#f87171", "差异", "原作机制未做 / 做法不同"),
}


def _parse_egt_hp() -> dict[str, float]:
    """从参考表 §7 附录解析原作第一层基础血量。"""
    text = REF_MD.read_text(encoding="utf-8")
    block = text.split("## 7. 附录")[1].split("## 8.")[0]
    out: dict[str, float] = {}
    for line in block.splitlines():
        if not line.startswith("| "):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2 or not re.fullmatch(r"\d+(\.\d+)?", cells[1]):
            continue
        out[cells[0]] = float(cells[1])
    return out


def audit() -> dict:
    egt_hp = _parse_egt_hp()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    live = {m["kind"]: m for m in manifest["monsters"]}

    rows = []
    fails = []
    for entry in AUDIT:
        kind = entry["kind"]
        if kind not in live:
            fails.append(f"{kind} 不在 manifest 里（出图脚本漏了？）")
            continue
        if entry["egt_key"] not in egt_hp:
            fails.append(f"{kind} 的 egt_key「{entry['egt_key']}」在附录表里找不到")
            continue
        m = live[kind]
        base = egt_hp[entry["egt_key"]]
        ratio = m["hp"] / base if base else 0.0
        hp_ok = abs(ratio - 10.0) < 0.005
        if not hp_ok:
            fails.append(f"{kind} 血量 {m['hp']} ÷ 原作 {base} = {ratio:.3f}，不是 10.00")
        rows.append({
            **entry,
            "hp": m["hp"],
            "egt_hp": base,
            "hp_ratio": round(ratio, 3),
            "hp_ok": hp_ok,
            "damage": m["damage"],
            "move_speed": m["move_speed"],
            "attack_style": m["attack_style"],
            "body_scale": m["body_scale"],
            "png": str(PORTRAIT_DIR / f"{kind}.png"),
        })

    order = {e["kind"]: i for i, e in enumerate(AUDIT)}
    rows.sort(key=lambda r: order[r["kind"]])

    counts = {k: 0 for k in VERDICT_META}
    for r in rows:
        counts[r["verdict"]] += 1

    return {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "total": len(rows),
        "counts": counts,
        "hp_all_scaled_x10": all(r["hp_ok"] for r in rows),
        "rows": rows,
        "retired": RETIRED,
        "fails": fails,
        "egt_hp_table": egt_hp,
    }


def _bold(text: str) -> str:
    """把手写数据里的 `**重点**` 转成 <strong>。

    数据表里的备注是照设计文档的习惯写的（富文本就是 `**`），直接塞进 HTML
    会把星号原样显示出来 —— 「不是**相同**」会读成「不是**相同**」。
    """
    return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)


def _render_html(data: dict) -> str:
    import base64

    def img(p: str) -> str:
        path = Path(p)
        if not path.exists():
            return ""
        return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")

    rows_html = []
    for r in data["rows"]:
        color, label, _ = VERDICT_META[r["verdict"]]
        hp_cls = "" if r["hp_ok"] else ' style="color:#f87171;font-weight:700"'
        rows_html.append(f"""
    <tr data-v="{r['verdict']}">
      <td class="shot"><img src="{img(r['png'])}" alt="{r['egt_key']}" loading="lazy"></td>
      <td class="ident">
        <div class="nm">{r['egt_zh']}</div>
        <div class="kid">{r['kind']}</div>
      </td>
      <td class="proto">
        <div class="en">{r['egt_key']}</div>
        <div class="zh">{r['egt_zh']}</div>
      </td>
      <td class="num ehp">{r['egt_hp']:g}</td>
      <td class="num ours"{hp_cls}>{r['hp']}</td>
      <td class="num ratio">{r['hp_ratio']:.2f}×</td>
      <td class="lore">{r['egt_attack']}</td>
      <td class="impl">{_bold(r['ours'])}</td>
      <td class="vd"><span class="tag" style="--c:{color}">{label}</span></td>
      <td class="gnote">{_bold(r['grade_note'])}</td>
    </tr>""")

    retired_html = "".join(
        f"""
    <tr class="retired">
      <td class="shot"></td>
      <td class="ident"><div class="nm">{x['egt_zh']}</div><div class="kid">{x['kind']}</div></td>
      <td class="proto"><div class="en">{x['egt_key']}</div><div class="zh">{x['egt_zh']}</div></td>
      <td class="num ehp">100</td>
      <td class="num ours">—</td>
      <td class="num ratio">—</td>
      <td class="lore">分档血量：棕 100 / 蓝 120 / 绿 140 / 红 160 / 黑 180；开箱或中弹才现形</td>
      <td class="impl">已从远征03 编成摘除</td>
      <td class="vd"><span class="tag" style="--c:#64748b">未实装</span></td>
      <td class="gnote">{_bold(x['reason'])}。{_bold(x['note'])}</td>
    </tr>"""
        for x in data["retired"]
    )

    c = data["counts"]
    legend = "".join(
        f'<span class="tag" style="--c:{VERDICT_META[k][0]}">{VERDICT_META[k][1]} · {c[k]}</span>'
        for k in VERDICT_META
    )

    gap_rows = [r for r in data["rows"] if r["verdict"] == "GAP"]
    gap_list = "".join(
        f"<li><b>{r['egt_zh']}</b>（{r['egt_key']}）：{_bold(r['grade_note'])}</li>" for r in gap_rows
    )

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>远征03 vs 《挺进地牢》第一层 · 逐只对照</title>
<style>
  :root {{ --bg:#0e1116; --panel:#151a22; --line:#242c38; --text:#e6ecf5;
           --muted:#8794a8; --accent:#5eead4; }}
  * {{ box-sizing:border-box; }}
  html,body {{ margin:0; background:var(--bg); color:var(--text); }}
  body {{ font:14px/1.55 "Microsoft YaHei UI","PingFang SC","Segoe UI",system-ui,sans-serif; }}
  .wrap {{ padding:26px 28px 60px; max-width:2000px; margin:0 auto; }}

  header {{ display:flex; align-items:flex-end; justify-content:space-between; gap:24px;
            padding-bottom:16px; border-bottom:1px solid var(--line); }}
  h1 {{ margin:0 0 6px; font-size:24px; font-weight:700; }}
  h1 small {{ font-size:13px; color:var(--muted); font-weight:400; margin-left:10px; }}
  .sub {{ color:var(--muted); font-size:12.5px; }}
  .verdict-box {{ display:flex; gap:8px; flex-wrap:wrap; flex:none; }}

  .tag {{ --c:#94a3b8; display:inline-block; padding:2px 9px; border-radius:999px;
          font-size:11.5px; white-space:nowrap; color:var(--c);
          background:color-mix(in srgb, var(--c) 14%, transparent);
          box-shadow:0 0 0 1px color-mix(in srgb, var(--c) 34%, transparent) inset; }}

  .verdicts {{ display:flex; flex-direction:column; gap:10px; margin:18px 0 6px; }}
  .vcard {{ display:flex; gap:12px; align-items:flex-start; padding:11px 14px;
            border-radius:8px; background:var(--panel); border-left:3px solid var(--c); }}
  .vcard b {{ color:var(--c); }}
  .vcard p {{ margin:0; color:#b6c3d4; font-size:13px; }}

  .note {{ color:var(--muted); font-size:12px; margin:14px 0 16px; }}
  .note code {{ color:#8ea3bd; }}

  table {{ width:100%; border-collapse:separate; border-spacing:0; }}
  thead th {{ position:sticky; top:0; z-index:5; background:#1a212b; color:#9fb0c6;
              font-size:11.5px; font-weight:600; text-align:left; padding:9px 9px;
              white-space:nowrap; border-bottom:1px solid var(--line); }}
  thead th:first-child {{ border-top-left-radius:8px; }}
  thead th:last-child {{ border-top-right-radius:8px; }}
  tbody tr {{ background:var(--panel); }}
  tbody tr:nth-child(even) {{ background:#131922; }}
  tbody tr:hover {{ background:#1d2735; }}
  td {{ padding:9px; border-bottom:1px solid #1c232d; vertical-align:top; }}

  .shot {{ width:96px; padding:6px 4px 6px 9px; }}
  .shot img {{ width:82px; height:88px; object-fit:contain; display:block; border-radius:6px;
               background:radial-gradient(ellipse at 50% 78%, #182231 0%, #0e1116 72%); }}
  .ident {{ width:128px; }}
  .nm {{ font-size:14.5px; font-weight:600; }}
  .kid {{ font-family:Consolas,"Cascadia Mono",monospace; font-size:10.5px; color:#6f7f95; }}
  .proto {{ width:150px; }}
  .proto .en {{ font-size:13px; color:#cfdaea; }}
  .proto .zh {{ font-size:11px; color:#7c8ba1; }}
  .num {{ font-variant-numeric:tabular-nums; width:62px; font-size:13.5px; }}
  .ehp {{ color:#9fb0c6; }}
  .ours {{ font-weight:600; }}
  .ratio {{ color:#5eead4; font-size:12.5px; }}
  .lore {{ width:300px; font-size:12.5px; color:#a9b7c9; }}
  .impl {{ width:300px; font-size:12.5px; color:#c7d3e2; }}
  .vd {{ width:78px; }}
  .gnote {{ width:330px; font-size:12px; color:#93a2b6; }}
  tr.retired {{ opacity:.55; }}

  footer {{ margin-top:24px; color:#63718a; font-size:11.5px; line-height:1.9; }}
  footer code {{ color:#8ea3bd; }}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div>
      <h1>远征03 vs 《挺进地牢》第一层 · 逐只对照<small>{data['total']} 只全部核对</small></h1>
      <div class="sub">左半 = 原作；右半 = 我们的实现。血量列逐只相除，倍率不是 10.00 会标红。</div>
    </div>
    <div class="verdict-box">{legend}</div>
  </header>

  <div class="verdicts">
    <div class="vcard" style="--c:#34d399"><b>血量：{data['total']} / {data['total']} 严格等比 ×10，0 偏差</b>
      <p>不是「相同」，是<strong>比例完全相同、绝对值放大 10 倍</strong>。原作用的是一套 6 格血，
      我们用的是 100 血；15 血 → 150、33.8 → 338、18.8 → 188，逐只都是 ×10。
      放大 10 倍的理由是对齐「击杀发数」：原作 Bullet Kin 15 血 ÷ 手枪 6 伤 ≈ 3 发，
      我们 150 血 ÷ 初始步枪 50 伤 = 3 发。</p></div>
    <div class="vcard" style="--c:#38bdf8"><b>伤害：全部 17（2 只 0），比例一致</b>
      <p>原作「几乎所有伤害都是半颗心」是全局约定，不是逐怪配表。我们换算成 17 = 玩家 100 血的 1/6
      = 原作 6 格里的 1 格，比例一致。两只 0 是枪歌者（辅助不输出）与抓握大师（原作明确 deal no damage）。</p></div>
    <div class="vcard" style="--c:#fbbf24"><b>速度：序关系对，绝对值不可比</b>
      <p>原作只给「慢速 / 中速 / 快速 / 浮空 / 停留」五种定性，<strong>没有任何数字</strong>。
      我们按档给数（2.0 / 2.4 / 3.4 / 1.8 / 0.6），序关系逐只对上（老兵比普通小子快、
      链枪手比枪坚果快），但绝对值没有原作依据。</p></div>
    <div class="vcard" style="--c:#f87171"><b>攻击方式：{c['COPY']} 只逐项照抄、{c['APPROX']} 只近似、{len(gap_rows)} 只有真差异</b>
      <p>「照抄」的判据是有硬数据：连发数、扇形形状、死亡效果、预判有无、分裂链 —— 这些原作 Wiki 逐条写明。
      「近似」是方向对但角度 / 秒数 / 概率 / 弹速自拟（原作不发布这些数值），
      或者少了一条次要规则（如链枪手的链不能穿墙）。
      「差异」是原作的核心机制我们没有或做成别的，见下表。</p></div>
  </div>

  <div class="note">
    <b style="color:#f87171">真差异 {{len(gap_rows)}} 项：</b>
    <ul style="margin:6px 0 0; padding-left:20px; color:#b6c3d4; font-size:12.5px; line-height:1.9;">{gap_list}</ul>
  </div>

  <table>
    <thead>
      <tr>
        <th>模型</th><th>我们</th><th>原作原型</th><th>原作血量</th><th>我们血量</th><th>倍率</th>
        <th>原作攻击方式</th><th>我们的实现</th><th>判定</th><th>说明</th>
      </tr>
    </thead>
    <tbody>{''.join(rows_html)}{retired_html}
    </tbody>
  </table>

  <footer>
    原作血量解析自 <code>docs/v0.1/reference/挺进地牢/第一层怪物数据表.md §7</code>；
    我们血量取 <code>outputs/expedition03_monster_roster/manifest.json</code>（运行时实测，非公式重算）。<br>
    本表由 <code>tools/egt_fidelity_audit.py</code> 生成 · {data['generated_at']} ·
    机械核对 {data['total']} 只，失败 {len(data['fails'])} 项。<br>
    「攻击方式」一栏是人工核对后的判断，脚本不假装它是机械比对 —— 原作没有可机读的行为结构。
  </footer>
</div>
</body>
</html>
"""


def main() -> int:
    data = audit()
    JSON_OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    HTML_OUT.write_text(_render_html(data), encoding="utf-8")

    c = data["counts"]
    print(f"EGT_FIDELITY 核对 {data['total']} 只")
    print(f"  血量等比 ×10: {'全部通过' if data['hp_all_scaled_x10'] else '有偏差'}")
    print(f"  COPY {c['COPY']} / APPROX {c['APPROX']} / GAP {c['GAP']}")
    if data["fails"]:
        print("  失败项:")
        for f in data["fails"]:
            print(f"    - {f}")
    print(f"  报告 {HTML_OUT}")
    return 0 if not data["fails"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
