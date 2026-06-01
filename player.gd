extends CharacterBody2D

const ATTACK_RADIUS := 150.0
const ATTACK_COOLDOWN := 0.65
const SKILL_COOLDOWN := 3.0

@export var hp: int = 100
@export var max_hp: int = 100
@export var blood_pledge_id: int = 0
@export var class_id: String = "blood_knight"
@export var role_name: String = "血誓騎士"
@export var ability_name: String = "血盾衝擊"
@export var level: int = 1
@export var experience: int = 0
@export var xp_to_next: int = 100

var base_speed := 285.0
var base_max_hp := 100
var base_attack_damage := 20
var base_ability_damage := 36
var speed := 285.0
var attack_damage := 20
var ability_damage := 36
var inventory: Array[Dictionary] = []
var equipment := {
	"weapon": {},
	"armor": {},
	"shoes": {},
	"ring": {},
}
var attack_ready := true
var ability_ready := true
var _applied_class_id := ""


func _enter_tree() -> void:
	var authority_id := str(name).to_int()
	set_multiplayer_authority(authority_id)

	if has_node("ServerSynchronizer"):
		$ServerSynchronizer.set_multiplayer_authority(1)


func _ready() -> void:
	add_to_group("players")
	$AttackArea.visible = false
	_update_hp_label()

	if is_multiplayer_authority():
		$Camera2D.enabled = true
		var main := get_tree().current_scene
		if main != null and main.has_method("register_local_player"):
			main.register_local_player(self)


func _physics_process(_delta: float) -> void:
	if class_id != _applied_class_id:
		_apply_class_values(false)

	_update_hp_label()

	if is_multiplayer_authority():
		var main := get_tree().current_scene
		if main != null and main.has_method("update_player_status"):
			main.update_player_status(self)

	if not is_multiplayer_authority():
		return

	var direction := Vector2.ZERO
	if Input.is_action_pressed("ui_right"):
		direction.x += 1.0
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1.0
	if Input.is_action_pressed("ui_down"):
		direction.y += 1.0
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1.0

	velocity = direction.normalized() * speed
	move_and_slide()

	if Input.is_action_just_pressed("ui_accept") and attack_ready:
		attack_ready = false
		_show_attack_flash(Color(0.8, 0.06, 0.08, 0.18), 0.14)
		rpc_id(1, "request_cast_aoe")
		await get_tree().create_timer(ATTACK_COOLDOWN).timeout
		attack_ready = true

	if Input.is_action_just_pressed("skill_primary") and ability_ready:
		ability_ready = false
		_show_attack_flash(Color(0.42, 0.04, 0.74, 0.24), 0.22)
		rpc_id(1, "request_cast_skill")
		await get_tree().create_timer(SKILL_COOLDOWN).timeout
		ability_ready = true


func apply_class(new_class_id: String) -> void:
	class_id = new_class_id
	_apply_class_values(true)
	_sync_inventory_state()


func _apply_class_values(reset_health: bool) -> void:
	_applied_class_id = class_id

	match class_id:
		"abyss_hunter":
			role_name = "深淵獵手"
			ability_name = "裂隙箭雨"
			base_speed = 340.0
			base_max_hp = 82
			base_attack_damage = 18
			base_ability_damage = 44
			$ColorRect.color = Color(0.05, 0.45, 0.95, 1.0)
		"blood_mage":
			role_name = "咒血術士"
			ability_name = "血咒爆裂"
			base_speed = 265.0
			base_max_hp = 88
			base_attack_damage = 16
			base_ability_damage = 58
			$ColorRect.color = Color(0.65, 0.08, 0.55, 1.0)
		_:
			class_id = "blood_knight"
			role_name = "血誓騎士"
			ability_name = "血盾衝擊"
			base_speed = 285.0
			base_max_hp = 120
			base_attack_damage = 24
			base_ability_damage = 36
			$ColorRect.color = Color(0.85, 0.05, 0.05, 1.0)

	_recalculate_stats()
	if reset_health:
		hp = max_hp
	_update_hp_label()


@rpc("any_peer", "call_local", "reliable")
func request_cast_aoe() -> void:
	if not multiplayer.is_server():
		return

	var hit_count := _damage_nearby_targets(ATTACK_RADIUS, attack_damage)
	_announce("玩家 %s 施放普攻，命中 %d 個目標。" % [name, hit_count])


@rpc("any_peer", "call_local", "reliable")
func request_cast_skill() -> void:
	if not multiplayer.is_server():
		return

	match class_id:
		"abyss_hunter":
			var hit_count := _damage_nearby_targets(230.0, ability_damage)
			_announce("深淵獵手 %s 施放裂隙箭雨，命中 %d 個目標。" % [name, hit_count])
		"blood_mage":
			var hit_count := _damage_nearby_targets(190.0, ability_damage)
			take_damage(8, blood_pledge_id, false)
			_announce("咒血術士 %s 以生命引爆血咒，命中 %d 個目標。" % [name, hit_count])
		_:
			var hit_count := _damage_nearby_targets(165.0, ability_damage)
			hp = min(hp + 12, max_hp)
			_announce("血誓騎士 %s 發動血盾衝擊，命中 %d 個目標並回復生命。" % [name, hit_count])


