extends Node3D

# ---------------------------------------------------------------
# CENAS QUE VAMOS USAR
# ---------------------------------------------------------------
# Por enquanto todo personagem é um cubo (Casa.tscn). O código troca a cor.
const CENA_PERSONAGEM = preload("res://cenas/Casa.tscn")
const CENA_PISO = preload("res://cenas/Piso.tscn")

# ---------------------------------------------------------------
# CONFIGURAÇÕES DO TABULEIRO
# ---------------------------------------------------------------
const TAMANHO_CELULA: float = 2.0       # distância entre o centro de uma célula e a vizinha
const ALTURA_PERSONAGEM: float = 1.5    # altura do cubo do personagem
const ALTURA_TOPO_PISO: float = 0.0     # altura da superfície do piso
const TAMANHO_MINIMO: int = 2           # menor tabuleiro permitido (células por lado)
const TAMANHO_MAXIMO: int = 50          # maior tabuleiro permitido (células por lado)

# Alturas dos desenhos por cima do piso (o destaque verde fica embaixo do quadrado amarelo)
const ALTURA_DESTAQUE: float = 0.12
const ALTURA_MARCADOR: float = 0.18

# Se true, o código posiciona a câmera e cria a luz sozinho (bom para testes).
const CONFIGURAR_CENA_AUTOMATICAMENTE: bool = true

const CELULA_INVALIDA: Vector2i = Vector2i(-1, -1)

# ---------------------------------------------------------------
# CONFIGURAÇÕES DOS PERSONAGENS E DOS TURNOS
# ---------------------------------------------------------------
const COR_IA: Color = Color(0.85, 0.1, 0.1)          # vermelho
const COR_JOGADOR: Color = Color(0.1, 0.4, 1.0)      # azul

# Velocidade por raça, em CÉLULAS (1 célula = 5 pés, como no D&D: 30 pés = 6 células)
const VELOCIDADE_POR_RACA: Dictionary = {
	"Humano": 6,
	"Elfo": 6,
	"Meio-Elfo": 6,
	"Meio-Orc": 6,
	"Anão": 5,
	"Halfling": 5,
	"Gnomo": 5,
}

# Valores pelos quais o botão "Distância máxima" vai alternando (para testes)
const OPCOES_DISTANCIA: Array[int] = [3, 5, 6, 8, 10]

# Cria 1 jogador e 2 personagens da IA ao iniciar (para você testar logo)
const CRIAR_PERSONAGENS_DE_TESTE: bool = true

# Enquanto a IA de verdade não existe, os personagens vermelhos andam aleatoriamente no turno da IA
const IA_SIMULADA_MOVE_PECAS: bool = true
const VELOCIDADE_IA_SIMULADA: int = 3

# ---------------------------------------------------------------
# CONFIGURAÇÕES DA CÂMERA
# ---------------------------------------------------------------
const DISTANCIA_MINIMA: float = 3.0         # o mais perto que dá para chegar
const DISTANCIA_MAXIMA: float = 300.0       # o mais longe que dá para ir
const ZOOM_RODA: float = 0.9                # cada "clique" da roda multiplica a distância por isto
const ZOOM_TECLADO: float = 1.0             # velocidade do zoom pelas teclas R e F
const VELOCIDADE_GIRO: float = 90.0         # graus por segundo (teclas Q, E, Z, X)
const SENSIBILIDADE_MOUSE: float = 0.3      # quão rápido o mouse gira a câmera
const INCLINACAO_MINIMA: float = 10.0       # graus (quase de lado)
const INCLINACAO_MAXIMA: float = 85.0       # graus (quase de cima)

# ---------------------------------------------------------------
# TAMANHO ATUAL DO TABULEIRO (muda durante o jogo)
# ---------------------------------------------------------------
var largura_tabuleiro: int = 6          # quantas células no eixo X
var profundidade_tabuleiro: int = 6     # quantas células no eixo Z

# ---------------------------------------------------------------
# MEMÓRIA DO TABULEIRO
# ---------------------------------------------------------------
# Guarda qual personagem está em qual célula. Exemplo: {(2, 3): <cubo>}
var pecas: Dictionary = {}

