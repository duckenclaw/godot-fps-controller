extends Control

const SLOT_BG: Texture2D = preload("res://assets/images/slot-bg.png")
const QUICK_SLOT_SIZE: Vector2 = Vector2(64, 64)

@onready var health_bar: ProgressBar = $MarginContainer/Bars/HealthBar
@onready var health_bar_label: Label = $MarginContainer/Bars/HealthBar/Value

@onready var mana_bar: ProgressBar = $MarginContainer/Bars/ManaBar
@onready var mana_bar_label: Label = $MarginContainer/Bars/ManaBar/Value

@onready var stamina_bar: ProgressBar = $MarginContainer/Bars/StaminaBar
@onready var stamina_bar_label: Label = $MarginContainer/Bars/StaminaBar/Value

@onready var quick_bar: HBoxContainer = $QuickBar
@onready var toast_label: Label = $ToastLabel

var _quick_widgets: Array = []  # Array of {root, icon, label, outline}
var _toast_timer: float = 0.0
var _damage_flash: ColorRect

func _ready() -> void:
	_build_quick_bar()
	_build_damage_flash()
	if toast_label:
		toast_label.visible = false
	set_process(true)

## Full-screen red overlay used for damage feedback. Built in code so the HUD
## scene needs no extra nodes.
func _build_damage_flash() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.6, 0.0, 0.0, 0.0)
	_damage_flash.anchor_right = 1.0
	_damage_flash.anchor_bottom = 1.0
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_flash)

## Flash the screen red briefly (call from the player on taking damage).
func flash_damage(strength: float = 0.4) -> void:
	if _damage_flash == null:
		return
	_damage_flash.color = Color(0.6, 0.0, 0.0, strength)
	var tween := create_tween()
	tween.tween_property(_damage_flash, "color:a", 0.0, 0.5)

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and toast_label:
			toast_label.visible = false

func show_toast(msg: String) -> void:
	if toast_label == null:
		return
	toast_label.text = msg
	toast_label.visible = true
	_toast_timer = 2.0

func _build_quick_bar() -> void:
	for c in quick_bar.get_children():
		c.queue_free()
	_quick_widgets.clear()
	for i in 8:
		var root: Control = Control.new()
		root.custom_minimum_size = QUICK_SLOT_SIZE

		var bg: TextureRect = TextureRect.new()
		bg.texture = SLOT_BG
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.anchor_right = 1.0
		bg.anchor_bottom = 1.0
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)

		var outline: Panel = Panel.new()
		outline.anchor_right = 1.0
		outline.anchor_bottom = 1.0
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(1.0, 0.85, 0.2, 1.0)
		sb.set_border_width_all(3)
		sb.shadow_color = Color(1.0, 0.85, 0.2, 0.6)
		sb.shadow_size = 6
		outline.add_theme_stylebox_override("panel", sb)
		outline.visible = false
		root.add_child(outline)

		var icon: TextureRect = TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.anchor_right = 1.0
		icon.anchor_bottom = 1.0
		icon.offset_left = 4
		icon.offset_top = 4
		icon.offset_right = -4
		icon.offset_bottom = -4
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(icon)

		var key_label: Label = Label.new()
		key_label.text = str(i + 1)
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.offset_left = 4
		key_label.offset_top = 2
		key_label.offset_right = 20
		key_label.offset_bottom = 18
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(key_label)

		var count_label: Label = Label.new()
		count_label.anchor_left = 1.0
		count_label.anchor_top = 1.0
		count_label.anchor_right = 1.0
		count_label.anchor_bottom = 1.0
		count_label.offset_left = -28
		count_label.offset_top = -20
		count_label.offset_right = -4
		count_label.offset_bottom = -2
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.add_theme_font_size_override("font_size", 12)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(count_label)

		quick_bar.add_child(root)
		_quick_widgets.append({
			"root": root,
			"icon": icon,
			"count": count_label,
			"outline": outline,
		})

func update_bar(bar: String, current: float, max: float):
	match bar:
		"health":
			health_bar.max_value = max
			health_bar.value = current
			health_bar_label.text = str(int(current)) + "/" + str(int(max))
		"mana":
			mana_bar.max_value = max
			mana_bar.value = current
			mana_bar_label.text = str(int(current)) + "/" + str(int(max))
		"stamina":
			stamina_bar.max_value = max
			stamina_bar.value = current
			stamina_bar_label.text = str(int(current)) + "/" + str(int(max))

## Refresh quick bar contents. `equipped_left` and `equipped_right` are ItemResources or null.
func update_quick_bar(inventory, equipped_left, equipped_right) -> void:
	if inventory == null:
		return
	for i in _quick_widgets.size():
		var w: Dictionary = _quick_widgets[i]
		var gi: int = inventory.get_quick_index(i)
		var slot = inventory.get_slot(gi) if gi >= 0 else null
		if slot == null or slot.is_empty():
			w.icon.texture = null
			w.count.text = ""
			w.outline.visible = false
		else:
			w.icon.texture = slot.item.icon
			w.count.text = str(slot.count) if slot.count > 1 else ""
			w.outline.visible = slot.item == equipped_left or slot.item == equipped_right
