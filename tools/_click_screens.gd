extends SceneTree
## Clica em cada card da trilha DENTRO das telas reais (Home e Trilha), com
## ScrollContainer, ScreenFrame e Outer no caminho do evento.
##
## As conexões originais são desligadas para o clique não navegar no meio do
## teste; no lugar delas entra um ouvinte que só registra o id recebido.

const FAKE_CATALOG: Array = [
	{"id": 1, "nome": "Alfabeto: A a E"},
	{"id": 2, "nome": "Alfabeto: F a J"},
	{"id": 3, "nome": "Cumprimentos"},
	{"id": 4, "nome": "Números 1 a 10"},
]

var _got: Array[int] = []


func _init() -> void:
	root.set_content_scale_size(Vector2i(1080, 1920))
	root.set_content_scale_mode(Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	await process_frame

	var g: Node = root.get_node_or_null("/root/Global")
	if g != null:
		g.reset_progress()
		g.mark_completed(1, 3)

	var failures: int = 0
	failures += await _check("Home", "res://GUI/Screens/Main/Main.tscn")
	failures += await _check("Trilha", "res://GUI/lessonmap/LessonMapScreen.tscn")
	failures += await _audit("Home", "res://GUI/Screens/Main/Main.tscn")
	failures += await _audit("Trilha", "res://GUI/lessonmap/LessonMapScreen.tscn")
	failures += await _audit("Progresso", "res://GUI/progress/ProgressScreen.tscn")

	print("\n--- problemas: %d ---" % failures)
	quit(1 if failures > 0 else 0)


func _check(label: String, path: String) -> int:
	for c in root.get_children():
		if c.name not in ["Global", "LessonService", "MediaPipeExternalFiles", "GDMPAndroid"]:
			c.queue_free()
	await process_frame

	var screen: Node = (load(path) as PackedScene).instantiate()
	root.add_child(screen)
	await process_frame
	await create_timer(1.2).timeout          # deixa a API real responder
	screen.call("_on_catalog_loaded", FAKE_CATALOG)
	await create_timer(0.8).timeout          # espera a animação de entrada

	var nodes: Array[Node] = screen.find_children("*", "LessonNode", true, false)
	print("\n[%s] %d cards na trilha" % [label, nodes.size()])

	var lost: int = 0
	for n: Node in nodes:
		var node := n as LessonNode
		# Desliga a navegação real e escuta só para medir.
		for conn: Dictionary in node.pressed.get_connections():
			node.pressed.disconnect(conn["callable"])
		node.pressed.connect(func(id: int) -> void: _got.append(id))

		var p := _card_point(node)
		_got.clear()
		var hovered := await _click(p)
		await process_frame

		var locked: bool = node.state == LessonNode.State.LOCKED
		var ok: bool = (_got.size() > 0) if not locked else (_got.size() == 0)
		if not ok:
			lost += 1
		print("  lição %d  %-9s -> %-8s | sob o cursor: %s" % [
			node.lesson_id, _state_name(node.state),
			("RECEBEU" if _got.size() > 0 else "sem sinal"), hovered])

	return lost


## Varre TODO Button visível da tela e confere se ele é mesmo quem está sob o
## cursor no próprio centro. Um botão coberto por conteúdo com
## MOUSE_FILTER_STOP aparece aqui como ocluso — foi exatamente esse o defeito
## dos cards da trilha.
func _audit(label: String, path: String) -> int:
	for c in root.get_children():
		if c.name not in ["Global", "LessonService", "MediaPipeExternalFiles", "GDMPAndroid"]:
			c.queue_free()
	await process_frame

	var screen: Node = (load(path) as PackedScene).instantiate()
	root.add_child(screen)
	await process_frame
	if screen.has_method("_on_catalog_loaded"):
		await create_timer(1.2).timeout
		screen.call("_on_catalog_loaded", FAKE_CATALOG)
	await create_timer(0.8).timeout

	var bad: int = 0
	var total: int = 0
	print("\n[%s] auditoria de oclusão" % label)
	for b: Node in screen.find_children("*", "Button", true, false):
		var button := b as Button
		if not button.is_visible_in_tree() or button.disabled:
			continue
		var r := button.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		if not root.get_visible_rect().intersects(r):
			continue   # fora da tela (rolagem) — não dá para clicar mesmo
		total += 1

		var hovered := await _hover(r.get_center())
		if hovered != button and not button.is_ancestor_of(hovered):
			bad += 1
			var who: String = "(nenhum)"
			if hovered != null:
				who = "%s (%s)" % [hovered.name, hovered.get_class()]
			print("  OCLUSO: %s coberto por %s" % [_describe(button), who])

	print("  %d botões visíveis, %d oclusos" % [total, bad])
	return bad


func _hover(canvas_point: Vector2) -> Control:
	var p: Vector2 = root.get_final_transform() * canvas_point
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	root.push_input(mm)
	await process_frame
	return root.gui_get_hovered_control()


func _describe(b: Button) -> String:
	if not b.text.is_empty():
		return '"%s"' % b.text
	return "%s <%s>" % [b.name, b.theme_type_variation]


## Ponto no meio do card, à direita da coluna do trilho.
func _card_point(node: LessonNode) -> Vector2:
	var r := node.get_global_rect()
	return Vector2(r.position.x + LessonNode.RAIL_WIDTH + r.size.x * 0.3,
		r.position.y + r.size.y * 0.5)


func _click(canvas_point: Vector2) -> String:
	var p: Vector2 = root.get_final_transform() * canvas_point

	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	root.push_input(mm)
	await process_frame

	var hovered: Control = root.gui_get_hovered_control()
	var label: String = "(nenhum)"
	if hovered != null:
		label = "%s (%s)" % [hovered.name, hovered.get_class()]

	for pressed_state: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed_state
		ev.position = p
		ev.global_position = p
		root.push_input(ev)
		await process_frame

	return label


func _state_name(s: int) -> String:
	match s:
		LessonNode.State.DONE: return "DONE"
		LessonNode.State.CURRENT: return "CURRENT"
		LessonNode.State.AVAILABLE: return "AVAILABLE"
	return "LOCKED"
