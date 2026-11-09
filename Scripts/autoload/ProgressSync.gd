extends Node
## Sincroniza o progresso local (user://progress.json, dono: Global) com o
## servidor. Cadastre como Autoload com nome "ProgressSync", DEPOIS de Global
## e LessonService.
##
## O usuário é anônimo: no primeiro uso o servidor gera um UUID e um token, que
## ficam em user://account.json. O UUID aparece em Configurações; é por ele que
## o painel admin encontra o usuário.
##
## O JSON local continua sendo a fonte da verdade no dia a dia — o app abre e
## funciona sem rede. O servidor é a cópia de segurança e o canal do admin.
##
## Protocolo (ver routes/usuarios.js na API):
##   POST /usuario/registro   -> { uuid, token }
##   GET  /usuario/progresso  -> { dados, versao, autoritativo }
##   PUT  /usuario/progresso  { dados, versao_base } -> { versao } | 409 + estado atual
##
## Cada gravação no servidor sobe a `versao`. Guardamos a última versão vista;
## se o servidor estiver em outra, alguém mexeu lá (na prática, o admin) e
## `decide()` escolhe entre adotar, mesclar ou sobrescrever.

const GlobalScript := preload("res://Scripts/autoload/Global.gd")

const ACCOUNT_PATH := "user://account.json"
## Espera depois da última alteração antes de enviar: uma lição gera várias
## gravações em sequência (estrela, XP, prática) e uma requisição basta.
const DEBOUNCE_S := 3.0
## Tentativas de PUT seguidas de 409 antes de desistir até a próxima rodada.
const MAX_ATTEMPTS := 3
const TIMEOUT_S := 15.0

enum Status {
	DISABLED,   ## sem chave de API ou rodando via -s (testes, ferramentas)
	IDLE,       ## ainda não tentou nesta sessão
	SYNCING,
	SYNCED,
	OFFLINE,    ## a última tentativa não alcançou o servidor
	BLOCKED,    ## o admin bloqueou este usuário
}

signal status_changed(status: Status)

## Estado persistido em ACCOUNT_PATH.
##   uuid, token  — identidade dada pelo servidor
##   versao       — última versão do servidor que este aparelho conhece
##   dirty        — há alteração local que o servidor ainda não tem
##   force        — o usuário apagou os dados: sobrescrever, nunca mesclar
var _account: Dictionary = {}
var _status: Status = Status.IDLE
var _enabled: bool = true

var _busy: bool = false
var _again: bool = false
## Conta alterações locais. Comparar antes/depois de um PUT diz se o usuário
## mexeu no progresso enquanto a requisição estava no ar — nesse caso o
## servidor recebeu uma foto velha e `dirty` precisa continuar ligado.
var _local_rev: int = 0
var _timer: Timer
## Dono do progresso. É o autoload Global; os testes trocam por um stub antes
## do `_ready` para não mexer no user://progress.json de verdade.
var _g: Node = null


func _ready() -> void:
	if _g == null:
		_g = Global
	_enabled = _should_enable()
	_load_account()

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DEBOUNCE_S
	_timer.timeout.connect(sync_now)
	add_child(_timer)

	_g.progress_changed.connect(_on_progress_changed)
	_g.progress_reset.connect(_on_progress_reset)

	if not _enabled:
		_set_status(Status.DISABLED)
		return
	_boot_sync()


func _boot_sync() -> void:
	sync_now.call_deferred()


func _notification(what: int) -> void:
	if not _enabled:
		return
	match what:
		# Indo para segundo plano: última chance de enviar antes de o Android
		# matar o processo.
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			if bool(_account.get("dirty", false)):
				sync_now()
		# Voltando: pega uma alteração do admin feita enquanto o app dormia.
		NOTIFICATION_APPLICATION_RESUMED:
			sync_now()


## Sem chave não há como falar com a API. E rodando via `-s` (GUT, scripts de
## tools/) o app não deve registrar usuários de mentira no servidor real.
func _should_enable() -> bool:
	if OS.get_environment("PENO_SYNC_DISABLED") == "1":
		return false
	var args := OS.get_cmdline_args()
	if args.has("-s") or args.has("--script"):
		return false
	return not LessonService.api_key.is_empty()


# ============================================================
# API PÚBLICA
# ============================================================

## UUID deste usuário, ou "" se ainda não registrou (sem rede no 1º uso).
func get_uuid() -> String:
	return String(_account.get("uuid", ""))


func get_status() -> Status:
	return _status


func has_pending_changes() -> bool:
	return bool(_account.get("dirty", false))


## Dispara uma rodada de sincronização. Seguro chamar a qualquer momento: se
## já houver uma rodando, ela roda de novo ao terminar.
func sync_now() -> void:
	if not _enabled or _status == Status.BLOCKED:
		return
	if _busy:
		_again = true
		return
	_busy = true
	_set_status(Status.SYNCING)
	var ok := true
	while true:
		_again = false
		ok = await _sync_once()
		if not _again or _status == Status.BLOCKED:
			break
	_busy = false
	if _status == Status.SYNCING:
		_set_status(Status.SYNCED if ok else Status.OFFLINE)


