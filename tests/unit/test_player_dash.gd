extends RefCounted

const PlayerDashScript := preload("res://scripts/characters/player_dash.gd")
const PlayableCharacterScript := preload("res://scripts/characters/playable_character.gd")


func run() -> int:
	var failures := 0
	failures += _test_default_dash_travel()
	failures += _test_config_speed_overrides_defaults()
	failures += _test_config_from_player_exports()
	return failures


func _test_default_dash_travel() -> int:
	var config := {
		"distance": PlayerDashScript.DEFAULT_DISTANCE,
		"duration": PlayerDashScript.DEFAULT_DURATION,
		"speed": PlayerDashScript.DEFAULT_SPEED,
	}
	var speed := PlayerDashScript.dash_speed(config)
	var distance := speed * PlayerDashScript.dash_duration(config)
	if not is_equal_approx(distance, PlayerDashScript.DEFAULT_DISTANCE):
		push_error("Expected default dash to travel 3 m, got %s m" % distance)
		return 1
	return 0


func _test_config_speed_overrides_defaults() -> int:
	var config := {"speed": 12.0, "duration": 0.25}
	if not is_equal_approx(PlayerDashScript.dash_speed(config), 12.0):
		push_error("Expected dash_speed to read config speed")
		return 1
	return 0


func _test_config_from_player_exports() -> int:
	var player := PlayableCharacterScript.new()
	player.dash_distance = 4.0
	player.dash_duration = 0.2
	player.dash_cooldown_sec = 2.5
	player.dash_speed = 15.0
	var config := PlayerDashScript.config_from(player)
	player.free()
	if not is_equal_approx(float(config["distance"]), 4.0):
		push_error("Expected config_from to read dash_distance export")
		return 1
	if not is_equal_approx(float(config["speed"]), 15.0):
		push_error("Expected config_from to read dash_speed export")
		return 1
	return 0
