"""Build the textured Arms Taker GLB from its mesh and validated motion donor.

Run with Blender in background: --python this_file -- MODEL.glb MOTION.glb OUTPUT.glb
"""

import json
import struct
import sys
from bisect import bisect_right
from pathlib import Path

import numpy as np
from mathutils import Matrix, Quaternion, Vector


def read_glb(path):
    payload = path.read_bytes()
    magic, version, size, json_size, chunk = struct.unpack_from("<4sIII4s", payload)
    assert (magic, version, size, chunk) == (b"glTF", 2, len(payload), b"JSON")
    binary_size, chunk = struct.unpack_from("<I4s", payload, 20 + json_size)
    binary = payload[28 + json_size:]
    assert chunk == b"BIN\0" and len(binary) == binary_size
    return json.loads(payload[20:20 + json_size]), bytearray(binary)


def write_glb(path, doc, binary):
    binary.extend(b"\0" * (-len(binary) % 4))
    doc["buffers"][0]["byteLength"] = len(binary)
    metadata = json.dumps(doc, separators=(",", ":"), ensure_ascii=False).encode()
    metadata += b" " * (-len(metadata) % 4)
    header = struct.pack("<4sIII4s", b"glTF", 2, len(metadata) + len(binary) + 28, len(metadata), b"JSON")
    path.write_bytes(header + metadata + struct.pack("<I4s", len(binary), b"BIN\0") + binary)


def accessor_values(doc, binary, index):
    accessor = doc["accessors"][index]
    view = doc["bufferViews"][accessor["bufferView"]]
    widths = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
    codes = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
    item = struct.Struct("<" + codes[accessor["componentType"]] * widths[accessor["type"]])
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", item.size)
    return [item.unpack_from(binary, start + stride * index) for index in range(accessor["count"])]


def append_accessor(doc, binary, values, kind, bounds=False):
    binary.extend(b"\0" * (-len(binary) % 4))
    offset = len(binary)
    item = struct.Struct("<" + "f" * len(values[0]))
    for value in values:
        binary.extend(item.pack(*value))
    view = len(doc["bufferViews"])
    doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(binary) - offset})
    accessor = {"bufferView": view, "componentType": 5126, "count": len(values), "type": kind}
    if bounds:
        columns = list(zip(*values))
        accessor["min"] = [min(column) for column in columns]
        accessor["max"] = [max(column) for column in columns]
    doc["accessors"].append(accessor)
    return len(doc["accessors"]) - 1


def rotation(values):
    x, y, z, w = values
    return Quaternion((w, x, y, z)).normalized()


def node_rotation(node):
    return rotation(node.get("rotation", (0, 0, 0, 1)))


def rig(doc):
    nodes = doc["nodes"]
    root = doc["scenes"][doc.get("scene", 0)]["nodes"]
    assert len(root) == 1 and nodes[root[0]]["name"] == "Armature"
    parents = {}
    globals_by_name = {}
    indices = {}

    def visit(index, parent, orientation):
        node = nodes[index]
        name = node["name"]
        assert name not in indices and "matrix" not in node
        indices[name] = index
        parents[name] = parent
        if parent is not None:
            orientation = orientation @ node_rotation(node)
        globals_by_name[name] = orientation
        for child in node.get("children", []):
            visit(child, name, orientation)

    visit(root[0], None, Quaternion())
    return indices, parents, globals_by_name


