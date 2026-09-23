extends VisionTask

var package_name := "mediapipe.tasks.vision.holistic_landmarker"
## O caminho é o do bundle oficial, usado só como URL de fallback pelo
## download do GDMP. O que o app carrega de verdade é o repack em
## `res://assets/mediapipe/` — pose full e sem os modelos de face. Ver
## `tools/montar_bundle_holistico.py`.
var task_file := "holistic_landmarker/holistic_landmarker/float16/latest/holistic_landmarker.task"
var task_runner := MediaPipeTaskRunner.new()
var renderer: MediaPipeHolisticRenderer

@onready var lbl_blendshapes: Label = $VBoxContainer/Image/Blendshapes

var capture_timer: Timer
var capture_active := false
## true somente após task_runner.initialize() — enviar frames antes disso
## gera um erro do MediaPipe por frame de câmera.
var _task_initialized := false
## Backend com que o grafo atual subiu. Difere da preferência do usuário
## quando a GPU não pôde ser usada.
var active_backend: Global.InferenceBackend = Global.InferenceBackend.CPU
## Sonda de GPU aberta esperando veredito. Só o primeiro resultado que a GPU
## entregar fecha como sucesso — ver `Global.end_gpu_probe`.
var _gpu_probe_open := false

# ─────────────────────────────────────────────
#  MEDIÇÃO DE DESEMPENHO
# ─────────────────────────────────────────────
#
# Duas grandezas independentes, porque elas têm donos diferentes:
#   * readback — custo de main thread para tirar o quadro do SubViewport e
#     converter o formato. Não muda com o backend de inferência.
#   * resultados/s — o que o pipeline realmente entrega. É o número que
#     decide se GPU vale a pena.
# O log sai só em build de debug e só enquanto há quadros entrando.

const PERF_REPORT_INTERVAL_MS := 3000

## `_packets_callback` roda em thread do GDMP, então este contador pode
## perder uma contagem numa corrida. Para uma taxa média em janela de 3 s
## isso não muda a conclusão, e a alternativa (mutex ou `call_deferred` por
## quadro) custaria justamente no caminho que se quer medir.
## Último fechamento da janela de medição, retido para o painel de depuração
## poder mostrar os mesmos números que a linha [perf] imprime. Vazio até a
## primeira janela fechar. Ver `_maybe_report_performance`.
var last_perf: Dictionary = {}
var _perf_results: int = 0
var _perf_submitted: int = 0
var _perf_latency_ms_total: int = 0
var _perf_window_started_ms: int = 0
var capture_started_at_ms := 0
var capture_first_packet_ms := -1
var capture_frames: Array = []
var capture_frame_index := 0
@export var capture_duration_seconds := 10.0
var capture_output_path := ""

signal landmarks_detected
## Emitido quando a câmera ativa muda (após start_camera_with_feed).
signal camera_changed(feed_name: String)
## Emitido a cada (re)inicialização bem-sucedida do grafo, com o backend que
## de fato subiu — que pode não ser o pedido, se a GPU falhou.
signal inference_backend_ready(backend: Global.InferenceBackend)
## Emitido quando a câmera começa a transmitir quadros reais.
signal camera_ready

var is_camera_ready: bool = false
var camera_frames_count: int = 0
var _inference_paused: bool = false

# ─────────────────────────────────────────────
#  CONTROLE DE RENDER DO OVERLAY (performance)
# ─────────────────────────────────────────────

## Quando true, o renderer do overlay roda. Quando false, o pipeline
## ainda detecta landmarks (e captura no _collect_frame) mas pula o
## render visual — economiza CPU quando não há preview na tela.
var render_overlay_enabled: bool = true

## Intervalo mínimo entre renders consecutivos do overlay, em ms.
## Mesmo com render_overlay_enabled=true, frames vindo mais rápido que
## isso são pulados. Default = ~33ms (~30fps cap).
var render_overlay_min_interval_ms: int = 33

## Tolerância máxima entre timestamps dos packets de entrada do renderer.
## Frames com divergência maior são descartados sem chamar render()
## (previne o erro "inconsistent timestamps" do AnnotationOverlayCalculator).
var render_timestamp_tolerance_us: int = 5000  # 5ms

var _last_render_at_ms: int = 0

func _ready() -> void:
	running_mode = MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM
	super()
	# Trocar o backend em Configurações no meio de uma lição refaz o grafo
	# aqui mesmo — sem isso a escolha só valeria na próxima abertura do app.
	Global.inference_backend_changed.connect(_on_inference_backend_changed)
	capture_timer = Timer.new()
	capture_timer.one_shot = true
	add_child(capture_timer)
	capture_timer.timeout.connect(_on_capture_timeout)


