extends SceneTree
## Fumaça do seletor de backend: monta o HolisticLandmarker de verdade,
## confere que o grafo sobe com aceleração declarada e que trocar a
## preferência em Configurações remonta o grafo.
##
## Uso: godot --headless -s res://tools/_backend_smoke.gd


func _init() -> void:
	await process_frame
	var g: Node = root.get_node_or_null("/root/Global")
	print("preferência: %s | resolvido: %s | threads: %d" % [
		g.inference_backend_label(g.get_inference_backend()),
		g.inference_backend_label(g.resolve_inference_backend()),
		g.get_inference_cpu_threads()])

	var holistic: Node = (load(
		"res://GUI/vision/holistic_landmarker/HolisticLandmarker.tscn") as PackedScene
	).instantiate()
	root.add_child(holistic)
	await process_frame

	print("grafo pronto: %s | backend ativo: %s" % [
		holistic._task_initialized,
		g.inference_backend_label(holistic.active_backend)])

	print("--- trocando para CPU explícito ---")
	g.set_inference_backend(g.InferenceBackend.CPU)
	await process_frame
	print("grafo pronto: %s | backend ativo: %s" % [
		holistic._task_initialized,
		g.inference_backend_label(holistic.active_backend)])

	# Só sob pedido: no headless o único GL disponível é o llvmpipe, e o
	# delegate GL derruba o processo nele em vez de devolver erro.
	if "gpu" in OS.get_cmdline_user_args():
		print("--- trocando para GPU explícito ---")
		g.set_inference_backend(g.InferenceBackend.GPU)
		await process_frame
		print("grafo pronto: %s | backend ativo: %s | gpu vetada: %s" % [
			holistic._task_initialized,
			g.inference_backend_label(holistic.active_backend),
			g.is_gpu_blocked()])

	print("--- diálogo de configurações ---")
	var dlg: Node = (load("res://GUI/settings/SettingsDialog.tscn") as PackedScene).instantiate()
	root.add_child(dlg)
	await process_frame
	var list: Node = dlg.get_node("%BackendList")
	print("opções renderizadas: %d" % list.get_child_count())
	for row: Button in list.get_children():
		var lbl: Label = row.get_child(0).get_child(0)
		var marked: bool = row.theme_type_variation == &"PrimaryButton"
		print("  [%s] %s" % ["x" if marked else " ", lbl.text])
	print("ajuda: %s" % dlg.get_node("%BackendHelp").text.replace("\n", " / "))

	g.set_inference_backend(g.InferenceBackend.AUTO)
	g.end_gpu_probe(true)
	quit()
