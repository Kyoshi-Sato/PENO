extends GutTest
## Normalização do catálogo — o teste que teria pego o bug id_exercicio/id.

const LessonServiceScript := preload("res://Scripts/autoload/LessonService.gd")

const SAFE_TRES := """[gd_resource type="Animation" format=3]

[resource]
resource_name = "ACENAR"
length = 2.5
tracks/0/type = "position_3d"
tracks/0/path = NodePath("Armature_002/Skeleton3D:hand_R")
"""

var svc: Node


func before_each() -> void:
	svc = autofree(LessonServiceScript.new())


func test_normalizes_api_shape_id_exercicio() -> void:
	# Formato real observado em GET /licoes.
	var catalog: Array = svc._normalize_catalog([
		{"id_exercicio": 1, "nome_exercicio": "debug1"},
		{"id_exercicio": 2, "nome_exercicio": "Frutas"},
	])
	assert_eq(catalog.size(), 2)
	assert_eq(int(catalog[0]["id"]), 1)
	assert_eq(String(catalog[0]["nome"]), "debug1")
	assert_eq(int(catalog[1]["id"]), 2)
	assert_eq(String(catalog[1]["nome"]), "Frutas")


func test_normalizes_canonical_shape() -> void:
	var catalog: Array = svc._normalize_catalog([{"id": 7, "nome": "Cores"}])
	assert_eq(int(catalog[0]["id"]), 7)
	assert_eq(String(catalog[0]["nome"]), "Cores")


func test_normalizes_int_list() -> void:
	var catalog: Array = svc._normalize_catalog([3, 4.0])
	assert_eq(int(catalog[0]["id"]), 3)
	assert_eq(String(catalog[0]["nome"]), "Lição 3")
	assert_eq(int(catalog[1]["id"]), 4)


func test_missing_name_gets_placeholder() -> void:
	var catalog: Array = svc._normalize_catalog([{"id_exercicio": 9}])
	assert_eq(String(catalog[0]["nome"]), "Lição 9")


func test_garbage_entries_are_dropped() -> void:
	var catalog: Array = svc._normalize_catalog(["oi", null, {"id": 1, "nome": "Ok"}])
	assert_eq(catalog.size(), 1)
	assert_eq(int(catalog[0]["id"]), 1)


func test_debug_catalog_matches_canonical_schema() -> void:
	# O catálogo de debug precisa ter o MESMO shape do normalizado —
	# a divergência entre eles foi o que mascarou o bug original.
	for entry: Dictionary in LessonServiceScript.DEBUG_CATALOG:
		assert_true(entry.has("id"), "DEBUG_CATALOG usa chave canônica 'id'")
		assert_true(entry.has("nome"), "DEBUG_CATALOG usa chave canônica 'nome'")


# ---------- validação de segurança do .tres remoto ----------

func test_safe_animation_tres_accepted() -> void:
	assert_true(svc._is_safe_animation_tres(SAFE_TRES))


func test_tres_with_ext_resource_rejected() -> void:
	var evil := SAFE_TRES + "\n[ext_resource type=\"Script\" path=\"res://x.gd\" id=\"1\"]\n"
	assert_false(svc._is_safe_animation_tres(evil))


func test_tres_with_embedded_gdscript_rejected() -> void:
	# O vetor clássico de RCE: sub_resource GDScript + script = SubResource
	# executa _init arbitrário no ResourceLoader.load().
	var evil := """[gd_resource type="Animation" format=3]

[sub_resource type="GDScript" id="1"]
script/source = "func _init(): OS.execute(\\"rm\\", [])"

[resource]
script = SubResource("1")
"""
	assert_false(svc._is_safe_animation_tres(evil))


func test_tres_with_script_assignment_rejected() -> void:
	var evil := SAFE_TRES + "script = ExtResource(\"1\")\n"
	assert_false(svc._is_safe_animation_tres(evil))


func test_tres_wrong_resource_type_rejected() -> void:
	var evil := "[gd_resource type=\"PackedScene\" format=3]\n[resource]\n"
	assert_false(svc._is_safe_animation_tres(evil))


func test_tres_garbage_rejected() -> void:
	assert_false(svc._is_safe_animation_tres(""))
	assert_false(svc._is_safe_animation_tres("not a tres at all"))