func _damage_nearby_targets(radius: float, amount: int) -> int:
	var hit_count := 0
	for monster in get_tree().get_nodes_in_group("monsters"):
		if global_position.distance_to(monster.global_position) <= radius:
			hit_count += 1
			monster.take_damage(amount, self)

	for other_player in get_tree().get_nodes_in_group("players"):
		if other_player == self:
			continue
		if global_position.distance_to(other_player.global_position) <= radius:
			if blood_pledge_id == 0 or blood_pledge_id != other_player.blood_pledge_id:
				hit_count += 1
				other_player.take_damage(amount, blood_pledge_id, true)

	return hit_count


func take_damage(amount: int, attacker_pledge_id: int, is_aoe: bool) -> void:
	if not multiplayer.is_server():
		return

	if hp <= 0:
		return

	if is_aoe and blood_pledge_id != 0 and blood_pledge_id == attacker_pledge_id:
		return

	hp = max(hp - amount, 0)
	_announce("玩家 %s 受到 %d 點傷害。" % [name, amount])

	if hp == 0:
		DeathManager.handle_player_death(self)


func gain_experience(amount: int) -> void:
	if not multiplayer.is_server():
		return

	experience += amount
	_announce("玩家 %s 獲得 %d 經驗。" % [name, amount])

	while experience >= xp_to_next:
		experience -= xp_to_next
		level += 1
		xp_to_next = int(xp_to_next * 1.35) + 30
		base_max_hp += 12
		base_attack_damage += 3
		base_ability_damage += 4
		_recalculate_stats()
		hp = max_hp
		_announce("玩家 %s 升到 %d 級！" % [name, level])


func add_loot(loot: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	inventory.append(loot.duplicate(true))
	_announce("拾取：%s 已放入背包。" % str(loot.get("name", "未知物品")))
	_sync_inventory_state()


@rpc("any_peer", "call_local", "reliable")
func request_equip_inventory_item(index: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != get_multiplayer_authority():
		return

	if index < 0 or index >= inventory.size():
		return

	var item := inventory[index]
	var slot := _slot_for_item_type(str(item.get("type", "")))
	if slot == "":
		_announce("這件物品無法裝備。")
		return

	inventory.remove_at(index)
	var old_item: Dictionary = equipment.get(slot, {})
	if not old_item.is_empty():
		inventory.append(old_item.duplicate(true))

	equipment[slot] = item.duplicate(true)
	_recalculate_stats()
	_announce("已裝備：%s" % str(item.get("name", "未知物品")))
	_sync_inventory_state()


@rpc("any_peer", "call_local", "reliable")
func receive_inventory_state(new_inventory: Array, new_equipment: Dictionary) -> void:
	if not is_multiplayer_authority():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != 1:
		return

	inventory.assign(new_inventory)
	equipment = new_equipment.duplicate(true)
	_recalculate_stats()

	var main := get_tree().current_scene
	if main != null and main.has_method("set_inventory_state"):
		main.set_inventory_state(inventory, equipment, self)


func _sync_inventory_state() -> void:
	if not multiplayer.is_server():
		return

	if get_multiplayer_authority() == 1:
		receive_inventory_state(inventory, equipment)
	else:
		rpc_id(get_multiplayer_authority(), "receive_inventory_state", inventory, equipment)


func _slot_for_item_type(item_type: String) -> String:
	match item_type:
		"weapon":
			return "weapon"
		"armor":
			return "armor"
		"shoes":
			return "shoes"
		"ring":
			return "ring"
		_:
			return ""


func _recalculate_stats() -> void:
	var old_max_hp := max_hp
	max_hp = base_max_hp
	speed = base_speed
	attack_damage = base_attack_damage
	ability_damage = base_ability_damage

	var weapon: Dictionary = equipment.get("weapon", {})
	var armor: Dictionary = equipment.get("armor", {})
	var shoes: Dictionary = equipment.get("shoes", {})
	var ring: Dictionary = equipment.get("ring", {})

	attack_damage += int(weapon.get("base_atk", 0))
	ability_damage += int(weapon.get("base_atk", 0)) / 2
	max_hp += int(armor.get("base_def", 0)) * 4
	speed += float(shoes.get("base_spd", 0)) * 18.0
	max_hp += int(ring.get("base_spd", 0)) * 2

	if old_max_hp > 0 and hp > 0:
		hp = min(hp + max_hp - old_max_hp, max_hp)


func _show_attack_flash(color: Color, duration: float) -> void:
	$AttackArea.color = color
	$AttackArea.visible = true
	await get_tree().create_timer(duration).timeout
	$AttackArea.visible = false


func _announce(message: String) -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("show_message"):
		main.show_message(message)


func _update_hp_label() -> void:
	$HPLabel.text = "生命 %d/%d" % [hp, max_hp]