## Garante que o runner de Live Stream do MediaPipe está pronto antes de iniciar o exercício.
func ensure_task_initialized() -> void:
	if not _task_initialized:
		running_mode = MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM
		_init_task()


func _ensure_monitoring_feeds() -> void:
	if not CameraServer.monitoring_feeds:
		CameraServer.monitoring_feeds = true
	_initialize_camera_extension()


func _on_inference_backend_changed(_backend: Global.InferenceBackend) -> void:
	_init_task()


func _reset() -> void:
	capture_active = false
	capture_frames.clear()
	capture_frame_index = 0
	capture_first_packet_ms = -1
	is_camera_ready = false
	camera_frames_count = 0
	if capture_timer and not capture_timer.is_stopped():
		capture_timer.stop()
	super()

func _start_camera() -> void:
	super()

## O CameraFeed vive no CameraServer (fora da árvore de cena): se ninguém
## desativar, a câmera continua ligada depois desta cena morrer.
func _exit_tree() -> void:
	super()
	# Saímos vivos, mas talvez sem nenhum quadro ter passado pela GPU: fecha
	# a sonda sem veredito em vez de vetar quem nunca chegou a ser testado.
	if _gpu_probe_open:
		_gpu_probe_open = false
		Global.cancel_gpu_probe()
	if camera_feed != null:
		camera_feed.feed_is_active = false


# ─────────────────────────────────────────────
#  PAUSA / RETOMADA DO FEED (bateria + GPU)
# ─────────────────────────────────────────────

## Pausa a inferência e processamento pesado fora da gravação.
## Mantém o feed da câmera ativo para evitar renegociação lenta de hardware (2-4s)
## ao transicionar entre etapas.
func pause_camera() -> void:
	render_overlay_enabled = false
	_inference_paused = true


## Retoma a inferência da câmera e garante feed ativo.
func resume_camera() -> void:
	_inference_paused = false
	render_overlay_enabled = true
	if camera_feed == null:
		return
	if not camera_feed.frame_changed.is_connected(self._camera_frame_changed):
		_start_camera()
	elif not camera_feed.feed_is_active:
		camera_feed.feed_is_active = true


# ═══════════════════════════════════════════════════════════
#  API PÚBLICA — SELEÇÃO E PREVIEW DE CÂMERA
# ═══════════════════════════════════════════════════════════

## Lista todas as câmeras disponíveis no sistema.
## Retorna Array de Dictionary: [{ id, name, position, formats }, ...]
## position: "front" | "back" | "unspecified"
func list_available_cameras() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_ensure_monitoring_feeds()
	var feeds: Array[CameraFeed] = CameraServer.feeds()
	for feed in feeds:
		var pos_str := "unspecified"
		match feed.get_position():
			CameraFeed.FEED_FRONT: pos_str = "front"
			CameraFeed.FEED_BACK:  pos_str = "back"
		result.append({
			"id": feed.get_id(),
			"name": feed.get_name(),
			"position": pos_str,
			"formats": feed.get_formats(),
		})
	return result


## Escolhe a "melhor" câmera disponível seguindo:
##   1. Preferência por câmera frontal (selfie)
##   2. Senão, a primeira disponível
## Retorna o id da câmera escolhida, ou -1 se nenhuma disponível.
func pick_best_camera_id() -> int:
	var cameras := list_available_cameras()
	if cameras.is_empty():
		return -1

	for cam in cameras:
		if cam.get("position", "") == "front":
			return int(cam.get("id", -1))

	return int(cameras[0].get("id", -1))


