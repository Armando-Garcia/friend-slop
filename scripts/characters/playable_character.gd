class_name PlayableCharacter
extends Character

const WALK_SPEED := 3.0
const SPRINT_SPEED := 5.0
const JUMP_VELOCITY := 2.5
const MOUSE_SENSITIVITY := 0.002
const INTERACT_RANGE_SQ := 9.0
const PLAYER_MIN_SEPARATION := 0.55
const AIM_RAY_LENGTH := 200.0

const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")
const GameWorldScript := preload("res://scripts/game_world.gd")
const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")
const NetworkManagerScript := preload("res://scripts/network/network_manager.gd")
const TargetHighlightScript := preload("res://scripts/spells/target_highlight.gd")
const TargetedObjectControlScript := preload("res://scripts/spells/targeted_object_control.gd")
const FakeWallPlacementScript := preload("res://scripts/headmaster/fake_wall_placement.gd")
const BroomFlightScript := preload("res://scripts/headmaster/broom_flight.gd")
const BroomLocomotionScript := preload("res://scripts/headmaster/broom_locomotion.gd")
const EmberHaloFlightScript := preload("res://scripts/monsters/abilities/ember_halo_flight.gd")
const SpellEffectSyncScript := preload("res://scripts/spells/spell_effect_sync.gd")
const SpellManaScript := preload("res://scripts/spells/spell_mana.gd")

@export var player_index: int = 0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var broom_active := false:
	set(value):
		broom_active = value
		_refresh_broom_visual()

var _spell_loadout: Node
var _casting_session: SpellCastingSession
var _game_hud: CanvasLayer
var _effect_applier: Node
var _armed_spell: SpellDefinition
var _mana: float = SpellManaScript.MANA_MAX
var _speed_boost_multiplier: float = 1.0
var _speed_boost_timer: float = 0.0
var _wand: PlayerWand
var _wand_raised := false
var _spell_fire_charging := false
var _spell_fire_releasing := false
var _fake_wall_placement: Node
var _knockback_vel := Vector3.ZERO
var _knockback_timer := 0.0
var _broom_active_visual := false

@onready var camera_pivot: Node3D = %CameraPivot
@onready var spell_loadout: Node = %CharacterSpellLoadout
@onready var casting_session: SpellCastingSession = %SpellCastingSession
@onready var effect_applier: Node = %SpellEffectApplier
@onready var _view_camera: Camera3D = %FirstPersonCamera


func _ready() -> void:
	if _should_use_preview_mode():
		_enter_editor_preview_mode()
		return

	add_to_group("player")
	collision_layer = 1
	floor_block_on_wall = false
	floor_snap_length = 0.15
	safe_margin = 0.04
	_wand = get_node_or_null("Head/CameraPivot/Wand") as PlayerWand
	if _wand == null:
		_wand = get_node_or_null("Head/CameraPivot/FirstPersonCamera/Wand") as PlayerWand
	if _wand != null:
		_wand.cache_idle_transform()
	_character_color = GameState.get_snail_color(player_index)
	_apply_character_color(_character_color)
	_setup_view_camera()


func _should_use_preview_mode() -> bool:
	if _is_under_spawn_slot():
		return true
	if not is_inside_tree():
		return false
	var scene := get_tree().current_scene
	return scene != null and scene.has_meta("character_preview_scene")


func _is_under_spawn_slot() -> bool:
	var node := get_parent()
	while node != null:
		if node.is_in_group("player_spawn_slot"):
			return true
		node = node.get_parent()
	return false


func _enter_editor_preview_mode() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	collision_layer = 0
	collision_mask = 0
	var sync := get_node_or_null("MultiplayerSynchronizer")
	if sync != null:
		sync.process_mode = Node.PROCESS_MODE_DISABLED
	var cam := get_node_or_null("%FirstPersonCamera") as Camera3D
	if cam != null:
		cam.current = false
	if Engine.is_editor_hint():
		visible = true
		_apply_character_color(_preview_tint())
	else:
		visible = false
		queue_free()


func _preview_tint() -> Color:
	var parent := get_parent()
	if (
		parent != null
		and parent.is_in_group("player_spawn_slot")
		and parent.has_method("get_game_role")
		and int(parent.call("get_game_role")) == 1
	):
		return Color(0.55, 0.2, 0.7)
	var scr := get_script() as Script
	if scr != null and scr.resource_path.ends_with("headmaster.gd"):
		return Color(0.55, 0.2, 0.7)
	return Color(0.25, 0.65, 0.95)


