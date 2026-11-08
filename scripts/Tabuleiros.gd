extends Node3D

# ===============================================================
# TABULEIROS.GD  (versão BG3: terreno, combate, IA tática, mundo interativo)
#
# Organização (3 camadas, como antes):
#   CAMADA 1 - ENTRADA: teclado, mouse (e depois o texto da IA)
#   CAMADA 2 - COMANDOS: executar_comando_mestre() recebe ordens do Mestre IA
#   CAMADA 3 - TABULEIRO: as funções que realmente mexem nas peças
#
# Quem decide o quê:
#   - IA DE TEXTO (Mestre): narra, cria objetos/cenas, dá "intenções" aos NPCs.
#   - ESTE CÓDIGO + ia_tatica.gd + regras.gd: movimento, dados, dano, táticas.
# ===============================================================

const IATatica = preload("res://scripts/ia_tatica.gd")
const Regras = preload("res://scripts/regras.gd")
const Gerador = preload("res://scripts/gerador_cenas.gd")
const Mundo = preload("res://scripts/mundo.gd")

# Sinais: o painel de chat escuta o "log_de_combate" para mostrar o que aconteceu
signal log_de_combate(texto: String)
signal personagens_mudaram()      # o painel da esquerda escuta este sinal
signal jogador_encerrou()          # o jogador terminou o turno dele (dentro do combate)

# ---------------------------------------------------------------
# CENAS QUE VAMOS USAR
# ---------------------------------------------------------------
const CENA_PERSONAGEM = preload("res://cenas/Casa.tscn")
const CENA_PISO = preload("res://cenas/Piso.tscn")

# ---------------------------------------------------------------
# CONFIGURAÇÕES DO TABULEIRO
# ---------------------------------------------------------------
const TAMANHO_CELULA: float = 2.0
const ALTURA_PERSONAGEM: float = 1.5
const ALTURA_TOPO_PISO: float = 0.0
const ALTURA_NIVEL: float = 0.6          # quanto sobe cada "nível" de altura do terreno
const NIVEL_MAXIMO: int = 3
const SUBIDA_MAXIMA: int = 2             # diferença de níveis que dá para escalar de uma vez
const TAMANHO_MINIMO: int = 2
const TAMANHO_MAXIMO: int = 50
const ALTURA_DESTAQUE: float = 0.12
const ALTURA_MARCADOR: float = 0.18

const CONFIGURAR_CENA_AUTOMATICAMENTE: bool = true
const CELULA_INVALIDA: Vector2i = Vector2i(-1, -1)

# ---------------------------------------------------------------
# CONFIGURAÇÕES DO JOGO
# ---------------------------------------------------------------
const COR_JOGADOR: Color = Color(0.1, 0.4, 1.0)      # azul
const COR_ALIADO: Color = Color(0.1, 0.75, 0.3)      # verde
const COR_INIMIGO: Color = Color(0.85, 0.1, 0.1)     # vermelho
const COR_NEUTRO: Color = Color(0.6, 0.6, 0.6)       # cinza

const OPCOES_DISTANCIA: Array[int] = [3, 5, 6, 8, 10]

const LEGENDA: String = """Azul = Kuzin | Verde = aliado | Vermelho = inimigo | Número sob o nome = vida
Chão verde = onde pode andar | Chão vermelho = alvo ao alcance | Amarelo = cursor
F1 = ajuda de teclas"""

const AJUDA_TECLAS: String = """TECLAS
Combate: K inicia/encerra | Espaço encerra o turno | clique = andar/atacar
Câmera: roda = zoom | botão do meio arrasta = girar | WASD desloca | Q/E gira | R/F zoom | C recentra
Teste: B notas da IA | J demo do pão | N monstro | O pedra | H altura | F2 andar livre | F9 reinicia
Chat: /onde | /notas | /nova | Esc ou clicar fora solta o chat"""

const CRIAR_CENARIO_DE_TESTE: bool = true
const ORIGEM_CENARIO: Vector2i = Vector2i(10, 8)   # onde o cenário de teste começa no mapa grande
const USAR_MESTRE_IA: bool = true                    # false = NPCs agem sem narração do Mestre
const MAX_NPCS: int = 12
const MAX_OBJETOS: int = 600
const ALCANCE_OBJETO: int = 8                        # até onde o Mestre pode "jogar" um objeto

# ---------------------------------------------------------------
# CATÁLOGO DE CRIATURAS (o Mestre só pode escolher destas - ele não inventa números)
# ---------------------------------------------------------------
# lado: "jogador" (azul), "aliado" (verde), "inimigo" (vermelho), "neutro" (cinza)
const MODELOS_CRIATURA: Dictionary = {
	"kuzin": {"classe": "Meio-Elfo Ladino Nível 3", "lado": "jogador", "arquetipo": "brutamontes", "pv": 30, "ca": 14, "velocidade": 6,
		"ataques": [{"nome": "Adaga", "alcance": 1, "dado": "1d4+3", "bonus": 5},
					{"nome": "Arco curto", "alcance": 6, "dado": "1d6+3", "bonus": 5}]},
	"goblin": {"classe": "Goblin Guerreiro Nível 1", "lado": "inimigo", "arquetipo": "brutamontes", "pv": 7, "ca": 13, "velocidade": 6,
		"ataques": [{"nome": "Cimitarra", "alcance": 1, "dado": "1d6+2", "bonus": 4}]},
	"goblin_arqueiro": {"classe": "Goblin Arqueiro Nível 1", "lado": "inimigo", "arquetipo": "arqueiro", "pv": 9, "ca": 13, "velocidade": 6,
		"ataques": [{"nome": "Arco curto", "alcance": 6, "dado": "1d6+2", "bonus": 4}]},
	"goblin_xama": {"classe": "Goblin Xamã Nível 2", "lado": "inimigo", "arquetipo": "mago", "pv": 10, "ca": 12, "velocidade": 6,
		"ataques": [{"nome": "Bola de fogo", "alcance": 6, "dado": "2d6", "area": 1, "automatico": true, "usos": 2},
					{"nome": "Cajado", "alcance": 1, "dado": "1d6", "bonus": 3}]},
	"chefe_goblin": {"classe": "Goblin Chefe Nível 3", "lado": "inimigo", "arquetipo": "lider", "pv": 21, "ca": 15, "velocidade": 6,
		"ataques": [{"nome": "Cimitarra", "alcance": 1, "dado": "1d6+2", "bonus": 4}]},
	"orc": {"classe": "Meio-Orc Bárbaro Nível 5", "lado": "inimigo", "arquetipo": "brutamontes", "pv": 30, "ca": 13, "velocidade": 6,
		"ataques": [{"nome": "Machado grande", "alcance": 1, "dado": "1d12+3", "bonus": 5}]},
	"ogro": {"classe": "Ogro Brutamontes Nível 4", "lado": "inimigo", "arquetipo": "brutamontes", "pv": 40, "ca": 11, "velocidade": 8,
		"ataques": [{"nome": "Clava", "alcance": 1, "dado": "2d8+4", "bonus": 6}]},
	"lobo": {"classe": "Lobo Fera Nível 1", "lado": "inimigo", "arquetipo": "brutamontes", "pv": 11, "ca": 13, "velocidade": 8,
		"ataques": [{"nome": "Mordida", "alcance": 1, "dado": "2d4+2", "bonus": 4}]},
	"bandido": {"classe": "Humano Bandido Nível 1", "lado": "inimigo", "arquetipo": "brutamontes", "pv": 11, "ca": 12, "velocidade": 6,
		"ataques": [{"nome": "Espada curta", "alcance": 1, "dado": "1d6+1", "bonus": 3}]},
	"esqueleto": {"classe": "Esqueleto Arqueiro Nível 2", "lado": "inimigo", "arquetipo": "arqueiro", "pv": 13, "ca": 13, "velocidade": 6,
		"ataques": [{"nome": "Arco curto", "alcance": 6, "dado": "1d6+2", "bonus": 4}]},
	"guarda": {"classe": "Humana Guarda Nível 3", "lado": "aliado", "arquetipo": "lider", "pv": 22, "ca": 16, "velocidade": 6,
		"ataques": [{"nome": "Lança", "alcance": 1, "dado": "1d6+3", "bonus": 5}]},
	"aldeao": {"classe": "Humano Aldeão Nível 1", "lado": "aliado", "arquetipo": "covarde", "pv": 6, "ca": 10, "velocidade": 6,
		"ataques": []},
}
const MODELOS_PARA_TESTE: Array[String] = ["goblin", "goblin_arqueiro", "goblin_xama", "lobo", "bandido", "ogro"]

# ---------------------------------------------------------------
# CATÁLOGO DE OBJETOS DO MUNDO
# ---------------------------------------------------------------
# forma: caixa | esfera | cilindro      tamanho: (largura, altura, profundidade) em metros
# bloqueia: impede andar e a linha de visão   item: pode ser carregado   movel: pode ser movido
# estados: lista dos estados permitidos (o primeiro é o inicial)
const CATALOGO_OBJETOS: Dictionary = {
	"pao": {"forma": "esfera", "tamanho": Vector3(0.6, 0.4, 0.6), "cor": Color(0.85, 0.6, 0.25), "bloqueia": false, "item": true, "movel": true, "estados": ["normal"]},
	"pocao": {"forma": "esfera", "tamanho": Vector3(0.4, 0.5, 0.4), "cor": Color(0.6, 0.2, 0.8), "bloqueia": false, "item": true, "movel": true, "estados": ["normal"]},
	"moeda": {"forma": "cilindro", "tamanho": Vector3(0.4, 0.1, 0.4), "cor": Color(1.0, 0.85, 0.1), "bloqueia": false, "item": true, "movel": true, "estados": ["normal"]},
	"espada": {"forma": "caixa", "tamanho": Vector3(0.15, 0.1, 0.9), "cor": Color(0.75, 0.78, 0.82), "bloqueia": false, "item": true, "movel": true, "estados": ["normal"]},
	"chave": {"forma": "caixa", "tamanho": Vector3(0.15, 0.1, 0.4), "cor": Color(0.9, 0.75, 0.2), "bloqueia": false, "item": true, "movel": true, "estados": ["normal"]},
	"barril": {"forma": "cilindro", "tamanho": Vector3(1.0, 1.2, 1.0), "cor": Color(0.5, 0.32, 0.15), "bloqueia": true, "item": false, "movel": true, "estados": ["normal", "quebrado"]},
	"caixote": {"forma": "caixa", "tamanho": Vector3(1.1, 1.0, 1.1), "cor": Color(0.6, 0.45, 0.25), "bloqueia": true, "item": false, "movel": true, "estados": ["normal", "quebrado"]},
	"bau": {"forma": "caixa", "tamanho": Vector3(1.2, 0.8, 0.8), "cor": Color(0.45, 0.28, 0.1), "bloqueia": true, "item": false, "movel": false, "estados": ["fechado", "aberto"]},
	"parede": {"forma": "caixa", "tamanho": Vector3(1.97, 2.2, 1.97), "cor": Color(0.55, 0.4, 0.28), "bloqueia": true, "item": false, "movel": false, "estados": ["normal", "destruido"]},
	"mesa": {"forma": "caixa", "tamanho": Vector3(1.3, 0.8, 1.3), "cor": Color(0.5, 0.33, 0.16), "bloqueia": true, "item": false, "movel": true, "estados": ["normal", "quebrado"]},
	"balcao": {"forma": "caixa", "tamanho": Vector3(1.9, 1.0, 1.1), "cor": Color(0.38, 0.24, 0.12), "bloqueia": true, "item": false, "movel": false, "estados": ["normal", "quebrado"]},
	"cadeira": {"forma": "caixa", "tamanho": Vector3(0.6, 0.9, 0.6), "cor": Color(0.6, 0.4, 0.2), "bloqueia": false, "item": false, "movel": true, "estados": ["normal", "quebrado"]},
	"alcapao": {"forma": "caixa", "tamanho": Vector3(1.4, 0.1, 1.4), "cor": Color(0.25, 0.15, 0.08), "bloqueia": false, "item": false, "movel": false, "estados": ["fechado", "aberto"]},
	"cama": {"forma": "caixa", "tamanho": Vector3(1.1, 0.6, 1.8), "cor": Color(0.72, 0.3, 0.3), "bloqueia": true, "item": false, "movel": false, "estados": ["normal", "quebrado"]},
	"banco": {"forma": "caixa", "tamanho": Vector3(1.6, 0.5, 0.6), "cor": Color(0.55, 0.4, 0.22), "bloqueia": false, "item": false, "movel": true, "estados": ["normal", "quebrado"]},
	"altar": {"forma": "caixa", "tamanho": Vector3(1.6, 1.0, 1.0), "cor": Color(0.8, 0.8, 0.85), "bloqueia": true, "item": false, "movel": false, "estados": ["normal", "quebrado"]},
	"arvore": {"forma": "cilindro", "tamanho": Vector3(1.2, 3.0, 1.2), "cor": Color(0.15, 0.5, 0.2), "bloqueia": true, "item": false, "movel": false, "estados": ["normal", "destruido"]},
	"pedra": {"forma": "esfera", "tamanho": Vector3(1.5, 1.2, 1.5), "cor": Color(0.5, 0.5, 0.52), "bloqueia": true, "item": false, "movel": false, "estados": ["normal"]},
	"muro": {"forma": "caixa", "tamanho": Vector3(1.95, 1.6, 1.95), "cor": Color(0.42, 0.42, 0.45), "bloqueia": true, "item": false, "movel": false, "estados": ["normal", "destruido"]},
	"porta": {"forma": "caixa", "tamanho": Vector3(1.9, 2.0, 1.9), "cor": Color(0.5, 0.3, 0.12), "bloqueia": true, "item": false, "movel": false, "estados": ["fechado", "aberto"]},
	"tocha": {"forma": "cilindro", "tamanho": Vector3(0.2, 1.2, 0.2), "cor": Color(0.35, 0.2, 0.1), "bloqueia": false, "item": false, "movel": false, "estados": ["apagado", "aceso"], "luz": true},
	"fogueira": {"forma": "cilindro", "tamanho": Vector3(0.9, 0.4, 0.9), "cor": Color(0.9, 0.35, 0.05), "bloqueia": false, "item": false, "movel": false, "estados": ["aceso", "apagado"], "luz": true},
}

# CONSTRUÇÕES (feitas de vários blocos, como LEGO): paredes em volta, porta, piso por dentro
const CATALOGO_PREDIOS: Dictionary = {
	"taverna": {"parede": Color(0.55, 0.36, 0.22), "piso": Color(0.6, 0.45, 0.28)},
	"casa": {"parede": Color(0.78, 0.72, 0.6), "piso": Color(0.62, 0.52, 0.42)},
	"armazem": {"parede": Color(0.45, 0.45, 0.5), "piso": Color(0.5, 0.48, 0.44)},
	"templo": {"parede": Color(0.88, 0.88, 0.9), "piso": Color(0.75, 0.75, 0.8)},
}

# Estados que NÃO bloqueiam mais (porta aberta, coisa quebrada...)
const ESTADOS_LIVRES: Array[String] = ["aberto", "quebrado", "destruido"]

# ---------------------------------------------------------------
# CONFIGURAÇÕES DA CÂMERA
# ---------------------------------------------------------------
const DISTANCIA_MINIMA: float = 3.0
const DISTANCIA_MAXIMA: float = 300.0
const ZOOM_RODA: float = 0.9
const ZOOM_TECLADO: float = 1.0
const VELOCIDADE_GIRO: float = 90.0
const SENSIBILIDADE_MOUSE: float = 0.3
const INCLINACAO_MINIMA: float = 10.0
const INCLINACAO_MAXIMA: float = 85.0

# ---------------------------------------------------------------
# ESTADO DO TABULEIRO
# ---------------------------------------------------------------
var largura_tabuleiro: int = 40       # mude para 50 se quiser um mapa ainda maior (máximo: TAMANHO_MAXIMO)
var profundidade_tabuleiro: int = 40

var pecas: Dictionary = {}                  # {célula: Node3D}   (cada peça tem meta "ficha")
var pisos: Array = []
var alturas: Dictionary = {}                # {célula: nível 1..3}   (sem entrada = nível 0)
var plataformas: Dictionary = {}            # {célula: MeshInstance3D} visual das alturas
var predios: Dictionary = {}                # {nome: {nome, modelo, x0, z0, x1, z1, porta, fora, extras}}
var objetos: Dictionary = {}                # {nome: {nome, modelo, celula, estado, dono, no}}
var obstaculos: Dictionary = {}             # {célula: true} (recalculado a partir dos objetos)

var cursor_celula: Vector2i = Vector2i(0, 0)
var marcador: MeshInstance3D

# ---------------------------------------------------------------
# ESTADO DOS TURNOS E DO JOGADOR
# ---------------------------------------------------------------
enum Turno { JOGADOR, IA }
var turno_atual: Turno = Turno.JOGADOR
var rodada: int = 1
var raca_jogador: String = "Meio-Elfo"
var distancia_maxima: int = 6
var movimento_restante: int = 6
var indice_distancia: int = 0
var acao_disponivel: bool = true
var celula_jogador: Vector2i = CELULA_INVALIDA
var aviso: String = ""
var fim_de_jogo: bool = false
var turno_em_andamento: bool = false
# MODO DE JOGO (igual à mesa): "exploracao" = conversa com o Mestre, sem turnos;
# "combate" = ordem de iniciativa, cada um age no seu turno.
var mundo = Mundo.new()                     # propriedades dos itens, fichas de conhecimento e diário
var _registro_ativo: bool = false           # só registra no diário depois que o cenário inicial está pronto
var _gerando: bool = false                  # true enquanto o gerador monta uma construção inteira
var _carregando: bool = false               # true enquanto o jogo salvo está sendo restaurado
var _construindo: bool = false              # true enquanto uma construção monta paredes/portas (não vira evento)
var modo: String = "exploracao"
var ordem_iniciativa: Array = []            # nomes, do mais rápido ao mais lento
var ator_atual: String = ""
var movimento_livre: bool = false           # F2: ferramenta de TESTE para andar sem o Mestre
var legenda_visivel: bool = false
const LIMITE_EXPLORACAO: int = 20           # até quantas "células de custo" o Mestre move alguém fora de combate
var eventos_turno: Array = []               # frases sobre o que aconteceu (vai para o Mestre narrar)
var indice_modelo_teste: int = 0

