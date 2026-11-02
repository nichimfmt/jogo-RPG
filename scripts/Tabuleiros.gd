extends Node3D

# ---------------------------------------------------------------
# CENAS QUE VAMOS USAR (as "peças" do jogo)
# ---------------------------------------------------------------
const CENA_PISO = preload("res://cenas/Piso.tscn")
const CENA_CASA = preload("res://cenas/Casa.tscn")

# ---------------------------------------------------------------
# CONFIGURAÇÕES FIXAS (você pode mudar estes números)
# ---------------------------------------------------------------
const TAMANHO_CELULA: float = 2.0       # distância entre o centro de uma célula e a vizinha
const ALTURA_CASA: float = 1.5          # altura do cubo da casa
const ALTURA_TOPO_PISO: float = 0.0     # altura da superfície do piso
const TAMANHO_MINIMO: int = 2           # menor tabuleiro permitido (células por lado)
const TAMANHO_MAXIMO: int = 50          # maior tabuleiro permitido (células por lado)

# Se true, o código posiciona a câmera e cria a luz sozinho (bom para testes).
const CONFIGURAR_CENA_AUTOMATICAMENTE: bool = true

const CELULA_INVALIDA: Vector2i = Vector2i(-1, -1)

# ---------------------------------------------------------------
# CONFIGURAÇÕES DA CÂMERA (você pode mudar estes números)
# ---------------------------------------------------------------
const DISTANCIA_MINIMA: float = 3.0         # o mais perto que dá para chegar
const DISTANCIA_MAXIMA: float = 300.0       # o mais longe que dá para ir
const ZOOM_RODA: float = 0.9                # cada "clique" da roda multiplica a distância por isto (menor = zoom mais forte)
const ZOOM_TECLADO: float = 1.0             # velocidade do zoom pelas teclas R e F
const VELOCIDADE_GIRO: float = 90.0         # graus por segundo (teclas Q, E, Z, X)
const SENSIBILIDADE_MOUSE: float = 0.3      # quão rápido o mouse gira a câmera
const INCLINACAO_MINIMA: float = 10.0       # graus (quase de lado)
const INCLINACAO_MAXIMA: float = 85.0       # graus (quase de cima)

# ---------------------------------------------------------------
# TAMANHO ATUAL DO TABULEIRO (muda durante o jogo)
# Para mudar o tamanho INICIAL, altere estes dois números.
# ---------------------------------------------------------------
var largura_tabuleiro: int = 30          # quantas células no eixo X
var profundidade_tabuleiro: int = 30     # quantas células no eixo Z

# ---------------------------------------------------------------
# MEMÓRIA DO TABULEIRO
# ---------------------------------------------------------------
# Guarda qual peça está em qual célula. Exemplo: {(2, 3): <a casa>}
var pecas: Dictionary = {}

# Lista de todos os pisos criados (para poder recriar ao redimensionar)
var pisos: Array = []

# Célula onde está o cursor amarelo (usado pelo teclado)
var cursor_celula: Vector2i = Vector2i(0, 0)

# O quadrado amarelo que mostra onde o cursor está
var marcador: MeshInstance3D

# ---------------------------------------------------------------
# ESTADO DA CÂMERA
# ---------------------------------------------------------------
var camera: Camera3D
var camera_alvo: Vector3 = Vector3.ZERO     # ponto para onde a câmera olha
var camera_distancia: float = 20.0          # distância até o alvo
var camera_yaw: float = 0.0                 # giro em volta do alvo (graus)
var camera_pitch: float = 42.0              # inclinação (graus)


func _ready() -> void:
	gerar_tabuleiro()
	_criar_marcador()
	_atualizar_marcador()
	if CONFIGURAR_CENA_AUTOMATICAMENTE:
		_configurar_camera_e_luz()
	print("Tabuleiro pronto! WASD/setas = cursor | Enter = colocar | Delete = remover | + e - = tamanho | Roda = zoom | Q/E = girar | Home = resetar câmera")


# ===============================================================
# CÂMERA E LUZ
# ===============================================================

func _configurar_camera_e_luz() -> void:
	# ----- CÂMERA -----
	camera = get_viewport().get_camera_3d()
	if camera == null:
		camera = Camera3D.new()
		add_child(camera)
	camera.make_current()
	_enquadrar_camera()

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


# Volta a câmera para a posição inicial: olhando o tabuleiro inteiro.
func _enquadrar_camera() -> void:
	if camera == null:
		return

	var centro_local := Vector3(
		(largura_tabuleiro - 1) * TAMANHO_CELULA / 2.0,
		ALTURA_TOPO_PISO,
		(profundidade_tabuleiro - 1) * TAMANHO_CELULA / 2.0)
	camera_alvo = to_global(centro_local)

	var maior_lado := float(maxi(largura_tabuleiro, profundidade_tabuleiro))
	camera_distancia = clampf(maior_lado * TAMANHO_CELULA * 1.8, DISTANCIA_MINIMA, DISTANCIA_MAXIMA)
	camera_yaw = 0.0
	camera_pitch = 42.0
	_atualizar_camera()


