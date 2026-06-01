extends Node2D

const PORT := 8910
const DEFAULT_SERVER_IP := "127.0.0.1"
const MAX_LOG_LINES := 6
const MAX_MONSTERS := 8

var peer := ENetMultiplayerPeer.new()
var player_scene := preload("res://player.tscn")
var loot_drop_scene := preload("res://loot_drop.tscn")
var monster_scene := preload("res://monster.tscn")

var selected_class_id := "blood_knight"
var pending_player_classes: Dictionary = {}
var log_lines: Array[String] = []
var inventory_items: Array[Dictionary] = []
var selected_inventory_index := -1
var local_player: Node = null


func _ready() -> void:
	$CanvasLayer/MainMenu/MenuVBox/ClassRow/BloodKnightButton.pressed.connect(_select_blood_knight)
	$CanvasLayer/MainMenu/MenuVBox/ClassRow/AbyssHunterButton.pressed.connect(_select_abyss_hunter)
	$CanvasLayer/MainMenu/MenuVBox/ClassRow/BloodMageButton.pressed.connect(_select_blood_mage)
	$CanvasLayer/MainMenu/MenuVBox/HostButton.pressed.connect(_on_host_pressed)
	$CanvasLayer/MainMenu/MenuVBox/JoinButton.pressed.connect(_on_join_pressed)
	$CanvasLayer/HUD/InventoryPanel.visible = false
	$CanvasLayer/HUD/InventoryPanel/InventoryVBox/InventoryList.item_selected.connect(_on_inventory_item_selected)
	$CanvasLayer/HUD/InventoryPanel/InventoryVBox/EquipButton.pressed.connect(_on_equip_button_pressed)
	$MonsterTimer.timeout.connect(_on_monster_timer_timeout)

	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)

	_update_class_hint()
	_update_inventory_label()
	_update_empty_equipment_view()
	_clear_item_detail()
	show_message("歡迎來到《深淵之血》。選擇角色型態後建立主機或加入遊戲。")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()


func _select_blood_knight() -> void:
	selected_class_id = "blood_knight"
	_update_class_hint()


func _select_abyss_hunter() -> void:
	selected_class_id = "abyss_hunter"
	_update_class_hint()


func _select_blood_mage() -> void:
	selected_class_id = "blood_mage"
	_update_class_hint()


func _on_host_pressed() -> void:
	var error := peer.create_server(PORT, 100)
	if error != OK:
		show_message("建立主機失敗：%s" % error)
		return

	multiplayer.multiplayer_peer = peer
	show_message("主機已建立。深淵開始生成怪物。")
	_hide_connection_buttons()
	var player := add_player(1)
	player.apply_class(selected_class_id)
	$MonsterTimer.start()


func _on_join_pressed() -> void:
	var error := peer.create_client(DEFAULT_SERVER_IP, PORT)
	if error != OK:
		show_message("連線失敗：%s" % error)
		return

	multiplayer.multiplayer_peer = peer
	show_message("正在加入 127.0.0.1 的遊戲。")
	_hide_connection_buttons()


func _on_connected_to_server() -> void:
	rpc_id(1, "request_player_class", selected_class_id)


func _on_player_connected(id: int) -> void:
	show_message("玩家 %d 加入了深淵。" % id)
	if multiplayer.is_server():
		add_player(id)


func _on_player_disconnected(id: int) -> void:
	show_message("玩家 %d 離開了深淵。" % id)
	if multiplayer.is_server() and has_node(str(id)):
		get_node(str(id)).queue_free()