# Lista de todos os pisos criados (para poder recriar ao redimensionar)
var pisos: Array = []

# Célula onde está o cursor amarelo
var cursor_celula: Vector2i = Vector2i(0, 0)

# O quadrado amarelo que mostra onde o cursor está
var marcador: MeshInstance3D

# ---------------------------------------------------------------
# ESTADO DOS TURNOS E DO JOGADOR
# ---------------------------------------------------------------
enum Turno { JOGADOR, IA }

var turno_atual: Turno = Turno.JOGADOR
var rodada: int = 1
var raca_jogador: String = "Meio-Elfo"
var distancia_maxima: int = 6               # quantas células o jogador pode andar por turno
var movimento_restante: int = 6             # quantas ainda sobram neste turno
var indice_distancia: int = 0               # posição na lista OPCOES_DISTANCIA
var celula_jogador: Vector2i = CELULA_INVALIDA
var aviso: String = ""                      # mensagem curta mostrada na tela

# ---------------------------------------------------------------
# PEÇAS VISUAIS EXTRAS (destaque verde e interface)
# ---------------------------------------------------------------
var destaques: Node3D
var malha_destaque: BoxMesh
var material_destaque: StandardMaterial3D

var interface: CanvasLayer
var rotulo_status: Label
var botao_distancia: Button
var botao_turno: Button

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
	_criar_destaques()
	_criar_interface()
	if CONFIGURAR_CENA_AUTOMATICAMENTE:
		_configurar_camera_e_luz()

	# Velocidade inicial do jogador, de acordo com a raça
	distancia_maxima = int(VELOCIDADE_POR_RACA.get(raca_jogador, 6))
	indice_distancia = maxi(OPCOES_DISTANCIA.find(distancia_maxima), 0)
	movimento_restante = distancia_maxima

	if CRIAR_PERSONAGENS_DE_TESTE:
		colocar_personagem(Vector2i(1, 1), "jogador")
		colocar_personagem(Vector2i(4, 3), "ia")
		colocar_personagem(Vector2i(3, 5), "ia")

	_atualizar_marcador()
	_atualizar_destaques()
	_atualizar_interface()
	print("Tabuleiro pronto! Setas = cursor | Enter = mover jogador | Espaço = encerrar turno | WASD = câmera | N = IA de teste | P = jogador")


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

	# Deslocar a câmera com W A S D
	var eixo_x := 0.0
	var eixo_y := 0.0
	if Input.is_key_pressed(KEY_D):
		eixo_x += 1.0
	if Input.is_key_pressed(KEY_A):
		eixo_x -= 1.0
	if Input.is_key_pressed(KEY_W):
		eixo_y += 1.0
	if Input.is_key_pressed(KEY_S):
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

	# Não deixa o tabuleiro encolher se o jogador ficaria para fora
	if celula_jogador != CELULA_INVALIDA and (celula_jogador.x >= nova_largura or celula_jogador.y >= nova_profundidade):
		_mostrar_aviso("Não dá para diminuir: o jogador ficaria fora do tabuleiro.")
		return false

	largura_tabuleiro = nova_largura
	profundidade_tabuleiro = nova_profundidade

	# Se o tabuleiro encolheu, remove os personagens que ficaram fora dele
	for celula in pecas.keys():
		if not celula_valida(celula):
			remover_peca(celula)

	# Garante que o cursor não fique fora do tabuleiro
	cursor_celula = Vector2i(
		clampi(cursor_celula.x, 0, largura_tabuleiro - 1),
		clampi(cursor_celula.y, 0, profundidade_tabuleiro - 1))

	gerar_tabuleiro()
	_atualizar_marcador()
	_atualizar_destaques()
	_enquadrar_camera()

	print("Tabuleiro redimensionado para ", largura_tabuleiro, " x ", profundidade_tabuleiro)
	return true


