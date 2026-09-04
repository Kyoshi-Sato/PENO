extends Control
## Home do HandSign.
##
## Hierarquia da tela, de cima para baixo:
##   1. quem é o usuário e o que ele acumulou (cabeçalho + chips)
##   2. A AÇÃO PRINCIPAL — card "continue de onde parou" com o mascote
##   3. a trilha completa, rolável
##   4. navegação
##
## A versão anterior era um layout de sidebar de desktop (coluna fixa de 320px
## ao lado da área principal) renderizado num canvas retrato de 1080x1920, com
## quatro cards dos quais três estavam `visible = false` por não terem dados.
##
## A lógica de catálogo/progresso é a mesma de antes; o que mudou é a
## apresentação e o fato de XP/ofensiva agora existirem de verdade em Global.

@onready var mascot: TextureRect = %Mascot
@onready var avatar_viewport: SubViewport = $SubViewport

@onready var lbl_hello: Label = %Hello
@onready var chips: HBoxContainer = %Chips
@onready var header_actions: HBoxContainer = %HeaderActions

@onready var hero: PanelContainer = %Hero
@onready var lbl_hero_title: Label = %HeroTitle
@onready var bar_hero: ProgressBar = %HeroProgress
@onready var lbl_hero_progress: Label = %HeroProgressText
@onready var btn_hero_cta: Button = %HeroCta

@onready var btn_see_all: Button = %SeeAll
@onready var path_container: VBoxContainer = %PathContainer
@onready var nav: BottomNav = %Nav
@onready var settings_dialog: SettingsDialog = $SettingsDialog

var _catalog: Array = []
## Lição que o botão principal abre: a primeira desbloqueada e não concluída.
var _next_lesson_id: int = -1

var _chip_xp: StatChip
var _chip_streak: StatChip


func _ready() -> void:
	_build_header()
	_build_chips()

	# A textura do SubViewport é atribuída em runtime em vez de gravada na
	# cena: um ViewportTexture serializado dispara "Path to node is invalid"
	# toda vez que o editor abre a cena fora de contexto.
	mascot.texture = avatar_viewport.get_texture()
	_hide_avatar_backdrop()

	settings_dialog.data_erased.connect(_on_data_erased)

	btn_hero_cta.pressed.connect(_on_practice)
	btn_see_all.pressed.connect(_on_see_all)
	nav.tab_selected.connect(_on_nav)
	nav.active = &"home"

	Motion.attach_press(btn_hero_cta)
	Motion.attach_press(btn_see_all)

	_show_placeholder("Carregando sua trilha…")
	LessonService.fetch_catalog(_on_catalog_loaded, _on_catalog_failed)


# ═══════════════════════════════════════════════════════════
#  CABEÇALHO
# ═══════════════════════════════════════════════════════════

func _build_header() -> void:
	_update_greeting()

	var settings := IconButton.create(HSIcon.Name.SETTINGS, IconButton.Tone.SURFACE)
	settings.pressed.connect(_on_settings)
	header_actions.add_child(settings)


func _update_greeting() -> void:
	lbl_hello.text = "%s · Nível %d" % [_greeting(), Global.get_level()]


## A cena do Libra traz um quad de cenário atrás do personagem. Ele faz
## sentido na tela de lição, onde o avatar ocupa o fundo inteiro; dentro do
## card azul da home ele aparece como um retângulo colorido em volta do
## mascote. Escondemos só nesta viewport — a cena do modelo fica intacta.
func _hide_avatar_backdrop() -> void:
	var avatar: Node = avatar_viewport.get_node_or_null("Avatar")
	if avatar == null:
		return
	for node: Node in avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh is QuadMesh or mesh_node.mesh is PlaneMesh:
			mesh_node.visible = false


func _greeting() -> String:
	var hour: int = Time.get_datetime_dict_from_system().get("hour", 12)
	if hour < 12:
		return "Bom dia"
	if hour < 18:
		return "Boa tarde"
	return "Boa noite"


## Chips de XP e ofensiva. A ofensiva só aparece quando existe: um "0 dias"
## permanente na tela é ruído, não informação.
func _build_chips() -> void:
	for child in chips.get_children():
		child.queue_free()

	_chip_xp = StatChip.create(HSIcon.Name.BOLT, str(Global.get_xp()), "XP total",
		StatChip.Tone.VIOLET)
	chips.add_child(_chip_xp)

	var streak: int = Global.get_streak()
	if streak > 0:
		_chip_streak = StatChip.create(
			HSIcon.Name.FLAME, str(streak),
			"dia seguido" if streak == 1 else "dias seguidos",
			StatChip.Tone.GOLD)
		chips.add_child(_chip_streak)


