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

func _ready() -> void:
	super()
	capture_timer = Timer.new()
	capture_timer.one_shot = true
	capture_timer.wait_time = capture_duration_seconds
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
	_begin_capture()

func _begin_capture() -> void:
	capture_frames.clear()
	capture_frame_index = 0
	capture_first_packet_ms = -1
	capture_started_at_ms = Time.get_ticks_msec()
	capture_active = true

	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	capture_output_path = "user://holistic_capture_%s.json" % stamp

	if capture_timer and not capture_timer.is_stopped():
		capture_timer.stop()
	capture_timer.start()

	print("Captura iniciada por 10 segundos.")

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
	#node.get_output_tag("FACE_LANDMARKS").connect_to(builder.get_output_tag("FACE_LANDMARKS"), "face_landmarks")
	#node.get_output_tag("FACE_BLENDSHAPES").connect_to(builder.get_output_tag("FACE_BLENDSHAPES"), "face_blendshapes")
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

	var file := FileAccess.open(capture_output_path, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível criar o arquivo JSON em: " + capture_output_path)
		return

	file.store_string(JSON.stringify(export_data, "\t"))
	file.close()

	print("JSON exportado em: ", ProjectSettings.globalize_path(capture_output_path))

func show_blendshapes(classifications: Array) -> void:
	lbl_blendshapes.text = ""
	for classification: Variant in classifications:
		var score: Variant = classification.get_field("score")
		var label: Variant = classification.get_field("label")
		if score >= 0.5:
			lbl_blendshapes.text += "%s: %.2f\n" % [label, score]
