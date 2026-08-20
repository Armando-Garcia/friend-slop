class_name CharacterSpellLoadout
extends Node

## Per-character known spells, split into starting kit vs spells learned in-run.
## Most casting is gated by voice recognition; spells with cooldown_sec use timers.

signal spell_learned(spell_id: String)
signal spell_unlearned(spell_id: String)
signal loadout_changed()

const SOURCE_STARTING := "starting"
const SOURCE_TOME := "tome"

var _spell_defs: Dictionary = {}
## spell_id -> { "learned_at": int }
var _starting: Dictionary = {}
## spell_id -> { "learned_at": int, "source": String }
var _learned: Dictionary = {}
## spell_id -> cooldown end time (msec)
var _cooldown_until_msec: Dictionary = {}


func configure(spells: Array[SpellDefinition]) -> void:
	_spell_defs.clear()
	for spell in spells:
		if spell != null:
			_spell_defs[spell.id] = spell


func reset() -> void:
	_starting.clear()
	_learned.clear()
	_cooldown_until_msec.clear()
	loadout_changed.emit()


func is_on_cooldown(spell_id: String) -> bool:
	return remaining_cooldown_sec(spell_id) > 0.0


func remaining_cooldown_sec(spell_id: String) -> float:
	if not _cooldown_until_msec.has(spell_id):
		return 0.0
	var remaining_msec: int = int(_cooldown_until_msec[spell_id]) - Time.get_ticks_msec()
	if remaining_msec <= 0:
		_cooldown_until_msec.erase(spell_id)
		return 0.0
	return float(remaining_msec) / 1000.0


func start_cooldown(spell_id: String) -> void:
	var spell: SpellDefinition = get_spell_definition(spell_id)
	if spell == null or spell.cooldown_sec <= 0.0:
		return
	_cooldown_until_msec[spell_id] = (
		Time.get_ticks_msec() + int(round(spell.cooldown_sec * 1000.0))
	)


func knows(spell_id: String) -> bool:
	return _starting.has(spell_id) or _learned.has(spell_id)


func has_known_spells() -> bool:
	return not _starting.is_empty() or not _learned.is_empty()


## Grant the role starter kit. Spells already known are left alone.
func apply_starting_spells(spell_ids: Array[String]) -> void:
	var changed := false
	for spell_id in spell_ids:
		if _add_starting_spell(spell_id):
			changed = true
			spell_learned.emit(spell_id)
	if changed:
		loadout_changed.emit()


## Learn a spell during the run (tomes, etc.). Source "starting" goes into the starter set.
func learn_spell(spell_id: String, source: String = "") -> bool:
	if spell_id.is_empty() or not _spell_defs.has(spell_id):
		return false
	if knows(spell_id):
		return false
	if source == SOURCE_STARTING:
		_add_starting_spell(spell_id)
	else:
		_learned[spell_id] = {
			"learned_at": Time.get_ticks_msec(),
			"source": source if not source.is_empty() else SOURCE_TOME,
		}
	spell_learned.emit(spell_id)
	loadout_changed.emit()
	return true


func unlearn_spell(spell_id: String) -> void:
	var removed := false
	if _starting.has(spell_id):
		_starting.erase(spell_id)
		removed = true
	if _learned.has(spell_id):
		_learned.erase(spell_id)
		removed = true
	if not removed:
		return
	spell_unlearned.emit(spell_id)
	loadout_changed.emit()


func get_starting_spell_ids() -> Array[String]:
	return _sorted_ids(_starting)


func get_learned_spell_ids() -> Array[String]:
	return _sorted_ids(_learned)


func get_known_spell_ids() -> Array[String]:
	var seen: Dictionary = {}
	var ids: Array[String] = []
	for spell_id in _starting.keys():
		seen[spell_id] = true
		ids.append(spell_id)
	for spell_id in _learned.keys():
		if seen.has(spell_id):
			continue
		ids.append(spell_id)
	ids.sort()
	return ids


func get_starting_spells() -> Array[SpellDefinition]:
	return _defs_for_ids(get_starting_spell_ids())


func get_learned_spells() -> Array[SpellDefinition]:
	return _defs_for_ids(get_learned_spell_ids())


func get_known_spells() -> Array[SpellDefinition]:
	return _defs_for_ids(get_known_spell_ids())


func get_spell_definition(spell_id: String) -> SpellDefinition:
	return _spell_defs.get(spell_id)


func _add_starting_spell(spell_id: String) -> bool:
	if spell_id.is_empty() or not _spell_defs.has(spell_id):
		return false
	if knows(spell_id):
		return false
	_starting[spell_id] = {"learned_at": Time.get_ticks_msec()}
	return true


func _sorted_ids(bucket: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for spell_id in bucket.keys():
		ids.append(spell_id)
	ids.sort()
	return ids


func _defs_for_ids(ids: Array[String]) -> Array[SpellDefinition]:
	var spells: Array[SpellDefinition] = []
	for spell_id in ids:
		var spell: SpellDefinition = get_spell_definition(spell_id)
		if spell != null:
			spells.append(spell)
	return spells
