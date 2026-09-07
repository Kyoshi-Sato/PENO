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
	Motion.attach_press(btn_close)


## cameras: array vindo de HolisticLandmarker.list_available_cameras()
## current_id: id da câmera atualmente ativa (pra destacar) — -1 se nenhuma
func populate(cameras: Array, current_id: int = -1) -> void:
	_current_id = current_id

	for child in list.get_children():
		child.queue_free()

	if cameras.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"BodyMuted"
		empty.text = "Nenhuma câmera disponível"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
		return

	for cam: Variant  in cameras:
		list.add_child(_build_camera_row(cam))


func _build_camera_row(cam: Dictionary) -> Control:
	var feed_id := int(cam.get("id", -1))
	var is_current := feed_id == _current_id

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, DS.TOUCH_MIN)
	btn.theme_type_variation = &"SecondaryButton" if not is_current else &"PrimaryButton"
	btn.focus_mode = Control.FOCUS_NONE

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", DS.SPACE_SM)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.offset_left = DS.SPACE_MD
	row.offset_right = -DS.SPACE_MD
	btn.add_child(row)

	# Câmera frontal e traseira eram diferenciadas por emojis de celular
	# ("📱", "📷", "🎥"), que além de fora da família de ícones nem sempre
	# renderizam no Android. O ícone é o mesmo dos dois lados; o que muda é
	# o rótulo, que já diz "frontal" ou "traseira".
	var glyph := HSIcon.new()
	glyph.icon = HSIcon.Name.CAMERA
	glyph.color = DS.TEXT_ON_PRIMARY if is_current else DS.PRIMARY
	glyph.custom_minimum_size = Vector2(52, 52)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)

	var lbl := Label.new()
	lbl.text = _camera_label(cam, feed_id)
	lbl.theme_type_variation = &"H3"
	lbl.add_theme_color_override("font_color",
		DS.TEXT_ON_PRIMARY if is_current else DS.TEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	if is_current:
		var check := HSIcon.new()
		check.icon = HSIcon.Name.CHECK
		check.color = DS.TEXT_ON_PRIMARY
		check.custom_minimum_size = Vector2(52, 52)
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(check)

	# Mesmo retorno de toque do resto do app: sem isto as linhas de câmera
	# seriam os únicos botões grandes que não respondem ao dedo.
	Motion.attach_press(btn)
	btn.pressed.connect(func() -> void:
		camera_selected.emit(feed_id)
		hide()
	)
	return btn


func _camera_label(cam: Dictionary, feed_id: int) -> String:
	var name_str := String(cam.get("name", "Câmera %d" % feed_id))
	match String(cam.get("position", "")):
		"front":
			return "%s (frontal)" % name_str
		"back":
			return "%s (traseira)" % name_str
	return name_str
