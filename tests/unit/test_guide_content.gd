class_name TestGuideContent
extends RefCounted

const GuideContentScript := preload("res://scripts/ui/guide_content.gd")
const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")
const CharacterSpellLoadoutScript := preload("res://scripts/spells/character_spell_loadout.gd")
const DeliveryObjectiveStateScript := preload(
	"res://scripts/objectives/delivery_objective_state.gd"
)


func run() -> int:
	var failures := 0
	failures += _test_objective_formatting()
	failures += _test_build_view_includes_all_sections()
	failures += _test_codex_row_label()
	failures += _test_codex_row_label_with_cooldown()
	failures += _test_spell_detail_includes_active_cooldown()
	failures += _test_codex_spell_ids_from_loadout()
	failures += _test_spell_detail_includes_effect()
	failures += _test_objective_state_status_lines()
	return failures


func _test_objective_formatting() -> int:
	if GuideContentScript.format_objective_lines(PackedStringArray()) \
			!= GuideContentScript.EMPTY_OBJECTIVES:
		push_error("Expected empty objective lines to use fallback text")
		return 1
	var lines := PackedStringArray(["Line one", "Line two"])
	if GuideContentScript.format_objective_lines(lines) != "Line one\nLine two":
		push_error("Expected objective lines to join with newlines")
		return 1
	return 0


func _test_build_view_includes_all_sections() -> int:
	var view := GuideContentScript.build_view(
		PackedStringArray(["Objective: shrine"])
	)
	if not view.has("hints") or str(view["hints"]).is_empty():
		push_error("Expected guide view to include control hints")
		return 1
	if view["objectives"] != "Objective: shrine":
		push_error("Expected guide view to include objective text")
		return 1
	return 0


func _test_codex_row_label() -> int:
	var spell := SpellDefinitionScript.new()
	spell.id = "fireball"
	spell.display_name = "Fireball"
	spell.incantation_words = PackedStringArray(["fireball"])
	var label := GuideContentScript.codex_row_label(spell, "fireball")
	if label != "Fireball — \"fireball\"":
		push_error("Expected codex row label to match spellbook format")
		return 1
	return 0


func _test_codex_row_label_with_cooldown() -> int:
	var spell := SpellDefinitionScript.new()
	spell.id = "fake_wall"
	spell.display_name = "Fake Wall"
	spell.incantation_words = PackedStringArray(["fake", "wall"])
	var idle := GuideContentScript.codex_row_label(spell, "fake_wall", 0.0)
	if idle.contains("Cooldown"):
		push_error("Expected idle codex row to omit cooldown countdown")
		return 1
	var active := GuideContentScript.codex_row_label(spell, "fake_wall", 12.34)
	if not active.contains("Cooldown — 12.3s"):
		push_error("Expected active codex row to show cooldown countdown")
		return 1
	return 0


func _test_spell_detail_includes_active_cooldown() -> int:
	var spell := SpellDefinitionScript.new()
	spell.id = "fake_wall"
	spell.display_name = "Fake Wall"
	spell.incantation_words = PackedStringArray(["fake", "wall"])
	spell.effect_id = "fake_wall"
	var idle := GuideContentScript.build_spell_detail(spell, 0.0)
	if str(idle.get("body", "")).contains("Cooldown"):
		push_error("Expected idle spell detail to omit cooldown countdown")
		return 1
	var active := GuideContentScript.build_spell_detail(spell, 7.0)
	var body := str(active.get("body", ""))
	if not body.begins_with("Cooldown — 7.0s"):
		push_error("Expected active spell detail to lead with cooldown countdown")
		return 1
	return 0


func _test_codex_spell_ids_from_loadout() -> int:
	var loadout := CharacterSpellLoadoutScript.new()
	var spell := SpellDefinitionScript.new()
	spell.id = "haste"
	loadout.configure([spell])
	loadout.learn_spell("haste")
	var ids := GuideContentScript.codex_spell_ids(loadout)
	if ids.size() != 1 or ids[0] != "haste":
		push_error("Expected codex spell ids to come from known loadout spells")
		return 1
	return 0


func _test_spell_detail_includes_effect() -> int:
	var spell := SpellDefinitionScript.new()
	spell.id = "fireball"
	spell.display_name = "Fireball"
	spell.incantation_words = PackedStringArray(["fireball"])
	spell.effect_id = "fireball"
	var detail := GuideContentScript.build_spell_detail(spell)
	var body := str(detail.get("body", ""))
	if not body.contains("explode"):
		push_error("Expected fireball detail to describe the impact explosion")
		return 1
	if body.contains("flare"):
		push_error("Expected fireball detail to omit signal flare text")
		return 1
	return 0


func _test_objective_state_status_lines() -> int:
	var state := DeliveryObjectiveStateScript.new()
	var seek_lines := state.get_status_lines()
	if seek_lines.is_empty() or not str(seek_lines[0]).contains("relic"):
		push_error("Expected seek phase status to mention relic")
		return 1
	state.phase = DeliveryObjectiveStateScript.Phase.COMPLETE
	var complete_lines := state.get_status_lines()
	if complete_lines.is_empty() or not str(complete_lines[0]).contains("complete"):
		push_error("Expected complete phase status to mention completion")
		return 1
	return 0
