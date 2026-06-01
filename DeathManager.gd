extends Node

enum Alignment { BLUE, WHITE, RED }

const RED_NAME_DROP_SLOTS := 5
const RED_NAME_DROP_CHANCE := 0.50
const DROP_SCATTER_RADIUS := 56.0

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func handle_player_death(player_node: Node2D) -> void:
	if not multiplayer.is_server():
		return

	_announce("玩家 %s 死亡，開始結算死亡懲罰。" % player_node.name)

	var alignment := Alignment.RED
	var exp_penalty := 0.0

	match alignment:
		Alignment.BLUE:
			exp_penalty = 0.05
			_announce("藍名死亡：扣除 %.0f%% 經驗。" % (exp_penalty * 100.0))
		Alignment.WHITE:
			exp_penalty = 0.05
			_announce("白名死亡：扣除 %.0f%% 經驗。" % (exp_penalty * 100.0))
		Alignment.RED:
			exp_penalty = 0.10
			_announce("紅名死亡：扣除 %.0f%% 經驗，身上裝備逐件擲骰噴落。" % (exp_penalty * 100.0))
			for i in range(RED_NAME_DROP_SLOTS):
				if rng.randf() <= RED_NAME_DROP_CHANCE:
					_spawn_death_loot(player_node.global_position)

	player_node.queue_free()


func _spawn_death_loot(origin: Vector2) -> void:
	var loot := LootManager.generate_loot_from_monster("fallen_player")
	if loot.is_empty():
		return

	var main := get_tree().current_scene
	if main == null or not main.has_method("spawn_loot"):
		push_warning("Current scene cannot spawn loot.")
		return

	var offset := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(12.0, DROP_SCATTER_RADIUS)
	main.spawn_loot(loot, origin + offset)


func _announce(message: String) -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("show_message"):
		main.show_message(message)
	else:
		print(message)