# Depuração das notas da IA (tecla B)
var debug_ativo: bool = false
var debug_no: Node3D
var ultimo_debug_texto: String = ""

# ---------------------------------------------------------------
# PEÇAS VISUAIS EXTRAS
# ---------------------------------------------------------------
var destaques: Node3D
var malha_destaque: BoxMesh
var material_destaque: StandardMaterial3D
var material_alvo: StandardMaterial3D

var interface: CanvasLayer
var rotulo_status: Label
var rotulo_debug: Label
var botao_distancia: Button
var botao_turno: Button
var botao_combate: Button
var rotulo_cursor: Label
var rotulo_legenda: Label

# ---------------------------------------------------------------
# CÂMERA
# ---------------------------------------------------------------
var camera: Camera3D
var camera_alvo: Vector3 = Vector3.ZERO
var camera_distancia: float = 20.0
var camera_yaw: float = 0.0
var camera_pitch: float = 42.0


func _ready() -> void:
	add_to_group("tabuleiro")
	gerar_tabuleiro()
	_criar_marcador()
	_criar_destaques()
	_criar_interface()
	debug_no = Node3D.new()
	add_child(debug_no)
	if CONFIGURAR_CENA_AUTOMATICAMENTE:
		_configurar_camera_e_luz()

	distancia_maxima = 6
	indice_distancia = maxi(OPCOES_DISTANCIA.find(distancia_maxima), 0)
	movimento_restante = distancia_maxima

	if CRIAR_CENARIO_DE_TESTE:
		_montar_cenario_de_teste()

	carregar_mundo()            # se existe um jogo salvo, continua de onde parou
	_registro_ativo = true

	if celula_jogador != CELULA_INVALIDA:
		cursor_celula = celula_jogador
		_enquadrar_camera()
	_atualizar_marcador()
	_atualizar_destaques()
	_atualizar_interface()
	print("Tabuleiro pronto! Clique = mover/atacar | Espaço = encerrar turno | B = notas da IA | J = demo do pão | N = criar monstro")


# Monta um cenário inicial para você testar a IA tática
# O cenário de teste fica no meio do mapa grande: "_o" soma a posição de início do cenário
func _o(x: int, z: int) -> Vector2i:
	return Vector2i(x + ORIGEM_CENARIO.x, z + ORIGEM_CENARIO.y)


func _montar_cenario_de_teste() -> void:
	# Um morro (nível 1) à direita, onde o arqueiro vai ficar
	for x in range(20, 24):
		for z in range(3, 7):
			definir_altura(_o(x, z), 1)

	# Construções de LEGO: paredes + porta + piso por dentro
	# Taverna: 12 x 9 blocos (interior de 10 x 7). Casa do padeiro: 7 x 6 (interior de 5 x 4).
	construir_predio("Taverna Javali Dourado", "taverna", _o(1, 1), 12, 9, "sul")
	construir_predio("Casa do Padeiro", "casa", _o(1, 13), 7, 6, "norte")

	# Taverna: balcão ao norte, mesas com cadeiras, lareira, barris
	for x in range(3, 7):
		criar_objeto("Balcão" if x == 3 else "Balcão %d" % (x - 2), "balcao", _o(x, 2))
	criar_objeto("Mesa do canto", "mesa", _o(9, 4))
	criar_objeto("Cadeira", "cadeira", _o(8, 4))
	criar_objeto("Cadeira 2", "cadeira", _o(10, 4))
	criar_objeto("Mesa grande", "mesa", _o(9, 7))
	criar_objeto("Cadeira 3", "cadeira", _o(8, 7))
	criar_objeto("Cadeira 4", "cadeira", _o(10, 7))
	criar_objeto("Mesa redonda", "mesa", _o(4, 6))
	criar_objeto("Lareira", "fogueira", _o(2, 5))
	criar_objeto("Barril de cerveja", "barril", _o(11, 2))
	criar_objeto("Barril de cerveja 2", "barril", _o(11, 3))
	criar_objeto("Baú da taverna", "bau", _o(2, 8))
	criar_objeto("Tocha", "tocha", _o(11, 8))

	# Casa do padeiro
	criar_objeto("Bancada do padeiro", "mesa", _o(3, 15))
	criar_objeto("Saco de farinha", "barril", _o(6, 15))
	criar_objeto("Baú do padeiro", "bau", _o(6, 17))

	# Lá fora (a praça)
	criar_objeto("Poço", "pedra", _o(15, 11))
	criar_objeto("Fogueira da praça", "fogueira", _o(17, 12))
	criar_objeto("Árvore", "arvore", _o(16, 1))
	criar_objeto("Árvore 2", "arvore", _o(19, 9))
	criar_objeto("Árvore 3", "arvore", _o(14, 16))
	criar_objeto("Barril da praça", "barril", _o(13, 12))

	# Personagens
	colocar_personagem(_o(6, 7), "Kuzin", "kuzin", "jogador")
	colocar_personagem(_o(5, 3), "Taberneiro Barnaby", "aldeao", "aliado", "Humano Taberneiro Nível 1")
	colocar_personagem(_o(9, 3), "Guarda Elara", "guarda", "aliado")
	colocar_personagem(_o(4, 16), "Padeiro Joaquim", "aldeao", "aliado", "Humano Padeiro Nível 1")
	colocar_personagem(_o(16, 6), "Tharok", "orc", "inimigo")
	colocar_personagem(_o(18, 13), "Chefe Goblin", "chefe_goblin", "inimigo")
	colocar_personagem(_o(21, 4), "Goblin Arqueiro", "goblin_arqueiro", "inimigo")


# ---------------------------------------------------------------
# CONSTRUÇÕES (LEGO): vários blocos de parede em volta + porta + piso por dentro
# ---------------------------------------------------------------
# canto = célula do canto noroeste (esquerda/cima). lado_porta = norte | sul | leste | oeste
const LADO_OPOSTO: Dictionary = {"norte": "sul", "sul": "norte", "leste": "oeste", "oeste": "leste"}


# Célula da porta (no meio da parede) e a célula de fora dela
func _porta_do_lado(x0: int, z0: int, x1: int, z1: int, lado: String) -> Dictionary:
	var larg: int = x1 - x0 + 1
	var prof: int = z1 - z0 + 1
	match lado:
		"norte":
			var c := Vector2i(x0 + larg / 2, z0)
			return {"celula": c, "fora": c + Vector2i(0, -1), "dentro": c + Vector2i(0, 1)}
		"leste":
			var c2 := Vector2i(x1, z0 + prof / 2)
			return {"celula": c2, "fora": c2 + Vector2i(1, 0), "dentro": c2 + Vector2i(-1, 0)}
		"oeste":
			var c3 := Vector2i(x0, z0 + prof / 2)
			return {"celula": c3, "fora": c3 + Vector2i(-1, 0), "dentro": c3 + Vector2i(1, 0)}
	var c4 := Vector2i(x0 + larg / 2, z1)
	return {"celula": c4, "fora": c4 + Vector2i(0, 1), "dentro": c4 + Vector2i(0, -1)}


# canto = célula do canto noroeste (esquerda/cima). lado_porta = porta da FRENTE (norte|sul|leste|oeste).
# portas_extras = outros lados que também têm porta (o lado oposto à frente vira "porta dos fundos").
func construir_predio(nome: String, modelo: String, canto: Vector2i, largura: int, profundidade: int, lado_porta: String = "sul", portas_extras: Array = []) -> bool:
	if not CATALOGO_PREDIOS.has(modelo):
		_falhar("Construção desconhecida: %s. Use: %s." % [modelo, ", ".join(CATALOGO_PREDIOS.keys())])
		return false
	if largura < 3 or profundidade < 3 or largura > 16 or profundidade > 16:
		_falhar("Tamanho inválido: a construção precisa ter de 3 a 16 células de largura e de profundidade.")
		return false
	var x0: int = canto.x
	var z0: int = canto.y
	var x1: int = x0 + largura - 1
	var z1: int = z0 + profundidade - 1
	if not celula_valida(Vector2i(x0, z0)) or not celula_valida(Vector2i(x1, z1)):
		_falhar("A construção não cabe no tabuleiro (x de 0 a %d, z de 0 a %d)." % [largura_tabuleiro - 1, profundidade_tabuleiro - 1])
		return false

	if not LADO_OPOSTO.has(lado_porta):
		lado_porta = "sul"
	# Lista de portas: frente + extras (sem repetir lado)
	var portas: Array = []
	var lados_usados: Array = []
	var todos: Array = [lado_porta]
	for l in portas_extras:
		if LADO_OPOSTO.has(str(l)) and not todos.has(str(l)):
			todos.append(str(l))
	for l in todos:
		var info: Dictionary = _porta_do_lado(x0, z0, x1, z1, str(l))
		var rotulo: String = "porta da frente"
		if str(l) != lado_porta:
			rotulo = "porta dos fundos" if str(l) == str(LADO_OPOSTO[lado_porta]) else "porta lateral"
		portas.append({"lado": str(l), "celula": info["celula"], "fora": info["fora"], "dentro": info["dentro"], "rotulo": rotulo})
		lados_usados.append(info["celula"])

	var paredes: Array = []
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var borda: bool = x == x0 or x == x1 or z == z0 or z == z1
			if not borda:
				continue
			var c := Vector2i(x, z)
			if not lados_usados.has(c):
				paredes.append(c)
			if celula_ocupada(c) or eh_obstaculo(c) or not _objetos_na_celula(c).is_empty():
				_falhar("O lugar da construção está ocupado em (%d,%d)." % [x, z])
				return false
	if objetos.size() + paredes.size() + portas.size() > MAX_OBJETOS:
		_falhar("Objetos demais no tabuleiro para construir isto.")
		return false

	var nome_final: String = nome.strip_edges() if nome.strip_edges() != "" else modelo.capitalize()
	var n: int = 2
	var base_nome: String = nome_final
	while predios.has(nome_final):
		nome_final = "%s %d" % [base_nome, n]
		n += 1

	var cores: Dictionary = CATALOGO_PREDIOS[modelo]
	var extras: Array = []
	_construindo = true
	for c in paredes:
		if criar_objeto("Parede de " + nome_final, "parede", c):
			var obj: Dictionary = objetos[_nome_criado_por_ultimo]
			(obj["no"] as Node3D).get_meta("material").albedo_color = cores["parede"]
			obj["predio"] = nome_final
	for porta in portas:
		var nome_porta: String = ("Porta dos fundos de " if str(porta["rotulo"]) == "porta dos fundos" else "Porta de ") + nome_final
		if criar_objeto(nome_porta, "porta", porta["celula"]):
			mudar_estado(_nome_criado_por_ultimo, "aberto")
			objetos[_nome_criado_por_ultimo]["predio"] = nome_final
	_construindo = false

	# Piso por dentro
	for x in range(x0 + 1, x1):
		for z in range(z0 + 1, z1):
			var chao := MeshInstance3D.new()
			var malha := BoxMesh.new()
			malha.size = Vector3(TAMANHO_CELULA * 0.99, 0.06, TAMANHO_CELULA * 0.99)
			chao.mesh = malha
			var mat := StandardMaterial3D.new()
			mat.albedo_color = cores["piso"]
			chao.material_override = mat
			add_child(chao)
			chao.position = _celula_para_posicao(Vector2i(x, z), _y_base(Vector2i(x, z)) + 0.04)
			extras.append(chao)

	# Nome da construção flutuando sobre ela
	var titulo := Label3D.new()
	titulo.text = nome_final
	titulo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	titulo.no_depth_test = true
	titulo.pixel_size = 0.012
	titulo.font_size = 48
	titulo.outline_size = 14
	titulo.modulate = Color(1.0, 0.9, 0.5)
	add_child(titulo)
	titulo.position = _celula_para_posicao(Vector2i((x0 + x1) / 2, (z0 + z1) / 2), 3.4)
	extras.append(titulo)

	var porta_principal: Dictionary = portas[0]
	predios[nome_final] = {"nome": nome_final, "modelo": modelo, "x0": x0, "z0": z0, "x1": x1, "z1": z1,
		"porta": porta_principal["celula"], "fora": porta_principal["fora"], "lado_porta": lado_porta,
		"portas": portas, "recursos": [], "alturas": [], "extras": extras}
	_recalcular_obstaculos()
	_atualizar_destaques()
	_ultimo_predio = nome_final
	print("Construção '", nome_final, "' (", modelo, ") em ", canto, " ", largura, "x", profundidade)
	return true


# Apaga uma construção inteira (paredes, porta, móveis, piso e alturas que ela criou)
func demolir_predio(nome: String) -> bool:
	if not predios.has(nome):
		return false
	var p: Dictionary = predios[nome]
	for n in objetos.keys():
		if str(objetos[n].get("predio", "")) == nome:
			remover_objeto(str(n))
	for e in p["extras"]:
		if is_instance_valid(e):
			e.queue_free()
	for c in p["alturas"]:
		definir_altura(c, 0)
	predios.erase(nome)
	_recalcular_obstaculos()
	_atualizar_destaques()
	return true


# Nome da construção em que a célula está DENTRO ("" se está fora de todas)
func predio_em(celula: Vector2i) -> String:
	for nome in predios.keys():
		var p: Dictionary = predios[nome]
		if celula.x > int(p["x0"]) and celula.x < int(p["x1"]) and celula.y > int(p["z0"]) and celula.y < int(p["z1"]):
			return str(nome)
		for porta in p["portas"]:
			if celula == porta["celula"]:
				return str(nome)
	return ""


# "da Taverna", "do Armazém"... (para frases em português)
func _de_predio(nome: String) -> String:
	var modelo: String = str(predios[nome]["modelo"]) if predios.has(nome) else ""
	var feminino: bool = modelo == "taverna" or modelo == "casa"
	return ("da " if feminino else "do ") + nome


# Descreve o lugar em linguagem natural: "dentro da Taverna, junto ao Balcão"
func lugar_texto(celula: Vector2i) -> String:
	var dentro: String = predio_em(celula)
	var perto: String = ""
	var melhor: int = 99
	for n in objetos.keys():
		var o: Dictionary = objetos[n]
		var m: String = str(o["modelo"])
		if m == "parede" or m == "muro" or str(o["dono"]) != "":
			continue
		var d: int = distancia(celula, o["celula"])
		if m == "porta":
			d += 1
		if d < melhor:
			melhor = d
			perto = str(n)
	if dentro != "":
		if melhor <= 1:
			if str(objetos[perto]["modelo"]) == "porta":
				return "dentro %s, junto da porta" % _de_predio(dentro)
			return "dentro %s, junto de %s" % [_de_predio(dentro), perto]
		return "dentro %s" % _de_predio(dentro)
	for nome in predios.keys():
		var p: Dictionary = predios[nome]
		var dx: int = maxi(maxi(int(p["x0"]) - celula.x, celula.x - int(p["x1"])), 0)
		var dz: int = maxi(maxi(int(p["z0"]) - celula.y, celula.y - int(p["z1"])), 0)
		if maxi(dx, dz) <= 2:
			return "do lado de fora %s" % _de_predio(nome)
	if melhor <= 2:
		return "ao ar livre, perto de %s" % perto
	return "ao ar livre"


# ===============================================================
# CÂMERA E LUZ
# ===============================================================

func _configurar_camera_e_luz() -> void:
	camera = get_viewport().get_camera_3d()
	if camera == null:
		camera = Camera3D.new()
		add_child(camera)
	camera.make_current()
	_enquadrar_camera()

	var luzes := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	var luz: DirectionalLight3D
	if luzes.is_empty():
		luz = DirectionalLight3D.new()
		add_child(luz)
	else:
		luz = luzes[0] as DirectionalLight3D
	luz.global_rotation_degrees = Vector3(-50.0, 30.0, 0.0)

	var ambiente := Environment.new()
	ambiente.background_mode = Environment.BG_COLOR
	ambiente.background_color = Color(0.15, 0.17, 0.22)
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambiente.ambient_light_color = Color(1.0, 1.0, 1.0)
	ambiente.ambient_light_energy = 0.5
	var mundo := WorldEnvironment.new()
	mundo.environment = ambiente
	add_child(mundo)


# Enquadra o jogador (ou o centro do mapa, se ele não existir). Com mapa grande, o zoom inicial é "de perto".
func _enquadrar_camera(tabuleiro_inteiro: bool = false) -> void:
	if camera == null:
		return
	var centro_local := Vector3(
		(largura_tabuleiro - 1) * TAMANHO_CELULA / 2.0,
		ALTURA_TOPO_PISO,
		(profundidade_tabuleiro - 1) * TAMANHO_CELULA / 2.0)
	var maior_lado := float(maxi(largura_tabuleiro, profundidade_tabuleiro))
	var distancia_total: float = maior_lado * TAMANHO_CELULA * 1.8
	if not tabuleiro_inteiro and celula_jogador != CELULA_INVALIDA:
		centro_local = _celula_para_posicao(celula_jogador, ALTURA_TOPO_PISO)
		distancia_total = minf(distancia_total, 40.0)
	camera_alvo = to_global(centro_local)
	camera_distancia = clampf(distancia_total, DISTANCIA_MINIMA, DISTANCIA_MAXIMA)
	camera_yaw = 0.0
	camera_pitch = 42.0
	_atualizar_camera()


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


func _deslocar_camera(direita: float, frente: float) -> void:
	if camera == null:
		return
	var base := camera.global_transform.basis
	var vetor_direita := Vector3(base.x.x, 0.0, base.x.z).normalized()
	var vetor_frente := Vector3(-base.z.x, 0.0, -base.z.z).normalized()
	camera_alvo += vetor_direita * direita + vetor_frente * frente
	var margem := TAMANHO_CELULA * 3.0
	var local := to_local(camera_alvo)
	local.x = clampf(local.x, -margem, (largura_tabuleiro - 1) * TAMANHO_CELULA + margem)
	local.z = clampf(local.z, -margem, (profundidade_tabuleiro - 1) * TAMANHO_CELULA + margem)
	camera_alvo = to_global(local)
	_atualizar_camera()


