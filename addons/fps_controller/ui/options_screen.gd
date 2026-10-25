extends Control
## Options screen for managing game settings
## Settings are applied when the Apply button is clicked

signal close_options()

# Graphics controls
@onready var screen_mode_option: OptionButton = $MarginContainer/OptionsContainer/Graphics/MarginContainer/FlowContainer/ScreenMode/OptionButton
@onready var resolution_option: OptionButton = $MarginContainer/OptionsContainer/Graphics/MarginContainer/FlowContainer/Resolution/OptionButton
@onready var vsync_check: CheckButton = $MarginContainer/OptionsContainer/Graphics/MarginContainer/FlowContainer/VSync/CheckButton
@onready var brightness_slider: HSlider = $MarginContainer/OptionsContainer/Graphics/MarginContainer/FlowContainer/Brightness/HSlider
@onready var brightness_label: Label = $MarginContainer/OptionsContainer/Graphics/MarginContainer/FlowContainer/Brightness/Value
@onready var fov_slider: HSlider = $MarginContainer/OptionsContainer/Graphics/MarginContainer/FlowContainer/FieldOfView/HSlider
@onready var fov_label: Label = $MarginContainer/OptionsContainer/Graphics/MarginContainer/FlowContainer/FieldOfView/Value

# Audio controls
@onready var master_volume_slider: HSlider = $MarginContainer/OptionsContainer/Audio/MarginContainer/FlowContainer/Master/HSlider
@onready var master_volume_label: Label = $MarginContainer/OptionsContainer/Audio/MarginContainer/FlowContainer/Master/Value
@onready var music_volume_slider: HSlider = $MarginContainer/OptionsContainer/Audio/MarginContainer/FlowContainer/Music/HSlider
@onready var music_volume_label: Label = $MarginContainer/OptionsContainer/Audio/MarginContainer/FlowContainer/Music/Value
@onready var effects_volume_slider: HSlider = $MarginContainer/OptionsContainer/Audio/MarginContainer/FlowContainer/Effects/HSlider
@onready var effects_volume_label: Label = $MarginContainer/OptionsContainer/Audio/MarginContainer/FlowContainer/Effects/Value

# Gameplay controls
@onready var difficulty_option: OptionButton = $MarginContainer/OptionsContainer/Gameplay/MarginContainer/FlowContainer/Difficulty/OptionButton
@onready var sensitivity_slider: HSlider = $MarginContainer/OptionsContainer/Gameplay/MarginContainer/FlowContainer/CameraSensitivity/HSlider
@onready var sensitivity_label: Label = $MarginContainer/OptionsContainer/Gameplay/MarginContainer/FlowContainer/CameraSensitivity/Value
@onready var invert_x_check: CheckButton = $MarginContainer/OptionsContainer/Gameplay/MarginContainer/FlowContainer/InvertX/CheckButton
@onready var invert_y_check: CheckButton = $MarginContainer/OptionsContainer/Gameplay/MarginContainer/FlowContainer/InvertY/CheckButton

# Temporary settings (not saved until Apply is clicked)
var temp_screen_mode: int = DisplayServer.WINDOW_MODE_WINDOWED
var temp_resolution: Vector2i = Vector2i(1920, 1080)
var temp_vsync_enabled: bool = true
var temp_brightness: float = 50.0
var temp_fov: float = 90.0
var temp_master_volume: float = 50.0
var temp_music_volume: float = 50.0
var temp_effects_volume: float = 50.0
var temp_difficulty: String = "Normal"
var temp_sensitivity: float = 0.003
var temp_invert_x: bool = false
var temp_invert_y: bool = false

# Language selector (built at runtime so no scene edits are needed)
var _language_option: OptionButton
var _language_locales: Array[String] = []

# Controller tab (rebind rows + settings, built at runtime into the Controller tab)
const REBIND_SCENE: PackedScene = preload("res://addons/settings_kit/rebind_container.tscn")
## Actions exposed for controller rebinding, in display order (movement uses the
## left stick and is not button-rebindable, so it is omitted).
const CONTROLLER_ACTIONS: Array[String] = [
	"interact", "jump", "dash", "sprint", "crouch",
	"right_hand", "left_hand", "reload", "inventory",
	"tilt_left", "tilt_right",
	"equip_1", "equip_2", "equip_3", "equip_4",
]
var _controller_sens_slider: HSlider
var _controller_sens_value: Label
var _controller_deadzone_slider: HSlider
var _controller_deadzone_value: Label
var _controller_invert_y_check: CheckButton

