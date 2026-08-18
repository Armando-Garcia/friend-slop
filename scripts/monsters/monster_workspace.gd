@tool
extends Node3D

## Monster look-dev: type scenes side-by-side. Dropdown picks the active
## target for pose / abilities / fireball. Works in the editor and Play (F6).

const MONSTER_PICK_WRETCH := 0
const MONSTER_PICK_ASH_WRETCH := 1
const MONSTER_PICK_EMBER_WRETCH := 2
const MONSTER_PICK_CHARGER := 3

const WretchScene := preload("res://scenes/monsters/wretch.tscn")
const AshWretchScene := preload("res://scenes/monsters/ash_wretch.tscn")
const EmberWretchScene := preload("res://scenes/monsters/ember_wretch.tscn")
const ChargerScene := preload("res://scenes/monsters/charger.tscn")
const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")
const FireballSpell := preload("res://resources/spells/fireball.tres")
const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")

## Horizontal spacing between type previews.
const GALLERY_SPACING := 3.5

@export_group("Monster")
## Which gallery monster tools (pose / abilities / fireball) target.
@export_enum("Wretch", "Ash Wretch", "Ember Wretch", "Charger")
var monster_type: int = MONSTER_PICK_WRETCH:
	set(value):
		monster_type = value
		if is_inside_tree():
			_focus_selected_monster()

@export_tool_button("Reload All Monsters", "Callable")
var reload_monster_action := reload_selected_monster
@export_tool_button("Ensure Gallery", "Callable")
var ensure_monster_action := ensure_one_monster
@export_tool_button("Clear Monster + Corpses", "Callable")
var clear_monsters_action := clear_monsters_and_corpses
@export_tool_button("Set Patrol Pose", "Callable")
var set_patrol_pose_action := set_patrol_pose
@export_tool_button("Set Chase Pose", "Callable")
var set_chase_pose_action := set_chase_pose
## Look-dev HP so one default fireball (20) can kill for death/ragdoll preview.
@export_range(1.0, 200.0, 1.0) var preview_max_health: float = 20.0
@export_range(1.0, 60.0, 0.5) var preview_death_linger_sec: float = 10.0
@export_range(0.25, 10.0, 0.25) var preview_death_fade_sec: float = 2.0
@export var show_combat_ranges: bool = true

@export_group("Abilities")
## Filled from the active type scene (Right / Left hand).
@export var ability_1_name: String = "—"
@export var ability_2_name: String = "—"
@export_tool_button("Preview Ability 1", "Callable")
var preview_ability_1_action := preview_ability_1
@export_tool_button("Preview Ability 2", "Callable")
var preview_ability_2_action := preview_ability_2

@export_group("Fireball")
@export_tool_button("Cast Fireball", "Callable")
var cast_fireball_action := cast_fireball_at_monster
@export_range(0.0, 1.5, 0.05) var tip_forward_nudge: float = 0.08

var _spawn_root: Node3D


func get_monster_scene(pick: int = -1) -> PackedScene:
	var which := monster_type if pick < 0 else pick
	match which:
		MONSTER_PICK_ASH_WRETCH:
			return AshWretchScene
		MONSTER_PICK_EMBER_WRETCH:
			return EmberWretchScene
		MONSTER_PICK_CHARGER:
			return ChargerScene
		_:
			return WretchScene


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cache_spawn_root()
	_ensure_bucket("FireballPreview")
	_ensure_bucket("AbilityPreview")
	## Always respawn so we never keep a stale baked override from an old scene save.
	_respawn_monster_from_scene()
	_aim_wand_at_monster()
	set_process(true)
	set_process_unhandled_input(true)


func _process(_delta: float) -> void:
	_aim_wand_at_monster()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() and not _is_playing_lookdev():
		return
	if event.is_action_pressed("ui_accept") or (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and (event as InputEventKey).keycode == KEY_SPACE
	):
		cast_fireball_at_monster()
		get_viewport().set_input_as_handled()


func reload_selected_monster() -> void:
	_respawn_monster_from_scene()


func ensure_one_monster() -> void:
	_cache_spawn_root()
	if _spawn_root == null:
		return
	if _gallery_is_complete():
		_focus_selected_monster()
		return
	_respawn_monster_from_scene()


