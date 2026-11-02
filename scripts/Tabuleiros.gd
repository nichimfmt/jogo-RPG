extends Node3D

# ---------------------------------------------------------------
# CENAS QUE VAMOS USAR (as "peças" do jogo)
# ---------------------------------------------------------------
const CENA_PISO = preload("res://cenas/Piso.tscn")
const CENA_CASA = preload("res://cenas/Casa.tscn")

# ---------------------------------------------------------------
# CONFIGURAÇÕES DO TABULEIRO (você pode mudar estes números)
# ---------------------------------------------------------------
const TAMANHO_CELULA: float = 2.0       # distância entre o centro de uma célula e a vizinha
const LARGURA_TABULEIRO: int = 6        # quantas células no eixo X
const PROFUNDIDADE_TABULEIRO: int = 6   # quantas células no eixo Z
const ALTURA_CASA: float = 1.5          # altura do cubo da casa
const ALTURA_TOPO_PISO: float = 0.0     # altura da superfície do piso (ajuste se a casa ficar afundada/flutuando)

# Se true, o código posiciona a câmera e cria a luz sozinho (bom para testes).
# Quando você quiser usar sua própria câmera/luz, mude para false.
const CONFIGURAR_CENA_AUTOMATICAMENTE: bool = true

const CELULA_INVALIDA: Vector2i = Vector2i(-1, -1)

# ---------------------------------------------------------------
# MEMÓRIA DO TABULEIRO
# ---------------------------------------------------------------
# Guarda qual peça está em qual célula. Exemplo: {(2, 3): <a casa>}
var pecas: Dictionary = {}

# Célula onde está o cursor amarelo (usado pelo teclado)
var cursor_celula: Vector2i = Vector2i(0, 0)

# O quadrado amarelo que mostra onde o cursor está
var marcador: MeshInstance3D


func _ready() -> void:
	gerar_tabuleiro()
	_criar_marcador()
	_atualizar_marcador()
	if CONFIGURAR_CENA_AUTOMATICAMENTE:
		_configurar_camera_e_luz()
	print("Tabuleiro pronto! Setas/WASD = mover cursor | Enter = colocar | Delete = remover | T e Y = testes de comando")


# ===============================================================
# CÂMERA E LUZ (para você conseguir ENXERGAR o tabuleiro)
# ===============================================================

func _configurar_camera_e_luz() -> void:
	# Centro do tabuleiro, em coordenadas do mundo
	var centro_local := Vector3(
		(LARGURA_TABULEIRO - 1) * TAMANHO_CELULA / 2.0,
		ALTURA_TOPO_PISO,
		(PROFUNDIDADE_TABULEIRO - 1) * TAMANHO_CELULA / 2.0)
	var centro := to_global(centro_local)

	# ----- CÂMERA: fica no alto, atrás do tabuleiro, olhando para o centro -----
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		camera = Camera3D.new()
		add_child(camera)
	camera.global_position = centro + Vector3(0.0, 14.0, 16.0)
	camera.look_at(centro, Vector3.UP)
	camera.make_current()

	# ----- LUZ: usa a DirectionalLight3D que já existe ou cria uma -----
	var luzes := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	var luz: DirectionalLight3D
	if luzes.is_empty():
		luz = DirectionalLight3D.new()
		add_child(luz)
	else:
		luz = luzes[0] as DirectionalLight3D
	luz.global_rotation_degrees = Vector3(-50.0, 30.0, 0.0)

	# ----- LUZ AMBIENTE: para as partes sem sol não ficarem pretas -----
	var ambiente := Environment.new()
	ambiente.background_mode = Environment.BG_COLOR
	ambiente.background_color = Color(0.15, 0.17, 0.22)
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambiente.ambient_light_color = Color(1.0, 1.0, 1.0)
	ambiente.ambient_light_energy = 0.5
	var mundo := WorldEnvironment.new()
	mundo.environment = ambiente
	add_child(mundo)


# ===============================================================
# CAMADA 3: O TABULEIRO (faz o trabalho de verdade)
# ===============================================================

func gerar_tabuleiro() -> void:
	for x in range(LARGURA_TABULEIRO):
		for z in range(PROFUNDIDADE_TABULEIRO):
			var piso = CENA_PISO.instantiate()
			add_child(piso)
			piso.position = _celula_para_posicao(Vector2i(x, z), 0.0)


func celula_valida(celula: Vector2i) -> bool:
	return celula.x >= 0 and celula.x < LARGURA_TABULEIRO and celula.y >= 0 and celula.y < PROFUNDIDADE_TABULEIRO


func celula_ocupada(celula: Vector2i) -> bool:
	return pecas.has(celula)


func colocar_casa(celula: Vector2i) -> bool:
	if not celula_valida(celula):
		print("Célula fora do tabuleiro: ", celula)
		return false
	if celula_ocupada(celula):
		print("Já existe uma peça na célula: ", celula)
		return false

	var nova_casa = CENA_CASA.instantiate()
	add_child(nova_casa)
	nova_casa.position = _celula_para_posicao(celula, ALTURA_TOPO_PISO + ALTURA_CASA / 2.0)
	pecas[celula] = nova_casa
	print("Casa colocada na célula: ", celula)
	return true


