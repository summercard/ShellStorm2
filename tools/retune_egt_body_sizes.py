#!/usr/bin/env python3
"""远征03 复刻怪体型重定标（2026-10-30）。

业主口径
--------
「还有只怪物太小了，好像是用了小僵尸的模型做了分裂的怪物，怪物不用这么小。可以用其它模型」

## 一、问题不是"某一只小"，是整批偏小

实测（`tools/_egt_enemy_size_probe.gd`，玩家身高按 1.8m 当尺）：

| 怪 | 借用资产 | 世界高 | 玩家比 |
|---|---|---|---|
| egt_blobulin（分裂三阶最小） | melee_chaser | **0.36m** | **0.20×** |
| egt_blobuloid（二阶段） | melee_chaser | 0.56m | 0.31× |
| egt_blobulon（母体） | melee_chaser | 0.91m | 0.51× |
| egt_bullat | exploder | 0.49m | 0.27× |
| egt_grenat | exploder | 0.63m | 0.35× |
| ...13 只低于 0.55× |

根因是**两层倍率相乘**，两层都没人算过乘积：

```
世界高 = 资产基准高 × DEFAULT_BASE_SIZE_MULTIPLIER(0.70) × BODY_SCALE_BY_KIND[kind]
```

而 `BODY_SCALE_BY_KIND` 的 egt 段是**族内相对阶梯**（分裂 1.00/0.62/0.40），
写的人想的是"相对母体小一圈"，但绝对世界高要在 `× 0.70` 之后再看 ——
0.40 已经不是"小一圈"，是 0.36m 的花园地精。

## 二、新口径：**先定目标世界高，再回算缩放**

缩放本身没有语义，世界高才有。所以本脚本以 `TARGET_HEIGHT_M` 为唯一真源：

```
BODY_SCALE = TARGET_HEIGHT / (资产基准高 × 0.70)
```

资产基准高取 `EnemyAvatar3D.FOOTPRINT_PROFILES[资产].height`（碰撞柱高，
它本来就是按"实际模块化模型的最大轮廓"定的，是最稳的高度代理）。

### 目标值怎么定的

| 族 | 目标区间 | 理由 |
|---|---|---|
| 远程族 | 1.22 ~ 1.50m | 比玩家(1.8)矮一档，读起来是"人形敌人"；族内随威胁单调递增 |
| 分裂族 | **1.00 ~ 1.60m** | 业主点名的族。三阶仍要能看出"越裂越小"，但**最小那只也不低于 1.0m** |
| 爆炸族 | 1.00 ~ 1.48m | 自爆怪压扁、贴地；但同样不低于 1.00m（实测 0.95 会掉到 0.53× 下限之下）|
| 法术/书怪 | 1.46 ~ 1.70m | 悬浮施法者偏高，仍然是房间里最显眼的 |
| 触发射手 | 1.02 ~ 1.34m | 钥匙小子一直在跑，最小但要看得见 |

**下限 1.00m（≈玩家 0.55×）** 是业主那句"不用这么小"的可执行版本：
低于它就变成"小动物"而不是"会杀了你的敌人"。

## 三、血条宽度同步回算

`HEALTH_BAR_SIZE_BY_KIND` 的 egt 段原本是 `基类宽 × 旧缩放` 手算出来的。
改了缩放不同步改它，就会出现"体型变大、血条还是窄的"—— 远看像贴错标签。
本脚本按 `基类宽 × 新缩放` 重算，并保留原有的可读性下限（不低于 0.72）与高度档
（<1.7 → 0.15，<2.0 → 0.16，其余 0.18）。

## 四、为什么不动重型三只

`egt_chain_gunner` / `egt_gun_nut` / `egt_mimic` 借 `fat_zombie03`（基准 3.14m），
实测 2.5~2.6m —— **偏大不偏小**，业主没提，本轮不碰。
改它们等于顺手改玩法手感（更大的碰撞柱 = 更容易被打到），没需求就不做。
"""

import io
import re
import sys

SRC = "src/enemy3d/Enemy3D.gd"

# 资产基准高（与 `EnemyAvatar3D.FOOTPRINT_PROFILES` 逐值一致）。
ASSET_HEIGHT = {
    "fat_zombie03": 3.142857,
    "melee_chaser": 1.30,
    "ranged_caster": 1.62,
    "summoner": 1.82,
    "exploder": 1.28,
    "shielded": 1.42,
    "ambusher": 0.86,
    "boss": 2.30,
}
# 资产基准血条宽（与 `HEALTH_BAR_SIZE_BY_KIND` 的基类行逐值一致）。
ASSET_BAR_WIDTH = {
    "fat_zombie03": 1.8,
    "exploder": 1.15,
    "ranged_caster": 1.38,
    "melee_chaser": 1.38,
    "ambusher": 1.38,
    "shielded": 1.55,
    "summoner": 1.55,
    "boss": 2.65,
}
BASE_MULTIPLIER = 0.70
BAR_MIN_WIDTH = 0.72

