@tool
class_name StarRow
extends HBoxContainer
## Nota de 0 a 3 estrelas.
##
## Substitui os Labels com "★"/"☆" que eram modulados na mão em três lugares
## diferentes. As estrelas ganhas entram em sequência, com um pequeno atraso
## entre elas — é a recompensa visual do resultado da lição.

const MAX_STARS := 3
## Atraso entre uma estrela e a próxima na animação de revelação. Público
## porque quem sonoriza o resultado precisa cair no mesmo compasso — som e
## imagem desencontrados são piores do que só imagem.
const REVEAL_STAGGER := 0.09

@export_range(0, 3) var stars: int = 0:
	set(v):
		stars = clampi(v, 0, MAX_STARS)
		_sync(false)

@export var star_size: int = 84:
	set(v):
		star_size = v
		_rebuild()

var _glyphs: Array[HSIcon] = []


static func create(value: int = 0, size_px: int = 84) -> StarRow:
	var row := StarRow.new()
	row.star_size = size_px
	row.stars = value
	return row


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", DS.SPACE_SM)
	_rebuild()


func _rebuild() -> void:
	for g: HSIcon in _glyphs:
		if is_instance_valid(g):
			g.queue_free()
	_glyphs.clear()

	for i in range(MAX_STARS):
		var g := HSIcon.new()
		g.icon = HSIcon.Name.STAR
		g.custom_minimum_size = Vector2(star_size, star_size)
		g.weight = 2.2
		add_child(g)
		_glyphs.append(g)

	_sync(false)


func _sync(animate: bool) -> void:
	for i in range(_glyphs.size()):
		var g: HSIcon = _glyphs[i]
		if not is_instance_valid(g):
			continue
		var earned: bool = i < stars
		g.filled = earned
		# Estrela não ganha fica vazada e apagada, nunca ausente: o usuário
		# precisa ver quantas ainda dá para conquistar.
		g.color = DS.GOLD if earned else DS.DISABLED
		if animate and earned:
			g.scale = Vector2.ZERO
			g.pivot_offset = g.custom_minimum_size * 0.5
			var t := g.create_tween()
			t.tween_interval(REVEAL_STAGGER * float(i))
			t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(g, "scale", Vector2.ONE, DS.DUR_BASE)
		else:
			g.scale = Vector2.ONE


## Define a nota com a animação de conquista.
func reveal(value: int) -> void:
	stars = clampi(value, 0, MAX_STARS)
	_sync(true)