func _exit_tree() -> void:
	NetworkManagerScript.disable_player_sync(self)


func _setup_view_camera() -> void:
	var local_view := _uses_local_view()
	if local_view:
		_view_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_view_camera.queue_free()
	TomeDebug.log(
		"PlayableCharacter",
		"'%s' view=%s authority=%d local_peer=%d"
		% [
			name,
			"local" if local_view else "remote",
			get_multiplayer_authority(),
			multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0,
		]
	)


func _uses_local_view() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return is_multiplayer_authority()


func initialize_player(index: int) -> void:
	player_index = index
	_character_color = GameState.get_snail_color(player_index)
	_apply_character_color(_character_color)
	_on_player_initialized()


func _on_player_initialized() -> void:
	pass


func configure_interaction(
	spell_loadout_ref: Node,
	casting_session_ref: SpellCastingSession,
	game_hud: CanvasLayer,
	effect_applier_ref: Node
) -> void:
	_spell_loadout = spell_loadout_ref
	_casting_session = casting_session_ref
	_game_hud = game_hud
	_effect_applier = effect_applier_ref
	if _casting_session != null:
		if not _casting_session.state_changed.is_connected(_on_cast_session_state_changed):
			_casting_session.state_changed.connect(_on_cast_session_state_changed)
		if not _casting_session.listen_level_changed.is_connected(_on_cast_listen_level_changed):
			_casting_session.listen_level_changed.connect(_on_cast_listen_level_changed)
		if not _casting_session.cast_succeeded.is_connected(_on_wand_cast_succeeded):
			_casting_session.cast_succeeded.connect(_on_wand_cast_succeeded)
		if not _casting_session.cast_failed.is_connected(_on_wand_cast_failed):
			_casting_session.cast_failed.connect(_on_wand_cast_failed)
		if not _casting_session.spell_selected.is_connected(_on_wand_spell_selected):
			_casting_session.spell_selected.connect(_on_wand_spell_selected)


func get_spell_loadout() -> Node:
	return spell_loadout


func get_casting_session() -> SpellCastingSession:
	return casting_session


func get_effect_applier() -> Node:
	return effect_applier


func _begin_fake_wall_placement(spell: SpellDefinition) -> bool:
	if spell == null or _spell_loadout == null:
		return false
	if _spell_loadout.has_method("is_on_cooldown") and _spell_loadout.is_on_cooldown(spell.id):
		return false
	if _fake_wall_placement == null:
		_fake_wall_placement = FakeWallPlacementScript.new()
		_fake_wall_placement.name = "FakeWallPlacement"
		add_child(_fake_wall_placement)
		_fake_wall_placement.configure(self)
	return _fake_wall_placement.begin(spell)


func _is_fake_wall_placing() -> bool:
	return _fake_wall_placement != null and _fake_wall_placement.is_active()


func _monster_book() -> Node:
	return get_node_or_null("MonsterBook")


func _is_monster_book_busy() -> bool:
	var book := _monster_book()
	return book != null and book.has_method("is_busy") and bool(book.call("is_busy"))


func _is_spellbook_open() -> bool:
	return (
		_game_hud != null
		and _game_hud.has_method("is_spellbook_open")
		and bool(_game_hud.call("is_spellbook_open"))
	)


func _is_player_menu_open() -> bool:
	return (
		_game_hud != null
		and _game_hud.has_method("is_player_menu_open")
		and bool(_game_hud.call("is_player_menu_open"))
	)


func _wand_controls_blocked() -> bool:
	return (
		is_stunned()
		or _is_spellbook_open()
		or _is_player_menu_open()
		or _is_monster_book_busy()
		or get_tree().paused
	)


func is_stunned() -> bool:
	var stun := get_node_or_null("Stun")
	return stun != null and stun.has_method("is_stunned") and bool(stun.call("is_stunned"))