func celula_valida(celula: Vector2i) -> bool:
	return celula.x >= 0 and celula.x < largura_tabuleiro and celula.y >= 0 and celula.y < profundidade_tabuleiro


func celula_ocupada(celula: Vector2i) -> bool:
	return pecas.has(celula)


# tipo: "ia" (cubo vermelho) ou "jogador" (cubo azul, só pode existir um)
func colocar_personagem(celula: Vector2i, tipo: String = "ia") -> bool:
	if not celula_valida(celula):
		print("Célula fora do tabuleiro: ", celula)
		return false
	if celula_ocupada(celula):
		print("Já existe uma peça na célula: ", celula)
		return false
	if tipo == "jogador" and celula_jogador != CELULA_INVALIDA:
		print("O personagem do jogador já está no tabuleiro.")
		return false

	var peca: Node3D = CENA_PERSONAGEM.instantiate()
	add_child(peca)
	peca.position = _celula_para_posicao(celula, ALTURA_TOPO_PISO + ALTURA_PERSONAGEM / 2.0)
	peca.set_meta("tipo", tipo)
	_pintar_peca(peca, tipo)
	pecas[celula] = peca

	if tipo == "jogador":
		celula_jogador = celula
		_atualizar_destaques()
		_atualizar_interface()

	print("Personagem (", tipo, ") colocado na célula: ", celula)
	return true


func remover_peca(celula: Vector2i) -> bool:
	if not celula_ocupada(celula):
		print("Não há peça para remover na célula: ", celula)
		return false

	var peca: Node3D = pecas[celula]
	if peca.get_meta("tipo", "") == "jogador":
		celula_jogador = CELULA_INVALIDA
	peca.queue_free()
	pecas.erase(celula)
	print("Peça removida da célula: ", celula)

	_atualizar_destaques()
	_atualizar_interface()
	return true


# Remove só personagens da IA (usado pelo teclado e pelo clique direito)
func remover_personagem_ia(celula: Vector2i) -> bool:
	if not celula_ocupada(celula):
		print("Não há peça para remover na célula: ", celula)
		return false
	if pecas[celula].get_meta("tipo", "") == "jogador":
		_mostrar_aviso("O personagem do jogador não pode ser removido por aqui.")
		return false
	return remover_peca(celula)


# Move qualquer peça (a IA usa isto pelo comando "mover"; não gasta movimento do jogador)
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

	var peca: Node3D = pecas[origem]
	pecas.erase(origem)
	pecas[destino] = peca

	if peca.get_meta("tipo", "") == "jogador":
		celula_jogador = destino

	# Desliza suavemente até o destino
	var alvo := _celula_para_posicao(destino, ALTURA_TOPO_PISO + ALTURA_PERSONAGEM / 2.0)
	var animacao := peca.create_tween()
	animacao.tween_property(peca, "position", alvo, 0.25)

	print("Peça movida de ", origem, " para ", destino)
	return true


# ===============================================================
# TURNOS E MOVIMENTO DO JOGADOR
# ===============================================================

# Calcula todas as células que dá para alcançar a partir de "origem" andando no máximo "limite" células.
# Diagonal conta como 1 célula. Células ocupadas por outras peças bloqueiam o caminho.
# Retorna um dicionário no formato {célula: custo em células}.
func _calcular_alcance(origem: Vector2i, limite: int) -> Dictionary:
	var custos := {origem: 0}
	var fila: Array[Vector2i] = [origem]
	var indice := 0

	while indice < fila.size():
		var atual: Vector2i = fila[indice]
		indice += 1
		var custo_atual: int = custos[atual]
		if custo_atual >= limite:
			continue

		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var vizinha := atual + Vector2i(dx, dz)
				if not celula_valida(vizinha) or custos.has(vizinha) or celula_ocupada(vizinha):
					continue
				custos[vizinha] = custo_atual + 1
				fila.append(vizinha)

	return custos