# ═══════════════════════════════════════════════════════════
#  CATÁLOGO E TRILHA
# ═══════════════════════════════════════════════════════════

func _on_catalog_loaded(catalog: Array) -> void:
	_catalog = catalog
	_resolve_next_lesson()
	_update_hero()
	_build_trail()


func _on_catalog_failed(error: String) -> void:
	_next_lesson_id = -1
	_update_hero()
	_show_placeholder("Não foi possível carregar as lições.\n%s" % error, true)


## Primeira lição desbloqueada ainda não concluída — é o "continue daqui".
## Se tudo estiver concluído, aponta para a última (revisão).
func _resolve_next_lesson() -> void:
	_next_lesson_id = -1
	for entry: Variant in _catalog:
		var lid: int = int((entry as Dictionary).get("id", -1))
		if Global.is_unlocked(lid, _catalog) and not Global.is_completed(lid):
			_next_lesson_id = lid
			return
	if not _catalog.is_empty():
		_next_lesson_id = int((_catalog[_catalog.size() - 1] as Dictionary).get("id", -1))


func _update_hero() -> void:
	if _catalog.is_empty():
		lbl_hero_title.text = "Trilha indisponível"
		lbl_hero_progress.text = "Verifique sua conexão."
		bar_hero.value = 0.0
		btn_hero_cta.disabled = true
		return

	var total: int = _catalog.size()
	var done: int = 0
	for entry: Variant in _catalog:
		if Global.is_completed(int((entry as Dictionary).get("id", -1))):
			done += 1

	lbl_hero_title.text = _lesson_name(_next_lesson_id)
	lbl_hero_progress.text = "%d de %d lições concluídas" % [done, total]
	bar_hero.max_value = float(total)
	Motion.fill_bar(bar_hero, float(done))

	btn_hero_cta.disabled = _next_lesson_id < 0
	btn_hero_cta.text = "Revisar sinais" if done == total else "Continuar lição"


func _lesson_name(lesson_id: int) -> String:
	for entry: Variant in _catalog:
		var e: Dictionary = entry as Dictionary
		if int(e.get("id", -1)) == lesson_id:
			return String(e.get("nome", "Lição %d" % lesson_id))
	return "Lição"


func _build_trail() -> void:
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
		node.pressed.connect(_on_lesson_pressed)
		path_container.add_child(node)
		nodes.append(node)

	Motion.stagger_in(nodes)


func _state_for(lesson_id: int) -> LessonNode.State:
	if Global.is_completed(lesson_id):
		return LessonNode.State.DONE
	if not Global.is_unlocked(lesson_id, _catalog):
		return LessonNode.State.LOCKED
	# Só a próxima lição recebe o destaque de "você está aqui".
	if lesson_id == _next_lesson_id:
		return LessonNode.State.CURRENT
	return LessonNode.State.AVAILABLE


## Mensagem única para carregando / erro, no lugar dos dois Labels soltos
## que a versão anterior criava na mão com font_size diferente em cada caso.
func _show_placeholder(message: String, is_error: bool = false) -> void:
	for child in path_container.get_children():
		child.queue_free()

	var card := PanelContainer.new()
	card.theme_type_variation = &"CardFlat"
	card.mouse_filter = Control.MOUSE_FILTER_PASS
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


# ═══════════════════════════════════════════════════════════
#  AÇÕES
# ═══════════════════════════════════════════════════════════

func _on_lesson_pressed(lesson_id: int) -> void:
	Global.go_to_lesson(lesson_id)


func _on_practice() -> void:
	if _next_lesson_id < 0:
		return
	Global.go_to_lesson(_next_lesson_id)


func _on_see_all() -> void:
	Global.go_to_map()


func _on_settings() -> void:
	# A seleção de câmera, a outra preferência do app, mora na engrenagem da
	# tela de lição: é lá que ela tem efeito visível.
	if !settings_dialog.is_visible():
		settings_dialog.popup_centered()
	else:
		settings_dialog.hide()

## A Home inteira é derivada do progresso, então apagar os dados invalida tudo
## o que está na tela: saudação com o nível, chips de XP e ofensiva, card
## "continue de onde parou" e os cadeados da trilha.
func _on_data_erased() -> void:
	_update_greeting()
	_build_chips()
	_resolve_next_lesson()
	_update_hero()
	_build_trail()


func _on_nav(id: StringName) -> void:
	match id:
		&"home":
			nav.active = &"home"
		&"lessons":
			Global.go_to_map()
		&"practice":
			_on_practice()
		&"progress":
			Global.go_to_progress()