func _digitando() -> bool:
	var foco := get_viewport().gui_get_focus_owner()
	return foco is LineEdit or foco is TextEdit


func _process(delta: float) -> void:
	_seguir_carregadores()

	if camera == null or _digitando():
		return

	if Input.is_key_pressed(KEY_Q):
		camera_yaw += VELOCIDADE_GIRO * delta
	if Input.is_key_pressed(KEY_E):
		camera_yaw -= VELOCIDADE_GIRO * delta
	if Input.is_key_pressed(KEY_Z):
		camera_pitch += VELOCIDADE_GIRO * delta
	if Input.is_key_pressed(KEY_X):
		camera_pitch -= VELOCIDADE_GIRO * delta
	if Input.is_key_pressed(KEY_R):
		camera_distancia -= camera_distancia * ZOOM_TECLADO * delta
	if Input.is_key_pressed(KEY_F):
		camera_distancia += camera_distancia * ZOOM_TECLADO * delta

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
# CAMADA 3: O TABULEIRO
# ===============================================================

func gerar_tabuleiro() -> void:
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
	if celula_jogador != CELULA_INVALIDA and (celula_jogador.x >= nova_largura or celula_jogador.y >= nova_profundidade):
		_mostrar_aviso("Não dá para diminuir: o jogador ficaria fora do tabuleiro.")
		return false

	largura_tabuleiro = nova_largura
	profundidade_tabuleiro = nova_profundidade

	for celula in pecas.keys():
		if not celula_valida(celula):
			remover_peca(celula)
	for nome in objetos.keys():
		if not celula_valida(objetos[nome]["celula"]):
			remover_objeto(nome)
	for celula in alturas.keys():
		if not celula_valida(celula):
			definir_altura(celula, 0)

	cursor_celula = Vector2i(
		clampi(cursor_celula.x, 0, largura_tabuleiro - 1),
		clampi(cursor_celula.y, 0, profundidade_tabuleiro - 1))

	gerar_tabuleiro()
	_atualizar_marcador()
	_atualizar_destaques()
	_enquadrar_camera(true)
	print("Tabuleiro redimensionado para ", largura_tabuleiro, " x ", profundidade_tabuleiro)
	return true


func celula_valida(celula: Vector2i) -> bool:
	return celula.x >= 0 and celula.x < largura_tabuleiro and celula.y >= 0 and celula.y < profundidade_tabuleiro


func celula_ocupada(celula: Vector2i) -> bool:
	return pecas.has(celula)


func eh_obstaculo(celula: Vector2i) -> bool:
	return obstaculos.has(celula)


func altura_de(celula: Vector2i) -> int:
	return int(alturas.get(celula, 0))


# Distância em células (diagonal conta como 1)
func distancia(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func ficha_em(celula: Vector2i) -> Dictionary:
	if not pecas.has(celula):
		return {}
	return pecas[celula].get_meta("ficha", {})


# "bem" = jogador e aliados, "mal" = inimigos, "" = neutro
func equipe_de(ficha: Dictionary) -> String:
	var lado: String = str(ficha.get("lado", ""))
	if lado == "jogador" or lado == "aliado":
		return "bem"
	if lado == "inimigo":
		return "mal"
	return ""


func sao_hostis(a: Dictionary, b: Dictionary) -> bool:
	var ea: String = equipe_de(a)
	var eb: String = equipe_de(b)
	return ea != "" and eb != "" and ea != eb


# ---------------------------------------------------------------
# PAINEL DA ESQUERDA (grupo / inimigos / npcs)
# ---------------------------------------------------------------
var _notificacao_pendente: bool = false


func _notificar_personagens() -> void:
	if _notificacao_pendente:
		return
	_notificacao_pendente = true
	_emitir_personagens.call_deferred()


func _emitir_personagens() -> void:
	_notificacao_pendente = false
	personagens_mudaram.emit()


# Lista para os cards: [{nome, classe, progresso (0-100 = vida), categoria: "grupo"|"inimigos"|"npcs"}]
# jogador -> grupo | inimigo -> inimigos | aliado e neutro -> npcs
func lista_para_painel() -> Array:
	var lista: Array = []
	for celula in pecas.keys():
		var f: Dictionary = ficha_em(celula)
		var categoria: String = "npcs"
		if str(f["lado"]) == "jogador":
			categoria = "grupo"
		elif str(f["lado"]) == "inimigo":
			categoria = "inimigos"
		var vida: int = roundi(100.0 * float(f["pv"]) / float(maxi(int(f["pv_max"]), 1)))
		lista.append({"nome": str(f["nome"]), "classe": str(f.get("classe", "")), "progresso": vida, "categoria": categoria})
	return lista


# ---------------------------------------------------------------
# ALTURAS
# ---------------------------------------------------------------
func definir_altura(celula: Vector2i, nivel: int) -> bool:
	if not celula_valida(celula):
		return false
	nivel = clampi(nivel, 0, NIVEL_MAXIMO)
	if nivel == 0:
		alturas.erase(celula)
	else:
		alturas[celula] = nivel

	if plataformas.has(celula):
		plataformas[celula].queue_free()
		plataformas.erase(celula)
	if nivel > 0:
		var altura_visual: float = float(nivel) * ALTURA_NIVEL
		var bloco := MeshInstance3D.new()
		var malha := BoxMesh.new()
		malha.size = Vector3(TAMANHO_CELULA * 0.98, altura_visual, TAMANHO_CELULA * 0.98)
		bloco.mesh = malha
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.45, 0.4, 0.3).lerp(Color(0.6, 0.55, 0.4), float(nivel) / float(NIVEL_MAXIMO))
		bloco.material_override = material
		add_child(bloco)
		bloco.position = _celula_para_posicao(celula, ALTURA_TOPO_PISO + altura_visual / 2.0)
		plataformas[celula] = bloco

	# Quem estiver em cima precisa acompanhar a nova altura
	if pecas.has(celula):
		pecas[celula].position = _pos_peca(celula)
	for nome in objetos.keys():
		var obj: Dictionary = objetos[nome]
		if obj["celula"] == celula and str(obj["dono"]) == "":
			_posicionar_objeto(obj)
	_atualizar_destaques()
	return true


# ---------------------------------------------------------------
# PERSONAGENS
# ---------------------------------------------------------------
# modelo = nome no MODELOS_CRIATURA   lado = "jogador" | "aliado" | "inimigo" | "neutro"
func colocar_personagem(celula: Vector2i, nome: String, modelo: String = "goblin", lado: String = "", classe: String = "") -> bool:
	if not celula_valida(celula):
		_falhar("Célula (%d,%d) fora do tabuleiro (x de 0 a %d, z de 0 a %d)." % [celula.x, celula.y, largura_tabuleiro - 1, profundidade_tabuleiro - 1])
		return false
	if celula_ocupada(celula):
		_falhar("A célula (%d,%d) já tem %s." % [celula.x, celula.y, str(ficha_em(celula).get("nome", "alguém"))])
		return false
	if eh_obstaculo(celula):
		_falhar("A célula (%d,%d) está bloqueada por um obstáculo." % [celula.x, celula.y])
		return false
	if not MODELOS_CRIATURA.has(modelo):
		_falhar("Modelo de criatura desconhecido: %s." % modelo)
		return false

	var molde: Dictionary = MODELOS_CRIATURA[modelo]
	var ficha: Dictionary = {}
	ficha["nome"] = _nome_livre(nome)
	ficha["modelo"] = modelo
	ficha["classe"] = classe if classe != "" else str(molde.get("classe", "Criatura Nível 1"))
	ficha["lado"] = lado if lado != "" else str(molde["lado"])
	if ficha["lado"] == "jogador" and celula_jogador != CELULA_INVALIDA:
		_falhar("O personagem do jogador já está no tabuleiro.")
		return false
	ficha["arquetipo"] = molde["arquetipo"]
	ficha["pv"] = int(molde["pv"])
	ficha["pv_max"] = int(molde["pv"])
	ficha["ca"] = int(molde["ca"])
	ficha["velocidade"] = int(molde["velocidade"])
	ficha["ataques"] = (molde["ataques"] as Array).duplicate(true)
	ficha["inventario"] = []
	ficha["intencao"] = "padrao"
	ficha["historico"] = []
	ficha["atividade"] = ""
	ficha["iniciativa"] = 2
	ficha["conhecimento"] = mundo.conhecimento_inicial(str(ficha["nome"]), str(ficha["lado"]))

	var peca: Node3D = CENA_PERSONAGEM.instantiate()
	add_child(peca)
	peca.position = _pos_peca(celula)
	peca.set_meta("ficha", ficha)
	peca.set_meta("tipo", "jogador" if ficha["lado"] == "jogador" else "ia")
	_pintar_peca(peca, str(ficha["lado"]))
	_criar_etiqueta(peca, ficha)
	pecas[celula] = peca

	if ficha["lado"] == "jogador":
		celula_jogador = celula
		distancia_maxima = int(ficha["velocidade"])
		indice_distancia = maxi(OPCOES_DISTANCIA.find(distancia_maxima), 0)
		movimento_restante = distancia_maxima

	_atualizar_destaques()
	_atualizar_interface()
	_notificar_personagens()
	print("Personagem '", ficha["nome"], "' (", modelo, ", ", ficha["lado"], ") em ", celula)
	return true


func remover_peca(celula: Vector2i) -> bool:
	if not celula_ocupada(celula):
		_falhar("Não há ninguém na célula (%d,%d)." % [celula.x, celula.y])
		return false
	var peca: Node3D = pecas[celula]
	var ficha: Dictionary = peca.get_meta("ficha", {})
	_soltar_todos_os_itens(str(ficha.get("nome", "")), celula)
	if str(ficha.get("lado", "")) == "jogador":
		celula_jogador = CELULA_INVALIDA
	peca.queue_free()
	pecas.erase(celula)
	_atualizar_destaques()
	_atualizar_interface()
	_notificar_personagens()
	return true


# Usado pelo clique direito / Delete (ferramenta de teste)
func remover_personagem_ia(celula: Vector2i) -> bool:
	if not celula_ocupada(celula):
		return false
	if str(ficha_em(celula).get("lado", "")) == "jogador":
		_mostrar_aviso("O personagem do jogador não pode ser removido por aqui.")
		return false
	return remover_peca(celula)


# Move uma peça. "caminho" (opcional) = lista de células por onde ela passa (para contornar obstáculos visualmente).
func mover_peca(origem: Vector2i, destino: Vector2i, caminho: Array = []) -> bool:
	if not celula_ocupada(origem):
		_falhar("Não há ninguém em (%d,%d)." % [origem.x, origem.y])
		return false
	if not celula_valida(destino):
		_falhar("Destino (%d,%d) fora do tabuleiro." % [destino.x, destino.y])
		return false
	if celula_ocupada(destino):
		_falhar("O destino (%d,%d) já está ocupado." % [destino.x, destino.y])
		return false
	if eh_obstaculo(destino):
		_falhar("O destino (%d,%d) está bloqueado por um obstáculo." % [destino.x, destino.y])
		return false

	var peca: Node3D = pecas[origem]
	pecas.erase(origem)
	pecas[destino] = peca

	var ficha: Dictionary = peca.get_meta("ficha", {})
	if str(ficha.get("lado", "")) == "jogador":
		celula_jogador = destino
	var historico: Array = ficha.get("historico", [])
	historico.append(origem)
	while historico.size() > 3:
		historico.pop_front()
	ficha["historico"] = historico

	var animacao := peca.create_tween()
	if caminho.is_empty():
		animacao.tween_property(peca, "position", _pos_peca(destino), 0.25)
	else:
		for c in caminho:
			animacao.tween_property(peca, "position", _pos_peca(c), 0.12)
	if modo == "exploracao":
		salvar_mundo()
	return true


func _duracao_do_caminho(caminho: Array) -> float:
	if caminho.is_empty():
		return 0.3
	return 0.12 * float(caminho.size()) + 0.05


func _nome_livre(base: String) -> String:
	var nome: String = base.strip_edges()
	if nome == "":
		nome = "Criatura"
	var candidato: String = nome
	var n: int = 2
	while _achar_exato(candidato) != CELULA_INVALIDA or objetos.has(candidato):
		candidato = "%s %d" % [nome, n]
		n += 1
	return candidato


func _achar_exato(nome: String) -> Vector2i:
	for celula in pecas.keys():
		if str(ficha_em(celula).get("nome", "")) == nome:
			return celula
	return CELULA_INVALIDA


# Procura por nome ignorando maiúsculas; aceita parte do nome ("Barnaby" acha "Taberneiro Barnaby")
func _achar_por_nome(nome: String) -> Vector2i:
	var alvo: String = nome.strip_edges().to_lower()
	if alvo == "":
		return CELULA_INVALIDA
	for celula in pecas.keys():
		if str(ficha_em(celula).get("nome", "")).to_lower() == alvo:
			return celula
	for celula in pecas.keys():
		var n: String = str(ficha_em(celula).get("nome", "")).to_lower()
		if n.contains(alvo) or alvo.contains(n):
			return celula
	return CELULA_INVALIDA


func _contar_npcs() -> int:
	var total: int = 0
	for celula in pecas.keys():
		if str(ficha_em(celula).get("lado", "")) != "jogador":
			total += 1
	return total


func _contar_lado(lado: String) -> int:
	var total: int = 0
	for celula in pecas.keys():
		if str(ficha_em(celula).get("lado", "")) == lado:
			total += 1
	return total


# ---------------------------------------------------------------
# CAMINHOS (Dijkstra por "baldes": custo de cada passo é 1, 2 ou 3)
# ---------------------------------------------------------------
# Custo de dar um passo de "a" para "b" (-1 = impossível):
#   - obstáculo bloqueia; não dá para "cortar quina" de obstáculo na diagonal
#   - subir custa +1 por nível; subir mais que SUBIDA_MAXIMA é impossível; descer é de graça
func _custo_do_passo(a: Vector2i, b: Vector2i) -> int:
	if eh_obstaculo(b):
		return -1
	if a.x != b.x and a.y != b.y:
		if eh_obstaculo(Vector2i(b.x, a.y)) or eh_obstaculo(Vector2i(a.x, b.y)):
			return -1
	var subida: int = altura_de(b) - altura_de(a)
	if subida > SUBIDA_MAXIMA:
		return -1
	return 1 + maxi(subida, 0)


# Devolve {célula: custo}. Se "previos" for passado, é preenchido com {célula: célula anterior}.
func _dijkstra(origem: Vector2i, limite: int, considerar_pecas: bool, previos: Dictionary = {}) -> Dictionary:
	var custos: Dictionary = {origem: 0}
	var baldes: Array = [[origem]]
	var c: int = 0
	while c < baldes.size() and c <= limite:
		var lista: Array = baldes[c]
		var i: int = 0
		while i < lista.size():
			var atual: Vector2i = lista[i]
			i += 1
			if int(custos[atual]) != c:
				continue
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					var viz: Vector2i = atual + Vector2i(dx, dz)
					if not celula_valida(viz):
						continue
					if considerar_pecas and pecas.has(viz):
						continue
					var passo: int = _custo_do_passo(atual, viz)
					if passo < 0:
						continue
					var novo: int = c + passo
					if novo > limite:
						continue
					if custos.has(viz) and int(custos[viz]) <= novo:
						continue
					custos[viz] = novo
					previos[viz] = atual
					while baldes.size() <= novo:
						baldes.append([])
					baldes[novo].append(viz)
		c += 1
	return custos


# Células alcançáveis andando no máximo "limite" (peças bloqueiam se considerar_pecas = true)
func calcular_alcance(origem: Vector2i, limite: int, considerar_pecas: bool = true) -> Dictionary:
	return _dijkstra(origem, limite, considerar_pecas)


# Distância andando (contornando obstáculos, ignorando peças) até todas as células do tabuleiro
func mapa_distancias(origem: Vector2i) -> Dictionary:
	return _dijkstra(origem, 40, false)


func _reconstruir_caminho(previos: Dictionary, origem: Vector2i, destino: Vector2i) -> Array:
	var caminho: Array = []
	var atual: Vector2i = destino
	var seguranca: int = 0
	while atual != origem and previos.has(atual) and seguranca < 500:
		caminho.push_front(atual)
		atual = previos[atual]
		seguranca += 1
	return caminho


# Linha de visão: nenhum obstáculo entre as duas células (algoritmo de Bresenham)
func linha_de_visao(a: Vector2i, b: Vector2i) -> bool:
	var x0: int = a.x
	var y0: int = a.y
	var dx: int = absi(b.x - a.x)
	var dy: int = absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var erro: int = dx - dy
	var passos: int = 0
	while not (x0 == b.x and y0 == b.y) and passos < 200:
		var e2: int = 2 * erro
		if e2 > -dy:
			erro -= dy
			x0 += sx
		if e2 < dx:
			erro += dx
			y0 += sy
		passos += 1
		if not (x0 == b.x and y0 == b.y) and eh_obstaculo(Vector2i(x0, y0)):
			return false
	return true


# ===============================================================
# COMBATE
# ===============================================================

func _log(texto: String) -> void:
	eventos_turno.append(texto)
	print(texto)
	log_de_combate.emit(texto)


# Escolhe o melhor ataque de quem está em "de" contra o alvo em "alvo" (ou {} se nenhum serve)
func melhor_ataque(de: Vector2i, alvo: Vector2i) -> Dictionary:
	var ficha: Dictionary = ficha_em(de)
	var melhor: Dictionary = {}
	var melhor_media: float = -1.0
	for ataque in ficha.get("ataques", []):
		if ataque.has("usos") and int(ataque["usos"]) <= 0:
			continue
		var alcance: int = int(ataque.get("alcance", 1))
		if distancia(de, alvo) > alcance:
			continue
		if alcance > 1 and not linha_de_visao(de, alvo):
			continue
		var media: float = Regras.media(str(ataque.get("dado", "1d4")))
		if media > melhor_media:
			melhor_media = media
			melhor = ataque
	return melhor


