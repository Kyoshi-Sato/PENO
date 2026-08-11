extends "res://Scripts/autoload/Global.gd"
## Global sem persistência em disco, para testes.
## Sobrescreve load/save para não tocar user://progress.json real.


func _load_progress() -> void:
	_progress = {}


func _save_progress() -> void:
	pass
