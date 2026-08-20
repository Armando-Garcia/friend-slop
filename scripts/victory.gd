extends Control


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$CenterContainer/VBoxContainer/MenuButton.pressed.connect(_on_menu_pressed)


func _on_menu_pressed() -> void:
	NetworkManager.disconnect_session()
	get_tree().change_scene_to_file("res://scenes/game_app.tscn")
