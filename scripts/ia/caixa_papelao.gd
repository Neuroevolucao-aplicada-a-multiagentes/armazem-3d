extends RefCounted

## Caixa de papelao com a mesma textura das caixas das prateleiras. A textura e
## uma planificacao em cruz, entao a malha e montada face a face.

const TAMANHO := Vector3(0.6, 0.46, 0.53)
const TEXTURA := preload("res://models/shelving/warehouse_shelving_unit_0.jpg")

# Limites da cruz na textura, em pixels: tampa de 298 a 725 em x e de 318 a 695
# em y; as abas vao ate as bordas ocupadas da imagem.
const U0 := 298.0 / 1024.0
const U1 := 726.0 / 1024.0
const V0 := 318.0 / 1024.0
const V1 := 696.0 / 1024.0
const U_ESQ := 1.0 / 1024.0
const U_DIR := 1022.0 / 1024.0
const V_CIMA := 3.0 / 1024.0
const V_BAIXO := 1010.0 / 1024.0

static var _malha: ArrayMesh


static func malha() -> ArrayMesh:
	if _malha != null:
		return _malha
	var hx := TAMANHO.x * 0.5
	var hy := TAMANHO.y * 0.5
	var hz := TAMANHO.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tampa: o alto da imagem fica para -z e a esquerda para -x.
	_face(st, Vector3.UP,
		[Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz)],
		[Vector2(U0, V0), Vector2(U1, V0), Vector2(U1, V1), Vector2(U0, V1)])
	# Cada aba encosta na tampa pela aresta de cima da lateral.
	_face(st, Vector3.FORWARD,
		[Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz)],
		[Vector2(U0, V0), Vector2(U1, V0), Vector2(U1, V_CIMA), Vector2(U0, V_CIMA)])
	_face(st, Vector3.BACK,
		[Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz)],
		[Vector2(U0, V1), Vector2(U1, V1), Vector2(U1, V_BAIXO), Vector2(U0, V_BAIXO)])
	_face(st, Vector3.LEFT,
		[Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz)],
		[Vector2(U0, V0), Vector2(U0, V1), Vector2(U_ESQ, V1), Vector2(U_ESQ, V0)])
	_face(st, Vector3.RIGHT,
		[Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz)],
		[Vector2(U1, V0), Vector2(U1, V1), Vector2(U_DIR, V1), Vector2(U_DIR, V0)])
	# O fundo nao tem desenho proprio na planificacao; repete a tampa.
	_face(st, Vector3.DOWN,
		[Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz)],
		[Vector2(U0, V0), Vector2(U1, V0), Vector2(U1, V1), Vector2(U0, V1)])
	_malha = st.commit()
	return _malha


## Material da caixa. Com brilho, ganha um leve tom da cor dada, como a caixa
## que marca a proxima coleta.
static func material(brilho: Color = Color.BLACK, energia: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = TEXTURA
	mat.roughness = 0.9
	# A malha e montada a mao: sem descarte de faces, a ordem dos vertices nao
	# importa para a caixa aparecer.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if energia > 0.0:
		mat.emission_enabled = true
		mat.emission = brilho
		mat.emission_energy_multiplier = energia
	return mat


static func _face(st: SurfaceTool, normal: Vector3, v: Array, uv: Array) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(uv[i])
		st.add_vertex(v[i])
