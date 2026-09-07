extends GutTest
## Efeitos sonoros (Audio + a preferência em Global).
##
## O que estes testes protegem: os WAVs são gerados por um script fora da
## engine (`tools/gerar_sons.py`) e carregados por caminho montado em runtime.
## Nenhum erro de compilação aparece se um arquivo sumir, for renomeado ou
## deixar de importar — o app simplesmente fica mudo. Estes testes são o
## único ponto do projeto onde essa ligação é verificada.

const StubGlobal := preload("res://tests/helpers/stub_global.gd")
const AudioScript := preload("res://Scripts/autoload/Audio.gd")

var g: Node


func before_each() -> void:
	g = autofree(StubGlobal.new())


# ---------- A PREFERÊNCIA ----------

func test_som_vem_ligado_por_padrao() -> void:
	assert_true(g.is_sound_enabled(),
		"nenhum som carrega informação exclusiva, então ligado é o padrão seguro")


func test_liga_e_desliga() -> void:
	g.set_sound_enabled(false)
	assert_false(g.is_sound_enabled())
	g.set_sound_enabled(true)
	assert_true(g.is_sound_enabled())


func test_regravar_o_mesmo_valor_nao_emite() -> void:
	watch_signals(g)
	g.set_sound_enabled(false)
	g.set_sound_enabled(false)
	assert_signal_emit_count(g, "sound_enabled_changed", 1)


func test_preferencia_nao_e_apagada_com_os_dados() -> void:
	# "Apagar dados" zera progresso, não configuração do aparelho — o som
	# mora em settings.json justamente por isso.
	g.set_sound_enabled(false)
	g.erase_all_data()
	assert_false(g.is_sound_enabled(),
		"apagar o progresso não pode religar o som que o usuário desligou")


# ---------- A TABELA DE SONS ----------

func test_todo_cue_tem_entrada_na_tabela() -> void:
	for nome: String in AudioScript.Cue:
		var valor: int = AudioScript.Cue[nome]
		assert_true(AudioScript.CUES.has(valor),
			"Cue.%s não tem arquivo nem ganho definidos" % nome)


func test_todo_arquivo_existe_e_e_audio() -> void:
	for cue: int in AudioScript.CUES:
		var arquivo: String = String((AudioScript.CUES[cue] as Dictionary)["file"])
		var caminho: String = AudioScript.AUDIO_DIR + arquivo + ".wav"
		assert_true(ResourceLoader.exists(caminho),
			"%s não existe — rode `python3 tools/gerar_sons.py` e reimporte" % caminho)
		if not ResourceLoader.exists(caminho):
			continue
		var res: Resource = load(caminho)
		assert_true(res is AudioStream, "%s não importou como AudioStream" % caminho)
		if res is AudioStream:
			var dur: float = (res as AudioStream).get_length()
			assert_gt(dur, 0.0, "%s tem duração zero" % caminho)
			# Um efeito de interface longo demais atropela o próximo passo do
			# fluxo — a contagem toca de segundo em segundo.
			assert_lt(dur, 1.5, "%s é longo demais para um efeito de UI" % caminho)


func test_nenhum_som_repetido_na_tabela() -> void:
	var vistos: Dictionary = {}
	for cue: int in AudioScript.CUES:
		var arquivo: String = String((AudioScript.CUES[cue] as Dictionary)["file"])
		assert_false(vistos.has(arquivo),
			"'%s' está em dois cues — momentos diferentes devem soar diferente" % arquivo)
		vistos[arquivo] = true


func test_ganhos_nunca_amplificam() -> void:
	# Os WAVs já saem do gerador normalizados perto do pico. Um ganho positivo
	# aqui satura no alto-falante do celular em vez de ficar mais alto.
	for cue: int in AudioScript.CUES:
		var db: float = float((AudioScript.CUES[cue] as Dictionary)["db"])
		assert_lte(db, 0.0, "cue %d amplifica um arquivo já normalizado" % cue)


func test_toque_e_o_som_mais_discreto() -> void:
	# É o som mais repetido do app — se empatar com os outros, cansa.
	var db_toque: float = float((AudioScript.CUES[AudioScript.Cue.TAP] as Dictionary)["db"])
	for cue: int in AudioScript.CUES:
		if cue == AudioScript.Cue.TAP:
			continue
		assert_lt(db_toque, float((AudioScript.CUES[cue] as Dictionary)["db"]),
			"o clique de botão precisa ser mais baixo que o cue %d" % cue)


# ---------- BARRAMENTO E VOZES ----------

func test_barramento_sfx_existe() -> void:
	# Sem ele os efeitos caem no Master, junto da captura de áudio do GDMP.
	assert_gte(AudioServer.get_bus_index(AudioScript.BUS_NAME), 0,
		"o barramento SFX sumiu de default_bus_layout.tres")


func test_autoload_montou_as_vozes() -> void:
	var vozes: int = 0
	for filho: Node in Audio.get_children():
		if filho is AudioStreamPlayer:
			vozes += 1
	assert_eq(vozes, AudioScript.VOICES)


func test_todos_os_sons_carregaram_no_autoload() -> void:
	for cue: int in AudioScript.CUES:
		assert_true(Audio._streams.has(cue),
			"cue %d não carregou no autoload" % cue)


func test_voz_ocupada_nao_e_devolvida_duas_vezes() -> void:
	# Três estrelas em cascata mais o XP só soam juntos se cada chamada pegar
	# um tocador diferente.
	var a: AudioStreamPlayer = Audio._take_voice()
	a.stream = Audio._streams[AudioScript.Cue.STAR]
	a.play()
	var b: AudioStreamPlayer = Audio._take_voice()
	assert_ne(a, b, "a segunda voz cortaria a primeira no meio")
	a.stop()


## `Motion.attach_press` é um método ESTÁTICO que chama o autoload `Audio`.
## Se um dia essa referência parar de resolver de dentro de um contexto
## estático, o app inteiro fica sem clique de botão e nada acusa.
func test_toque_de_botao_sai_do_metodo_estatico() -> void:
	var b := Button.new()
	add_child_autofree(b)
	Motion.attach_press(b)
	Audio.stop_all()
	b.emit_signal("button_down")
	assert_eq(_vozes_tocando(), 1, "button_down não produziu som")


func test_som_desligado_nao_toca_nada() -> void:
	# Mexe no dicionário direto para não gravar preferência em disco durante
	# a suíte — `set_sound_enabled` persiste em user://settings.json.
	var antes: Variant = Global._settings.get("sound_enabled")
	Global._settings["sound_enabled"] = false
	Audio.stop_all()
	Audio.play(AudioScript.Cue.LESSON_DONE)
	var tocando: int = _vozes_tocando()
	if antes == null:
		Global._settings.erase("sound_enabled")
	else:
		Global._settings["sound_enabled"] = antes
	assert_eq(tocando, 0, "com o som desligado nenhuma voz pode disparar")


func _vozes_tocando() -> int:
	var n: int = 0
	for filho: Node in Audio.get_children():
		if filho is AudioStreamPlayer and (filho as AudioStreamPlayer).playing:
			n += 1
	return n


func test_estrelas_tem_um_pitch_por_estrela() -> void:
	# A cascata lê STAR_PITCHES por índice; faltando um, a terceira estrela
	# sairia na mesma nota da primeira e o acorde não fecharia.
	assert_eq(FeedbackState.STAR_PITCHES.size(), StarRow.MAX_STARS)
	var anterior: float = 0.0
	for p: float in FeedbackState.STAR_PITCHES:
		assert_gt(p, anterior, "as notas da cascata precisam subir")
		anterior = p
