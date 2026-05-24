class_name GridConstants
## 房间格子系统常量
## 所有房间尺寸/坐标计算统一使用此文件，避免硬编码数字散落

## 格子系统
const CELL_SIZE: int = 64  # 单元格尺寸（pixels）
const ROOM_CELLS_X: int = 15  # 房间横向格子数（15 × 64 = 960px）
const ROOM_CELLS_Y: int = 12  # 房间纵向格子数（12 × 64 = 768px）

## 房间像素尺寸（用于碰撞体/相机边界）
## 实际使用 ROOM_CELLS_X * CELL_SIZE 作为宽度
const ROOM_PIXEL_WIDTH: int = ROOM_CELLS_X * CELL_SIZE   # 960
const ROOM_PIXEL_HEIGHT: int = ROOM_CELLS_Y * CELL_SIZE  # 768

## 房间原点偏移（TileMap 填充时的偏移量，让格子以房间中心为原点）
## 负半轴 + 正半轴 = 一个方向的总格子数
const ROOM_OFFSET_X: int = -ROOM_PIXEL_WIDTH / 2   # -480
const ROOM_OFFSET_Y: int = -ROOM_PIXEL_HEIGHT / 2  # -384

## 门洞配置
const DOOR_WIDTH: int = 132  # 门洞宽度（pixels）
const DOOR_CELL_WIDTH: int = int(DOOR_WIDTH / CELL_SIZE) + 1  # 门洞占格子数（约3格）

## 边界碰撞体厚度
const BOUNDARY_THICKNESS: float = 40.0

## 边界碰撞体偏移（碰撞体在房间边缘外侧）
const BOUNDARY_OFFSET: float = BOUNDARY_THICKNESS * 0.5  # 20.0

## ===== 坐标转换工具 =====

## 像素坐标 → 格子坐标（向下取整）
static func pixel_to_cell(pixel: Vector2) -> Vector2i:
	return Vector2i(floor(pixel.x / CELL_SIZE), floor(pixel.y / CELL_SIZE))

## 格子坐标 → 像素坐标（格子左上角）
static func cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)

## 格子坐标 → 像素坐标（格子中心）
static func cell_center_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL_SIZE + CELL_SIZE / 2, cell.y * CELL_SIZE + CELL_SIZE / 2)

## 像素坐标是否在房间范围内（不含边界）
static func is_in_room_bounds(pixel: Vector2, room_pixel_size: Vector2) -> bool:
	var half: Vector2 = room_pixel_size * 0.5
	return pixel.x >= -half.x and pixel.x <= half.x and pixel.y >= -half.y and pixel.y <= half.y

## 像素坐标是否在有效房间格子上（不含边缘墙格）
static func is_valid_room_cell(pixel: Vector2) -> bool:
	var cell: Vector2i = pixel_to_cell(pixel)
	return cell.x >= 1 and cell.x < ROOM_CELLS_X - 1 and cell.y >= 1 and cell.y < ROOM_CELLS_Y - 1

## 获取方向名称字符串（用于调试/日志）
static func direction_name(dir: Vector2) -> String:
	if dir == Vector2.UP: return "UP"
	if dir == Vector2.DOWN: return "DOWN"
	if dir == Vector2.LEFT: return "LEFT"
	if dir == Vector2.RIGHT: return "RIGHT"
	if dir == Vector2(1, -1): return "UP_RIGHT"
	if dir == Vector2(1, 1): return "DOWN_RIGHT"
	if dir == Vector2(-1, -1): return "UP_LEFT"
	if dir == Vector2(-1, 1): return "DOWN_LEFT"
	return "UNKNOWN"