# ============================================================
# DECISÃO E MESCLA (puras, testadas em test_progress_sync.gd)
# ============================================================

## O que fazer com o estado do servidor. Devolve
##   { "action": "none" | "adopt" | "push", "data": Dictionary }
## "adopt" = trocar o local pelo `data`; "push" = enviar `data` (e, se for uma
## mescla, gravar também localmente).
static func decide(local: Dictionary, server: Dictionary, known_version: int,
		dirty: bool, force: bool) -> Dictionary:
	var server_version: int = int(server.get("versao", 0))
	var server_data: Dictionary = _as_dict(server.get("dados", {}))

	if server_version == known_version:
		# Ninguém mexeu lá desde a última vez.
		if dirty or force:
			return {"action": "push", "data": local}
		return {"action": "none", "data": {}}

	# O servidor andou. Se foi o admin, a palavra dele vale: uma correção
	# (ex.: zerar) desfeita pelo "a maior nota vence" seria inútil.
	if bool(server.get("autoritativo", false)):
		return {"action": "adopt", "data": server_data}
	# O usuário apagou os dados aqui: mesclar ressuscitaria o que ele apagou.
	if force:
		return {"action": "push", "data": local}
	if dirty:
		return {"action": "push", "data": merge(local, server_data)}
	return {"action": "adopt", "data": server_data}


## Junta dois progress.json sem perder conquista de nenhum dos lados.
## Quase tudo é "a melhor nota vence"; os contadores ficam com o lado que
## praticou mais, para a precisão média continuar coerente.
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = b.duplicate(true)

	for key: Variant in a:
		var k := String(key)
		if k == GlobalScript.STATS_KEY:
			continue
		var ea: Variant = a[key]
		var eb: Variant = out.get(k, null)
		if not (ea is Dictionary):
			if eb == null:
				out[k] = ea
			continue
		if not (eb is Dictionary):
			out[k] = (ea as Dictionary).duplicate(true)
			continue
		var da: Dictionary = ea
		var db: Dictionary = eb
		var merged: Dictionary = db.duplicate(true)
		merged.merge(da, false)
		merged["completed"] = bool(da.get("completed", false)) or bool(db.get("completed", false))
		merged["stars"] = maxi(int(da.get("stars", 0)), int(db.get("stars", 0)))
		out[k] = merged

	var sa := _as_dict(a.get(GlobalScript.STATS_KEY, {}))
	var sb := _as_dict(b.get(GlobalScript.STATS_KEY, {}))
	if not sa.is_empty() or not sb.is_empty():
		out[GlobalScript.STATS_KEY] = _merge_stats(sa, sb)
	return out


static func _merge_stats(sa: Dictionary, sb: Dictionary) -> Dictionary:
	var out: Dictionary = sb.duplicate(true)
	out.merge(sa, false)

	var signs: Dictionary = _as_dict(sb.get("signs", {})).duplicate(true)
	var signs_a := _as_dict(sa.get("signs", {}))
	for key: Variant in signs_a:
		signs[key] = maxi(int(signs.get(key, 0)), int(signs_a[key]))
	out["signs"] = signs

	# O XP é a soma das melhoras por sinal (ver Global.award_sign_result), então
	# a soma das melhores notas mescladas é o piso certo.
	var derived: int = 0
	for key: Variant in signs:
		derived += int(signs[key]) * GlobalScript.XP_PER_STAR
	out["xp"] = maxi(maxi(int(sa.get("xp", 0)), int(sb.get("xp", 0))), derived)

	var pa: int = int(sa.get("practices", 0))
	var pb: int = int(sb.get("practices", 0))
	var more := sa if pa >= pb else sb
	out["practices"] = int(more.get("practices", 0))
	out["precision_sum"] = float(more.get("precision_sum", 0.0))

	# Datas "AAAA-MM-DD" ordenam como texto. A ofensiva vem do lado mais recente.
	var la := String(sa.get("last_day", ""))
	var lb := String(sb.get("last_day", ""))
	var recent := sa if la >= lb else sb
	out["last_day"] = String(recent.get("last_day", ""))
	out["streak"] = int(recent.get("streak", 0))
	out["best_streak"] = maxi(
		maxi(int(sa.get("best_streak", 0)), int(sb.get("best_streak", 0))),
		int(out["streak"]))
	return out


static func _as_dict(v: Variant) -> Dictionary:
	return v as Dictionary if v is Dictionary else {}


# ============================================================
# RODADA DE SINCRONIZAÇÃO
# ============================================================

