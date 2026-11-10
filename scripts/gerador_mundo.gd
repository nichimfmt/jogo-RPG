extends RefCounted
# ---------------------------------------------------------------
# GERADOR_MUNDO.GD - o "urbanista" do jogo: planeja o MAPA EM ZONAS antes de colocar qualquer coisa.
#
# Como funciona (leia na ordem, é a ordem em que o código roda):
#   1) PRAÇA     : escolhe o centro da vila (perto do meio do mapa).
#   2) VILA      : desenha uma mancha redonda (irregular) em volta da praça.
#   3) PRÉDIOS   : o prédio principal e as casas ficam num ANEL em volta da praça,
#                  com as portas viradas para a praça e sempre com folga entre eles.
#   4) ESTRADAS  : duas estradas saem da praça até a borda do mapa (curvas suaves).
#   5) ACAMPAMENTO: uma clareira na beira da estrada, longe da vila (onde fica a ameaça).
#   6) FLORESTA  : um "mapa de ruído" decide onde há mata fechada; lá nascem muitas árvores.
#                  Fora da floresta há só umas árvores soltas (campo).
#   7) PINTURA   : cada célula guarda o nome da sua zona -> o chão é pintado e o Mestre sabe onde está.
#
# Todos os números que você pode mexer estão na seção "AJUSTES" logo abaixo.
# ---------------------------------------------------------------

const Gerador = preload("res://scripts/gerador_cenas.gd")

# ===================== AJUSTES (mexa à vontade) =====================
const RAIO_DA_PRACA: int = 3              # tamanho da praça no centro da vila
const RAIO_DA_VILA: float = 17.0          # tamanho médio da mancha da vila
const DISTANCIA_DOS_PREDIOS: float = 14.0 # distância dos prédios até o centro da praça
const FOLGA_ENTRE_PREDIOS: int = 4        # células vazias mínimas entre dois prédios
const LARGURA_DA_ESTRADA: int = 1         # 1 = estrada com 3 células de largura (centro +-1)
const DIST_ACAMPAMENTO_MIN: int = 22      # o acampamento fica a esta distância (em passos pela estrada)...
const DIST_ACAMPAMENTO_MAX: int = 30      # ...até esta
const RAIO_DO_ACAMPAMENTO: int = 4
const FREQUENCIA_DA_FLORESTA: float = 0.05   # menor = manchas de floresta maiores
const LIMIAR_DA_FLORESTA: float = 0.05       # menor = MAIS floresta (0.05 dá mais ou menos 40% do mapa)
const DENSIDADE_MATA_FECHADA: float = 0.55   # chance de haver árvore numa célula de mata fechada
const DENSIDADE_MATA_RALA: float = 0.30      # chance na borda da floresta
const DENSIDADE_CAMPO: float = 0.012         # árvores soltas fora da floresta
const DENSIDADE_PEDRAS: float = 0.006
# ====================================================================