func mover_jogador(destino: Vector2i) -> bool:
	if turno_atual != Turno.JOGADOR:
		_mostrar_aviso("Não é o seu turno! Aguarde a IA terminar.")
		return false
	if celula_jogador == CELULA_INVALIDA:
		_mostrar_aviso("O personagem do jogador não está no tabuleiro (aperte P para colocar).")
		return false
	if destino == celula_jogador:
		return false

	var alcance := _calcular_alcance(celula_jogador, movimento_restante)
	if not alcance.has(destino):
		_mostrar_aviso("Fora do alcance! Você ainda pode andar %d célula(s) neste turno." % movimento_restante)
		return false

	var custo: int = alcance[destino]
	if not mover_peca(celula_jogador, destino):
		return false

	movimento_restante -= custo
	aviso = ""
	_atualizar_destaques()
	_atualizar_interface()
	return true


func encerrar_turno() -> void:
	if turno_atual != Turno.JOGADOR:
		return

	turno_atual = Turno.IA
	aviso = ""
	_atualizar_destaques()
	_atualizar_interface()
	print("--- Turno da IA ---")

	await _executar_turno_da_ia()
	_iniciar_turno_do_jogador()


func _iniciar_turno_do_jogador() -> void:
	rodada += 1
	turno_atual = Turno.JOGADOR
	movimento_restante = distancia_maxima
	aviso = ""
	_atualizar_destaques()
	_atualizar_interface()
	print("--- Turno do jogador (rodada ", rodada, ") ---")


# AQUI, no futuro, a IA de verdade vai mandar seus comandos pelo executar_comando().
# Por enquanto, cada personagem vermelho anda para um lugar aleatório perto dele.
func _executar_turno_da_ia() -> void:
	if IA_SIMULADA_MOVE_PECAS:
		var personagens_ia: Array = []
		for celula in pecas.keys():
			if pecas[celula].get_meta("tipo", "") == "ia":
				personagens_ia.append(celula)

		for origem in personagens_ia:
			await get_tree().create_timer(0.5).timeout
			if not pecas.has(origem):
				continue
			var alcance := _calcular_alcance(origem, VELOCIDADE_IA_SIMULADA)
			var opcoes: Array = alcance.keys()
			opcoes.erase(origem)
			if opcoes.is_empty():
				continue
			var destino: Vector2i = opcoes.pick_random()
			executar_comando({"acao": "mover", "de_x": origem.x, "de_z": origem.y, "para_x": destino.x, "para_z": destino.y})

	await get_tree().create_timer(0.6).timeout


# Muda a distância máxima que o jogador anda por turno (usado pelo botão de teste e, no futuro, pela ficha/IA).
func definir_distancia_maxima(celulas: int) -> bool:
	if celulas < 1 or celulas > TAMANHO_MAXIMO:
		print("Distância inválida: ", celulas)
		return false

	distancia_maxima = celulas
	indice_distancia = maxi(OPCOES_DISTANCIA.find(celulas), 0)
	if turno_atual == Turno.JOGADOR:
		movimento_restante = distancia_maxima
	_atualizar_destaques()
	_atualizar_interface()
	print("Distância máxima por turno: ", distancia_maxima, " células")
	return true


# ===============================================================
# CAMADA 2: COMANDOS (é isto que a IA vai usar no futuro)
# ===============================================================
# Exemplos de comando:
#   {"acao": "colocar", "tipo": "ia", "x": 3, "z": 3}        (tipo: "ia" ou "jogador")
#   {"acao": "remover", "x": 3, "z": 3}
#   {"acao": "mover", "de_x": 3, "de_z": 3, "para_x": 4, "para_z": 3}
#   {"acao": "redimensionar", "largura": 10, "profundidade": 10}
#   {"acao": "definir_distancia", "celulas": 8}

