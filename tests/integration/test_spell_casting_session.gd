class_name TestSpellCastingSession
extends RefCounted

## Integration tests for SpellCastingSession state machine (stub mode, no real mic).
## Requires a SceneTree so nodes can be added; drives _process directly.

const FireballSpell := preload("res://resources/spells/fireball.tres")
const ShowMeSpell := preload("res://resources/spells/show_me.tres")
const HasteSpell := preload("res://resources/spells/haste.tres")
const WorkerScript := preload("res://scripts/spells/spell_validation_worker.gd")
const SpellSttConfigScript := preload("res://scripts/spells/spell_stt_config.gd")
const CharacterSpellLoadoutScript := preload("res://scripts/spells/character_spell_loadout.gd")
const SpellGrammarBuilderScript := preload("res://scripts/spells/spell_grammar_builder.gd")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_stub_tome_teaching_completes(tree)
	failures += _test_validation_runs_async_without_blocking_first_poll(tree)
	failures += _test_offline_session_runs_process(tree)
	failures += _test_non_stub_fails_before_validation_when_stt_unavailable(tree)
	failures += _test_cast_preflight_surfaces_editor_stt_guidance(tree)
	failures += _test_cast_fireball_stub_succeeds(tree)
	failures += _test_cast_fireball_heard_transcript_succeeds(tree)
	failures += _test_cast_fireball_wrong_words_fails(tree)
	failures += _test_free_cast_hold_blocks_silence_auto_commit(tree)
	failures += _test_free_cast_release_commits(tree)
	failures += _test_free_cast_returns_idle_after_success(tree)
	failures += _test_grammar_spells_come_from_player_loadout(tree)
	return failures


func _scene_root() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


func _signal_latch() -> Dictionary:
	return {"hit": false}


func _pump_session_frame(session: SpellCastingSession) -> void:
	session._process(0.016)
	## Validation runner lives under VoiceSpellValidator (match hierarchy).
	if session.has_method("poll_validation_progress"):
		session.poll_validation_progress()
	else:
		var runner := session.get_node_or_null("SpellValidationRunner") as SpellValidationRunner
		if runner != null:
			runner._process(0.0)


func _attach_validator(
	session: SpellCastingSession,
	use_stub: bool = true
) -> VoiceSpellValidator:
	var validator := VoiceSpellValidator.new()
	## Must be in-tree so SpellValidationRunner can process.
	session.add_child(validator)
	## Set after add_child — _ready syncs from SettingsManager first.
	validator.use_stub = use_stub
	session.configure(validator)
	return validator


func _drive_listen_and_validate(
	session: SpellCastingSession,
	transcript_words: PackedStringArray = PackedStringArray()
) -> void:
	session._process(0.51)
	session._recorded_samples = _loud_samples(0.5)
	session._sample_rate = 48000
	if not transcript_words.is_empty():
		session._transcript_words = transcript_words
	session._begin_validation()
	for _attempt in 3000:
		_pump_session_frame(session)
		if session.get_state() == SpellCastingSession.STATE_IDLE:
			break


func _loud_samples(duration_sec: float, sample_rate: int = 48000) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for _i in int(sample_rate * duration_sec):
		samples.append(0.04)
	return samples


func _make_session(tree: SceneTree) -> SpellCastingSession:
	var cast_session_script := load("res://scripts/spells/spell_casting_session.gd") as GDScript
	var player := CharacterBody3D.new()
	var session: SpellCastingSession = cast_session_script.new()
	player.add_child(session)
	tree.root.add_child(player)
	return session


func _free_session(session: SpellCastingSession) -> void:
	var player := session.get_parent()
	if player != null:
		player.queue_free()


func _test_stub_tome_teaching_completes(tree: SceneTree) -> int:
	var session := _make_session(tree)
	var validator := _attach_validator(session, true)

	var succeeded := _signal_latch()
	session.cast_succeeded.connect(func(_spell, _mode, _validation) -> void:
		succeeded["hit"] = true
	)

	session.begin_tome_teaching(FireballSpell)
	session._process(0.51)
	session._recorded_samples = _loud_samples(0.5)
	session._sample_rate = 48000
	session._begin_validation()
	for _attempt in 3000:
		_pump_session_frame(session)
		if session.get_state() == SpellCastingSession.STATE_IDLE:
			break

	_free_session(session)

	if not bool(succeeded["hit"]):
		push_error("Expected stub tome teaching cast to emit cast_succeeded")
		return 1
	return 0


