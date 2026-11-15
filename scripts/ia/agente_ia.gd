class_name AgenteIA
extends CharacterBody3D

## Emitido ao alcancar o ponto de coleta. O gerenciador apaga o marcador.
signal coletou
## Emitido ao concluir a entrega. O gerenciador sorteia uma vaga nova.
signal entregou

const CaixaPapelao := preload("res://scripts/ia/caixa_papelao.gd")

# Area util: x ~6..34, z ~-98..-24, diagonal ~79 u. As grandezas abaixo mantem
# as proporcoes do treino em relacao a diagonal (docs/contrato_ambiente.md).
const DIAGONAL_MAPA := 79.0
const ALCANCE_RAY := DIAGONAL_MAPA * 0.203        # 220 / 1081 no treino
const VELOCIDADE_AGENTE := DIAGONAL_MAPA * 0.185  # 200 px/s / 1081
const RAIO_COLETA := DIAGONAL_MAPA * 0.0185       # 20 / 1081
const RAIO_ENTREGA := DIAGONAL_MAPA * 0.0324      # 35 / 1081

const NUM_RAYS := 8
const DURACAO_CICLO := 45.0
const CAMINHO_REDE := "res://assets/melhor_rede_fase5.json"

# layer 1 = estaticos (prateleiras, chao), layer 2 = agentes. Os agentes
# colidem entre si e aparecem nos raycasts uns dos outros.
const MASCARA_PERCEPCAO := 1 | 2

# Altura dos raycasts: o centro da capsula de colisao, e nao a origem do no,
# que fica abaixo das prateleiras.
const ALTURA_SENSOR := 1.275

# --- Camada de recuperacao (fora da rede) -----------------------------------
# A rede foi treinada para evitar contato, nao para sair dele: encostada numa
# parede, recebe sempre as mesmas entradas e fica parada. Esta camada faz o
# agente deslizar ao longo do obstaculo.
const TEMPO_ATE_DESENCALHE := 0.5   # segundos em contato sem avancar
const DURACAO_DESENCALHE := 0.6     # duracao do empurrao lateral
const DESLOCAMENTO_MINIMO := 0.05   # por frame, para considerar que avancou

@export var alvo: Node3D
@export var zona_entrega: Node3D
@export var carregando_item: bool = false
@export var mostrar_debug: bool = false
@export var usar_desencalhe: bool = true

var rede: RedeNeural
var tempo_ciclo: float = 0.0
var itens_entregues: int = 0
var desencalhes: int = 0
# Quadros sem deslocamento apreciavel, para medir tempo travado.
var quadros_sem_avancar: int = 0
var quadros_avaliados: int = 0

var _alvo_pacote: Node3D
var _raycasts: Array[RayCast3D] = []
var _ultimo_heading: float = 0.0
var _caixa: MeshInstance3D
## Segundos parado ao coletar, enquanto a caixa passa para o robo.
var pausa_coleta: float = 0.0
var _tempo_pausa: float = 0.0
var _pos_anterior := Vector3.ZERO
var _tempo_travado := 0.0
var _tempo_desencalhe := 0.0
var _dir_desencalhe := Vector2.ZERO

func _ready() -> void:
	rede = RedeNeural.new()
	if not rede.carregar(CAMINHO_REDE):
		push_error("AgenteIA [%s]: falha ao carregar rede neural" % name)

	collision_layer = 2
	collision_mask = MASCARA_PERCEPCAO

	for i in NUM_RAYS:
		var ray := RayCast3D.new()
		ray.name = "Ray%d" % i
		ray.enabled = true
		ray.exclude_parent = true
		ray.collision_mask = MASCARA_PERCEPCAO
		ray.position = Vector3(0.0, ALTURA_SENSOR, 0.0)
		ray.target_position = Vector3(ALCANCE_RAY, 0.0, 0.0)
		add_child(ray)
		_raycasts.append(ray)

	_criar_visual_carga()
	_pos_anterior = global_position

func _criar_visual_carga() -> void:
	# A caixa que o robo leva, visivel so entre a coleta e a entrega.
	_caixa = MeshInstance3D.new()
	_caixa.mesh = CaixaPapelao.malha()
	_caixa.material_override = CaixaPapelao.material()
	_caixa.position = Vector3(0.0, 1.95, 0.0)
	_caixa.visible = false
	add_child(_caixa)

