@tool
extends Node

func _ready() -> void:
	# Só no editor (não no Play)
	if not Engine.is_editor_hint():
		return

	# Defer pra evitar rodar no meio do carregamento
	call_deferred("_generate_theme")


func _generate_theme() -> void:
	var theme := Theme.new()

	# Font size
	theme.default_font_size = 18

	# --------- Colors ----------
	var text := Color(0.30, 0.26, 0.23, 1)
	theme.set_color("font_color", "Label", text)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.06))

	theme.set_color("font_color", "Button", text)
	theme.set_color("font_hover_color", "Button", Color(0.26, 0.22, 0.20, 1))
	theme.set_color("font_pressed_color", "Button", Color(0.22, 0.19, 0.17, 1))
	theme.set_color("font_disabled_color", "Button", Color(0.30, 0.26, 0.23, 0.35))

	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("placeholder_color", "LineEdit", Color(0.30, 0.26, 0.23, 0.35))
	theme.set_color("font_color", "TextEdit", text)
	theme.set_color("font_color", "ProgressBar", Color(0.30, 0.26, 0.23, 0.85))

	# --------- Styles ----------
	theme.set_stylebox("panel", "PanelContainer", _sb_card())
	theme.set_stylebox("panel", "Panel", _sb_base_panel())

	theme.set_stylebox("normal", "Button", _sb_button("#F3EBE3"))
	theme.set_stylebox("hover", "Button", _sb_button("#F6EEE7", 14, 6))
	theme.set_stylebox("pressed", "Button", _sb_button("#EBCFC8", 6, 2))
	theme.set_stylebox("disabled", "Button", _sb_button("#F3EBE3"))

	theme.set_stylebox("normal", "OptionButton", theme.get_stylebox("normal", "Button"))
	theme.set_stylebox("hover", "OptionButton", theme.get_stylebox("hover", "Button"))
	theme.set_stylebox("pressed", "OptionButton", theme.get_stylebox("pressed", "Button"))
	theme.set_stylebox("disabled", "OptionButton", theme.get_stylebox("disabled", "Button"))

	theme.set_stylebox("normal", "LineEdit", _sb_input(false))
	theme.set_stylebox("focus", "LineEdit", _sb_input(true))

	theme.set_stylebox("normal", "TextEdit", _sb_input(false))
	theme.set_stylebox("focus", "TextEdit", _sb_input(true))

	theme.set_stylebox("background", "ProgressBar", _sb_progress_bg())
	theme.set_stylebox("fill", "ProgressBar", _sb_progress_fill())
	theme.set_constant("min_height", "ProgressBar", 18)

	# --------- Save ----------
	var dir_path := "res://themes"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var path := "res://themes/libras_soft.tres"
	var err := ResourceSaver.save(theme, path)
	if err != OK:
		push_error("Falha ao salvar Theme: %s" % err)
	else:
		print("Theme salvo em: ", path)


# =========================
# Helpers (fora da função!)
# =========================
func _sb_card() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#FBF8F4")
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.6)
	sb.set_corner_radius_all(28)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 8)
	sb.shadow_color = Color(0.35, 0.30, 0.26, 0.12)
	sb.content_margin_left = 20
	sb.content_margin_top = 16
	sb.content_margin_right = 20
	sb.content_margin_bottom = 16
	return sb

func _sb_base_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#F7F2EB")
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.55)
	sb.set_corner_radius_all(26)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 6)
	sb.shadow_color = Color(0.35, 0.30, 0.26, 0.10)
	sb.content_margin_left = 18
	sb.content_margin_top = 14
	sb.content_margin_right = 18
	sb.content_margin_bottom = 14
	return sb

func _sb_button(normal_hex: String, shadow_size := 12, shadow_y := 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(normal_hex)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.7)
	sb.set_corner_radius_all(22)
	sb.shadow_size = shadow_size
	sb.shadow_offset = Vector2(0, shadow_y)
	sb.shadow_color = Color(0.35, 0.30, 0.26, 0.12)
	sb.content_margin_left = 18
	sb.content_margin_top = 12
	sb.content_margin_right = 18
	sb.content_margin_bottom = 12
	return sb

func _sb_input(focused := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#FBF8F4")
	sb.set_corner_radius_all(20)
	sb.shadow_size = 10 if not focused else 12
	sb.shadow_offset = Vector2(0, 4) if not focused else Vector2(0, 5)
	sb.shadow_color = Color(0.35, 0.30, 0.26, 0.10 if not focused else 0.12)
	sb.content_margin_left = 16
	sb.content_margin_top = 10
	sb.content_margin_right = 16
	sb.content_margin_bottom = 10
	if focused:
		sb.set_border_width_all(2)
		sb.border_color = Color(0.86, 0.70, 0.55, 0.55)
	else:
		sb.set_border_width_all(1)
		sb.border_color = Color(0.85, 0.79, 0.73, 0.25)
	return sb

func _sb_progress_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#F0E8DF")
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 6
	sb.content_margin_top = 6
	sb.content_margin_right = 6
	sb.content_margin_bottom = 6
	return sb

func _sb_progress_fill() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#BDD4B3")
	sb.set_corner_radius_all(999)
	return sb
