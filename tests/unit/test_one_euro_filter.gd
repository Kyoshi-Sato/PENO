extends GutTest
## Filtro One-Euro: propriedades que sustentam a escolha dos parâmetros
## (ver calibração documentada em Scripts/OneEuroFilter.gd).

const FPS := 12.0


func _timestamps(n: int) -> Array:
	var ts: Array = []
	for i in range(n):
		ts.append(float(i) * 1000.0 / FPS)
	return ts


## Jitter determinístico (sem RNG) — mesma abordagem da fábrica de capturas.
func _jitter(i: int, amp: float) -> float:
	return amp * (sin(float(i) * 2.9) + sin(float(i) * 5.7)) * 0.5


func _apply(values: Array, ts: Array) -> Array:
	var f := OneEuroFilter.new()
	var out: Array = []
	for i in range(values.size()):
		out.append(f.filter(float(values[i]), float(ts[i])))
	return out


func _noise_level(values: Array) -> float:
	# Resíduo de curvatura: isola a componente de alta frequência.
	var residuals: Array = []
	for i in range(1, values.size() - 1):
		residuals.append(absf(
			float(values[i]) - (float(values[i - 1]) + float(values[i + 1])) / 2.0))
	residuals.sort()
	return float(residuals[residuals.size() / 2])


# ---------- comportamento do filtro escalar ----------

func test_constant_signal_passes_unchanged() -> void:
	var ts := _timestamps(30)
	var values: Array = []
	for i in range(30):
		values.append(0.42)
	var out := _apply(values, ts)
	for v: float in out:
		assert_almost_eq(v, 0.42, 0.0000001, "sinal constante não pode ser deslocado")


func test_first_sample_passes_through() -> void:
	var f := OneEuroFilter.new()
	assert_almost_eq(f.filter(0.7, 0.0), 0.7, 0.0000001)


func test_reduces_jitter_on_static_signal() -> void:
	var ts := _timestamps(40)
	var noisy: Array = []
	for i in range(40):
		noisy.append(0.5 + _jitter(i, 0.005))
	var filtered := _apply(noisy, ts)

	var before := _noise_level(noisy)
	var after := _noise_level(filtered)
	gut.p("ruído: %.5f -> %.5f" % [before, after])
	assert_lt(after, before * 0.6, "filtro deve cortar boa parte do tremor")


func test_tracks_real_movement() -> void:
	# Rampa na velocidade típica de um sinal (~0.3 un/s): o filtro não
	# pode achatar o movimento real.
	var ts := _timestamps(24)
	var values: Array = []
	for i in range(24):
		values.append(0.2 + 0.3 * float(i) / FPS)
	var out := _apply(values, ts)
	var traveled: float = float(out[out.size() - 1]) - float(out[0])
	var expected: float = float(values[values.size() - 1]) - float(values[0])
	assert_gt(traveled, expected * 0.8, "deve seguir o movimento real")


func test_reset_clears_state() -> void:
	var f := OneEuroFilter.new()
	f.filter(0.0, 0.0)
	f.filter(0.0, 100.0)
	f.reset()
	assert_almost_eq(f.filter(0.9, 200.0), 0.9, 0.0000001, "após reset, passa direto")


func test_handles_non_monotonic_timestamps() -> void:
	var f := OneEuroFilter.new()
	f.filter(0.5, 100.0)
	var out: float = f.filter(0.6, 100.0)   # dt == 0
	assert_false(is_nan(out), "dt zero não pode produzir NaN")
	assert_between(out, 0.5, 0.6)


# ---------- fase zero (duas passadas) ----------

func test_zero_phase_removes_causal_lag() -> void:
	# Pulso triangular simétrico centrado no quadro 15. O centroide temporal
	# detecta atraso fracionário (a esta velocidade o pico em si desloca
	# menos de um quadro, então medir o pico não bastaria).
	var n := 31
	var frames: Array = []
	for i in range(n):
		var v: float = 0.2 + 0.3 * (1.0 - absf(float(i - 15)) / 15.0)
		frames.append(_pose_frame(i, v))

	var raw_centroid := _centroid(frames)
	var causal_centroid := _centroid(OneEuroFilter.filter_frames(frames, 1.5, 2.0, false))
	var zero_phase_centroid := _centroid(OneEuroFilter.filter_frames(frames, 1.5, 2.0, true))
	gut.p("centroide: cru=%.3f causal=%.3f duas-passadas=%.3f"
		% [raw_centroid, causal_centroid, zero_phase_centroid])

	assert_gt(causal_centroid, raw_centroid + 0.1, "filtro causal atrasa o sinal")
	assert_almost_eq(zero_phase_centroid, raw_centroid, 0.1,
		"duas passadas cancelam o atraso")


