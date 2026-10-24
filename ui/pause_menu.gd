extends Control

# Node references
@onready var main_container: Control = $MainContainer
@onready var options_screen: Control = $OptionsScreen
@onready var _resume_button: Button = $MainContainer/CenterContainer/VBoxContainer/ButtonsContainer/ResumeButton

# Reference to the player (will be set by player script)
var player: CharacterBody3D

func _ready():
	# Initially hide the pause menu
	visible = false
	# Set process mode to always so it works when paused
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event):
	# Close the pause menu on the pause button (Esc / Options) or B (ui_cancel).
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		_on_resume()
		get_viewport().set_input_as_handled()

func show_main_menu():
	if options_screen:
		options_screen.visible = false
	main_container.visible = true
	# Focus the first button so the pause menu is controller/keyboard navigable.
	if _resume_button:
		_resume_button.call_deferred("grab_focus")

func show_options():
	main_container.visible = false
	if options_screen:
		options_screen.visible = true

func _on_resume():
	if player:
		player.resume_game()

func _on_open_options():
	show_options()

func _on_close_options():
	show_main_menu()

func _on_exit_to_main_menu():
	# SceneManager unpauses and fades during the transition.
	SceneManager.change_scene("main_menu")

func _on_exit_to_desktop():
	get_tree().quit()