func _confirm_fake_wall_placement(spell: SpellDefinition, params: Dictionary) -> void:
	if spell == null or params.is_empty():
		return
	var applier: Node = _effect_applier
	if applier == null:
		applier = get_effect_applier()
	if applier == null:
		return
	if _spell_loadout != null and _spell_loadout.has_method("start_cooldown"):
		_spell_loadout.start_cooldown(spell.id)
	if applier.has_method("cast_spell_with_params"):
		applier.cast_spell_with_params(self, spell, params)
	elif applier.has_method("cast_spell"):
		applier.cast_spell(self, spell)


func apply_speed_boost(duration: float, multiplier: float) -> void:
	_speed_boost_multiplier = multiplier
	_speed_boost_timer = duration


func set_flashlight_enabled(active: bool) -> void:
	if _wand != null:
		_wand.set_flashlight_enabled(active)


func is_flashlight_enabled() -> bool:
	if _wand == null:
		return false
	return _wand.is_flashlight_active()


func toggle_flashlight() -> void:
	set_flashlight_enabled(not is_flashlight_enabled())


func set_flame_glow_enabled(active: bool) -> void:
	if _wand != null:
		_wand.set_flame_glow_enabled(active)


func launch_fireball() -> void:
	launch_fireball_from_params(_aim_fireball_origin(), _aim_fireball_direction())


func launch_fireball_from_params(origin: Vector3, direction: Vector3) -> void:
	var world: Node = GameWorldScript.find_match_root(get_tree())
	if world == null:
		world = get_parent()
	FireballProjectileScript.spawn(world, origin, direction.normalized())


func get_wand_cast_origin() -> Vector3:
	if _wand != null:
		return _wand.get_cast_origin()
	return _head_aim_origin()


func get_wand_cast_direction() -> Vector3:
	return _aim_direction_from_origin(get_wand_cast_origin())


func get_view_camera() -> Camera3D:
	return _view_camera


func get_view_direction() -> Vector3:
	return _camera_aim_direction()


func get_view_origin() -> Vector3:
	if _view_camera != null:
		return _view_camera.global_position
	return head.global_position


func _camera_aim_direction() -> Vector3:
	return -camera_pivot.global_transform.basis.z.normalized()


func _head_aim_origin() -> Vector3:
	return head.global_position + _camera_aim_direction() * 0.6 + Vector3(0.0, 0.1, 0.0)


func _aim_direction_from_origin(origin: Vector3) -> Vector3:
	var to_aim := _crosshair_world_point() - origin
	if to_aim.length_squared() < 0.0001:
		return _camera_aim_direction()
	return to_aim.normalized()


func _crosshair_world_point() -> Vector3:
	var look := _camera_aim_direction()
	var cam_origin := get_view_origin()
	var far_point := cam_origin + look * AIM_RAY_LENGTH
	var world_3d := get_world_3d()
	if world_3d == null or world_3d.direct_space_state == null:
		return far_point
	var ray := PhysicsRayQueryParameters3D.create(cam_origin, far_point)
	ray.collide_with_areas = false
	ray.exclude = [get_rid()]
	var hit := world_3d.direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return far_point
	return hit.position


func _aim_fireball_direction() -> Vector3:
	return get_wand_cast_direction()


func _aim_fireball_origin() -> Vector3:
	return get_wand_cast_origin()


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("ui_cancel") and _wand_raised and not _wand_controls_blocked():
		_lower_wand(true)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clampf(
			camera_pivot.rotation.x,
			deg_to_rad(-70.0),
			deg_to_rad(70.0)
		)
		_sync_body_yaw_to_head()

	if event.is_action_pressed("spellbook"):
		if _casting_session != null \
				and (_casting_session.is_active() or _casting_session.is_tome_teaching()):
			return
		if _game_hud != null and _game_hud.has_method("toggle_spellbook"):
			_game_hud.toggle_spellbook()

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("wand_raise"):
		if _try_toggle_wand_raise():
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("spell_fire"):
		if _try_begin_spell_fire():
			get_viewport().set_input_as_handled()
		return

	if event.is_action_released("spell_fire"):
		if _try_release_spell_fire():
			get_viewport().set_input_as_handled()


func _on_cast_session_state_changed(state: String, _spell: SpellDefinition) -> void:
	if _wand == null:
		return
	var tip_armed := (
		_wand_raised
		and (
			state == SpellCastingSession.STATE_ARMING
			or state == SpellCastingSession.STATE_LISTENING
			or state == SpellCastingSession.STATE_VALIDATING
		)
	)
	_wand.set_armed(tip_armed)


