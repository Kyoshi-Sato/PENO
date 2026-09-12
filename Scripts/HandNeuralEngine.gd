class_name HandNeuralEngine
extends RefCounted

## Motor de inferência neural nativo para reconhecimento de postura da mão (TCC).
## Executa o forward-pass das 4 camadas densas (42 -> 512 -> 256 -> 128 -> 2364)
## com BatchNormalization e Softmax, carregando os pesos de res://assets/models/weights.bin.

const DEFAULT_WEIGHTS_PATH := "res://assets/models/weights.bin"
const DEFAULT_LABELS_PATH := "res://assets/models/labels.json"

var is_loaded: bool = false
var labels: Array = []

# Dimensões
var d_in: int = 42
var d_h1: int = 512
var d_h2: int = 256
var d_h3: int = 128
var d_out: int = 2364

# Pesos e bias das camadas
var w0: PackedFloat32Array
var b0: PackedFloat32Array
var s0: PackedFloat32Array
var o0: PackedFloat32Array

var w1: PackedFloat32Array
var b1: PackedFloat32Array
var s1: PackedFloat32Array
var o1: PackedFloat32Array

var w2: PackedFloat32Array
var b2: PackedFloat32Array
var s2: PackedFloat32Array
var o2: PackedFloat32Array

var w3: PackedFloat32Array
var b3: PackedFloat32Array


func load_model(weights_path: String = DEFAULT_WEIGHTS_PATH, labels_path: String = DEFAULT_LABELS_PATH) -> bool:
	if not FileAccess.file_exists(weights_path):
		push_error("HandNeuralEngine: Arquivo de pesos não encontrado em %s" % weights_path)
		return false

	if not FileAccess.file_exists(labels_path):
		push_error("HandNeuralEngine: Arquivo de labels não encontrado em %s" % labels_path)
		return false

	# 1. Carregar labels
	var labels_file := FileAccess.open(labels_path, FileAccess.READ)
	if labels_file == null:
		push_error("HandNeuralEngine: Falha ao abrir labels.")
		return false
	var labels_text := labels_file.get_as_text()
	var parsed_labels: Variant = JSON.parse_string(labels_text)
	if not (parsed_labels is Array):
		push_error("HandNeuralEngine: Formato inválido de labels.")
		return false
	labels = parsed_labels as Array

	# 2. Carregar weights.bin
	var bin_file := FileAccess.open(weights_path, FileAccess.READ)
	if bin_file == null:
		push_error("HandNeuralEngine: Falha ao abrir arquivo binário de pesos.")
		return false

	# Cabeçalho: 5 uint32
	d_in  = bin_file.get_32()
	d_h1  = bin_file.get_32()
	d_h2  = bin_file.get_32()
	d_h3  = bin_file.get_32()
	d_out = bin_file.get_32()

	# Leitura dos buffers
	w0 = _read_float_array(bin_file, d_in * d_h1)
	b0 = _read_float_array(bin_file, d_h1)
	s0 = _read_float_array(bin_file, d_h1)
	o0 = _read_float_array(bin_file, d_h1)

	w1 = _read_float_array(bin_file, d_h1 * d_h2)
	b1 = _read_float_array(bin_file, d_h2)
	s1 = _read_float_array(bin_file, d_h2)
	o1 = _read_float_array(bin_file, d_h2)

	w2 = _read_float_array(bin_file, d_h2 * d_h3)
	b2 = _read_float_array(bin_file, d_h3)
	s2 = _read_float_array(bin_file, d_h3)
	o2 = _read_float_array(bin_file, d_h3)

	w3 = _read_float_array(bin_file, d_h3 * d_out)
	b3 = _read_float_array(bin_file, d_out)

	is_loaded = true
	return true


func _read_float_array(file: FileAccess, count: int) -> PackedFloat32Array:
	var byte_count := count * 4
	var raw_bytes := file.get_buffer(byte_count)
	return raw_bytes.to_float32_array()