## Uma rodada completa. Devolve false se não alcançou o servidor.
func _sync_once() -> bool:
	if get_uuid().is_empty() or String(_account.get("token", "")).is_empty():
		if not await _register():
			return false

	var r: Dictionary = await _request(HTTPClient.METHOD_GET, "/usuario/progresso")
	if int(r.code) == 401:
		# O admin apagou o usuário (ou o token se perdeu no servidor). O
		# progresso local continua valendo: registra de novo e envia.
		_forget_account()
		if not await _register():
			return false
		r = await _request(HTTPClient.METHOD_GET, "/usuario/progresso")

	for _attempt: int in MAX_ATTEMPTS:
		var code: int = int(r.code)
		if code == 403:
			_set_status(Status.BLOCKED)
			return true
		if code != 200 and code != 409:
			return false

		var d := decide(
			_g.get_progress_snapshot(), r.data,
			int(_account.get("versao", 0)),
			bool(_account.get("dirty", false)),
			bool(_account.get("force", false)))

		match String(d.action):
			"none":
				return true
			"adopt":
				_g.apply_remote_progress(d.data)
				_account["versao"] = int(r.data.get("versao", 0))
				_account["dirty"] = false
				_account["force"] = false
				_save_account()
				return true
			"push":
				var payload: Dictionary = d.data
				# Mescla: o aparelho também precisa ficar com o resultado.
				if payload != _g.get_progress_snapshot():
					_g.apply_remote_progress(payload)
				var rev_before := _local_rev
				var base: int = int(r.data.get("versao", 0))
				var p: Dictionary = await _request(HTTPClient.METHOD_PUT, "/usuario/progresso",
					{"dados": payload, "versao_base": base})
				if int(p.code) == 200:
					_account["versao"] = int(p.data.get("versao", base + 1))
					_account["dirty"] = _local_rev != rev_before
					_account["force"] = false
					_save_account()
					if _account.dirty:
						_again = true
					return true
				# 409: o corpo traz o estado atual; decide de novo com ele.
				r = p
	return false


func _register() -> bool:
	var r: Dictionary = await _request(HTTPClient.METHOD_POST, "/usuario/registro", {})
	if int(r.code) != 201:
		return false
	var uuid := String(r.data.get("uuid", ""))
	var token := String(r.data.get("token", ""))
	if uuid.is_empty() or token.is_empty():
		return false
	# Conta nova, servidor vazio: tudo o que há no aparelho precisa subir.
	_account = {"uuid": uuid, "token": token, "versao": 0, "dirty": true, "force": false}
	_save_account()
	return true


func _forget_account() -> void:
	_account = {"uuid": "", "token": "", "versao": 0, "dirty": true, "force": false}
	_save_account()


## Transporte HTTP. Devolve { code: int, data: Dictionary }; code 0 = sem rede.
## Os testes sobrescrevem este método com um servidor falso.
func _request(method: int, path: String, body: Variant = null) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_S
	add_child(req)

	var headers := PackedStringArray([
		"x-api-key: " + LessonService.api_key,
		"Content-Type: application/json",
	])
	var token := String(_account.get("token", ""))
	if not token.is_empty():
		headers.append("x-user-token: " + token)

	var payload := "" if body == null else JSON.stringify(body)
	var err := req.request(LessonService.base_url + path, headers, method, payload)
	if err != OK:
		req.queue_free()
		return {"code": 0, "data": {}}

	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"code": 0, "data": {}}
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return {"code": int(res[1]), "data": _as_dict(parsed)}


# ============================================================
# EVENTOS DO GLOBAL
# ============================================================

## Desligado (testes, ferramentas em tools/) não registra nada: os testes que
## usam o Global de verdade gravariam account.json no user:// do desenvolvedor.
func _on_progress_changed() -> void:
	if not _enabled:
		return
	_local_rev += 1
	if not bool(_account.get("dirty", false)):
		_account["dirty"] = true
		_save_account()
	if _status != Status.BLOCKED:
		_timer.start()


## "Apagar dados": o servidor tem que ficar vazio também, não ser mesclado.
## Vem antes do `progress_changed` que o reset dispara em seguida.
func _on_progress_reset() -> void:
	if not _enabled:
		return
	_account["force"] = true
	_save_account()


func _set_status(s: Status) -> void:
	if _status == s:
		return
	_status = s
	status_changed.emit(s)


# ============================================================
# PERSISTÊNCIA DA CONTA
# ============================================================

func _load_account() -> void:
	_account = {"uuid": "", "token": "", "versao": 0, "dirty": false, "force": false}
	if not FileAccess.file_exists(ACCOUNT_PATH):
		return
	var f := FileAccess.open(ACCOUNT_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_account.merge(parsed as Dictionary, true)


func _save_account() -> void:
	var f := FileAccess.open(ACCOUNT_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("ProgressSync: não foi possível gravar %s" % ACCOUNT_PATH)
		return
	f.store_string(JSON.stringify(_account))
	f.close()