@rpc("any_peer", "call_local", "reliable")
func request_player_class(class_id: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	pending_player_classes[sender_id] = class_id
	if has_node(str(sender_id)):
		get_node(str(sender_id)).apply_class(class_id)


func add_player(id: int) -> Node:
	var player := player_scene.instantiate()
	player.name = str(id)
	player.position = Vector2(randi_range(-260, 260), randi_range(-160, 160))
	add_child(player)

	if pending_player_classes.has(id):
		player.apply_class(str(pending_player_classes[id]))

	return player


func spawn_loot(loot: Dictionary, spawn_position: Vector2) -> void:
	if not multiplayer.is_server():
		return

	var drop := loot_drop_scene.instantiate()
	drop.name = "LootDrop_%d" % Time.get_ticks_usec()
	drop.position = spawn_position
	drop.configure(loot)
	add_child(drop)
	show_message("地上出現了%s「%s」。" % [drop.quality, drop.item_name])


func register_local_player(player: Node) -> void:
	local_player = player
	$CanvasLayer/HUD.visible = true
	update_player_status(player)
	set_inventory_state(player.inventory, player.equipment, player)
	show_message("你已進入戰場。方向鍵移動，空白鍵普攻，Q 使用技能，I 開關背包。")


func update_player_status(player: Node) -> void:
	$CanvasLayer/HUD/StatusPanel/StatusVBox/ClassLabel.text = "型態：%s" % player.role_name
	$CanvasLayer/HUD/StatusPanel/StatusVBox/LevelLabel.text = "等級：%d　經驗：%d / %d" % [
		player.level,
		player.experience,
		player.xp_to_next,
	]
	$CanvasLayer/HUD/StatusPanel/StatusVBox/HealthLabel.text = "生命：%d / %d" % [player.hp, player.max_hp]
	$CanvasLayer/HUD/StatusPanel/StatusVBox/SkillHint.text = "技能：%s（Q）" % player.ability_name
	$CanvasLayer/HUD/StatusPanel/StatusVBox/PowerLabel.text = "攻擊：%d　術力：%d" % [
		player.attack_damage,
		player.ability_damage,
	]


func set_inventory_state(new_inventory: Array, equipment: Dictionary, player: Node) -> void:
	inventory_items.clear()
	for item in new_inventory:
		inventory_items.append((item as Dictionary).duplicate(true))

	_render_inventory_grid()
	update_equipment_view_from_data(equipment, player)
	_update_inventory_label()

	if selected_inventory_index >= inventory_items.size():
		selected_inventory_index = -1

	if selected_inventory_index == -1:
		_clear_item_detail()
	else:
		_show_item_detail(inventory_items[selected_inventory_index])


func update_equipment_view(player: Node) -> void:
	update_equipment_view_from_data(player.equipment, player)


func update_equipment_view_from_data(equipment: Dictionary, player: Node) -> void:
	_set_slot_text("WeaponSlot", "武器", equipment.get("weapon", {}))
	_set_slot_text("ArmorSlot", "護甲", equipment.get("armor", {}))
	_set_slot_text("ShoesSlot", "靴子", equipment.get("shoes", {}))
	_set_slot_text("RingSlot", "戒指", equipment.get("ring", {}))
	_update_paper_doll(equipment, player)


func show_message(message: String) -> void:
	log_lines.append(message)
	while log_lines.size() > MAX_LOG_LINES:
		log_lines.pop_front()

	if has_node("CanvasLayer/HUD/LogPanel/LogLabel"):
		$CanvasLayer/HUD/LogPanel/LogLabel.text = "\n".join(log_lines)
	print(message)


func _on_monster_timer_timeout() -> void:
	if not multiplayer.is_server():
		return

	var monster_count := get_tree().get_nodes_in_group("monsters").size()
	if monster_count >= MAX_MONSTERS:
		return

	spawn_monster()


func spawn_monster() -> void:
	var monster := monster_scene.instantiate()
	monster.name = "Monster_%d" % Time.get_ticks_usec()
	monster.position = Vector2(randi_range(-620, 620), randi_range(-420, 420))
	monster.configure(randi_range(1, 3))
	add_child(monster)
	show_message("%s 從深淵裂縫中爬出。" % monster.monster_name)


func _on_inventory_item_selected(index: int) -> void:
	selected_inventory_index = index
	if index >= 0 and index < inventory_items.size():
		_show_item_detail(inventory_items[index])


func _on_equip_button_pressed() -> void:
	if local_player == null:
		return
	if selected_inventory_index < 0 or selected_inventory_index >= inventory_items.size():
		show_message("請先選擇一件背包裝備。")
		return

	local_player.rpc_id(1, "request_equip_inventory_item", selected_inventory_index)


func _render_inventory_grid() -> void:
	var list: ItemList = $CanvasLayer/HUD/InventoryPanel/InventoryVBox/InventoryList
	list.clear()

	for item in inventory_items:
		var quality := str(item.get("quality", "普通"))
		var item_name := str(item.get("name", "未知物品"))
		var item_type := _type_name(str(item.get("type", "")))
		var index := list.add_item("%s  %s\n%s" % [_quality_icon(quality), item_name, item_type])
		list.set_item_custom_fg_color(index, _quality_color(quality))


func _show_item_detail(item: Dictionary) -> void:
	var lines := []
	lines.append("【%s】%s" % [str(item.get("quality", "普通")), str(item.get("name", "未知物品"))])
	lines.append("部位：%s" % _type_name(str(item.get("type", ""))))

	if int(item.get("base_atk", 0)) != 0:
		lines.append("攻擊 +%d" % int(item.get("base_atk", 0)))
	if int(item.get("base_def", 0)) != 0:
		lines.append("護甲 +%d" % int(item.get("base_def", 0)))
	if int(item.get("base_spd", 0)) != 0:
		lines.append("速度 +%d" % int(item.get("base_spd", 0)))

	var affixes: Array = item.get("affixes", [])
	if not affixes.is_empty():
		lines.append("")
		lines.append("詞綴：")
		for affix in affixes:
			lines.append("・%s" % str(affix))

	$CanvasLayer/HUD/InventoryPanel/InventoryVBox/ItemDetail.text = "\n".join(lines)
	$CanvasLayer/HUD/InventoryPanel/InventoryVBox/EquipButton.disabled = _slot_for_item_type(str(item.get("type", ""))) == ""


func _clear_item_detail() -> void:
	$CanvasLayer/HUD/InventoryPanel/InventoryVBox/ItemDetail.text = "選擇背包中的裝備以查看細節。"
	$CanvasLayer/HUD/InventoryPanel/InventoryVBox/EquipButton.disabled = true


func _hide_connection_buttons() -> void:
	$CanvasLayer/MainMenu.hide()


func _toggle_inventory() -> void:
	var panel := $CanvasLayer/HUD/InventoryPanel
	panel.visible = not panel.visible


func _set_slot_text(node_name: String, label: String, item: Dictionary) -> void:
	var text := "%s：未裝備" % label
	if not item.is_empty():
		text = "%s：【%s】%s" % [
			label,
			str(item.get("quality", "普通")),
			str(item.get("name", "未知物品")),
		]
	$CanvasLayer/HUD/CharacterPanel/CharacterVBox/EquipmentGrid.get_node(node_name).text = text


func _update_paper_doll(equipment: Dictionary, player: Node) -> void:
	var doll := $CanvasLayer/HUD/CharacterPanel/CharacterVBox/PaperDoll
	var body_color := Color(0.55, 0.18, 0.16, 1.0)
	match player.class_id:
		"abyss_hunter":
			body_color = Color(0.13, 0.34, 0.58, 1.0)
		"blood_mage":
			body_color = Color(0.43, 0.12, 0.43, 1.0)

	doll.get_node("Torso").color = body_color
	doll.get_node("LeftArm").color = body_color.darkened(0.12)
	doll.get_node("RightArm").color = body_color.darkened(0.12)
	doll.get_node("Legs").color = body_color.darkened(0.2)

	var weapon: Dictionary = equipment.get("weapon", {})
	var armor: Dictionary = equipment.get("armor", {})
	var shoes: Dictionary = equipment.get("shoes", {})
	var ring: Dictionary = equipment.get("ring", {})
	doll.get_node("WeaponPixel").visible = not weapon.is_empty()
	doll.get_node("ArmorPixel").visible = not armor.is_empty()
	doll.get_node("BootPixel").visible = not shoes.is_empty()
	doll.get_node("RingPixel").visible = not ring.is_empty()


func _update_empty_equipment_view() -> void:
	_set_slot_text("WeaponSlot", "武器", {})
	_set_slot_text("ArmorSlot", "護甲", {})
	_set_slot_text("ShoesSlot", "靴子", {})
	_set_slot_text("RingSlot", "戒指", {})


func _update_inventory_label() -> void:
	$CanvasLayer/HUD/StatusPanel/StatusVBox/InventoryHint.text = "背包：%d 件（I）" % inventory_items.size()


func _update_class_hint() -> void:
	$CanvasLayer/MainMenu/MenuVBox/ClassHint.text = "目前型態：%s" % _role_name(selected_class_id)


func _role_name(class_id: String) -> String:
	match class_id:
		"abyss_hunter":
			return "深淵獵手"
		"blood_mage":
			return "咒血術士"
		_:
			return "血誓騎士"


func _type_name(item_type: String) -> String:
	match item_type:
		"weapon":
			return "武器"
		"armor":
			return "護甲"
		"shoes":
			return "靴子"
		"ring":
			return "戒指"
		_:
			return "雜物"


func _slot_for_item_type(item_type: String) -> String:
	match item_type:
		"weapon", "armor", "shoes", "ring":
			return item_type
		_:
			return ""


func _quality_icon(quality: String) -> String:
	match quality:
		"傳奇":
			return "◆"
		"稀有":
			return "◆"
		"魔法":
			return "◆"
		_:
			return "◇"


func _quality_color(quality: String) -> Color:
	match quality:
		"傳奇":
			return Color(1.0, 0.48, 0.12, 1.0)
		"稀有":
			return Color(1.0, 0.86, 0.16, 1.0)
		"魔法":
			return Color(0.3, 0.62, 1.0, 1.0)
		_:
			return Color(0.9, 0.86, 0.72, 1.0)