## Inicia a captura usando a câmera de id especificado.
## Para a câmera anterior, escolhe a nova, seleciona o melhor formato
## e ativa o feed. Retorna true em caso de sucesso.
func start_camera_with_feed(feed_id: int, format_index: int = -1) -> bool:
	# Para qualquer captura/feed anterior
	_reset()

	# Encontra o CameraFeed correspondente
	var feeds: Array[CameraFeed] = CameraServer.feeds()
	var target: CameraFeed = null
	for feed in feeds:
		if feed.get_id() == feed_id:
			target = feed
			break

	if target == null:
		push_warning("Nenhum CameraFeed encontrado para id=%d" % feed_id)
		return false

	camera_feed = target

	# Escolhe o formato — se não especificado, pega o último (geralmente
	# o de maior resolução).
	var formats: Array = camera_feed.get_formats()
	if formats.is_empty():
		push_warning("Câmera '%s' não expõe formatos" % camera_feed.get_name())
		return false

	var idx := format_index
	if idx < 0 or idx >= formats.size():
		idx = _pick_reasonable_format_index(formats)

	# A resolução não muda o custo da inferência (o ImageToTensor
	# redimensiona para o tamanho fixo do modelo), mas muda a QUALIDADE das
	# mãos: o recorte da mão sai do quadro em resolução nativa, e a 720p uma
	# mão a um braço de distância já vem sendo ampliada para caber no tensor.
	# O log diz o que o aparelho ofereceu, para essa escolha ser decidida com
	# dado em vez de palpite.
	if OS.is_debug_build():
		var catalogo: PackedStringArray = PackedStringArray()
		for i in range(formats.size()):
			var fmt: Dictionary = formats[i] as Dictionary
			catalogo.append("%s%dx%d" % [
				"*" if i == idx else "", int(fmt.get("width", 0)), int(fmt.get("height", 0))])
		print("[camera] %s formatos (* = escolhido): %s" %
			[camera_feed.get_name(), ", ".join(catalogo)])

	if not camera_feed.set_format(idx, {}):
		push_warning("Falha ao setar formato %d para câmera '%s'" % [idx, camera_feed.get_name()])
		return false

	_start_camera()
	camera_changed.emit(camera_feed.get_name())
	return true


## Heurística pra escolher um formato razoável: prefere ~720p, senão
## o do meio da lista.
func _pick_reasonable_format_index(formats: Array) -> int:
	var best_idx := -1
	var best_diff := INF
	for i in range(formats.size()):
		var f: Dictionary = formats[i] as Dictionary
		var w: int = int(f.get("width", 0))
		var h: int = int(f.get("height", 0))
		if w == 0 or h == 0:
			continue
		var diff: float = absf(float(h) - 720.0)
		if diff < best_diff:
			best_diff = diff
			best_idx = i
	if best_idx >= 0:
		return best_idx
	return formats.size() / 2


## Textura crua da câmera (sem overlay de landmarks), já convertida
## (shader YCbCr→RGB no Android), rotacionada e espelhada pelo viewport.
## camera_texture.texture NÃO serve aqui: no caminho YCbCr ela é apenas
## uma ImageTexture placeholder — a imagem real é a saída do SubViewport.
func get_camera_texture() -> Texture2D:
	if camera_viewport != null:
		return camera_viewport.get_texture()
	return null


## Textura com overlay de landmarks renderizado (atualizada a cada frame
## processado). Pode estar null nos primeiros frames.
func get_annotated_texture() -> Texture2D:
	if image_view != null:
		return image_view.texture
	return null


## Útil pra UI: nome legível da câmera atualmente ativa.
func get_active_camera_name() -> String:
	if camera_feed != null:
		return camera_feed.get_name()
	return ""


## Útil pra preview espelhar quando a câmera é frontal.
func is_active_camera_front() -> bool:
	if camera_feed == null:
		return false
	return camera_feed.get_position() == CameraFeed.FEED_FRONT


## Retorna true se a câmera estiver ativamente enviando quadros.
func is_camera_streaming() -> bool:
	return camera_feed != null and camera_feed.feed_is_active and is_camera_ready


## Aguarda de forma assíncrona a câmera estar pronta e entregando quadros.
## Possui timeout seguro para não travar em ambientes sem câmera (ex: testes unitários ou permissão negada).
func wait_for_camera_ready(timeout_seconds: float = 6.0) -> bool:
	if is_camera_streaming():
		return true

	_ensure_monitoring_feeds()

	var deadline_ms: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)

	# 1. Aguarda feeds serem descobertos pelo sistema operacional
	# Em sistemas Windows/Android a enumeração de hardware pode demorar até 1.5 - 2s
	while CameraServer.feeds().is_empty() and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame

	if CameraServer.feeds().is_empty():
		push_warning("[HolisticLandmarker] Nenhuma câmera física encontrada após aguardar enumeração")
		return false

	# 2. Seleciona e inicia a melhor câmera se ainda não tiver feito
	if camera_feed == null:
		var best_id: int = pick_best_camera_id()
		if best_id >= 0:
			if not start_camera_with_feed(best_id):
				push_warning("[HolisticLandmarker] Falha ao iniciar câmera id=%d" % best_id)
				return false
		else:
			return false
	elif not camera_feed.feed_is_active:
		resume_camera()

	# 3. Aguarda a câmera começar a entregar quadros reais (is_camera_ready == true)
	while not is_camera_streaming() and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame

	return is_camera_streaming()


