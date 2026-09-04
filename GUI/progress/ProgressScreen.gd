extends Control
## Tela de progresso: nível, XP, ofensiva, métricas e conquistas.
##
## Substitui a `PlayerStats.tscn` legada, que era inalcançável (navegava para
## `res://Screens/...`, caminho que não existe) e exibia "—" em todos os
## quatro cards porque nada alimentava os dados. Aqui tudo vem de `Global`.

@onready var header_slot: HBoxContainer = %Header
@onready var content: VBoxContainer = %Content
@onready var nav: BottomNav = %Nav


func _ready() -> void:
	var header := AppHeader.new()
	header.title = "Seu progresso"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.back_pressed.connect(func() -> void: Global.go_to_main_scene())
	header_slot.add_child(header)

	nav.tab_selected.connect(_on_nav)
	nav.active = &"progress"

	_build_level_card()
	_build_metrics()
	_build_achievements()

	Motion.stagger_in(content.get_children())


# ------------------------------------------------------------
#  nível + XP
# ------------------------------------------------------------

func _build_level_card() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardHero"
	# Sem PASS o card ocuparia o topo do ScrollContainer como zona morta.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", DS.SPACE_SM)
	card.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", DS.SPACE_SM)
	box.add_child(top)

	var level_box := VBoxContainer.new()
	level_box.add_theme_constant_override("separation", 0)
	level_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(level_box)

	var eyebrow := Label.new()
	eyebrow.theme_type_variation = &"OnPrimaryMuted"
	eyebrow.text = "NÍVEL"
	level_box.add_child(eyebrow)

	var level := Label.new()
	level.theme_type_variation = &"OnPrimaryH1"
	level.text = str(Global.get_level())
	level_box.add_child(level)

	var streak: int = Global.get_streak()
	if streak > 0:
		var flame := HSIcon.new()
		flame.icon = HSIcon.Name.FLAME
		flame.color = DS.GOLD
		flame.custom_minimum_size = Vector2(64, 64)
		flame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(flame)

		var streak_lbl := Label.new()
		streak_lbl.theme_type_variation = &"OnPrimaryH2"
		streak_lbl.text = "%d" % streak
		streak_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(streak_lbl)

	var bar := ProgressBar.new()
	bar.theme_type_variation = &"ProgressBarOnDark"
	bar.custom_minimum_size = Vector2(0, 26)
	bar.max_value = 1.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)
	Motion.fill_bar(bar, Global.get_level_progress())

	var caption := Label.new()
	caption.theme_type_variation = &"OnPrimaryMuted"
	caption.text = "%d / %d XP para o nível %d" % [
		Global.get_xp_into_level(), Global.XP_PER_LEVEL, Global.get_level() + 1]
	box.add_child(caption)


# ------------------------------------------------------------
#  métricas
# ------------------------------------------------------------

func _build_metrics() -> void:
	content.add_child(_section_title("Números"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", DS.SPACE_SM)
	grid.add_theme_constant_override("v_separation", DS.SPACE_SM)
	content.add_child(grid)

	grid.add_child(MetricCard.create(HSIcon.Name.BOLT,
		str(Global.get_xp()), "XP total", DS.VIOLET_INK))

	grid.add_child(MetricCard.create(HSIcon.Name.LESSONS,
		str(Global.count_completed_lessons()), "Lições concluídas", DS.PRIMARY))

	grid.add_child(MetricCard.create(HSIcon.Name.STAR,
		str(Global.get_mastered_signs()), "Sinais dominados", DS.GOLD_INK))

	# Precisão média só aparece depois da primeira prática — antes disso o
	# número honesto é "ainda não sabemos", não "0%".
	var precision: float = Global.get_average_precision()
	grid.add_child(MetricCard.create(HSIcon.Name.TARGET,
		"%d%%" % int(round(precision * 100.0)) if precision >= 0.0 else "—",
		"Precisão média", DS.ACCENT_INK))

	grid.add_child(MetricCard.create(HSIcon.Name.CAMERA,
		str(Global.get_practice_count()), "Práticas gravadas", DS.PRIMARY))

	grid.add_child(MetricCard.create(HSIcon.Name.FLAME,
		str(Global.get_best_streak()), "Melhor ofensiva", DS.GOLD_INK))


# ------------------------------------------------------------
#  conquistas
# ------------------------------------------------------------

func _build_achievements() -> void:
	var all: Array[Dictionary] = Achievements.list()
	var unlocked: int = Achievements.unlocked_count()

	content.add_child(_section_title("Conquistas", "%d de %d" % [unlocked, all.size()]))

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", DS.SPACE_SM)
	content.add_child(list)

	# Desbloqueadas primeiro; entre as bloqueadas, as mais próximas antes.
	var sorted: Array[Dictionary] = all.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["unlocked"]) != bool(b["unlocked"]):
			return bool(a["unlocked"])
		return float(a["progress"]) > float(b["progress"]))

	for data: Dictionary in sorted:
		list.add_child(AchievementBadge.create(data))


func _section_title(text: String, trailing: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SPACE_SM)

	var lbl := Label.new()
	lbl.theme_type_variation = &"H2"
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	if not trailing.is_empty():
		var side := Label.new()
		side.theme_type_variation = &"Caption"
		side.text = trailing
		side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(side)

	return row


func _on_nav(id: StringName) -> void:
	match id:
		&"home":
			Global.go_to_main_scene()
		&"lessons":
			Global.go_to_map()
		&"practice":
			Global.go_to_lesson(Global.current_lesson_id)
		&"progress":
			nav.active = &"progress"
