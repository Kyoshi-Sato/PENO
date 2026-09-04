extends SceneTree
## Verifica o fluxo da splash: aquecimento -> Home, com captura da splash.
##
## A splash é montada à mão porque `--script` substitui o MainLoop e a
## `main_scene` do projeto nunca chega a ser instanciada neste modo.

func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://shots"))

	var splash: Node = (load("res://GUI/splash/SplashScreen.tscn") as PackedScene).instantiate()
	root.add_child(splash)
	await process_frame
	await process_frame

	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png("user://shots/00_splash.png")
	print("splash capturada")

	var t0 := Time.get_ticks_msec()
	var guard: int = 0
	while guard < 900:
		if current_scene != null and String(current_scene.name) == "Main":
			break
		await process_frame
		guard += 1

	var landed: String = String(current_scene.name) if current_scene else "(nenhuma)"
	print("splash -> %s em %d ms" % [landed, Time.get_ticks_msec() - t0])

	var g: Node = root.get_node_or_null("/root/Global")
	print("cenas em cache após o boot: %d" % (g._scene_cache as Dictionary).size())

	var t1 := Time.get_ticks_msec()
	g.change_scene(g.MAP_SCENE)
	var g2: int = 0
	while bool(g._is_changing) and g2 < 600:
		await process_frame
		g2 += 1
	print("Home -> Trilha depois do aquecimento: %d ms" % (Time.get_ticks_msec() - t1))
	quit(0)
