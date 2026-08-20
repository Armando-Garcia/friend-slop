class_name TestInputBindOverlaps
extends RefCounted

const CatalogScript := preload("res://scripts/ui/keybinds/input_rebind_catalog.gd")
const StoreScript := preload("res://scripts/ui/keybinds/input_rebind_store.gd")


func run() -> int:
	var failures := 0
	var input_bak := StoreScript.snapshot_catalog()
	failures += _test_catalog_groups()
	failures += _test_overlap_matrix()
	failures += _test_conflict_scan_filters_allowed()
	failures += _test_project_defaults_allowed_shares()
	StoreScript.apply_snapshot(input_bak)
	return failures


func _p_key() -> Dictionary:
	return {
		"type": "key",
		"physical_keycode": KEY_P,
		"alt": false,
		"shift": false,
		"ctrl": false,
		"meta": false,
	}


func _test_catalog_groups() -> int:
	var err := _catalog_group_error()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _catalog_group_error() -> String:
	var err := ""
	if CatalogScript.has_action("not_a_catalog_action"):
		err = "Unknown actions must not be in the catalog"
	if err.is_empty() and not CatalogScript.group_of("not_a_catalog_action").is_empty():
		err = "Unknown actions must have an empty group"
	if err.is_empty() and CatalogScript.group_of("jump") != CatalogScript.GROUP_MOVEMENT:
		err = "jump must be Movement"
	if err.is_empty() and CatalogScript.group_of("crouch") != CatalogScript.GROUP_MOVEMENT:
		err = "crouch must be Movement"
	if err.is_empty() and CatalogScript.group_of("dash") != CatalogScript.GROUP_MOVEMENT:
		err = "dash must be Movement"
	if err.is_empty() and CatalogScript.group_of("move_forward") != CatalogScript.GROUP_MOVEMENT:
		err = "move_forward must be Movement"
	var flying := PackedStringArray()
	var saw_movement := false
	var saw_flying := false
	for entry in CatalogScript.entries():
		if not err.is_empty():
			break
		var action := str(entry.get("action", ""))
		var group := str(entry.get("group", ""))
		if CatalogScript.group_of(action) != group:
			err = "group_of(%s) must match the catalog entry" % action
			break
		if group == CatalogScript.GROUP_FLYING:
			flying.append(action)
			if not saw_movement:
				err = "Flying must come after Movement"
			saw_flying = true
		elif group == CatalogScript.GROUP_MOVEMENT:
			saw_movement = true
			if saw_flying:
				err = "Movement must not resume after Flying"
		elif saw_movement and not saw_flying:
			err = "Flying must be the section directly below Movement"
	if err.is_empty() and flying.size() != 2:
		err = "Flying must only list Ascend and Descend"
	if err.is_empty() and (not flying.has("fly_ascend") or not flying.has("fly_descend")):
		err = "Flying must contain fly_ascend and fly_descend"
	if err.is_empty() and CatalogScript.group_of("book_page_prev") != CatalogScript.GROUP_WORLD:
		err = "book_page_prev must stay in World / UI"
	if err.is_empty() and CatalogScript.group_of("book_page_next") != CatalogScript.GROUP_WORLD:
		err = "book_page_next must stay in World / UI"
	return err


func _test_overlap_matrix() -> int:
	var err := _overlap_matrix_error()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _overlap_matrix_error() -> String:
	var err := ""
	if not CatalogScript.is_allowed_bind_overlap("jump", "jump"):
		err = "An action may share a bind with itself"
	var flight := PackedStringArray(["fly_ascend", "fly_descend"])
	var loco := PackedStringArray(["jump", "crouch", "dash"])
	for fly in flight:
		if not err.is_empty():
			break
		for ground in loco:
			if not CatalogScript.is_allowed_bind_overlap(fly, ground):
				err = "%s vs %s must be an allowed overlap" % [fly, ground]
				break
			if not CatalogScript.is_allowed_bind_overlap(ground, fly):
				err = "%s vs %s must be symmetric" % [ground, fly]
				break
		if err.is_empty() and CatalogScript.is_allowed_bind_overlap(fly, "move_forward"):
			err = "%s vs move_forward must still conflict" % fly
		if err.is_empty() and CatalogScript.is_allowed_bind_overlap(fly, "interact"):
			err = "%s vs interact must still conflict" % fly
	if err.is_empty() and CatalogScript.is_allowed_bind_overlap("fly_ascend", "fly_descend"):
		err = "Two flying actions must still conflict"
	if err.is_empty() and CatalogScript.is_allowed_bind_overlap("jump", "dash"):
		err = "jump vs dash must still conflict"
	if err.is_empty() and CatalogScript.is_allowed_bind_overlap("book_page_prev", "book_page_next"):
		err = "Book page prev vs next must still conflict"
	for entry in CatalogScript.entries():
		if not err.is_empty():
			break
		var other := str(entry.get("action", ""))
		err = _book_page_overlap_error("book_page_prev", other)
		if err.is_empty():
			err = _book_page_overlap_error("book_page_next", other)
	if err.is_empty() and CatalogScript.is_allowed_bind_overlap("book_page_prev", "missing_action"):
		err = "Book pages must not waive unknown actions"
	return err


