extends Control

# ─────────────────────────────────────────────────────────────
#  PlayerStats.gd
#
#  Exibe progresso do jogador: XP, sinais dominados, acertos,
#  dias consecutivos e medalhas conquistadas.
#
#  DADOS MOCKADOS — para integrar com Oracle futuramente:
#  1. Substitua _load_mock_data() por HTTPRequest ao seu backend.
#  2. Mapeamento sugerido para tabelas Oracle:
#       PLAYER          → player_name, total_xp, streak_days
#       PLAYER_PROGRESS → signs_mastered, accuracy_rate
#       PLAYER_BADGES   → Array de badge IDs conquistados
#  3. PlayerData (AutoLoad) deve ser populado após o login
#     e mantido em memória durante a sessão.
# ─────────────────────────────────────────────────────────────

const SCENE_MAIN_MENU = "res://Screens/MainMenu.tscn"

@onready var btn_back         : Button       = $Header/BtnBack
@onready var lbl_name         : Label        = $Content/ProfileCard/VBox/LblName
@onready var lbl_xp           : Label        = $Content/ProfileCard/VBox/LblXP
@onready var progress_bar     : ProgressBar  = $Content/ProfileCard/VBox/ProgressBar
@onready var lbl_next_level   : Label        = $Content/ProfileCard/VBox/LblNextLevel

@onready var lbl_signs        : Label        = $Content/StatsGrid/CardSigns/VBox/LblValue
@onready var lbl_accuracy     : Label        = $Content/StatsGrid/CardAccuracy/VBox/LblValue
@onready var lbl_streak       : Label        = $Content/StatsGrid/CardStreak/VBox/LblValue
@onready var lbl_modules      : Label        = $Content/StatsGrid/CardModules/VBox/LblValue

@onready var badges_container : HBoxContainer = $Content/BadgesSection/BadgesRow

# ─────────────────────────────────────────────────────────────
#  MOCK DATA — substituir por query Oracle via API REST
# ─────────────────────────────────────────────────────────────
var _stats : Dictionary = {}

func _ready() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	_load_mock_data()
	_populate_ui()

func _load_mock_data() -> void:
	# Futuramente: await _fetch_from_oracle(PlayerData.player_id)
	_stats = {
		# PLAYER table
		"player_name"    : "Alexar",
		"total_xp"       : 1290,
		"level"          : 5,
		"xp_to_next"     : 1500,   # XP necessário para o próximo nível
		"streak_days"    : 7,

		# PLAYER_PROGRESS table
		"signs_mastered" : 32,
		"accuracy_rate"  : 88,      # porcentagem (0–100)
		"modules_done"   : 2,
		"modules_total"  : 8,

		# PLAYER_BADGES table (ids → título + emoji)
		"badges": [
			{ "id": 1, "emoji": "🌟", "title": "Primeiro Sinal"   },
			{ "id": 2, "emoji": "🔥", "title": "7 Dias Seguidos"  },
			{ "id": 3, "emoji": "🏆", "title": "Módulo Completo"  },
			{ "id": 4, "emoji": "💎", "title": "90% de Acerto"    },
		],
	}

# ─────────────────────────────────────────────────────────────
#  POPULAÇÃO DA UI
# ─────────────────────────────────────────────────────────────
func _populate_ui() -> void:
	lbl_name.text       = _stats["player_name"]
	lbl_xp.text         = "Nível %d  ·  %d XP" % [_stats["level"], _stats["total_xp"]]
	progress_bar.value  = float(_stats["total_xp"]) / float(_stats["xp_to_next"]) * 100.0
	lbl_next_level.text = "%d / %d XP para o próximo nível" % [_stats["total_xp"], _stats["xp_to_next"]]

	lbl_signs.text    = str(_stats["signs_mastered"])
	lbl_accuracy.text = "%d%%" % _stats["accuracy_rate"]
	lbl_streak.text   = str(_stats["streak_days"])
	lbl_modules.text  = "%d/%d" % [_stats["modules_done"], _stats["modules_total"]]

	_build_badges()

func _build_badges() -> void:
	for child: Node in badges_container.get_children():
		child.queue_free()

	for badge: Dictionary in _stats["badges"]:
		var panel := PanelContainer.new()
		var vbox  := VBoxContainer.new()
		var emoji := Label.new()
		var title := Label.new()

		emoji.text = badge["emoji"]
		emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emoji.add_theme_font_size_override("font_size", 28)

		title.text = badge["title"]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 11)
		title.add_theme_color_override("font_color", Color(0.55, 0.46, 0.40, 1))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD

		vbox.add_child(emoji)
		vbox.add_child(title)
		vbox.add_theme_constant_override("separation", 4)
		panel.add_child(vbox)
		panel.custom_minimum_size = Vector2(76, 80)
		badges_container.add_child(panel)

# ─────────────────────────────────────────────────────────────
#  EVENTOS
# ─────────────────────────────────────────────────────────────
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)
