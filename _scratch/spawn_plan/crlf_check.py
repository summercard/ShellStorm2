"""行尾纯度检查：本次改动文件必须全 CRLF。"""
import os

FILES = [
    r"I:\工作项目\shellstrom2\ShellStorm2\src\map\LevelPlanLoader.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\src\map\FloorPlanGenerator.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\src\map\MonsterInjector.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\src\map\LevelPlanValidator.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\Dungeon3D.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\DungeonRoom3D.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\TowerDescent3D.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_level_plan_design_source.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_test_level_99_flow.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\source\art\whitebox\tower_zones\99\v001\data\floors\floor_00.json",
    r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\design\新关卡设计表.md",
    r"C:\Users\zhuangmenghong\.workbuddy\skills\09-level-plan-authoring\SKILL.md",
]

for path in FILES:
    with open(path, "rb") as handle:
        data = handle.read()
    crlf = data.count(b"\r\n")
    lone_lf = data.count(b"\n") - crlf
    lone_cr = data.count(b"\r") - crlf
    flag = "OK " if (lone_lf == 0 and lone_cr == 0) else "BAD"
    print("%s crlf=%-6d loneLF=%-4d loneCR=%-4d %s" % (flag, crlf, lone_lf, lone_cr, os.path.basename(path)))
