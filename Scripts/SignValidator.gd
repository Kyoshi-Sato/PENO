class_name SignValidator
extends RefCounted
## Interface base para validadores de sinais.
##
## Um validator recebe a gravação do usuário e a referência (gabarito)
## e retorna um Dictionary padronizado com a nota da execução.
##
## Formato do retorno:
##   {
##     "precision": float,           # 0.0 a 1.0 — usado pra estrelas e %
##     "global_similarity_pct": float,  # 0 a 100 — opcional, info bruta
##     "details": Dictionary,        # opcional — quebra por grupo/osso
##     "ok": bool,                   # true se a validação foi possível
##     "error": String,              # vazio se ok==true
##   }
##
## Formato esperado de user_payload e reference:
##   { "video_info": { "fps": float, "total_frames": int, ... },
##     "frames": [ { "frame": int, "hands": [...], "pose": [...] }, ... ] }


## Sobrescreva nas subclasses.
func validate(user_payload: Dictionary, reference: Dictionary) -> Dictionary:
	push_error("SignValidator.validate() não implementado — use uma subclasse")
	return {
		"precision": 0.0,
		"global_similarity_pct": 0.0,
		"details": {},
		"ok": false,
		"error": "validator base — não implementado",
	}