func _on_cast_listen_level_changed(level: float) -> void:
	if _wand != null:
		_wand.set_listen_level(level)


func _on_wand_spell_selected(spell: SpellDefinition) -> void:
	_armed_spell = spell
	_refill_mana()
	if _game_hud != null and _game_hud.has_method("reveal_cast_spell"):
		_game_hud.call("reveal_cast_spell", spell)
	if _wand != null and _wand.has_method("play_spell_recognition"):
		await _wand.play_spell_recognition(spell)
	_lower_wand(false)
	if _wand != null:
		_wand.play_cast_success(spell, true)


func _on_wand_cast_succeeded(
	spell: SpellDefinition,
	mode: String,
	_validation: CastValidationResult
) -> void:
	if _wand == null or mode != "cast":
		return
	_wand.play_cast_success(spell)


func _on_wand_cast_failed(
	_spell: SpellDefinition,
	_reason: String,
	_partial: CastValidationResult
) -> void:
	if _wand == null or _casting_session == null:
		return
	if _casting_session.is_tome_teaching():
		return
	if _casting_session.is_wand_voice_select() and _wand_raised:
		return
	_wand.play_fizzle()


func _separate_from_players() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if node == self or not node is CharacterBody3D:
			continue

		var other: CharacterBody3D = node as CharacterBody3D
		var away: Vector3 = global_position - other.global_position
		away.y = 0.0
		if away.length_squared() < 0.0001:
			away = Vector3(1.0, 0.0, 0.0)
		var distance: float = away.length()
		if distance >= PLAYER_MIN_SEPARATION:
			continue
		global_position += away.normalized() * (PLAYER_MIN_SEPARATION - distance)


func _try_interact() -> void:
	TomeDebug.log("PlayableCharacter", "interact pressed — try_interact")
	if _is_fake_wall_placing():
		_fake_wall_placement.try_confirm()
		return
	if _casting_session != null and _casting_session.is_active():
		return

	if _try_tome_teaching_interact():
		return

	var objective := _find_delivery_objective()
	if objective != null and objective.try_interact(self):
		return

	var interactable: Interactable = _find_nearest_interactable()
	if interactable != null:
		interactable.interact(self)
		return

	TomeDebug.log("PlayableCharacter", "no interactable in range")


func is_carrying_relic() -> bool:
	var objective := _find_delivery_objective()
	return objective != null and objective.is_carrier(self)


func stop_casting_for_relic_carry() -> void:
	if _casting_session == null:
		return
	if _casting_session.is_tome_teaching():
		_casting_session.end_tome_teaching()
	elif _casting_session.is_active():
		_casting_session.cancel()
	_lower_wand(true)
	if _game_hud != null and _game_hud.has_method("hide_casting"):
		_game_hud.hide_casting()


func _try_toggle_wand_raise() -> bool:
	if not is_multiplayer_authority():
		return false
	if _wand_controls_blocked():
		return false
	if is_carrying_relic():
		stop_casting_for_relic_carry()
		return true
	if _casting_session != null and _casting_session.is_tome_teaching():
		return false
	if _wand_raised:
		_lower_wand(true)
		return true
	return _raise_wand_and_listen()


func _raise_wand_and_listen() -> bool:
	if _spell_loadout == null or _casting_session == null:
		return false
	var candidates: Array[SpellDefinition] = _filter_free_cast_candidates(
		_spell_loadout.get_known_spells()
	)
	if candidates.is_empty():
		return false
	_cancel_spell_fire_charge(true)
	_wand_raised = true
	if _wand != null:
		_wand.set_raised(true)
		_wand.set_armed(true)
	_casting_session.start_wand_voice_select(candidates)
	return true


func _lower_wand(cancel_listen: bool) -> void:
	_wand_raised = false
	if cancel_listen and _casting_session != null and _casting_session.is_wand_voice_select():
		_casting_session.cancel()
	if _wand != null:
		_wand.set_raised(false)
		_wand.set_armed(false)


func _can_fire_armed_spell() -> bool:
	if not (
		is_multiplayer_authority()
		and not _wand_controls_blocked()
		and not _wand_raised
		and not is_carrying_relic()
		and _armed_spell != null
		and _effect_applier != null
		and (_casting_session == null or not _casting_session.is_tome_teaching())
	):
		return false
	if _mana <= 0.0:
		return false
	var one: Array[SpellDefinition] = []
	one.append(_armed_spell)
	return not _filter_free_cast_candidates(one).is_empty()

