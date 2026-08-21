extends RefCounted

const CombatHealthScript := preload("res://scripts/combat/combat_health.gd")
const CatalogScript := preload("res://scripts/combat/combat_balance_catalog.gd")
const LoadoutScript := preload("res://scripts/spells/character_spell_loadout.gd")
const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")
const WardShieldScript := preload("res://scripts/spells/ward_shield.gd")
const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")


func run() -> int:
	var failures := 0
	failures += _test_health_pool_reaches_zero()
	failures += _test_fireball_damage_and_dps()
	failures += _test_monster_roster_has_health()
	failures += _test_spell_catalog_loads_authored_defs()
	failures += _test_spell_rows_match_loaded_defs()
	failures += _test_ward_block_matches_fireball()
	failures += _test_shatter_penalty_doubles_next_ward_only()
	failures += _test_shatter_penalty_uses_authored_scale()
	failures += _test_ward_spell_row_exposes_shatter_scale()
	failures += _test_spell_discovery_finds_tres_files()
	failures += _test_monster_kits_nest_abilities()
	return failures


func _test_health_pool_reaches_zero() -> int:
	var health := CombatHealthScript.new()
	health.max_health = 40.0
	health.current_health = 40.0
	health.take_damage(25.0)
	if health.is_dead() or not is_equal_approx(health.current_health, 15.0):
		push_error("Expected health to drop without dying")
		return 1
	health.take_damage(20.0)
	if not health.is_dead():
		push_error("Expected health pool to empty")
		return 1
	return 0


func _test_fireball_damage_and_dps() -> int:
	var spell := SpellDefinitionScript.new()
	spell.id = "fireball"
	spell.display_name = "Fireball"
	spell.effect_id = "fireball"
	spell.damage = FireballProjectileScript.DEFAULT_HIT_DAMAGE
	spell.require_full_charge = true
	spell.cooldown_sec = 0.0
	var interval := spell.get_fire_interval_sec()
	var dps := spell.get_base_damage() / interval
	if spell.get_base_damage() <= 0.0:
		push_error("Expected fireball to have base damage")
		return 1
	if interval < 0.05 or dps <= 0.0:
		push_error("Expected fireball DPS from charge interval")
		return 1
	return 0


func _test_monster_roster_has_health() -> int:
	var rows := CatalogScript.monster_roster()
	if rows.size() < 5:
		push_error("Expected authored monster health rows")
		return 1
	for row in rows:
		if float(row["max_health"]) <= 0.0:
			push_error("Expected every monster roster row to have HP")
			return 1
	return 0


func _test_spell_catalog_loads_authored_defs() -> int:
	var spells: Array = CatalogScript.load_all_spell_defs()
	if spells.size() < 10:
		push_error("Expected authored spell defs, got %s" % spells.size())
		return 1
	var ids: Dictionary = {}
	for item in spells:
		var spell: Resource = item as Resource
		if spell == null or str(spell.get("id")).is_empty():
			push_error("Expected every loaded spell def to have an id")
			return 1
		ids[str(spell.get("id"))] = true
	for required in ["fireball", "ward", "flare"]:
		if not ids.has(required):
			push_error("Expected catalog to include %s" % required)
			return 1
	return 0


func _test_spell_rows_match_loaded_defs() -> int:
	var spells: Array = CatalogScript.load_all_spell_defs()
	var rows := CatalogScript.spell_rows(spells)
	if rows.size() != spells.size() or rows.is_empty():
		push_error(
			"Expected a table row per spell def, got %s rows for %s defs"
			% [rows.size(), spells.size()]
		)
		return 1
	var fireball: Dictionary = {}
	for row in rows:
		if str(row["id"]) == "fireball":
			fireball = row
			break
	if fireball.is_empty():
		push_error("Expected a Fireball row in the spell table")
		return 1
	if float(fireball["damage"]) <= 0.0 or float(fireball["dps"]) <= 0.0:
		push_error("Expected Fireball table row to have damage and DPS")
		return 1
	if str(fireball["path"]).find("fireball.tres") < 0:
		push_error("Expected Fireball row to point at the authored .tres")
		return 1
	var skipped := CatalogScript.spell_rows([Resource.new(), null])
	if not skipped.is_empty():
		push_error("Expected non-spell resources to be skipped in spell rows")
		return 1
	return 0


func _test_ward_block_matches_fireball() -> int:
	if WardShieldScript.DEFAULT_BLOCK_HP <= FireballProjectileScript.DEFAULT_HIT_DAMAGE:
		push_error("Expected player ward max HP to survive one fireball")
		return 1
	var wards := CatalogScript.ward_rows()
	if wards.size() < 2:
		push_error("Expected player/ash and charger ward block rows")
		return 1
	if CatalogScript.ward_break_consequence().find("×2") < 0:
		push_error("Expected ward shatter to mention doubled regen delay")
		return 1
	var report := CatalogScript.format_report()
	if not report.contains("Fireball") or not report.contains("Player max HP"):
		push_error("Expected editor balance report to list player HP and fireball")
		return 1
	return 0


