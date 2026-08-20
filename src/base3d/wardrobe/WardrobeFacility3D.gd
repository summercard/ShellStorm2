class_name WardrobeFacility3D
extends BaseFacility3D
## 衣柜设施在静态设施目录接线前也可独立实例化验收；正式接线后仍走
## BaseFacility3D.activated -> TowerDescent3D 菜单链，不新增第二套交互逻辑。


func _ready() -> void:
	super()
	facility_id = "avatar_wardrobe"
	display_name = "角色衣柜"
	description = "更换身体、头部、手部、脚部、帽子与眼镜外观"
	activation_type = ActivationType.OPEN_MENU
	menu_scene_path = "res://scenes/ui/WardrobeMenu3D.tscn"
	apply_snapshot({
		"available": true,
		"display_name": display_name,
		"summary": "外观档案已连接",
		"description": description,
		"action_kind": "menu",
	})