# ═══════════════════════════════════════════════════════════
#  CAPTURA (lógica original com travas de segurança)
# ═══════════════════════════════════════════════════════════

const MAX_CAPTURE_FRAMES: int = 360 # ~12 segundos a 30fps

func _begin_capture(tempo: float) -> void:
	# Garante o feed vivo: um _reset anterior (cancelamento) o desativa e
	# desconecta os sinais; sem isso a captura gravaria 0 frames.
	resume_camera()

	capture_frames.clear()
	capture_frame_index = 0
	capture_first_packet_ms = -1
	capture_started_at_ms = Time.get_ticks_msec()
	capture_active = true

	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	capture_output_path = "user://anim_cache/holistic_capture_%s.json" % stamp

	var safe_tempo: float = clampf(tempo, 1.0, 15.0) if tempo > 0.0 else 10.0
	if capture_timer and not capture_timer.is_stopped():
		capture_timer.stop()
	capture_timer.wait_time = safe_tempo
	capture_timer.start()

	print_debug("Captura iniciada por: %.2f segundos" % safe_tempo)


## Interrompe e finaliza imediatamente a gravação ativa.
func stop_capture() -> void:
	if not capture_active:
		return
	capture_active = false
	if capture_timer and not capture_timer.is_stopped():
		capture_timer.stop()
	_export_capture_json()


func _on_capture_timeout() -> void:
	stop_capture()

## Roda na thread de callbacks do GDMP. Um resultado chegando é a única
## prova de que o delegate sobreviveu à abertura dos nós; o veredito vai
## para a main thread porque fechar a sonda grava arquivo.
func _packets_callback(outputs: Dictionary) -> void:
	_perf_results += 1
	# Latência ponta a ponta sem estado compartilhado entre threads: o
	# timestamp do pacote é o `Time.get_ticks_msec()` carimbado na
	# submissão, então a subtração fecha aqui dentro mesmo.
	if outputs.has("image_out"):
		var out_packet: MediaPipePacket = outputs["image_out"]
		if out_packet != null:
			_perf_latency_ms_total += Time.get_ticks_msec() - int(out_packet.timestamp / 1000)
	if _gpu_probe_open:
		_confirm_gpu_probe.call_deferred()
	show_result(outputs)


func _confirm_gpu_probe() -> void:
	if not _gpu_probe_open:
		return
	_gpu_probe_open = false
	Global.end_gpu_probe(true)

func _init_task() -> void:
	var file := get_external_model(task_file)
	if file == null:
		# request != null significa download em andamento (fluxo legítimo:
		# _init_task será chamado de novo no callback). Sem download, o
		# modelo simplesmente não existe — falha alta e única.
		if request == null:
			push_error(
				"HolisticLandmarker: modelo '%s' não encontrado (esperado em %s ou user://GDMP). Sem ele não há detecção." %
				[task_file, Global.BUNDLED_MODEL_DIR])
		return

	var model := file.get_buffer(file.get_length())

	var async := false
	if running_mode == MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM:
		async = true

	if not task_runner.packets_callback.is_connected(self._packets_callback):
		task_runner.packets_callback.connect(self._packets_callback)

	# Enquanto o runner novo não subir, nenhum quadro deve entrar: um
	# `send` no meio da troca é erro do MediaPipe por quadro de câmera.
	_task_initialized = false

	# Uma sonda da montagem anterior que ficou sem resposta não vale como
	# falha: o grafo está sendo trocado, não travou.
	if _gpu_probe_open:
		_gpu_probe_open = false
		Global.cancel_gpu_probe()

	var wanted := Global.resolve_inference_backend()

	# A tentativa de GPU fica cercada por uma sonda gravada em disco: se o
	# delegate derrubar o processo, o boot seguinte encontra a sonda aberta
	# e nem tenta de novo (ver `Global.begin_gpu_probe`).
	if wanted == Global.InferenceBackend.GPU:
		Global.begin_gpu_probe()
		_gpu_probe_open = true

	var ok := _try_initialize(model, wanted, async)

	# O delegate GPU depende de driver: quando o kGpuService não pode ser
	# criado, `initialize` devolve false. Antes o retorno era ignorado e o
	# nó seguia se dizendo pronto — câmera ligada, zero landmark, nenhum
	# aviso. Cair para a CPU é o comportamento certo.
	#
	# `ok == true` NÃO fecha a sonda: o delegate GL abre os nós na thread
	# dele e o segfault chega depois do initialize já ter voltado. Quem
	# fecha é o primeiro resultado, em `_packets_callback`.
	if wanted == Global.InferenceBackend.GPU and not ok:
		_gpu_probe_open = false
		Global.end_gpu_probe(false)
		push_warning(
			"HolisticLandmarker: delegate GPU indisponível neste aparelho; caindo para CPU.")
		wanted = Global.InferenceBackend.CPU
		ok = _try_initialize(model, wanted, async)

	if not ok:
		push_error("HolisticLandmarker: não foi possível inicializar o grafo. Sem detecção.")
		return

	active_backend = wanted
	# Trocar de backend no meio da sessão: a janela de medição em curso tem
	# quadros do backend antigo dentro. Recomeça, senão a primeira linha do
	# backend novo sai misturada.
	_perf_window_started_ms = 0
	_task_initialized = true
	renderer = MediaPipeHolisticRenderer.new()
	inference_backend_ready.emit(active_backend)
	super()


