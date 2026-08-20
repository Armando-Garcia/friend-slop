class_name TestBookPanels
extends RefCounted

## Verifies pre-baked two-page books: monster summon tome and spellbook.

const MonsterBookScene := preload("res://scenes/ui/book/monster/monster_book.tscn")
const SpellBookScene := preload("res://scenes/ui/book/spell/spell_book.tscn")
const CharacterSpellLoadoutScript := preload("res://scripts/spells/character_spell_loadout.gd")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_monster_book_paging(tree)
	failures += _test_monster_book_has_select(tree)
	failures += _test_monster_odd_page_blank_right(tree)
	failures += _test_spellbook_paging(tree)
	failures += _test_spellbook_is_browse_only(tree)
	failures += _test_spellbook_always_has_pages(tree)
	failures += _test_player_menu_has_no_spellbook_tab(tree)
	return failures


func _key_action(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func _test_monster_book_paging(tree: SceneTree) -> int:
	var book: Control = MonsterBookScene.instantiate()
	tree.root.add_child(book)
	book.open_book()
	var problem := _check_monster_book_opens(book)
	if problem.is_empty():
		problem = _check_monster_book_turns_pages(book)
	tree.root.remove_child(book)
	book.queue_free()
	if problem.is_empty():
		return 0
	push_error(problem)
	return 1


func _check_monster_book_opens(book: Control) -> String:
	var left_title := _page_title(book, true)
	var prev_btn: Button = book.get_node("Center/BookRoot/OpenBook/PrevButton")
	var next_btn: Button = book.get_node("Center/BookRoot/OpenBook/NextButton")
	var problem := ""
	if book.page_count() != 4:
		problem = "Expected 4 baked monster pages, got %d" % book.page_count()
	elif book.spread_count() != 2:
		problem = "Expected 2 spreads for 4 pages, got %d" % book.spread_count()
	elif left_title != "Rat Queen" or book.get_page_index() != 0:
		problem = "Expected monster book to open on Rat Queen (page index 0)"
	elif not prev_btn.disabled:
		problem = "Expected prev disabled on the first spread"
	elif next_btn.disabled:
		problem = "Expected next enabled when more spreads remain"
	elif not prev_btn.text.contains("[Q]") or not next_btn.text.contains("[E]"):
		problem = "Expected arrow buttons to indicate the Q/E hotkeys"
	return problem


func _check_monster_book_turns_pages(book: Control) -> String:
	var next_btn: Button = book.get_node("Center/BookRoot/OpenBook/NextButton")
	var prev_btn: Button = book.get_node("Center/BookRoot/OpenBook/PrevButton")
	var problem := ""
	book._input(_key_action("book_page_prev"))
	if book.get_spread_index() != 0 or book._turning:
		problem = "Expected Q on the first spread to stay put (no wrap)"
	else:
		next_btn.pressed.emit()
		if book.get_spread_index() != 1 or not book._turning:
			problem = "Expected next button to advance to spread 1 with a turn animation"
		else:
			book.close_book()
			if book.is_open() or book._turning or book._flip_leaf != null:
				problem = "Expected close to reset the page flip"
			else:
				problem = _check_monster_book_end_stop(book, prev_btn, next_btn)
	return problem


func _check_monster_book_end_stop(
	book: Control, prev_btn: Button, next_btn: Button
) -> String:
	book.open_book()
	book._spread_index = 1
	book._show_spread(1)
	if book.get_spread_index() != 1:
		return "Expected to open on the last monster spread for end-stop check"
	book.next_page()
	if book.get_spread_index() != 1 or book._turning:
		return "Expected next on the last spread to stay put (no wrap)"
	if prev_btn.disabled or not next_btn.disabled:
		return "Expected only next disabled on the last spread"
	book._input(_key_action("ui_cancel"))
	if book.is_open() or book.visible:
		return "Expected Esc to close the monster book"
	return ""


func _test_monster_book_has_select(tree: SceneTree) -> int:
	var book: Control = MonsterBookScene.instantiate()
	tree.root.add_child(book)
	book.open_book()
	var select_btn := book.get_node_or_null(
		"Center/BookRoot/OpenBook/BookBody/Inner/Spread/LeftPage/PageHost"
		+ "/WretchPage/Margin/VBox/SelectButton"
	)
	if select_btn == null:
		## Page instance name may vary; search under left host.
		select_btn = _find_select_button(book)
	var ok: bool = select_btn != null and book.has_signal("monster_selected")
	tree.root.remove_child(book)
	book.queue_free()
	if not ok:
		push_error("Expected monster book to keep its left-click select feature")
		return 1
	return 0


func _test_monster_odd_page_blank_right(tree: SceneTree) -> int:
	var book: Control = MonsterBookScene.instantiate()
	tree.root.add_child(book)
	book.open_book()
	book._spread_index = 1
	book._show_spread(1)
	var right_host: Node = book.get_node(
		"Center/BookRoot/OpenBook/BookBody/Inner/Spread/RightPage/PageHost"
	)
	var right_page := right_host.get_child(0) if right_host.get_child_count() > 0 else null
	var left_title := _page_title(book, true)
	var right_title := ""
	if right_page != null:
		var label := right_page.get_node_or_null("Margin/VBox/TitleLabel") as Label
		if label != null:
			right_title = label.text
	tree.root.remove_child(book)
	book.queue_free()
	if left_title != "Ember Caster":
		push_error("Expected last spread left page to be Ember Caster")
		return 1
	if right_title != "Charger":
		push_error("Expected last spread right page to be Charger")
		return 1
	return 0


func _test_spellbook_paging(tree: SceneTree) -> int:
	var spellbook: Control = SpellBookScene.instantiate()
	tree.root.add_child(spellbook)
	spellbook.configure_loadout(CharacterSpellLoadoutScript.new())
	spellbook.set_selected_spell_id("fireball")
	spellbook.open_book()
	var problem := ""
	if spellbook.page_count() < 2:
		problem = "Expected pre-baked spell pages, got %d" % spellbook.page_count()
	elif spellbook.get_spread_index() != 0:
		problem = "Expected fireball to open on spread 0"
	elif not _spread_has_title(spellbook, "Fireball"):
		problem = "Expected Fireball page visible on the opening spread"
	else:
		spellbook.next_page()
		if spellbook.get_spread_index() != 1:
			problem = "Expected next_page to advance the spellbook to spread 1"
		else:
			spellbook.close_book()
			if spellbook.is_open():
				problem = "Expected spellbook to close"
	tree.root.remove_child(spellbook)
	spellbook.queue_free()
	if problem.is_empty():
		return 0
	push_error(problem)
	return 1


func _test_spellbook_is_browse_only(tree: SceneTree) -> int:
	var spellbook: Control = SpellBookScene.instantiate()
	tree.root.add_child(spellbook)
	var select_btn := _find_select_button(spellbook)
	var bad := select_btn != null or spellbook.has_signal("monster_selected")
	tree.root.remove_child(spellbook)
	spellbook.queue_free()
	if bad:
		push_error("Spellbook must not have the left-click select feature")
		return 1
	return 0


func _test_spellbook_always_has_pages(tree: SceneTree) -> int:
	var spellbook: Control = SpellBookScene.instantiate()
	tree.root.add_child(spellbook)
	spellbook.open_book()
	var prev_btn: Button = spellbook.get_node("Center/BookRoot/OpenBook/PrevButton")
	var next_btn: Button = spellbook.get_node("Center/BookRoot/OpenBook/NextButton")
	var ok: bool = (
		spellbook.page_count() >= 2
		and spellbook.spread_count() >= 2
		and prev_btn.disabled
		and not next_btn.disabled
	)
	tree.root.remove_child(spellbook)
	spellbook.queue_free()
	if not ok:
		push_error("Expected spellbook to ship multiple spreads with end-stopped navigation")
		return 1
	return 0


func _test_player_menu_has_no_spellbook_tab(tree: SceneTree) -> int:
	var menu_scene: PackedScene = load("res://scenes/ui/player_menu.tscn")
	var menu: Control = menu_scene.instantiate()
	tree.root.add_child(menu)
	var tabs: TabBar = menu.get_node("MarginContainer/VBox/TabBar")
	var bad := (
		tabs.tab_count != 3
		or tabs.get_tab_title(1) != "Spells"
		or menu.get_node_or_null("MarginContainer/VBox/CodexPage") != null
		or menu.get_node_or_null("MarginContainer/VBox/SpellsPage") == null
	)
	tree.root.remove_child(menu)
	menu.queue_free()
	if bad:
		push_error("Expected player menu to have Inventory / Spells / Guide tabs")
		return 1
	return 0


func _page_title(book: Control, left: bool) -> String:
	var side := "LeftPage" if left else "RightPage"
	var host: Node = book.get_node(
		"Center/BookRoot/OpenBook/BookBody/Inner/Spread/%s/PageHost" % side
	)
	if host.get_child_count() == 0:
		return ""
	var page: Node = host.get_child(0)
	var label := page.get_node_or_null("Margin/VBox/SpellName") as Label
	if label == null:
		label = page.get_node_or_null("Margin/VBox/TitleLabel") as Label
	if label == null:
		return ""
	return label.text


func _spread_has_title(book: Control, title: String) -> bool:
	return _page_title(book, true) == title or _page_title(book, false) == title


func _find_select_button(root: Node) -> Button:
	if root is Button and str(root.name) == "SelectButton":
		return root
	for child in root.get_children():
		var found := _find_select_button(child)
		if found != null:
			return found
	return null
