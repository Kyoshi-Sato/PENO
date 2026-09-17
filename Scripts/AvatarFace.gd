class_name AvatarFace
extends Node3D
## Rosto da boneca: piscada automática + expressões faciais.
##
## Usa os blend shapes padrão do VRoid (`Fcl_*`), que já vêm no modelo — não
## precisamos autorar nada. Os `Fcl_ALL_*` são combinações prontas (olho +
## boca + sobrancelha), e são eles que usamos como base de cada expressão.
##
## O detalhe que exige cuidado: `Fcl_ALL_Joy` e `Fcl_EYE_Joy` JÁ fecham os
## olhos. Somar a piscada por cima deforma a pálpebra além do limite e o olho
## "afunda" na cabeça. Por isso a piscada é atenuada pelo quanto a expressão
## atual já ocupa o olho — ver `_eye_occupancy`.

## Expressões disponíveis. O valor é o peso de cada blend shape do VRoid.
const EXPRESSOES: Dictionary = {
	&"neutro":      {},
	## 3 estrelas: comemoração cheia, olhos em ^_^ e boca aberta sorrindo.
	&"alegria":     {"Fcl_ALL_Joy": 1.0},
	## 2 estrelas: satisfeita, mas de olhos abertos — ela ainda está te olhando.
	&"contente":    {"Fcl_ALL_Fun": 0.85, "Fcl_MTH_Joy": 0.35},
	## 1 estrela: sorriso de incentivo, discreto.
	&"incentivo":   {"Fcl_ALL_Fun": 0.45},
	## 0 estrelas: desânimo contido. Acima de ~0.7 vira choro e fica pesado
	## demais para um app de aprendizado.
	&"pena":        {"Fcl_ALL_Sorrow": 0.65},
	## Enquanto a validação roda: uma expectativa leve.
	&"expectativa": {"Fcl_ALL_Surprised": 0.35},
}

## Blend shapes que fecham a pálpebra. Usados para atenuar a piscada.
const SHAPES_DE_OLHO: PackedStringArray = [
	"Fcl_ALL_Joy", "Fcl_EYE_Joy", "Fcl_EYE_Close", "Fcl_ALL_Sorrow",
]

## Velocidade da transição entre expressões (unidades de peso por segundo).
const VELOCIDADE_EXPRESSAO := 4.0
const VELOCIDADE_PISCADA := 15.0

@onready var face: MeshInstance3D = $Libra2/Armature_002/Skeleton3D/Face
@onready var anim_player: AnimationPlayer = $Libra2/Armature_002/AnimationPlayer

## Valor de `Fcl_EYE_Close`: 0.0 = olho aberto (repouso), 1.0 = fechado.
## A piscada é um pico curto até 1.0 e a volta imediata para 0.0.
var _piscada: float = 0.0
var _alvo_piscada: float = 1.0
var _tempo_piscada: float = 0.0
var _espera_piscada: float = 0.0

## Peso atual e alvo de cada blend shape de expressão.
var _atual: Dictionary = {}
var _alvo: Dictionary = {}


func _ready() -> void:
	_espera_piscada = randf_range(1.0, 4.0)


func _on_animation_player_animation_finished(_anim_name: StringName) -> void:
	anim_player.play("Idle", 0.25)


## Troca a expressão. `nome` deve ser uma chave de `EXPRESSOES`.
## A transição é interpolada, então pode ser chamada a qualquer momento.
func set_expression(nome: StringName) -> void:
	if not EXPRESSOES.has(nome):
		push_warning("AvatarFace: expressão desconhecida '%s'" % nome)
		return
	# Zera o alvo dos shapes da expressão anterior que não estão na nova,
	# senão eles ficariam congelados no peso antigo.
	for shape: String in _alvo:
		_alvo[shape] = 0.0
	for shape: String in EXPRESSOES[nome]:
		_alvo[shape] = float(EXPRESSOES[nome][shape])


## Expressão correspondente a um número de estrelas (0 a 3).
func set_expression_for_stars(estrelas: int) -> void:
	match estrelas:
		3: set_expression(&"alegria")
		2: set_expression(&"contente")
		1: set_expression(&"incentivo")
		_: set_expression(&"pena")


func _physics_process(delta: float) -> void:
	_atualiza_expressao(delta)
	_atualiza_piscada(delta)


func _atualiza_expressao(delta: float) -> void:
	for shape: String in _alvo:
		var alvo: float = _alvo[shape]
		var atual: float = _atual.get(shape, 0.0)
		if is_equal_approx(atual, alvo):
			continue
		atual = move_toward(atual, alvo, VELOCIDADE_EXPRESSAO * delta)
		_atual[shape] = atual
		_aplica(shape, atual)


func _atualiza_piscada(delta: float) -> void:
	_tempo_piscada += delta
	if _tempo_piscada >= _espera_piscada:
		_piscada = lerp(_piscada, _alvo_piscada, VELOCIDADE_PISCADA * delta)
		if absf(_piscada - _alvo_piscada) <= 0.01:
			if _alvo_piscada > 0.5:
				_alvo_piscada = 0.0        # acabou de fechar -> reabre
			else:
				_alvo_piscada = 1.0        # acabou de abrir -> agenda a próxima
				_tempo_piscada = 0.0
				_espera_piscada = randf_range(1.0, 5.0)

	# A expressão já mexe na pálpebra por conta própria. Somar a piscada por
	# cima estoura a deformação, então reduzimos a AMPLITUDE dela — não
	# adicionamos um piso. Com `alegria` (olho totalmente ocupado) a piscada
	# simplesmente não acontece, que é o certo: os olhos já estão em ^_^.
	var amplitude := 1.0 - _eye_occupancy()
	_aplica("Fcl_EYE_Close", _piscada * amplitude)


## Quanto da pálpebra a expressão atual já está usando (0 a 1).
func _eye_occupancy() -> float:
	var maior := 0.0
	for shape: String in SHAPES_DE_OLHO:
		if shape == "Fcl_EYE_Close":
			continue
		maior = maxf(maior, float(_atual.get(shape, 0.0)))
	return clampf(maior, 0.0, 1.0)


func _aplica(shape: String, valor: float) -> void:
	var caminho := "blend_shapes/%s" % shape
	if absf(float(face.get(caminho)) - valor) > 0.001:
		face.set(caminho, valor)
