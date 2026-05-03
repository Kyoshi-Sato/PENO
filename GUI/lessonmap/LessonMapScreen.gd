extends Control
## Mapa de lições: consulta o catálogo na API e exibe um botão por lição.
## O estado de unlock/complete/stars é mantido localmente pelo Global.

@onready var path_container: VBoxContainer = %PathContainer
@onready var btn_back: Button = %BackButton
@onready var lbl_title: Label = %TitleLabel

const NODE_SIZE := Vector2(120, 120)


func _ready() -> void:
	btn_back.pressed.connect(_on_back)
	lbl_title.text = "Continuar aprendendo"

	_show_loading()
	LessonService.fetch_catalog(_on_catalog_loaded, _on_catalog_failed)


func _show_loading() -> void:
	for child in path_container.get_children():
		child.queue_free()
	var lbl := Label.new()
	lbl.text = "Carregando..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 48)
	path_container.add_child(lbl)


func _on_catalog_loaded(catalog: Array) -> void:
	_build_path(catalog)


func _on_catalog_failed(error: String) -> void:
	for child in path_container.get_children():
		child.queue_free()
	var lbl := Label.new()
	lbl.text = "Falha ao carregar lições:\n%s" % error
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 48)
	path_container.add_child(lbl)


func _build_path(catalog: Array) -> void:
	for child in path_container.get_children():
		child.queue_free()
	
	for i in range(catalog.size()):
		var entry: Dictionary = catalog[i]
		var row := _build_row(entry, i, catalog)
		path_container.add_child(row)


func _build_row(entry: Dictionary, index: int, catalog: Array) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)

	# Indentação alternada para dar a sensação de "caminho"
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(80 + (index % 3) * 60, 0)
	row.add_child(spacer)

	var lesson_id := int(entry.get("id", -1))
	var nome := String(entry.get("nome_exercicio", "Lição %d" % lesson_id))

	var btn := Button.new()
	btn.custom_minimum_size = NODE_SIZE
	btn.add_theme_font_size_override("font_size", 48)

	var unlocked := Global.is_unlocked(lesson_id, catalog)
	var completed := Global.is_completed(lesson_id)
	var stars := Global.get_stars(lesson_id)

	if not unlocked:
		btn.disabled = true
		btn.text = "🔒"
	elif completed:
		btn.text = "★".repeat(maxi(stars, 1)) + "\n" + nome
	else:
		btn.text = nome

	if unlocked:
		btn.pressed.connect(_on_node_pressed.bind(lesson_id))

	row.add_child(btn)
	return row


func _on_node_pressed(lesson_id: int) -> void:
	Global.go_to_lesson(lesson_id)


func _on_back() -> void:
	Global.go_to_main_scene()