## Monta o grafo com o backend pedido e tenta subir o runner.
## Devolve false quando o MediaPipe recusa a configuração.
func _try_initialize(model: PackedByteArray, backend: Global.InferenceBackend, async: bool) -> bool:
	var options := MediaPipeProto.new()
	options.initialize(package_name + ".proto.HolisticLandmarkerGraphOptions")
	options.set_field("base_options/model_asset/file_content", model)
	_apply_acceleration(options, backend)

	var builder := MediaPipeGraphBuilder.new()
	var node := builder.add_node(package_name + ".HolisticLandmarkerGraph")
	node.set_options(options)

	builder.get_input_tag("IMAGE").connect_to(node.get_input_tag("IMAGE"), "image_in")
	node.get_output_tag("POSE_LANDMARKS").connect_to(builder.get_output_tag("POSE_LANDMARKS"), "pose_landmarks")
	node.get_output_tag("LEFT_HAND_LANDMARKS").connect_to(builder.get_output_tag("LEFT_HAND_LANDMARKS"), "left_hand_landmarks")
	node.get_output_tag("RIGHT_HAND_LANDMARKS").connect_to(builder.get_output_tag("RIGHT_HAND_LANDMARKS"), "right_hand_landmarks")
	node.get_output_tag("IMAGE").connect_to(builder.get_output_tag("IMAGE"), "image_out")

	# `delegate` (herdado da VisionTask) decide o formato do pixel que o
	# `_camera_frame_changed` entrega: RGBA8 para o caminho GL, RGB8 para a
	# CPU. Ele precisa acompanhar o backend real, senão o grafo GPU recebe
	# um quadro sem canal alfa para subir como textura.
	delegate = (MediaPipeTaskBaseOptions.DELEGATE_GPU if backend == Global.InferenceBackend.GPU
		else MediaPipeTaskBaseOptions.DELEGATE_CPU)

	if backend == Global.InferenceBackend.GPU:
		# Com acceleration/gpu os nós de inferência passam a exigir o
		# kGpuService. Sem passar recursos aqui o MediaPipe tenta criá-los
		# sozinho e, se o EGL do aparelho não colaborar, o grafo inteiro
		# falha em vez de só a inferência.
		return task_runner.initialize(builder.get_config(), async, {}, MediaPipeGPUResources.new())

	return task_runner.initialize(builder.get_config(), async)


## Escreve `base_options/acceleration`. O campo é um oneof: gravar uma folha
## dentro de `gpu` ou de `xnnpack` já seleciona o ramo correspondente.
##
## `use_advanced_gpu_api` não é detalhe: ele escolhe entre os DOIS caminhos de
## GPU do InferenceCalculator.
##   false → TfLiteGpuDelegate. Recusa os `DEQUANTIZE` do bundle float16
##           esparso, particiona o modelo e morre com SIGSEGV em
##           `densify::Prepare` (S23 Ultra e desktop, mesma assinatura).
##   true  → TFLiteGPURunner, implementação do próprio MediaPipe, que nem
##           passa pelo delegate do TFLite. Sobrevive ao mesmo bundle.
## O valor default do proto é false — ou seja, pedir GPU "do jeito óbvio"
## cai no caminho que quebra.
func _apply_acceleration(options: MediaPipeProto, backend: Global.InferenceBackend) -> void:
	if backend == Global.InferenceBackend.GPU:
		options.set_field(
			"base_options/acceleration/gpu/use_advanced_gpu_api", Global.GPU_ADVANCED_API)
		return
	options.set_field(
		"base_options/acceleration/xnnpack/num_threads", Global.get_inference_cpu_threads())

func _process_image(image: Image) -> void:
	var input_image := MediaPipeImage.new()
	input_image.set_image(image)
	var packet := input_image.get_packet()
	var outputs := task_runner.process({"image_in": packet})
	show_result(outputs)

