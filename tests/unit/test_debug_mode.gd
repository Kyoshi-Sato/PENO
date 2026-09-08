extends GutTest
## Painel de depuração e validador sintético.
##
## O que estes testes protegem: uma ferramenta de teste que mente é pior que
## nenhuma. Dois riscos concretos —
##
##   1. o validador falso ficar instalado depois do uso, fazendo a PRÓXIMA
##      gravação de verdade devolver uma nota inventada, indistinguível de
##      uma nota real;
##   2. o resultado sintético creditar XP e contar como prática, poluindo a
##      ofensiva e a precisão média, que são números que o trabalho cita.

const FEEDBACK_SCENE := "res://GUI/feedback/FeedbackState.tscn"


func _licao() -> Lesson:
	var l := Lesson.new()
	l.lesson_id = 99
	l.nome_exercicio = "Teste"
	l.sinais = [{"nome_sinal": "SINAL", "json_sinal": {}}]
	return l


func _tela() -> FeedbackState:
	var fs: FeedbackState = load(FEEDBACK_SCENE).instantiate()
	add_child_autofree(fs)
	return fs


# ---------- FORMATO DO RESULTADO ----------

func test_resultado_imita_o_validador_real() -> void:
	var r: Dictionary = DebugValidator.create(0.72).validate({}, {})
	for chave: String in ["precision", "global_similarity_pct", "details",
			"mirrored", "ok", "error"]:
		assert_true(r.has(chave), "falta a chave '%s' que a tela lê" % chave)
	assert_almost_eq(float(r["precision"]), 0.72, 0.001)
	assert_true(bool(r["ok"]))


func test_todo_resultado_vem_marcado_como_sintetico() -> void:
	# É a marca que impede o crédito de XP. Sem ela em QUALQUER caminho, o
	# painel passa a corromper dados em silêncio.
	for v: DebugValidator in [DebugValidator.create(0.9), DebugValidator.failure(),
			DebugValidator.missing_hands()]:
		assert_true(bool(v.validate({}, {}).get(DebugValidator.DEBUG_FLAG, false)),
			"um caminho do validador falso não se identifica como sintético")


func test_grupos_tem_notas_diferentes() -> void:
	# A tela dá a frase de orientação ao PIOR parâmetro. Com três notas
	# iguais o "pior" seria arbitrário e o detalhamento não seria exercitado.
	var detalhes: Dictionary = DebugValidator.create(0.6).validate({}, {})["details"]
	var vistos: Array[float] = []
	for grupo: String in DebugValidator.GROUPS:
		assert_true(detalhes.has(grupo), "falta o grupo '%s'" % grupo)
		var pct: float = float((detalhes[grupo] as Dictionary)["group_similarity_pct"])
		assert_false(vistos.has(pct), "dois grupos com a mesma nota")
		vistos.append(pct)


func test_maos_ausentes_zeram_nota_e_cobertura() -> void:
	var r: Dictionary = DebugValidator.missing_hands().validate({}, {})
	var detalhes: Dictionary = r["details"]
	assert_eq((detalhes["_missing_groups"] as Array).size(), 2)
	for mao: String in ["Mão Esquerda", "Mão Direita"]:
		var g: Dictionary = detalhes[mao]
		assert_eq(float(g["group_similarity_pct"]), 0.0)
		assert_eq(float(g["detection_coverage"]), 0.0)
	assert_gt(float((detalhes["Pose (corpo)"] as Dictionary)["group_similarity_pct"]), 0.0,
		"o corpo continua detectado quando só as mãos saem do quadro")


func test_falha_nao_traz_detalhes() -> void:
	var r: Dictionary = DebugValidator.failure("teste").validate({}, {})
	assert_false(bool(r["ok"]))
	assert_eq(String(r["error"]), "teste")
	assert_true((r["details"] as Dictionary).is_empty())


func test_precisao_e_limitada() -> void:
	assert_eq(DebugValidator.create(5.0).precision, 1.0)
	assert_eq(DebugValidator.create(-2.0).precision, 0.0)