def retarget(model, mesh_binary, motion, motion_binary):
    model_ids, model_parents, model_rest = rig(model)
    motion_ids, motion_parents, motion_rest = rig(motion)
    motion_targets = {motion["nodes"][c["target"]["node"]]["name"]
                      for clip in motion["animations"] for c in clip["channels"]}
    assert len(motion_targets) == 42
    assert all(model_parents[name] == motion_parents[name] for name in motion_targets)
    correction = {name: motion_rest[name].inverted() @ model_rest[name] for name in motion_targets}
    model_armature = model["nodes"][model_ids["Armature"]]
    motion_armature = motion["nodes"][motion_ids["Armature"]]
    for key in ("scale", "rotation"):
        model_armature[key] = motion_armature[key]

    time_accessors = {}
    model["animations"] = []
    for clip in motion["animations"]:
        output = {"name": clip["name"], "channels": [], "samplers": []}
        for channel in clip["channels"]:
            target = channel["target"]
            name = motion["nodes"][target["node"]]["name"]
            path = target["path"]
            sampler = clip["samplers"][channel["sampler"]]
            interpolation = sampler.get("interpolation", "LINEAR")
            assert interpolation in ("LINEAR", "STEP")
            old_node = motion["nodes"][motion_ids[name]]
            new_node = model["nodes"][model_ids[name]]
            parent_correction = correction.get(model_parents[name], Quaternion()).inverted()
            samples = accessor_values(motion, motion_binary, sampler["output"])
            if path == "rotation":
                quats = [(parent_correction @ rotation(value) @ correction[name]).normalized() for value in samples]
                values = [(q.x, q.y, q.z, q.w) for q in quats]
            elif path == "translation":
                old_offset = Vector(old_node.get(path, (0, 0, 0)))
                new_offset = Vector(new_node.get(path, (0, 0, 0)))
                values = [new_offset + parent_correction @ (Vector(value) - old_offset) for value in samples]
            else:
                assert path == "scale"
                factor = [new / old for old, new in zip(old_node.get(path, (1, 1, 1)), new_node.get(path, (1, 1, 1)))]
                values = [tuple(a * b for a, b in zip(value, factor)) for value in samples]

            time_index = sampler["input"]
            if time_index not in time_accessors:
                times = accessor_values(motion, motion_binary, time_index)
                time_accessors[time_index] = append_accessor(model, mesh_binary, times, "SCALAR", bounds=True)
            output["channels"].append({"sampler": len(output["samplers"]), "target": {"node": model_ids[name], "path": path}})
            output["samplers"].append({
                "input": time_accessors[time_index],
                "output": append_accessor(model, mesh_binary, values, "VEC4" if path == "rotation" else "VEC3"),
                "interpolation": interpolation,
            })
        model["animations"].append(output)


def print_limb_bounds(model, binary):
    skin = model["skins"][0]
    joint_names = [model["nodes"][index]["name"] for index in skin["joints"]]
    inverse_bind = [
        Matrix([values[i:i + 4] for i in range(0, 16, 4)]).transposed()
        for values in accessor_values(model, binary, skin["inverseBindMatrices"])
    ]
    prim = model["meshes"][0]["primitives"][0]["attributes"]
    positions, joints, weights = [
        accessor_values(model, binary, prim[key]) for key in ("POSITION", "JOINTS_0", "WEIGHTS_0")
    ]
    boxes = {}
    for pos, influences, values in zip(positions, joints, weights):
        joint = influences[max(range(4), key=values.__getitem__)]
        name = joint_names[joint]
        if "Twist" in name:
            name = name.split("Twist")[0]
        if name.endswith("_ToeBase"):
            name = name.replace("_ToeBase", "_Foot")
        if name in joint_names:
            point = inverse_bind[joint_names.index(name)] @ Vector(pos)
            boxes.setdefault(name, []).append(point)
    for name, points in boxes.items():
        columns = list(zip(*points))
        lo, hi = Vector([min(col) for col in columns]), Vector([max(col) for col in columns])
        print(name, len(points), "center", tuple(round(v, 4) for v in (lo + hi) / 2), "size", tuple(round(v, 4) for v in hi - lo))