# Executa um ataque (rola dados, aplica dano, anima). Mortos saem do tabuleiro.
func atacar(de: Vector2i, ataque: Dictionary, alvo_cel: Vector2i) -> void:
	if not pecas.has(de):
		return
	var ficha_a: Dictionary = ficha_em(de)
	var nome_a: String = str(ficha_a.get("nome", "?"))
	var nome_ataque: String = str(ataque.get("nome", "ataque"))
	var alcance: int = int(ataque.get("alcance", 1))
	var area: int = int(ataque.get("area", 0))
	var automatico: bool = bool(ataque.get("automatico", false))
	var dado: String = str(ataque.get("dado", "1d4"))

	if ataque.has("usos"):
		ataque["usos"] = int(ataque["usos"]) - 1
	_animar_ataque(de, alvo_cel, alcance, area)

	# Quem é atingido?
	var atingidos: Array = []
	if area > 0:
		for c in pecas.keys():
			if distancia(c, alvo_cel) <= area:
				atingidos.append(c)
		_log("%s conjura %s em (%d,%d)." % [nome_a, nome_ataque, alvo_cel.x, alvo_cel.y])
	else:
		atingidos.append(alvo_cel)

	var dano_da_area: int = Regras.rolar_dano(dado, false) if (area > 0 or automatico) else 0
	var mortos: Array = []
	for c in atingidos:
		if not pecas.has(c):
			continue
		var f: Dictionary = ficha_em(c)
		var nome_alvo: String = str(f.get("nome", "?"))
		var dano: int = 0
		var texto: String = ""
		if area > 0 or automatico:
			dano = dano_da_area
			texto = "%s sofre %d de dano de %s" % [nome_alvo, dano, nome_ataque]
		else:
			var bonus: int = int(ataque.get("bonus", 0))
			if alcance > 1 and altura_de(de) > altura_de(c):
				bonus += 1
			var rolagem: Dictionary = Regras.rolar_ataque(bonus, int(f.get("ca", 10)))
			var conta: String = "d20=%d%+d=%d vs CA %d" % [rolagem["d20"], bonus, rolagem["total"], int(f.get("ca", 10))]
			if rolagem["acertou"]:
				dano = Regras.rolar_dano(dado, bool(rolagem["critico"]))
				texto = "%s ataca %s com %s (%s): %s, %d de dano" % [nome_a, nome_alvo, nome_ataque, conta, "CRÍTICO" if rolagem["critico"] else "ACERTOU", dano]
			else:
				texto = "%s ataca %s com %s (%s): ERROU" % [nome_a, nome_alvo, nome_ataque, conta]
		if dano > 0:
			var pv_antes: int = int(f["pv"])
			f["pv"] = maxi(pv_antes - dano, 0)
			texto += " (PV %d -> %d)" % [pv_antes, int(f["pv"])]
			_piscar_peca(pecas[c])
			_atualizar_etiqueta(pecas[c])
			if int(f["pv"]) <= 0:
				mortos.append(c)
		_log(texto + ".")

	for c in mortos:
		_morrer(c)
	_atualizar_interface()
	_notificar_personagens()


func _morrer(celula: Vector2i) -> void:
	if not pecas.has(celula):
		return
	var ficha: Dictionary = ficha_em(celula)
	var nome: String = str(ficha.get("nome", "?"))
	var era_jogador: bool = str(ficha.get("lado", "")) == "jogador"
	_log("%s caiu!" % nome)
	registrar_evento("morte", "%s morreu." % nome)
	remover_peca(celula)
	if era_jogador:
		apagar_mundo()
		fim_de_jogo = true
		_mostrar_aviso("%s foi derrotado. Fim de jogo (F9 reinicia)." % nome)
	elif _contar_lado("inimigo") == 0:
		_log("Todos os inimigos foram derrotados!")


func _animar_ataque(de: Vector2i, alvo: Vector2i, alcance: int, area: int) -> void:
	var origem_pos: Vector3 = _pos_peca(de) + Vector3(0.0, 0.3, 0.0)
	var alvo_pos: Vector3 = _celula_para_posicao(alvo, _y_base(alvo) + 0.8)
	if alcance <= 1 and area == 0:
		# investida curta no corpo a corpo
		if pecas.has(de):
			var peca: Node3D = pecas[de]
			var base: Vector3 = _pos_peca(de)
			var meio: Vector3 = base + (alvo_pos - origem_pos).normalized() * 0.6
			var tw := peca.create_tween()
			tw.tween_property(peca, "position", Vector3(meio.x, base.y, meio.z), 0.1)
			tw.tween_property(peca, "position", base, 0.12)
		return

	# projétil / magia
	var bola := MeshInstance3D.new()
	var malha := SphereMesh.new()
	malha.radius = 0.2 if area == 0 else 0.35
	malha.height = malha.radius * 2.0
	bola.mesh = malha
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.1) if area > 0 else Color(0.95, 0.95, 0.7)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	bola.material_override = mat
	add_child(bola)
	bola.position = origem_pos
	var tw2 := bola.create_tween()
	tw2.tween_property(bola, "position", alvo_pos, 0.25)
	if area > 0:
		var raio: float = float(area) * TAMANHO_CELULA + 0.5
		tw2.tween_property(bola, "scale", Vector3.ONE * raio * 2.0, 0.2)
	tw2.tween_callback(bola.queue_free)


func _piscar_peca(peca: Node3D) -> void:
	var mat = peca.get_meta("material", null)
	if mat == null:
		return
	var cor: Color = peca.get_meta("cor_original", Color.WHITE)
	var tw := peca.create_tween()
	tw.tween_property(mat, "albedo_color", Color(1, 1, 1), 0.08)
	tw.tween_property(mat, "albedo_color", cor, 0.25)


# ---------------------------------------------------------------
# ATAQUE DO JOGADOR (clique esquerdo em um inimigo)
# ---------------------------------------------------------------
func jogador_atacar(alvo_cel: Vector2i) -> bool:
	if fim_de_jogo:
		return false
	if modo != "combate":
		_mostrar_aviso("Fora de combate. Diga ao Mestre no chat que você quer atacar (ou aperte K para iniciar o combate).")
		return false
	if turno_atual != Turno.JOGADOR or turno_em_andamento:
		_mostrar_aviso("Não é o seu turno!")
		return false
	if celula_jogador == CELULA_INVALIDA:
		return false
	if not acao_disponivel:
		_mostrar_aviso("Você já usou sua ação neste turno.")
		return false
	if not sao_hostis(ficha_em(celula_jogador), ficha_em(alvo_cel)):
		_mostrar_aviso("Esse alvo não é um inimigo.")
		return false
	var ataque: Dictionary = melhor_ataque(celula_jogador, alvo_cel)
	if ataque.is_empty():
		_mostrar_aviso("Fora de alcance ou sem linha de visão (ande mais perto).")
		return false
	acao_disponivel = false
	aviso = ""
	atacar(celula_jogador, ataque, alvo_cel)
	_atualizar_destaques()
	_atualizar_interface()
	return true


# ===============================================================
# TURNOS
# ===============================================================

func mover_jogador(destino: Vector2i) -> bool:
	if fim_de_jogo:
		return false
	var livre: bool = movimento_livre and modo != "combate"
	if modo != "combate" and not livre:
		_mostrar_aviso("Fora de combate quem move você é o Mestre: diga no chat para onde quer ir (ex.: \"vou até a cabana\").")
		return false
	if not livre and (turno_atual != Turno.JOGADOR or turno_em_andamento):
		_mostrar_aviso("Não é o seu turno! Aguarde.")
		return false
	if celula_jogador == CELULA_INVALIDA:
		_mostrar_aviso("O personagem do jogador não está no tabuleiro.")
		return false
	if destino == celula_jogador:
		return false

	var limite_mov: int = LIMITE_EXPLORACAO if livre else movimento_restante
	var previos: Dictionary = {}
	var alcance: Dictionary = _dijkstra(celula_jogador, limite_mov, true, previos)
	if not alcance.has(destino):
		_mostrar_aviso("Fora do alcance! Você ainda pode andar %d de movimento (subir custa mais, obstáculos bloqueiam)." % movimento_restante)
		return false

	var custo: int = alcance[destino]
	var caminho: Array = _reconstruir_caminho(previos, celula_jogador, destino)
	if not mover_peca(celula_jogador, destino, caminho):
		return false
	if not livre:
		movimento_restante -= custo
	aviso = ""
	_atualizar_destaques()
	_atualizar_interface()
	return true


# Botão "Encerrar turno" / Espaço: só vale no combate, no turno do jogador.
func encerrar_turno() -> void:
	if modo != "combate":
		_mostrar_aviso("Não há turnos fora de combate. Converse com o Mestre no chat.")
		return
	if turno_atual != Turno.JOGADOR or fim_de_jogo:
		return
	turno_em_andamento = true
	aviso = ""
	_atualizar_destaques()
	_atualizar_interface()
	jogador_encerrou.emit()


func _mestre() -> Node:
	if not USAR_MESTRE_IA:
		return null
	return get_node_or_null("/root/MestreIA")


# ---------------------------------------------------------------
# COMBATE POR INICIATIVA (igual à mesa de RPG)
# ---------------------------------------------------------------
const RAIO_DE_AMEACA: int = 8     # o Mestre só pode iniciar combate se algum inimigo estiver a esta distância do Kuzin


func _inimigo_proximo(raio: int) -> bool:
	if celula_jogador == CELULA_INVALIDA:
		return false
	var minha: Dictionary = ficha_em(celula_jogador)
	for c in pecas.keys():
		if sao_hostis(minha, ficha_em(c)) and distancia(celula_jogador, c) <= raio:
			return true
	return false


# motivo = o que desencadeou a luta (aparece no log). origem = "mestre" aplica as travas de coerência.
func iniciar_combate(motivo: String = "", origem: String = "jogo") -> bool:
	if modo == "combate":
		_falhar("O combate já começou.")
		return false
	if fim_de_jogo:
		_falhar("O jogo acabou.")
		return false
	if _contar_lado("inimigo") == 0:
		_falhar("Não há inimigos no tabuleiro para lutar.")
		return false
	if origem == "mestre":
		if motivo.strip_edges() == "":
			_falhar("Para iniciar combate você precisa informar o MOTIVO no campo 'texto' (o que desencadeou a luta).")
			return false
		if not _inimigo_proximo(RAIO_DE_AMEACA):
			_falhar("Nenhum inimigo está a %d células ou menos de Kuzin: ninguém o ameaça ainda. Aproxime os inimigos (mover) ou narre o perigo sem iniciar combate." % RAIO_DE_AMEACA)
			return false

	# Rola iniciativa: d20 + modificador
	var rolagens: Array = []
	for celula in pecas.keys():
		var f: Dictionary = ficha_em(celula)
		var valor: int = randi_range(1, 20) + int(f.get("iniciativa", 0))
		rolagens.append({"nome": str(f["nome"]), "valor": valor})
	rolagens.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["valor"]) > int(b["valor"]))
	ordem_iniciativa = []
	var partes: Array = []
	for r in rolagens:
		ordem_iniciativa.append(r["nome"])
		partes.append("%s %d" % [r["nome"], r["valor"]])

	modo = "combate"
	rodada = 1
	_limpar_debug()
	_log("COMBATE! " + ("Motivo: " + motivo.strip_edges() + ". " if motivo.strip_edges() != "" else "") + "Iniciativa: " + ", ".join(partes) + ".")
	registrar_evento("combate", "Combate começou. " + ("Motivo: " + motivo.strip_edges() + "." if motivo.strip_edges() != "" else ""))
	_atualizar_destaques()
	_atualizar_interface()
	_loop_de_combate()          # roda "em segundo plano" (é uma corrotina)
	return true


func encerrar_combate() -> bool:
	if modo != "combate":
		_falhar("Não há combate em andamento.")
		return false
	modo = "exploracao"
	ator_atual = ""
	turno_atual = Turno.JOGADOR
	turno_em_andamento = false
	_log("O combate terminou.")
	registrar_evento("combate", "O combate terminou.")
	jogador_encerrou.emit()      # acorda o laço caso ele esteja esperando o jogador
	_atualizar_destaques()
	_atualizar_interface()
	return true


func _loop_de_combate() -> void:
	while modo == "combate" and not fim_de_jogo:
		for nome in ordem_iniciativa.duplicate():
			if modo != "combate" or fim_de_jogo:
				break
			var celula: Vector2i = _achar_exato(str(nome))
			if celula == CELULA_INVALIDA:
				continue                           # morreu
			ator_atual = str(nome)
			if str(ficha_em(celula).get("lado", "")) == "jogador":
				await _narrar_pendentes()
				if modo != "combate" or fim_de_jogo:
					break
				_comecar_turno_do_jogador()
				await jogador_encerrou
			else:
				turno_atual = Turno.IA
				_atualizar_destaques()
				_atualizar_interface()
				await get_tree().create_timer(0.35).timeout
				if modo != "combate" or fim_de_jogo:
					break
				await _turno_do_npc(celula)
			if modo == "combate" and _contar_lado("inimigo") == 0:
				encerrar_combate()
		if modo == "combate":
			rodada += 1
	await _narrar_pendentes()
	turno_atual = Turno.JOGADOR
	turno_em_andamento = false
	_atualizar_destaques()
	_atualizar_interface()


func _comecar_turno_do_jogador() -> void:
	turno_atual = Turno.JOGADOR
	turno_em_andamento = false
	movimento_restante = distancia_maxima
	acao_disponivel = true
	aviso = ""
	_limpar_debug()
	_atualizar_destaques()
	_atualizar_interface()


# Entrega ao Mestre IA (texto) o que aconteceu, para ele narrar
func _narrar_pendentes() -> void:
	if eventos_turno.is_empty():
		return
	var lista: Array = eventos_turno.duplicate()
	eventos_turno.clear()
	var mestre: Node = _mestre()
	if mestre != null and mestre.has_method("esta_pronto") and mestre.esta_pronto():
		await mestre.narrar_turno(lista)


func _turno_do_npc(origem: Vector2i) -> void:
	if not pecas.has(origem):
		return
	var ficha: Dictionary = ficha_em(origem)
	var plano: Dictionary = IATatica.decidir(self, origem)

	ultimo_debug_texto = str(plano["texto"])
	if debug_ativo:
		print("[IA] ", ultimo_debug_texto)
		_desenhar_debug(plano, origem)
		_atualizar_interface()
		await get_tree().create_timer(0.9).timeout

	var destino: Vector2i = plano["destino"]
	var atual: Vector2i = origem
	if destino != origem:
		var previos: Dictionary = {}
		_dijkstra(origem, int(ficha.get("velocidade", 6)), true, previos)
		var caminho: Array = _reconstruir_caminho(previos, origem, destino)
		if mover_peca(origem, destino, caminho):
			atual = destino
			await get_tree().create_timer(_duracao_do_caminho(caminho)).timeout

	var ataque: Dictionary = plano["ataque"]
	if not ataque.is_empty() and pecas.has(atual):
		var alvo: Vector2i = plano["alvo_celula"]
		# O alvo pode ter morrido/mudado: confere se ainda tem alguém lá (ou é magia de área)
		if int(ataque.get("area", 0)) > 0 or pecas.has(alvo):
			atacar(atual, ataque, alvo)
			await get_tree().create_timer(0.7).timeout
	elif destino == origem and ataque.is_empty() and plano["texto"] != "":
		pass


func definir_distancia_maxima(celulas: int) -> bool:
	if celulas < 1 or celulas > TAMANHO_MAXIMO:
		return false
	distancia_maxima = celulas
	indice_distancia = maxi(OPCOES_DISTANCIA.find(celulas), 0)
	if turno_atual == Turno.JOGADOR:
		movimento_restante = distancia_maxima
	_atualizar_destaques()
	_atualizar_interface()
	return true


# ===============================================================
# MUNDO INTERATIVO (objetos, itens, cenário)
# ===============================================================

func _objeto_bloqueia(obj: Dictionary) -> bool:
	var dados: Dictionary = CATALOGO_OBJETOS[str(obj["modelo"])]
	if not bool(dados["bloqueia"]):
		return false
	return not ESTADOS_LIVRES.has(str(obj["estado"]))


func _recalcular_obstaculos() -> void:
	obstaculos.clear()
	for nome in objetos.keys():
		var obj: Dictionary = objetos[nome]
		if str(obj["dono"]) == "" and _objeto_bloqueia(obj):
			obstaculos[obj["celula"]] = true


func _objetos_na_celula(celula: Vector2i) -> Array:
	var lista: Array = []
	for nome in objetos.keys():
		var obj: Dictionary = objetos[nome]
		if obj["celula"] == celula and str(obj["dono"]) == "":
			lista.append(nome)
	return lista


func _achar_objeto(nome: String) -> String:
	var alvo: String = nome.strip_edges().to_lower()
	if alvo == "":
		return ""
	for n in objetos.keys():
		if str(n).to_lower() == alvo:
			return str(n)
	for n in objetos.keys():
		var minusculo: String = str(n).to_lower()
		if minusculo.contains(alvo) or alvo.contains(minusculo):
			return str(n)
	return ""


func criar_objeto(nome: String, modelo: String, celula: Vector2i) -> bool:
	if not CATALOGO_OBJETOS.has(modelo):
		_falhar("Objeto desconhecido: %s. Use um destes: %s." % [modelo, ", ".join(CATALOGO_OBJETOS.keys())])
		return false
	if not celula_valida(celula):
		_falhar("Célula (%d,%d) fora do tabuleiro." % [celula.x, celula.y])
		return false
	if objetos.size() >= MAX_OBJETOS:
		_falhar("Já existem objetos demais (máximo %d)." % MAX_OBJETOS)
		return false
	var dados: Dictionary = CATALOGO_OBJETOS[modelo]
	if eh_obstaculo(celula):
		_falhar("A célula (%d,%d) já está bloqueada por outro objeto." % [celula.x, celula.y])
		return false
	if bool(dados["bloqueia"]):
		if celula_ocupada(celula):
			_falhar("Tem alguém na célula (%d,%d); não dá para colocar %s ali." % [celula.x, celula.y, modelo])
			return false
		if not _objetos_na_celula(celula).is_empty():
			_falhar("Já existe um objeto na célula (%d,%d)." % [celula.x, celula.y])
			return false

	var nome_final: String = _nome_livre(nome if nome.strip_edges() != "" else modelo.capitalize())
	var no: Node3D = _criar_visual_objeto(modelo)
	add_child(no)
	var obj: Dictionary = {"nome": nome_final, "modelo": modelo, "celula": celula,
		"estado": str((dados["estados"] as Array)[0]), "dono": "", "no": no}
	objetos[nome_final] = obj
	_nome_criado_por_ultimo = nome_final
	if modelo != "muro" and modelo != "parede":
		var rot := Label3D.new()
		rot.text = nome_final
		rot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		rot.no_depth_test = true
		rot.pixel_size = 0.007
		rot.font_size = 40
		rot.outline_size = 10
		rot.modulate = Color(1.0, 1.0, 0.8)
		rot.position = Vector3(0.0, (dados["tamanho"] as Vector3).y + 0.5, 0.0)
		no.add_child(rot)
	_posicionar_objeto(obj)
	_aplicar_estado_visual(obj)
	_recalcular_obstaculos()
	_atualizar_destaques()
	print("Objeto '", nome_final, "' (", modelo, ") em ", celula)
	return true