func _book_page_overlap_error(page: String, other: String) -> String:
	if other == page:
		return ""
	var allowed := CatalogScript.is_allowed_bind_overlap(page, other)
	var reverse := CatalogScript.is_allowed_bind_overlap(other, page)
	var err := ""
	if allowed != reverse:
		err = "%s vs %s must be symmetric" % [page, other]
	var expect := _expect_book_page_overlap(other)
	if err.is_empty() and allowed != expect:
		if expect:
			err = "%s vs %s must be an allowed overlap" % [page, other]
		else:
			err = "%s vs %s must still conflict" % [page, other]
	return err


func _expect_book_page_overlap(other: String) -> bool:
	if other == "book_page_prev" or other == "book_page_next":
		return false
	var group := CatalogScript.group_of(other)
	return (
		group == CatalogScript.GROUP_MOVEMENT
		or group == CatalogScript.GROUP_FLYING
		or group == CatalogScript.GROUP_SPELLS
		or group == CatalogScript.GROUP_ITEMS
		or group == CatalogScript.GROUP_WORLD
	)


func _test_conflict_scan_filters_allowed() -> int:
	var err := _conflict_scan_error()
	StoreScript.apply_snapshot(SettingsManager.get_input_project_defaults())
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _conflict_scan_error() -> String:
	var err := _expect_conflict_set(
		PackedStringArray(["jump", "dash", "fly_ascend"]),
		PackedStringArray(["jump", "dash"]),
		PackedStringArray(["fly_ascend"])
	)
	if err.is_empty():
		err = _expect_conflict_set(
			PackedStringArray(["book_page_prev", "jump", "interact"]),
			PackedStringArray(["jump", "interact"]),
			PackedStringArray(["book_page_prev"])
		)
	if err.is_empty():
		err = _expect_conflict_set(
			PackedStringArray(["fly_ascend", "fly_descend", "jump"]),
			PackedStringArray(["fly_ascend", "fly_descend"]),
			PackedStringArray(["jump"])
		)
	if err.is_empty():
		err = _expect_conflict_set(
			PackedStringArray(["book_page_prev", "book_page_next", "crouch"]),
			PackedStringArray(["book_page_prev", "book_page_next"]),
			PackedStringArray(["crouch"])
		)
	return err


func _expect_conflict_set(
	sharing: PackedStringArray, must_have: PackedStringArray, must_not: PackedStringArray
) -> String:
	var before := StoreScript.snapshot_actions(sharing)
	for action in sharing:
		StoreScript.apply_packed(action, _p_key())
	var conflicts := StoreScript.conflict_action_names()
	StoreScript.apply_snapshot(before)
	var err := ""
	for action in must_have:
		if err.is_empty() and not conflicts.has(action):
			err = "%s must stay in the conflict list" % action
	for action in must_not:
		if err.is_empty() and conflicts.has(action):
			err = "%s must not highlight when every extra share is allowed" % action
	return err


func _test_project_defaults_allowed_shares() -> int:
	SettingsManager.snapshot_input_project_defaults()
	StoreScript.apply_snapshot(SettingsManager.get_input_project_defaults())
	var conflicts := StoreScript.conflict_action_names()
	var waived := PackedStringArray(
		["jump", "crouch", "dash", "fly_ascend", "fly_descend"]
	)
	for action in waived:
		if conflicts.has(action):
			push_error("Project default %s must not highlight vs allowed flight shares" % action)
			return 1
	return 0
