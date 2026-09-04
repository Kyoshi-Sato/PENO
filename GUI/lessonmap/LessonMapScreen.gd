extends Control
## Trilha completa de lições.
##
## Usa exatamente o mesmo `LessonNode` da Home. Antes as duas telas tinham
## cópias quase idênticas de `_build_path`/`_build_row`, cada uma com um
## `font_size` diferente (48 aqui, 32 lá) e uma regra própria de rótulo — a
## mesma lição aparecia de dois jeitos dependendo de onde você a visse.

@onready var header_slot: HBoxContainer = %Header
@onready var path_container: VBoxContainer = %PathContainer
@onready var summary_card: PanelContainer = %SummaryCard
@onready var lbl_percent: Label = %PercentLabel
@onready var bar: ProgressBar = %Bar
@onready var lbl_caption: Label = %CaptionLabel
@onready var nav: BottomNav = %Nav

var _catalog: Array = []
var _next_lesson_id: int = -1


func _ready() -> void:
	var header := AppHeader.new()
	header.title = "Trilha de aprendizado"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.back_pressed.connect(_on_back)
	header_slot.add_child(header)

	nav.tab_selected.connect(_on_nav)
	nav.active = &"lessons"

	summary_card.visible = false
	_show_placeholder("Carregando lições…")
	LessonService.fetch_catalog(_on_catalog_loaded, _on_catalog_failed)


func _on_catalog_loaded(catalog: Array) -> void:
	_catalog = catalog
	_resolve_next_lesson()
	_update_summary()
	_build_path()


func _on_catalog_failed(error: String) -> void:
	summary_card.visible = false
	_show_placeholder("Não foi possível carregar as lições.\n%s" % error, true)


func _resolve_next_lesson() -> void:
	_next_lesson_id = -1
	for entry: Variant in _catalog:
		var lid: int = int((entry as Dictionary).get("id", -1))
		if Global.is_unlocked(lid, _catalog) and not Global.is_completed(lid):
			_next_lesson_id = lid
			return


func _update_summary() -> void:
	if _catalog.is_empty():
		summary_card.visible = false
		return

	summary_card.visible = true
	var total: int = _catalog.size()
	var done: int = 0
	for entry: Variant in _catalog:
		if Global.is_completed(int((entry as Dictionary).get("id", -1))):
			done += 1

	var pct: int = int(round(float(done) / float(total) * 100.0))
	lbl_percent.text = "%d%%" % pct
	lbl_percent.add_theme_color_override("font_color",
		DS.SUCCESS_INK if done == total else DS.ACCENT_INK)
	bar.max_value = float(total)
	bar.value = 0.0
	Motion.fill_bar(bar, float(done))
	lbl_caption.text = "%d de %d lições concluídas" % [done, total]


func _build_path() -> void:
	for child in path_container.get_children():
		child.queue_free()

	var nodes: Array = []
	for i in range(_catalog.size()):
		var entry: Dictionary = _catalog[i] as Dictionary
		var lid: int = int(entry.get("id", -1))
		var node := LessonNode.create(
			lid,
			String(entry.get("nome", "Lição %d" % lid)),
			_state_for(lid),
			i,
			Global.get_stars(lid))
		node.is_first = i == 0
		node.is_last = i == _catalog.size() - 1
		node.pressed.connect(_on_node_pressed)
		path_container.add_child(node)
		nodes.append(node)

	Motion.stagger_in(nodes)


func _state_for(lesson_id: int) -> LessonNode.State:
	if Global.is_completed(lesson_id):
		return LessonNode.State.DONE
	if not Global.is_unlocked(lesson_id, _catalog):
		return LessonNode.State.LOCKED
	if lesson_id == _next_lesson_id:
		return LessonNode.State.CURRENT
	return LessonNode.State.AVAILABLE


func _show_placeholder(message: String, is_error: bool = false) -> void:
	for child in path_container.get_children():
		child.queue_free()

	var card := PanelContainer.new()
	card.theme_type_variation = &"CardFlat"
	path_container.add_child(card)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", DS.SPACE_SM)
	card.add_child(box)

	var glyph := HSIcon.new()
	glyph.icon = HSIcon.Name.CROSS if is_error else HSIcon.Name.SPARKLE
	glyph.color = DS.DANGER_INK if is_error else DS.PRIMARY_TINT_STRONG
	glyph.custom_minimum_size = Vector2(80, 80)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(glyph)

	var lbl := Label.new()
	lbl.theme_type_variation = &"BodySm"
	lbl.text = message
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lbl)


func _on_node_pressed(lesson_id: int) -> void:
	Global.go_to_lesson(lesson_id)


func _on_back() -> void:
	Global.go_to_main_scene()


func _on_nav(id: StringName) -> void:
	match id:
		&"home":
			Global.go_to_main_scene()
		&"lessons":
			nav.active = &"lessons"
		&"practice":
			if _next_lesson_id >= 0:
				Global.go_to_lesson(_next_lesson_id)
		&"progress":
			Global.go_to_progress()
