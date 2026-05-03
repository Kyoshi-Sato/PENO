class_name Lesson
extends RefCounted
## Modelo de uma lição retornada pela API.
## Contém o nome do exercício, o array bruto dos sinais (com landmarks
## de referência em json_sinal) e a AnimationLibrary já montada com
## todas as animações dos sinais, prontas para serem tocadas pelo
## AnimationPlayer do Libra.

var lesson_id: int
var nome_exercicio: String
## Array de Dictionary, cada um com:
##   { "nome_sinal": String, "json_sinal": Dictionary }
## (anim_lib foi consumido na construção da animation_library)
var sinais: Array = []
## AnimationLibrary com uma Animation por sinal.
## A key de cada animação é o `nome_sinal`.
var animation_library: AnimationLibrary


func get_sign_names() -> PackedStringArray:
	var names := PackedStringArray()
	for s: Variant in sinais:
		names.append(s.get("nome_sinal", ""))
	return names


func get_sign(nome_sinal: String) -> Dictionary:
	for s: Variant in sinais:
		if s.get("nome_sinal", "") == nome_sinal:
			return s
	return {}