func _criar_visual_objeto(modelo: String) -> Node3D:
	var dados: Dictionary = CATALOGO_OBJETOS[modelo]
	var tam: Vector3 = dados["tamanho"]
	var raiz := Node3D.new()
	var malha := MeshInstance3D.new()
	var forma: String = str(dados["forma"])
	if forma == "esfera":
		var m := SphereMesh.new()
		m.radius = tam.x / 2.0
		m.height = tam.y
		malha.mesh = m
	elif forma == "cilindro":
		var m2 := CylinderMesh.new()
		m2.top_radius = tam.x / 2.0
		m2.bottom_radius = tam.x / 2.0
		m2.height = tam.y
		malha.mesh = m2
	else:
		var m3 := BoxMesh.new()
		m3.size = tam
		malha.mesh = m3
	var material := StandardMaterial3D.new()
	material.albedo_color = dados["cor"]
	malha.material_override = material
	malha.position.y = tam.y / 2.0
	raiz.add_child(malha)
	raiz.set_meta("material", material)
	raiz.set_meta("malha", malha)
	if bool(dados.get("luz", false)):
		var luz := OmniLight3D.new()
		luz.position.y = tam.y + 0.3
		luz.light_color = Color(1.0, 0.65, 0.3)
		luz.omni_range = 7.0
		luz.light_energy = 0.0
		raiz.add_child(luz)
		raiz.set_meta("luz", luz)
	return raiz


func _posicionar_objeto(obj: Dictionary) -> void:
	var no: Node3D = obj["no"]
	if not is_instance_valid(no):
		return
	var celula: Vector2i = obj["celula"]
	no.position = _celula_para_posicao(celula, _y_base(celula))
	no.rotation = Vector3.ZERO


# Itens carregados acompanham quem os carrega (flutuam acima da cabeça)
func _seguir_carregadores() -> void:
	var contagem: Dictionary = {}
	for nome in objetos.keys():
		var obj: Dictionary = objetos[nome]
		var dono: String = str(obj["dono"])
		if dono == "":
			continue
		var cel: Vector2i = _achar_exato(dono)
		var no: Node3D = obj["no"]
		if cel == CELULA_INVALIDA or not is_instance_valid(no):
			continue
		var n: int = int(contagem.get(dono, 0))
		contagem[dono] = n + 1
		no.position = pecas[cel].position + Vector3(0.0, ALTURA_PERSONAGEM / 2.0 + 0.1 + 0.35 * float(n), 0.0)


func _aplicar_estado_visual(obj: Dictionary) -> void:
	var no: Node3D = obj["no"]
	if not is_instance_valid(no):
		return
	var dados: Dictionary = CATALOGO_OBJETOS[str(obj["modelo"])]
	var estado: String = str(obj["estado"])
	var material: StandardMaterial3D = no.get_meta("material")
	var malha: MeshInstance3D = no.get_meta("malha")
	var cor_base: Color = dados["cor"]
	var tam: Vector3 = dados["tamanho"]

	material.albedo_color = cor_base
	material.emission_enabled = false
	malha.scale = Vector3.ONE
	malha.position.y = tam.y / 2.0
	no.rotation = Vector3.ZERO

	match estado:
		"aberto":
			material.albedo_color = cor_base.lightened(0.35)
			if str(obj["modelo"]) == "porta":
				# porta aberta = só a soleira no chão (passagem livre)
				malha.scale = Vector3(1.0, 0.06, 1.0)
				malha.position.y = tam.y * 0.03
		"quebrado":
			material.albedo_color = cor_base.darkened(0.45)
			malha.scale = Vector3(1.0, 0.4, 1.0)
			malha.position.y = tam.y * 0.2
		"aceso":
			material.emission_enabled = true
			material.emission = Color(1.0, 0.55, 0.15)
			material.emission_energy_multiplier = 1.5
		"apagado":
			material.albedo_color = cor_base.darkened(0.3)
		"destruido":
			material.albedo_color = cor_base.darkened(0.6)
			malha.scale = Vector3(1.0, 0.15, 1.0)
			malha.position.y = tam.y * 0.075

	if no.has_meta("luz"):
		var luz: OmniLight3D = no.get_meta("luz")
		luz.light_energy = 2.0 if estado == "aceso" else 0.0


func mover_objeto(nome: String, destino: Vector2i) -> bool:
	if not objetos.has(nome):
		_falhar("Não existe o objeto '%s'." % nome)
		return false
	var obj: Dictionary = objetos[nome]
	var dados: Dictionary = CATALOGO_OBJETOS[str(obj["modelo"])]
	if not bool(dados["movel"]):
		_falhar("'%s' não pode ser movido (é fixo)." % nome)
		return false
	if str(obj["dono"]) != "":
		_falhar("'%s' está com %s; peça para soltar primeiro." % [nome, str(obj["dono"])])
		return false
	if not celula_valida(destino):
		_falhar("Destino (%d,%d) fora do tabuleiro." % [destino.x, destino.y])
		return false
	if distancia(obj["celula"], destino) > ALCANCE_OBJETO:
		_falhar("Longe demais: um objeto só vai até %d células de uma vez." % ALCANCE_OBJETO)
		return false
	if eh_obstaculo(destino):
		_falhar("O destino (%d,%d) está bloqueado." % [destino.x, destino.y])
		return false
	if bool(dados["bloqueia"]) and (celula_ocupada(destino) or not _objetos_na_celula(destino).is_empty()):
		_falhar("O destino (%d,%d) está ocupado." % [destino.x, destino.y])
		return false

	var no: Node3D = obj["no"]
	var inicio: Vector3 = no.position
	obj["celula"] = destino
	var fim: Vector3 = _celula_para_posicao(destino, _y_base(destino))
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(no):
			var p: Vector3 = inicio.lerp(fim, t)
			p.y += sin(t * PI) * 1.2
			no.position = p, 0.0, 1.0, 0.6)
	_recalcular_obstaculos()
	_atualizar_destaques()
	return true


func dar_item(nome_objeto: String, nome_personagem: String) -> bool:
	if not objetos.has(nome_objeto):
		_falhar("Não existe o objeto '%s'." % nome_objeto)
		return false
	var obj: Dictionary = objetos[nome_objeto]
	var dados: Dictionary = CATALOGO_OBJETOS[str(obj["modelo"])]
	if not bool(dados["item"]):
		_falhar("'%s' não é um item que dá para carregar." % nome_objeto)
		return false
	if str(obj["dono"]) != "":
		_falhar("'%s' já está com %s." % [nome_objeto, str(obj["dono"])])
		return false
	var cel: Vector2i = _achar_por_nome(nome_personagem)
	if cel == CELULA_INVALIDA:
		_falhar("Não existe o personagem '%s'." % nome_personagem)
		return false
	if distancia(obj["celula"], cel) > 1:
		_falhar("'%s' está longe de %s (célula (%d,%d)). Use mover_objeto para trazê-lo até perto antes." % [nome_objeto, nome_personagem, obj["celula"].x, obj["celula"].y])
		return false

	var ficha: Dictionary = ficha_em(cel)
	obj["dono"] = str(ficha["nome"])
	(ficha["inventario"] as Array).append(nome_objeto)
	registrar_evento("item", "%s pegou %s." % [str(ficha["nome"]), nome_objeto])
	_recalcular_obstaculos()
	_atualizar_interface()
	return true


func soltar_item(nome_objeto: String) -> bool:
	if not objetos.has(nome_objeto):
		_falhar("Não existe o objeto '%s'." % nome_objeto)
		return false
	var obj: Dictionary = objetos[nome_objeto]
	var dono: String = str(obj["dono"])
	if dono == "":
		_falhar("'%s' não está com ninguém." % nome_objeto)
		return false
	var cel: Vector2i = _achar_exato(dono)
	if cel == CELULA_INVALIDA:
		_falhar("Não achei quem carrega '%s'." % nome_objeto)
		return false
	_largar(nome_objeto, cel)
	registrar_evento("item", "%s largou %s." % [dono, nome_objeto])
	_atualizar_interface()
	return true


func _largar(nome_objeto: String, celula: Vector2i) -> void:
	var obj: Dictionary = objetos[nome_objeto]
	var dono_cel: Vector2i = _achar_exato(str(obj["dono"]))
	if dono_cel != CELULA_INVALIDA:
		(ficha_em(dono_cel)["inventario"] as Array).erase(nome_objeto)
	obj["dono"] = ""
	obj["celula"] = celula
	_posicionar_objeto(obj)
	_recalcular_obstaculos()


func _soltar_todos_os_itens(nome_dono: String, celula: Vector2i) -> void:
	for nome in objetos.keys():
		if str(objetos[nome]["dono"]) == nome_dono:
			_largar(nome, celula)


func mudar_estado(nome_objeto: String, estado: String) -> bool:
	if not objetos.has(nome_objeto):
		_falhar("Não existe o objeto '%s'." % nome_objeto)
		return false
	var obj: Dictionary = objetos[nome_objeto]
	var dados: Dictionary = CATALOGO_OBJETOS[str(obj["modelo"])]
	if not (dados["estados"] as Array).has(estado):
		_falhar("'%s' (%s) só pode ficar: %s." % [nome_objeto, obj["modelo"], ", ".join(dados["estados"])])
		return false
	if estado == "fechado" and bool(dados["bloqueia"]) and celula_ocupada(obj["celula"]):
		_falhar("Tem alguém na frente; não dá para fechar.")
		return false
	if estado == "aberto" and bool(obj.get("trancado", false)):
		_falhar("'%s' está trancado; é preciso destrancar ou arrombar." % nome_objeto)
		return false
	obj["estado"] = estado
	registrar_evento("objeto", "%s agora está %s." % [nome_objeto, estado])
	_posicionar_objeto(obj)
	_aplicar_estado_visual(obj)
	_recalcular_obstaculos()
	_atualizar_destaques()
	return true


func remover_objeto(nome_objeto: String) -> bool:
	if not objetos.has(nome_objeto):
		_falhar("Não existe o objeto '%s'." % nome_objeto)
		return false
	var obj: Dictionary = objetos[nome_objeto]
	var dono: String = str(obj["dono"])
	if dono != "":
		var cel: Vector2i = _achar_exato(dono)
		if cel != CELULA_INVALIDA:
			(ficha_em(cel)["inventario"] as Array).erase(nome_objeto)
	var no: Node3D = obj["no"]
	if is_instance_valid(no):
		no.queue_free()
	objetos.erase(nome_objeto)
	_recalcular_obstaculos()
	_atualizar_destaques()
	_atualizar_interface()
	return true


# ===============================================================
# CAMADA 2: COMANDOS DO MESTRE IA
# ===============================================================
# Devolve um texto começando com "OK:" ou "FALHOU:" - o Mestre lê esse resultado no próximo turno.
# Exemplos de comando (Dictionary):
#   {"acao":"mover", "alvo":"Tharok", "x":3, "z":4}
#   {"acao":"colocar", "alvo":"Goblin Ladrão", "modelo":"goblin", "papel":"inimigo", "x":5, "z":5}
#   {"acao":"remover", "alvo":"Goblin Ladrão"}
#   {"acao":"intencao", "alvo":"Tharok", "estado":"fugir"}       (padrao | fugir | parado | agressivo)
#   {"acao":"criar_objeto", "alvo":"Pão quente", "modelo":"pao", "x":2, "z":6}
#   {"acao":"mover_objeto", "alvo":"Pão quente", "para":"Kuzin"}  (ou "x" e "z")
#   {"acao":"dar_item", "alvo":"Pão quente", "para":"Kuzin"}
#   {"acao":"soltar_item", "alvo":"Pão quente"}
#   {"acao":"mudar_estado", "alvo":"Tocha", "estado":"aceso"}
#   {"acao":"remover_objeto", "alvo":"Pão quente"}
#   {"acao":"definir_altura", "x":3, "z":3, "nivel":2}
var ultimo_motivo: String = ""
var _nome_criado_por_ultimo: String = ""
var _ultimo_predio: String = ""


func _falhar(motivo: String) -> void:
	ultimo_motivo = motivo
	print("FALHOU: ", motivo)


func executar_comando_mestre(comando: Dictionary) -> String:
	ultimo_motivo = ""
	var acao: String = str(comando.get("acao", ""))
	var alvo: String = str(comando.get("alvo", "")).strip_edges()
	var x: int = int(comando.get("x", -1))
	var z: int = int(comando.get("z", -1))
	var para: String = str(comando.get("para", "")).strip_edges()
	var modelo: String = str(comando.get("modelo", "")).strip_edges().to_lower()
	var estado: String = str(comando.get("estado", "")).strip_edges().to_lower()
	var resultado: bool = false

	match acao:
		"mover":
			var origem: Vector2i = _achar_por_nome(alvo)
			if origem == CELULA_INVALIDA:
				return "FALHOU: não existe ninguém chamado '%s'. %s" % [alvo, _lista_de_nomes()]
			var ficha: Dictionary = ficha_em(origem)
			var destino: Vector2i = Vector2i(x, z)
			if not celula_valida(destino):
				return "FALHOU: destino (%d,%d) fora do tabuleiro (x de 0 a %d, z de 0 a %d)." % [x, z, largura_tabuleiro - 1, profundidade_tabuleiro - 1]
			if modo == "combate":
				return "FALHOU: em combate cada personagem age no próprio turno (NPCs pela IA tática). Use 'intencao' para influenciar um NPC."
			var previos: Dictionary = {}
			var alcance: Dictionary = _dijkstra(origem, LIMITE_EXPLORACAO, true, previos)
			if not alcance.has(destino):
				return "FALHOU: %s não consegue chegar a (%d,%d): está bloqueado por obstáculos/personagens ou é longe demais. Escolha uma célula livre perto do destino." % [ficha["nome"], x, z]
			resultado = mover_peca(origem, destino, _reconstruir_caminho(previos, origem, destino))
			if resultado:
				return "OK: %s foi para (%d,%d)." % [ficha["nome"], x, z]
		"colocar":
			if _contar_npcs() >= MAX_NPCS:
				return "FALHOU: já existem personagens demais (máximo %d)." % MAX_NPCS
			if modelo == "":
				modelo = "goblin"
			var lado: String = str(comando.get("papel", "")).strip_edges().to_lower()
			if lado == "jogador":
				lado = ""
			if lado != "" and not ["aliado", "inimigo", "neutro"].has(lado):
				return "FALHOU: papel inválido '%s' (use aliado, inimigo ou neutro)." % lado
			resultado = colocar_personagem(Vector2i(x, z), alvo if alvo != "" else modelo.capitalize(), modelo, lado)
			if resultado:
				registrar_evento("cena", "%s apareceu na cena (%s)." % [alvo, lado if lado != "" else "criatura"])
				return "OK: %s apareceu em (%d,%d)." % [alvo, x, z]
		"remover":
			var cel: Vector2i = _achar_por_nome(alvo)
			if cel == CELULA_INVALIDA:
				return "FALHOU: não existe ninguém chamado '%s'. %s" % [alvo, _lista_de_nomes()]
			if str(ficha_em(cel).get("lado", "")) == "jogador":
				return "FALHOU: o personagem do jogador não pode ser removido."
			var nome_removido: String = str(ficha_em(cel)["nome"])
			resultado = remover_peca(cel)
			if resultado:
				registrar_evento("cena", "%s saiu de cena." % nome_removido)
				return "OK: %s saiu de cena." % nome_removido
		"intencao":
			var c2: Vector2i = _achar_por_nome(alvo)
			if c2 == CELULA_INVALIDA:
				return "FALHOU: não existe ninguém chamado '%s'. %s" % [alvo, _lista_de_nomes()]
			if not ["padrao", "fugir", "parado", "agressivo"].has(estado):
				return "FALHOU: intenção inválida '%s' (use padrao, fugir, parado ou agressivo)." % estado
			ficha_em(c2)["intencao"] = estado
			return "OK: %s agora está com a intenção '%s'." % [ficha_em(c2)["nome"], estado]
		"criar_objeto":
			resultado = criar_objeto(alvo, modelo, Vector2i(x, z))
			if resultado:
				return "OK: objeto criado em (%d,%d)." % [x, z]
		"mover_objeto":
			var nome_obj: String = _achar_objeto(alvo)
			if nome_obj == "":
				return "FALHOU: não existe o objeto '%s'. %s" % [alvo, _lista_de_objetos()]
			var dest: Vector2i = Vector2i(x, z)
			if para != "":
				var cp: Vector2i = _achar_por_nome(para)
				if cp == CELULA_INVALIDA:
					return "FALHOU: não existe ninguém chamado '%s'. %s" % [para, _lista_de_nomes()]
				dest = cp
			resultado = mover_objeto(nome_obj, dest)
			if resultado:
				return "OK: '%s' foi para (%d,%d)." % [nome_obj, dest.x, dest.y]
		"dar_item":
			var nome_obj2: String = _achar_objeto(alvo)
			if nome_obj2 == "":
				return "FALHOU: não existe o objeto '%s'. %s" % [alvo, _lista_de_objetos()]
			resultado = dar_item(nome_obj2, para)
			if resultado:
				return "OK: '%s' agora está com %s." % [nome_obj2, para]
		"soltar_item":
			var nome_obj3: String = _achar_objeto(alvo)
			if nome_obj3 == "":
				return "FALHOU: não existe o objeto '%s'. %s" % [alvo, _lista_de_objetos()]
			resultado = soltar_item(nome_obj3)
			if resultado:
				return "OK: '%s' foi solto no chão." % nome_obj3
		"mudar_estado":
			var nome_obj4: String = _achar_objeto(alvo)
			if nome_obj4 == "":
				return "FALHOU: não existe o objeto '%s'. %s" % [alvo, _lista_de_objetos()]
			resultado = mudar_estado(nome_obj4, estado)
			if resultado:
				return "OK: '%s' agora está '%s'." % [nome_obj4, estado]
		"remover_objeto":
			var nome_obj5: String = _achar_objeto(alvo)
			if nome_obj5 == "":
				return "FALHOU: não existe o objeto '%s'. %s" % [alvo, _lista_de_objetos()]
			resultado = remover_objeto(nome_obj5)
			if resultado:
				registrar_evento("objeto", "%s foi removido do mundo." % nome_obj5)
				return "OK: '%s' foi removido." % nome_obj5
		"construir":
			var lado: String = str(comando.get("lado", "sul")).to_lower()
			resultado = construir_predio(alvo, modelo, Vector2i(x, z), int(comando.get("largura", 5)), int(comando.get("profundidade", 4)), lado)
			if resultado:
				return "OK: '%s' construída; interior livre para mover personagens e colocar móveis." % alvo
		"gerar_construcao":
			var referencia: Vector2i = _resolver_referencia(para)
			var lista_extras: Array = []
			for e in comando.get("extras", []):
				lista_extras.append(str(e))
			var tamanho: String = str(comando.get("tamanho", "medio")).to_lower()
			_gerando = true              # móveis, tochas e portas da construção não viram eventos do diário
			var r: Dictionary = Gerador.gerar_predio(self, modelo, alvo, referencia, tamanho, lista_extras, randi())
			_gerando = false
			if bool(r["ok"]):
				registrar_evento("construcao", "Surgiu a construção %s (%s)." % [alvo, modelo])
				return "OK: " + str(r["resumo"])
			return "FALHOU: " + str(r["motivo"])
		"iniciar_combate":
			var motivo_combate: String = str(comando.get("texto", "")).strip_edges()
			resultado = iniciar_combate(motivo_combate, "mestre")
			if resultado:
				return "OK: combate iniciado. Motivo: %s. Ordem de iniciativa definida." % motivo_combate
		"encerrar_combate":
			resultado = encerrar_combate()
			if resultado:
				return "OK: combate encerrado."
		"atividade":
			var c3: Vector2i = _achar_por_nome(alvo)
			if c3 == CELULA_INVALIDA:
				return "FALHOU: não existe ninguém chamado '%s'. %s" % [alvo, _lista_de_nomes()]
			ficha_em(c3)["atividade"] = str(comando.get("texto", "")).strip_edges().left(60)
			return "OK: %s agora está: %s." % [ficha_em(c3)["nome"], ficha_em(c3)["atividade"]]
		"definir_altura":
			resultado = definir_altura(Vector2i(x, z), int(comando.get("nivel", 0)))
			if resultado:
				return "OK: altura de (%d,%d) mudou." % [x, z]
		_:
			return "FALHOU: ação desconhecida '%s'." % acao

	return "FALHOU: %s" % (ultimo_motivo if ultimo_motivo != "" else "não foi possível.")


