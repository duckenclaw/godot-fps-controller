class_name GridCellUI
extends Control

## A single background cell in the inventory grid. Acts as a drop target.
## Hover-during-drag is forwarded to the InventoryScreen so it can draw a snap ghost.

signal cell_hovered(cell_index: int, data: Variant)

@export var slot_bg: Texture2D

var cell_index: int = 0
var inventory: Inventory
var screen: InventoryScreen

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg: TextureRect = TextureRect.new()
	bg.texture = slot_bg
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var src: String = data.get("source", "")
	if src == "":
		return false
	var is_valid: bool = src == "grid" and _is_drop_valid(data)
	if screen and src == "grid":
		screen.on_grid_hover(cell_index, data, is_valid)
	# Consume both grid and quick drags so they never fall through to the screen's
	# throw-on-background handler. Invalid grid moves simply no-op in _drop_data.
	return src == "grid" or src == "quick"

func _is_drop_valid(data: Variant) -> bool:
	if inventory == null:
		return false
	var src: String = data.get("source", "")
	if src != "grid":
		return false
	var anchor: int = data.get("anchor", -1)
	var s: InventorySlot = inventory.get_slot_at_anchor(anchor)
	if s == null:
		return false
	var pick_dx: int = data.get("pick_dx", 0)
	var pick_dy: int = data.get("pick_dy", 0)
	var target: int = Inventory.xy_to_index(
		Inventory.x_of(cell_index) - pick_dx,
		Inventory.y_of(cell_index) - pick_dy
	)
	# Bounds + rect fit (ignoring self).
	var tx: int = Inventory.x_of(target)
	var ty: int = Inventory.y_of(target)
	if tx < 0 or ty < 0:
		return false
	var w: int = s.item.slots.x
	var h: int = s.item.slots.y
	return inventory.rect_fits(target, w, h, anchor)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if inventory == null:
		return
	if screen:
		screen.on_drag_ended()
	var src: String = data.get("source", "")
	if src != "grid":
		return  # quick drags are consumed but do nothing on a grid cell
	var anchor: int = data.get("anchor", -1)
	var pick_dx: int = data.get("pick_dx", 0)
	var pick_dy: int = data.get("pick_dy", 0)
	var target_x: int = Inventory.x_of(cell_index) - pick_dx
	var target_y: int = Inventory.y_of(cell_index) - pick_dy
	if target_x < 0 or target_y < 0 or target_x >= Inventory.GRID_W or target_y >= Inventory.GRID_H:
		return
	var target: int = Inventory.xy_to_index(target_x, target_y)
	inventory.move_item(anchor, target)