func _try_begin_spell_fire() -> bool:
	if _spell_fire_charging or _spell_fire_releasing:
		return false
	if not _can_fire_armed_spell():
		return false
	_spell_fire_charging = true
	if _wand != null:
		_wand.begin_cast_charge(_armed_spell)
	return true

func _try_release_spell_fire() -> bool:
	if not _spell_fire_charging:
		return false
	_spell_fire_charging = false
	if _wand == null or not _wand.is_cast_charge_ready():
		if _wand != null:
			_wand.cancel_cast_charge()
		return false
	if not _can_fire_armed_spell():
		_wand.fizzle_cast_charge()
		return false
	_spell_fire_releasing = true
	_fire_armed_spell()
	return true

func _cancel_spell_fire_charge(instant: bool = false) -> void:
	if _spell_fire_charging:
		_spell_fire_charging = false
		if _wand != null:
			_wand.cancel_cast_charge(instant)
	if _spell_fire_releasing and _wand != null and instant:
		_wand.cancel_cast_charge(true)

func _fire_armed_spell() -> void:
	var cost := SpellManaScript.cast_cost(_armed_spell)
	var spell := _armed_spell
	if _wand != null:
		if spell != null and spell.get_wand_fx_kind() == SpellDefinition.WandFxKind.LIFT_DEFENSIVE:
			_wand.return_from_cast_charge()
		else:
			await _wand.return_from_cast_charge()
	if not is_instance_valid(self) or spell == null:
		_spell_fire_releasing = false
		return
	if _armed_spell != spell or _mana <= 0.0:
		_spell_fire_releasing = false
		return
	if spell.effect_id == "fake_wall":
		if _begin_fake_wall_placement(spell):
			if _wand != null:
				_wand.play_cast_success(spell, true)
			_spend_mana(cost)
		_spell_fire_releasing = false
		return
	var params := SpellEffectSyncScript.build_params(spell, self)
	var effect_duration := SpellEffectSyncScript.get_effect_duration_sec(spell, params)
	if _effect_applier.has_method("cast_spell"):
		_effect_applier.cast_spell(self, spell)
	if spell.id == "clone" and _spell_loadout != null and _spell_loadout.has_method("start_cooldown"):
		_spell_loadout.start_cooldown(spell.id)
	if effect_duration > 0.0 and _game_hud != null and _game_hud.has_method("show_spell_active"):
		_game_hud.call("show_spell_active", spell.id, effect_duration)
	if _wand != null:
		_wand.play_cast_success(spell, true)
	_spend_mana(cost)
	_spell_fire_releasing = false


func _refill_mana() -> void:
	_mana = SpellManaScript.MANA_MAX
	_sync_mana_hud()

func _spend_mana(amount: float) -> void:
	if amount <= 0.0:
		_sync_mana_hud()
		return
	_mana = maxf(0.0, _mana - amount)
	if _mana <= 0.001:
		_deplete_mana()
	else:
		_sync_mana_hud()

func _deplete_mana() -> void:
	_mana = 0.0
	_cancel_spell_fire_charge(true)
	_armed_spell = null
	if _game_hud != null:
		if _game_hud.has_method("hide_mana"):
			_game_hud.call("hide_mana")
		if _game_hud.has_method("clear_spell_word"):
			_game_hud.call("clear_spell_word")

func _sync_mana_hud() -> void:
	if _game_hud == null:
		return
	if _armed_spell == null or _mana <= 0.001:
		if _game_hud.has_method("hide_mana"):
			_game_hud.call("hide_mana")
		return
	var bar_color := _armed_spell.get_display_color()
	if _game_hud.has_method("show_mana"):
		_game_hud.call("show_mana", _mana, SpellManaScript.MANA_MAX, bar_color)
	elif _game_hud.has_method("set_mana"):
		_game_hud.call("set_mana", _mana, SpellManaScript.MANA_MAX, bar_color)

