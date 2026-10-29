extends StaticBody3D
## Projectile3D hits this collider directly: forward the real shot direction.


func take_damage(
	damage: int,
	critical: bool = false,
	direction: Vector3 = Vector3.ZERO,
	knockback: float = 0.0
) -> void:
	var owner := get_parent() as BreakableClutter3D
	if owner != null:
		owner.take_damage(damage, critical, direction, knockback)