func _process_video(image: Image, timestamp_ms: int) -> void:
	var input_image := MediaPipeImage.new()
	input_image.set_image(image)
	var packet := input_image.get_packet()
	packet.timestamp = timestamp_ms * 1000
	var outputs := task_runner.process({"image_in": packet})
	show_result(outputs)

const INFERENCE_TARGET_FPS: float = 30.0
const MIN_INFERENCE_INTERVAL_MS: int = 33
const MAX_INFLIGHT_FRAMES: int = 1
const MIN_READBACK_INTERVAL_MS: int = 30

var _last_inference_submitted_ms: int = 0
var _last_readback_ms: int = 0


func _camera_frame_changed() -> void:
	# Economia massiva de CPU/GPU: se a inferência estiver pausada (durante exibição do avatar 3D)
	# e a câmera já foi confirmada pronta, não faz o readback pesado GPU->CPU a 60-120fps.
	if _inference_paused and is_camera_ready:
		return

	# Limita taxa de readback de textura na CPU para ~30 FPS
	var now_ms: int = Time.get_ticks_msec()
	if (now_ms - _last_readback_ms) < MIN_READBACK_INTERVAL_MS:
		return
	_last_readback_ms = now_ms

	super._camera_frame_changed()


func _process_camera(image: MediaPipeImage, timestamp_ms: int) -> void:
	camera_frames_count += 1
	if not is_camera_ready:
		is_camera_ready = true
		camera_ready.emit()

	if not _task_initialized or _inference_paused:
		return   # sem modelo ou em modo de economia, apenas mantém a câmera aquecida

	var now_ms: int = Time.get_ticks_msec()

	# 1. Throttling de taxa de quadros (não sobrecarregar CPU/GPU acima de 30 FPS)
	if (now_ms - _last_inference_submitted_ms) < MIN_INFERENCE_INTERVAL_MS:
		return

	# 2. Backpressure / Drop-if-busy: se o MediaPipe ainda estiver ocupado processando
	# o quadro anterior na thread C++, descarta este quadro para evitar estouro de memória (1.7 GB) e lag.
	var in_flight: int = _perf_submitted - _perf_results
	if in_flight > MAX_INFLIGHT_FRAMES:
		return

	_last_inference_submitted_ms = now_ms
	_perf_submitted += 1
	_maybe_report_performance()
	var packet := image.get_packet()
	packet.timestamp = timestamp_ms * 1000
	task_runner.send({"image_in": packet})


## Main thread, chamado por quadro de câmera. Fecha a janela de medição a
## cada PERF_REPORT_INTERVAL_MS e imprime uma linha.
func _maybe_report_performance() -> void:
	if not OS.is_debug_build():
		return

	var now_ms := Time.get_ticks_msec()
	if _perf_window_started_ms == 0:
		_perf_window_started_ms = now_ms
		_reset_performance_window()
		return

	var elapsed_ms := now_ms - _perf_window_started_ms
	if elapsed_ms < PERF_REPORT_INTERVAL_MS:
		return

	var seconds := float(elapsed_ms) / 1000.0
	var readback_ms := 0.0
	if perf_readback_frames > 0:
		readback_ms = (float(perf_readback_us) / float(perf_readback_frames)) / 1000.0

	var frame_size := Vector2i.ZERO
	if camera_viewport != null:
		frame_size = camera_viewport.size

	var latency_ms := 0.0
	if _perf_results > 0:
		latency_ms = float(_perf_latency_ms_total) / float(_perf_results)

	# Retido antes de zerar a janela: sem isto os números só existem dentro
	# desta linha de print, e o painel de depuração não teria o que mostrar.
	last_perf = {
		"backend": Global.inference_backend_label(active_backend),
		"entrada_fps": float(_perf_submitted) / seconds,
		"resultados_fps": float(_perf_results) / seconds,
		"latencia_ms": latency_ms,
		"readback_ms": readback_ms,
		"quadro": frame_size,
	}

	print(("[perf] backend=%s  entrada=%.1f fps  resultados=%.1f fps  "
		+ "latencia=%.0f ms  readback=%.1f ms/quadro  quadro=%dx%d") % [
		last_perf["backend"],
		last_perf["entrada_fps"],
		last_perf["resultados_fps"],
		latency_ms,
		readback_ms,
		frame_size.x, frame_size.y,
	])

	_perf_window_started_ms = now_ms
	_reset_performance_window()


