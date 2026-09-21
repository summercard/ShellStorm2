"""在 CHANGELOG.md 顶部（标题行之后）插入三次修正条目，保持 CRLF。"""
import sys

P = "docs/v0.1/development/CHANGELOG.md"
b = open(P, "rb").read()

ANCHOR = "# 游戏设计文档 v0.1 变更记录\r\n".encode("utf-8")
if b.count(ANCHOR) != 1:
    print("ANCHOR_FAIL count=%d" % b.count(ANCHOR))
    sys.exit(1)

SECTION = """## 2026-09-21｜三次修正 100F 天台装饰：立管接到地板、墙挂空调 90° 倾倒让风扇朝外

业主实机看截图反馈两条：「水管可以接下来一些，接到地板 上面基本看不到的」「空调机的在墙上的状态，需要 90 度旋转，让风扇朝外」。全部**原地修正**（AssetID / layout_id / layout_version 不变）：

1. **立管落地**：`pipe_riser` 件高 **4.945m**、原点在**管底**、顶端是朝 +X 的鹅颈出水口。旧版放 `h=5.8` ⇒ 管底**悬空 5.8m**。现每处摆**两段、两段的 h 都是 4.945**：下段 `rotation_x_deg=180` **倒装**（几何绕原点翻到下方 ⇒ 包络 0~4.945m，原点即上端；鹅颈转到贴地 0.095m，读作立管底部的泄水口）、上段正装（4.945~9.89m，鹅颈仍在顶 9.795m），合成一根 **0~9.89m 连续落水管**；与 10.65m 环管之间残留 **0.76m**，由环管本体与支架轨遮住 ⇒ 达成业主「上面基本看不到」。支架同时补一段低位（1.5m）与原有 7.0m 位，覆盖 1.56~10.64m。立管 4 处 → **8 段**、支架 4 → **8 件**。
2. **墙挂空调倾倒 90°**：新增实例朝向分量 **`rotation_x_deg`**（绕自身 X 轴的「倾倒」，此前 `add()` 只会绕 Z 轴转平面朝向）。组件 `hvac_small` 的**顶面**（Blender 局部 +Z）自带出风风扇、**前面**（局部 −Y）自带进风格栅 —— 落地摆放时风扇朝上是对的，**一挂到墙上风扇就朝天**。故 4 台墙挂机统一 `rotation_x_deg=90`，风扇转成朝墙外（南墙 → +Z、东墙 → +X、西墙 → −X）。⚠️ **欧拉序契约**：Blender 默认 XYZ 序（矩阵 = `Rz·Rx·Ry`）、Godot 默认 YXZ 序（矩阵 = `Ry·Rx·Rz`），**只有 `rz` 分量为 0 时** `Rz@Rx` 与 `Ry@Rx` 才同序、角度才可逐值搬运 ⇒ 布局源只用 `rotation_x_deg` + `rotation_y_deg` 两轴，**禁止同时给 ry 与 rz**。两个引擎分别取过真值矩阵验证，映射 `(bx,by,bz)→(bx,bz,−by)` 下等价。
3. **6 个墙挂件贴墙**：4 空调 + 2 通风口的后背统一埋进墙外皮内 **0.05m**，不再悬空（旧版通风口后背离墙 0.63m）。立管与支架按各自墙面给 yaw（旧版立管一律 0 ⇒ 东西墙鹅颈朝墙里）。

**运行时重放实例 112 → 120**（`pipe_risers` 8 → 16）：空调与通风口 6 + 绿化 20 + 藤蔓 16 + 女儿墙挂藤 8 + 水管 54 + 立管/支架 16；结构壳体（234 地砖 / 68 件女儿墙 / 楼梯与碰撞）与玩法不变。

验收与防再犯：布局 QA（`validate_rooftop_decorated_layout_v001.py`）新增**第 4 层断言** —— ① 墙挂空调「倾倒后包络轴交换」：沿墙法线进深必须 = 原**高度** 1.87、竖向高度必须 = 原**进深** 2.365，且机背埋进外皮 0.05m；② 立管两段接地：下段 `rotation_x=180` 且**管底 z=0**、顶 z=4.945，两段合成顶 z=9.890。运行时探针 `probe_rooftop_decorated_layout.gd` 新增 `_check_fan_outward()`（**风扇轴必须指向该墙外法线**，外法线由 30×30 壳体中心推得、不查表）与 `_check_riser_runs()`（按**实测可视包络**判两段连成 0~9.89m、最低点落 y=0；⚠️ 倒装件原点在上端，**不能用 `position.y` 判落地**）。**两层断言都做了反向对照**（`HVAC_SMALL_TIP`、`PIPE_RISER_LOWER_TIP` 双双改 0 → 重生成 → 两侧同时变红：QA 报 14 条、运行时报 12 条；还原后 .json 与基线**逐字节一致**）。⚠️ 本轮还修掉探针自身的**判据错误**：风扇在 Blender 局部 +Z，经 glTF Y-up 导入 Godot 后是**局部 +Y**，原来读 `basis.z` 会恒判「没朝外」（改用 `basis.y`）。

门禁：`check_asset_registry --ledger scenes --scope full` 维持 **46**（布局 .blend 重生成 ⇒ 同步 row 240 的 SHA `96f914c5… → 09e9a917…`）；账本 row 240（112/6 组 → 120/6 组）与域变更日志 **v0.1.7** 同步；运行时清单 `assets/art/environments/tower_zones/rooftop/runtime/rooftop_100f_decorated_runtime_manifest.json` 112 → 120。8/8 屋顶验收全绿 0 ERROR：`probe_rooftop_decorated_layout`（`ROOFTOP_DECORATED_LAYOUT_RUNTIME_OK instances=120`）/ `probe_rooftop_decorated_stage_only` / `verify_rooftop_32x32_contract` / `verify_rooftop_door` / `verify_base_rooftop_transit_door_motion` / `verify_rooftop_railing` / `verify_tower_grid_component_alignment` / `verify_rooftop_floor_facade_components`。视觉取证：`probe_rooftop_decor_fix_shots.{gd,tscn}` 扩到 **14 机位**（新增立管南/西落地侧视、俯视「上面看不到」、空调南/东正视图，并自加补光灯）→ `_scratch/rooftop/decor_fix_shots/*.png`。旧布局源码留档 `_scratch/rooftop/green_baseline.{blend,json}`、旧账本 `ShellStorm2_场景账本_v001.xlsx.bak_rooftop_decor_third_fix`。

<br>

"""
SEC = SECTION.replace("\n", "\r\n").encode("utf-8")

b = b.replace(ANCHOR, ANCHOR + SEC, 1)
open(P, "wb").write(b)
print("CHANGELOG_OK CR=%d LF=%d CRCRLF=%d" % (b.count(b"\r"), b.count(b"\n"), b.count(b"\r\r\n")))
