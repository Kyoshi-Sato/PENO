extends Control
## Main Menu (dashboard).
##
## Layout:
##   ┌───────────────┬──────────────────────────────────┐
##   │  Sidebar      │  TopBar (módulo + streak/xp)     │
##   │   - Avatar    │  ──────────────────────────────  │
##   │   - Progresso │                                  │
##   │   - (oculto)  │  LessonMap (embutido)            │
##   │               │                                  │
##   │               │  ──────────────────────────────  │
##   │               │  BottomNav (só visual)           │
##   └───────────────┴──────────────────────────────────┘
##
## Reutiliza:
##   - Avatar 3D (SubViewport com Libra que já existia no Main)
##   - Global (is_completed, get_stars, go_to_lesson)
##   - LessonService (fetch_catalog) — mesma lógica do LessonMapScreen
##
## Não inventa sistemas novos: campos sem dados ficam ocultos.

# ---------- SIDEBAR ----------
@onready var avatar_viewport: SubViewport = $SubViewport
@onready var lbl_user_name: Label = %UserNameLabel
@onready var lbl_user_level: Label = %UserLevelLabel
@onready var card_progresso: PanelContainer = %CardProgresso
@onready var bar_evolucao: ProgressBar = %EvolucaoBar
@onready var lbl_evolucao_pct: Label = %EvolucaoPct
@onready var lbl_evolucao_text: Label = %EvolucaoText
@onready var card_estatisticas: PanelContainer = %CardEstatisticas
@onready var card_recompensa: PanelContainer = %CardRecompensa

# ---------- TOPBAR ----------
@onready var lbl_modulo: Label = %ModuloLabel
@onready var lbl_modulo_subtitle: Label = %ModuloSubtitle
@onready var btn_ver_modulos: Button = %VerModulosButton
@onready var indicator_streak: Control = %StreakIndicator
@onready var indicator_xp: Control = %XPIndicator
@onready var btn_settings: Button = %SettingsButton

# ---------- LESSON MAP (embutido) ----------
@onready var path_container: VBoxContainer = %PathContainer

# ---------- BOTTOM NAV ----------
@onready var btn_nav_home: Button = %NavHome
@onready var btn_nav_lessons: Button = %NavLessons
@onready var btn_nav_practice: Button = %NavPractice
@onready var btn_nav_progress: Button = %NavProgress
@onready var btn_nav_profile: Button = %NavProfile

# ---------- SIGNALS (bottom nav — preparados, sem implementação) ----------
signal nav_home_pressed
signal nav_lessons_pressed
signal nav_practice_pressed
signal nav_progress_pressed
signal nav_profile_pressed

# Tamanho do nó de lição no mapa
const NODE_SIZE := Vector2(160, 160)

var _catalog: Array = []


func _ready() -> void:
	# Sidebar — só o que dá pra preencher
	_setup_sidebar_visibility()
	_setup_topbar_visibility()
	_setup_bottom_nav()

	btn_settings.pressed.connect(_on_settings_pressed)
	btn_ver_modulos.pressed.connect(_on_ver_modulos_pressed)

	# Carrega o catálogo (mesma lógica do LessonMapScreen original)
	_show_loading()
	LessonService.fetch_catalog(_on_catalog_loaded, _on_catalog_failed)


# ═══════════════════════════════════════════════════════════
#  SIDEBAR
# ═══════════════════════════════════════════════════════════

func _setup_sidebar_visibility() -> void:
	# Nome / nível: dados não existem em Global → oculto
	# TODO: ativar quando houver perfil de usuário
	lbl_user_name.visible = false
	lbl_user_level.visible = false

	# Card de progresso: existe — calculado a partir de Global._progress
	card_progresso.visible = true

	# Estatísticas: dados não existem (sinais aprendidos, precisão, tempo) → oculto
	# TODO: ativar quando houver tracking detalhado
	card_estatisticas.visible = false

	# Próxima recompensa: dados não existem → oculto
	# TODO: ativar quando houver sistema de XP/recompensas
	card_recompensa.visible = false


