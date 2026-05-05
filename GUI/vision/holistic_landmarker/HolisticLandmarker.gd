extends VisionTask

var package_name := "mediapipe.tasks.vision.holistic_landmarker"
var task_file := "holistic_landmarker/holistic_landmarker/float16/latest/holistic_landmarker.task"
var task_runner := MediaPipeTaskRunner.new()
var renderer: MediaPipeHolisticRenderer

@onready var lbl_blendshapes: Label = $VBoxContainer/Image/Blendshapes

var capture_timer: Timer
var capture_active := false
var capture_started_at_ms := 0
var capture_first_packet_ms := -1
var capture_frames: Array = []
var capture_frame_index := 0
@export var capture_duration_seconds := 10.0
var capture_output_path := ""

signal landmarks_detected
## Emitido quando a câmera ativa muda (após start_camera_with_feed).
signal camera_changed(feed_name: String)

func _ready() -> void:
	super()
	capture_timer = Timer.new()
	capture_timer.one_shot = true
	add_child(capture_timer)
	capture_timer.timeout.connect(_on_capture_timeout)

func _reset() -> void:
	capture_active = false
	capture_frames.clear()
	capture_frame_index = 0
	capture_first_packet_ms = -1
	if capture_timer and not capture_timer.is_stopped():
		capture_timer.stop()
	super()

func _start_camera() -> void:
	super()


# ═══════════════════════════════════════════════════════════
#  API PÚBLICA — SELEÇÃO E PREVIEW DE CÂMERA
# ═══════════════════════════════════════════════════════════

## Lista todas as câmeras disponíveis no sistema.
## Retorna Array de Dictionary: [{ id, name, position, formats }, ...]
## position: "front" | "back" | "unspecified"
func list_available_cameras() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not CameraServer.monitoring_feeds:
		CameraServer.monitoring_feeds = true
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


## Textura crua da câmera (sem overlay de landmarks).
func get_camera_texture() -> Texture2D:
	if camera_texture != null:
		return camera_texture.texture
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


# ═══════════════════════════════════════════════════════════
#  CAPTURA (lógica original)
# ═══════════════════════════════════════════════════════════

func _begin_capture(tempo: float) -> void:
	capture_frames.clear()
	capture_frame_index = 0
	capture_first_packet_ms = -1
	capture_started_at_ms = Time.get_ticks_msec()
	capture_active = true

	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	capture_output_path = "user://anim_cache/holistic_capture_%s.json" % stamp

	if capture_timer and not capture_timer.is_stopped():
		capture_timer.stop()
	capture_timer.wait_time = tempo
	capture_timer.start()

	print_debug("Captura iniciada por: %.2f segundos" % tempo)

func _on_capture_timeout() -> void:
	capture_active = false
	_export_capture_json()

func _packets_callback(outputs: Dictionary) -> void:
	show_result(outputs)

func _init_task() -> void:
	var file := get_external_model(task_file)
	if file == null:
		return

	var options := MediaPipeProto.new()
	options.initialize(package_name + ".proto.HolisticLandmarkerGraphOptions")
	options.set_field("base_options/model_asset/file_content", file.get_buffer(file.get_length()))

	var builder := MediaPipeGraphBuilder.new()
	var node := builder.add_node(package_name + ".HolisticLandmarkerGraph")
	node.set_options(options)

	builder.get_input_tag("IMAGE").connect_to(node.get_input_tag("IMAGE"), "image_in")
	node.get_output_tag("POSE_LANDMARKS").connect_to(builder.get_output_tag("POSE_LANDMARKS"), "pose_landmarks")
	node.get_output_tag("LEFT_HAND_LANDMARKS").connect_to(builder.get_output_tag("LEFT_HAND_LANDMARKS"), "left_hand_landmarks")
	node.get_output_tag("RIGHT_HAND_LANDMARKS").connect_to(builder.get_output_tag("RIGHT_HAND_LANDMARKS"), "right_hand_landmarks")
	node.get_output_tag("IMAGE").connect_to(builder.get_output_tag("IMAGE"), "image_out")

	var config := builder.get_config()
	var async := false
	if running_mode == MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM:
		async = true

	if not task_runner.packets_callback.is_connected(self._packets_callback):
		task_runner.packets_callback.connect(self._packets_callback)

	task_runner.initialize(config, async)
	renderer = MediaPipeHolisticRenderer.new()
	super()

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

func _process_camera(image: MediaPipeImage, timestamp_ms: int) -> void:
	var packet := image.get_packet()
	packet.timestamp = timestamp_ms * 1000
	task_runner.send({"image_in": packet})

func show_result(outputs: Dictionary) -> void:
	if capture_active:
		_collect_frame(outputs)

	var packets := {}

	if outputs.has("image_out"):
		var packet: MediaPipePacket = outputs["image_out"]
		var image := packet.get() as MediaPipeImage
		packets["input_image"] = image.get_image_frame_packet()
		packets["input_image"].timestamp = packet.timestamp

	if outputs.has("pose_landmarks"):
		packets["pose_landmarks"] = outputs["pose_landmarks"]

	if outputs.has("left_hand_landmarks"):
		packets["left_hand_landmarks"] = outputs["left_hand_landmarks"]

	if outputs.has("right_hand_landmarks"):
		packets["right_hand_landmarks"] = outputs["right_hand_landmarks"]

	var output_image := renderer.render(packets)
	if output_image == null:
		return

	update_image(output_image.image)

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

	capture_frames.append({
		"frame": capture_frame_index,
		"timestamp_ms": timestamp_ms,
		"hands": hands,
		"pose": pose
	})

	capture_frame_index += 1

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
			fps = float(capture_frames.size()) / (float(last_timestamp_ms) / 1000.0)

	var export_data := {
		"video_info": {
			"source": source_name,
			"total_frames": capture_frames.size(),
			"fps": fps
		},
		"frames": capture_frames
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