func clear_monsters_and_corpses() -> void:
	_cache_spawn_root()
	_clear_spawn_root_immediate()
	_clear_bucket("FireballPreview")
	_clear_bucket("AbilityPreview")
	ability_1_name = "—"
	ability_2_name = "—"


func set_patrol_pose() -> void:
	ensure_one_monster()
	var monster := _living_monster()
	if monster != null and monster.has_method("set_lookdev_pose"):
		monster.call("set_lookdev_pose", MonsterAIScript.LookdevPose.PATROL, true)


func set_chase_pose() -> void:
	ensure_one_monster()
	var monster := _living_monster()
	if monster != null and monster.has_method("set_lookdev_pose"):
		monster.call("set_lookdev_pose", MonsterAIScript.LookdevPose.CHASE, true)


func preview_ability_1() -> void:
	_preview_ability_at(0)


func preview_ability_2() -> void:
	_preview_ability_at(1)


func cast_fireball_at_monster() -> void:
	if not is_inside_tree():
		return
	ensure_one_monster()
	var monster := _living_monster()
	if monster == null:
		push_warning("MonsterWorkspace: no living monster to shoot")
		return
	_apply_preview_stats(monster)

	var origin := _wand_cast_origin()
	var aim_at: Vector3 = (monster as Node3D).global_position + Vector3(0.0, 0.4, 0.0)
	var direction := aim_at - origin
	if direction.length_squared() < 0.0001:
		direction = Vector3(0.0, 0.0, -1.0)
	else:
		direction = direction.normalized()
	origin += direction * tip_forward_nudge

	var wand := _wand()
	## PlayerWand is not @tool — skip cast FX on editor placeholder instances.
	if (
		wand != null
		and not Engine.is_editor_hint()
		and wand.has_method("play_cast_success")
	):
		wand.call("play_cast_success", FireballSpell, true)

	var bucket := _ensure_bucket("FireballPreview")
	## One shot at a time for clear look-dev.
	_clear_bucket_children(bucket)
	var lookdev := Engine.is_editor_hint()
	var projectile: Node = FireballProjectileScript.spawn(
		bucket, origin, direction, null, lookdev
	)
	if projectile != null:
		projectile.process_mode = Node.PROCESS_MODE_ALWAYS
		if lookdev and get_tree() != null:
			var root := get_tree().edited_scene_root
			if root != null:
				projectile.owner = root


func _respawn_monster_from_scene() -> void:
	_cache_spawn_root()
	if _spawn_root == null:
		return
	_clear_spawn_root_immediate()
	_clear_bucket("AbilityPreview")
	for pick in [
		MONSTER_PICK_WRETCH, MONSTER_PICK_ASH_WRETCH,
		MONSTER_PICK_EMBER_WRETCH, MONSTER_PICK_CHARGER
	]:
		_spawn_gallery_monster(pick)
	_focus_selected_monster()


func _spawn_gallery_monster(pick: int) -> Node:
	var packed: PackedScene = get_monster_scene(pick)
	if packed == null:
		push_warning("MonsterWorkspace: no scene for pick %s" % pick)
		return null
	## Fresh pack so inspector edits to type scenes show up immediately.
	if packed.resource_path != "":
		packed = load(packed.resource_path) as PackedScene
	var monster: Node = packed.instantiate()
	monster.process_mode = Node.PROCESS_MODE_ALWAYS
	_spawn_root.add_child(monster)
	if Engine.is_editor_hint():
		var edited := get_tree().edited_scene_root if get_tree() != null else null
		if edited != null:
			monster.owner = edited
	if monster is Node3D:
		(monster as Node3D).position = _gallery_offset(pick)
	_enable_lookdev(monster)
	if (
		monster.has_method("apply_summon_appearance")
		and "body_tint" in monster
		and "eye_glow_color" in monster
	):
		monster.call(
			"apply_summon_appearance",
			monster.get("body_tint"),
			monster.get("eye_glow_color")
		)
	return monster


func _gallery_offset(pick: int) -> Vector3:
	return Vector3((float(pick) - 1.5) * GALLERY_SPACING, 0.0, 0.0)


