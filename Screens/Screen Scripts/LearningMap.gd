extends Control

# ─────────────────────────────────────────────────────────────
#  LearningMap.gd
#
#  DADOS MOCKADOS — para integrar com Oracle futuramente:
#  1. Substitua _load_mock_data() por HTTPRequest ao seu backend.
#  2. Formato esperado: Array de Dictionaries (ver abaixo).
#  3. PlayerData.current_module_id controla qual módulo está ativo.
# ─────────────────────────────────────────────────────────────

const SCENE_MAIN_MENU = "res://Screens/MainMenu.tscn"
const SCENE_LESSON    = "res://Screens/Lesson.tscn"
const ModuleButton    = preload("res://Screens/Components/ModuleButton.tscn")

@onready var scroll_container : ScrollContainer = $Root/ScrollContainer
@onready var map_container    : VBoxContainer   = $Root/ScrollContainer/MapContainer
@onready var btn_back         : Button          = $Root/Header/HeaderBox/BtnBack
@onready var lbl_title        : Label           = $Root/Header/HeaderBox/LblTitle

var modules_data : Array = []

func _ready() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	lbl_title.text = "Jornada de Aprendizado"
	_load_mock_data()
	_build_map()

# ─────────────────────────────────────────────────────────────
#  MOCK DATA — substituir por query Oracle via API REST
#  Campos esperados por módulo:
#    id          : int    — PK (future: MODULE_ID no Oracle)
#    title       : String — nome exibido
#    icon        : String — emoji
#    total_signs : int    — total de sinais
#    status      : String — "completed" | "available" | "locked"
#    xp_reward   : int    — XP ao concluir (future: XP_REWARD)
# ─────────────────────────────────────────────────────────────
func _load_mock_data() -> void:
	modules_data = [
		{ "id": 1, "title": "Saudações",    "icon": "👋", "total_signs": 4, "status": "completed", "xp_reward": 50 },
		{ "id": 2, "title": "Família",      "icon": "🏠", "total_signs": 4, "status": "completed", "xp_reward": 60 },
		{ "id": 3, "title": "Números",      "icon": "🔢", "total_signs": 4, "status": "available", "xp_reward": 70 },
		{ "id": 4, "title": "Cores",        "icon": "🎨", "total_signs": 3, "status": "locked",    "xp_reward": 60 },
		{ "id": 5, "title": "Animais",      "icon": "🐾", "total_signs": 4, "status": "locked",    "xp_reward": 80 },
		{ "id": 6, "title": "Alimentos",    "icon": "🍎", "total_signs": 4, "status": "locked",    "xp_reward": 80 },
		{ "id": 7, "title": "Escola",       "icon": "📚", "total_signs": 4, "status": "locked",    "xp_reward": 90 },
		{ "id": 8, "title": "Corpo Humano", "icon": "🧍", "total_signs": 4, "status": "locked",    "xp_reward": 90 },
	]

# ─────────────────────────────────────────────────────────────
#  CONSTRUÇÃO DINÂMICA DO MAPA
# ─────────────────────────────────────────────────────────────
func _build_map() -> void:
	for child: Node in map_container.get_children():
		child.queue_free()

	for i: int in modules_data.size():
		var data : Dictionary = modules_data[i]

		# MarginContainer cria o efeito zigue-zague alternando margens
		var wrapper := MarginContainer.new()
		wrapper.size_flags_horizontal = Control.SIZE_FILL

		if i % 2 == 0:
			wrapper.add_theme_constant_override("margin_left",  24)
			wrapper.add_theme_constant_override("margin_right", 100)
		else:
			wrapper.add_theme_constant_override("margin_left",  100)
			wrapper.add_theme_constant_override("margin_right", 24)

		var btn : PanelContainer = ModuleButton.instantiate()
		btn.module_pressed.connect(_on_module_pressed)
		wrapper.add_child(btn)
		btn.setup(data)
		map_container.add_child(wrapper)

		# Conector visual entre nós (exceto após o último)
		if i < modules_data.size() - 1:
			map_container.add_child(_make_connector(data["status"]))

func _make_connector(status: String) -> Control:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(4, 28)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	line.color = Color(0.46, 0.65, 0.38, 1.0) if status == "completed" \
			else Color(0.85, 0.80, 0.74, 0.45)
	return line

# ─────────────────────────────────────────────────────────────
#  EVENTOS
# ─────────────────────────────────────────────────────────────
func _find_module(module_id: int) -> Dictionary:
	for module: Dictionary in modules_data:
		if module["id"] == module_id:
			return module
	return {}

func _on_module_pressed(module_id: int) -> void:
	var module: Dictionary = _find_module(module_id)
	if module.is_empty() or module["status"] == "locked":
		return
	#PlayerData.current_module_id = module_id
	get_tree().change_scene_to_file(SCENE_LESSON)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)
