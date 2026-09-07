extends SceneTree
## Mede o custo por quadro do grafo holístico em cada configuração de
## aceleração. Foi com ele que se descobriu que o grafo rodava sem nenhuma
## aceleração declarada — e que isso significa XNNPACK de UMA thread.
##
## Uso:
##   godot --headless -s res://tools/_bench_inferencia.gd -- <modo> [iters] [imagem]
##   modo: "cpu" (nada declarado) | "xnn<N>" (N threads)
##         | "gpu" (TfLiteGpuDelegate — SEGFAULTA, ver Global.GPU_ADVANCED_API)
##         | "gpuadv" (TFLiteGPURunner, o caminho que funciona)
##
## Cuidado com "gpu" no headless: o único GL disponível é o llvmpipe, e o
## delegate GL derruba o processo nele em vez de devolver erro.
##
## Medido nesta máquina (quadro 720p vazio — só o detector de pose roda,
## pois sem pessoa o resto do grafo fica fechado):
##   cpu / xnn1 .... 18,9 ms      xnn4 ....  6,0 ms
##   xnn2 .......... 10,4 ms      xnn8 ....  4,0 ms
##
## A resolução da entrada não muda esse número: o ImageToTensor redimensiona
## para o tamanho fixo do modelo (512x512 e 1280x720 deram o mesmo tempo).
## O que a resolução encarece é o readback da textura do lado da Godot.

const PKG := "mediapipe.tasks.vision.holistic_landmarker"
const TASK := "res://assets/mediapipe/holistic_landmarker.task"

var runner := MediaPipeTaskRunner.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "cpu"
	var iters: int = int(args[1]) if args.size() > 1 else 25
	var img_path: String = args[2] if args.size() > 2 else ""

	var t0 := Time.get_ticks_usec()
	var ok := _build(mode)
	print("[%s] init ok=%s em %.1f ms" % [mode, ok, (Time.get_ticks_usec() - t0) / 1000.0])
	if not ok:
		quit()
		return

	var mp := MediaPipeImage.new()
	mp.set_image(_input_image(img_path))

	var times: Array[float] = []
	for i in range(iters):
		var packet := mp.get_packet()
		packet.timestamp = (i + 1) * 33000
		var t := Time.get_ticks_usec()
		var out := runner.process({"image_in": packet})
		times.append((Time.get_ticks_usec() - t) / 1000.0)
		if i == 0:
			print("  detectado: %s" % [_detected(out)])

	times.sort()
	var total := 0.0
	for v in times:
		total += v
	print("[%s] n=%d  media=%.1f ms  mediana=%.1f ms  min=%.1f  max=%.1f" %
		[mode, iters, total / iters, times[iters / 2], times[0], times[-1]])
	quit()


func _build(mode: String) -> bool:
	var file := FileAccess.open(TASK, FileAccess.READ)
	if file == null:
		print("modelo não encontrado em ", TASK)
		return false

	var options := MediaPipeProto.new()
	options.initialize(PKG + ".proto.HolisticLandmarkerGraphOptions")
	options.set_field("base_options/model_asset/file_content", file.get_buffer(file.get_length()))
	if mode == "gpu":
		options.set_field("base_options/acceleration/gpu/use_advanced_gpu_api", false)
	elif mode == "gpuadv":
		options.set_field("base_options/acceleration/gpu/use_advanced_gpu_api", true)
	elif mode.begins_with("xnn"):
		options.set_field("base_options/acceleration/xnnpack/num_threads", int(mode.substr(3)))

	var builder := MediaPipeGraphBuilder.new()
	var node := builder.add_node(PKG + ".HolisticLandmarkerGraph")
	node.set_options(options)
	builder.get_input_tag("IMAGE").connect_to(node.get_input_tag("IMAGE"), "image_in")
	node.get_output_tag("POSE_LANDMARKS").connect_to(
		builder.get_output_tag("POSE_LANDMARKS"), "pose_landmarks")
	node.get_output_tag("LEFT_HAND_LANDMARKS").connect_to(
		builder.get_output_tag("LEFT_HAND_LANDMARKS"), "left_hand_landmarks")
	node.get_output_tag("RIGHT_HAND_LANDMARKS").connect_to(
		builder.get_output_tag("RIGHT_HAND_LANDMARKS"), "right_hand_landmarks")
	node.get_output_tag("IMAGE").connect_to(builder.get_output_tag("IMAGE"), "image_out")

	if mode.begins_with("gpu"):
		return runner.initialize(builder.get_config(), false, {}, MediaPipeGPUResources.new())
	return runner.initialize(builder.get_config(), false)


func _input_image(path: String) -> Image:
	if path != "":
		var loaded := Image.load_from_file(path)
		loaded.convert(Image.FORMAT_RGB8)
		print("  imagem: ", loaded.get_size())
		return loaded
	var blank := Image.create_empty(1280, 720, false, Image.FORMAT_RGB8)
	blank.fill(Color(0.45, 0.4, 0.38))
	return blank


func _detected(out: Dictionary) -> Array:
	var found: Array = []
	for k: String in ["pose_landmarks", "left_hand_landmarks", "right_hand_landmarks"]:
		if out.has(k) and out[k] != null and out[k].get() != null:
			found.append(k)
	return found