class SkinSampler:
    """Sample the skinned surface, including soles and coat, in GLB coordinates."""

    def __init__(self, doc, binary):
        self.doc = doc
        self.binary = binary
        skin = doc["skins"][0]
        self.bones = skin["joints"]
        self.inverse_bind = np.array(accessor_values(doc, binary, skin["inverseBindMatrices"])).reshape(-1, 4, 4).transpose(0, 2, 1)
        attributes = doc["meshes"][0]["primitives"][0]["attributes"]
        self.joints = np.array(accessor_values(doc, binary, attributes["JOINTS_0"]))
        self.weights = np.array(accessor_values(doc, binary, attributes["WEIGHTS_0"]))
        positions = np.array(accessor_values(doc, binary, attributes["POSITION"]))
        self.points = np.column_stack([positions, np.ones(len(positions))])
        self.nodes = doc["nodes"]
        self.root = doc["scenes"][doc.get("scene", 0)]["nodes"][0]
        self.joint_names = [self.nodes[index]["name"] for index in self.bones]
        self.dominant_joints = self.joints[np.arange(len(self.weights)), self.weights.argmax(axis=1)]
        self.parents = {child: index for index, node in enumerate(self.nodes) for child in node.get("children", [])}

    def read_tracks(self, clip):
        tracks = {}
        for channel in clip["channels"]:
            node = channel["target"]["node"]
            path = channel["target"]["path"]
            sampler = clip["samplers"][channel["sampler"]]
            times = [value[0] for value in accessor_values(self.doc, self.binary, sampler["input"])]
            values = accessor_values(self.doc, self.binary, sampler["output"])
            if path == "rotation":
                values = [rotation(value) for value in values]
            else:
                values = [Vector(value) for value in values]
            tracks[node, path] = times, values, sampler.get("interpolation") == "STEP"
        return tracks

    @staticmethod
    def sample_track(tracks, time, index, path, fallback):
        track = tracks.get((index, path))
        if track is None:
            return fallback
        times, values, step = track
        last = min(len(times) - 1, max(0, bisect_right(times, time) - 1))
        if step or time <= times[last] or last == len(times) - 1:
            return values[last]
        weight = (time - times[last]) / (times[last + 1] - times[last])
        return values[last].slerp(values[last + 1], weight) if path == "rotation" else values[last].lerp(values[last + 1], weight)

    def sample_surface(self, tracks, time):
        transforms = {}

        def visit(index, parent):
            node = self.nodes[index]
            pos = self.sample_track(tracks, time, index, "translation", Vector(node.get("translation", (0, 0, 0))))
            orient = self.sample_track(tracks, time, index, "rotation", node_rotation(node))
            scale = self.sample_track(tracks, time, index, "scale", Vector(node.get("scale", (1, 1, 1))))
            world = parent @ Matrix.LocRotScale(pos, orient, scale)
            transforms[index] = world
            for child in node.get("children", []):
                visit(child, world)

        visit(self.root, Matrix.Identity(4))
        bone_matrices = np.array([transforms[index] for index in self.bones]) @ self.inverse_bind
        joint_heights = np.einsum("nki,ni->nk", bone_matrices[self.joints, 1, :], self.points)
        return np.sum(joint_heights * self.weights, axis=1), transforms

    def sample_min_height(self, tracks, time):
        return float(self.sample_surface(tracks, time)[0].min())


def plant_idle_boots(model, binary, clip, skin, times):
    tracks = skin.read_tracks(clip)
    sample_id = append_accessor(model, binary, [(time,) for time in times], "SCALAR", bounds=True)
    boots = {}
    for side in ("L", "R"):
        foot = f"{side}_Foot"
        joint_ids = [skin.joint_names.index(name) for name in (foot, f"{side}_ToeBase")]
        mask = np.isin(skin.dominant_joints, joint_ids)
        fractions = np.sum(skin.weights[mask] * np.isin(skin.joints[mask], joint_ids), axis=1)
        boots[skin.bones[joint_ids[0]]] = (mask, fractions, [])
    for time in times:
        heights, transforms = skin.sample_surface(tracks, time)
        for foot, (mask, fractions, offsets) in boots.items():
            # The ankle and toe translate together. Weighted calf influence
            # stays fixed and is accounted for when finding first sole contact.
            delta_y = float(np.max(-heights[mask] / fractions))
            parent_space = transforms[skin.parents[foot]].to_3x3().inverted()
            position = skin.sample_track(tracks, time, foot, "translation", Vector(skin.nodes[foot]["translation"]))
            offsets.append(position + parent_space @ Vector((0.0, delta_y, 0.0)))
    for foot, (_, _, offsets) in boots.items():
        channel = next(channel for channel in clip["channels"]
                       if channel["target"] == {"node": foot, "path": "translation"})
        clip["samplers"][channel["sampler"]] = {
            "input": sample_id,
            "output": append_accessor(model, binary, offsets, "VEC3"),
            "interpolation": "LINEAR",
        }
    corrected = skin.read_tracks(clip)
    maximum_error = 0.0
    for time in times:
        heights, _ = skin.sample_surface(corrected, time)
        maximum_error = max(maximum_error, *(abs(float(heights[mask].min())) for mask, _, _ in boots.values()))
    assert maximum_error < 0.001
    print("IDLE_BOTH_BOOTS_MAX_ERROR_M", round(maximum_error, 6), flush=True)


