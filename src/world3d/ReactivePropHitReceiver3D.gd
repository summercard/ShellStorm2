extends StaticBody3D
## The collider owns forwarding; projectiles never need to know a prop's kind.

func take_damage(amount: int, critical := false, direction := Vector3.ZERO, knockback := 0.0) -> void:
	(get_parent() as ReactiveProp3D).take_damage(amount, critical, direction, knockback)
