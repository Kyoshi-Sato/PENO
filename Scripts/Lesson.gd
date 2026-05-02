class_name Lesson
extends Resource

## Recurso que representa uma lição de gesto/sinal.
## Cada lição tem um id, um conjunto de animações que o avatar executa para ensinar
## e um conjunto de JSONs de referência para comparação com a gravação do aluno.

@export var id: StringName = &""
@export var lesson_name: String = ""
@export var description: String = ""

## Caminhos (res://...) para os arquivos JSON de validação do gesto.
## Cada JSON contém os landmarks de referência capturados previamente.
@export var validation_jsons: Array[String] = []

## Nomes das animações que devem ser tocadas no AnimationPlayer do avatar.
## Ex.: "Libra2Anim/HelloSign". A ordem deve casar com os JSONs quando aplicável.
@export var animation_names: Array[StringName] = []

## XP / pontuação concedida ao concluir com sucesso.
@export var reward_xp: int = 10