## A caixa em cima do robo aparece quando a animacao de transferencia termina.
func mostrar_carga(visivel: bool) -> void:
	if _caixa != null:
		_caixa.visible = visivel


func posicao_carga() -> Vector3:
	return _caixa.global_position if _caixa != null else global_position


func configurar(pacote: Node3D, entrega: Node3D) -> void:
	_alvo_pacote = pacote
	zona_entrega = entrega
	alvo = _alvo_pacote


## Reposiciona o ponto que o agente persegue. A rede so enxerga a direcao e a
## distancia ate ele, nunca a posicao.
func mover_alvo_pacote(pos: Vector3) -> void:
	if _alvo_pacote != null:
		_alvo_pacote.global_position = pos

func _physics_process(delta: float) -> void:
	tempo_ciclo += delta

	if not is_on_floor():
		velocity.y -= 9.8 * delta
		# Sem movimento horizontal ate pousar.
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# Zera a velocidade vertical ao pousar; sem isso o corpo alternava entre chao
	# e ar e o agente ficava parado.
	velocity.y = 0.0

	if rede.w1.is_empty() or alvo == null:
		move_and_slide()
		return

	# Parado durante o carregamento, antes da rede e da camada de recuperacao.
	if _tempo_pausa > 0.0:
		_tempo_pausa -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_pos_anterior = global_position
		return

	var inputs := _montar_inputs()
	var output := rede.forward(inputs)

	var vel2d := Vector2(output[0], output[1])
	if vel2d.length() > 1.0:
		vel2d = vel2d.normalized()

	# Quando ativa, a camada de recuperacao substitui a saida da rede, que
	# continua sendo avaliada.
	if _tempo_desencalhe > 0.0:
		_tempo_desencalhe -= delta
		velocity.x = _dir_desencalhe.x * VELOCIDADE_AGENTE
		velocity.z = _dir_desencalhe.y * VELOCIDADE_AGENTE
	else:
		velocity.x = vel2d.x * VELOCIDADE_AGENTE
		velocity.z = vel2d.y * VELOCIDADE_AGENTE

	move_and_slide()

	if usar_desencalhe:
		_atualizar_desencalhe(delta)
	_pos_anterior = global_position

	_verificar_coleta_entrega()

	if mostrar_debug:
		var adx := alvo.global_position.x - global_position.x
		var adz := alvo.global_position.z - global_position.z
		var raio_min := 1.0
		for r in inputs.slice(8):
			raio_min = minf(raio_min, float(r))
		print("AgenteIA[%s] pos=(%.1f,%.1f,%.1f) dist2d=%.1f |v|=%.1f raio_min=%.2f colis=%d desenc=%d%s carr=%s itens=%d" % [
			name,
			global_position.x, global_position.y, global_position.z,
			sqrt(adx * adx + adz * adz),
			Vector2(velocity.x, velocity.z).length(),
			raio_min,
			get_slide_collision_count(),
			desencalhes,
			"*" if _tempo_desencalhe > 0.0 else " ",
			str(carregando_item),
			itens_entregues
		])

func _atualizar_desencalhe(delta: float) -> void:
	# Considera travado quem esta em contato com algo que nao e o chao e nao
	# conseguiu se deslocar de forma apreciavel neste frame.
	var avancou := _pos_anterior.distance_to(global_position) > DESLOCAMENTO_MINIMO
	quadros_avaliados += 1
	if not avancou:
		quadros_sem_avancar += 1

	if avancou or _tempo_desencalhe > 0.0:
		_tempo_travado = 0.0
		return

	_tempo_travado += delta
	if _tempo_travado < TEMPO_ATE_DESENCALHE:
		return

	_tempo_travado = 0.0
	var direcao := _direcao_de_escape()
	if direcao == Vector2.ZERO:
		return

	_dir_desencalhe = direcao
	_tempo_desencalhe = DURACAO_DESENCALHE
	desencalhes += 1