func executar_comando(comando: Dictionary) -> bool:
	var acao: String = comando.get("acao", "")
	match acao:
		"colocar":
			var tipo: String = comando.get("tipo", "ia")
			return colocar_personagem(Vector2i(int(comando["x"]), int(comando["z"])), tipo)
		"remover":
			return remover_peca(Vector2i(int(comando["x"]), int(comando["z"])))
		"mover":
			var origem := Vector2i(int(comando["de_x"]), int(comando["de_z"]))
			var destino := Vector2i(int(comando["para_x"]), int(comando["para_z"]))
			return mover_peca(origem, destino)
		"redimensionar":
			return redimensionar_tabuleiro(int(comando["largura"]), int(comando["profundidade"]))
		"definir_distancia":
			return definir_distancia_maxima(int(comando["celulas"]))

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

	# ----- CLIQUES NO TABULEIRO -----
	if clique.button_index != MOUSE_BUTTON_LEFT and clique.button_index != MOUSE_BUTTON_RIGHT:
		return
	# Com Alt apertado o clique é para girar a câmera
	if Input.is_key_pressed(KEY_ALT):
		return
	# Se o clique foi em cima de um botão ou do painel do jogo, deixa a interface cuidar dele
	if controle is BaseButton or _sobre_interface(controle):
		return

	var celula := celula_sob_mouse(clique.position)
	if not celula_valida(celula):
		return

	cursor_celula = celula
	_atualizar_marcador()
	if clique.button_index == MOUSE_BUTTON_LEFT:
		mover_jogador(celula)
	else:
		remover_personagem_ia(celula)


# TECLADO (teclas de um toque só)
func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return

	match tecla.keycode:
		# Setas: mover o cursor (respeitando para onde a câmera está olhando)
		KEY_UP:
			_mover_cursor(Vector2i(0, -1))
		KEY_DOWN:
			_mover_cursor(Vector2i(0, 1))
		KEY_LEFT:
			_mover_cursor(Vector2i(-1, 0))
		KEY_RIGHT:
			_mover_cursor(Vector2i(1, 0))

		# Ações do jogador
		KEY_ENTER, KEY_KP_ENTER:
			mover_jogador(cursor_celula)
		KEY_SPACE:
			encerrar_turno()

		# Ferramentas de teste
		KEY_N:
			colocar_personagem(cursor_celula, "ia")
		KEY_P:
			colocar_personagem(cursor_celula, "jogador")
		KEY_DELETE, KEY_BACKSPACE:
			remover_personagem_ia(cursor_celula)

		# Câmera
		KEY_HOME, KEY_C:
			_enquadrar_camera()

		# Tamanho do tabuleiro (simula a IA mandando redimensionar)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			executar_comando({"acao": "redimensionar", "largura": largura_tabuleiro + 1, "profundidade": profundidade_tabuleiro + 1})
		KEY_MINUS, KEY_KP_SUBTRACT:
			executar_comando({"acao": "redimensionar", "largura": largura_tabuleiro - 1, "profundidade": profundidade_tabuleiro - 1})

		# Testes de comando da IA
		KEY_T:
			executar_comando({"acao": "colocar", "tipo": "ia", "x": 3, "z": 3})
		KEY_Y:
			executar_comando({"acao": "mover", "de_x": 3, "de_z": 3, "para_x": 4, "para_z": 3})


# ===============================================================
# INTERFACE (painel e botões em cima da tela do jogo)
# ===============================================================

func _criar_interface() -> void:
	interface = CanvasLayer.new()
	interface.layer = 10
	add_child(interface)

	var painel := PanelContainer.new()
	painel.position = Vector2(330.0, 55.0)
	interface.add_child(painel)

	var caixa := VBoxContainer.new()
	painel.add_child(caixa)

	rotulo_status = Label.new()
	caixa.add_child(rotulo_status)

	var linha := HBoxContainer.new()
	caixa.add_child(linha)

	# focus_mode = NONE: assim o teclado (setas, Espaço) não "aperta" os botões sem querer
	botao_distancia = Button.new()
	botao_distancia.focus_mode = Control.FOCUS_NONE
	botao_distancia.pressed.connect(_ao_clicar_distancia)
	linha.add_child(botao_distancia)

	botao_turno = Button.new()
	botao_turno.text = "Encerrar turno (Espaço)"
	botao_turno.focus_mode = Control.FOCUS_NONE
	botao_turno.pressed.connect(encerrar_turno)
	linha.add_child(botao_turno)


