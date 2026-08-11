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