# Calcula onde a câmera fica (a partir do alvo, da distância e dos ângulos) e aponta para o alvo.
func _atualizar_camera() -> void:
	if camera == null:
		return

	camera_distancia = clampf(camera_distancia, DISTANCIA_MINIMA, DISTANCIA_MAXIMA)
	camera_pitch = clampf(camera_pitch, INCLINACAO_MINIMA, INCLINACAO_MAXIMA)

	var yaw := deg_to_rad(camera_yaw)
	var pitch := deg_to_rad(camera_pitch)
	var deslocamento := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)) * camera_distancia

	camera.global_position = camera_alvo + deslocamento
	camera.look_at(camera_alvo, Vector3.UP)


func _zoom_camera(fator: float) -> void:
	camera_distancia *= fator
	_atualizar_camera()


# Desloca o alvo da câmera para a direita e/ou para a frente (em relação ao que a câmera está vendo).
func _deslocar_camera(direita: float, frente: float) -> void:
	if camera == null:
		return

	var base := camera.global_transform.basis
	var vetor_direita := Vector3(base.x.x, 0.0, base.x.z).normalized()
	var vetor_frente := Vector3(-base.z.x, 0.0, -base.z.z).normalized()
	camera_alvo += vetor_direita * direita + vetor_frente * frente

	# Não deixa a câmera se afastar demais do tabuleiro
	var margem := TAMANHO_CELULA * 3.0
	var local := to_local(camera_alvo)
	local.x = clampf(local.x, -margem, (largura_tabuleiro - 1) * TAMANHO_CELULA + margem)
	local.z = clampf(local.z, -margem, (profundidade_tabuleiro - 1) * TAMANHO_CELULA + margem)
	camera_alvo = to_global(local)

	_atualizar_camera()


# Teclas SEGURADAS (girar, inclinar, zoom e deslocar) são verificadas a cada quadro aqui.
func _process(delta: float) -> void:
	if camera == null:
		return
	# Se estiver digitando num campo de texto (ex.: chat), não mexe na câmera
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return

	# Girar em volta do tabuleiro
	if Input.is_key_pressed(KEY_Q):
		camera_yaw += VELOCIDADE_GIRO * delta
	if Input.is_key_pressed(KEY_E):
		camera_yaw -= VELOCIDADE_GIRO * delta

	# Inclinar
	if Input.is_key_pressed(KEY_Z):
		camera_pitch += VELOCIDADE_GIRO * delta
	if Input.is_key_pressed(KEY_X):
		camera_pitch -= VELOCIDADE_GIRO * delta

	# Zoom
	if Input.is_key_pressed(KEY_R):
		camera_distancia -= camera_distancia * ZOOM_TECLADO * delta
	if Input.is_key_pressed(KEY_F):
		camera_distancia += camera_distancia * ZOOM_TECLADO * delta

	# Deslocar (Shift + WASD ou setas)
	if Input.is_key_pressed(KEY_SHIFT):
		var eixo_x := 0.0
		var eixo_y := 0.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			eixo_x += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			eixo_x -= 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			eixo_y += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			eixo_y -= 1.0
		if eixo_x != 0.0 or eixo_y != 0.0:
			var velocidade := camera_distancia * 0.6 * delta
			_deslocar_camera(eixo_x * velocidade, eixo_y * velocidade)

	_atualizar_camera()


# ===============================================================
# CAMADA 3: O TABULEIRO (faz o trabalho de verdade)
# ===============================================================

func gerar_tabuleiro() -> void:
	# Apaga os pisos antigos (se existirem) antes de criar os novos
	for piso in pisos:
		piso.queue_free()
	pisos.clear()

	for x in range(largura_tabuleiro):
		for z in range(profundidade_tabuleiro):
			var piso = CENA_PISO.instantiate()
			add_child(piso)
			piso.position = _celula_para_posicao(Vector2i(x, z), 0.0)
			pisos.append(piso)


func redimensionar_tabuleiro(nova_largura: int, nova_profundidade: int) -> bool:
	if nova_largura < TAMANHO_MINIMO or nova_profundidade < TAMANHO_MINIMO:
		print("Tamanho muito pequeno. Mínimo: ", TAMANHO_MINIMO)
		return false
	if nova_largura > TAMANHO_MAXIMO or nova_profundidade > TAMANHO_MAXIMO:
		print("Tamanho muito grande. Máximo: ", TAMANHO_MAXIMO)
		return false

	largura_tabuleiro = nova_largura
	profundidade_tabuleiro = nova_profundidade

	# Se o tabuleiro encolheu, remove as peças que ficaram fora dele
	for celula in pecas.keys():
		if not celula_valida(celula):
			remover_peca(celula)

	# Garante que o cursor não fique fora do tabuleiro
	cursor_celula = Vector2i(
		clampi(cursor_celula.x, 0, largura_tabuleiro - 1),
		clampi(cursor_celula.y, 0, profundidade_tabuleiro - 1))

	gerar_tabuleiro()
	_atualizar_marcador()
	_enquadrar_camera()

	print("Tabuleiro redimensionado para ", largura_tabuleiro, " x ", profundidade_tabuleiro)
	return true


