class_name InventorySlotUI
extends Control

## Single-cell slot widget for the quick-equip bar.
## Drag source payload: {"source": "quick", "quick_index": int}
## Accepts drops from grid items (binds the quick slot to the grid anchor)
## and from other quick slots (swap).

signal throw_requested(anchor: int, amount: int)

const SLOT_SIZE: Vector2 = Vector2(64, 64)

@export var slot_bg: Texture2D

var inventory: Inventory
var index: int = 0  # quick_index

var _bg_rect: TextureRect
var _icon_rect: TextureRect
var _count_label: Label
var _outline: Panel

func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP

	_bg_rect = TextureRect.new()
	_bg_rect.texture = slot_bg
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_bg_rect.anchor_right = 1.0
	_bg_rect.anchor_bottom = 1.0
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_rect)

	_outline = Panel.new()
	_outline.anchor_right = 1.0
	_outline.anchor_bottom = 1.0
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.visible = false
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1.0, 0.85, 0.2, 1.0)
	sb.set_border_width_all(3)
	sb.shadow_color = Color(1.0, 0.85, 0.2, 0.6)
	sb.shadow_size = 6
	_outline.add_theme_stylebox_override("panel", sb)
	add_child(_outline)

	_icon_rect = TextureRect.new()
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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

func _get_slot() -> InventorySlot:
	if inventory == null:
		return null
	var anchor: int = inventory.get_quick_index(index)
	return inventory.get_slot_at_anchor(anchor) if anchor >= 0 else null

func _get_item() -> ItemResource:
	var s: InventorySlot = _get_slot()
	return s.item if s else null

func refresh() -> void:
	var s: InventorySlot = _get_slot()
	if s == null or s.is_empty():
		_icon_rect.texture = null
		_count_label.text = ""
	else:
		_icon_rect.texture = s.item.icon
		_count_label.text = str(s.count) if s.count > 1 else ""

func set_outline(active: bool) -> void:
	if _outline:
		_outline.visible = active

func _get_drag_data(_at_position: Vector2) -> Variant:
	var s: InventorySlot = _get_slot()
	if s == null or s.is_empty():
		return null

	var preview: TextureRect = TextureRect.new()
	preview.texture = s.item.icon
	preview.custom_minimum_size = SLOT_SIZE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var wrap: Control = Control.new()
	wrap.custom_minimum_size = SLOT_SIZE
	wrap.add_child(preview)
	preview.anchor_right = 1.0
	preview.anchor_bottom = 1.0
	set_drag_preview(wrap)

	return {"source": "quick", "quick_index": index}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var src: String = data.get("source", "")
	return src == "grid" or src == "quick"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if inventory == null:
		return
	var src: String = data.get("source", "")
	if src == "grid":
		var anchor: int = data.get("anchor", -1)
		if anchor >= 0:
			inventory.set_quick(index, anchor)
	elif src == "quick":
		inventory.swap_quick(index, data.get("quick_index", -1))

func _make_custom_tooltip(_for_text: String) -> Object:
	var s: InventorySlot = _get_slot()
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
	_info(vb, "Type: %s" % String(item.type))
	_info(vb, "Weight: %.2f kg" % item.weight)
	_info(vb, "Price: %.2f \u20AC" % item.price)
	_info(vb, "Slots: %d x %d" % [item.slots.x, item.slots.y])
	_info(vb, "Stack: %d / %d" % [s.count, item.max_stack])
	if item.is_weapon():
		_info(vb, "Grip: %s" % String(item.grip))
		_info(vb, "Damage: %.0f" % item.damage)
		_info(vb, "Speed: %.2fx" % item.speed)
	if item.description != "":
		var desc: Label = Label.new()
		desc.text = item.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc.custom_minimum_size.x = 220
		vb.add_child(desc)
	return panel

func _info(parent: VBoxContainer, text: String) -> void:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.ctrl_pressed:
		var s: InventorySlot = _get_slot()
		if s == null or s.is_empty():
			return
		var anchor: int = inventory.get_quick_index(index)
		if anchor < 0:
			return
		throw_requested.emit(anchor, 1)
		accept_event()
