class_name MeuValidatorCustom
extends SignValidator

func validate(user_payload: Dictionary, reference: Dictionary) -> Dictionary:
	# sua lógica aqui — pode ser ML, regras simples, qualquer coisa
	var sim_pct: float = ...
	return {
		"precision": sim_pct / 100.0,
		"global_similarity_pct": sim_pct,
		"details": {},
		"ok": true,
		"error": "",
	}