func celula_valida(celula: Vector2i) -> bool:
	return celula.x >= 0 and celula.x < largura_tabuleiro and celula.y >= 0 and celula.y < profundidade_tabuleiro


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
#   {"acao": "redimensionar", "largura": 10, "profundidade": 10}

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
		"redimensionar":
			return redimensionar_tabuleiro(int(comando["largura"]), int(comando["profundidade"]))

	print("Comando desconhecido: ", acao)
	return false


# ===============================================================
# CAMADA 1: ENTRADA (teclado e mouse; depois será a IA)
# ===============================================================

# MOUSE: usa _input para receber o clique ANTES da interface (painéis, chat).
func _input(event: InputEvent) -> void:
	var controle: Control = get_viewport().gui_get_hovered_control()

	# ----- MOVIMENTO DO MOUSE: girar / inclinar / deslocar a câmera -----
	var movimento := event as InputEventMouseMotion
	if movimento != null:
		var botao_meio := (movimento.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0
		var alt_com_esquerdo := Input.is_key_pressed(KEY_ALT) and (movimento.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if camera != null and (botao_meio or alt_com_esquerdo):
			if movimento.shift_pressed:
				# Shift + arrastar = deslocar
				var fator := camera_distancia * 0.0015
				_deslocar_camera(-movimento.relative.x * fator, movimento.relative.y * fator)
			else:
				# Arrastar = girar e inclinar
				camera_yaw -= movimento.relative.x * SENSIBILIDADE_MOUSE
				camera_pitch += movimento.relative.y * SENSIBILIDADE_MOUSE
				_atualizar_camera()
		return

	var clique := event as InputEventMouseButton
	if clique == null or not clique.pressed:
		return

	# ----- RODA DO MOUSE: zoom -----
	if clique.button_index == MOUSE_BUTTON_WHEEL_UP:
		if not (controle is ScrollContainer):
			_zoom_camera(ZOOM_RODA)
		return
	if clique.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not (controle is ScrollContainer):
			_zoom_camera(1.0 / ZOOM_RODA)
		return

	# ----- CLIQUES: colocar / remover casa -----
	if clique.button_index != MOUSE_BUTTON_LEFT and clique.button_index != MOUSE_BUTTON_RIGHT:
		return
	# Com Alt apertado o clique é para girar a câmera, não para colocar casa
	if Input.is_key_pressed(KEY_ALT):
		return
	# Se o clique foi em cima de um botão da interface, deixa o botão cuidar dele
	if controle is BaseButton:
		return

	var celula := celula_sob_mouse(clique.position)
	if not celula_valida(celula):
		return

	cursor_celula = celula
	_atualizar_marcador()
	if clique.button_index == MOUSE_BUTTON_LEFT:
		colocar_casa(celula)
	else:
		remover_peca(celula)


# TECLADO (teclas de um toque só)
func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return

	# Com Shift apertado, WASD/setas deslocam a câmera (veja _process), não o cursor
	var cursor_liberado := not tecla.shift_pressed

	match tecla.keycode:
		KEY_UP, KEY_W:
			if cursor_liberado:
				_mover_cursor(Vector2i(0, -1))
		KEY_DOWN, KEY_S:
			if cursor_liberado:
				_mover_cursor(Vector2i(0, 1))
		KEY_LEFT, KEY_A:
			if cursor_liberado:
				_mover_cursor(Vector2i(-1, 0))
		KEY_RIGHT, KEY_D:
			if cursor_liberado:
				_mover_cursor(Vector2i(1, 0))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			colocar_casa(cursor_celula)
		KEY_DELETE, KEY_BACKSPACE:
			remover_peca(cursor_celula)
		KEY_HOME, KEY_C:
			_enquadrar_camera()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			# Simula a IA mandando aumentar o tabuleiro em 1 célula
			executar_comando({"acao": "redimensionar", "largura": largura_tabuleiro + 1, "profundidade": profundidade_tabuleiro + 1})
		KEY_MINUS, KEY_KP_SUBTRACT:
			# Simula a IA mandando diminuir o tabuleiro em 1 célula
			executar_comando({"acao": "redimensionar", "largura": largura_tabuleiro - 1, "profundidade": profundidade_tabuleiro - 1})
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
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return CELULA_INVALIDA

	var origem := cam.project_ray_origin(posicao_tela)
	var direcao := cam.project_ray_normal(posicao_tela)
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