func _test_validation_runs_async_without_blocking_first_poll(tree: SceneTree) -> int:
	WorkerScript.test_delay_sec = 0.08
	var session := _make_session(tree)
	var validator := _attach_validator(session, true)

	var succeeded := _signal_latch()
	session.cast_succeeded.connect(func(_spell, _mode, _validation) -> void:
		succeeded["hit"] = true
	)

	session.begin_tome_teaching(FireballSpell)
	session._process(0.51)
	session._recorded_samples = _loud_samples(0.5)
	session._sample_rate = 48000
	session._begin_validation()

	if session.get_state() != SpellCastingSession.STATE_VALIDATING:
		WorkerScript.test_delay_sec = 0.0
		_free_session(session)
		push_error("Expected validating state after _begin_validation")
		return 1

	session._process(0.0)
	session.poll_validation_progress()
	if bool(succeeded["hit"]):
		WorkerScript.test_delay_sec = 0.0
		_free_session(session)
		push_error("Expected first poll not to finish validation while worker is delayed")
		return 1
	if session.get_state() != SpellCastingSession.STATE_VALIDATING:
		WorkerScript.test_delay_sec = 0.0
		_free_session(session)
		push_error("Expected session to remain validating on first poll")
		return 1

	for _attempt in 3000:
		_pump_session_frame(session)
		if session.get_state() == SpellCastingSession.STATE_IDLE:
			break
		# Yield wall time so the delayed worker thread can finish.
		OS.delay_msec(1)

	WorkerScript.test_delay_sec = 0.0
	_free_session(session)

	if not bool(succeeded["hit"]):
		push_error("Expected async validation to eventually emit cast_succeeded")
		return 1
	return 0


func _test_cast_fireball_stub_succeeds(tree: SceneTree) -> int:
	var session := _make_session(tree)
	var validator := _attach_validator(session, true)

	var outcome := {
		"spell": null,
		"mode": "",
		"validation": null,
	}
	session.cast_succeeded.connect(
		func(spell: SpellDefinition, mode: String, result: CastValidationResult) -> void:
			outcome["spell"] = spell
			outcome["mode"] = mode
			outcome["validation"] = result
	)

	session.start(FireballSpell, SpellCastingSession.Mode.CAST)
	_drive_listen_and_validate(session)
	_free_session(session)

	var cast_spell: SpellDefinition = outcome["spell"]
	var cast_mode: String = str(outcome["mode"])
	var validation: CastValidationResult = outcome["validation"]
	if cast_spell == null or cast_spell.id != "fireball":
		push_error("Expected stub cast to succeed with fireball spell")
		return 1
	if cast_mode != "cast":
		push_error("Expected cast mode 'cast', got: %s" % cast_mode)
		return 1
	if validation == null or not validation.passed:
		push_error("Expected successful fireball validation")
		return 1
	if validation.heard_text != "fireball":
		push_error("Expected heard incantation 'fireball', got: %s" % validation.heard_text)
		return 1
	return 0


func _test_cast_fireball_heard_transcript_succeeds(tree: SceneTree) -> int:
	if not SpellSttConfigScript.get_runtime_issue().is_empty():
		return 0

	var session := _make_session(tree)
	var validator := _attach_validator(session, false)

	var outcome := {"spell": null, "validation": null}
	session.cast_succeeded.connect(
		func(spell: SpellDefinition, _mode: String, result: CastValidationResult) -> void:
			outcome["spell"] = spell
			outcome["validation"] = result
	)

	session.start(FireballSpell, SpellCastingSession.Mode.CAST)
	_drive_listen_and_validate(session, PackedStringArray(["fireball"]))
	_free_session(session)

	var cast_spell: SpellDefinition = outcome["spell"]
	var validation: CastValidationResult = outcome["validation"]
	if cast_spell == null or cast_spell.id != "fireball":
		push_error("Expected non-stub cast with 'fireball' transcript to succeed")
		return 1
	if validation == null or not validation.passed:
		push_error(
			"Expected fireball validation to pass, reason: %s"
			% (validation.failure_reason if validation != null else "null")
		)
		return 1
	if validation.heard_text != "fireball":
		push_error("Expected heard text 'fireball', got: %s" % validation.heard_text)
		return 1
	return 0


