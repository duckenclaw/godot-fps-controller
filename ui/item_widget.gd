class_name ItemWidget
extends Control

## A placed item on the inventory grid. Sized (w*cell, h*cell). Drag source.

signal throw_requested(anchor: int, amount: int)

var inventory: Inventory
var anchor: int = 0
var cell_size: int = 64

var _icon_rect: TextureRect
var _count_label: Label
var _saved_mouse_filter: int = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	_icon_rect = TextureRect.new()
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_icon_rect.anchor_right = 1.0
	_icon_rect.anchor_bottom = 1.0
	_icon_rect.offset_left = 4
	_icon_rect.offset_top = 4
	_icon_rect.offset_right = -4
	_icon_rect.offset_bottom = -4
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_rect)

	_count_label = Label.new()
	_count_label.anchor_left = 1.0
	_count_label.anchor_top = 1.0
	_count_label.anchor_right = 1.0
	_count_label.anchor_bottom = 1.0
	_count_label.offset_left = -28
	_count_label.offset_top = -20
	_count_label.offset_right = -4
	_count_label.offset_bottom = -2
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	refresh()

func refresh() -> void:
	var s: InventorySlot = inventory.get_slot_at_anchor(anchor) if inventory else null
	if s == null or s.is_empty():
		_icon_rect.texture = null
		_count_label.text = ""
		return
	_icon_rect.texture = s.item.icon
	_count_label.text = str(s.count) if s.count > 1 else ""

func _get_drag_data(at_position: Vector2) -> Variant:
	var s: InventorySlot = inventory.get_slot_at_anchor(anchor) if inventory else null
	if s == null or s.is_empty():
		return null

	# Figure out which cell within the item the user grabbed.
	var pick_dx: int = clamp(int(at_position.x / float(cell_size)), 0, s.item.slots.x - 1)
	var pick_dy: int = clamp(int(at_position.y / float(cell_size)), 0, s.item.slots.y - 1)

	var preview: TextureRect = TextureRect.new()
	preview.texture = s.item.icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.custom_minimum_size = Vector2(s.item.slots.x * cell_size, s.item.slots.y * cell_size)
	preview.modulate = Color(1, 1, 1, 0.75)
	set_drag_preview(preview)

	# Let cells below receive the drop.
	_saved_mouse_filter = mouse_filter
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	return {
		"source": "grid",
		"anchor": anchor,
		"pick_dx": pick_dx,
		"pick_dy": pick_dy,
	}

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		mouse_filter = _saved_mouse_filter

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.ctrl_pressed:
		throw_requested.emit(anchor, 1)
		accept_event()

func _make_custom_tooltip(_for_text: String) -> Object:
	var s: InventorySlot = inventory.get_slot_at_anchor(anchor) if inventory else null
	if s == null or s.is_empty():
		return null
	var item: ItemResource = s.item
	var panel: PanelContainer = PanelContainer.new()
	var vb: VBoxContainer = VBoxContainer.new()
	panel.add_child(vb)
	var name_lbl: Label = Label.new()
	name_lbl.text = item.display_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	vb.add_child(name_lbl)
	_add_info(vb, "Type: %s" % String(item.type))
	_add_info(vb, "Weight: %.2f kg" % item.weight)
	_add_info(vb, "Price: %.2f \u20AC" % item.price)
	_add_info(vb, "Slots: %d x %d" % [item.slots.x, item.slots.y])
	_add_info(vb, "Stack: %d / %d" % [s.count, item.max_stack])
	if item.is_weapon():
		_add_info(vb, "Grip: %s" % String(item.grip))
		_add_info(vb, "Damage: %.0f" % item.damage)
		_add_info(vb, "Speed: %.2fx" % item.speed)
	if item.description != "":
		var desc: Label = Label.new()
		desc.text = item.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc.custom_minimum_size.x = 220
		vb.add_child(desc)
	return panel

func _add_info(parent: VBoxContainer, text: String) -> void:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)
