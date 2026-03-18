extends Node
class_name PlayerData
# ─────────────────────────────────────────────────────────────
#  PlayerData.gd  —  AutoLoad / Singleton
#
#  Como registrar no Godot:
#    Project > Project Settings > Globals (AutoLoad)
#    Nome: PlayerData
#    Caminho: res://autoload/PlayerData.gd
#
#  Futuramente estes valores serão populados via API Oracle
#  logo após o login do usuário.
# ─────────────────────────────────────────────────────────────

# ── Dados do jogador (future: tabela PLAYER no Oracle) ───────
var player_name       : String = "Jogador"
var xp                : int    = 0
var level             : int    = 1
var xp_to_next        : int    = 500
var streak_days       : int    = 0
var id: int = 1

# ── Progresso (future: tabela PLAYER_PROGRESS no Oracle) ─────
var signs_mastered    : int    = 0
var accuracy_rate     : int    = 0   # 0–100
var modules_done      : int    = 0
var modules_total     : int    = 8

# ── Navegação entre cenas ────────────────────────────────────
var current_module_id : int    = -1

# ── Badges (future: tabela PLAYER_BADGES no Oracle) ──────────
var badges            : Array  = []


# ─────────────────────────────────────────────────────────────
#  Quando PlayerData estiver conectado ao Oracle,
#  chame este método após receber a resposta da API:
#
#  func populate_from_api(data: Dictionary) -> void:
#      player_name    = data.get("player_name", "Jogador")
#      xp             = data.get("total_xp", 0)
#      level          = data.get("level", 1)
#      xp_to_next     = data.get("xp_to_next", 500)
#      streak_days    = data.get("streak_days", 0)
#      signs_mastered = data.get("signs_mastered", 0)
#      accuracy_rate  = data.get("accuracy_rate", 0)
#      modules_done   = data.get("modules_done", 0)
#      badges         = data.get("badges", [])
# ─────────────────────────────────────────────────────────────