# ===============================================================
# MUNDO: diário, propriedades dos itens, conhecimento dos NPCs, salvamento
# ===============================================================
func registrar_evento(tipo: String, texto: String) -> void:
	if not _registro_ativo or _construindo or _gerando:
		return
	mundo.registrar(tipo, texto)
	salvar_mundo()


# O que dá para fazer com um objeto (alimenta o menu de clique da etapa 2)
func verbos_do_objeto(nome_objeto: String) -> Array:
	if not objetos.has(nome_objeto):
		return []
	var obj: Dictionary = objetos[nome_objeto]
	var dados: Dictionary = CATALOGO_OBJETOS[str(obj["modelo"])]
	return mundo.verbos_de(str(obj["modelo"]), str(obj["estado"]), bool(obj.get("trancado", false)), dados)


func propriedades_do_objeto(nome_objeto: String) -> Dictionary:
	if not objetos.has(nome_objeto):
		return {}
	var obj: Dictionary = objetos[nome_objeto]
	return mundo.propriedades_de(str(obj["modelo"]), CATALOGO_OBJETOS[str(obj["modelo"])])


func trancar_objeto(nome_objeto: String, trancado: bool) -> bool:
	if not objetos.has(nome_objeto):
		_falhar("Não existe o objeto '%s'." % nome_objeto)
		return false
	var obj: Dictionary = objetos[nome_objeto]
	if not bool(propriedades_do_objeto(nome_objeto)["pode_trancar"]):
		_falhar("'%s' não tem tranca." % nome_objeto)
		return false
	if trancado and str(obj["estado"]) != "fechado":
		_falhar("'%s' precisa estar fechado para ser trancado." % nome_objeto)
		return false
	obj["trancado"] = trancado
	registrar_evento("objeto", "%s foi %s." % [nome_objeto, "trancado" if trancado else "destrancado"])
	return true


func descrever_npc(nome: String) -> String:
	var cel: Vector2i = _achar_por_nome(nome)
	if cel == CELULA_INVALIDA:
		return "Não existe ninguém chamado '%s'." % nome
	return mundo.descrever_npc(str(ficha_em(cel)["nome"]), ficha_em(cel))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		salvar_mundo()


func apagar_mundo() -> void:
	if FileAccess.file_exists(Mundo.ARQUIVO_MUNDO):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Mundo.ARQUIVO_MUNDO))


func salvar_mundo() -> void:
	if not _registro_ativo or _carregando or celula_jogador == CELULA_INVALIDA or fim_de_jogo:
		return
	var pers: Array = []
	for c in pecas.keys():
		var f: Dictionary = ficha_em(c)
		pers.append({"nome": str(f["nome"]), "modelo": str(f["modelo"]), "lado": str(f["lado"]), "classe": str(f["classe"]),
			"celula": c, "pv": int(f["pv"]), "intencao": str(f["intencao"]), "atividade": str(f.get("atividade", "")),
			"conhecimento": (f.get("conhecimento", {}) as Dictionary).duplicate(true)})
	var objs: Array = []
	for n in objetos.keys():
		var o: Dictionary = objetos[n]
		objs.append({"nome": str(n), "modelo": str(o["modelo"]), "celula": o["celula"], "estado": str(o["estado"]),
			"dono": str(o["dono"]), "trancado": bool(o.get("trancado", false)), "predio": str(o.get("predio", ""))})
	var preds: Array = []
	for n in predios.keys():
		var p: Dictionary = predios[n]
		var lados_extras: Array = []
		for i in range(1, (p["portas"] as Array).size()):
			lados_extras.append(str(p["portas"][i]["lado"]))
		preds.append({"nome": str(n), "modelo": str(p["modelo"]), "canto": Vector2i(int(p["x0"]), int(p["z0"])),
			"largura": int(p["x1"]) - int(p["x0"]) + 1, "profundidade": int(p["z1"]) - int(p["z0"]) + 1,
			"lado_porta": str(p["lado_porta"]), "extras": lados_extras, "recursos": (p["recursos"] as Array).duplicate()})
	var dados: Dictionary = {"versao": 1, "mundo": mundo.para_salvar(), "personagens": pers, "objetos": objs,
		"predios": preds, "alturas": alturas.duplicate()}
	var f := FileAccess.open(Mundo.ARQUIVO_MUNDO, FileAccess.WRITE)
	if f != null:
		f.store_string(var_to_str(dados))


# Reconstrói o estado salvo POR CIMA do cenário inicial já montado
func carregar_mundo() -> void:
	if not FileAccess.file_exists(Mundo.ARQUIVO_MUNDO):
		return
	var dados: Variant = str_to_var(FileAccess.get_file_as_string(Mundo.ARQUIVO_MUNDO))
	if not (dados is Dictionary) or int(dados.get("versao", 0)) != 1:
		return
	_carregando = true

	# 1) construções
	var salvos_pred: Dictionary = {}
	for p in dados.get("predios", []):
		salvos_pred[str(p["nome"])] = p
	for n in predios.keys():
		if not salvos_pred.has(n):
			demolir_predio(str(n))
	for n in salvos_pred.keys():
		if not predios.has(n):
			var sp: Dictionary = salvos_pred[n]
			construir_predio(str(n), str(sp["modelo"]), sp["canto"], int(sp["largura"]), int(sp["profundidade"]), str(sp["lado_porta"]), sp["extras"])
		if predios.has(n):
			predios[n]["recursos"] = (salvos_pred[n]["recursos"] as Array).duplicate()

	# 2) alturas do terreno
	var salvas_alt: Dictionary = dados.get("alturas", {})
	for c in alturas.keys():
		if not salvas_alt.has(c):
			definir_altura(c, 0)
	for c in salvas_alt.keys():
		if int(alturas.get(c, 0)) != int(salvas_alt[c]):
			definir_altura(c, int(salvas_alt[c]))

	# 3) objetos que não existem mais
	var salvos_obj: Dictionary = {}
	for o in dados.get("objetos", []):
		salvos_obj[str(o["nome"])] = o
	for n in objetos.keys():
		if not salvos_obj.has(n):
			remover_objeto(str(n))

	# 4) personagens: reposiciona os que existem, remove os que morreram, cria os novos
	var salvos_pers: Dictionary = {}
	for pr in dados.get("personagens", []):
		salvos_pers[str(pr["nome"])] = pr
	var existentes: Dictionary = {}
	for c in pecas.keys():
		existentes[str(ficha_em(c)["nome"])] = pecas[c]
	pecas.clear()
	for nome in existentes.keys():
		var peca: Node3D = existentes[nome]
		if not salvos_pers.has(nome):
			peca.queue_free()
			continue
		var sv: Dictionary = salvos_pers[nome]
		pecas[sv["celula"]] = peca
		peca.position = _pos_peca(sv["celula"])
		_aplicar_ficha_salva(peca.get_meta("ficha"), sv)
		_atualizar_etiqueta(peca)
		if str(sv["lado"]) == "jogador":
			celula_jogador = sv["celula"]
	for nome in salvos_pers.keys():
		if existentes.has(nome):
			continue
		var sv2: Dictionary = salvos_pers[nome]
		if colocar_personagem(sv2["celula"], str(nome), str(sv2["modelo"]), str(sv2["lado"]), str(sv2["classe"])):
			var ce: Vector2i = sv2["celula"]
			_aplicar_ficha_salva(ficha_em(ce), sv2)
			_atualizar_etiqueta(pecas[ce])
	for c in pecas.keys():
		(ficha_em(c)["inventario"] as Array).clear()

	# 5) objetos: cria os novos e aplica posição, estado, dono
	for n in salvos_obj.keys():
		var so: Dictionary = salvos_obj[n]
		if not objetos.has(n):
			if not criar_objeto(str(n), str(so["modelo"]), so["celula"]):
				continue
		var obj: Dictionary = objetos[n]
		obj["celula"] = so["celula"]
		obj["trancado"] = bool(so.get("trancado", false))
		if str(so.get("predio", "")) != "":
			obj["predio"] = str(so["predio"])
		obj["estado"] = str(so["estado"])
		obj["dono"] = ""
		var dono: String = str(so["dono"])
		if dono != "":
			var dc: Vector2i = _achar_exato(dono)
			if dc != CELULA_INVALIDA:
				obj["dono"] = dono
				(ficha_em(dc)["inventario"] as Array).append(str(n))
		_posicionar_objeto(obj)
		_aplicar_estado_visual(obj)

	mundo.carregar_de(dados.get("mundo", {}))
	modo = "exploracao"
	_recalcular_obstaculos()
	_atualizar_destaques()
	_atualizar_interface()
	_notificar_personagens()
	_carregando = false
	print("Mundo carregado: ", pecas.size(), " personagens, ", objetos.size(), " objetos, ", mundo.diario.size(), " eventos no diário.")


func _aplicar_ficha_salva(ficha: Dictionary, sv: Dictionary) -> void:
	ficha["pv"] = mini(int(sv["pv"]), int(ficha["pv_max"]))
	ficha["intencao"] = str(sv.get("intencao", "padrao"))
	ficha["atividade"] = str(sv.get("atividade", ""))
	if not (sv.get("conhecimento", {}) as Dictionary).is_empty():
		ficha["conhecimento"] = (sv["conhecimento"] as Dictionary).duplicate(true)


# Versão simples (true/false) para os atalhos de teclado
func executar_comando(comando: Dictionary) -> bool:
	return executar_comando_mestre(comando).begins_with("OK")


func _lista_de_nomes() -> String:
	var nomes: Array = []
	for c in pecas.keys():
		nomes.append(str(ficha_em(c).get("nome", "?")))
	return "Personagens existentes: " + ", ".join(nomes) + "."


func _lista_de_objetos() -> String:
	if objetos.is_empty():
		return "Não há objetos no tabuleiro."
	return "Objetos existentes: " + ", ".join(objetos.keys()) + "."


# Entende "Kuzin", "Poço", "Taverna Javali Dourado" ou vazio (= perto do jogador)
func _resolver_referencia(texto: String) -> Vector2i:
	var t: String = texto.strip_edges()
	if t != "":
		var cp: Vector2i = _achar_por_nome(t)
		if cp != CELULA_INVALIDA:
			return cp
		var no: String = _achar_objeto(t)
		if no != "":
			return objetos[no]["celula"]
		for n in predios.keys():
			if str(n).to_lower().contains(t.to_lower()):
				var pr: Dictionary = predios[n]
				return Vector2i((int(pr["x0"]) + int(pr["x1"])) / 2, (int(pr["z0"]) + int(pr["z1"])) / 2)
	if celula_jogador != CELULA_INVALIDA:
		return celula_jogador
	return Vector2i(largura_tabuleiro / 2, profundidade_tabuleiro / 2)


# ---------------------------------------------------------------
# COERÊNCIA: o Mestre só pode falar do que EXISTE
# ---------------------------------------------------------------
# Coisas que o modelo de texto costuma inventar. Se a narração citar uma delas e ela NÃO existe
# no tabuleiro, o Mestre é obrigado a reescrever (ver mestre_ia.gd).
const TERMOS_DE_CENARIO: Array[String] = ["alcapao", "escada", "janela", "porao", "adega", "sotao", "andar de cima", "segundo andar",
	"chamine", "estatua", "altar", "espelho", "quadro", "tapete", "cortina", "vitral", "ponte", "rio", "lago", "fonte", "portao",
	"armadilha", "cofre", "alavanca", "cama", "estante", "lustre", "candelabro", "palco", "lareira", "balcao", "barril", "mesa",
	"cadeira", "bau", "tocha", "poco", "fogueira", "arvore", "cerca", "porta dos fundos", "porta lateral", "banco", "caixote"]

# Recursos que a descrição lista como "NÃO possui" quando faltam (rótulo, palavras que provam que existe)
const RECURSOS_VERIFICAVEIS: Array = [["alçapão", "alcapao"], ["escada", "escada"], ["janelas", "janela"], ["porão ou adega", "porao|adega"],
	["segundo andar", "segundo andar|andar de cima"], ["chaminé", "chamine"], ["palco", "palco"], ["lareira", "lareira"], ["porta dos fundos", "porta dos fundos"]]


# ---------------------------------------------------------------
# MOVIMENTO DO JOGADOR POR TEXTO (feito pelo JOGO, não pela IA)
# "vou até a bancada", "me aproximo do Barnaby", "entro na casa"...
# O jogo acha o alvo, calcula o caminho, move o Kuzin e devolve um FATO verdadeiro para o Mestre narrar.
# ---------------------------------------------------------------
const GATILHOS_DE_MOVIMENTO: Array[String] = ["aproxim", "chego", "dirij", "caminho", "corro", "entro", "saio", "me posiciono",
	"vou ate", "vou para", "vou pra", "vou a ", "vou ao", "vou na", "vou no", "vou em", "indo ate", "ir ate", "ir para", "ir pra",
	"quero ir", "vamos ate", "me movo", "me mexo", "ando ate", "ando ao", "ando para", "chegar perto", "ficar perto", "me afasto de"]
const PALAVRAS_IGNORADAS: Array[String] = ["de", "do", "da", "dos", "das", "dourado", "javali"]


func _alvos_de_movimento() -> Array:
	var lista: Array = []
	for c in pecas.keys():
		if c == celula_jogador:
			continue
		lista.append({"nome": str(ficha_em(c)["nome"]), "busca": str(ficha_em(c)["nome"]), "celula": c, "tipo": "personagem"})
	for n in objetos.keys():
		if str(objetos[n]["modelo"]) == "parede":
			continue
		var busca: String = str(n)
		for pn in predios.keys():
			busca = busca.replace(" de " + str(pn), "")     # "Porta de Taverna X" -> "Porta"
		lista.append({"nome": str(n), "busca": busca, "celula": objetos[n]["celula"], "tipo": "objeto"})
	for n in predios.keys():
		lista.append({"nome": str(n), "busca": str(n), "celula": CELULA_INVALIDA, "tipo": "predio"})
	return lista


# Variantes pelas quais o jogador pode citar o alvo (nome inteiro e cada palavra grande)
func _variantes_do_nome(nome: String) -> Array:
	var n: String = _normalizar(nome)
	var v: Array = [n]
	for tok in n.split(" "):
		if tok.length() >= 4 and not PALAVRAS_IGNORADAS.has(tok) and not tok.is_valid_int():
			v.append(tok)
	return v