func _focus_selected_monster() -> void:
	var monster := _living_monster()
	if monster == null:
		ability_1_name = "—"
		ability_2_name = "—"
		return
	_apply_preview_stats(monster)
	_enable_lookdev(monster)
	_refresh_ability_labels(monster)


func _gallery_is_complete() -> bool:
	for pick in [
		MONSTER_PICK_WRETCH, MONSTER_PICK_ASH_WRETCH,
		MONSTER_PICK_EMBER_WRETCH, MONSTER_PICK_CHARGER
	]:
		if _find_gallery_monster(pick) == null:
			return false
	return true


func _enable_lookdev(node: Node) -> void:
	if node == null:
		return
	if "lookdev_override" in node:
		node.set("lookdev_override", true)
	if "show_combat_ranges" in node:
		node.set("show_combat_ranges", show_combat_ranges)
	if node.has_method("set_lookdev_pose"):
		var pose = node.get("lookdev_pose")
		if pose == null:
			pose = MonsterAIScript.LookdevPose.PATROL
		node.call("set_lookdev_pose", pose, true)


func _refresh_ability_labels(monster: Node) -> void:
	var abilities := _ordered_preview_abilities(monster)
	ability_1_name = _format_ability_label(abilities, 0)
	ability_2_name = _format_ability_label(abilities, 1)


func _format_ability_label(abilities: Array, index: int) -> String:
	if index < 0 or index >= abilities.size():
		return "—(none)—"
	var ability: Node = abilities[index] as Node
	var name_s: String = ability.name
	if "display_name" in ability:
		var displayed := str(ability.get("display_name"))
		if not displayed.is_empty():
			name_s = displayed
	var hand: String = ""
	if "hand_side" in ability:
		hand = "Right" if int(ability.get("hand_side")) == 0 else "Left"
	elif ability.name.to_lower().contains("left"):
		hand = "Left"
	elif ability.name.to_lower().contains("right"):
		hand = "Right"
	if hand.is_empty():
		return name_s
	return "%s (%s)" % [name_s, hand]


func _ordered_preview_abilities(monster: Node) -> Array[Node]:
	var out: Array[Node] = []
	if monster == null:
		return out
	if monster.has_method("get_ability_placeholders"):
		var raw: Array = monster.call("get_ability_placeholders")
		var right: Array[Node] = []
		var left: Array[Node] = []
		var other: Array[Node] = []
		for item in raw:
			if not (item is Node):
				continue
			var ability: Node = item
			if "hand_side" in ability:
				if int(ability.get("hand_side")) == 0:
					right.append(ability)
				else:
					left.append(ability)
			else:
				other.append(ability)
		out.append_array(right)
		out.append_array(left)
		out.append_array(other)
	return out


func _preview_ability_at(index: int) -> void:
	ensure_one_monster()
	var monster := _living_monster()
	if monster == null:
		push_warning("MonsterWorkspace: no monster for ability preview")
		return
	_refresh_ability_labels(monster)
	var abilities := _ordered_preview_abilities(monster)
	if index < 0 or index >= abilities.size():
		push_warning("MonsterWorkspace: ability index %d missing" % index)
		return
	var ability: Node = abilities[index]
	_clear_bucket("AbilityPreview")
	## Give summon / projectile casts a stable lookdev parent when they ask for match root.
	if ability.has_method("set_meta"):
		ability.set_meta("lookdev_preview_parent", _ensure_bucket("AbilityPreview"))
	if ability.has_method("preview_cast"):
		ability.call("preview_cast")
	else:
		push_warning("MonsterWorkspace: %s has no preview_cast" % ability.name)


func _monster_matches_selected(node: Node) -> bool:
	return _monster_matches_pick(node, monster_type)


