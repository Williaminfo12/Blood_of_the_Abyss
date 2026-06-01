extends Area2D

@export var item_name: String = ""
@export var quality: String = "普通"
@export var affixes: Array[String] = []

var _last_quality := ""


func _ready() -> void:
	_update_color()
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	if quality != _last_quality:
		_update_color()


func _update_color() -> void:
	_last_quality = quality
	var color := Color.WHITE
	match quality:
		"傳奇":
			color = Color(1.0, 0.45, 0.05)
		"稀有":
			color = Color(1.0, 0.9, 0.05)
		"魔法":
			color = Color(0.1, 0.45, 1.0)
		_:
			color = Color.WHITE

	$ColorRect.color = color
	$NameLabel.text = quality


func configure(loot: Dictionary) -> void:
	item_name = str(loot.get("name", "未知物品"))
	quality = str(loot.get("quality", "普通"))
	affixes.assign(loot.get("affixes", []))
	_update_color()


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return

	if not body.is_in_group("players"):
		return

	if body.has_method("add_loot"):
		body.add_loot({
			"name": item_name,
			"quality": quality,
			"affixes": affixes.duplicate(),
		})

	var main := get_tree().current_scene
	if main != null and main.has_method("show_message"):
		main.show_message("玩家 %s 拾取了%s「%s」。" % [body.name, quality, item_name])
	queue_free()