## Atualiza a barra de evolução com base em quantas lições do catálogo
## estão marcadas como completed em Global.
func _update_evolution_card() -> void:
	if _catalog.is_empty():
		bar_evolucao.value = 0
		lbl_evolucao_pct.text = "0%"
		lbl_evolucao_text.text = "0 / 0 lições concluídas"
		return

	var total: int = _catalog.size()
	var done: int = 0
	for entry: Variant in _catalog:
		var lid: int = int(entry.get("id", -1))
		if Global.is_completed(lid):
			done += 1

	var pct: float = (float(done) / float(total)) * 100.0
	bar_evolucao.max_value = float(total)
	bar_evolucao.value = float(done)
	lbl_evolucao_pct.text = "%d%%" % int(round(pct))
	lbl_evolucao_text.text = "%d / %d lições concluídas" % [done, total]


# ═══════════════════════════════════════════════════════════
#  TOPBAR
# ═══════════════════════════════════════════════════════════

func _setup_topbar_visibility() -> void:
	# Streak / XP: dados não existem → oculto
	# TODO: ativar quando houver sistema de streak/XP
	indicator_streak.visible = false
	indicator_xp.visible = false


func _on_ver_modulos_pressed() -> void:
	# TODO: abrir tela de seleção de módulos quando existir mais de um.
	# Por enquanto, sem ação — só preparado.
	pass


func _on_settings_pressed() -> void:
	# TODO: abrir tela de configurações.
	pass


# ═══════════════════════════════════════════════════════════
#  BOTTOM NAV (só visual + signals)
# ═══════════════════════════════════════════════════════════

func _setup_bottom_nav() -> void:
	btn_nav_home.pressed.connect(func() -> void: nav_home_pressed.emit())
	btn_nav_lessons.pressed.connect(func() -> void: nav_lessons_pressed.emit())
	btn_nav_practice.pressed.connect(func() -> void: nav_practice_pressed.emit())
	btn_nav_progress.pressed.connect(func() -> void: nav_progress_pressed.emit())
	btn_nav_profile.pressed.connect(func() -> void: nav_profile_pressed.emit())


# ═══════════════════════════════════════════════════════════
#  LESSON MAP EMBUTIDO
#  (lógica reaproveitada do LessonMapScreen.gd original)
# ═══════════════════════════════════════════════════════════

func _show_loading() -> void:
	for child in path_container.get_children():
		child.queue_free()
	var lbl := Label.new()
	lbl.text = "Carregando..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 32)
	path_container.add_child(lbl)


func _on_catalog_loaded(catalog: Array) -> void:
	_catalog = catalog
	_update_evolution_card()
	_update_module_label()
	_build_path(catalog)


func _on_catalog_failed(error: String) -> void:
	for child in path_container.get_children():
		child.queue_free()
	var lbl := Label.new()
	lbl.text = "Falha ao carregar lições:\n%s" % error
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	path_container.add_child(lbl)


func _update_module_label() -> void:
	if _catalog.is_empty():
		lbl_modulo.text = "Mapa de aprendizado"
		lbl_modulo_subtitle.text = ""
		return
	# Heurística: pega o nome da primeira lição como "nome do módulo"
	# se ela tiver um nome consistente. Se não, mantém genérico.
	# TODO: trocar por um campo `modulo` quando a API expor.
	var first_name: String = String(_catalog[0].get("nome_exercicio", ""))
	lbl_modulo.text = "Mapa de aprendizado"
	lbl_modulo_subtitle.text = first_name if not first_name.is_empty() else ""


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
	btn.add_theme_font_size_override("font_size", 32)

	var unlocked := Global.is_unlocked(lesson_id, catalog)
	var completed := Global.is_completed(lesson_id)
	var stars := Global.get_stars(lesson_id)

	if not unlocked:
		btn.disabled = true
		btn.text = "🔒\n%s" % nome
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
