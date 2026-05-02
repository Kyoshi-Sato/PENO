extends Control

# MainMenu.gd

# ── Ajuste os caminhos abaixo conforme a sua árvore de nós ───
# Se um nó não for encontrado, o jogo imprime um aviso mas não trava.

@onready var btn_aprender : Button = $Layout/BtnAprender
@onready var btn_stats    : Button = $Layout/BtnStats

const SCENE_MAP   = "res://Screens/LearningMap.tscn"
const SCENE_STATS = "res://Screens/PlayerStats.tscn"

func _ready() -> void:
	# Verifica se os botões foram encontrados antes de conectar
	if btn_aprender:
		btn_aprender.pressed.connect(_on_aprender_pressed)
	else:
		push_error("MainMenu: BtnAprender não encontrado em $Layout/BtnAprender")

	if btn_stats:
		btn_stats.pressed.connect(_on_stats_pressed)
	else:
		push_error("MainMenu: BtnStats não encontrado em $Layout/BtnStats")


func _on_aprender_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_MAP)


func _on_stats_pressed() -> void:
	get_tree().change_scene_to_file(SCENE_STATS)
