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

@onready var avatar_viewport: SubViewport = $Palco/SubViewport
@onready var avatar: AvatarFace = $Palco/SubViewport/Avatar
@onready var toque: Control = %Toque
@onready var lbl_fala: Label = %FalaLabel

@onready var lbl_hello: Label = %Hello
@onready var chips: HBoxContainer = %Chips
@onready var header_actions: HBoxContainer = %HeaderActions

@onready var hero: PanelContainer = %Hero
@onready var lbl_hero_title: Label = %HeroTitle
@onready var bar_hero: ProgressBar = %HeroProgress
@onready var lbl_hero_progress: Label = %HeroProgressText
@onready var btn_hero_cta: Button = %HeroCta

@onready var nav: BottomNav = %Nav
@onready var settings_dialog: SettingsDialog = $SettingsDialog

var _catalog: Array = []
## Lição que o botão principal abre: a primeira desbloqueada e não concluída.
var _next_lesson_id: int = -1
## Marca o catálogo como indisponível — muda o que ela fala e a cara dela.
var _catalog_falhou: bool = false
## Geração do toque, para um toque novo cancelar o retorno do anterior.
var _geracao_toque: int = 0

var _chip_xp: StatChip
var _chip_streak: StatChip


func _ready() -> void:
	_build_header()
	_build_chips()

	_hide_avatar_backdrop()

	settings_dialog.data_erased.connect(_on_data_erased)
	# A sincronização do boot pode trazer um progresso do servidor (correção
	# do admin) depois que a Home já se desenhou — o redesenho é o mesmo.
	Global.progress_replaced.connect(_on_data_erased)

	btn_hero_cta.pressed.connect(_on_practice)
	toque.gui_input.connect(_on_toque)
	nav.tab_selected.connect(_on_nav)
	nav.active = &"home"

	Motion.attach_press(btn_hero_cta)

	_atualiza_fala()
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


## A cena do Libra traz um quad de cenário atrás do personagem. Aqui o fundo
## é a cor lisa da Home, e o quad apareceria como um retângulo colorido em
## volta dela. Escondemos só nesta viewport — a cena do modelo fica intacta.
func _hide_avatar_backdrop() -> void:
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
	_atualiza_fala()


func _on_catalog_failed(error: String) -> void:
	push_warning("Catálogo indisponível: %s" % error)
	_next_lesson_id = -1
	_catalog_falhou = true
	_update_hero()
	_atualiza_fala()


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


# ═══════════════════════════════════════════════════════════
#  A BONECA
# ═══════════════════════════════════════════════════════════
##
## A Home não tem mais trilha: quem ocupa a tela é ela. Para não virar um
## pôster, ela precisa de duas coisas — dizer algo que só faça sentido HOJE,
## para esta pessoa, e responder quando é tocada. Ambas saem de dados que a
## tela já tinha (hora, ofensiva, progresso); nada aqui é decorativo.

## Reações ao toque. Sorteadas, e cada uma traz a própria expressão: a frase
## sozinha soaria robótica se a cara dela não mudasse junto.
const REACOES: Array[Dictionary] = [
	{"texto": "Oi! Tava te esperando.", "cara": &"alegria"},
	{"texto": "Pode contar comigo, tá?", "cara": &"contente"},
	{"texto": "Quer treinar agora?", "cara": &"expectativa"},
	{"texto": "Olha minhas mãos com atenção quando eu fizer o sinal.", "cara": &"contente"},
	{"texto": "Sem pressa. A gente repete quantas vezes precisar.", "cara": &"contente"},
]

## Quanto tempo a reação ao toque fica na tela antes de voltar à fala do dia.
const DURACAO_DA_REACAO := 3.2


## Frase e expressão do momento. A ordem dos casos é de prioridade: o que é
## excepcional (erro, primeira vez, trilha inteira concluída) fala mais alto
## que a saudação de rotina.
func _atualiza_fala() -> void:
	_geracao_toque += 1   # cancela o retorno de um toque em andamento

	if _catalog_falhou:
		_diz("Não consegui carregar as lições. Dá uma olhada na conexão?", &"pena")
		return

	if _catalog.is_empty():
		_diz("Só um instante, tô buscando as lições…", &"expectativa")
		return

	var total: int = _catalog.size()
	var feitas: int = 0
	for entry: Variant in _catalog:
		if Global.is_completed(int((entry as Dictionary).get("id", -1))):
			feitas += 1

	if feitas == 0:
		_diz("Vamos começar? Eu faço devagar pra você acompanhar.", &"expectativa")
		return

	if feitas == total:
		_diz("Você já aprendeu todos. Bora revisar comigo?", &"alegria")
		return

	var ofensiva: int = Global.get_streak()
	if ofensiva >= 2:
		_diz("%d dias seguidos. Tô orgulhosa de você." % ofensiva, &"alegria")
		return

	_diz("%s! Continua de onde a gente parou?" % _greeting(), &"contente")


func _diz(texto: String, cara: StringName) -> void:
	lbl_fala.text = texto
	avatar.set_expression(cara)


func _on_toque(evento: InputEvent) -> void:
	var apertou := false
	if evento is InputEventMouseButton:
		apertou = (evento as InputEventMouseButton).pressed
	elif evento is InputEventScreenTouch:
		apertou = (evento as InputEventScreenTouch).pressed
	if apertou:
		_reage_ao_toque()


func _reage_ao_toque() -> void:
	var reacao: Dictionary = REACOES[randi() % REACOES.size()]
	_diz(String(reacao["texto"]), StringName(reacao["cara"]))

	# A geração é conferida na volta: sem ela, dois toques seguidos fariam o
	# primeiro timer devolver a fala do dia por cima da segunda reação.
	_geracao_toque += 1
	var minha := _geracao_toque
	await get_tree().create_timer(DURACAO_DA_REACAO).timeout
	if minha == _geracao_toque and is_inside_tree():
		_atualiza_fala()


# ═══════════════════════════════════════════════════════════
#  AÇÕES
# ═══════════════════════════════════════════════════════════

func _on_practice() -> void:
	if _next_lesson_id < 0:
		return
	Global.go_to_lesson(_next_lesson_id)


func _on_settings() -> void:
	# A seleção de câmera, a outra preferência do app, mora na engrenagem da
	# tela de lição: é lá que ela tem efeito visível.
	if !settings_dialog.is_visible():
		settings_dialog.popup_centered()
	else:
		settings_dialog.hide()

## A Home inteira é derivada do progresso, então apagar os dados invalida tudo
## o que está na tela: saudação com o nível, chips de XP e ofensiva, card
## "continue de onde parou" e o que ela tem a dizer.
func _on_data_erased() -> void:
	_update_greeting()
	_build_chips()
	_resolve_next_lesson()
	_update_hero()
	_atualiza_fala()


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
