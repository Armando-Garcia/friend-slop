@tool
extends Node3D

## Single-type monster lookdev studio. Dropdown spawns one monster at origin.
## Dummy + ability buttons work in the inspector; F6 Play Scene enables live aggro.

const MONSTER_PICK_WRETCH := 0
const MONSTER_PICK_ASH_WRETCH := 1
const MONSTER_PICK_EMBER_WRETCH := 2
const ABILITY_SLOT_COUNT := 6
const DUMMY_DISTANCE := 6.0
const NONE_LABEL := "—(none)—"

const WretchScene := preload("res://scenes/monsters/wretch.tscn")
const AshWretchScene := preload("res://scenes/monsters/ash_wretch.tscn")
const EmberWretchScene := preload("res://scenes/monsters/ember_wretch.tscn")
const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")
const FireballSpell := preload("res://resources/spells/fireball.tres")
const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const WorkspacePlayerDummyScript := preload(
	"res://scripts/monsters/workspace_player_dummy.gd"
)

@export_group("Monster")
## Which type scene SpawnRoot instantiates at the origin.
@export_enum("Rat Queen", "Ice Caster", "Ember Caster")
var monster_type: int = MONSTER_PICK_WRETCH:
	set(value):
		var changed := monster_type != value
		monster_type = value
		if not is_inside_tree():
			return
		if changed:
			_respawn_monster_from_scene()
		else:
			_focus_selected_monster()

@export_tool_button("Reload Monster", "Callable")
var reload_monster_action := reload_selected_monster
@export_tool_button("Ensure Monster", "Callable")
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

@export_group("Dummy")
@export_tool_button("Spawn Player Dummy", "Callable")
var spawn_dummy_action := spawn_player_dummy
@export_tool_button("Clear Dummy", "Callable")
var clear_dummy_action := clear_player_dummy

@export_group("Abilities")
@export var ability_1_name: String = NONE_LABEL
@export var ability_2_name: String = NONE_LABEL
@export var ability_3_name: String = NONE_LABEL
@export var ability_4_name: String = NONE_LABEL
@export var ability_5_name: String = NONE_LABEL
@export var ability_6_name: String = NONE_LABEL
@export_tool_button("Preview Ability 1", "Callable")
var preview_ability_1_action := preview_ability_1
@export_tool_button("Preview Ability 2", "Callable")
var preview_ability_2_action := preview_ability_2
@export_tool_button("Preview Ability 3", "Callable")
var preview_ability_3_action := preview_ability_3
@export_tool_button("Preview Ability 4", "Callable")
var preview_ability_4_action := preview_ability_4
@export_tool_button("Preview Ability 5", "Callable")
var preview_ability_5_action := preview_ability_5
@export_tool_button("Preview Ability 6", "Callable")
var preview_ability_6_action := preview_ability_6
@export_tool_button("Preview Combo", "Callable")
var preview_combo_action := preview_combo

@export_group("Fireball")
@export_tool_button("Cast Fireball", "Callable")
var cast_fireball_action := cast_fireball_at_monster
@export_range(0.0, 1.5, 0.05) var tip_forward_nudge: float = 0.08

var _spawn_root: Node3D
var _dummy_root: Node3D


func get_monster_scene(pick: int = -1) -> PackedScene:
	var which := monster_type if pick < 0 else pick
	match which:
		MONSTER_PICK_ASH_WRETCH:
			return AshWretchScene
		MONSTER_PICK_EMBER_WRETCH:
			return EmberWretchScene
		_:
			return WretchScene


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cache_spawn_root()
	_cache_dummy_root()
	_ensure_bucket("FireballPreview")
	_ensure_bucket("AbilityPreview")
	_respawn_monster_from_scene()
	_aim_wand_at_target()
	set_process(true)
	set_process_unhandled_input(true)


func _process(_delta: float) -> void:
	_aim_wand_at_target()


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
	if _living_monster() != null:
		_focus_selected_monster()
		return
	_respawn_monster_from_scene()


func clear_monsters_and_corpses() -> void:
	_cache_spawn_root()
	_clear_spawn_root_immediate()
	_clear_bucket("FireballPreview")
	_clear_bucket("AbilityPreview")
	_reset_ability_labels()
	_notify_hud()


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


