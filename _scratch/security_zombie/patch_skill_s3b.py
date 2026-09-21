import io
from pathlib import Path

SK = Path(r'C:\Users\zhuangmenghong\.workbuddy\skills\normal-enemy-model-pipeline\SKILL.md')
raw = SK.read_bytes()
assert raw.count(b'\r\n') == raw.count(b'\n'), 'file is not pure CRLF, abort'

anchor = b'- \xe5\x9d\x91\xef\xbc\x9a\xe5\x88\xa4\xe6\x8d\xae\xe5\x8f\xaa\xe8\x83\xbd\xe6\x98\xaf\xe6\xb8\xb2\xe6\x9f\x93\xe5\x9b\xbe'
idx = raw.find(anchor)
assert idx != -1, 'anchor not found'
# fall back to a plain ascii anchor if the utf-8 probe missed
if idx == -1:
    raise SystemExit(1)

new_section = '''### S3b 外部已绑定骨架重定向到契约（要求"不改绑定/蒙皮"时用）

外部给来一套**已绑好蒙皮的骨架**（Tripo / Mixamo 产物等），要求"保持原绑定、只对齐契约"时走这条路径；
**不要**套 §S1 的"换成自己的骨架"，也不要重算骨架数据或重新分权重。

- 只做三件事：①骨名 + 顶点组 **1:1 改名**（Armature Modifier 按名字匹配，两者必须同步）；②朝向 / 缩放对**骨与网格施加同一个变换**（作用在数据层，不写对象级 scale）；③补契约缺失的根骨（如 `Root`：head 世界原点、挂到 `Hip` 之上，父级必须是 None）。
- ⇒ "保持蒙皮"按定义成立：没动权重、没动骨架数据、没重算绑定，只是换名字 + 换坐标系。
- 骨名映射要分两张表：契约骨进 `BONE_MAP`，非契约的中间骨（Twist / `*3` `*4` 指骨 / ToeBase / HeadTop_End）进 `EXTRA_MAP` 保留可辨识名，**别让它们撞上契约名**。
- 动画重定向公式（**方向别写反**，写反会产生 80~141° 系统性偏差，容易误判成"重定向失败"）：
  `M_t = M_s @ R_s⁻¹ @ R_t`，其中 `R = matrix_local.to_3x3()`。先解出源姿态相对源静止的局部旋转，再乘目标静止旋转。
- ⛔ **全身位移必须显式搬**：若源动作把位移放在 `Hip`（根骨无动画），而目标 `Hip` 的父骨**不是 None**，把位移搬运写在 `parent is None` 分支里 ⇒ **永不执行**，静默丢掉走路起伏 / 倒地后滑。
  判据：`hip_path_err_m == 源 hip_travel_m`（目标位移恒 0）即命中本坑。
- 保真判据用 **Δ = M_pose · R_rest⁻¹ 逐帧一致**（本路径 Δ_t ≡ Δ_s，实测可到 0.0000°）；
  **不要**用骨指向轴（bone Y 方向角）——两套骨架静止 roll 常差 ~90°，轴指向必然有差，会把正常静止差误读成重定向失败。
- 源数据自带"无顶点组的骨"（如 `*4` 指尖骨、`Toe_End`）先回查**原始 FBX** 是否本就如此；是则属源特性、非本次引入，别当缺陷去"修"，但要在报告里说明。
- 验收补三件：局部性探针（旋转单骨，被移动顶点须落在该骨主导组内）、自运动幅度（防动作被冻成静态帧）、持枪/变体剪辑与基础剪辑的逐骨差（防占位复制，但**位移差异也要看**，不要只比旋转）。

### S4 源级预览'''

# the anchor line ends with a CRLF; insert the new section right before S4 heading
s4 = b'### S4 \xe6\xba\x90\xe7\xba\xa7\xe9\xa2\x84\xe8\xa7\x88'
i4 = raw.find(s4)
assert i4 != -1, 'S4 heading not found'

payload = new_section.replace('\n', '\r\n').encode('utf-8')
payload = payload[:payload.rfind(b'\r\n') + 2]  # drop trailing crlf duplicated with original
out = raw[:i4] + payload + raw[i4:]
SK.write_bytes(out)

chk = SK.read_bytes()
print('CR', chk.count(b'\r'), 'LF', chk.count(b'\n'))
assert chk.count(b'\r') == chk.count(b'\n'), 'CRLF purity broken'
print('S3B_INSERTED_OK')
