@abstract
class_name Motion
extends Object
## Microinterações do HandSign.
##
## Regra: animação só existe onde comunica alguma coisa — que o toque
## registrou, que um número mudou, que o estado avançou. Duração vem do
## Design System, nunca de valores soltos por tela, para que todo o app
## tenha o mesmo "peso" de resposta.


## Feedback tátil de toque: encolhe e volta. Aplique uma vez em `_ready()`
## de cada botão e esqueça.
static func attach_press(button: BaseButton) -> void:
	if button == null:
		return
	# Escala a partir do centro; sem isso o botão "foge" para a direita.
	button.pivot_offset = button.size * 0.5
	button.resized.connect(func() -> void:
		button.pivot_offset = button.size * 0.5)

	button.button_down.connect(func() -> void:
		_scale_to(button, Vector2.ONE * DS.PRESS_SCALE, DS.DUR_INSTANT))
	button.button_up.connect(func() -> void:
		_scale_to(button, Vector2.ONE, DS.DUR_FAST))


static func _scale_to(node: Control, target: Vector2, duration: float) -> void:
	if not is_instance_valid(node):
		return
	var t := node.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(node, "scale", target, duration)


## Um Container reposiciona seus filhos a cada layout, então animar
## `position` neles é uma briga que o container ganha — e o efeito colateral
## é que todos os itens terminam empilhados na mesma coordenada. Nestes casos
## a entrada usa `scale`, que nenhum container toca.
static func _is_in_container(node: CanvasItem) -> bool:
	return node is Control and node.get_parent() is Container


## Entrada de tela/estado: revela subindo (ou crescendo, dentro de container).
static func fade_in(node: CanvasItem, duration: float = DS.DUR_BASE, rise: float = 24.0) -> void:
	if node == null:
		return
	node.modulate.a = 0.0
	var t := node.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(node, "modulate:a", 1.0, duration)
	if node is Control and rise > 0.0 and not _is_in_container(node):
		var c := node as Control
		var to := c.position
		c.position = to + Vector2(0, rise)
		t.parallel().tween_property(c, "position", to, duration)


## Entrada em cascata de uma lista (trilha de lições, cards de estatística).
## `stagger` pequeno de propósito: a lista deve parecer rápida, não teatral.
static func stagger_in(nodes: Array, stagger: float = 0.04) -> void:
	var i: int = 0
	for n: Variant in nodes:
		if n is CanvasItem:
			var item := n as CanvasItem
			item.modulate.a = 0.0
			var t := item.create_tween()
			t.tween_interval(stagger * float(i))
			t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(item, "modulate:a", 1.0, DS.DUR_BASE)
			if item is Control:
				var c := item as Control
				if _is_in_container(c):
					c.pivot_offset = c.size * 0.5
					c.scale = Vector2(1.0, 0.985)
					t.parallel().tween_property(c, "scale", Vector2.ONE, DS.DUR_BASE)
				else:
					var to := c.position
					c.position = to + Vector2(0, 18)
					t.parallel().tween_property(c, "position", to, DS.DUR_BASE)
			i += 1


## Barra de progresso preenchendo. Sempre animada: um salto instantâneo faz o
## usuário perder a informação de que progrediu.
static func fill_bar(bar: Range, to_value: float, duration: float = DS.DUR_SLOW) -> void:
	if bar == null:
		return
	var t := bar.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(bar, "value", to_value, duration)


## Contagem de um número (XP, precisão). `fmt` recebe o valor inteiro.
static func count_up(label: Label, from: int, to: int, fmt: String = "%d",
		duration: float = DS.DUR_SLOW) -> void:
	if label == null:
		return
	var t := label.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_method(func(v: float) -> void:
		if is_instance_valid(label):
			label.text = fmt % int(round(v)),
		float(from), float(to), duration)


## Pulso curto de destaque — sinal validado, XP recebido, conquista.
static func pulse(node: Control, amount: float = 1.12) -> void:
	if node == null:
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(node, "scale", Vector2.ONE * amount, DS.DUR_FAST)
	t.set_trans(Tween.TRANS_QUAD)
	t.tween_property(node, "scale", Vector2.ONE, DS.DUR_BASE)


## Chamada de atenção sem alarme: usada quando a captura falha, no lugar de
## piscar vermelho na tela inteira.
static func shake(node: Control, amount: float = 14.0) -> void:
	if node == null:
		return
	var origin := node.position
	var t := node.create_tween()
	t.set_trans(Tween.TRANS_SINE)
	for offset: float in [amount, -amount * 0.7, amount * 0.4, 0.0]:
		t.tween_property(node, "position", origin + Vector2(offset, 0), 0.06)
	node.position = origin


## Troca entre dois estados do fluxo da lição (Assista → Pratique → Resultado).
static func cross_fade(from: CanvasItem, to: CanvasItem, duration: float = DS.DUR_FAST) -> void:
	if to == null:
		return
	if from != null and from != to:
		var out := from.create_tween()
		out.tween_property(from, "modulate:a", 0.0, duration * 0.6)
		out.tween_callback(func() -> void:
			if is_instance_valid(from):
				from.visible = false
				from.modulate.a = 1.0)
	to.visible = true
	to.modulate.a = 0.0
	var t := to.create_tween()
	t.tween_interval(duration * 0.35)
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(to, "modulate:a", 1.0, duration)
