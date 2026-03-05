extends VisionTask

var package_name := "mediapipe.tasks.vision.holistic_landmarker"
var task_file := "holistic_landmarker/holistic_landmarker/float16/latest/holistic_landmarker.task"
var task_runner := MediaPipeTaskRunner.new()
var renderer: MediaPipeHolisticRenderer
@onready var lbl_blendshapes: Label = $VBoxContainer/Image/Blendshapes

func _packets_callback(outputs: Dictionary) -> void:
	show_result(outputs)
	processing = false

func _init_task() -> void:
	var file := get_external_model(task_file)
	if file == null:
		return
	var options := MediaPipeProto.new()
	options.initialize(package_name+".proto.HolisticLandmarkerGraphOptions")
	options.set_field("base_options/model_asset/file_content", file.get_buffer(file.get_length()))
	var builder := MediaPipeGraphBuilder.new()
	var node := builder.add_node(package_name+".HolisticLandmarkerGraph")
	node.set_options(options)
	builder.get_input_tag("IMAGE").connect_to(node.get_input_tag("IMAGE"), "image_in")
	node.get_output_tag("POSE_LANDMARKS").connect_to(builder.get_output_tag("POSE_LANDMARKS"), "pose_landmarks")
	node.get_output_tag("LEFT_HAND_LANDMARKS").connect_to(builder.get_output_tag("LEFT_HAND_LANDMARKS"), "left_hand_landmarks")
	node.get_output_tag("RIGHT_HAND_LANDMARKS").connect_to(builder.get_output_tag("RIGHT_HAND_LANDMARKS"), "right_hand_landmarks")
	node.get_output_tag("FACE_LANDMARKS").connect_to(builder.get_output_tag("FACE_LANDMARKS"), "face_landmarks")
	node.get_output_tag("FACE_BLENDSHAPES").connect_to(builder.get_output_tag("FACE_BLENDSHAPES"), "face_blendshapes")
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

var processing := false

func _process_camera(image: MediaPipeImage, timestamp_ms: int) -> void:
	if processing:
		return

	processing = true

	var packet := image.get_packet()
	packet.timestamp = timestamp_ms * 1000
	task_runner.send({"image_in": packet})

func show_result(outputs: Dictionary) -> void:
	var packets := {}
	if outputs.has("image_out"):
		var packet: MediaPipePacket = outputs["image_out"]
		var image: = packet.get() as MediaPipeImage
		packets["input_image"] = image.get_image_frame_packet()
		packets["input_image"].timestamp = packet.timestamp
	#if outputs.has("face_landmarks"):
		#packets["face_landmarks"] = outputs["face_landmarks"]
	if outputs.has("pose_landmarks"):
		packets["pose_landmarks"] = outputs["pose_landmarks"]
	if outputs.has("left_hand_landmarks"):
		packets["left_hand_landmarks"] = outputs["left_hand_landmarks"]
	if outputs.has("right_hand_landmarks"):
		packets["right_hand_landmarks"] = outputs["right_hand_landmarks"]
	var output_image := renderer.render(packets)
	debug_print_landmarks(packets)
	if output_image == null:
		return
	update_image(output_image.image)

func debug_print_landmarks(packets: Dictionary) -> void:
	var keys: Array[String] = [
		"pose_landmarks",
		"left_hand_landmarks",
		"right_hand_landmarks",
		"face_landmarks"
	]

	for key in keys:
		if not packets.has(key):
			continue

		print("\n===== ", key, " =====")

		var packet: MediaPipePacket = packets[key]
		if packet == null:
			continue

		var proto: Variant = packet.get()
		if proto == null:
			continue

		var landmarks : Variant = proto.get_field("landmark")
		if landmarks == null:
			print("Sem landmarks")
			continue

		print("Total landmarks:", landmarks.size())

		for i in range(landmarks.size()):
			var lm: Variant = landmarks[i]

			var x: Variant = lm.get_field("x")
			var y: Variant = lm.get_field("y")
			var z: Variant = lm.get_field("z")

			var visibility: Variant = lm.get_field("visibility")
			var presence: Variant = lm.get_field("presence")

			print("ID:", i,
				" x:", x,
				" y:", y,
				" z:", z,
				" vis:", visibility,
				" pres:", presence
			)

func packets_to_json_dict(packets: Dictionary) -> Dictionary:
	var result := {}

	var keys: Array[String] = [
		"pose_landmarks",
		"left_hand_landmarks",
		"right_hand_landmarks",
	]

	for key in keys:
		if not packets.has(key):
			continue

		var packet: MediaPipePacket = packets[key]
		if packet == null:
			continue

		var proto: Variant = packet.get()
		if proto == null:
			continue

		var landmarks: Variant = proto.get_field("landmark")
		if landmarks == null:
			continue

		var landmark_array := []

		for i in range(landmarks.size()):
			var lm: Variant = landmarks[i]

			landmark_array.append({
				"id": i,
				"x": lm.get_field("x"),
				"y": lm.get_field("y"),
				"z": lm.get_field("z"),
				"visibility": lm.get_field("visibility"),
				"presence": lm.get_field("presence")
			})

		result[key] = landmark_array

	return result

func show_blendshapes(classifications: Array) -> void:
	lbl_blendshapes.text = ""
	for classification: Variant  in classifications:
		var score: Variant = classification.get_field("score")
		var label: Variant  = classification.get_field("label")
		if score >= 0.5:
			lbl_blendshapes.text += "%s: %.2f\n" % [label, score]
