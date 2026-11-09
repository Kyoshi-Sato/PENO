extends "res://Scripts/autoload/Global.gd"
## Global sem persistência em disco, para testes.
## Sobrescreve load/save para não tocar user://progress.json real.


func _load_progress() -> void:
	_progress = {}


## Não grava, mas avisa como o de verdade — o ProgressSync dos testes
## depende do sinal para saber que há alteração a enviar.
func _save_progress() -> void:
	progress_changed.emit()


func _load_settings() -> void:
	_settings = {}


func _save_settings() -> void:
	pass


## `erase_all_data()` confere o resultado relendo o arquivo. Sem este override
## o stub leria o user://progress.json real — justamente o que ele evita.
func _saved_progress_is_empty() -> bool:
	return _progress.is_empty()


## `apply_remote_progress()` grava direto por aqui, sem passar por
## `_save_progress()`.
func _write_progress_file() -> void:
	pass