func _test_cast_fireball_wrong_words_fails(tree: SceneTree) -> int:
	if not SpellSttConfigScript.get_runtime_issue().is_empty():
		return 0

	var session := _make_session(tree)
	var validator := _attach_validator(session, false)

	var failure := {"hit": false, "reason": ""}
	session.cast_failed.connect(func(_spell, reason, _partial) -> void:
		failure["hit"] = true
		failure["reason"] = reason
	)

	session.start(FireballSpell, SpellCastingSession.Mode.CAST)
	_drive_listen_and_validate(session, PackedStringArray(["show", "me"]))
	_free_session(session)

	if not bool(failure["hit"]):
		push_error("Expected fireball cast to fail when incantation was 'show me'")
		return 1
	var fail_reason: String = str(failure["reason"])
	if fail_reason.is_empty():
		push_error("Expected a failure reason for wrong incantation")
		return 1
	return 0


func _test_offline_session_runs_process(tree: SceneTree) -> int:
	var session := _make_session(tree)
	var validator := _attach_validator(session, true)

	var multiplayer_api := tree.root.get_multiplayer()
	var prev_peer: MultiplayerPeer = multiplayer_api.multiplayer_peer
	multiplayer_api.multiplayer_peer = OfflineMultiplayerPeer.new()

	session.begin_tome_teaching(FireballSpell)
	var state_before := session.get_state()
	session._process(0.51)
	var state_after := session.get_state()

	multiplayer_api.multiplayer_peer = prev_peer
	_free_session(session)

	if state_before != "arming":
		push_error("Expected arming state at tome teaching start")
		return 1
	if state_after != "listening":
		push_error(
			"Expected offline cast session to advance to listening, got: %s"
			% state_after
		)
		return 1
	return 0


func _pump_to_listening(session: SpellCastingSession) -> void:
	for _i in 30:
		if session.get_state() == SpellCastingSession.STATE_LISTENING:
			return
		session._process(0.016)


func _test_free_cast_hold_blocks_silence_auto_commit(tree: SceneTree) -> int:
	var session := _make_session(tree)
	var validator := _attach_validator(session, true)

	session.start_free_cast([FireballSpell])
	_pump_to_listening(session)

	session._speech_detected = true
	session._listen_elapsed = 1.0
	session._silence_after_speech = 1.0
	session._update_listen_coaching(0.0, 0.2)

	if session.get_state() != SpellCastingSession.STATE_LISTENING:
		_free_session(session)
		push_error("Expected silence not to auto-commit while hold release is required")
		return 1

	_free_session(session)
	return 0


func _test_free_cast_release_commits(tree: SceneTree) -> int:
	var session := _make_session(tree)
	var validator := _attach_validator(session, true)

	var succeeded := _signal_latch()
	session.cast_succeeded.connect(func(_spell, _mode, _validation) -> void:
		succeeded["hit"] = true
	)

	session.start_free_cast([FireballSpell])
	_pump_to_listening(session)
	session._recorded_samples = _loud_samples(0.5)
	session._sample_rate = 48000
	session.release_wand_hold()

	for _attempt in 3000:
		_pump_session_frame(session)
		if session.get_state() == SpellCastingSession.STATE_IDLE:
			break

	_free_session(session)

	if not bool(succeeded["hit"]):
		push_error("Expected free cast to commit on wand release")
		return 1
	return 0


