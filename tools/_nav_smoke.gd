extends SceneTree
## Exercita as trocas de tela reais e mede quanto tempo cada uma leva.
## Serve para conferir que a transição não trava nem fica presa no véu.

func _init() -> void:
	root.set_content_scale_size(Vector2i(1080, 1920))
	root.set_content_scale_mode(Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	await process_frame
	await process_frame

	var g: Node = root.get_node_or_null("/root/Global")
	if g == null:
		print("Global indisponível")
		quit(1)
		return

	var route: Array[String] = [
		g.MAIN_SCENE, g.MAP_SCENE, g.PROGRESS_SCENE,
		g.MAIN_SCENE, g.LESSON_SCENE, g.MAIN_SCENE,
	]

	for path: String in route:
		var t0 := Time.get_ticks_msec()
		g.change_scene(path)
		# Espera a transição inteira terminar (o guard volta a false no fim).
		var guard := 0
		while bool(g._is_changing) and guard < 1200:
			await process_frame
			guard += 1
		var dt := Time.get_ticks_msec() - t0
		var scene_name := "—"
		if current_scene != null:
			scene_name = current_scene.name
		print("%-52s %5d ms  -> %s%s" % [
			path.get_file(), dt, scene_name,
			"   [TRAVOU]" if guard >= 1200 else ""])

	print("rota concluída")
	quit(0)
