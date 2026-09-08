extends Node
## Painel de depuração. Cadastre como Autoload com nome "Debug".
##
## POR QUE ELE EXISTE
## ------------------
## Chegar na tela de resultado custava: abrir o app, escolher a lição, ver o
## avatar, esperar a contagem, executar o sinal na frente da câmera, esperar
## de 1 a 8 s de análise — e mesmo assim sem controle sobre a nota que ia
## sair. Testar 0 estrelas exigia errar de propósito; testar "não vimos suas
## mãos" exigia sair do quadro na hora certa; testar o mapa com lições
## concluídas exigia concluí-las.
##
## Este painel encurta isso para um toque, E FUNCIONA NO CELULAR — que é o
## único lugar onde a câmera, o backend de inferência e o alto-falante se
## comportam como de verdade, e onde não há editor nem depurador à mão.
##
## COMO ELE NÃO VAZA PARA A BUILD FINAL
## ------------------------------------
## `_ready` sai imediatamente quando `OS.is_debug_build()` é falso. Numa build
## de release nada é instanciado: sem CanvasLayer, sem alça, sem `_process`.
## O script continua no pacote (é um autoload), mas inerte — e é por isso que
## nenhuma ação daqui pode depender de estar escondida para ser segura.
##
## O QUE ELE NÃO FAZ
## -----------------
## Não credita XP nem conta prática pelo resultado sintético. A ofensiva e a
## precisão média são estatísticas que o trabalho cita; enchê-las de notas
## inventadas durante um teste de UI as invalidaria sem deixar rastro. Quem
## garante isso é a flag `DebugValidator.DEBUG_FLAG`, lida em
## `FeedbackState._fill_reward`.

## Acima da camada de transição de cena do Global (128), de propósito: o
## painel precisa continuar acessível durante um fade.
const LAYER := 200
const HANDLE_SIZE := 88
const SHEET_WIDTH := 760
## Diagnóstico é o único bloco que muda sozinho. 4x por segundo é suficiente
## para acompanhar fps sem virar custo.
const REFRESH_INTERVAL := 0.25

## Presets do resultado sintético: rótulo -> precisão. Os valores caem no
## meio de cada faixa de estrelas em vez de na fronteira — testar a fronteira
## é trabalho do teste unitário, não do dedo.
const PRESETS: Array[Dictionary] = [
	{"label": "0★", "precision": 0.30},
	{"label": "1★", "precision": 0.55},
	{"label": "2★", "precision": 0.65},
	{"label": "3★", "precision": 0.85},
]

var _layer: CanvasLayer
var _handle: Button
var _sheet: PanelContainer
var _status: Label
var _slider: HSlider
var _slider_label: Label
var _stage_buttons: Array[Button] = []
var _diag_values: Dictionary = {}
var _accum: float = 0.0
## Catálogo buscado sob demanda por "Concluir todas" — só o LessonService
## sabe quais ids existem.
var _catalog: Array = []


func _ready() -> void:
	if not OS.is_debug_build():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	set_process(false)


# ═══════════════════════════════════════════════════════════
#  MONTAGEM
# ═══════════════════════════════════════════════════════════

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	add_child(_layer)

	# Casca que ocupa a tela inteira mas não intercepta nada: sem IGNORE aqui
	# o painel fechado engoliria todo toque do app.
	var casca := Control.new()
	casca.set_anchors_preset(Control.PRESET_FULL_RECT)
	casca.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(casca)

	_build_handle(casca)
	_build_sheet(casca)
	_sheet.visible = false