func _ao_clicar_distancia() -> void:
	var proximo := (indice_distancia + 1) % OPCOES_DISTANCIA.size()
	definir_distancia_maxima(OPCOES_DISTANCIA[proximo])


func _atualizar_interface() -> void:
	if rotulo_status == null:
		return

	var nome_turno := "JOGADOR"
	if turno_atual == Turno.IA:
		nome_turno = "IA (aguarde...)"

	var texto := "Rodada %d  |  Turno: %s\n" % [rodada, nome_turno]
	if celula_jogador == CELULA_INVALIDA:
		texto += "Jogador: ainda não está no tabuleiro (aperte P para colocar)"
	else:
		texto += "Raça: %s  |  Movimento: %d / %d células (%d pés)" % [raca_jogador, movimento_restante, distancia_maxima, movimento_restante * 5]
	if aviso != "":
		texto += "\n" + aviso
	rotulo_status.text = texto

	botao_distancia.text = "Distância máxima: %d células (%d pés) - alternar" % [distancia_maxima, distancia_maxima * 5]
	botao_turno.disabled = turno_atual != Turno.JOGADOR


func _mostrar_aviso(texto: String) -> void:
	aviso = texto
	print(texto)
	_atualizar_interface()


# Diz se o controle sob o mouse faz parte do painel que criamos acima
func _sobre_interface(controle: Control) -> bool:
	return controle != null and interface != null and interface.is_ancestor_of(controle)


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


# Converte "cima/baixo/esquerda/direita da TELA" em direção no tabuleiro,
# de acordo com o giro atual da câmera (arredondado para múltiplos de 90 graus).
func _direcao_relativa_camera(direcao_tela: Vector2i) -> Vector2i:
	var passos := roundi(camera_yaw / 90.0)
	var yaw := deg_to_rad(passos * 90.0)
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2i(
		roundi(c * direcao_tela.x + s * direcao_tela.y),
		roundi(-s * direcao_tela.x + c * direcao_tela.y))


func _mover_cursor(direcao_tela: Vector2i) -> void:
	var nova := cursor_celula + _direcao_relativa_camera(direcao_tela)
	if celula_valida(nova):
		cursor_celula = nova
		_atualizar_marcador()


# Troca a cor do cubo conforme o tipo (vermelho = IA, azul = jogador)
func _pintar_peca(peca: Node3D, tipo: String) -> void:
	var cor := COR_IA
	if tipo == "jogador":
		cor = COR_JOGADOR

	var material := StandardMaterial3D.new()
	material.albedo_color = cor
	for malha in peca.find_children("*", "MeshInstance3D", true, false):
		(malha as MeshInstance3D).material_override = material


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
		marcador.position = _celula_para_posicao(cursor_celula, ALTURA_TOPO_PISO + ALTURA_MARCADOR)


func _criar_destaques() -> void:
	destaques = Node3D.new()
	add_child(destaques)

	malha_destaque = BoxMesh.new()
	malha_destaque.size = Vector3(TAMANHO_CELULA * 0.9, 0.04, TAMANHO_CELULA * 0.9)

	material_destaque = StandardMaterial3D.new()
	material_destaque.albedo_color = Color(0.2, 1.0, 0.3, 0.45)
	material_destaque.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


# Pinta de verde todas as células que o jogador ainda consegue alcançar neste turno.
func _atualizar_destaques() -> void:
	if destaques == null:
		return

	for filho in destaques.get_children():
		filho.queue_free()

	if turno_atual != Turno.JOGADOR or celula_jogador == CELULA_INVALIDA or movimento_restante <= 0:
		return

	var alcance := _calcular_alcance(celula_jogador, movimento_restante)
	for celula in alcance.keys():
		if celula == celula_jogador:
			continue
		var quadrado := MeshInstance3D.new()
		quadrado.mesh = malha_destaque
		quadrado.material_override = material_destaque
		quadrado.position = _celula_para_posicao(celula, ALTURA_TOPO_PISO + ALTURA_DESTAQUE)
		destaques.add_child(quadrado)