var temp_controller_sens: float = 3.0
var temp_controller_deadzone: float = 0.2
var temp_controller_invert_y: bool = false


func _ready() -> void:
	# Connect slider signals for live preview
	brightness_slider.value_changed.connect(_on_brightness_changed)
	fov_slider.value_changed.connect(_on_fov_changed)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	effects_volume_slider.value_changed.connect(_on_effects_volume_changed)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)

	# Build the language selector into the Gameplay tab
	_build_language_selector()

	# Build the controller rebind rows + settings into the Controller tab
	_build_controller_tab()

	# Grab focus when opened so the tabs/controls are controller/keyboard navigable.
	visibility_changed.connect(_on_visibility_changed)
	if visible:
		_grab_default_focus()

	# Load current settings from GameSettings
	load_settings_to_ui()


func _on_visibility_changed() -> void:
	if visible:
		_grab_default_focus()


## Focus the tab bar so left/right cycles tabs and down enters the tab content.
func _grab_default_focus() -> void:
	var tabs := get_node_or_null("MarginContainer/OptionsContainer")
	if tabs:
		tabs.call_deferred("grab_focus")


## Build a "Language" row in the Gameplay tab from the locales the Localization
## autoload has loaded. Switching is applied live (and persisted) immediately.
func _build_language_selector() -> void:
	var flow := get_node_or_null("MarginContainer/OptionsContainer/Gameplay/MarginContainer/FlowContainer")
	if flow == null or not is_instance_valid(Localization):
		return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = "Language"  # auto-translated by Godot
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)

	_language_option = OptionButton.new()
	_language_option.custom_minimum_size = Vector2(160, 0)
	# Language names should display in their own language, so disable
	# auto-translation on the dropdown items.
	_language_option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

	var locales: Array[String] = []
	for l in Localization.get_languages():
		locales.append(l)
	locales.sort()

	_language_locales = locales
	var current := Localization.get_current_language()
	for i in locales.size():
		var code: String = locales[i]
		_language_option.add_item(_locale_display_name(code))
		if code == current or current.begins_with(code):
			_language_option.selected = i

	_language_option.item_selected.connect(_on_language_selected)
	row.add_child(_language_option)
	flow.add_child(row)


func _on_language_selected(index: int) -> void:
	if index >= 0 and index < _language_locales.size():
		Localization.set_language(_language_locales[index])


func _locale_display_name(code: String) -> String:
	match code:
		"en": return "English"
		"es": return "Español"
		_: return code


## Build the Controller tab: a controller rebind row per action, followed by
## controller-specific settings (look sensitivity, invert Y, deadzone).
func _build_controller_tab() -> void:
	var flow := get_node_or_null("MarginContainer/OptionsContainer/Controller/MarginContainer/FlowContainer")
	if flow == null:
		return

	for action_name in CONTROLLER_ACTIONS:
		if not InputMap.has_action(action_name):
			continue
		var row := REBIND_SCENE.instantiate()
		row.action = action_name
		row.device_type = "controller"
		flow.add_child(row)

	# --- Controller settings ---
	var sens := _add_controller_slider(flow, "Look Sensitivity", 1.0, 8.0, 0.5)
	_controller_sens_slider = sens[0]
	_controller_sens_value = sens[1]
	_controller_sens_slider.value_changed.connect(_on_controller_sens_changed)

	_controller_invert_y_check = _add_controller_check(flow, "Invert Look Y")
	_controller_invert_y_check.toggled.connect(_on_controller_invert_y_toggled)

	var dz := _add_controller_slider(flow, "Stick Deadzone", 0.0, 0.5, 0.05)
	_controller_deadzone_slider = dz[0]
	_controller_deadzone_value = dz[1]
	_controller_deadzone_slider.value_changed.connect(_on_controller_deadzone_changed)


## Create a "Label + HSlider + value" row. Returns [slider, value_label].
func _add_controller_slider(parent: Node, label_text: String, min_v: float, max_v: float, step_v: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(200, 60)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(180, 60)
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value := Label.new()
	value.custom_minimum_size = Vector2(60, 60)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)

	parent.add_child(row)
	return [slider, value]


