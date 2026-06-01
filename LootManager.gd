extends Node

const DATABASE_PATH := "res://item_db.json"

var base_items: Array = []
var normal_affixes: Array[String] = []
var legendary_affixes: Array[String] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	load_database()


func load_database() -> void:
	base_items.clear()
	normal_affixes.clear()
	legendary_affixes.clear()

	var file := FileAccess.open(DATABASE_PATH, FileAccess.READ)
	if file == null:
		push_error("找不到掉落資料庫：%s" % DATABASE_PATH)
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("掉落資料庫解析失敗，第 %d 行：%s" % [json.get_error_line(), json.get_error_message()])
		return

	var data: Dictionary = json.data
	for item in data.get("base_items", []):
		base_items.append(item)

	for pool_name in data.get("affix_pools", {}):
		for affix in data["affix_pools"][pool_name]:
			var desc := str(affix.get("desc", ""))
			if desc.begins_with("【傳奇】"):
				legendary_affixes.append(desc)
			else:
				normal_affixes.append(desc)

	print("掉落資料庫載入完成：%d 個基底物品、%d 個一般詞綴、%d 個傳奇詞綴" % [
		base_items.size(),
		normal_affixes.size(),
		legendary_affixes.size(),
	])


func generate_loot_from_monster(_monster_name: String = "") -> Dictionary:
	if base_items.is_empty():
		return {}

	var roll := rng.randf()
	var quality := "普通"
	var affix_count := 0
	var is_legendary := false

	if roll <= 0.01:
		quality = "傳奇"
		affix_count = 4
		is_legendary = true
	elif roll <= 0.10:
		quality = "稀有"
		affix_count = 4
	elif roll <= 0.30:
		quality = "魔法"
		affix_count = 2

	var base_item: Dictionary = base_items[rng.randi_range(0, base_items.size() - 1)]
	var item_affixes: Array[String] = []

	for i in range(affix_count):
		if normal_affixes.is_empty():
			break
		item_affixes.append(normal_affixes[rng.randi_range(0, normal_affixes.size() - 1)])

	if is_legendary and not legendary_affixes.is_empty():
		item_affixes.append(legendary_affixes[rng.randi_range(0, legendary_affixes.size() - 1)])

	return {
		"id": str(base_item.get("id", "")),
		"name": str(base_item.get("name", "未知物品")),
		"type": str(base_item.get("type", "misc")),
		"quality": quality,
		"affixes": item_affixes,
		"base_atk": int(base_item.get("base_atk", 0)),
		"base_def": int(base_item.get("base_def", 0)),
		"base_spd": int(base_item.get("base_spd", 0)),
	}
