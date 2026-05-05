class_name CameraSelectorDialog
extends Window
## Popup com a lista de câmeras disponíveis. Quando o usuário escolhe
## uma, emite `camera_selected(feed_id)` e fecha.
##
## Uso:
##   dialog.populate(holistic.list_available_cameras(), holistic.camera_feed.get_id() if holistic.camera_feed else -1)
##   dialog.popup_centered()
##   await dialog.camera_selected
##
## A LessonScreen escuta o signal e chama holistic.start_camera_with_feed(id).

signal camera_selected(feed_id: int)

@onready var list: VBoxContainer = %CameraList
@onready var btn_close: Button = %CloseButton

var _current_id: int = -1


func _ready() -> void:
	close_requested.connect(hide)
	btn_close.pressed.connect(hide)


## cameras: array vindo de HolisticLandmarker.list_available_cameras()
## current_id: id da câmera atualmente ativa (pra destacar) — -1 se nenhuma
func populate(cameras: Array, current_id: int = -1) -> void:
	_current_id = current_id

	for child in list.get_children():
		child.queue_free()

	if cameras.is_empty():
		var empty := Label.new()
		empty.text = "Nenhuma câmera disponível"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 32)
		list.add_child(empty)
		return

	for cam: Variant  in cameras:
		list.add_child(_build_camera_row(cam))


func _build_camera_row(cam: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 100)
	btn.add_theme_font_size_override("font_size", 32)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var feed_id := int(cam.get("id", -1))
	var name_str := String(cam.get("name", "Câmera %d" % feed_id))
	var pos_str := String(cam.get("position", ""))

	var prefix := ""
	match pos_str:
		"front": prefix = "📱  "  # selfie
		"back":  prefix = "📷  "  # traseira
		_:       prefix = "🎥  "

	var suffix := ""
	if feed_id == _current_id:
		suffix = "  ✓"

	btn.text = "%s%s%s" % [prefix, name_str, suffix]
	btn.pressed.connect(func() -> void:
		camera_selected.emit(feed_id)
		hide()
	)
	return btn
