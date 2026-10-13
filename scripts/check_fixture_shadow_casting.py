"""校验：灯具外壳的「不投影」必须在运行时由代码兜底，不能只靠预置件 .tscn。

背景（2026-10-12 事故 + 根因实测）
    「84_东面圆形工业吊灯」在编辑器无投影、打包后地板出现悬空圆形暗斑。链路：

    ① 99F 中央玩法主灯挂在 **11.62m**（`DungeonRoom3D._install_base99_facility_lights`：
       y = FLOOR_HEIGHT_M − 2.72），主灯 prefab 写 `cast_shadow = true`；
    ② 吊灯挂在 ~2.5m —— 灯在灯罩正上方，灯罩轮廓被放大投到地板；
    ③ 灯具外壳网格没关投影（GLB 导入出的 MeshInstance3D 默认 cast_shadow = ON）。

    **关键坑：在预置件 .tscn 里对「导入 GLB 场景的内部节点」写属性覆盖
    （`[node name="<网格名>" parent="ImportedModel" index="0"]` + `cast_shadow = 0`）
    编辑器生效、项目内运行生效，但导出转换会静默丢弃。**

    2026-10-12 实测（不是推理）：
      - 源 .tscn 读 0，导出后 `.godot/exported/*.scn` 读 1；
      - 删掉 `.godot/exported` 缓存强制重新转换，产物仍为 1（字节数与旧版一致）；
      - 对照组正常保留：普通 `.tscn` 实例的内部节点覆盖（玩家换装件的 `visible`）
        与实例根节点覆盖（基座顶灯阵列的 `cast_shadow`）导出后逐值不变。

    ⇒ 唯一可靠修法：**代码**（一定进包）。落在 `BaseFixtureGlow3D._disable_fixture_shadow()`，
    由 `FIXTURE_PROFILES` 逐个灯具兜底。

判据
    对每个「灯具」预置件（预置件自身文件名含 light / lamp / pendant / fixture / 灯），
    取其根节点名，要求它出现在 `src/world3d/BaseFixtureGlow3D.gd` 的
    `FIXTURE_PROFILES` 名单里 —— 否则发行包里这盏灯的灯罩会投影。

    覆盖范围：`assets/art/environments/base_facility_3d/runtime/`（本轮已裁定）。
    其余目录只提示，`--all` 可强制。

退出码：0 = 通过；1 = 有灯具没有运行时兜底。
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART_ROOT = ROOT / "assets" / "art"
GLOW_SCRIPT = ROOT / "src" / "world3d" / "BaseFixtureGlow3D.gd"

# 判定「这是灯具」只看预置件自身文件名。
# 刻意**不**看子 GLB 名：聚合包（如 env_base99_wall_contents，18 个 GLB 里混着
# 管线/配电柜/海报与一个「照明支持」）会被误判，一刀切关掉会杀掉正常投影。
LIGHT_KEYS = ("light", "lamp", "pendant", "fixture", "灯")

ENFORCED_PREFIX = "assets/art/environments/base_facility_3d/runtime/"

# 显式豁免：预置件相对路径 -> 理由。
EXEMPT: dict[str, str] = {}

_NODE_RE = re.compile(r'^\[node name="(?P<name>[^"]+)"(?P<attrs>[^\]]*)\]', re.M)


def runtime_fixture_names() -> set[str]:
    """从 BaseFixtureGlow3D 的 FIXTURE_PROFILES 里取出受兜底的灯具名。"""
    if not GLOW_SCRIPT.is_file():
        return set()
    text = GLOW_SCRIPT.read_text(encoding="utf-8", errors="ignore")
    block = re.search(r"FIXTURE_PROFILES\s*:?=\s*\[(.*?)\n\]", text, re.S)
    if not block:
        return set()
    return set(re.findall(r'"name":\s*"([^"]+)"', block.group(1)))


def prefab_root_name(text: str) -> str:
    """取 tscn 里第一个顶层节点（无 parent）的名字，即预置件根节点名。"""
    for m in _NODE_RE.finditer(text):
        if "parent=" not in m.group("attrs"):
            return m.group("name")
    return ""


def scan(enforce_all: bool) -> tuple[list[str], list[str], list[str]]:
    covered = runtime_fixture_names()
    failures: list[str] = []
    infos: list[str] = []
    skipped: list[str] = []
    if not covered:
        return (
            ["无法从 BaseFixtureGlow3D.gd 解析出 FIXTURE_PROFILES —— 运行时兜底名单缺失"],
            infos,
            skipped,
        )

    for tscn in sorted(ART_ROOT.rglob("*.tscn")):
        if not any(k in tscn.name.lower() for k in LIGHT_KEYS):
            continue
        rel = tscn.relative_to(ROOT).as_posix()
        if rel in EXEMPT:
            skipped.append(f"{rel}  —— 已登记豁免：{EXEMPT[rel]}")
            continue
        text = tscn.read_text(encoding="utf-8", errors="ignore")
        if not re.search(r'\[ext_resource type="PackedScene" path="res://[^"]+\.glb"', text):
            continue
        root_name = prefab_root_name(text)
        if root_name in covered:
            continue
        detail = (
            f"{rel}\n"
            f"      预置件根节点「{root_name}」不在 BaseFixtureGlow3D.FIXTURE_PROFILES 里"
        )
        if enforce_all or rel.startswith(ENFORCED_PREFIX):
            failures.append(detail)
        else:
            infos.append(detail)
    return failures, infos, skipped


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="CI/验收别名，行为相同")
    parser.add_argument("--all", action="store_true", help="把强制范围扩到全工程")
    args = parser.parse_args()

    failures, infos, skipped = scan(enforce_all=args.all)

    if infos:
        print(
            f"提示：以下 {len(infos)} 处同类件尚无运行时兜底"
            "（默认不判失败；确认该灯确实该投影就无需处理，用 --all 可强制）："
        )
        for item in infos:
            print(f"  - {item}")
        print()
    for item in skipped:
        print(f"跳过：{item}")
    if skipped:
        print()

    if failures:
        print("FIXTURE_SHADOW_CASTING_VIOLATION")
        print(
            "灯具外壳的不投影必须在运行时由代码兜底。\n"
            "原因：预置件 .tscn 里对「导入 GLB 内部节点」的属性覆盖，导出转换会静默丢弃\n"
            "（源 .tscn 读 0、导出后 .scn 读 1，删缓存重转亦然）——只有代码一定进包。\n"
        )
        for item in failures:
            print(f"  ❌ {item}")
        print(
            "\n修法：把该灯具的根节点名加进 src/world3d/BaseFixtureGlow3D.gd 的\n"
            'FIXTURE_PROFILES（{ "name": "<预置件根节点名>", ... }）。\n'
            "兜底逻辑在 _disable_fixture_shadow()，会自动关掉该灯具下所有网格的投影。\n"
            "注意：若该灯确实应该投影（例如贴墙、远在背景），请在 EXEMPT 里登记理由。"
        )
        return 1

    print("FIXTURE_SHADOW_CASTING_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