## Create a "Label + CheckButton" row. Returns the CheckButton.
func _add_controller_check(parent: Node, label_text: String) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(200, 60)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var check := CheckButton.new()
	check.custom_minimum_size = Vector2(40, 60)
	row.add_child(check)

	parent.add_child(row)
	return check


func _on_controller_sens_changed(value: float) -> void:
	temp_controller_sens = value
	if _controller_sens_value:
		_controller_sens_value.text = "%.1f" % value


func _on_controller_deadzone_changed(value: float) -> void:
	temp_controller_deadzone = value
	if _controller_deadzone_value:
		_controller_deadzone_value.text = "%d%%" % round(value * 100.0)


func _on_controller_invert_y_toggled(pressed: bool) -> void:
	temp_controller_invert_y = pressed


## Load settings from GameSettings singleton and update UI
func load_settings_to_ui() -> void:
	# Graphics
	temp_screen_mode = GameSettings.screen_mode
	temp_resolution = GameSettings.resolution
	temp_vsync_enabled = GameSettings.vsync_enabled
	temp_brightness = GameSettings.brightness
	temp_fov = GameSettings.field_of_view

	# Set screen mode dropdown
	match temp_screen_mode:
		DisplayServer.WINDOW_MODE_WINDOWED:
			screen_mode_option.selected = 0
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			screen_mode_option.selected = 1
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			screen_mode_option.selected = 2

	# Set resolution dropdown
	var resolution_text = "%dx%d" % [temp_resolution.x, temp_resolution.y]
	for i in resolution_option.item_count:
		if resolution_option.get_item_text(i) == resolution_text:
			resolution_option.selected = i
			break

	# Set VSync checkbox
	vsync_check.button_pressed = temp_vsync_enabled

	# Set brightness slider
	brightness_slider.value = temp_brightness
	brightness_label.text = "%d%%" % temp_brightness

	# Set FOV slider
	fov_slider.value = temp_fov
	fov_label.text = "%d" % temp_fov

	# Audio
	temp_master_volume = GameSettings.master_volume
	temp_music_volume = GameSettings.music_volume
	temp_effects_volume = GameSettings.effects_volume

	master_volume_slider.value = temp_master_volume
	master_volume_label.text = "%d%%" % temp_master_volume
	music_volume_slider.value = temp_music_volume
	music_volume_label.text = "%d%%" % temp_music_volume
	effects_volume_slider.value = temp_effects_volume
	effects_volume_label.text = "%d%%" % temp_effects_volume

	# Gameplay
	temp_difficulty = GameSettings.difficulty
	temp_sensitivity = GameSettings.mouse_sensitivity
	temp_invert_x = GameSettings.invert_camera_x
	temp_invert_y = GameSettings.invert_camera_y

	# Set difficulty dropdown
	for i in difficulty_option.item_count:
		if difficulty_option.get_item_text(i) == temp_difficulty:
			difficulty_option.selected = i
			break

	# Convert sensitivity from 0.001-0.005 range to 0-100 slider range
	var sensitivity_percent = (temp_sensitivity - 0.001) / (0.005 - 0.001) * 100.0
	sensitivity_slider.value = sensitivity_percent
	sensitivity_label.text = "%d%%" % sensitivity_percent

	invert_x_check.button_pressed = temp_invert_x
	invert_y_check.button_pressed = temp_invert_y

	# Controller
	temp_controller_sens = GameSettings.controller_look_sensitivity
	temp_controller_deadzone = GameSettings.controller_deadzone
	temp_controller_invert_y = GameSettings.invert_controller_y
	if _controller_sens_slider:
		_controller_sens_slider.value = temp_controller_sens
		_controller_sens_value.text = "%.1f" % temp_controller_sens
		_controller_deadzone_slider.value = temp_controller_deadzone
		_controller_deadzone_value.text = "%d%%" % round(temp_controller_deadzone * 100.0)
		_controller_invert_y_check.button_pressed = temp_controller_invert_y


## Graphics: Screen mode changed
func _on_screen_mode_item_selected(index: int) -> void:
	match index:
		0:  # Windowed
			temp_screen_mode = DisplayServer.WINDOW_MODE_WINDOWED
		1:  # Fullscreen
			temp_screen_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		2:  # Borderless
			temp_screen_mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Graphics: Resolution changed