func _test_shatter_penalty_doubles_next_ward_only() -> int:
	var loadout := LoadoutScript.new()
	var ward := SpellDefinitionScript.new()
	ward.id = "ward"
	ward.display_name = "Ward"
	ward.effect_id = "ward"
	ward.cooldown_sec = 0.0
	ward.cast_mode = SpellDefinitionScript.CastMode.CHANNEL
	ward.shatter_regen_scale = 2.0
	ward.regen_delay_sec = 1.0
	loadout.configure([ward])
	loadout.learn_spell("ward", "test")
	loadout.arm_ward_shatter_penalty()
	if not loadout.is_ward_shatter_penalty_armed():
		push_error("Expected shatter penalty to arm")
		return 1
	loadout.start_cooldown("ward")
	if loadout.remaining_cooldown_sec("ward") > 0.05:
		push_error("Expected no cast cooldown after shatter")
		return 1
	var first := float(loadout.get_ward_runtime().apply_shatter_regen_delay(1.0))
	if first < 1.8 or first > 2.2:
		push_error("Expected shatter to double regen delay to 2s, got %s" % first)
		return 1
	if loadout.is_ward_shatter_penalty_armed():
		push_error("Expected shatter penalty to consume after one ward")
		return 1
	var second := float(loadout.get_ward_runtime().apply_shatter_regen_delay(1.0))
	if second < 0.9 or second > 1.1:
		push_error("Expected following ward to use authored regen delay, got %s" % second)
		return 1
	return 0


func _test_shatter_penalty_uses_authored_scale() -> int:
	var loadout := LoadoutScript.new()
	var ward := SpellDefinitionScript.new()
	ward.id = "ward"
	ward.display_name = "Ward"
	ward.effect_id = "ward"
	ward.cooldown_sec = 0.0
	ward.cast_mode = SpellDefinitionScript.CastMode.CHANNEL
	ward.shatter_regen_scale = 3.0
	ward.regen_delay_sec = 1.0
	loadout.configure([ward])
	loadout.learn_spell("ward", "test")
	loadout.arm_ward_shatter_penalty()
	var first := float(loadout.get_ward_runtime().apply_shatter_regen_delay(1.0))
	if first < 2.8 or first > 3.2:
		push_error("Expected authored shatter regen delay ×3, got %s" % first)
		return 1
	return 0


func _test_ward_spell_row_exposes_shatter_scale() -> int:
	var rows := CatalogScript.spell_rows(CatalogScript.load_all_spell_defs())
	var ward_row: Dictionary = {}
	for row in rows:
		if bool(row.get("is_ward", false)):
			ward_row = row
			break
	if ward_row.is_empty():
		push_error("Expected a Ward row in the spell table")
		return 1
	var hp_ok := is_equal_approx(float(ward_row["max_health"]), 40.0)
	var delay_ok := is_equal_approx(float(ward_row["regen_delay_sec"]), 1.0)
	var regen_ok := is_equal_approx(float(ward_row["regen_per_sec"]), 10.0)
	var cd_ok := is_equal_approx(float(ward_row["cooldown_sec"]), 0.0)
	var shatter_ok := is_equal_approx(float(ward_row["shatter_regen_scale"]), 2.0)
	if not (hp_ok and delay_ok and regen_ok and cd_ok and shatter_ok):
		push_error("Expected Ward row: 40 HP, 0 CD, regen 10/s after 1s, shatter regen ×2")
		return 1
	if CatalogScript.format_report().find("regen 10/s") < 0:
		push_error("Expected balance report to list ward regen")
		return 1
	return 0


func _test_spell_discovery_finds_tres_files() -> int:
	var from_path := CatalogScript.load_spell_defs_from_paths(
		PackedStringArray(["res://scenes/spells/fireball/fireball.tres"])
	)
	if from_path.size() != 1:
		push_error("Expected loading a spell .tres path to yield one def")
		return 1
	if str(from_path[0].get("id")) != "fireball":
		push_error("Expected fireball.tres to load as fireball")
		return 1
	return 0


func _test_monster_kits_nest_abilities() -> int:
	var kits := CatalogScript.monster_spell_kits()
	var names: Dictionary = {}
	for kit in kits:
		names[str(kit["name"])] = kit
	var ash_ids: Dictionary = {}
	if names.has("Ash Wretch"):
		for row in names["Ash Wretch"]["spells"]:
			ash_ids[str(row["id"])] = row
	var ice: Dictionary = ash_ids.get("ash_ice", {})
	var report := CatalogScript.format_report()
	var ok := (
		kits.size() >= 4
		and names.has("Ash Wretch")
		and names.has("Ember Wretch")
		and ash_ids.has("ash_ice")
		and ash_ids.has("ash_frost_breath")
		and float(ice.get("damage", 0.0)) > 0.0
		and float(ice.get("cooldown_sec", 0.0)) > 0.0
		and report.find("Monster spells") >= 0
		and report.find("Ice Bolt") >= 0
	)
	if not ok:
		push_error("Expected nested monster spell kits with Ice Bolt stats")
		return 1
	return 0