func _test_grammar_spells_come_from_player_loadout(tree: SceneTree) -> int:
	var session := _make_session(tree)
	var loadout: CharacterSpellLoadout = CharacterSpellLoadoutScript.new()
	loadout.configure([FireballSpell, ShowMeSpell, HasteSpell])
	loadout.learn_spell("fireball", "test")
	loadout.learn_spell("haste", "test")

	var validator := _attach_validator(session, true)
	## Re-configure with loadout after attach.
	session.configure(validator, loadout)

	# Pass a different candidate list; grammar must still use the loadout.
	session.start_free_cast([ShowMeSpell])
	var grammar := session._grammar_spells_for_player()
	var grammar_ids: Array[String] = []
	for spell in grammar:
		grammar_ids.append(spell.id)
	grammar_ids.sort()

	_free_session(session)

	if grammar_ids != ["fireball", "haste"]:
		push_error(
			"Expected grammar from player loadout known spells, got: %s" % str(grammar_ids)
		)
		return 1

	var phrases: Variant = JSON.parse_string(
		SpellGrammarBuilderScript.build_json_from_spell_dicts(
			SpellValidationCodec.spells_to_dict_array(grammar)
		)
	)
	if not phrases is Array or phrases.size() != 3:
		push_error("Expected grammar JSON for known spells plus [unk], got: %s" % phrases)
		return 1
	return 0


func _test_free_cast_returns_idle_after_success(tree: SceneTree) -> int:
	var session := _make_session(tree)
	var validator := _attach_validator(session, true)

	session.start_free_cast([FireballSpell])
	_pump_to_listening(session)
	session._recorded_samples = _loud_samples(0.5)
	session._sample_rate = 48000
	session.release_wand_hold()
	for _attempt in 3000:
		if session.get_state() == SpellCastingSession.STATE_IDLE:
			break
		_pump_session_frame(session)

	_free_session(session)

	if session.get_state() != SpellCastingSession.STATE_IDLE:
		push_error("Expected free cast to return idle after one successful cast")
		return 1
	return 0


func _test_non_stub_fails_before_validation_when_stt_unavailable(tree: SceneTree) -> int:
	var runtime_issue := SpellSttConfigScript.get_runtime_issue()
	if runtime_issue.is_empty():
		return 0

	var session := _make_session(tree)
	var validator := _attach_validator(session, false)

	var failure := {"reason": ""}
	session.cast_failed.connect(func(_spell, reason, _partial) -> void:
		failure["reason"] = reason
	)

	session.begin_tome_teaching(FireballSpell)
	session._process(0.51)
	session._recorded_samples = _loud_samples(0.5)
	session._sample_rate = 48000
	session._begin_validation()

	var state := session.get_state()
	_free_session(session)

	var fail_reason: String = str(failure["reason"])
	if fail_reason != runtime_issue:
		push_error(
			"Expected cast to fail at STT preflight with runtime issue, got: %s"
			% fail_reason
		)
		return 1
	if state != "idle":
		push_error(
			"Expected idle state after STT preflight failure, got: %s" % state
		)
		return 1
	return 0


func _test_cast_preflight_surfaces_editor_stt_guidance(tree: SceneTree) -> int:
	if (
		not SpellSttConfigScript.is_configured()
		or GdvoskAdapter.is_available()
		or not OS.has_feature("editor")
	):
		return 0

	var expected := SpellSttConfigScript.get_extension_load_issue(true)
	var session := _make_session(tree)
	var validator := _attach_validator(session, false)

	var fail_reason := ""
	session.cast_failed.connect(func(_spell, reason, _partial) -> void:
		fail_reason = reason
	)

	session.begin_tome_teaching(FireballSpell)
	session._process(0.51)
	session._recorded_samples = _loud_samples(0.5)
	session._sample_rate = 48000
	session._begin_validation()

	var state := session.get_state()
	_free_session(session)

	var failures := 0
	if fail_reason != expected:
		push_error(
			"Expected cast preflight to fail with editor STT guidance, got: %s"
			% fail_reason
		)
		failures += 1
	elif not fail_reason.contains("gdvosk is not loaded in the Godot editor"):
		push_error(
			"Expected validation FAILED guidance for unloaded editor gdvosk, got: %s"
			% fail_reason
		)
		failures += 1
	if state != "idle":
		push_error(
			"Expected idle state after editor STT preflight failure, got: %s" % state
		)
		failures += 1
	return failures