func _on_resolution_item_selected(index: int) -> void:
	var resolution_text = resolution_option.get_item_text(index)
	var parts = resolution_text.split("x")
	if parts.size() == 2:
		temp_resolution = Vector2i(int(parts[0]), int(parts[1]))


## Graphics: Brightness changed
func _on_brightness_changed(value: float) -> void:
	temp_brightness = value
	brightness_label.text = "%d%%" % value


## Graphics: FOV changed
func _on_fov_changed(value: float) -> void:
	temp_fov = value
	fov_label.text = "%d" % value


## Audio: Master volume changed (live preview)
func _on_master_volume_changed(value: float) -> void:
	temp_master_volume = value
	master_volume_label.text = "%d%%" % value
	# Live preview
	GameSettings.set_bus_volume("Master", value)


## Audio: Music volume changed (live preview)
func _on_music_volume_changed(value: float) -> void:
	temp_music_volume = value
	music_volume_label.text = "%d%%" % value
	# Live preview
	GameSettings.set_bus_volume("Music", value)


## Audio: Effects volume changed (live preview)
func _on_effects_volume_changed(value: float) -> void:
	temp_effects_volume = value
	effects_volume_label.text = "%d%%" % value
	# Live preview
	GameSettings.set_bus_volume("Effects", value)


## Gameplay: Sensitivity changed
func _on_sensitivity_changed(value: float) -> void:
	sensitivity_label.text = "%d%%" % value
	# Convert 0-100 slider range to 0.001-0.005 sensitivity range
	temp_sensitivity = 0.001 + (value / 100.0) * (0.005 - 0.001)


## Apply button: Save all settings
func _on_apply_button_pressed() -> void:
	# Update GameSettings with all temp values
	GameSettings.screen_mode = temp_screen_mode
	GameSettings.resolution = temp_resolution
	GameSettings.vsync_enabled = vsync_check.button_pressed
	GameSettings.brightness = temp_brightness
	GameSettings.field_of_view = temp_fov
	GameSettings.master_volume = temp_master_volume
	GameSettings.music_volume = temp_music_volume
	GameSettings.effects_volume = temp_effects_volume
	GameSettings.difficulty = temp_difficulty
	GameSettings.mouse_sensitivity = temp_sensitivity
	GameSettings.invert_camera_x = invert_x_check.button_pressed
	GameSettings.invert_camera_y = invert_y_check.button_pressed

	# Controller
	GameSettings.controller_look_sensitivity = temp_controller_sens
	GameSettings.controller_deadzone = temp_controller_deadzone
	GameSettings.invert_controller_y = temp_controller_invert_y

	# Get difficulty from dropdown
	GameSettings.difficulty = difficulty_option.get_item_text(difficulty_option.selected)

	# Apply graphics settings (window mode and resolution)
	GameSettings.apply_graphics_settings()

	# Apply VSync
	GameSettings.apply_vsync()

	# Apply brightness
	GameSettings.apply_brightness()

	# Apply audio settings
	GameSettings.apply_audio_settings()

	# Update player config if player exists
	update_player_config()

	# Save settings to disk
	GameSettings.save_settings()

	# Persist any custom key/controller rebinds done in the Controls/Controller tabs
	GameSettings.save_keybinds()

	print("Settings applied and saved")


## Update player config with new settings
func update_player_config() -> void:
	# Find player in scene tree
	var player = get_tree().get_first_node_in_group("player")
	if player and player.config:
		player.config.mouse_sensitivity = GameSettings.mouse_sensitivity
		player.config.invert_camera_x = GameSettings.invert_camera_x
		player.config.invert_camera_y = GameSettings.invert_camera_y
		player.config.controller_look_sensitivity = GameSettings.controller_look_sensitivity
		player.config.controller_deadzone = GameSettings.controller_deadzone
		player.config.invert_controller_y = GameSettings.invert_controller_y
		player.config.difficulty = GameSettings.difficulty

		# Apply FOV to camera if it exists
		if player.camera_3d:
			GameSettings.apply_fov_to_camera(player.camera_3d)

		print("Player config updated")


## Close button: Close options menu
func _on_close_options_pressed() -> void:
	close_options.emit()