# Devolve "" se o texto não é um pedido de movimento; senão devolve o FATO (sucesso ou falha) já executado.
func interpretar_movimento(texto: String) -> String:
	var t: String = " " + _normalizar(texto) + " "
	var gatilho: bool = false
	for g in GATILHOS_DE_MOVIMENTO:
		if t.contains(g):
			gatilho = true
			break
	if not gatilho or celula_jogador == CELULA_INVALIDA:
		return ""
	# acha o alvo citado primeiro
	var melhor_pos: int = 9999
	var melhor_var: String = ""
	for a in _alvos_de_movimento():
		for v in _variantes_do_nome(a["busca"]):
			var pos: int = t.find(v)
			if pos >= 0 and (pos < melhor_pos or (pos == melhor_pos and v.length() > melhor_var.length())):
				melhor_pos = pos
				melhor_var = v
	if melhor_var == "":
		return ""
	# entre os que têm essa palavra, fica com o mais perto de Kuzin
	var escolhido: Dictionary = {}
	var melhor_d: int = 9999
	for a in _alvos_de_movimento():
		if not _variantes_do_nome(a["busca"]).has(melhor_var):
			continue
		var cel: Vector2i = a["celula"]
		if a["tipo"] == "predio":
			var pr: Dictionary = predios[a["nome"]]
			cel = Vector2i((int(pr["x0"]) + int(pr["x1"])) / 2, (int(pr["z0"]) + int(pr["z1"])) / 2)
		var d: int = distancia(celula_jogador, cel)
		if a["tipo"] != "predio" and predio_em(cel) != predio_em(celula_jogador):
			d += 15          # prefere o que está no mesmo lugar (dentro/fora) que Kuzin
		if d < melhor_d:
			melhor_d = d
			escolhido = a.duplicate()
			escolhido["celula"] = cel
	if escolhido.is_empty():
		return ""
	var nome_kuzin: String = str(ficha_em(celula_jogador)["nome"])
	if modo == "combate":
		return "FATO DO JOGO: estamos em combate; Kuzin só se move no próprio turno, clicando no tabuleiro. NADA foi movido."
	var alvo_cel: Vector2i = escolhido["celula"]
	var destinos: Array = []
	if escolhido["tipo"] == "predio":
		var pr2: Dictionary = predios[escolhido["nome"]]
		var dentro_agora: bool = predio_em(celula_jogador) == escolhido["nome"]
		var porta_c: Vector2i = pr2["porta"]
		var fora_c: Vector2i = pr2["fora"]
		var dentro_c: Vector2i = porta_c + (porta_c - fora_c)
		var quer_sair: bool = t.contains(" saio") or t.contains(" sair") or t.contains(" saindo")
		destinos.append(fora_c if (quer_sair or (dentro_agora and not t.contains(" entro"))) else dentro_c)
	var previos: Dictionary = {}
	var alcance: Dictionary = _dijkstra(celula_jogador, LIMITE_EXPLORACAO, true, previos)
	var destino: Vector2i = CELULA_INVALIDA
	if escolhido["tipo"] == "predio":
		for d2 in destinos:
			if alcance.has(d2) and not celula_ocupada(d2):
				destino = d2
		if destino == CELULA_INVALIDA:
			# tenta qualquer célula livre alcançável perto da porta
			var melhor_c: int = 9999
			for c in alcance.keys():
				if celula_ocupada(c):
					continue
				var dd: int = distancia(c, destinos[0])
				if dd <= 1 and int(alcance[c]) < melhor_c:
					melhor_c = int(alcance[c])
					destino = c
	else:
		var melhor_custo: int = 9999
		for raio in [1, 2]:
			for c in alcance.keys():
				if celula_ocupada(c) and c != celula_jogador:
					continue
				if distancia(c, alvo_cel) != raio:
					continue
				if int(alcance[c]) < melhor_custo:
					melhor_custo = int(alcance[c])
					destino = c
			if destino != CELULA_INVALIDA:
				break
	if destino == CELULA_INVALIDA:
		return "FATO DO JOGO: %s tentou ir até %s mas NÃO conseguiu (caminho bloqueado ou longe demais, mais de %d passos). Kuzin continua onde estava." % [nome_kuzin, escolhido["nome"], LIMITE_EXPLORACAO]
	if destino == celula_jogador:
		return "FATO DO JOGO: %s já estava ao lado de %s. Não precisou andar." % [nome_kuzin, escolhido["nome"]]
	var passos: int = int(alcance[destino])
	if not mover_peca(celula_jogador, destino, _reconstruir_caminho(previos, celula_jogador, destino)):
		return "FATO DO JOGO: %s tentou ir até %s mas não conseguiu andar. Kuzin continua onde estava." % [nome_kuzin, escolhido["nome"]]
	if escolhido["tipo"] == "predio":
		return "FATO DO JOGO: %s andou %d passos e agora está %s." % [nome_kuzin, passos, lugar_texto(celula_jogador)]
	return "FATO DO JOGO: %s andou %d passos e agora está ao lado de %s (%s)." % [nome_kuzin, passos, escolhido["nome"], lugar_texto(celula_jogador)]


func _normalizar(texto: String) -> String:
	var t: String = texto.to_lower()
	var mapa: Dictionary = {"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a", "é": "e", "è": "e", "ê": "e", "ë": "e", "í": "i", "ì": "i", "î": "i",
		"ï": "i", "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o", "ú": "u", "ù": "u", "û": "u", "ü": "u", "ç": "c"}
	for k in mapa.keys():
		t = t.replace(k, mapa[k])
	return t


# Tudo o que existe na cena, em texto normalizado (nomes, modelos, recursos das construções)
func _universo_de_termos(somente_predio: String = "") -> String:
	var partes: Array = []
	for n in objetos.keys():
		if somente_predio != "" and str(objetos[n].get("predio", "")) != somente_predio and predio_em(objetos[n]["celula"]) != somente_predio:
			continue
		partes.append(str(n))
		partes.append(str(objetos[n]["modelo"]))
	for n in predios.keys():
		if somente_predio != "" and str(n) != somente_predio:
			continue
		partes.append(str(n))
		for r in predios[n]["recursos"]:
			partes.append(str(r))
		for porta in predios[n]["portas"]:
			partes.append(str(porta["rotulo"]))
	return _normalizar(" | ".join(partes))


# Palavras que indicam contato/proximidade física com Kuzin
const FRASES_DE_PROXIMIDADE: Array[String] = ["sussurr", "cochich", "ao seu lado", "ao lado de voce", "do seu lado", "no seu ouvido",
	"sua orelha", "se inclina", "te entrega", "lhe entrega", "senta ao lado", "sentado ao lado", "sentada ao lado", "ao lado do", "ao lado da"]


# Analisa a narração frase por frase: [{frase, problema}]
func _analisar_frases(texto: String) -> Array:
	var resultado: Array = []
	var rx := RegEx.new()
	rx.compile("[^.!?\\n]+[.!?]*")
	var vago := RegEx.new()
	vago.compile("(sussurr|murmur|cochich|disse|diz|fal)\\w*\\s+(algo|alguma coisa|qualquer coisa)")
	for m in rx.search_all(texto):
		var frase: String = m.get_string().strip_edges()
		if frase == "":
			continue
		var n: String = _normalizar(frase)
		var inexistentes: Array = termos_inexistentes(frase)
		if not inexistentes.is_empty():
			resultado.append({"frase": frase, "problema": "cita coisas que NÃO existem na cena: " + ", ".join(inexistentes)})
			continue
		if vago.search(n) != null:
			resultado.append({"frase": frase, "problema": "alguém fala/sussurra 'algo' sem dizer o quê: escreva a fala entre aspas ou não faça o personagem falar"})
			continue
		if celula_jogador != CELULA_INVALIDA:
			var motivo_prox: String = ""
			for c in pecas.keys():
				if c == celula_jogador:
					continue
				var d: int = distancia(celula_jogador, c)
				if d <= 2:
					continue
				var nome_n: String = _normalizar(str(ficha_em(c)["nome"]))
				var citado: bool = false
				for token in nome_n.split(" "):
					if token.length() >= 5 and n.contains(token):
						citado = true
				if not citado:
					continue
				for chave in FRASES_DE_PROXIMIDADE:
					if n.contains(chave):
						motivo_prox = "%s está %s; longe demais para isso. Se a cena exige, primeiro mova-o até perto de Kuzin (comando mover) ou narre de outra forma" % [ficha_em(c)["nome"], _palavra_de_distancia(d)]
						break
				if motivo_prox != "":
					break
			if motivo_prox != "":
				resultado.append({"frase": frase, "problema": motivo_prox})
	return resultado


func problemas_de_narracao(texto: String) -> Array:
	var lista: Array = []
	for r in _analisar_frases(texto):
		var msg: String = "'%s' -> %s" % [str(r["frase"]).left(90), r["problema"]]
		if not lista.has(msg):
			lista.append(msg)
	return lista


# Último recurso: remove as frases problemáticas (se sobrar alguma coisa)
func limpar_narracao(texto: String) -> String:
	var ruins: Array = []
	for r in _analisar_frases(texto):
		ruins.append(str(r["frase"]))
	if ruins.is_empty():
		return texto
	var rx := RegEx.new()
	rx.compile("[^.!?\\n]+[.!?]*")
	var boas: Array = []
	for m in rx.search_all(texto):
		var frase: String = m.get_string().strip_edges()
		if frase != "" and not ruins.has(frase):
			boas.append(frase)
	if boas.is_empty():
		return texto
	return " ".join(boas)


# Termos citados no texto que NÃO existem no tabuleiro
func termos_inexistentes(texto: String) -> Array:
	var universo: String = _universo_de_termos()
	var t: String = _normalizar(texto)
	var achados: Array = []
	for termo in TERMOS_DE_CENARIO:
		if universo.contains(termo):
			continue
		var rx := RegEx.new()
		rx.compile("\\b" + termo + "(s|es)?\\b")
		var m: RegExMatch = rx.search(t)
		if m == null:
			continue
		var antes: String = t.substr(maxi(m.get_start() - 25, 0), mini(m.get_start(), 25))
		if antes.contains("nao ") or antes.contains("sem ") or antes.contains("nenhum") or antes.contains("nada de"):
			continue
		achados.append(termo)
	return achados


# Texto que o Mestre IA lê para "enxergar" o tabuleiro
func descrever_tabuleiro() -> String:
	var t: String = "TABULEIRO %dx%d (x = 0 a %d: oeste->leste; z = 0 a %d: norte->sul).\n" % [
		largura_tabuleiro, profundidade_tabuleiro, largura_tabuleiro - 1, profundidade_tabuleiro - 1]
	if modo == "combate":
		t += "MODO: COMBATE, rodada %d, turno de %s. Ordem: %s. (Em combate o jogador move e ataca sozinho; NPCs agem pela IA tática.)\n" % [rodada, ator_atual, " > ".join(ordem_iniciativa)]
	else:
		t += "MODO: EXPLORAÇÃO (sem turnos). Se Kuzin quer ir a algum lugar, mova-o com a ação mover (alvo Kuzin) para uma célula LIVRE perto do destino. Se começa uma luta, use iniciar_combate.\n"
	var jog: Vector2i = celula_jogador
	t += "PERSONAGENS:\n"
	for c in pecas.keys():
		var f: Dictionary = ficha_em(c)
		t += "- %s [%s] em (%d,%d) (%s), PV %d/%d, CA %d" % [f["nome"], f["lado"], c.x, c.y, lugar_texto(c), f["pv"], f["pv_max"], f["ca"]]
		if str(f["lado"]) != "jogador":
			t += ", comportamento %s, intenção %s" % [f["arquetipo"], f["intencao"]]
			if jog != CELULA_INVALIDA:
				t += ", em relação a Kuzin: " + _direcao_texto(jog, c)
		if str(f.get("atividade", "")) != "":
			t += ", fazendo: " + str(f["atividade"])
		var inv: Array = f["inventario"]
		if not inv.is_empty():
			t += ", carrega: " + ", ".join(inv)
		t += "\n"
	t += proximidade_texto()
	if not predios.is_empty():
		t += "CONSTRUÇÕES (paredes de blocos; só dá para entrar/sair pelas portas listadas). SÓ MENCIONE O QUE ESTÁ LISTADO; o que consta em NÃO possui NÃO EXISTE:\n"
		for n in predios.keys():
			var pr: Dictionary = predios[n]
			t += "- %s (%s): interior x %d a %d, z %d a %d\n" % [n, pr["modelo"], int(pr["x0"]) + 1, int(pr["x1"]) - 1, int(pr["z0"]) + 1, int(pr["z1"]) - 1]
			for porta in pr["portas"]:
				t += "    * %s no lado %s, em (%d,%d), saída para (%d,%d)\n" % [porta["rotulo"], porta["lado"], porta["celula"].x, porta["celula"].y, porta["fora"].x, porta["fora"].y]
			if not (pr["recursos"] as Array).is_empty():
				t += "    * contém: " + ", ".join(pr["recursos"]) + "\n"
			var dentro_nomes: Array = []
			for on in objetos.keys():
				var om: String = str(objetos[on]["modelo"])
				if om != "parede" and om != "porta" and predio_em(objetos[on]["celula"]) == str(n):
					dentro_nomes.append(str(on))
			if not dentro_nomes.is_empty():
				t += "    * objetos dentro: " + ", ".join(dentro_nomes) + "\n"
			var universo: String = _universo_de_termos(str(n))
			var faltando: Array = []
			for rv in RECURSOS_VERIFICAVEIS:
				var tem: bool = false
				for chave in str(rv[1]).split("|"):
					if universo.contains(chave):
						tem = true
				if not tem:
					faltando.append(rv[0])
			if not faltando.is_empty():
				t += "    * NÃO possui: " + ", ".join(faltando) + "\n"
	var lista_obj: String = ""
	for n in objetos.keys():
		var o: Dictionary = objetos[n]
		if str(o["modelo"]) == "parede" or str(o["modelo"]) == "muro" or str(o["modelo"]) == "porta":
			continue
		var onde: String = "com %s" % o["dono"] if str(o["dono"]) != "" else "em (%d,%d)" % [o["celula"].x, o["celula"].y]
		lista_obj += "- %s (%s, %s) %s\n" % [n, o["modelo"], o["estado"], onde]
	if lista_obj != "":
		t += "OBJETOS:\n" + lista_obj
	t += mundo.diario_para_ia()
	if not alturas.is_empty():
		var partes: Array = []
		for c in alturas.keys():
			partes.append("(%d,%d)=nível %d" % [c.x, c.y, alturas[c]])
		t += "TERRENO ELEVADO: " + ", ".join(partes) + "\n"
	return t


# Frases prontas de distância em relação ao Kuzin (o Mestre NÃO deve inventar distâncias)
func _palavra_de_distancia(d: int) -> String:
	if d <= 1:
		return "ao lado de Kuzin (dá para sussurrar e tocar)"
	if d <= 3:
		return "bem perto de Kuzin (conversa em voz normal)"
	if d <= 7:
		return "a alguns passos de Kuzin (precisa falar mais alto)"
	return "longe de Kuzin (só gritando; fora do alcance da voz)"


func proximidade_texto() -> String:
	if celula_jogador == CELULA_INVALIDA:
		return ""
	var t: String = "PROXIMIDADE DE KUZIN (já calculada pelo jogo; NÃO invente distâncias nem posições):\n"
	t += "- Kuzin está %s.\n" % lugar_texto(celula_jogador)
	for c in pecas.keys():
		if c == celula_jogador:
			continue
		var f: Dictionary = ficha_em(c)
		t += "- %s: %s.\n" % [f["nome"], _palavra_de_distancia(distancia(celula_jogador, c))]
	return t


# "3 células a leste e 2 ao sul"  (norte = topo do mapa, z menor; leste = direita, x maior)
func _direcao_texto(de: Vector2i, para: Vector2i) -> String:
	var dx: int = para.x - de.x
	var dz: int = para.y - de.y
	if dx == 0 and dz == 0:
		return "na mesma célula"
	var partes: Array = []
	if dx != 0:
		partes.append("%d a %s" % [absi(dx), "leste" if dx > 0 else "oeste"])
	if dz != 0:
		partes.append("%d ao %s" % [absi(dz), "sul" if dz > 0 else "norte"])
	return " e ".join(partes) + " (distância %d)" % distancia(de, para)


func _regiao(celula: Vector2i) -> String:
	var h: String = "esquerdo"
	if celula.x * 3 >= largura_tabuleiro * 2:
		h = "direito"
	elif celula.x * 3 >= largura_tabuleiro:
		h = "centro"
	var v: String = "superior"
	if celula.y * 3 >= profundidade_tabuleiro * 2:
		v = "inferior"
	elif celula.y * 3 >= profundidade_tabuleiro:
		v = "meio"
	if v == "meio" and h == "centro":
		return "centro do mapa"
	if v == "meio":
		return "lado " + h
	if h == "centro":
		return "parte " + v
	return "canto %s %s" % [v, h]


# Resumo curto para o jogador (comando /onde): onde está e quem está perto, em linguagem natural
func resumo_da_cena() -> String:
	if celula_jogador == CELULA_INVALIDA:
		return "Seu personagem não está no tabuleiro."
	var f: Dictionary = ficha_em(celula_jogador)
	var t: String = "%s está %s." % [f["nome"], lugar_texto(celula_jogador)]
	var ao_lado: Array = []
	var perto: Array = []
	var longe: Array = []
	for c in pecas.keys():
		if c == celula_jogador:
			continue
		var g: Dictionary = ficha_em(c)
		var d: int = distancia(celula_jogador, c)
		var item: String = "%s (%s)" % [g["nome"], {"aliado": "aliado", "inimigo": "inimigo", "neutro": "neutro"}.get(str(g["lado"]), "")]
		if d <= 1:
			ao_lado.append(item)
		elif d <= 4:
			perto.append(item)
		else:
			longe.append(item)
	if not ao_lado.is_empty():
		t += " Ao seu lado: " + ", ".join(ao_lado) + "."
	if not perto.is_empty():
		t += " Por perto: " + ", ".join(perto) + "."
	if not longe.is_empty():
		t += " Mais longe: " + ", ".join(longe) + "."
	if not (f["inventario"] as Array).is_empty():
		t += " Você carrega: " + ", ".join(f["inventario"]) + "."
	return t


