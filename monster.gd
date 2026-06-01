extends CharacterBody2D

const DETECT_RADIUS := 620.0
const ATTACK_RANGE := 46.0
const ATTACK_COOLDOWN := 1.05

@export var monster_name: String = "沉淵爬行者"
@export var level: int = 1
@export var hp: int = 45
@export var max_hp: int = 45
@export var xp_reward: int = 35

var speed := 115.0
var damage := 10
var attack_ready := true


func _ready() -> void:
	add_to_group("monsters")
	_update_label()


func configure(monster_level: int) -> void:
	level = monster_level
	var roll := randi_range(0, 2)
	match roll:
		0:
			monster_name = "沉淵爬行者"
			speed = 110.0
			damage = 8 + level * 2
			max_hp = 42 + level * 12
			$Body.color = Color(0.18, 0.55, 0.28, 1.0)
		1:
			monster_name = "裂口惡犬"
			speed = 150.0
			damage = 11 + level * 2
			max_hp = 34 + level * 10
			$Body.color = Color(0.55, 0.16, 0.12, 1.0)
		_:
			monster_name = "血礁怨靈"
			speed = 88.0
			damage = 14 + level * 3
			max_hp = 56 + level * 15
			$Body.color = Color(0.46, 0.12, 0.62, 1.0)

	hp = max_hp
	xp_reward = 28 + level * 18
	_update_label()


func _physics_process(_delta: float) -> void:
	_update_label()
	if not multiplayer.is_server():
		return

	var target := _find_target()
	if target == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var distance := global_position.distance_to(target.global_position)
	if distance > ATTACK_RANGE:
		velocity = global_position.direction_to(target.global_position) * speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		move_and_slide()
		if attack_ready:
			_attack(target)


func take_damage(amount: int, attacker: Node) -> void:
	if not multiplayer.is_server():
		return

	if hp <= 0:
		return

	hp = max(hp - amount, 0)
	var main := get_tree().current_scene
	if main != null and main.has_method("show_message"):
		main.show_message("%s 受到 %d 點傷害。" % [monster_name, amount])

	if hp == 0:
		_die(attacker)


func _die(attacker: Node) -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("show_message"):
		main.show_message("%s 被擊殺。" % monster_name)

	if attacker != null and attacker.has_method("gain_experience"):
		attacker.gain_experience(xp_reward)

	if randf() <= 0.62:
		var loot := LootManager.generate_loot_from_monster(monster_name)
		if not loot.is_empty() and main != null and main.has_method("spawn_loot"):
			main.spawn_loot(loot, global_position + Vector2(randi_range(-24, 24), randi_range(-24, 24)))

	queue_free()


func _attack(target: Node) -> void:
	attack_ready = false
	if target.has_method("take_damage"):
		target.take_damage(damage, 0, false)

	await get_tree().create_timer(ATTACK_COOLDOWN).timeout
	attack_ready = true


func _find_target() -> Node2D:
	var best_target: Node2D = null
	var best_distance := DETECT_RADIUS

	for player in get_tree().get_nodes_in_group("players"):
		if player.hp <= 0:
			continue

		var distance := global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best_target = player

	return best_target


func _update_label() -> void:
	$NameLabel.text = "%s Lv.%d\n%d/%d" % [monster_name, level, hp, max_hp]