func _reset_performance_window() -> void:
	_perf_submitted = 0
	_perf_results = 0
	_perf_latency_ms_total = 0
	perf_readback_us = 0
	perf_readback_frames = 0

func show_result(outputs: Dictionary) -> void:
	# Coleta de frames pra captura é independente do render visual.
	if capture_active:
		_collect_frame(outputs)

	# A partir daqui é só render do overlay — pode ser pulado.
	if not render_overlay_enabled:
		return

	# Throttling temporal: respeita um intervalo mínimo entre renders.
	var now_ms: int = Time.get_ticks_msec()
	if (now_ms - _last_render_at_ms) < render_overlay_min_interval_ms:
		return

	if not outputs.has("image_out"):
		return

	var image_packet: MediaPipePacket = outputs["image_out"]
	var image_ts: int = image_packet.timestamp

	# Verifica que todos os landmarks usam o mesmo timestamp (dentro da
	# tolerância). Se algum divergir, pula o frame em vez de chamar render
	# (que falharia com "inconsistent timestamps").
	if not _timestamps_compatible(outputs, image_ts):
		return

	var packets := {}
	var image := image_packet.get() as MediaPipeImage
	packets["input_image"] = image.get_image_frame_packet()
	packets["input_image"].timestamp = image_ts

	if outputs.has("pose_landmarks"):
		packets["pose_landmarks"] = outputs["pose_landmarks"]
	if outputs.has("left_hand_landmarks"):
		packets["left_hand_landmarks"] = outputs["left_hand_landmarks"]
	if outputs.has("right_hand_landmarks"):
		packets["right_hand_landmarks"] = outputs["right_hand_landmarks"]

	var output_image := renderer.render(packets)
	if output_image == null:
		return

	_last_render_at_ms = now_ms
	update_image(output_image.image)


## Verifica se todos os packets relevantes têm timestamp dentro da
## tolerância em relação ao image_ts. Retorna false se algum divergir.
func _timestamps_compatible(outputs: Dictionary, image_ts: int) -> bool:
	var keys := ["pose_landmarks", "left_hand_landmarks", "right_hand_landmarks"]
	for k: Variant in keys:
		if not outputs.has(k):
			continue
		var p: MediaPipePacket = outputs[k]
		if p == null:
			continue
		if absi(p.timestamp - image_ts) > render_timestamp_tolerance_us:
			return false
	return true

## Roda na thread de callbacks do GDMP: extrai os dados do packet aqui
## (timestamps precisos) mas delega o append à main thread — mutar
## capture_frames de duas threads corrompia/derrubava a captura.
func _collect_frame(outputs: Dictionary) -> void:
	var timestamp_ms := Time.get_ticks_msec() - capture_started_at_ms

	if outputs.has("image_out"):
		var image_packet: MediaPipePacket = outputs["image_out"]
		var packet_ms := int(image_packet.timestamp / 1000)
		if capture_first_packet_ms < 0:
			capture_first_packet_ms = packet_ms
		timestamp_ms = packet_ms - capture_first_packet_ms

	var hands: Array = []

	var left_hand := _build_hand_entry(outputs, "left_hand_landmarks", "Left")
	if not left_hand.is_empty():
		hands.append(left_hand)

	var right_hand := _build_hand_entry(outputs, "right_hand_landmarks", "Right")
	if not right_hand.is_empty():
		hands.append(right_hand)

	var pose: Array = []
	if outputs.has("pose_landmarks"):
		var pose_landmarks := _extract_landmarks_from_packet(outputs["pose_landmarks"])
		if not pose_landmarks.is_empty():
			pose.append({
				"landmarks": pose_landmarks
			})

	_append_capture_frame.call_deferred({
		"timestamp_ms": timestamp_ms,
		"hands": hands,
		"pose": pose
	})


## Main thread. Frames que chegam depois do fim/reset da captura são
## descartados (antes eles vazavam pra dentro do export em andamento).
func _append_capture_frame(frame_entry: Dictionary) -> void:
	if not capture_active:
		return
	frame_entry["frame"] = capture_frame_index
	capture_frames.append(frame_entry)
	capture_frame_index += 1

	# Trava de segurança: impede acúmulo descontrolado de quadros na memória
	if capture_frames.size() >= MAX_CAPTURE_FRAMES:
		push_warning("[HolisticLandmarker] Limite máximo de quadros (%d) atingido. Finalizando captura." % MAX_CAPTURE_FRAMES)
		stop_capture()

