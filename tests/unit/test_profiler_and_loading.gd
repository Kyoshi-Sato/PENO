extends GutTest
## Testes unitários para o Profiler de desempenho em arquivo, LoadingOverlay e Cache Local.

const ProfilerScript := preload("res://Scripts/autoload/Profiler.gd")
const LoadingOverlayScript := preload("res://GUI/components/LoadingOverlay.gd")
const LessonServiceScript := preload("res://Scripts/autoload/LessonService.gd")


func test_profiler_timer_and_file_logging() -> void:
	var profiler: Node = autofree(ProfilerScript.new())

	profiler.start_timer("UNIT_TEST_OPERATION")
	# Simula trabalho alocando memória temporária
	var dummy_arr: Array = []
	for i in range(10000):
		dummy_arr.append("string_%d" % i)

	var elapsed: float = profiler.end_timer("UNIT_TEST_OPERATION", {"test_key": "val123"})
	assert_gt(elapsed, 0.0, "O tempo medido deve ser estritamente positivo")

	profiler.log_event("TEST_CAT", "Mensagem de teste instantanea", {"meta": 42})

	# Verifica persistência física no disco
	assert_true(FileAccess.file_exists(profiler.LOG_PATH), "O arquivo user://performance.log deve existir no disco")

	var content: String = profiler.get_log_contents()
	assert_true(content.contains("[TIMER] UNIT_TEST_OPERATION"), "O log deve conter o registro da operação cronometrada")
	assert_true(content.contains("test_key=val123"), "O log deve conter os detalhes anexados")
	assert_true(content.contains("mem_current_mb="), "O log deve registrar o consumo de memória atual")
	assert_true(content.contains("[TEST_CAT] Mensagem de teste instantanea"), "O log deve registrar eventos instantâneos")


func test_loading_overlay_lifecycle() -> void:
	var overlay: LoadingOverlay = autofree(LoadingOverlayScript.new())
	add_child_autofree(overlay)

	overlay.set_title("Lição de Teste")
	assert_eq(overlay._lbl_title.text, "Lição de Teste", "Título deve ser configurado")

	overlay.set_progress("Baixando sinais...", 0.45)
	assert_eq(overlay._lbl_step.text, "Baixando sinais...", "Texto da etapa deve ser atualizado")
	assert_eq(overlay._lbl_pct.text, "45%", "Porcentagem deve refletir o valor 45%")

	# Teste de estado de erro
	var flags := {"retry": false, "cancel": false}

	var on_retry := func() -> void: flags["retry"] = true
	var on_cancel := func() -> void: flags["cancel"] = true

	overlay.show_error("Falha de conexão simulada", on_retry, on_cancel)
	assert_true(overlay._error_box.visible, "Painel de erro deve estar visível")
	assert_false(overlay._progress_bar.visible, "Barra de progresso deve estar oculta no erro")
	assert_true(overlay._lbl_error_msg.text.contains("Falha de conexão simulada"), "Mensagem de erro deve ser exibida")

	# Simula clique nos botões
	overlay._btn_retry.pressed.emit()
	assert_true(bool(flags["retry"]), "Callback de retry deve ser acionado")

	overlay._btn_cancel.pressed.emit()
	assert_true(bool(flags["cancel"]), "Callback de cancel deve ser acionado")


func test_lesson_service_instant_disk_cache() -> void:
	var svc: Node = autofree(LessonServiceScript.new())
	add_child_autofree(svc)

	var test_lesson_id := 8888
	var dummy_payload := {
		"nome_exercicio": "Lição de Teste em Cache",
		"sinais": [
			{
				"nome_sinal": "A",
				"anim_lib": "[gd_resource type=\"Animation\" format=3]\n[resource]\nresource_name = \"A\"\nlength = 1.0\n",
				"json_sinal": {
					"frames": [
						{
							"t": 0.0,
							"pose": [{"x": 0.5, "y": 0.5, "z": 0.0, "visibility": 1.0}],
							"hands": {"right": [{"x": 0.5, "y": 0.5, "z": 0.0}]}
						}
					]
				}
			}
		]
	}

	# Grava payload simulado no cache local
	svc._ensure_cache_dirs()
	var cache_file: String = svc.LESSON_CACHE_DIR.path_join("lesson_%d.json" % test_lesson_id)
	var f := FileAccess.open(cache_file, FileAccess.WRITE)
	assert_not_null(f, "Deve conseguir criar arquivo no cache de lições")
	f.store_string(JSON.stringify(dummy_payload))
	f.close()

	var result_box: Array = [null]
	var on_loaded := func(l: Lesson) -> void:
		result_box[0] = l

	# fetch_lesson deve carregar instantaneamente do cache em vez de ir na rede
	svc.fetch_lesson(test_lesson_id, on_loaded)

	var loaded_lesson: Lesson = result_box[0] as Lesson
	assert_not_null(loaded_lesson, "A lição em cache deve ser carregada com sucesso")
	if loaded_lesson != null:
		assert_eq(loaded_lesson.lesson_id, test_lesson_id, "Id da lição deve bater")
		assert_eq(loaded_lesson.nome_exercicio, "Lição de Teste em Cache")
		assert_eq(loaded_lesson.sinais.size(), 1)


func test_recording_state_waits_for_camera_before_countdown() -> void:
	var rec: Control = autofree(load("res://GUI/recordingstate/RecordingState.tscn").instantiate())
	add_child_autofree(rec)

	var dummy_lesson := Lesson.new()
	dummy_lesson.sinais = [{"nome_sinal": "A", "json_sinal": {}}]

	# Inicia gravação com a câmera ainda não pronta
	rec.is_camera_ready_override = false
	rec.begin(dummy_lesson, 0, 3.0)

	# Deve estar em WAITING_CAMERA e não em COUNTDOWN
	assert_eq(rec._phase, rec.Phase.WAITING_CAMERA, "Fase deve ser WAITING_CAMERA enquanto a câmera não carregou")
	assert_eq(rec.lbl_status.text, "Iniciando câmera...", "Status deve indicar espera da câmera")

	# Agora notifica que a câmera carregou
	rec.notify_camera_ready()

	# Deve ter transitado imediatamente para COUNTDOWN
	assert_eq(rec._phase, rec.Phase.COUNTDOWN, "Fase deve avançar para COUNTDOWN quando a câmera fica pronta")
	assert_eq(rec.lbl_status.text, "Prepare-se", "Status deve mudar para Prepare-se")
	assert_false(rec._tick_timer.is_stopped(), "Timer da contagem regressiva deve estar ativo")


func test_holistic_camera_helpers() -> void:
	var holistic: Node = autofree(load("res://GUI/vision/holistic_landmarker/HolisticLandmarker.tscn").instantiate())
	add_child_autofree(holistic)

	assert_false(holistic.is_camera_streaming(), "Sem feed ativo, is_camera_streaming deve ser false")

	# wait_for_camera_ready deve retornar de forma limpa e segura sem travar
	var ready_ok: bool = await holistic.wait_for_camera_ready(0.2)
	assert_false(ready_ok, "Sem câmera física conectada no teste headless, wait_for_camera_ready deve retornar false com segurança")
