class_name TomeInteractable
extends Interactable

## Floating spell tome — learn spell by voice casting while reading.

@export var float_height := 0.35
@export var float_speed := 1.6

var _placement: DiscoverablePlacement
var _definition: DiscoverableDefinition
var _spell: SpellDefinition
var _mesh: MeshInstance3D
var _base_y: float = 1.2
var _time := 0.0
var _learning_player: Node = null


func _ready() -> void:
	super._ready()
	prompt_text = "Read tome"
	_mesh = get_node_or_null("Mesh") as MeshInstance3D
	_base_y = global_position.y


func _on_body_entered(body: Node3D) -> void:
	super._on_body_entered(body)
	if body.is_in_group("player"):
		_debug_player_range("body_entered", body)


func _on_body_exited(body: Node3D) -> void:
	super._on_body_exited(body)
	if body.is_in_group("player"):
		_debug_player_range("body_exited", body)


func _debug_player_range(event_name: String, body: Node3D) -> void:
	if not TomeDebug.enabled:
		return
	var dist: float = global_position.distance_to(body.global_position)
	TomeDebug.log(
		"Tome",
		"%s player %s dist=%.2f player_inside=%s prompt='%s'"
		% [name, event_name, dist, _player_inside, prompt_text]
	)


func initialize(placement: DiscoverablePlacement, definition: DiscoverableDefinition) -> void:
	_placement = placement
	_definition = definition
	_spell = _resolve_spell(placement.variant_id)
	TomeDebug.log(
		"Tome",
		"initialize variant='%s' spell=%s pos=%s monitoring=%s"
		% [
			placement.variant_id,
			_spell.id if _spell != null else "null",
			str(global_position),
			monitoring,
		]
	)
	if _spell == null:
		TomeDebug.log(
			"Tome",
			"FAILED to resolve spell '%s' — registry in tree: %s"
			% [
				placement.variant_id,
				get_tree().get_first_node_in_group("spell_registry") != null,
			]
		)
	if _spell != null:
		_update_prompt()
		_apply_tome_color(_spell.get_display_color())


func get_prompt() -> String:
	if _learning_player != null:
		return InputPromptScript.with_action("interact", "Leave tome")
	return super.get_prompt()


func get_spell() -> SpellDefinition:
	return _spell


func is_teaching() -> bool:
	return _learning_player != null


func can_interact(player: Node) -> bool:
	if player is PlayableCharacter and (player as PlayableCharacter).is_carrying_relic():
		return false
	if _spell == null:
		return false
	if _learning_player != null and _learning_player != player:
		return false
	return super.can_interact(player) or _learning_player == player


func interact(player: Node) -> void:
	TomeDebug.log("Tome", "%s interact() called by %s" % [name, player.name])
	var session: SpellCastingSession = _find_casting_session(player)
	if session == null:
		TomeDebug.log("Tome", "%s interact aborted: SpellCastingSession not found" % name)
		return

	if session.is_tome_teaching() and session.get_tome_spell() == _spell:
		TomeDebug.log("Tome", "%s ending tome teaching via [F]" % name)
		_stop_teaching(player)
		return

	if not can_interact(player):
		TomeDebug.log(
			"Tome",
			"%s interact aborted: can_interact=false player_inside=%s dist=%.2f"
			% [name, _player_inside, global_position.distance_to(player.global_position)]
		)
		return
	if session.is_active():
		TomeDebug.log(
			"Tome",
			"%s interact aborted: casting session already active (state=%s)"
			% [name, session.get_state()]
		)
		return

	TomeDebug.log(
		"Tome",
		"%s starting tome teaching for spell '%s'" % [name, _spell.id]
	)
	_learning_player = player
	_update_prompt()
	if not session.tome_teaching_changed.is_connected(_on_tome_teaching_changed):
		session.tome_teaching_changed.connect(_on_tome_teaching_changed)
	session.begin_tome_teaching(_spell)


func _on_tome_teaching_changed(active: bool, spell: SpellDefinition) -> void:
	if active:
		return
	if spell != null and spell != _spell:
		return
	_learning_player = null
	_update_prompt()


func _stop_teaching(player: Node) -> void:
	if _learning_player != player:
		return
	var session: SpellCastingSession = _find_casting_session(player)
	if session != null and session.is_tome_teaching() and session.get_tome_spell() == _spell:
		session.end_tome_teaching()
	_learning_player = null
	_update_prompt()


func _update_prompt() -> void:
	if _spell == null:
		return
	if _learning_player != null:
		prompt_text = "Leave tome"
	else:
		prompt_text = "Learn '%s'" % _spell.display_name


func _process(delta: float) -> void:
	_time += delta
	position.y = sin(_time * float_speed) * float_height


func _resolve_spell(spell_id: String) -> SpellDefinition:
	var registry: Node = get_tree().get_first_node_in_group("spell_registry")
	if registry != null and registry.has_method("get_spell"):
		return registry.get_spell(spell_id)
	return null


func _find_casting_session(player: Node) -> SpellCastingSession:
	if player.has_node("SpellCastingSession"):
		return player.get_node("SpellCastingSession") as SpellCastingSession
	return get_tree().get_first_node_in_group("casting_session") as SpellCastingSession


func _apply_tome_color(color: Color) -> void:
	if _mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.5
	material.emission_energy_multiplier = 1.8
	material.roughness = 0.35
	_mesh.material_override = material


func consume_with_vfx() -> void:
	_learning_player = null
	monitoring = false
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.35)
	if _mesh != null:
		tween.tween_property(_mesh, "position:y", _mesh.position.y + 0.8, 0.35)
	tween.chain().tween_callback(queue_free)