# ---------- A TROCA DE VALIDATOR ----------

func test_injetar_devolve_o_validator_original() -> void:
	# O teste mais importante do arquivo.
	var fs: FeedbackState = _tela()
	var real: SignValidator = fs.validator
	assert_not_null(real, "a tela nasce com o validador de verdade")

	var falso := DebugValidator.create(0.5)
	var visto_durante: Array[SignValidator] = []
	Debug.injetar(fs, falso, func() -> void: visto_durante.append(fs.validator))

	assert_eq(visto_durante[0], falso, "o falso não estava instalado no gatilho")
	assert_eq(fs.validator, real, "o validador falso ficou instalado depois do uso")


func test_injetar_devolve_o_original_mesmo_sem_gatilho() -> void:
	var fs: FeedbackState = _tela()
	var real: SignValidator = fs.validator
	Debug.injetar(fs, DebugValidator.create(0.5), Callable())
	assert_eq(fs.validator, real)


# ---------- INTEGRAÇÃO COM A TELA ----------

func test_resultado_sintetico_preenche_a_tela_sem_camera() -> void:
	var fs: FeedbackState = _tela()
	fs.validator = DebugValidator.create(0.85)
	fs.evaluate(_licao(), 0, {})
	await wait_for_signal(fs.evaluation_completed, 5.0)
	assert_eq(fs.get_last_stars(), 3, "0.85 deveria valer 3 estrelas")
	assert_true(bool(fs.get_last_result().get("ok", false)))


func test_resultado_sintetico_nao_credita_nada() -> void:
	var fs: FeedbackState = _tela()
	fs.validator = DebugValidator.create(0.85)
	var xp: int = Global.get_xp()
	var praticas: int = Global.get_practice_count()
	var ofensiva: int = Global.get_streak()

	fs.evaluate(_licao(), 0, {})
	await wait_for_signal(fs.evaluation_completed, 5.0)

	assert_eq(Global.get_xp(), xp, "o resultado sintético creditou XP")
	assert_eq(Global.get_practice_count(), praticas, "contou como prática")
	assert_eq(Global.get_streak(), ofensiva, "mexeu na ofensiva")


# ---------- O PAINEL ----------

func test_painel_so_existe_em_build_de_debug() -> void:
	# A suíte roda em debug, então aqui o painel TEM de estar montado. O outro
	# lado da condição não é testável de dentro de uma build de debug — quem
	# garante é o `return` no topo de `Debug._ready`.
	assert_true(OS.is_debug_build())
	var camadas: int = 0
	for filho: Node in Debug.get_children():
		if filho is CanvasLayer:
			camadas += 1
	assert_eq(camadas, 1, "o painel não montou sua CanvasLayer")


func test_painel_nasce_fechado() -> void:
	assert_false(Debug._sheet.visible, "o painel não pode nascer aberto por cima do app")
	assert_false(Debug.is_processing(), "fechado, não pode custar quadro nenhum")


func test_previsao_de_estrelas_bate_com_a_tela() -> void:
	# O rótulo do slider prevê a nota com uma cópia do mapeamento. Se a tela
	# mudar os limiares e esta cópia não, o painel passa a mentir.
	var fs: FeedbackState = _tela()
	for centesimos in range(0, 101):
		var p: float = float(centesimos) / 100.0
		assert_eq(Debug._estrelas(p), fs._stars_for_precision(p),
			"divergência em precisão %.2f" % p)


func test_acoes_sem_licao_avisam_em_vez_de_quebrar() -> void:
	# A cena corrente da suíte não é uma LessonScreen — é exatamente o estado
	# em que o dedo escorrega no painel enquanto se está na Home.
	Debug._ir_para_sinal()
	assert_string_contains(Debug._status.text, "Abra uma lição")
	Debug._aplicar(DebugValidator.create(0.9))
	assert_string_contains(Debug._status.text, "Abra uma lição")