func spawn_player_dummy() -> void:
	ensure_one_monster()
	_cache_dummy_root()
	if _dummy_root == null:
		return
	_free_dummy_children()
	var dummy: CharacterBody3D = WorkspacePlayerDummyScript.new()
	dummy.name = "PlayerDummy"
	dummy.process_mode = Node.PROCESS_MODE_ALWAYS
	_dummy_root.add_child(dummy)
	var origin := Vector3.ZERO
	var forward := Vector3(0.0, 0.0, -1.0)
	var monster := _living_monster()
	if monster is Node3D:
		var body := monster as Node3D
		origin = body.global_position
		forward = -body.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = Vector3(0.0, 0.0, -1.0)
		else:
			forward = forward.normalized()
	dummy.global_position = origin + forward * DUMMY_DISTANCE
	_bind_monster_to_dummy(monster)
	if dummy.has_method("pin_home"):
		dummy.call("pin_home")
	_notify_hud()


func clear_player_dummy() -> void:
	_free_dummy_children()
	var monster := _living_monster()
	if monster != null and monster.has_method("set_lookdev_aggro"):
		monster.call("set_lookdev_aggro", null)
	_enable_lookdev(monster)
	_notify_hud()


func preview_ability_1() -> void:
	_preview_ability_at(0)


func preview_ability_2() -> void:
	_preview_ability_at(1)


func preview_ability_3() -> void:
	_preview_ability_at(2)


func preview_ability_4() -> void:
	_preview_ability_at(3)


func preview_ability_5() -> void:
	_preview_ability_at(4)


func preview_ability_6() -> void:
	_preview_ability_at(5)


func preview_ability_slot(index: int) -> void:
	_preview_ability_at(index)


func preview_combo() -> void:
	ensure_one_monster()
	var monster := _living_monster()
	if monster == null:
		push_warning("MonsterWorkspace: no monster for combo")
		return
	if _living_dummy() == null:
		spawn_player_dummy()
	var dummy := _living_dummy()
	if dummy == null:
		push_warning("MonsterWorkspace: combo needs a player dummy")
		return
	var caster := monster.get_node_or_null("CasterCombat")
	if caster == null or not caster.has_method("try_trigger_combo"):
		push_warning("MonsterWorkspace: no CasterCombat on this type")
		return
	if "_combo_lockout_left" in caster:
		caster.set("_combo_lockout_left", 0.0)
	caster.call("try_trigger_combo", dummy, 1.0, false)


func has_preview_combo() -> bool:
	var monster := _living_monster()
	if monster == null:
		return false
	return monster.get_node_or_null("CasterCombat") != null


func ability_preview_labels() -> PackedStringArray:
	var out := PackedStringArray()
	var monster := _living_monster()
	var abilities := _ordered_preview_abilities(monster)
	for i in range(ABILITY_SLOT_COUNT):
		out.append(_format_ability_label(abilities, i))
	return out


func cast_fireball_at_monster() -> void:
	if not is_inside_tree():
		return
	ensure_one_monster()
	var target := _fireball_aim_node()
	if target == null:
		push_warning("MonsterWorkspace: no living monster to shoot")
		return
	var monster := _living_monster()
	_apply_preview_stats(monster)

	var origin := _wand_cast_origin()
	var aim_at: Vector3 = target.global_position + Vector3(0.0, 0.4, 0.0)
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


func _respawn_monster_from_scene() -> void:
	_cache_spawn_root()
	if _spawn_root == null:
		return
	_clear_spawn_root_immediate()
	_clear_bucket("AbilityPreview")
	_spawn_selected_monster()
	_focus_selected_monster()
	_notify_hud()


func _spawn_selected_monster() -> Node:
	var packed: PackedScene = get_monster_scene()
	if packed == null:
		push_warning("MonsterWorkspace: no scene for pick %s" % monster_type)
		return null
	## Fresh pack so inspector edits to type scenes show up immediately.
	if packed.resource_path != "":
		packed = load(packed.resource_path) as PackedScene
	var monster: Node = packed.instantiate()
	monster.process_mode = Node.PROCESS_MODE_ALWAYS
	_spawn_root.add_child(monster)
	if monster is Node3D:
		(monster as Node3D).position = Vector3.ZERO
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


func _focus_selected_monster() -> void:
	var monster := _living_monster()
	if monster == null:
		_reset_ability_labels()
		return
	_apply_preview_stats(monster)
	_enable_lookdev(monster)
	_refresh_ability_labels(monster)
	_bind_monster_to_dummy(monster)


