extends PanelContainer

# ─────────────────────────────────────────────────────────────
#  ModuleButton.gd
#
#  setup() apenas armazena os dados.
#  _ready() aplica os dados nos nós, pois só aqui os
#  @onready já foram resolvidos.
# ─────────────────────────────────────────────────────────────

signal module_pressed(module_id: int)

@onready var lbl_icon   : Label  = $HBox/LblIcon
@onready var lbl_title  : Label  = $HBox/VBox/LblTitle
@onready var lbl_signs  : Label  = $HBox/VBox/LblSigns
@onready var lbl_status : Label  = $HBox/LblStatus
@onready var btn_area   : Button = $BtnArea

# Dados guardados até o _ready() ser chamado
var _data : Dictionary = {}

func setup(data: Dictionary) -> void:
	_data = data

func _ready() -> void:
	if _data.is_empty():
		return

	lbl_icon.text  = _data["icon"]
	lbl_title.text = _data["title"]
	lbl_signs.text = "%d sinais  ·  +%d XP" % [_data["total_signs"], _data["xp_reward"]]

	match _data["status"]:
		"completed":
			lbl_status.text = "✔"
			lbl_status.add_theme_color_override("font_color", Color(0.46, 0.65, 0.38, 1))
		"available":
			lbl_status.text = "▶"
			lbl_status.add_theme_color_override("font_color", Color(0.70, 0.52, 0.32, 1))
		"locked":
			lbl_status.text = "🔒"
			modulate = Color(1, 1, 1, 0.5)
			btn_area.disabled = true

	btn_area.pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if _data.get("status", "locked") != "locked":
		module_pressed.emit(_data["id"])