# ---------- normalização do json_sinal (formato compacto da API) ----------
#
# A API devolve gabaritos como {"frames": [{"t":.., "pose": [{x,y,z,visibility}],
# "hands": {"left":.., "right":..}}]} — sem isso, MotionComparatorValidator
# rejeitava TODO gabarito ("pose com 0 landmarks") e a nota ficava sempre em
# 0% ("Ops! Não conseguimos avaliar sua gravação"), mesmo com tudo certo.

const API_FLAT_JSON_SINAL := {
	"frames": [
		{
			"t": 0.0,
			"pose": [{"x": 0.1, "y": 0.2, "z": 0.3, "visibility": 0.9}],
			"hands": {"left": null, "right": null},
		},
		{
			"t": 0.1,
			"pose": [{"x": 0.15, "y": 0.2, "z": 0.3, "visibility": 0.9}],
			"hands": {
				"left": null,
				"right": [{"x": 0.5, "y": 0.6, "z": 0.0}],
			},
		},
	],
}


func test_normalize_json_sinal_wraps_pose_landmarks() -> void:
	var out: Dictionary = svc._normalize_json_sinal(API_FLAT_JSON_SINAL)
	var frames: Array = out["frames"]
	var pose: Array = frames[0]["pose"]
	assert_eq(pose.size(), 1, "pose vira array de 1 grupo (como o HolisticLandmarker exporta)")
	var landmarks: Array = pose[0]["landmarks"]
	assert_eq(int(landmarks[0]["id"]), 0)
	assert_almost_eq(float(landmarks[0]["x"]), 0.1, 0.0001)


func test_normalize_json_sinal_converts_hands_dict_to_array() -> void:
	var out: Dictionary = svc._normalize_json_sinal(API_FLAT_JSON_SINAL)
	var frames: Array = out["frames"]
	assert_eq((frames[0]["hands"] as Array).size(), 0, "os dois lados null viram array vazio")

	var hands1: Array = frames[1]["hands"]
	assert_eq(hands1.size(), 1)
	assert_eq(String(hands1[0]["handedness"]), "Right")
	assert_eq(int((hands1[0]["landmarks"] as Array)[0]["id"]), 0)


func test_normalize_json_sinal_converts_t_to_timestamp_ms() -> void:
	var out: Dictionary = svc._normalize_json_sinal(API_FLAT_JSON_SINAL)
	var frames: Array = out["frames"]
	assert_eq(int(frames[1]["timestamp_ms"]), 100)


func test_normalize_json_sinal_is_noop_on_canonical_shape() -> void:
	var canonical := {
		"video_info": {"fps": 30.0},
		"frames": [
			{"timestamp_ms": 0, "pose": [{"landmarks": [{"id": 0, "x": 1.0, "y": 2.0, "z": 3.0}]}], "hands": []},
		],
	}
	var out: Dictionary = svc._normalize_json_sinal(canonical)
	assert_eq(out, canonical)


## Ponta a ponta: um json_sinal como a API realmente devolve (fixture
## capturada de GET /exercicio/1) precisa passar no schema do validator e
## pontuar perto de 100% contra si mesmo — antes desta normalização, o
## schema rejeitava e a nota nunca saía do zero.
func test_real_api_json_sinal_scores_against_itself() -> void:
	var file := FileAccess.open("res://tests/fixtures/api_letra_a.json", FileAccess.READ)
	assert_not_null(file, "fixture api_letra_a.json ausente")
	if file == null:
		return
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	var normalized: Dictionary = svc._normalize_json_sinal(raw)

	var ValidatorScript := preload("res://Scripts/MotionWrapper.gd")
	var validator: SignValidator = ValidatorScript.new()

	var schema_error: String = validator.validate_reference_schema(normalized)
	assert_eq(schema_error, "", "gabarito real deveria passar no schema depois de normalizado")

	var result: Dictionary = validator.validate(normalized, normalized)
	assert_true(bool(result.get("ok", false)), "validate() deveria ter sucesso: %s" % result.get("error", ""))
	assert_gt(float(result.get("precision", 0.0)), 0.95, "gabarito comparado com ele mesmo deveria pontuar perto de 100%%")