def bake_ground_contact(model, mesh_binary, motion, motion_binary):
    # Keep each stance frame planted using the lowest skinned vertex. For running
    # and death, keep any clearance intentionally present in the source clip.
    planted_clips = ("idle", "walk", "attack_light", "hit")
    clearance_clips = ("run", "death")
    model_skin = SkinSampler(model, mesh_binary)
    source_skin = SkinSampler(motion, motion_binary)
    for target_clip, source_clip in zip(model["animations"], motion["animations"]):
        name = target_clip["name"]
        if name not in planted_clips + clearance_clips:
            continue
        target_tracks = model_skin.read_tracks(target_clip)
        source_tracks = source_skin.read_tracks(source_clip)
        key_times = sorted(set(time for keys, _, _ in target_tracks.values() for time in keys))
        samples = [a + (b - a) * part / 4 for a, b in zip(key_times, key_times[1:]) for part in range(4)]
        times = sorted(set(np.float32(samples + key_times).tolist()))
        root = model_skin.root
        root_channel = next(channel for channel in target_clip["channels"]
                            if channel["target"] == {"node": root, "path": "translation"})
        root_times, root_values, _ = target_tracks[root, "translation"]
        target_y = np.array([model_skin.sample_min_height(target_tracks, time) for time in times])
        clearance = np.zeros(len(times))
        if name in clearance_clips:
            clearance = np.maximum(0, [source_skin.sample_min_height(source_tracks, time) for time in times])
        positions = np.array([np.interp(times, root_times, axis) for axis in zip(*root_values)]).T
        positions[:, 1] += clearance - target_y
        target_clip["samplers"][root_channel["sampler"]] = {
            "input": append_accessor(model, mesh_binary, [(time,) for time in times], "SCALAR", bounds=True),
            "output": append_accessor(model, mesh_binary, positions.tolist(), "VEC3"),
            "interpolation": "LINEAR",
        }
        # Verify at the intermediate physics frames too, after writing float32 keys.
        corrected_tracks = model_skin.read_tracks(target_clip)
        midpoints = [(a + b) / 2 for a, b in zip(times, times[1:])]
        probe_times = sorted(times + midpoints)
        corrected = np.array([model_skin.sample_min_height(corrected_tracks, time) for time in probe_times])
        expected = np.interp(probe_times, times, clearance)
        error = max(abs(corrected - expected))
        print("GROUND_PROFILE", name, "before", np.round([min(target_y), max(target_y)], 4),
              "after", np.round([min(corrected), max(corrected)], 4), "max_error", round(error, 4), flush=True)
        assert error < 0.025, f"{name} departed from authored ground clearance"
        if name == "idle":
            plant_idle_boots(model, mesh_binary, target_clip, model_skin, times)


if __name__ == "__main__":
    model_path, motion_path, output_path = map(Path, sys.argv[sys.argv.index("--") + 1:])
    model, mesh_binary = read_glb(model_path)
    motion, motion_binary = read_glb(motion_path)
    assert not model.get("animations") and len(motion["animations"]) == 18
    assert len(model["skins"]) == 1 and len(model["skins"][0]["joints"]) == 41
    assert len(model["images"]) == 3 and not model.get("cameras") and not model.get("extensionsUsed")
    for image, name in zip(model["images"], ("normal", "albedo", "metallic_roughness")):
        image["name"] = name
    print_limb_bounds(model, mesh_binary)
    retarget(model, mesh_binary, motion, motion_binary)
    bake_ground_contact(model, mesh_binary, motion, motion_binary)
    write_glb(output_path, model, mesh_binary)
    print("RETARGET_OK", len(model["animations"]), output_path)