func _enable_lookdev(node: Node) -> void:
	if node == null:
		return
	if "show_combat_ranges" in node:
		node.set("show_combat_ranges", show_combat_ranges)
	if _living_dummy() != null:
		_bind_monster_to_dummy(node)
		return
	if "lookdev_override" in node:
		node.set("lookdev_override", true)
	if node.has_method("set_lookdev_pose"):
		var pose = node.get("lookdev_pose")
		if pose == null:
			pose = MonsterAIScript.LookdevPose.PATROL
		node.call("set_lookdev_pose", pose, true)


func _bind_monster_to_dummy(monster: Node) -> void:
	var dummy := _living_dummy()
	if dummy == null or monster == null:
		return
	if monster is Node3D:
		var body := monster as Node3D
		if body.global_position.distance_squared_to(dummy.global_position) > 0.0001:
			body.look_at(dummy.global_position, Vector3.UP)
			dummy.look_at(body.global_position, Vector3.UP)
	if monster.has_method("set_lookdev_aggro"):
		monster.call("set_lookdev_aggro", dummy)
	elif "lookdev_override" in monster:
		monster.set("lookdev_override", false)


func _refresh_ability_labels(monster: Node) -> void:
	var abilities := _ordered_preview_abilities(monster)
	ability_1_name = _format_ability_label(abilities, 0)
	ability_2_name = _format_ability_label(abilities, 1)
	ability_3_name = _format_ability_label(abilities, 2)
	ability_4_name = _format_ability_label(abilities, 3)
	ability_5_name = _format_ability_label(abilities, 4)
	ability_6_name = _format_ability_label(abilities, 5)


func _reset_ability_labels() -> void:
	ability_1_name = NONE_LABEL
	ability_2_name = NONE_LABEL
	ability_3_name = NONE_LABEL
	ability_4_name = NONE_LABEL
	ability_5_name = NONE_LABEL
	ability_6_name = NONE_LABEL


func _format_ability_label(abilities: Array, index: int) -> String:
	if index < 0 or index >= abilities.size():
		return NONE_LABEL
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
		_:
			ok = true
	return ok


func _find_spawned_monster(pick: int) -> Node:
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
	return _find_spawned_monster(monster_type)


func _living_dummy() -> Node3D:
	_cache_dummy_root()
	if _dummy_root == null:
		return null
	for child in _dummy_root.get_children():
		if child is Node3D and is_instance_valid(child):
			return child as Node3D
	return null


func _fireball_aim_node() -> Node3D:
	var dummy := _living_dummy()
	if dummy != null:
		return dummy
	return _living_monster() as Node3D


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


func _aim_wand_at_target() -> void:
	var wand := _wand()
	var target := _fireball_aim_node()
	if wand == null or target == null:
		return
	var from := wand.global_position
	var to: Vector3 = target.global_position + Vector3(0.0, 0.4, 0.0)
	var flat := Vector3(to.x - from.x, to.y - from.y, to.z - from.z)
	if flat.length_squared() < 0.0001:
		return
	## Wand shaft points along local -Z (see player_wand Model).
	wand.look_at(to, Vector3.UP)


func _is_playing_lookdev() -> bool:
	## Editor Play Scene / runtime — not idle edited scene.
	return not Engine.is_editor_hint()


func _notify_hud() -> void:
	var hud := get_node_or_null("LookdevHud")
	if hud != null and hud.has_method("rebuild"):
		hud.call("rebuild")


func _ensure_bucket(bucket_name: String) -> Node3D:
	var bucket := get_node_or_null(bucket_name) as Node3D
	if bucket != null:
		bucket.process_mode = Node.PROCESS_MODE_ALWAYS
		return bucket
	bucket = Node3D.new()
	bucket.name = bucket_name
	bucket.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bucket)
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
	_clear_bucket_children(_spawn_root)


func _cache_spawn_root() -> void:
	_spawn_root = get_node_or_null("SpawnRoot") as Node3D


func _cache_dummy_root() -> void:
	_dummy_root = get_node_or_null("DummyRoot") as Node3D


func _free_dummy_children() -> void:
	_cache_dummy_root()
	if _dummy_root != null:
		_clear_bucket_children(_dummy_root)