func _monster_matches_pick(node: Node, pick: int) -> bool:
	if node == null:
		return false
	var packed := get_monster_scene(pick)
	if packed == null:
		return false
	var path := str(node.get("scene_file_path"))
	if path.is_empty() or path != packed.resource_path:
		return false
	## Reject stale workspace overrides that swapped the type script.
	var script: Script = node.get_script()
	var script_path := "" if script == null else str(script.resource_path)
	var ok := false
	match pick:
		MONSTER_PICK_WRETCH:
			ok = (
				script_path.ends_with("wretch.gd")
				and not script_path.ends_with("ash_wretch.gd")
			)
		MONSTER_PICK_ASH_WRETCH:
			## Ash uses the base Monster script on its type scene (like Ember).
			ok = (
				script_path.ends_with("monster.gd")
				or script_path.ends_with("ash_wretch.gd")
			)
		MONSTER_PICK_EMBER_WRETCH:
			## Ember still uses the base Monster script on its type scene.
			ok = (
				script_path.ends_with("monster.gd")
				or script_path.ends_with("ember_wretch.gd")
			)
		MONSTER_PICK_CHARGER:
			ok = script_path.ends_with("charger.gd")
		_:
			ok = true
	return ok


func _find_gallery_monster(pick: int) -> Node:
	_cache_spawn_root()
	if _spawn_root == null:
		return null
	for child in _spawn_root.get_children():
		if not (child is Node3D):
			continue
		if not child.has_method("die"):
			continue
		var alive = child.get("is_alive")
		if alive != null and not bool(alive):
			continue
		if _monster_matches_pick(child, pick):
			return child
	return null


func _living_monster() -> Node:
	return _find_gallery_monster(monster_type)


func _apply_preview_stats(node: Node) -> void:
	if node == null:
		return
	if "max_health" in node:
		node.set("max_health", preview_max_health)
	if "current_health" in node:
		node.set("current_health", preview_max_health)
	if "death_linger_sec" in node:
		node.set("death_linger_sec", preview_death_linger_sec)
	if "death_fade_sec" in node:
		node.set("death_fade_sec", preview_death_fade_sec)


func _wand() -> Node3D:
	return get_node_or_null("Wand") as Node3D


func _wand_cast_origin() -> Vector3:
	var wand := _wand()
	if wand == null:
		return global_position + Vector3(-1.5, 1.0, 2.5)
	var tip := wand.get_node_or_null("Model/CastOrigin") as Node3D
	if tip == null:
		tip = wand.get_node_or_null("CastOrigin") as Node3D
	if tip != null:
		return tip.global_position
	return wand.global_position


func _aim_wand_at_monster() -> void:
	var wand := _wand()
	var monster := _living_monster()
	if wand == null or monster == null:
		return
	var tip := wand.get_node_or_null("Model/CastOrigin") as Node3D
	var from: Vector3 = tip.global_position if tip != null else wand.global_position
	var to: Vector3 = (monster as Node3D).global_position + Vector3(0.0, 0.4, 0.0)
	var flat := Vector3(to.x - from.x, to.y - from.y, to.z - from.z)
	if flat.length_squared() < 0.0001:
		return
	## Wand shaft points along local -Z (see player_wand Model).
	wand.look_at(to, Vector3.UP)


func _is_playing_lookdev() -> bool:
	## Editor Play Scene / runtime — not idle edited scene.
	return not Engine.is_editor_hint() or get_tree() != null and get_tree().edited_scene_root == null


func _ensure_bucket(bucket_name: String) -> Node3D:
	var bucket := get_node_or_null(bucket_name) as Node3D
	if bucket != null:
		bucket.process_mode = Node.PROCESS_MODE_ALWAYS
		return bucket
	bucket = Node3D.new()
	bucket.name = bucket_name
	bucket.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bucket)
	if Engine.is_editor_hint() and get_tree() != null:
		var root := get_tree().edited_scene_root
		if root != null:
			bucket.owner = root
	return bucket


func _clear_bucket(bucket_name: String) -> void:
	var bucket := get_node_or_null(bucket_name) as Node3D
	if bucket == null:
		return
	_clear_bucket_children(bucket)


func _clear_bucket_children(bucket: Node) -> void:
	var kids := bucket.get_children()
	for child in kids:
		bucket.remove_child(child)
		child.free()


func _clear_spawn_root_immediate() -> void:
	if _spawn_root == null:
		return
	var kids := _spawn_root.get_children()
	for child in kids:
		_spawn_root.remove_child(child)
		child.free()


func _cache_spawn_root() -> void:
	_spawn_root = get_node_or_null("SpawnRoot") as Node3D