func remover_peca(celula: Vector2i) -> bool:
	if not celula_ocupada(celula):
		print("Não há peça para remover na célula: ", celula)
		return false

	pecas[celula].queue_free()
	pecas.erase(celula)
	print("Peça removida da célula: ", celula)
	return true


func mover_peca(origem: Vector2i, destino: Vector2i) -> bool:
	if not celula_ocupada(origem):
		print("Não há peça na célula de origem: ", origem)
		return false
	if not celula_valida(destino):
		print("Destino fora do tabuleiro: ", destino)
		return false
	if celula_ocupada(destino):
		print("O destino já está ocupado: ", destino)
		return false

	var peca = pecas[origem]
	pecas.erase(origem)
	pecas[destino] = peca
	peca.position = _celula_para_posicao(destino, ALTURA_TOPO_PISO + ALTURA_CASA / 2.0)
	print("Peça movida de ", origem, " para ", destino)
	return true


# ===============================================================
# CAMADA 2: COMANDOS (é isto que a IA vai usar no futuro)
# ===============================================================
# Exemplos de comando:
#   {"acao": "colocar", "x": 3, "z": 3}
#   {"acao": "remover", "x": 3, "z": 3}
#   {"acao": "mover", "de_x": 3, "de_z": 3, "para_x": 4, "para_z": 3}

func executar_comando(comando: Dictionary) -> bool:
	var acao: String = comando.get("acao", "")
	match acao:
		"colocar":
			return colocar_casa(Vector2i(int(comando["x"]), int(comando["z"])))
		"remover":
			return remover_peca(Vector2i(int(comando["x"]), int(comando["z"])))
		"mover":
			var origem := Vector2i(int(comando["de_x"]), int(comando["de_z"]))
			var destino := Vector2i(int(comando["para_x"]), int(comando["para_z"]))
			return mover_peca(origem, destino)

	print("Comando desconhecido: ", acao)
	return false


# ===============================================================
# CAMADA 1: ENTRADA (teclado e mouse; depois será a IA)
# ===============================================================

func _unhandled_input(event: InputEvent) -> void:
	# ----- MOUSE -----
	if event is InputEventMouseButton and event.pressed:
		var celula := celula_sob_mouse(event.position)
		if not celula_valida(celula):
			return
		cursor_celula = celula
		_atualizar_marcador()
		if event.button_index == MOUSE_BUTTON_LEFT:
			colocar_casa(celula)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			remover_peca(celula)

	# ----- TECLADO -----
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W:
				_mover_cursor(Vector2i(0, -1))
			KEY_DOWN, KEY_S:
				_mover_cursor(Vector2i(0, 1))
			KEY_LEFT, KEY_A:
				_mover_cursor(Vector2i(-1, 0))
			KEY_RIGHT, KEY_D:
				_mover_cursor(Vector2i(1, 0))
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				colocar_casa(cursor_celula)
			KEY_DELETE, KEY_BACKSPACE:
				remover_peca(cursor_celula)
			KEY_T:
				# Simula a IA mandando colocar uma casa na célula 3,3
				executar_comando({"acao": "colocar", "x": 3, "z": 3})
			KEY_Y:
				# Simula a IA mandando mover a peça da célula 3,3 para 4,3
				executar_comando({"acao": "mover", "de_x": 3, "de_z": 3, "para_x": 4, "para_z": 3})


# ===============================================================
# FUNÇÕES AUXILIARES
# ===============================================================

# Converte uma célula (ex.: 2,3) em posição 3D real no mundo.
func _celula_para_posicao(celula: Vector2i, altura: float) -> Vector3:
	return Vector3(celula.x * TAMANHO_CELULA, altura, celula.y * TAMANHO_CELULA)


# Descobre qual célula está embaixo do mouse.
# Em vez de usar colisão, calcula onde o "raio" da câmera cruza o plano do chão.
func celula_sob_mouse(posicao_tela: Vector2) -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return CELULA_INVALIDA

	var origem := camera.project_ray_origin(posicao_tela)
	var direcao := camera.project_ray_normal(posicao_tela)
	var plano := Plane(Vector3.UP, ALTURA_TOPO_PISO)
	var ponto = plano.intersects_ray(origem, direcao)
	if ponto == null:
		return CELULA_INVALIDA

	var local := to_local(ponto)
	return Vector2i(roundi(local.x / TAMANHO_CELULA), roundi(local.z / TAMANHO_CELULA))


func _mover_cursor(direcao: Vector2i) -> void:
	var nova := cursor_celula + direcao
	if celula_valida(nova):
		cursor_celula = nova
		_atualizar_marcador()


func _criar_marcador() -> void:
	marcador = MeshInstance3D.new()
	var malha := BoxMesh.new()
	malha.size = Vector3(TAMANHO_CELULA, 0.05, TAMANHO_CELULA)
	marcador.mesh = malha

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.9, 0.1, 0.6)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marcador.material_override = material

	add_child(marcador)


func _atualizar_marcador() -> void:
	if marcador:
		marcador.position = _celula_para_posicao(cursor_celula, ALTURA_TOPO_PISO + 0.1)
