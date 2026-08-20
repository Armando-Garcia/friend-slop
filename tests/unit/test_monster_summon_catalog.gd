class_name TestMonsterSummonCatalog
extends RefCounted

const CatalogScript := preload("res://scripts/ui/book/monster/monster_summon_catalog.gd")


func run() -> int:
	var failures := 0
	failures += _test_has_pages()
	failures += _test_entry_fields()
	failures += _test_eye_glow_colors_by_id()
	failures += _test_type_scene_paths_by_id()
	return failures


func _test_has_pages() -> int:
	if CatalogScript.entry_count() < 1:
		push_error("Expected at least one summon book page")
		return 1
	return 0


func _test_entry_fields() -> int:
	var entry := CatalogScript.entry_at(0)
	if str(entry.get("display_name", "")).is_empty():
		push_error("Expected display_name on catalog entry")
		return 1
	if str(entry.get("scene_path", "")).is_empty():
		push_error("Expected scene_path on catalog entry")
		return 1
	if not (entry.get("eye_glow_color") is Color):
		push_error("Expected eye_glow_color Color on catalog entry")
		return 1
	return 0


func _test_eye_glow_colors_by_id() -> int:
	var by_id := {}
	for entry in CatalogScript.entries():
		by_id[str(entry.get("id", ""))] = entry.get("eye_glow_color")
	var expected := {
		"wretch": Color(0.25, 1.0, 0.35, 1.0),
		"ash_wretch": Color(0.55, 0.55, 0.58, 1.0),
		"ember_wretch": Color(1.0, 0.12, 0.08, 1.0),
		"charger": Color(0.95, 0.08, 0.05, 1.0),
	}
	for id in expected:
		if not by_id.has(id):
			push_error("Missing summon entry %s" % id)
			return 1
		var got: Color = by_id[id]
		var want: Color = expected[id]
		if not got.is_equal_approx(want):
			push_error("Unexpected eye_glow_color for %s: %s" % [id, got])
			return 1
	return 0


func _test_type_scene_paths_by_id() -> int:
	var expected := {
		"wretch": "res://scenes/monsters/wretch.tscn",
		"ash_wretch": "res://scenes/monsters/ash_wretch.tscn",
		"ember_wretch": "res://scenes/monsters/ember_wretch.tscn",
		"charger": "res://scenes/monsters/charger.tscn",
	}
	for entry in CatalogScript.entries():
		var id := str(entry.get("id", ""))
		if not expected.has(id):
			continue
		var path := str(entry.get("scene_path", ""))
		if path != expected[id]:
			push_error("Expected %s scene_path %s, got %s" % [id, expected[id], path])
			return 1
	return 0
