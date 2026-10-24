class_name InventoryScreen
extends Control

## Full inventory UI: 8x5 grid + 8 quick slots, drag/drop with snap, sort, throw.

const SLOT_BG: Texture2D = preload("res://assets/images/slot-bg.png")
const PICKUP_SCENE: PackedScene = preload("res://addons/fps_controller/items/pickup.tscn")
const CELL_SIZE: int = 64

@onready var _grid_area: Control = $Root/MarginContainer/HBoxContainer/Left/GridArea
@onready var _quick_bar: HBoxContainer = $Root/MarginContainer/HBoxContainer/Left/QuickBar
@onready var _sort_button: Button = $Root/MarginContainer/HBoxContainer/Right/SortButton
@onready var _weight_label: Label = $Root/MarginContainer/HBoxContainer/Right/WeightLabel
@onready var _price_label: Label = $Root/MarginContainer/HBoxContainer/Right/PriceLabel
@onready var _toast: Label = $Root/ToastLabel

var player: Node
var inventory: Inventory

var _grid_cells: Array[GridCellUI] = []
var _item_widgets: Array[ItemWidget] = []
var _quick_slots: Array[InventorySlotUI] = []

var _items_layer: Control
var _snap_ghost: Panel

var _toast_timer: float = 0.0

# --- controller / keyboard navigation ---
# A focus cursor drives the grid + quick bar for gamepad play; "carry" mode is the
# controller equivalent of a mouse drag (grab an item, move the cursor, drop it).
var _cursor_panel: Panel
var _cursor_zone: String = "grid"   # "grid" | "quick"
var _cursor_cell: int = 0           # grid cell 0..GRID_SIZE-1 (grid zone)
var _cursor_quick: int = 0          # quick slot 0..QUICK_COUNT-1 (quick zone)
var _carrying: bool = false
var _carry_anchor: int = -1

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_toast.visible = false
	_sort_button.pressed.connect(_on_sort_pressed)
	set_process(true)

	_grid_area.custom_minimum_size = Vector2(Inventory.GRID_W * CELL_SIZE, Inventory.GRID_H * CELL_SIZE)
	_grid_area.mouse_filter = Control.MOUSE_FILTER_PASS

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Close (inventory button, or the pause button)
	if event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
		return

	# Cancel a carry, or close if not carrying (B / Esc)
	if event.is_action_pressed("ui_cancel"):
		_cancel_or_close()
		get_viewport().set_input_as_handled()
		return

	# Sort (X / reload button) — only react to the discrete press, not mouse.
	if event.is_action_pressed("reload") and not event is InputEventMouseButton:
		if inventory:
			inventory.sort_by_type()
		get_viewport().set_input_as_handled()
		return

	# Directional navigation (D-pad / left stick / arrow keys)
	if event.is_action_pressed("ui_left"):
		_move_cursor(-1, 0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_right"):
		_move_cursor(1, 0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up"):
		_move_cursor(0, -1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down"):
		_move_cursor(0, 1)
		get_viewport().set_input_as_handled()
		return

	# Activate: grab/drop an item, or equip a quick slot (A / Enter)
	if event.is_action_pressed("ui_accept"):
		_activate()
		get_viewport().set_input_as_handled()
		return

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_hide_snap_ghost()

func bind(p_player: Node) -> void:
	player = p_player
	inventory = p_player.get_node("Inventory")
	inventory.changed.connect(_on_inventory_changed)
	inventory.quick_changed.connect(_on_inventory_changed)
	inventory.pickup_failed.connect(_on_pickup_failed)
	_build_ui()
	_refresh()

func _build_ui() -> void:
	for c in _grid_area.get_children():
		c.queue_free()
	for c in _quick_bar.get_children():
		c.queue_free()
	_grid_cells.clear()
	_item_widgets.clear()
	_quick_slots.clear()

	# 40 grid background / drop cells (absolute positioned).
	for i in Inventory.GRID_SIZE:
		var cell: GridCellUI = GridCellUI.new()
		cell.slot_bg = SLOT_BG
		cell.cell_index = i
		cell.inventory = inventory
		cell.screen = self
		cell.size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.position = Vector2(Inventory.x_of(i) * CELL_SIZE, Inventory.y_of(i) * CELL_SIZE)
		_grid_area.add_child(cell)
		_grid_cells.append(cell)

	# Items layer above cells. IGNORE so the layer itself never intercepts mouse
	# events — individual ItemWidget children still handle drag via their own filter.
	_items_layer = Control.new()
	_items_layer.name = "ItemsLayer"
	_items_layer.anchor_right = 1.0
	_items_layer.anchor_bottom = 1.0
	_items_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_area.add_child(_items_layer)

	# Snap ghost on top.
	_snap_ghost = Panel.new()
	_snap_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snap_ghost.visible = false
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.9, 0.4, 0.25)
	sb.border_color = Color(0.3, 0.9, 0.4, 0.9)
	sb.set_border_width_all(2)
	_snap_ghost.add_theme_stylebox_override("panel", sb)
	_grid_area.add_child(_snap_ghost)

	# Quick bar (8 slots).
	for i in Inventory.QUICK_COUNT:
		var q: InventorySlotUI = InventorySlotUI.new()
		q.slot_bg = SLOT_BG
		q.inventory = inventory
		q.index = i
		q.throw_requested.connect(_on_throw_requested)
		_quick_bar.add_child(q)
		_quick_slots.append(q)

	_rebuild_item_widgets()

func _rebuild_item_widgets() -> void:
	if _items_layer == null:
		return
	for w in _item_widgets:
		w.queue_free()
	_item_widgets.clear()

	for anchor in inventory.all_anchors():
		var s: InventorySlot = inventory.get_slot_at_anchor(anchor)
		if s == null:
			continue
		var iw: ItemWidget = ItemWidget.new()
		iw.inventory = inventory
		iw.anchor = anchor
		iw.cell_size = CELL_SIZE
		iw.size = Vector2(s.item.slots.x * CELL_SIZE, s.item.slots.y * CELL_SIZE)
		iw.position = Vector2(Inventory.x_of(anchor) * CELL_SIZE, Inventory.y_of(anchor) * CELL_SIZE)
		iw.throw_requested.connect(_on_throw_requested)
		_items_layer.add_child(iw)
		_item_widgets.append(iw)

func _on_inventory_changed() -> void:
	_refresh()

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player and "is_inventory_open" in player:
		player.is_inventory_open = true
	get_tree().paused = true
	# Reset the navigation cursor to the first item (or top-left cell).
	_carrying = false
	_carry_anchor = -1
	_cursor_zone = "grid"
	var anchors: Array[int] = inventory.all_anchors() if inventory else []
	_cursor_cell = anchors[0] if anchors.size() > 0 else 0
	_cursor_quick = 0
	_ensure_cursor_panel()
	_refresh()
	# Defer so container layout is settled before we read global rects.
	call_deferred("_update_cursor")

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if player and "is_inventory_open" in player:
		player.is_inventory_open = false
	get_tree().paused = false
	# Stop the closing button (e.g. B, also dash) from leaking into gameplay.
	if player and player.has_method("suppress_action_input"):
		player.suppress_action_input()
	_carrying = false
	_carry_anchor = -1
	if _cursor_panel:
		_cursor_panel.visible = false
	_hide_snap_ghost()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func _refresh() -> void:
	_rebuild_item_widgets()
	for q in _quick_slots:
		q.refresh()
	if inventory:
		_weight_label.text = "Weight: %.2f kg" % inventory.total_weight()
		_price_label.text = "Value: %.2f \u20AC" % inventory.total_price()
	_update_outlines()
	_update_cursor()

func _update_outlines() -> void:
	if player == null:
		return
	var left: ItemResource = player.get("equipped_left_item")
	var right: ItemResource = player.get("equipped_right_item")
	for q in _quick_slots:
		var it: ItemResource = q._get_item()
		q.set_outline(it != null and (it == left or it == right))

func _on_sort_pressed() -> void:
	if inventory:
		inventory.sort_by_type()

# -------- controller / keyboard cursor --------

func _ensure_cursor_panel() -> void:
	if _cursor_panel != null:
		return
	_cursor_panel = Panel.new()
	_cursor_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_panel.top_level = true  # position/size in global canvas space
	_cursor_panel.visible = false
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.85, 0.2, 0.15)
	sb.border_color = Color(1, 0.85, 0.2, 1)
	sb.set_border_width_all(3)
	_cursor_panel.add_theme_stylebox_override("panel", sb)
	add_child(_cursor_panel)

## Reposition/recolor the focus cursor for the current zone and carry state.
func _update_cursor() -> void:
	if _cursor_panel == null or not visible or inventory == null:
		return
	var rect: Rect2 = _current_cursor_rect()
	if rect.size == Vector2.ZERO:
		_cursor_panel.visible = false
		return
	_cursor_panel.global_position = rect.position
	_cursor_panel.size = rect.size

	var col: Color = Color(1, 0.85, 0.2)  # neutral focus (yellow)
	if _carrying:
		col = Color(0.3, 0.9, 0.4) if _carry_target_valid() else Color(0.9, 0.3, 0.3)
	var sb: StyleBoxFlat = _cursor_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_color = col
		sb.bg_color = Color(col.r, col.g, col.b, 0.15)
	_cursor_panel.visible = true
	_cursor_panel.move_to_front()

## Global-space rectangle the cursor should cover right now.
func _current_cursor_rect() -> Rect2:
	if _cursor_zone == "quick":
		var qi: int = clampi(_cursor_quick, 0, _quick_slots.size() - 1)
		if qi >= 0 and qi < _quick_slots.size():
			return _quick_slots[qi].get_global_rect()
		return Rect2()

	var base: Vector2 = _grid_area.global_position
	if _carrying:
		var s: InventorySlot = inventory.get_slot_at_anchor(_carry_anchor)
		var w: int = s.item.slots.x if s else 1
		var h: int = s.item.slots.y if s else 1
		var x: int = clampi(Inventory.x_of(_cursor_cell), 0, Inventory.GRID_W - w)
		var y: int = clampi(Inventory.y_of(_cursor_cell), 0, Inventory.GRID_H - h)
		return Rect2(base + Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(w * CELL_SIZE, h * CELL_SIZE))

	# Not carrying: outline the whole item under the cursor, or a single empty cell.
	var owner: int = inventory.get_anchor_of_cell(_cursor_cell)
	if owner >= 0:
		var s2: InventorySlot = inventory.get_slot_at_anchor(owner)
		var ax: int = Inventory.x_of(owner)
		var ay: int = Inventory.y_of(owner)
		return Rect2(base + Vector2(ax * CELL_SIZE, ay * CELL_SIZE),
			Vector2(s2.item.slots.x * CELL_SIZE, s2.item.slots.y * CELL_SIZE))
	var cx: int = Inventory.x_of(_cursor_cell)
	var cy: int = Inventory.y_of(_cursor_cell)
	return Rect2(base + Vector2(cx * CELL_SIZE, cy * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))

## Would dropping the carried item at the cursor be accepted?
func _carry_target_valid() -> bool:
	if _cursor_zone == "quick":
		return true
	var s: InventorySlot = inventory.get_slot_at_anchor(_carry_anchor)
	if s == null:
		return false
	var w: int = s.item.slots.x
	var h: int = s.item.slots.y
	var x: int = clampi(Inventory.x_of(_cursor_cell), 0, Inventory.GRID_W - w)
	var y: int = clampi(Inventory.y_of(_cursor_cell), 0, Inventory.GRID_H - h)
	return inventory.rect_fits(Inventory.xy_to_index(x, y), w, h, _carry_anchor)

## Move the cursor by one grid step (or between grid and quick bar).
func _move_cursor(dx: int, dy: int) -> void:
	if inventory == null:
		return

	if _cursor_zone == "quick":
		if dy < 0:
			# Up out of the quick bar into the grid's bottom row.
			_cursor_zone = "grid"
			var gx: int = clampi(_cursor_quick, 0, Inventory.GRID_W - 1)
			_cursor_cell = Inventory.xy_to_index(gx, Inventory.GRID_H - 1)
		else:
			_cursor_quick = clampi(_cursor_quick + dx, 0, Inventory.QUICK_COUNT - 1)
		_update_cursor()
		return

	# Grid zone
	var x: int = Inventory.x_of(_cursor_cell)
	var y: int = Inventory.y_of(_cursor_cell)
	var start_owner: int = inventory.get_anchor_of_cell(_cursor_cell)
	var nx: int = x + dx
	var ny: int = y + dy

	if ny >= Inventory.GRID_H:
		# Down out of the grid into the quick bar.
		_cursor_zone = "quick"
		_cursor_quick = clampi(x, 0, Inventory.QUICK_COUNT - 1)
		_update_cursor()
		return
	if nx < 0 or nx >= Inventory.GRID_W or ny < 0:
		return

	var ncell: int = Inventory.xy_to_index(nx, ny)
	# When not carrying, step over cells belonging to the same item so one press
	# moves to the next item/empty cell instead of within a multi-cell item.
	if not _carrying and start_owner != -1:
		while inventory.get_anchor_of_cell(ncell) == start_owner:
			nx += dx
			ny += dy
			if nx < 0 or nx >= Inventory.GRID_W or ny < 0:
				return
			if ny >= Inventory.GRID_H:
				_cursor_zone = "quick"
				_cursor_quick = clampi(x, 0, Inventory.QUICK_COUNT - 1)
				_update_cursor()
				return
			ncell = Inventory.xy_to_index(nx, ny)

	_cursor_cell = ncell
	_update_cursor()

## A / Enter: grab or drop when carrying; otherwise grab a grid item or equip a quick slot.
func _activate() -> void:
	if inventory == null:
		return
	if _carrying:
		_drop_carry()
		return
	if _cursor_zone == "quick":
		_equip_cursor_quick()
		return
	var owner: int = inventory.get_anchor_of_cell(_cursor_cell)
	if owner >= 0:
		_carrying = true
		_carry_anchor = owner
		_cursor_cell = owner  # snap to anchor for predictable placement
		_update_cursor()

func _drop_carry() -> void:
	if _cursor_zone == "quick":
		# Binding a grid item to a quick slot (controller equivalent of grid->quick drag).
		inventory.set_quick(_cursor_quick, _carry_anchor)
		_carrying = false
		_carry_anchor = -1
		_update_cursor()
		return

	var s: InventorySlot = inventory.get_slot_at_anchor(_carry_anchor)
	if s == null:
		_carrying = false
		_carry_anchor = -1
		_update_cursor()
		return
	var w: int = s.item.slots.x
	var h: int = s.item.slots.y
	var x: int = clampi(Inventory.x_of(_cursor_cell), 0, Inventory.GRID_W - w)
	var y: int = clampi(Inventory.y_of(_cursor_cell), 0, Inventory.GRID_H - h)
	var dst: int = Inventory.xy_to_index(x, y)

	var src: int = _carry_anchor
	_carrying = false
	_carry_anchor = -1
	if inventory.move_item(src, dst):
		_cursor_cell = dst
	else:
		# Didn't fit — keep carrying so the player can reposition.
		_carrying = true
		_carry_anchor = src
		_show_toast("Won't fit here")
	_update_cursor()

func _equip_cursor_quick() -> void:
	if player == null:
		return
	if player.has_method("equip_from_quick"):
		player.equip_from_quick(_cursor_quick)
		_update_outlines()

func _cancel_or_close() -> void:
	if _carrying:
		_carrying = false
		_carry_anchor = -1
		_update_cursor()
	else:
		close()

func _on_throw_requested(anchor: int, amount: int) -> void:
	_throw_from_anchor(anchor, amount)

func _throw_from_anchor(anchor: int, amount: int) -> void:
	if inventory == null or player == null:
		return
	var slot: InventorySlot = inventory.get_slot_at_anchor(anchor)
	if slot == null or slot.is_empty():
		return
	amount = min(amount, slot.count)
	var item: ItemResource = slot.item
	for _i in amount:
		inventory.remove_one(anchor)
		# After last removal the anchor might be freed, but remove_one handles empties.
	_spawn_thrown(item, amount)

func _spawn_thrown(item: ItemResource, count: int) -> void:
	if count <= 0 or item == null or player == null:
		return
	var cam: Node3D = player.get_node_or_null("CameraPivot/Camera3D")
	if cam == null:
		return
	var forward: Vector3 = -cam.global_transform.basis.z
	var origin: Vector3 = cam.global_position + forward * 0.8
	var velocity: Vector3 = forward * 6.0
	var world: Node = player.get_parent()
	Pickup.spawn(PICKUP_SCENE, item, count, world, origin, velocity)

# -------- background-drop (throw) --------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	return data.get("source", "") == "grid"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data.get("source", "") != "grid":
		return
	var anchor: int = data.get("anchor", -1)
	var slot: InventorySlot = inventory.get_slot_at_anchor(anchor)
	if slot == null:
		return
	_throw_from_anchor(anchor, slot.count)

# -------- snap ghost --------

func on_grid_hover(cell_index: int, data: Variant, is_valid: bool) -> void:
	if data.get("source", "") != "grid":
		_hide_snap_ghost()
		return
	var anchor: int = data.get("anchor", -1)
	var s: InventorySlot = inventory.get_slot_at_anchor(anchor)
	if s == null:
		_hide_snap_ghost()
		return
	var pick_dx: int = data.get("pick_dx", 0)
	var pick_dy: int = data.get("pick_dy", 0)
	var target_x: int = Inventory.x_of(cell_index) - pick_dx
	var target_y: int = Inventory.y_of(cell_index) - pick_dy
	var w: int = s.item.slots.x
	var h: int = s.item.slots.y
	# Clamp into grid for a visible ghost even if invalid.
	target_x = clamp(target_x, 0, Inventory.GRID_W - w)
	target_y = clamp(target_y, 0, Inventory.GRID_H - h)
	_show_snap_ghost(target_x, target_y, w, h, is_valid)

func _show_snap_ghost(cx: int, cy: int, w: int, h: int, is_valid: bool) -> void:
	if _snap_ghost == null:
		return
	_snap_ghost.position = Vector2(cx * CELL_SIZE, cy * CELL_SIZE)
	_snap_ghost.size = Vector2(w * CELL_SIZE, h * CELL_SIZE)
	var sb: StyleBoxFlat = _snap_ghost.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		if is_valid:
			sb.bg_color = Color(0.3, 0.9, 0.4, 0.25)
			sb.border_color = Color(0.3, 0.9, 0.4, 0.9)
		else:
			sb.bg_color = Color(0.9, 0.3, 0.3, 0.25)
			sb.border_color = Color(0.9, 0.3, 0.3, 0.9)
	_snap_ghost.visible = true
	_snap_ghost.get_parent().move_child(_snap_ghost, _snap_ghost.get_parent().get_child_count() - 1)

func _hide_snap_ghost() -> void:
	if _snap_ghost:
		_snap_ghost.visible = false

func on_drag_ended() -> void:
	_hide_snap_ghost()

# -------- toast --------

func _on_pickup_failed(_item: ItemResource, _leftover: int) -> void:
	_show_toast("Not enough space")

func _show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_timer = 2.0

func _process(delta: float) -> void:
	if _toast.visible:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast.visible = false
		elif _toast_timer < 0.6:
			_toast.modulate.a = _toast_timer / 0.6

func show_pickup_failed() -> void:
	_show_toast("Not enough space")