func _tick_mana_drain(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if _armed_spell == null or _mana <= 0.0:
		return
	_mana = maxf(0.0, _mana - SpellManaScript.drain_rate(_armed_spell) * delta)
	if _mana <= 0.001:
		_deplete_mana()
	else:
		_sync_mana_hud()


func _try_tome_teaching_interact() -> bool:
	if _casting_session == null or not _casting_session.is_tome_teaching():
		return false
	var tome: TomeInteractable = _find_nearest_tome()
	if tome == null or not tome.can_interact(self):
		return false
	tome.interact(self)
	return true


func _filter_free_cast_candidates(known: Array[SpellDefinition]) -> Array[SpellDefinition]:
	var filtered: Array[SpellDefinition] = []
	var tree := get_tree()
	var target_active := TargetHighlightScript.has_active_highlights(tree)
	for spell in known:
		if spell == null:
			continue
		if (
			_spell_loadout != null
			and _spell_loadout.has_method("is_on_cooldown")
			and _spell_loadout.is_on_cooldown(spell.id)
		):
			continue
		match spell.id:
			"pull", "follow":
				if not target_active:
					continue
			"dispell", "clone":
				if not target_active:
					continue
		filtered.append(spell)
	return filtered


func _find_nearest_interactable() -> Interactable:
	var best: Interactable = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("interactable"):
		if not node is Interactable:
			continue
		var interactable := node as Interactable
		if not interactable.can_interact(self):
			continue
		var dist := global_position.distance_squared_to(interactable.global_position)
		if dist < best_dist and dist <= INTERACT_RANGE_SQ:
			best_dist = dist
			best = interactable
	return best


func _find_nearest_tome() -> TomeInteractable:
	var best: TomeInteractable = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("interactable"):
		if not node is TomeInteractable:
			continue
		var tome := node as TomeInteractable
		if not tome.can_interact(self):
			continue
		var dist := global_position.distance_squared_to(tome.global_position)
		if dist < best_dist and dist <= INTERACT_RANGE_SQ:
			best_dist = dist
			best = tome
	return best


func _find_delivery_objective() -> DeliveryObjective:
	for node in get_tree().get_nodes_in_group("delivery_objective"):
		if node is DeliveryObjective:
			return node
	return null


func _update_interaction_prompt() -> void:
	if _game_hud == null or not _game_hud.has_method("set_interaction_prompt"):
		return
	_game_hud.set_interaction_prompt(_resolve_interaction_prompt())


func _resolve_interaction_prompt() -> String:
	if _is_monster_book_busy():
		var book := _monster_book()
		if book != null and book.has_method("get_prompt"):
			var book_prompt := str(book.call("get_prompt"))
			if not book_prompt.is_empty():
				return book_prompt
	if _is_fake_wall_placing():
		return _fake_wall_placement.get_prompt()
	var flight := _get_broom_flight()
	if (
		flight != null
		and flight.has_method("is_active")
		and bool(flight.call("is_active"))
		and flight.has_method("get_prompt")
	):
		return str(flight.call("get_prompt"))
	if _casting_session != null and _casting_session.is_tome_teaching():
		return InputPromptScript.with_action("interact", "Leave tome")
	if _casting_session != null and _casting_session.is_active():
		return ""
	var prompt := ""
	var objective := _find_delivery_objective()
	if objective != null:
		prompt = objective.get_interaction_prompt(self)
	if prompt.is_empty():
		var maze: Node = null
		var match_root: Node = GameWorldScript.find_match_root(get_tree())
		if match_root != null:
			maze = match_root.get_node_or_null("MazeGenerator")
		if maze != null and maze.has_method("get_exit_approach_prompt"):
			prompt = str(maze.call("get_exit_approach_prompt", self))
	if prompt.is_empty():
		var interactable: Interactable = _find_nearest_interactable()
		if interactable != null:
			prompt = interactable.get_prompt()
	if prompt.is_empty() and flight != null and flight.has_method("get_prompt"):
		prompt = str(flight.call("get_prompt"))
	if prompt.is_empty():
		prompt = _default_cast_prompt()
	return prompt


func _default_cast_prompt() -> String:
	var flight := _get_broom_flight()
	if flight != null and flight.has_method("get_prompt"):
		var broom_prompt := str(flight.call("get_prompt"))
		if not broom_prompt.is_empty():
			return broom_prompt
	return ""


func apply_fireball_knockback(fireball_dir: Vector3) -> void:
	if not is_multiplayer_authority() and GameState.is_multiplayer:
		return
	var impulse := BroomLocomotionScript.knockback_impulse(fireball_dir)
	if broom_active:
		var flight := _get_broom_flight()
		if flight != null and flight.has_method("knock_off"):
			flight.call("knock_off", fireball_dir)
	_knockback_vel = impulse
	_knockback_timer = 0.35
	velocity += impulse


func apply_ember_halo_hit(hit_dir: Vector3) -> void:
	if not is_multiplayer_authority() and GameState.is_multiplayer:
		return
	velocity.y = maxf(velocity.y, JUMP_VELOCITY)
	var flat := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if flat.length_squared() > 0.0001:
		flat = flat.normalized()
		var impulse := flat * EmberHaloFlightScript.HIT_KNOCKBACK_SPEED
		_knockback_vel = impulse
		_knockback_timer = 0.25
		velocity.x += impulse.x
		velocity.z += impulse.z
	apply_speed_boost(
		EmberHaloFlightScript.SLOW_DURATION_SEC,
		EmberHaloFlightScript.SLOW_MULTIPLIER
	)


func apply_wretch_command_hit(hit_dir: Vector3) -> void:
	if not is_multiplayer_authority() and GameState.is_multiplayer:
		return
	var dir := hit_dir
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	else:
		dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	var impulse := flat * 6.0 + Vector3.UP * 1.5
	_knockback_vel = impulse
	_knockback_timer = 0.28
	velocity += impulse
	if broom_active:
		var flight := _get_broom_flight()
		if flight != null and flight.has_method("knock_off"):
			flight.call("knock_off", flat)
	apply_speed_boost(2.0, 0.1)


func apply_rat_explode_hit(hit_dir: Vector3) -> void:
	if not is_multiplayer_authority() and GameState.is_multiplayer:
		return
	var dir := hit_dir
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	else:
		dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	var impulse := flat * 14.0 + Vector3.UP * 4.0
	_knockback_vel = impulse
	_knockback_timer = 0.5
	velocity += impulse
	if broom_active:
		var flight := _get_broom_flight()
		if flight != null and flight.has_method("knock_off"):
			flight.call("knock_off", flat)
	apply_speed_boost(0.75, 0.25)


func _get_broom_flight() -> Node:
	return get_node_or_null("BroomFlight")


func _refresh_broom_visual() -> void:
	if _broom_active_visual == broom_active:
		return
	_broom_active_visual = broom_active
	var flight := _get_broom_flight()
	if flight == null and broom_active:
		flight = BroomFlightScript.ensure_on(self, false)
	if flight != null and flight.has_method("set_active_visual"):
		flight.call("set_active_visual", broom_active)


func _sync_body_yaw_to_head() -> void:
	var body := get_node_or_null("Body") as Node3D
	if body == null or head == null:
		return
	body.rotation.y = head.rotation.y


func _physics_process(delta: float) -> void:
	_sync_body_yaw_to_head()
	if not is_multiplayer_authority():
		_refresh_broom_visual()
		return
	_tick_mana_drain(delta)
	if _speed_boost_timer > 0.0:
		_speed_boost_timer -= delta
		if _speed_boost_timer <= 0.0:
			_speed_boost_multiplier = 1.0

	if is_stunned():
		var stun := get_node("Stun")
		stun.call("tick_physics", self, delta, gravity)
		move_and_slide()
		if not bool(stun.call("is_launching")):
			_separate_from_players()
		_update_interaction_prompt()
		return

	var flight := _get_broom_flight()
	if flight != null and flight.has_method("is_active") and bool(flight.call("is_active")):
		flight.call("apply_locomotion", self, delta, _speed_boost_multiplier)
		_apply_knockback_bleed(delta)
		move_and_slide()
		_separate_from_players()
		_update_interaction_prompt()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (head.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := (SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED)
	speed *= _speed_boost_multiplier
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
	_apply_knockback_bleed(delta)

	move_and_slide()
	_separate_from_players()
	_update_interaction_prompt()


func _apply_knockback_bleed(delta: float) -> void:
	if _knockback_timer <= 0.0:
		return
	_knockback_timer -= delta
	velocity.x += _knockback_vel.x * 0.35
	velocity.z += _knockback_vel.z * 0.35
	_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO, 28.0 * delta)
