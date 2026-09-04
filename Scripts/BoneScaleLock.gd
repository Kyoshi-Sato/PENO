@tool
class_name BoneScaleLock
extends SkeletonModifier3D
## Trava o scale de ossos específicos do Skeleton3D pai.
##
## Roda na fase de modificação do esqueleto, ou seja, DEPOIS do
## AnimationPlayer escrever as poses. Qualquer scale vindo da animação
## é sobrescrito, resolvendo a boneca "cabeçuda" quando as animações
## importadas trazem scale no pescoço/cabeça.

## Nomes dos ossos cujo scale deve ficar travado.
@export var locked_bones: PackedStringArray = ["BnPescoco", "BnCabeca"]:
	set(value):
		locked_bones = value
		_dirty = true

## Se true, força scale (1, 1, 1). Se false, usa o scale do rest do osso.
@export var force_uniform: bool = false:
	set(value):
		force_uniform = value
		_dirty = true

## Índices resolvidos e o scale alvo de cada um, na mesma ordem.
var _bone_ids: PackedInt32Array = PackedInt32Array()
var _target_scales: PackedVector3Array = PackedVector3Array()
var _dirty: bool = true


func _skeleton_changed(_old_skeleton: Skeleton3D, _new_skeleton: Skeleton3D) -> void:
	_dirty = true


## Resolve nomes -> índices. O esqueleto só fica disponível depois que o nó
## entra na árvore, por isso a resolução é preguiçosa em vez de feita no _ready.
func _resolve_bones(skeleton: Skeleton3D) -> void:
	_dirty = false
	_bone_ids = PackedInt32Array()
	_target_scales = PackedVector3Array()

	for bone_name: String in locked_bones:
		var idx: int = skeleton.find_bone(bone_name)
		if idx == -1:
			push_warning("BoneScaleLock: osso não encontrado: %s" % bone_name)
			continue
		_bone_ids.append(idx)
		if force_uniform:
			_target_scales.append(Vector3.ONE)
		else:
			_target_scales.append(skeleton.get_bone_rest(idx).basis.get_scale())


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	if _dirty:
		_resolve_bones(skeleton)

	for i: int in _bone_ids.size():
		skeleton.set_bone_pose_scale(_bone_ids[i], _target_scales[i])