## Alça na borda esquerda, na altura do meio: é a única faixa da tela que
## nenhuma das telas do app usa (voltar e engrenagem ficam no topo, a
## navegação fica embaixo).
func _build_handle(pai: Control) -> void:
	_handle = Button.new()
	_handle.text = "D"
	_handle.focus_mode = Control.FOCUS_NONE
	_handle.custom_minimum_size = Vector2(HANDLE_SIZE, HANDLE_SIZE)
	_handle.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_handle.offset_left = 0
	_handle.offset_top = -HANDLE_SIZE * 0.5
	_handle.offset_right = HANDLE_SIZE
	_handle.offset_bottom = HANDLE_SIZE * 0.5
	_handle.modulate.a = 0.55
	_estilizar_botao(_handle, DS.DANGER_INK)
	_handle.pressed.connect(_toggle)
	pai.add_child(_handle)


func _build_sheet(pai: Control) -> void:
	_sheet = PanelContainer.new()
	_sheet.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_sheet.offset_left = DS.SPACE_SM
	_sheet.offset_right = DS.SPACE_SM + SHEET_WIDTH
	# Altura limitada e conteúdo rolável: o painel cresce com o diagnóstico e
	# não pode passar da tela num aparelho baixo.
	_sheet.offset_top = -820
	_sheet.offset_bottom = 820
	_sheet.add_theme_stylebox_override("panel",
		DS.fill(Color(0.06, 0.07, 0.14, 0.96), DS.RADIUS_MD, DS.SPACE_SM, DS.SPACE_SM))
	pai.add_child(_sheet)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", DS.SPACE_SM)
	scroll.add_child(col)

	_build_header(col)

	_status = _texto(col, "", DS.TEXT_CAPTION, DS.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_build_stage_section(col)
	_build_result_section(col)
	_build_progress_section(col)
	_build_diagnostics_section(col)


func _build_header(col: VBoxContainer) -> void:
	var linha := HBoxContainer.new()
	col.add_child(linha)

	var titulo := _texto(linha, "DEBUG", DS.TEXT_H3, DS.DANGER)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var fechar := Button.new()
	fechar.text = "✕"
	fechar.focus_mode = Control.FOCUS_NONE
	fechar.custom_minimum_size = Vector2(72, 72)
	_estilizar_botao(fechar, DS.DANGER_INK)
	fechar.pressed.connect(_toggle)
	linha.add_child(fechar)


func _build_stage_section(col: VBoxContainer) -> void:
	_secao(col, "ETAPA DA LIÇÃO")
	var linha := _linha(col)
	_stage_buttons = [
		_botao(linha, "Sinal", _ir_para_sinal),
		_botao(linha, "Gravar", _ir_para_gravacao),
	]


func _build_result_section(col: VBoxContainer) -> void:
	_secao(col, "RESULTADO SINTÉTICO")

	_slider_label = _texto(col, "", DS.TEXT_BODY_SM, DS.TEXT_ON_PRIMARY)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value = 0.62
	_slider.custom_minimum_size = Vector2(0, 72)
	_slider.value_changed.connect(_on_slider)
	col.add_child(_slider)
	_on_slider(_slider.value)

	var linha := _linha(col)
	_botao(linha, "Aplicar", func() -> void:
		_aplicar(DebugValidator.create(_slider.value)))
	for preset: Dictionary in PRESETS:
		var p: float = float(preset["precision"])
		_botao(linha, String(preset["label"]), func() -> void:
			_slider.value = p
			_aplicar(DebugValidator.create(p)))

	var linha2 := _linha(col)
	# Os dois caminhos de exceção da tela, que são os mais difíceis de
	# reproduzir de propósito com uma câmera na mão.
	_botao(linha2, "Sem mãos", func() -> void:
		_aplicar(DebugValidator.missing_hands()))
	_botao(linha2, "Falha", func() -> void:
		_aplicar(DebugValidator.failure()))
	_botao(linha2, "Espelhado", func() -> void:
		var v := DebugValidator.create(_slider.value)
		v.mirrored = true
		_aplicar(v))


func _build_progress_section(col: VBoxContainer) -> void:
	_secao(col, "PROGRESSO")
	var linha := _linha(col)
	_botao(linha, "+100 XP", _dar_xp.bind(100))
	_botao(linha, "+1 nível", _dar_xp.bind(Global.XP_PER_LEVEL))
	var linha2 := _linha(col)
	_botao(linha2, "Concluir todas", _concluir_todas)
	_botao(linha2, "Zerar tudo", _zerar, DS.DANGER_INK)


func _build_diagnostics_section(col: VBoxContainer) -> void:
	_secao(col, "DIAGNÓSTICO")
	var grade := GridContainer.new()
	grade.columns = 2
	grade.add_theme_constant_override("h_separation", DS.SPACE_SM)
	grade.add_theme_constant_override("v_separation", DS.SPACE_XXS)
	col.add_child(grade)

	# Linhas construídas uma vez; só o texto do valor é reescrito no refresh.
	# Reconstruir a grade 4x por segundo criaria e destruiria ~30 nós por
	# segundo em cima do pipeline de inferência.
	for chave: String in ["aparelho", "app", "fps UI", "memória", "som",
			"backend", "threads", "GPU", "lição", "câmera",
			"entrada", "resultados", "latência", "readback", "quadro"]:
		_texto(grade, chave, DS.TEXT_CAPTION, DS.TEXT_SUBTLE)
		var valor := _texto(grade, "—", DS.TEXT_CAPTION, DS.TEXT_ON_PRIMARY)
		valor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_diag_values[chave] = valor


# ═══════════════════════════════════════════════════════════
#  ABRIR / FECHAR
# ═══════════════════════════════════════════════════════════

func _toggle() -> void:
	_sheet.visible = not _sheet.visible
	_handle.visible = not _sheet.visible
	set_process(_sheet.visible)
	if _sheet.visible:
		_accum = REFRESH_INTERVAL
		_dizer("")


func _process(delta: float) -> void:
	_accum += delta
	if _accum < REFRESH_INTERVAL:
		return
	_accum = 0.0
	_atualizar_diagnostico()


# ═══════════════════════════════════════════════════════════
#  ETAPA E RESULTADO
# ═══════════════════════════════════════════════════════════

## A tela de lição não é acessível por caminho fixo — ela é a cena corrente
## só enquanto o usuário está numa lição. Procurar a cada ação é mais barato
## do que manter um registro que precisaria ser invalidado a cada troca.
func _lesson_screen() -> LessonScreen:
	var cena: Node = get_tree().current_scene
	if cena == null:
		return null
	if cena is LessonScreen:
		return cena as LessonScreen
	for filho: Node in cena.find_children("*", "Control", true, false):
		if filho is LessonScreen:
			return filho as LessonScreen
	return null


## Devolve a tela de lição pronta para receber um comando, ou null tendo já
## explicado no painel por que não dá.
func _lesson_screen_pronta() -> LessonScreen:
	var tela: LessonScreen = _lesson_screen()
	if tela == null:
		_dizer("Abra uma lição primeiro — não há LessonScreen na cena.")
		return null
	if tela.lesson == null or tela.lesson.sinais.is_empty():
		_dizer("A lição ainda não carregou (ou não tem sinais).")
		return null
	return tela


func _ir_para_sinal() -> void:
	var tela: LessonScreen = _lesson_screen_pronta()
	if tela == null:
		return
	(tela.state_machine as LessonStateMachine).go_to_sign_showcase()
	_dizer("Etapa: observar o sinal.")


func _ir_para_gravacao() -> void:
	var tela: LessonScreen = _lesson_screen_pronta()
	if tela == null:
		return
	(tela.state_machine as LessonStateMachine).go_to_recording()
	_dizer("Etapa: gravação (precisa de câmera).")


## Injeta a nota escolhida e entra na tela de resultado.
func _aplicar(validador: DebugValidator) -> void:
	var tela: LessonScreen = _lesson_screen_pronta()
	if tela == null:
		return

	injetar(tela.feedback as FeedbackState, validador,
		(tela.state_machine as LessonStateMachine).go_to_feedback)

	if not validador.ok:
		_dizer("Resultado: falha de validação.")
	elif not validador.missing_groups.is_empty():
		_dizer("Resultado: mãos não detectadas.")
	else:
		_dizer("Resultado: precisão %.2f (nada foi creditado)." % validador.precision)


## Troca o validator da tela, dispara a avaliação e DEVOLVE O ORIGINAL.
##
## É a parte perigosa do painel inteiro e por isso mora sozinha, estática e
## coberta por teste: deixar o validador falso no lugar faria a próxima
## gravação DE VERDADE devolver uma nota inventada — o pior defeito possível
## numa ferramenta de teste, porque o resultado errado é indistinguível de um
## resultado certo.
##
## Restaurar logo após o gatilho é seguro porque `FeedbackState.evaluate()`
## copia o validator para dentro da tarefa antes de devolver o controle.
static func injetar(fb: FeedbackState, validador: SignValidator, gatilho: Callable) -> void:
	if fb == null:
		return
	var original: SignValidator = fb.validator
	fb.validator = validador
	if gatilho.is_valid():
		gatilho.call()
	fb.validator = original


func _on_slider(valor: float) -> void:
	_slider_label.text = "precisão %.2f  →  %d estrela(s)" % [valor, _estrelas(valor)]


## Espelha o mapeamento de `FeedbackState`. Duplicado de propósito: o painel
## só PREVÊ o resultado no rótulo do slider, e não pode alterar o caminho
## real chamando um método privado da tela.
func _estrelas(p: float) -> int:
	if p >= 0.7:
		return 3
	if p >= 0.6:
		return 2
	if p >= 0.5:
		return 1
	return 0


# ═══════════════════════════════════════════════════════════
#  PROGRESSO
# ═══════════════════════════════════════════════════════════
#
# Mexe direto no dicionário do Global em vez de pedir métodos públicos novos.
# É a troca certa: `award_sign_result` existe para pagar melhora de nota, e
# abrir um `set_xp()` permanente na API só para o painel deixaria uma porta
# de fraude aberta na build final, onde este código nem roda.

func _dar_xp(quanto: int) -> void:
	var s: Dictionary = Global._stats()
	s["xp"] = int(s.get("xp", 0)) + quanto
	Global._progress[Global.STATS_KEY] = s
	Global._save_progress()
	_dizer("XP agora %d (nível %d)." % [Global.get_xp(), Global.get_level()])


## Conclui todas as lições do catálogo, o que também destrava todas — o
## desbloqueio é derivado ("a anterior está completa"), não um campo próprio.
func _concluir_todas() -> void:
	if not _catalog.is_empty():
		_concluir(_catalog)
		return
	_dizer("Buscando catálogo…")
	LessonService.fetch_catalog(
		func(catalogo: Array) -> void:
			_catalog = catalogo
			_concluir(catalogo),
		func(erro: String) -> void:
			_dizer("Catálogo falhou: %s" % erro))


func _concluir(catalogo: Array) -> void:
	for entrada: Dictionary in catalogo:
		Global.mark_completed(int(entrada.get("id", -1)), 3)
	_dizer("%d lições concluídas com 3 estrelas." % catalogo.size())


func _zerar() -> void:
	Global.erase_all_data()
	LessonService.clear_cache()
	_catalog.clear()
	_dizer("Progresso, XP, ofensiva e cache apagados.")


# ═══════════════════════════════════════════════════════════
#  DIAGNÓSTICO
# ═══════════════════════════════════════════════════════════

func _atualizar_diagnostico() -> void:
	_set_diag("aparelho", "%s · %s" % [OS.get_name(), OS.get_model_name()])
	_set_diag("app", "%s · debug" % ProjectSettings.get_setting(
		"application/config/version", "?"))
	_set_diag("fps UI", "%.0f" % Engine.get_frames_per_second())
	_set_diag("memória", "%.1f MB" % (float(OS.get_static_memory_usage()) / 1048576.0))
	_set_diag("som", "ligado" if Global.is_sound_enabled() else "desligado")

	_set_diag("backend", "%s → %s" % [
		Global.inference_backend_label(Global.get_inference_backend()),
		Global.inference_backend_label(Global.resolve_inference_backend())])
	_set_diag("threads", str(Global.get_inference_cpu_threads()))
	_set_diag("GPU", "bloqueada" if Global.is_gpu_blocked()
		else ("disponível" if Global.is_gpu_supported() else "desligada nesta versão"))

	_atualizar_licao()


func _atualizar_licao() -> void:
	var tela: LessonScreen = _lesson_screen()
	if tela == null or tela.lesson == null:
		_set_diag("lição", "—")
		_set_diag("câmera", "—")
		for chave: String in ["entrada", "resultados", "latência", "readback", "quadro"]:
			_set_diag(chave, "—")
		return

	_set_diag("lição", "%d · sinal %d/%d" % [
		tela.lesson.lesson_id, tela.current_sign_index + 1, tela.lesson.sinais.size()])

	var holistic: Node = tela.holistic
	if holistic == null:
		return

	var feed: Variant = holistic.get("camera_feed")
	_set_diag("câmera", "sem câmera" if feed == null
		else "%s%s" % [feed.get_name(),
			" (frontal)" if feed.get_position() == CameraFeed.FEED_FRONT else ""])

	var perf: Dictionary = holistic.get("last_perf") as Dictionary
	if perf == null or perf.is_empty():
		for chave: String in ["entrada", "resultados", "latência", "readback"]:
			_set_diag(chave, "aguardando")
		_set_diag("quadro", "—")
		return

	_set_diag("entrada", "%.1f fps" % float(perf["entrada_fps"]))
	_set_diag("resultados", "%.1f fps" % float(perf["resultados_fps"]))
	_set_diag("latência", "%.0f ms" % float(perf["latencia_ms"]))
	_set_diag("readback", "%.1f ms/quadro" % float(perf["readback_ms"]))
	var q: Vector2i = perf["quadro"]
	_set_diag("quadro", "%dx%d" % [q.x, q.y])


func _set_diag(chave: String, valor: String) -> void:
	var lbl: Label = _diag_values.get(chave, null) as Label
	if lbl != null:
		lbl.text = valor


# ═══════════════════════════════════════════════════════════
#  MIUDEZAS DE UI
# ═══════════════════════════════════════════════════════════

func _dizer(msg: String) -> void:
	_status.text = msg
	_status.visible = not msg.is_empty()


func _secao(pai: Node, titulo: String) -> void:
	var lbl := _texto(pai, titulo, DS.TEXT_LABEL, DS.ACCENT)
	lbl.add_theme_constant_override("line_spacing", 0)


func _linha(pai: Node) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", DS.SPACE_XS)
	pai.add_child(h)
	return h


func _texto(pai: Node, txt: String, tamanho: int, cor: Color) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", tamanho)
	lbl.add_theme_color_override("font_color", cor)
	pai.add_child(lbl)
	return lbl


func _botao(pai: Node, txt: String, acao: Callable, cor: Color = DS.PRIMARY) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 96)
	# Sem `Motion.attach_press`: o painel não deve tocar o clique da interface
	# nem animar como o app, senão vira parte dele.
	_estilizar_botao(b, cor)
	b.pressed.connect(acao)
	pai.add_child(b)
	return b


## Estilo próprio, escuro e chapado. O painel tem que ser impossível de
## confundir com a interface do app numa captura de tela.
func _estilizar_botao(b: Button, cor: Color) -> void:
	b.add_theme_font_size_override("font_size", DS.TEXT_BODY_SM)
	b.add_theme_color_override("font_color", DS.TEXT_ON_PRIMARY)
	b.add_theme_color_override("font_hover_color", DS.TEXT_ON_PRIMARY)
	b.add_theme_color_override("font_pressed_color", DS.TEXT_ON_PRIMARY)
	for estado: String in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(estado,
			DS.fill(cor, DS.RADIUS_SM, DS.SPACE_XS, DS.SPACE_XS))