# Descrição de UMA célula (para o cursor)
func descrever_celula(celula: Vector2i) -> String:
	var t: String = "Cursor (%d,%d)" % [celula.x, celula.y]
	if altura_de(celula) > 0:
		t += " terreno nível %d" % altura_de(celula)
	if pecas.has(celula):
		var f: Dictionary = ficha_em(celula)
		t += ": %s [%s] PV %d/%d CA %d" % [f["nome"], f["lado"], f["pv"], f["pv_max"], f["ca"]]
		if str(f["lado"]) != "jogador":
			t += " (%s)" % f["arquetipo"]
		if str(f.get("atividade", "")) != "":
			t += ", " + str(f["atividade"])
	for n in _objetos_na_celula(celula):
		t += ": %s (%s, %s)" % [n, objetos[n]["modelo"], objetos[n]["estado"]]
	return t


# ===============================================================
# CAMADA 1: ENTRADA
# ===============================================================

# Controles do chat/UI que não devem "vazar" cliques e roda do mouse para o tabuleiro
func _controle_de_interface(controle: Control) -> bool:
	if controle == null:
		return false
	if controle is BaseButton or controle is RichTextLabel or controle is TextEdit or controle is LineEdit or controle is ScrollContainer:
		return true
	return interface != null and interface.is_ancestor_of(controle)


# A roda do mouse só NÃO dá zoom quando está sobre o chat ou um botão
func _roda_pertence_a_interface(controle: Control) -> bool:
	return controle is RichTextLabel or controle is TextEdit or controle is LineEdit or controle is BaseButton or controle is ScrollContainer


func _input(event: InputEvent) -> void:
	var controle: Control = get_viewport().gui_get_hovered_control()

	var movimento := event as InputEventMouseMotion
	if movimento != null:
		var botao_meio := (movimento.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0
		var alt_com_esquerdo := Input.is_key_pressed(KEY_ALT) and (movimento.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if camera != null and (botao_meio or alt_com_esquerdo):
			if movimento.shift_pressed:
				var fator := camera_distancia * 0.0015
				_deslocar_camera(-movimento.relative.x * fator, movimento.relative.y * fator)
			else:
				camera_yaw -= movimento.relative.x * SENSIBILIDADE_MOUSE
				camera_pitch += movimento.relative.y * SENSIBILIDADE_MOUSE
				_atualizar_camera()
		return

	var clique := event as InputEventMouseButton
	if clique == null or not clique.pressed:
		return

	# Clicou FORA da caixa de texto? Então ela solta o teclado (WASD, Q, E... voltam a mexer a câmera)
	if clique.button_index == MOUSE_BUTTON_LEFT or clique.button_index == MOUSE_BUTTON_RIGHT or clique.button_index == MOUSE_BUTTON_MIDDLE:
		var foco := get_viewport().gui_get_focus_owner()
		if (foco is TextEdit or foco is LineEdit) and controle != foco:
			foco.release_focus()

	if clique.button_index == MOUSE_BUTTON_WHEEL_UP:
		if not _roda_pertence_a_interface(controle):
			_zoom_camera(ZOOM_RODA)
		return
	if clique.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not _roda_pertence_a_interface(controle):
			_zoom_camera(1.0 / ZOOM_RODA)
		return

	if clique.button_index != MOUSE_BUTTON_LEFT and clique.button_index != MOUSE_BUTTON_RIGHT:
		return
	if Input.is_key_pressed(KEY_ALT):
		return
	if _controle_de_interface(controle):
		return

	var celula := celula_sob_mouse(clique.position)
	if not celula_valida(celula):
		return

	cursor_celula = celula
	_atualizar_marcador()
	if clique.button_index == MOUSE_BUTTON_LEFT:
		# Clique em inimigo = atacar; clique em célula livre = andar
		if celula_ocupada(celula) and celula != celula_jogador:
			jogador_atacar(celula)
		else:
			mover_jogador(celula)
	else:
		remover_personagem_ia(celula)


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return

	match tecla.keycode:
		KEY_UP:
			_mover_cursor(Vector2i(0, -1))
		KEY_DOWN:
			_mover_cursor(Vector2i(0, 1))
		KEY_LEFT:
			_mover_cursor(Vector2i(-1, 0))
		KEY_RIGHT:
			_mover_cursor(Vector2i(1, 0))

		KEY_ENTER, KEY_KP_ENTER:
			if celula_ocupada(cursor_celula) and cursor_celula != celula_jogador:
				jogador_atacar(cursor_celula)
			else:
				mover_jogador(cursor_celula)
		KEY_SPACE:
			encerrar_turno()

		# ----- ferramentas de teste -----
		KEY_N:
			var modelo: String = MODELOS_PARA_TESTE[indice_modelo_teste % MODELOS_PARA_TESTE.size()]
			indice_modelo_teste += 1
			executar_comando({"acao": "colocar", "alvo": modelo.capitalize(), "modelo": modelo, "papel": "inimigo", "x": cursor_celula.x, "z": cursor_celula.y})
		KEY_O:
			executar_comando({"acao": "criar_objeto", "alvo": "Pedra", "modelo": "pedra", "x": cursor_celula.x, "z": cursor_celula.y})
		KEY_H:
			definir_altura(cursor_celula, (altura_de(cursor_celula) + 1) % (NIVEL_MAXIMO + 1))
		KEY_B:
			debug_ativo = not debug_ativo
			if not debug_ativo:
				_limpar_debug()
			_mostrar_aviso("Notas da IA: %s" % ("LIGADAS" if debug_ativo else "desligadas"))
		KEY_J:
			_demo_do_pao()
		KEY_K:
			if modo == "combate":
				encerrar_combate()
			else:
				iniciar_combate()
		KEY_F1:
			legenda_visivel = not legenda_visivel
			_atualizar_interface()
		KEY_F2:
			movimento_livre = not movimento_livre
			_mostrar_aviso("Andar livre fora de combate (TESTE): %s" % ("LIGADO" if movimento_livre else "desligado"))
			_atualizar_destaques()
		KEY_ESCAPE:
			var foco2 := get_viewport().gui_get_focus_owner()
			if foco2 != null:
				foco2.release_focus()
		KEY_DELETE, KEY_BACKSPACE:
			remover_personagem_ia(cursor_celula)
		KEY_C:
			_enquadrar_camera()                 # centraliza em você
		KEY_HOME:
			_enquadrar_camera(true)             # mostra o mapa inteiro
		KEY_F9:
			apagar_mundo()                      # F9 = recomeçar do zero (apaga o jogo salvo)
			get_tree().reload_current_scene()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			executar_comando({"acao": "redimensionar"}) if false else redimensionar_tabuleiro(largura_tabuleiro + 1, profundidade_tabuleiro + 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			redimensionar_tabuleiro(largura_tabuleiro - 1, profundidade_tabuleiro - 1)


# Demonstração do mundo interativo: "o pão sai da cabana e vai até o personagem"
func _demo_do_pao() -> void:
	var origem: Vector2i = Vector2i(2, 6)
	if predios.has("Casa do Padeiro"):
		origem = predios["Casa do Padeiro"]["fora"]
	var nome_pao: String = "Pão quente"
	if objetos.has(nome_pao):
		remover_objeto(nome_pao)
	var passos: Array = [
		{"acao": "criar_objeto", "alvo": nome_pao, "modelo": "pao", "x": origem.x, "z": origem.y},
		{"acao": "mover_objeto", "alvo": nome_pao, "para": "Kuzin"},
		{"acao": "dar_item", "alvo": nome_pao, "para": "Kuzin"},
	]
	for passo in passos:
		var r: String = executar_comando_mestre(passo)
		log_de_combate.emit("[demo] " + r)
		print("[demo] ", r)
		await get_tree().create_timer(0.8).timeout


# ===============================================================
# INTERFACE
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

	botao_distancia = Button.new()
	botao_distancia.focus_mode = Control.FOCUS_NONE
	botao_distancia.pressed.connect(_ao_clicar_distancia)
	linha.add_child(botao_distancia)

	botao_turno = Button.new()
	botao_turno.text = "Encerrar turno (Espaço)"
	botao_turno.focus_mode = Control.FOCUS_NONE
	botao_turno.pressed.connect(encerrar_turno)
	linha.add_child(botao_turno)

	botao_combate = Button.new()
	botao_combate.focus_mode = Control.FOCUS_NONE
	botao_combate.pressed.connect(func() -> void:
		if modo == "combate":
			encerrar_combate()
		else:
			iniciar_combate())
	linha.add_child(botao_combate)

	rotulo_cursor = Label.new()
	rotulo_cursor.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	caixa.add_child(rotulo_cursor)

	rotulo_legenda = Label.new()
	rotulo_legenda.add_theme_font_size_override("font_size", 13)
	rotulo_legenda.text = LEGENDA
	caixa.add_child(rotulo_legenda)

	rotulo_debug = Label.new()
	rotulo_debug.add_theme_color_override("font_color", Color(0.5, 1.0, 1.0))
	rotulo_debug.custom_minimum_size = Vector2(520.0, 0.0)
	rotulo_debug.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caixa.add_child(rotulo_debug)


func _ao_clicar_distancia() -> void:
	var proximo := (indice_distancia + 1) % OPCOES_DISTANCIA.size()
	definir_distancia_maxima(OPCOES_DISTANCIA[proximo])


func _atualizar_interface() -> void:
	if rotulo_status == null:
		return

	var texto: String = ""
	if modo == "combate":
		texto = "COMBATE  |  Rodada %d  |  Vez de: %s%s\n" % [rodada, ator_atual, "  (VOCÊ)" if turno_atual == Turno.JOGADOR else ""]
	else:
		texto = "EXPLORAÇÃO (sem turnos)  |  Converse com o Mestre no chat para agir\n"
	if celula_jogador == CELULA_INVALIDA:
		texto += "Jogador: fora do tabuleiro"
	else:
		var f: Dictionary = ficha_em(celula_jogador)
		texto += "%s  PV %d/%d  CA %d" % [f["nome"], f["pv"], f["pv_max"], f["ca"]]
		if modo == "combate":
			texto += "  |  Movimento %d/%d  |  Ação: %s" % [movimento_restante, distancia_maxima, "disponível" if acao_disponivel else "usada"]
		var inv: Array = f["inventario"]
		if not inv.is_empty():
			texto += "\nCarregando: " + ", ".join(inv)
	if aviso != "":
		texto += "\n" + aviso
	rotulo_status.text = texto

	botao_distancia.text = "Movimento máx.: %d (alternar)" % distancia_maxima
	botao_turno.disabled = modo != "combate" or turno_atual != Turno.JOGADOR or turno_em_andamento or fim_de_jogo
	if botao_combate != null:
		botao_combate.text = "Encerrar combate (K)" if modo == "combate" else "Iniciar combate (K)"
	if rotulo_cursor != null:
		rotulo_cursor.text = descrever_celula(cursor_celula)
	if rotulo_legenda != null:
		rotulo_legenda.text = LEGENDA + ("\n" + AJUDA_TECLAS if legenda_visivel else "")

	if rotulo_debug != null:
		rotulo_debug.visible = debug_ativo
		rotulo_debug.text = "NOTAS DA IA: " + ultimo_debug_texto


func _mostrar_aviso(texto: String) -> void:
	aviso = texto
	print(texto)
	_atualizar_interface()


# ===============================================================
# DEPURAÇÃO DAS NOTAS DA IA (tecla B)
# ===============================================================
# Mostra, em cada célula que o NPC poderia alcançar, a melhor nota daquela célula.
# Verde = nota alta, vermelho = nota baixa, ciano = a escolhida.

func _limpar_debug() -> void:
	if debug_no == null:
		return
	for filho in debug_no.get_children():
		filho.queue_free()


func _desenhar_debug(plano: Dictionary, origem: Vector2i) -> void:
	_limpar_debug()
	var por_celula: Dictionary = plano["por_celula"]
	if por_celula.is_empty():
		return
	var minimo: float = 99999.0
	var maximo: float = -99999.0
	for c in por_celula.keys():
		minimo = minf(minimo, float(por_celula[c]))
		maximo = maxf(maximo, float(por_celula[c]))
	var faixa: float = maxf(maximo - minimo, 0.001)
	for c in por_celula.keys():
		var nota: float = float(por_celula[c])
		var rotulo := Label3D.new()
		rotulo.text = "%.0f" % nota
		rotulo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		rotulo.no_depth_test = true
		rotulo.pixel_size = 0.012
		rotulo.font_size = 48
		rotulo.outline_size = 12
		var t: float = (nota - minimo) / faixa
		rotulo.modulate = Color(1.0, 0.25, 0.25).lerp(Color(0.3, 1.0, 0.3), t)
		if c == plano["destino"]:
			rotulo.modulate = Color(0.3, 1.0, 1.0)
			rotulo.font_size = 80
		debug_no.add_child(rotulo)
		rotulo.position = _celula_para_posicao(c, _y_base(c) + 0.5)


# ===============================================================
# FUNÇÕES AUXILIARES
# ===============================================================

func _y_base(celula: Vector2i) -> float:
	return ALTURA_TOPO_PISO + float(altura_de(celula)) * ALTURA_NIVEL


func _pos_peca(celula: Vector2i) -> Vector3:
	return _celula_para_posicao(celula, _y_base(celula) + ALTURA_PERSONAGEM / 2.0)


func _celula_para_posicao(celula: Vector2i, altura: float) -> Vector3:
	return Vector3(celula.x * TAMANHO_CELULA, altura, celula.y * TAMANHO_CELULA)


# Descobre qual célula está embaixo do mouse (considerando terreno elevado)
func celula_sob_mouse(posicao_tela: Vector2) -> Vector2i:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return CELULA_INVALIDA

	var origem := cam.project_ray_origin(posicao_tela)
	var direcao := cam.project_ray_normal(posicao_tela)

	# Tenta do nível mais alto para o chão: o primeiro que "bate" com a altura da célula vence
	for nivel in range(NIVEL_MAXIMO, -1, -1):
		var plano := Plane(Vector3.UP, ALTURA_TOPO_PISO + float(nivel) * ALTURA_NIVEL)
		var ponto = plano.intersects_ray(origem, direcao)
		if ponto == null:
			continue
		var local := to_local(ponto)
		var celula := Vector2i(roundi(local.x / TAMANHO_CELULA), roundi(local.z / TAMANHO_CELULA))
		if celula_valida(celula) and altura_de(celula) == nivel:
			return celula
	return CELULA_INVALIDA


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


func _pintar_peca(peca: Node3D, lado: String) -> void:
	var cor: Color = COR_NEUTRO
	match lado:
		"jogador":
			cor = COR_JOGADOR
		"aliado":
			cor = COR_ALIADO
		"inimigo":
			cor = COR_INIMIGO
	var material := StandardMaterial3D.new()
	material.albedo_color = cor
	for malha in peca.find_children("*", "MeshInstance3D", true, false):
		(malha as MeshInstance3D).material_override = material
	peca.set_meta("material", material)
	peca.set_meta("cor_original", cor)


func _criar_etiqueta(peca: Node3D, ficha: Dictionary) -> void:
	var etiqueta := Label3D.new()
	etiqueta.name = "Etiqueta"
	etiqueta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	etiqueta.no_depth_test = true
	etiqueta.pixel_size = 0.008
	etiqueta.font_size = 48
	etiqueta.outline_size = 12
	etiqueta.position = Vector3(0.0, ALTURA_PERSONAGEM / 2.0 + 0.7, 0.0)
	peca.add_child(etiqueta)
	_atualizar_etiqueta(peca)


func _atualizar_etiqueta(peca: Node3D) -> void:
	var etiqueta := peca.get_node_or_null("Etiqueta") as Label3D
	if etiqueta == null:
		return
	var ficha: Dictionary = peca.get_meta("ficha", {})
	etiqueta.text = "%s\n%d/%d" % [ficha.get("nome", "?"), ficha.get("pv", 0), ficha.get("pv_max", 0)]
	var fracao: float = float(ficha.get("pv", 0)) / float(maxi(int(ficha.get("pv_max", 1)), 1))
	etiqueta.modulate = Color(1.0, 0.3, 0.3).lerp(Color(1.0, 1.0, 1.0), fracao)


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
		marcador.position = _celula_para_posicao(cursor_celula, _y_base(cursor_celula) + ALTURA_MARCADOR)
	_atualizar_interface()


func _criar_destaques() -> void:
	destaques = Node3D.new()
	add_child(destaques)
	malha_destaque = BoxMesh.new()
	malha_destaque.size = Vector3(TAMANHO_CELULA * 0.9, 0.04, TAMANHO_CELULA * 0.9)
	material_destaque = StandardMaterial3D.new()
	material_destaque.albedo_color = Color(0.2, 1.0, 0.3, 0.45)
	material_destaque.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_alvo = StandardMaterial3D.new()
	material_alvo.albedo_color = Color(1.0, 0.2, 0.2, 0.5)
	material_alvo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


# Verde = onde o jogador ainda pode andar. Vermelho = inimigos que ele pode atacar agora.
func _atualizar_destaques() -> void:
	if destaques == null:
		return
	for filho in destaques.get_children():
		filho.queue_free()

	if celula_jogador == CELULA_INVALIDA or fim_de_jogo:
		return
	var livre: bool = movimento_livre and modo != "combate"
	if modo == "combate" and turno_atual != Turno.JOGADOR:
		return
	if modo != "combate" and not livre:
		return

	if livre:
		var alcance_livre := _dijkstra(celula_jogador, LIMITE_EXPLORACAO, true)
		for celula in alcance_livre.keys():
			if celula != celula_jogador:
				_adicionar_quadrado(celula, material_destaque)
		return

	if movimento_restante > 0:
		var alcance := _dijkstra(celula_jogador, movimento_restante, true)
		for celula in alcance.keys():
			if celula == celula_jogador:
				continue
			_adicionar_quadrado(celula, material_destaque)

	if acao_disponivel and modo == "combate":
		var minha: Dictionary = ficha_em(celula_jogador)
		for celula in pecas.keys():
			if sao_hostis(minha, ficha_em(celula)) and not melhor_ataque(celula_jogador, celula).is_empty():
				_adicionar_quadrado(celula, material_alvo)


func _adicionar_quadrado(celula: Vector2i, material: StandardMaterial3D) -> void:
	var quadrado := MeshInstance3D.new()
	quadrado.mesh = malha_destaque
	quadrado.material_override = material
	quadrado.position = _celula_para_posicao(celula, _y_base(celula) + ALTURA_DESTAQUE)
	destaques.add_child(quadrado)