# Planeja tudo e devolve {"centro": Vector2i, "estradas": [ [Vector2i...], ... ], "acampamento": Vector2i, "direcao_acampamento": String}
static func planejar(tab: Node, rng: RandomNumberGenerator) -> Dictionary:
	tab.zonas.clear()
	var w: int = tab.largura_tabuleiro
	var h: int = tab.profundidade_tabuleiro
	var centro := Vector2i(w / 2 + rng.randi_range(-8, 8), h / 2 + rng.randi_range(-8, 8))

	# --- estradas: duas direções diferentes ---
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in range(dirs.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = dirs[i]
		dirs[i] = dirs[j]
		dirs[j] = tmp
	var estradas: Array = []
	for k in range(2):
		estradas.append(_tracar_estrada(tab, centro, dirs[k], rng))

	# --- acampamento na beira da estrada 0 (a da ameaça) ---
	var rota: Array = estradas[0]
	var passo: int = clampi(rng.randi_range(DIST_ACAMPAMENTO_MIN, DIST_ACAMPAMENTO_MAX), 5, maxi(rota.size() - 6, 5))
	var acampamento: Vector2i = rota[mini(passo, rota.size() - 1)]
	return {"centro": centro, "estradas": estradas, "acampamento": acampamento, "direcao_acampamento": direcao_texto(centro, acampamento)}


static func direcao_texto(de: Vector2i, para: Vector2i) -> String:
	var dx: int = para.x - de.x
	var dz: int = para.y - de.y
	if absi(dx) >= absi(dz) * 2:
		return "leste" if dx > 0 else "oeste"
	if absi(dz) >= absi(dx) * 2:
		return "sul" if dz > 0 else "norte"
	var ns: String = "sul" if dz > 0 else "norte"
	var lo: String = "leste" if dx > 0 else "oeste"
	return ns + lo


# Estrada: do centro até a borda, ondulando de leve. Devolve a lista de células do eixo da estrada.
static func _tracar_estrada(tab: Node, centro: Vector2i, dir: Vector2i, rng: RandomNumberGenerator) -> Array:
	var perp := Vector2i(dir.y, dir.x)          # perpendicular
	var amp: float = rng.randf_range(2.0, 5.0)
	var fase: float = rng.randf_range(0.0, 6.28)
	var eixo: Array = []
	for t in range(0, 200):
		var lateral: int = int(round(amp * sin(float(t) / 9.0 + fase) * minf(float(t) / 15.0, 1.0)))
		var c: Vector2i = centro + dir * t + perp * lateral
		if not tab.celula_valida(c):
			break
		eixo.append(c)
	return eixo


# Marca as zonas no mapa (ordem importa: o que vem depois pinta por cima)
static func pintar_zonas(tab: Node, plano: Dictionary, rng: RandomNumberGenerator) -> void:
	var w: int = tab.largura_tabuleiro
	var h: int = tab.profundidade_tabuleiro
	var centro: Vector2i = plano["centro"]

	# 1) floresta pelo mapa de ruído
	var ruido := FastNoiseLite.new()
	ruido.seed = rng.randi()
	ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ruido.frequency = FREQUENCIA_DA_FLORESTA
	var valores: Dictionary = {}
	for x in range(w):
		for z in range(h):
			var v: float = ruido.get_noise_2d(float(x), float(z))
			valores[Vector2i(x, z)] = v
			if v > LIMIAR_DA_FLORESTA:
				tab.zonas[Vector2i(x, z)] = "floresta"
	plano["ruido"] = valores

	# 2) vila: mancha redonda irregular + folga em volta dos prédios
	var forma := FastNoiseLite.new()
	forma.seed = rng.randi()
	forma.frequency = 0.08
	for x in range(w):
		for z in range(h):
			var c := Vector2i(x, z)
			var d: float = Vector2(c - centro).length()
			if d < RAIO_DA_VILA + forma.get_noise_2d(float(x), float(z)) * 5.0:
				tab.zonas[c] = "vila"
	for n in tab.predios.keys():
		var p: Dictionary = tab.predios[n]
		for x in range(int(p["x0"]) - 3, int(p["x1"]) + 4):
			for z in range(int(p["z0"]) - 3, int(p["z1"]) + 4):
				if tab.celula_valida(Vector2i(x, z)):
					tab.zonas[Vector2i(x, z)] = "vila"

	# 3) estradas (por cima de campo, floresta e vila)
	for rota in plano["estradas"]:
		for c in rota:
			for dx in range(-LARGURA_DA_ESTRADA, LARGURA_DA_ESTRADA + 1):
				for dz in range(-LARGURA_DA_ESTRADA, LARGURA_DA_ESTRADA + 1):
					if absi(dx) + absi(dz) <= LARGURA_DA_ESTRADA + 1:
						var cc: Vector2i = c + Vector2i(dx, dz)
						if tab.celula_valida(cc):
							tab.zonas[cc] = "estrada"

	# 4) praça e acampamento
	for x in range(centro.x - RAIO_DA_PRACA, centro.x + RAIO_DA_PRACA + 1):
		for z in range(centro.y - RAIO_DA_PRACA, centro.y + RAIO_DA_PRACA + 1):
			var c2 := Vector2i(x, z)
			if tab.celula_valida(c2) and Vector2(c2 - centro).length() <= float(RAIO_DA_PRACA) + 0.5:
				tab.zonas[c2] = "praça"
	var camp: Vector2i = plano["acampamento"]
	for x in range(camp.x - RAIO_DO_ACAMPAMENTO, camp.x + RAIO_DO_ACAMPAMENTO + 1):
		for z in range(camp.y - RAIO_DO_ACAMPAMENTO, camp.y + RAIO_DO_ACAMPAMENTO + 1):
			var c3 := Vector2i(x, z)
			if tab.celula_valida(c3) and Vector2(c3 - camp).length() <= float(RAIO_DO_ACAMPAMENTO) + 0.5:
				tab.zonas[c3] = "acampamento"


# Planta as árvores e pedras segundo as zonas. Devolve quantas árvores nasceram.
static func plantar(tab: Node, plano: Dictionary, rng: RandomNumberGenerator) -> int:
	var w: int = tab.largura_tabuleiro
	var h: int = tab.profundidade_tabuleiro
	var valores: Dictionary = plano["ruido"]
	# células proibidas: dentro/perto de prédios, perto das portas, ocupadas
	var proibido: Dictionary = {}
	for n in tab.predios.keys():
		var p: Dictionary = tab.predios[n]
		for x in range(int(p["x0"]) - 2, int(p["x1"]) + 3):
			for z in range(int(p["z0"]) - 2, int(p["z1"]) + 3):
				proibido[Vector2i(x, z)] = true
		for porta in p["portas"]:
			var f: Vector2i = porta["fora"]
			for x in range(f.x - 3, f.x + 4):
				for z in range(f.y - 3, f.y + 4):
					proibido[Vector2i(x, z)] = true
	for c in tab.pecas.keys():
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				proibido[c + Vector2i(dx, dz)] = true
	for n in tab.objetos.keys():
		proibido[tab.objetos[n]["celula"]] = true

	var arvores: int = 0
	var pedras: int = 0
	tab.iniciar_lote()
	for x in range(1, w - 1):
		for z in range(1, h - 1):
			var c := Vector2i(x, z)
			var zona: String = str(tab.zonas.get(c, "campo"))
			if proibido.has(c) or zona == "estrada" or zona == "praça" or zona == "acampamento" or zona == "vila":
				continue
			var sorteio: float = rng.randf()
			var chance: float = DENSIDADE_CAMPO
			if zona == "floresta":
				chance = DENSIDADE_MATA_FECHADA if float(valores[c]) > LIMIAR_DA_FLORESTA + 0.18 else DENSIDADE_MATA_RALA
			if sorteio < chance:
				if tab.criar_objeto("Árvore %d" % (arvores + 1), "arvore", c):
					arvores += 1
			elif sorteio > 1.0 - DENSIDADE_PEDRAS and zona != "floresta":
				if tab.criar_objeto("Pedra %d" % (pedras + 1), "pedra", c):
					pedras += 1
	tab.finalizar_lote()
	return arvores