# 怪 → (借用资产, 目标世界高 m)
TARGET = {
    # —— 远程族：随威胁递增 ——
    "egt_bullet_kin": ("ranged_caster", 1.22),
    "egt_bandana_kin": ("ranged_caster", 1.28),
    "egt_veteran_kin": ("ranged_caster", 1.34),
    "egt_red_shotgun": ("ranged_caster", 1.38),
    "egt_blue_shotgun": ("ranged_caster", 1.52),
    "egt_cardinal": ("ranged_caster", 1.38),
    # 业主 2026-10-30 点名：「这个怪物的大小缩小一点，到现在的 70%」
    # 原 1.44m × 0.7 = 1.008 ⇒ 1.01m。
    # ⚠ 这会让「子弹族体型阶梯」倒挂（它血量 250 最高、体型却最小）——
    #   用户明确要求优先于族内排序规则，`_egt_variant_visual_probe` 里为此登记了
    #   显式豁免（`SIZE_EXEMPT`），理由写在豁免表里。
    "egt_hollowpoint": ("ranged_caster", 1.01),
    "egt_veteran_shotgun": ("ranged_caster", 1.45),
    "egt_confirmed": ("ranged_caster", 1.60),
    "egt_gun_fairy": ("ranged_caster", 1.06),
    # —— 分裂族：业主点名。阶梯保留，但最小那只也到 1.00m ——
    "egt_blobulon": ("melee_chaser", 1.50),
    "egt_blobuloid": ("melee_chaser", 1.22),
    "egt_blobulin": ("melee_chaser", 1.00),
    "egt_chancebulon": ("melee_chaser", 1.60),
    # —— 爆炸族：按血量单调 ——
    "egt_bullat": ("exploder", 1.00),
    "egt_shotgat": ("exploder", 1.05),
    "egt_grenat": ("exploder", 1.10),
    "egt_spirat": ("exploder", 1.15),
    "egt_nitra": ("exploder", 1.21),
    "egt_pinhead": ("exploder", 1.28),
    "egt_king_bullat": ("exploder", 1.48),
    # —— 法术 / 书怪族 ——
    "egt_bookllet": ("summoner", 1.46),
    "egt_blue_bookllet": ("summoner", 1.51),
    "egt_green_bookllet": ("summoner", 1.56),
    "egt_gigi": ("summoner", 1.52),
    "egt_gunjurer": ("summoner", 1.60),
    "egt_gunsinger": ("summoner", 1.70),
    "egt_gripmaster": ("summoner", 1.30),
    # —— 触发 / 逃逸族 ——
    "egt_keybullet_kin": ("melee_chaser", 1.02),
    "egt_chance_kin": ("melee_chaser", 1.08),
}

# 本轮**不改**的（偏大不偏小，业主没提）。
UNTOUCHED = {
    "egt_chain_gunner": ("fat_zombie03", 2.51),
    "egt_gun_nut": ("fat_zombie03", 2.64),
    "egt_mimic": ("fat_zombie03", 2.53),
}


def scale_for(asset: str, target_h: float) -> float:
    return target_h / (ASSET_HEIGHT[asset] * BASE_MULTIPLIER)


def bar_for(asset: str, scale: float) -> tuple:
    width = max(BAR_MIN_WIDTH, ASSET_BAR_WIDTH[asset] * scale)
    if width < 1.7:
        height = 0.15
    elif width < 2.0:
        height = 0.16
    else:
        height = 0.18
    # 爆炸族条薄一点（沿用原表：0.14/0.13 档），否则一排黄条压满屏幕。
    if asset == "exploder":
        height = 0.14
    return round(width, 2), height


def fmt(v: float) -> str:
    text = ("%.3f" % v).rstrip("0").rstrip(".")
    return text if text else "0"


def main() -> int:
    src = io.open(SRC, encoding="utf-8").read()

    replacements = []
    for kind, (asset, target_h) in TARGET.items():
        scale = scale_for(asset, target_h)
        width, height = bar_for(asset, scale)
        replacements.append((kind, asset, target_h, scale, width, height))

    # —— 替换 BODY_SCALE_BY_KIND 里对应行 ——
    for kind, _asset, _t, scale, _w, _h in replacements:
        pattern = r'("%s":\s*)([0-9.]+)(,)' % re.escape(kind)
        new_src, count = re.subn(pattern, lambda m: m.group(1) + fmt(scale) + m.group(3), src, count=1)
        if count != 1:
            print("BODY_SCALE 未找到 %s（count=%d）" % (kind, count), file=sys.stderr)
            return 1
        src = new_src

    # —— 替换 HEALTH_BAR_SIZE_BY_KIND 里对应行 ——
    for kind, _asset, _t, _s, width, height in replacements:
        pattern = r'("%s":\s*)Vector2\([0-9.]+,\s*[0-9.]+\)' % re.escape(kind)
        new_src, count = re.subn(
            pattern,
            lambda m: m.group(1) + "Vector2(%s, %s)" % (fmt(width), fmt(height)),
            src,
            count=1,
        )
        if count != 1:
            print("HEALTH_BAR 未找到 %s（count=%d）" % (kind, count), file=sys.stderr)
            return 1
        src = new_src

    io.open(SRC, "w", encoding="utf-8", newline="\n").write(src)

    print("%-24s %-14s %7s %8s %8s %s" % ("怪", "资产", "目标高", "缩放", "世界高", "血条宽"))
    for kind, asset, target_h, scale, width, height in sorted(replacements, key=lambda r: r[0]):
        print("%-24s %-14s %6.2fm %8.3f %7.2fm  %.2f×%.2f"
              % (kind, asset, target_h, scale, ASSET_HEIGHT[asset] * BASE_MULTIPLIER * scale, width, height))
    print("\n未改（偏大不偏小）：%s" % ", ".join(sorted(UNTOUCHED)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
