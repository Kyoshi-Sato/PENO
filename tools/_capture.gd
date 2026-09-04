extends SceneTree
## Ferramenta de revisão visual: carrega cada tela com dados falsos e salva
## um PNG em user://shots/. Não faz parte do app.

const OUT_DIR := "user://shots"

const FAKE_CATALOG: Array = [
	{"id": 1, "nome": "Alfabeto: A a E"},
	{"id": 2, "nome": "Alfabeto: F a J"},
	{"id": 3, "nome": "Cumprimentos"},
	{"id": 4, "nome": "Números 1 a 10"},
	{"id": 5, "nome": "Família"},
]


func _init() -> void:
	root.set_content_scale_size(Vector2i(1080, 1920))
	root.set_content_scale_mode(Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	await process_frame
	_seed_progress()

	await _shoot_main()
	await _shoot_progress()
	await _shoot_map()
	await _shoot_showcase()
	await _shoot_recording()
	await _shoot_feedback()
	await _shoot_lesson_chrome()

	print("shots em: ", ProjectSettings.globalize_path(OUT_DIR))
	quit(0)


func _seed_progress() -> void:
	var g: Node = root.get_node_or_null("/root/Global")
	if g == null:
		return
	g.reset_progress()
	g.mark_completed(1, 3)
	g.mark_completed(2, 2)
	g.award_sign_result(1, 0, 3)
	g.award_sign_result(1, 1, 3)
	g.award_sign_result(2, 0, 2)
	g.register_practice(0.86)
	g.register_practice(0.71)


func _capture(name: String) -> void:
	# As telas entram com fade/stagger; sem esperar, a captura pega tudo
	# no meio da animação e a revisão fica sobre um estado que o usuário
	# nunca vê parado.
	var timer := create_timer(1.4)
	await timer.timeout
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("  -> %s  %dx%d" % [name, img.get_width(), img.get_height()])


func _mount(path: String) -> Node:
	for c in root.get_children():
		if c.name != "Global" and c.name != "LessonService" \
				and c.name != "MediaPipeExternalFiles" and c.name != "GDMPAndroid":
			c.queue_free()
	await process_frame
	var inst: Node = (load(path) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	return inst


func _shoot_main() -> void:
	var s: Node = await _mount("res://GUI/Screens/Main/Main.tscn")
	# Injeta depois que a busca real na API já respondeu (ou falhou), senão
	# a resposta verdadeira sobrescreve o catálogo de revisão.
	await create_timer(1.2).timeout
	s.call("_on_catalog_loaded", FAKE_CATALOG)
	await _capture("01_home")


func _shoot_progress() -> void:
	await _mount("res://GUI/progress/ProgressScreen.tscn")
	await _capture("02_progresso")


func _shoot_map() -> void:
	var s: Node = await _mount("res://GUI/lessonmap/LessonMapScreen.tscn")
	await create_timer(1.2).timeout
	s.call("_on_catalog_loaded", FAKE_CATALOG)
	await _capture("03_trilha")


## Os três estados da lição são capturados isolados: montar a LessonScreen
## inteira ligaria câmera e MediaPipe, que não existem no ambiente de captura.
func _shoot_showcase() -> void:
	var s: Node = await _mount("res://GUI/signshowcase/SignShowcaseState.tscn")
	s.call("setup", _fake_lesson(), 0)
	await _capture("04_assista")


func _shoot_recording() -> void:
	var s: Node = await _mount("res://GUI/recordingstate/RecordingState.tscn")
	s.call("begin", _fake_lesson(), 0, 4.0)
	await _capture("05_pratique")


func _shoot_feedback() -> void:
	var s: Node = await _mount("res://GUI/feedback/FeedbackState.tscn")
	# Injeta um resultado de validação plausível direto no handler, em vez de
	# adicionar um método só-para-captura no código de produção.
	s.set("_pending_lesson", _fake_lesson())
	s.set("_pending_idx", 0)
	s.set("_pending_payload", {"video_info": {"fps": 30.0, "total_frames": 540}})
	s.call("_on_validation_done", {
		"ok": true,
		"precision": 0.78,
		"global_similarity_pct": 78.0,
		"mirrored": false,
		"error": "",
		"details": {
			"Pose (corpo)": {"group_similarity_pct": 88.4, "detection_coverage": 1.0},
			"Mão Direita": {"group_similarity_pct": 71.2, "detection_coverage": 0.94},
			"Mão Esquerda": {"group_similarity_pct": 42.0, "detection_coverage": 0.38},
			"_missing_groups": [],
		},
	}, 0)
	await _capture("06_resultado")
	# Rola até o fim: a linha de métricas e o card de módulo ficam abaixo da
	# dobra e não apareciam em nenhuma captura.
	var scroll: ScrollContainer = s.get_node("Scroll")
	scroll.scroll_vertical = 100000
	await _capture("06b_resultado_fim")

	var weak: Node = await _mount("res://GUI/feedback/FeedbackState.tscn")
	weak.set("_pending_lesson", _fake_lesson())
	weak.set("_pending_idx", 0)
	weak.set("_pending_payload", {"video_info": {"fps": 30.0, "total_frames": 300}})
	weak.call("_on_validation_done", {
		"ok": true,
		"precision": 0.41,
		"global_similarity_pct": 41.0,
		"mirrored": false,
		"error": "",
		"details": {
			"Pose (corpo)": {"group_similarity_pct": 46.0, "detection_coverage": 1.0},
			"Mão Direita": {"group_similarity_pct": 38.5, "detection_coverage": 0.92},
			"Mão Esquerda": {"group_similarity_pct": 44.0, "detection_coverage": 0.88},
			"_missing_groups": [],
		},
	}, 0)
	await _capture("06d_resultado_fraco")


## Monta a LessonScreen inteira para conferir se o chrome (voltar / etapas /
## câmera) convive com o conteúdo de cada estado sem sobreposição.
func _shoot_lesson_chrome() -> void:
	var s: Node = await _mount("res://GUI/lessonscreen/LessonScreen.tscn")
	var l := _fake_lesson()
	l.animation_library = AnimationLibrary.new()
	s.call("_on_lesson_loaded", l)
	await _capture("07_licao_chrome")


func _fake_lesson() -> Lesson:
	var l := Lesson.new()
	l.lesson_id = 3
	l.nome_exercicio = "Cumprimentos"
	var sinais: Array[Dictionary] = [
		{"nome_sinal": "bom dia", "json_sinal": {}},
		{"nome_sinal": "boa noite", "json_sinal": {}},
	]
	l.sinais = sinais
	return l
