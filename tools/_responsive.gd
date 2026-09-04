extends SceneTree
## Renderiza as telas principais na proporção passada por `--resolution` e
## reporta o viewport LÓGICO resultante.
##
##   godot --resolution 506x900 --script res://tools/_responsive.gd -- 16x9
##
## Prova que `stretch/aspect = expand` entrega área útil em vez de barras
## pretas, e que ScreenFrame limita a largura quando sobra espaço horizontal.

const OUT_DIR := "user://shots_resp"

const FAKE_CATALOG: Array = [
	{"id": 1, "nome": "Alfabeto: A a E"},
	{"id": 2, "nome": "Alfabeto: F a J"},
	{"id": 3, "nome": "Cumprimentos"},
	{"id": 4, "nome": "Números 1 a 10"},
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	var args := OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() > 0 else "sem_nome"

	var g: Node = root.get_node_or_null("/root/Global")
	if g != null:
		g.reset_progress()
		g.mark_completed(1, 3)
		g.award_sign_result(1, 0, 3)
		g.register_practice(0.86)

	var win := DisplayServer.window_get_size()
	var vp := root.get_visible_rect().size
	print("%-12s janela %4dx%-4d  ->  viewport lógico %5dx%-5d" % [
		tag, win.x, win.y, int(vp.x), int(vp.y)])

	await _capture("res://GUI/Screens/Main/Main.tscn", "home_" + tag, true)
	await _capture("res://GUI/signshowcase/SignShowcaseState.tscn", "assista_" + tag, false)
	quit(0)


func _capture(path: String, out_name: String, is_home: bool) -> void:
	for c in root.get_children():
		if c.name not in ["Global", "LessonService", "MediaPipeExternalFiles", "GDMPAndroid"]:
			c.queue_free()
	await process_frame

	var inst: Node = (load(path) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	if is_home:
		await create_timer(1.0).timeout
		inst.call("_on_catalog_loaded", FAKE_CATALOG)
	else:
		inst.call("setup", _fake_lesson(), 0)

	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, out_name])


func _fake_lesson() -> Lesson:
	var l := Lesson.new()
	l.lesson_id = 3
	l.nome_exercicio = "Cumprimentos"
	var sinais: Array[Dictionary] = [{"nome_sinal": "bom dia", "json_sinal": {}}]
	l.sinais = sinais
	return l
