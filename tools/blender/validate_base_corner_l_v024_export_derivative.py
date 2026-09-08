import bpy
import json


OBJECT_NAME = "env_base99_corner_l_5m_visual_top3d_v001"


def main():
    failures = []
    visual = bpy.data.objects.get(OBJECT_NAME)
    if visual is None or visual.type != "MESH":
        failures.append("missing selected game visual")
    else:
        mesh = visual.data
        if len(bpy.data.objects) != 1:
            failures.append("derivative contains objects outside selected game output")
        if len(mesh.polygons) != 140:
            failures.append(f"unexpected optimized triangle count: {len(mesh.polygons)}")
        if any(polygon.normal.z < -0.65 for polygon in mesh.polygons):
            failures.append("downward faces remain in derivative")
        if [layer.name for layer in mesh.uv_layers] != ["PaletteUV"]:
            failures.append("derivative UV contract is not PaletteUV only")
        if mesh.uv_layers.active is None or not mesh.uv_layers.active.active_render:
            failures.append("PaletteUV is not render active")
        long_rib_levels = {
            round(vertex.co.z, 3) for vertex in mesh.vertices
            if 0.20 < vertex.co.x < 4.80 and 0.09 < vertex.co.y < 0.16
        }
        short_rib_levels = {
            round(vertex.co.z, 3) for vertex in mesh.vertices
            if 0.09 < vertex.co.x < 0.16 and 0.20 < vertex.co.y < 4.80
        }
        if len(long_rib_levels) < 10 or len(short_rib_levels) < 10:
            failures.append("horizontal rib geometry is incomplete on one or both arms")
    report = {"passed": not failures, "derivative": bpy.data.filepath, "failures": failures}
    print("BASE99_CORNER_DERIVATIVE_VALID=" + json.dumps(report, ensure_ascii=False))
    if failures:
        raise SystemExit(1)


main()