## Executa a inferência para um vetor de entrada de 42 features.
## Retorna Dictionary com { code: String, confidence: float, top_index: int, probabilities: PackedFloat32Array }
func predict(features: PackedFloat32Array) -> Dictionary:
	if not is_loaded:
		push_error("HandNeuralEngine: Modelo não carregado. Chame load_model() primeiro.")
		return {"code": "0000000000", "confidence": 0.0, "top_index": -1, "probabilities": PackedFloat32Array()}

	if features.size() != d_in:
		push_error("HandNeuralEngine: Tamanho de entrada incorreto (%d != %d)" % [features.size(), d_in])
		return {"code": "0000000000", "confidence": 0.0, "top_index": -1, "probabilities": PackedFloat32Array()}

	# Layer 0: Dense (42 -> 512) + ReLU + BN
	var z0 := _dense_forward(features, w0, b0, d_in, d_h1)
	var a0 := _relu_and_bn(z0, s0, o0, d_h1)

	# Layer 1: Dense (512 -> 256) + ReLU + BN
	var z1 := _dense_forward(a0, w1, b1, d_h1, d_h2)
	var a1 := _relu_and_bn(z1, s1, o1, d_h2)

	# Layer 2: Dense (256 -> 128) + ReLU + BN
	var z2 := _dense_forward(a1, w2, b2, d_h2, d_h3)
	var a2 := _relu_and_bn(z2, s2, o2, d_h3)

	# Layer 3: Dense (128 -> 2364) + Softmax
	var z3 := _dense_forward(a2, w3, b3, d_h3, d_out)
	var probs := _softmax(z3, d_out)

	# Argmax e Confiança
	var top_idx := 0
	var max_prob := probs[0]
	for k in range(1, d_out):
		var p := probs[k]
		if p > max_prob:
			max_prob = p
			top_idx = k

	var code := "0000000000"
	if top_idx >= 0 and top_idx < labels.size():
		code = String(labels[top_idx])

	return {
		"code": code,
		"confidence": max_prob,
		"top_index": top_idx,
		"probabilities": probs
	}


## Multiplicação de matriz: output = input * W + bias
## input: (M,), W: (M, N) em row-major, bias: (N,), output: (N,)
func _dense_forward(x: PackedFloat32Array, W: PackedFloat32Array, b: PackedFloat32Array, M: int, N: int) -> PackedFloat32Array:
	var out := b.duplicate()
	for i in range(M):
		var xi := x[i]
		if xi == 0.0:
			continue  # Otimização para matrizes esparsas pós-ReLU
		var row_offset := i * N
		for j in range(N):
			out[j] += xi * W[row_offset + j]
	return out


## Aplica ReLU: h = max(0, z), seguido de BatchNormalization: h * scale + offset
func _relu_and_bn(z: PackedFloat32Array, scale: PackedFloat32Array, offset: PackedFloat32Array, N: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(N)
	for j in range(N):
		var val := z[j]
		if val > 0.0:
			out[j] = val * scale[j] + offset[j]
		else:
			out[j] = offset[j]
	return out


## Softmax numericamente estável: exp(z - max) / sum(exp(z - max))
func _softmax(z: PackedFloat32Array, N: int) -> PackedFloat32Array:
	var max_val := z[0]
	for j in range(1, N):
		if z[j] > max_val:
			max_val = z[j]

	var exp_sum := 0.0
	var out := PackedFloat32Array()
	out.resize(N)
	for j in range(N):
		var ez := exp(z[j] - max_val)
		out[j] = ez
		exp_sum += ez

	var inv_sum := 1.0 / exp_sum
	for j in range(N):
		out[j] *= inv_sum

	return out


## Teste de sanidade automática para validar paridade com o Python
func run_sanity_test(test_path: String = "res://assets/models/sanity_test.json") -> bool:
	if not is_loaded:
		if not load_model():
			return false

	if not FileAccess.file_exists(test_path):
		push_warning("HandNeuralEngine: Arquivo sanity_test.json não encontrado em %s" % test_path)
		return false

	var file := FileAccess.open(test_path, FileAccess.READ)
	if file == null:
		return false

	var test_data: Variant = JSON.parse_string(file.get_as_text())
	if not (test_data is Dictionary):
		return false

	var dict := test_data as Dictionary
	var feats_raw: Array = dict.get("input_features", []) as Array
	var expected_idx: int = int(dict.get("expected_top_index", -1))
	var expected_label: String = String(dict.get("expected_top_label", ""))
	var expected_conf: float = float(dict.get("expected_confidence", 0.0))

	var feats := PackedFloat32Array()
	feats.resize(feats_raw.size())
	for i in range(feats_raw.size()):
		feats[i] = float(feats_raw[i])

	var res := predict(feats)
	var ok_idx: bool = (res.top_index == expected_idx)
	var ok_label: bool = (res.code == expected_label)
	var diff_conf: float = absf(res.confidence - expected_conf)
	var ok_conf: bool = (diff_conf < 1e-4)

	if ok_idx and ok_label and ok_conf:
		print("✅ [HandNeuralEngine] Teste de sanidade passou com sucesso! Confianca: %.4f (diff: %.6f)" % [res.confidence, diff_conf])
		return true
	else:
		push_error("❌ [HandNeuralEngine] Falha no teste de sanidade: obtido %s (%.4f) vs esperado %s (%.4f)" % [res.code, res.confidence, expected_label, expected_conf])
		return false
