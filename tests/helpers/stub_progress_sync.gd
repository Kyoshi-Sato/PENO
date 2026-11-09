extends "res://Scripts/autoload/ProgressSync.gd"
## ProgressSync com um servidor falso em memória e sem tocar user://.
##
## O servidor imita as regras de routes/usuarios.js e routes/admin.js: versão
## sobe a cada gravação, PUT com versão velha dá 409 com o estado atual, a
## gravação do admin é "autoritativa", usuário apagado dá 401 e bloqueado 403.

## token -> { uuid, dados, versao, autoritativo, bloqueado }
var server: Dictionary = {}
## Simula falta de rede: toda requisição devolve code 0.
var offline: bool = false
## Requisições feitas, em ordem ("GET /usuario/progresso", ...).
var calls: PackedStringArray = PackedStringArray()
## Chamado antes de responder um PUT — para simular o usuário mexendo no
## progresso enquanto a requisição está no ar.
var before_put: Callable = Callable()

var _next_id: int = 1


func _should_enable() -> bool:
	return true


## Os testes chamam `sync_now()` quando querem, em vez de no boot.
func _boot_sync() -> void:
	pass


func _load_account() -> void:
	_account = {"uuid": "", "token": "", "versao": 0, "dirty": false, "force": false}


func _save_account() -> void:
	pass


func _request(method: int, path: String, body: Variant = null) -> Dictionary:
	var verb: String = {
		HTTPClient.METHOD_GET: "GET",
		HTTPClient.METHOD_POST: "POST",
		HTTPClient.METHOD_PUT: "PUT",
	}.get(method, "?")
	calls.append("%s %s" % [verb, path])
	if offline:
		return {"code": 0, "data": {}}

	if path == "/usuario/registro":
		var id: int = _next_id
		_next_id += 1
		var uuid := "00000000-0000-4000-8000-%012d" % id
		var new_token := "token-%d" % id
		server[new_token] = {"uuid": uuid, "dados": {}, "versao": 0,
			"autoritativo": false, "bloqueado": false}
		return {"code": 201, "data": {"uuid": uuid, "token": new_token}}

	var token: String = String(_account.get("token", ""))
	if not server.has(token):
		return {"code": 401, "data": {}}
	var row: Dictionary = server[token]
	if bool(row.bloqueado):
		return {"code": 403, "data": {}}

	if verb == "GET":
		return {"code": 200, "data": _state(row)}

	if before_put.is_valid():
		before_put.call()
	var b: Dictionary = body
	if int(b.versao_base) != int(row.versao):
		return {"code": 409, "data": _state(row)}
	row.dados = (b.dados as Dictionary).duplicate(true)
	row.versao = int(row.versao) + 1
	row.autoritativo = false
	return {"code": 200, "data": {"versao": row.versao}}


## O que o painel admin faz em PUT /admin/usuarios/:uuid/progresso.
func admin_set(dados: Dictionary) -> void:
	var row: Dictionary = server[String(_account.token)]
	row.dados = dados.duplicate(true)
	row.versao = int(row.versao) + 1
	row.autoritativo = true


func server_row() -> Dictionary:
	return server.get(String(_account.get("token", "")), {})


func _state(row: Dictionary) -> Dictionary:
	return {"dados": (row.dados as Dictionary).duplicate(true),
		"versao": row.versao, "autoritativo": row.autoritativo}
