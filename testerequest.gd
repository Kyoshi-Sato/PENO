@tool
extends Node

const API_URL = "https://api.ciclicainteractive.com/exercicio/"
const API_KEY = "chave_secreta_godot"

func buscar_exercicio(id: int) -> Dictionary:
	var http: = HTTPRequest.new()
	add_child(http)

	var headers: = [
		"x-api-key: " + API_KEY,
        "Content-Type: application/json"
	]

	var erro: = http.request(API_URL + str(id), headers, HTTPClient.METHOD_GET)
	if erro != OK:
		push_error("Falha ao iniciar requisição")
		http.queue_free()
		return {}

	var resultado: Array = await http.request_completed

	http.queue_free()

	var response_code:int = resultado[1]
	var body: String = resultado[3].get_string_from_utf8()

	if response_code == 200:
		return JSON.parse_string(body)
	else:
		push_error("Erro da API: " + str(response_code))
		return {}


func _ready() -> void:
	var exercicio: = await buscar_exercicio(1)
	if exercicio.is_empty():
		return

	print("Exercício: ", exercicio["nome_exercicio"])
	for sinal: Variant in exercicio["sinais"]:
		print("Sinal: ", sinal["nome_sinal"])
		print("Anim: ", sinal["anim_lib"])
		print("Json: ", sinal["json_sinal"])
		print("Animacao: ", sinal["json_sinal"])