func test_zero_phase_preserves_timestamps_and_order() -> void:
	var frames: Array = []
	for i in range(10):
		frames.append(_pose_frame(i, 0.5))
	var out: Array = OneEuroFilter.filter_frames(frames)

	assert_eq(out.size(), frames.size())
	for i in range(out.size()):
		assert_almost_eq(
			float((out[i] as Dictionary)["timestamp_ms"]),
			float((frames[i] as Dictionary)["timestamp_ms"]), 0.0001)
		assert_eq(int((out[i] as Dictionary)["frame"]), i, "ordem preservada")


# ---------- filtragem de capturas ----------

func test_filter_frames_does_not_mutate_input() -> void:
	var frames: Array = []
	for i in range(12):
		frames.append(_pose_frame(i, 0.5 + _jitter(i, 0.01)))
	var original_x: float = _first_x(frames[5])

	OneEuroFilter.filter_frames(frames)

	assert_almost_eq(_first_x(frames[5]), original_x, 0.0000001, "entrada intacta")


func test_filter_frames_smooths_capture_from_factory() -> void:
	var doc := CaptureDocFactory.make_doc(40, 30.0, true, true)
	var filtered: Array = OneEuroFilter.filter_frames(doc["frames"] as Array)

	var raw_series: Array = []
	var filtered_series: Array = []
	for i in range(40):
		raw_series.append(_hand_x((doc["frames"] as Array)[i]))
		filtered_series.append(_hand_x(filtered[i]))

	gut.p("mão: ruído %.5f -> %.5f" % [_noise_level(raw_series), _noise_level(filtered_series)])
	assert_lt(_noise_level(filtered_series), _noise_level(raw_series))


func test_gap_resets_filter_state() -> void:
	# Landmark some por mais de GAP_RESET_MS e volta noutra posição: o
	# valor de retorno não pode ser interpolado a partir do antigo.
	var frames: Array = []
	for i in range(6):
		frames.append(_pose_frame(i, 0.2, float(i) * 100.0))
	# lacuna de 2 s sem pose
	for i in range(6, 9):
		frames.append({"frame": i, "timestamp_ms": 600.0 + float(i - 5) * 700.0,
			"hands": [], "pose": []})
	frames.append(_pose_frame(9, 0.8, 3500.0))

	var out: Array = OneEuroFilter.filter_frames(frames, 1.5, 2.0, false)
	assert_almost_eq(_first_x(out[out.size() - 1]), 0.8, 0.0001,
		"após lacuna longa, o estado antigo é descartado")


# ---------- helpers ----------

func _pose_frame(index: int, x: float, timestamp_ms: float = -1.0) -> Dictionary:
	var ts: float = timestamp_ms if timestamp_ms >= 0.0 else float(index) * 1000.0 / FPS
	return {
		"frame": index,
		"timestamp_ms": ts,
		"hands": [],
		"pose": [{ "landmarks": [{ "id": 0, "x": x, "y": 0.5, "z": 0.0 }] }],
	}


func _first_x(frame: Variant) -> float:
	var pose: Array = (frame as Dictionary).get("pose", []) as Array
	if pose.is_empty():
		return NAN
	return float(((pose[0] as Dictionary)["landmarks"] as Array)[0]["x"])


func _hand_x(frame: Variant) -> float:
	var hands: Array = (frame as Dictionary).get("hands", []) as Array
	if hands.is_empty():
		return NAN
	return float(((hands[0] as Dictionary)["landmarks"] as Array)[0]["x"])


## Centroide temporal do pulso (posição média ponderada pela amplitude
## acima da linha de base) — mede deslocamento no tempo com resolução
## menor que um quadro.
func _centroid(frames: Array) -> float:
	var baseline := INF
	for f: Variant in frames:
		baseline = minf(baseline, _first_x(f))

	var weighted := 0.0
	var total := 0.0
	for i in range(frames.size()):
		var amplitude: float = _first_x(frames[i]) - baseline
		weighted += amplitude * float(i)
		total += amplitude
	return weighted / total if total > 0.0 else 0.0
