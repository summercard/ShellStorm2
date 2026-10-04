@tool
extends EditorScenePostImport
# Godot may synthesize default tracks for missing glTF channels.
# Keep light-hit suitable for an upper-body-only blending filter.
func _post_import(scene: Node) -> Object:
    _filter(scene)
    return scene
func _filter(node: Node) -> void:
    if node is AnimationPlayer and node.has_animation("hit_light"):
        var clip: Animation = node.get_animation("hit_light")
        var allowed = ["Waist", "Spine01", "Spine02", "Neck", "Head", "HeadTop_End"]
        for index in range(clip.get_track_count() - 1, -1, -1):
            var path: NodePath = clip.track_get_path(index)
            if path.get_subname_count() == 0 or str(path.get_subname(path.get_subname_count() - 1)) not in allowed:
                clip.remove_track(index)
    for child in node.get_children():
        _filter(child)