func _direcao_de_escape() -> Vector2:
	# Normal media das paredes tocadas neste frame, descartando o chao.
	var normal := Vector2.ZERO
	for i in get_slide_collision_count():
		var n: Vector3 = get_slide_collision(i).get_normal()
		if absf(n.y) > 0.7:
			continue
		normal += Vector2(n.x, n.z)

	if normal.length() < 0.01:
		return Vector2.ZERO
	normal = normal.normalized()

	# Desliza ao longo da parede, no sentido que aproxima do alvo.
	var tangente := Vector2(-normal.y, normal.x)
	if alvo != null:
		var para_alvo := Vector2(
			alvo.global_position.x - global_position.x,
			alvo.global_position.z - global_position.z
		)
		if para_alvo.length() > 0.001 and tangente.dot(para_alvo.normalized()) < 0.0:
			tangente = -tangente

	# Um pouco de normal junto para descolar da parede antes de deslizar.
	return (tangente * 0.8 + normal * 0.6).normalized()


func _verificar_coleta_entrega() -> void:
	if alvo == null or zona_entrega == null or _alvo_pacote == null:
		return
	var dx := alvo.global_position.x - global_position.x
	var dz := alvo.global_position.z - global_position.z
	var raio: float = RAIO_ENTREGA if carregando_item else RAIO_COLETA
	if sqrt(dx * dx + dz * dz) >= raio:
		return
	if not carregando_item:
		carregando_item = true
		alvo = zona_entrega
		_tempo_pausa = pausa_coleta
		tempo_ciclo = 0.0
		coletou.emit()
	else:
		carregando_item = false
		itens_entregues += 1
		alvo = _alvo_pacote
		if _caixa != null:
			_caixa.visible = false
		tempo_ciclo = 0.0
		entregou.emit()

func _montar_inputs() -> Array:
	var pos := global_position
	var pos_alvo := alvo.global_position

	var dx := pos_alvo.x - pos.x
	var dz := pos_alvo.z - pos.z
	var dist := sqrt(dx * dx + dz * dz)
	var dir_alvo_x := dx / (dist + 1e-6)
	var dir_alvo_z := dz / (dist + 1e-6)

	var dx_ent := dir_alvo_x
	var dz_ent := dir_alvo_z
	if zona_entrega != null:
		var pe := zona_entrega.global_position
		var ddx := pe.x - pos.x
		var ddz := pe.z - pos.z
		var de := sqrt(ddx * ddx + ddz * ddz)
		dx_ent = ddx / (de + 1e-6)
		dz_ent = ddz / (de + 1e-6)

	# O input 6 e o modulo da velocidade normalizada, como no treino.
	var vel_plano := Vector2(velocity.x, velocity.z)
	var vel_mag := minf(vel_plano.length() / VELOCIDADE_AGENTE, 1.0)

	# heading no plano XZ: equivalente ao atan2(vel.y, vel.x) do pygame
	var heading: float
	if vel_plano.length() > 0.01 * VELOCIDADE_AGENTE:
		heading = atan2(velocity.z, velocity.x)
	else:
		heading = atan2(dz, dx) if (dx != 0.0 or dz != 0.0) else 0.0
	_ultimo_heading = heading

	var rays := _get_ray_distances(heading)
	var tempo_norm := minf(tempo_ciclo / DURACAO_CICLO, 1.0)

	var inputs: Array = [
		dir_alvo_x,
		dir_alvo_z,
		dist / DIAGONAL_MAPA,
		1.0 if carregando_item else 0.0,
		dx_ent,
		dz_ent,
		vel_mag,
		tempo_norm,
	]
	inputs.append_array(rays)
	return inputs

func _get_ray_distances(heading: float) -> Array:
	var distancias: Array = []
	for i in NUM_RAYS:
		var ang := heading + (float(i) / NUM_RAYS) * TAU
		var ray: RayCast3D = _raycasts[i]
		ray.target_position = Vector3(cos(ang), 0.0, sin(ang)) * ALCANCE_RAY
		ray.force_raycast_update()
		var d: float
		if ray.is_colliding():
			d = ray.get_collision_point().distance_to(ray.global_position)
		else:
			d = ALCANCE_RAY
		distancias.append(d / ALCANCE_RAY)
	return distancias