func _build_hand_entry(outputs: Dictionary, key: String, handedness: String) -> Dictionary:
	if not outputs.has(key):
		return {}

	var landmarks := _extract_landmarks_from_packet(outputs[key])
	if landmarks.is_empty():
		return {}

	return {
		"handedness": handedness,
		"confidence": 1.0,
		"landmarks": landmarks
	}

func _extract_landmarks_from_packet(packet: Variant) -> Array:
	if packet == null:
		return []

	if packet is MediaPipePacket:
		return _extract_landmarks_from_value(packet.get())

	return _extract_landmarks_from_value(packet)

func _extract_landmarks_from_value(value: Variant) -> Array:
	if value == null:
		return []

	if value is Array:
		if value.is_empty():
			return []

		if _looks_like_landmark(value[0]):
			return _convert_landmark_array(value)

		for item: Variant in value:
			var nested := _extract_landmarks_from_value(item)
			if not nested.is_empty():
				return nested
		return []

	if value is Dictionary:
		if value.has("landmark"):
			return _extract_landmarks_from_value(value["landmark"])
		if value.has("landmarks"):
			return _extract_landmarks_from_value(value["landmarks"])
		if _looks_like_landmark(value):
			return [_landmark_to_dict(value, 0)]
		return []

	if value is Object and value.has_method("get_field"):
		var landmark_list: Variant = value.get_field("landmark")
		if landmark_list != null:
			return _extract_landmarks_from_value(landmark_list)

		var landmarks: Variant  = value.get_field("landmarks")
		if landmarks != null:
			return _extract_landmarks_from_value(landmarks)

		if _looks_like_landmark(value):
			return [_landmark_to_dict(value, 0)]

	return []

func _convert_landmark_array(items: Array) -> Array:
	var result: Array = []
	for i in range(items.size()):
		result.append(_landmark_to_dict(items[i], i))
	return result

func _landmark_to_dict(item: Variant, index: int) -> Dictionary:
	return {
		"id": index,
		"x": _field_or_null(item, "x"),
		"y": _field_or_null(item, "y"),
		"z": _field_or_null(item, "z"),
		"visibility": _field_or_null(item, "visibility"),
		"presence": _field_or_null(item, "presence")
	}

func _looks_like_landmark(value: Variant) -> bool:
	var x: Variant = _field_or_null(value, "x")
	var y: Variant = _field_or_null(value, "y")
	var z: Variant = _field_or_null(value, "z")
	return x != null and y != null and z != null

func _field_or_null(value: Variant, field_name: String) -> Variant:
	if value == null:
		return null

	if value is Dictionary:
		return value.get(field_name, null)

	if value is Object and value.has_method("get_field"):
		return value.get_field(field_name)

	return null

func _export_capture_json() -> void:
	var source_name := "camera"
	if camera_feed != null:
		source_name = camera_feed.get_name()

	var fps := 0.0
	if capture_frames.size() > 1:
		var last_timestamp_ms: int = capture_frames[capture_frames.size() - 1]["timestamp_ms"]
		if last_timestamp_ms > 0:
			# n frames cobrem n-1 intervalos (antes superestimava o fps).
			fps = float(capture_frames.size() - 1) / (float(last_timestamp_ms) / 1000.0)

	# Câmeras frontais/webcams alimentam o MediaPipe com imagem espelhada
	# (flip de selfie do SubViewport). Canonicaliza para a convenção dos
	# gabaritos (não-espelhada, rótulos anatômicos) — sem isso, o sinal
	# feito com a mão direita é comparado contra a mão errada do gabarito.
	var mirrored_input: bool = camera_texture != null and camera_texture.flip_h
	var frames_out: Array = capture_frames
	if mirrored_input:
		frames_out = CaptureMirror.mirror_frames(capture_frames)

	var export_data := {
		"video_info": {
			"source": source_name,
			"total_frames": frames_out.size(),
			"fps": fps,
			"canonicalized_from_mirrored": mirrored_input,
		},
		"frames": frames_out
	}

	# Garante que o diretório existe (user:// é writable em build exportada)
	var dir_path := capture_output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file := FileAccess.open(capture_output_path, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível criar o arquivo JSON em: " + capture_output_path)
	else:
		file.store_string(JSON.stringify(export_data, "\t"))
		file.close()
		print("JSON exportado em: ", ProjectSettings.globalize_path(capture_output_path))

	emit_signal("landmarks_detected", export_data)

func show_blendshapes(classifications: Array) -> void:
	lbl_blendshapes.text = ""
	for classification: Variant in classifications:
		var score: Variant = classification.get_field("score")
		var label: Variant = classification.get_field("label")
		if score >= 0.5:
			lbl_blendshapes.text += "%s: %.2f\n" % [label, score]
