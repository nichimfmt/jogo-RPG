extends RefCounted
# ---------------------------------------------------------------
# GERADOR_CENAS.GD - o sistema que MONTA construções diferentes cada vez (arquitetura procedural).
#
# Ideia: o Mestre IA só diz "uma taverna grande, com porta dos fundos, perto do Kuzin".
# Este código decide TUDO o resto (tamanho exato, onde ficam as portas, balcão, mesas, lareira,
# palco, alçapão...) usando só as PEÇAS do catálogo (parede, porta, mesa, barril...).
# Depois devolve a lista do que existe, para o Mestre narrar SÓ o que de fato foi criado.
#
# Não precisa ser Autoload: o Tabuleiros.gd carrega com preload.
# Para criar uma construção nova ou mudar a "receita", mexa nas funções _mobiliar_*.
# ---------------------------------------------------------------

const TENTATIVAS: int = 6

# Faixas de tamanho (largura mín, máx, profundidade mín, máx) por tipo e tamanho
const TAMANHOS: Dictionary = {
	"taverna": {"pequeno": [8, 9, 6, 7], "medio": [10, 12, 7, 9], "grande": [13, 15, 9, 11]},
	"casa": {"pequeno": [5, 6, 5, 5], "medio": [7, 8, 6, 7], "grande": [9, 10, 7, 8]},
	"armazem": {"pequeno": [7, 8, 6, 7], "medio": [9, 11, 7, 9], "grande": [12, 14, 9, 11]},
	"templo": {"pequeno": [7, 8, 9, 10], "medio": [9, 10, 10, 12], "grande": [11, 13, 12, 14]},
}


# Devolve {"ok": bool, "motivo": String, "nome": String, "recursos": Array, "resumo": String}
static func gerar_predio(tab: Node, modelo: String, nome: String, referencia: Vector2i, tamanho: String, extras: Array, semente: int) -> Dictionary:
	if not TAMANHOS.has(modelo):
		return {"ok": false, "motivo": "Não sei gerar '%s'. Use: %s." % [modelo, ", ".join(TAMANHOS.keys())]}
	if not (TAMANHOS[modelo] as Dictionary).has(tamanho):
		tamanho = "medio"

	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var motivo: String = "não achei espaço livre perto de (%d,%d)" % [referencia.x, referencia.y]

	for tentativa in range(TENTATIVAS):
		var faixa: Array = TAMANHOS[modelo][tamanho]
		var largura: int = rng.randi_range(int(faixa[0]), int(faixa[1]))
		var profundidade: int = rng.randi_range(int(faixa[2]), int(faixa[3]))
		var canto: Vector2i = _achar_lugar(tab, largura, profundidade, referencia, rng)
		if canto == tab.CELULA_INVALIDA:
			# tenta um pouco menor
			largura = maxi(largura - 2, 5)
			profundidade = maxi(profundidade - 2, 5)
			canto = _achar_lugar(tab, largura, profundidade, referencia, rng)
			if canto == tab.CELULA_INVALIDA:
				continue

		# --- portas ---
		var frente: String = _lado_virado_para(canto, largura, profundidade, referencia)
		if rng.randf() > 0.7:
			frente = ["norte", "sul", "leste", "oeste"][rng.randi_range(0, 3)]
		var lados_extras: Array = []
		var oposto: String = str(tab.LADO_OPOSTO[frente])
		var chance_fundos: float = {"taverna": 0.5, "casa": 0.35, "armazem": 0.4, "templo": 0.15}.get(modelo, 0.3)
		if extras.has("porta_dos_fundos") or rng.randf() < chance_fundos:
			lados_extras.append(oposto)
		if extras.has("porta_lateral") or rng.randf() < 0.18:
			var laterais: Array = ["leste", "oeste"] if frente == "norte" or frente == "sul" else ["norte", "sul"]
			lados_extras.append(laterais[rng.randi_range(0, 1)])

		if not tab.construir_predio(nome, modelo, canto, largura, profundidade, frente, lados_extras):
			motivo = str(tab.ultimo_motivo)
			continue
		var nome_final: String = tab._ultimo_predio

		var recursos: Array = []
		var predio: Dictionary = tab.predios[nome_final]
		match modelo:
			"taverna":
				_mobiliar_taverna(tab, predio, tamanho, extras, rng, recursos)
			"casa":
				_mobiliar_casa(tab, predio, extras, rng, recursos)
			"armazem":
				_mobiliar_armazem(tab, predio, extras, rng, recursos)
			"templo":
				_mobiliar_templo(tab, predio, extras, rng, recursos)

		if not _tudo_acessivel(tab, predio):
			tab.demolir_predio(nome_final)
			motivo = "o layout gerado ficou com cantos inacessíveis"
			continue

		predio["recursos"] = recursos
		var portas_txt: Array = []
		for porta in predio["portas"]:
			portas_txt.append("%s (lado %s)" % [porta["rotulo"], porta["lado"]])
		var resumo: String = "%s '%s' (%dx%d) com %s; contém: %s." % [modelo, nome_final, largura, profundidade, ", ".join(portas_txt), ", ".join(recursos) if not recursos.is_empty() else "nada além do salão vazio"]
		return {"ok": true, "motivo": "", "nome": nome_final, "recursos": recursos, "resumo": resumo}

	return {"ok": false, "motivo": motivo}


# ---------------------------------------------------------------
# ONDE COLOCAR
# ---------------------------------------------------------------
static func _celulas_ocupadas(tab: Node) -> Dictionary:
	var ocupadas: Dictionary = {}
	for c in tab.pecas.keys():
		ocupadas[c] = true
	for c in tab.obstaculos.keys():
		ocupadas[c] = true
	for c in tab.alturas.keys():
		ocupadas[c] = true
	for n in tab.objetos.keys():
		ocupadas[tab.objetos[n]["celula"]] = true
	return ocupadas


# Procura um retângulo LIVRE (com 1 célula de folga em volta), do mais perto para o mais longe da referência
static func _achar_lugar(tab: Node, largura: int, profundidade: int, referencia: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var ocupadas: Dictionary = _celulas_ocupadas(tab)
	for raio in range(3, 36):
		var candidatos: Array = []
		for dx in range(-raio, raio + 1):
			for dz in range(-raio, raio + 1):
				if maxi(absi(dx), absi(dz)) != raio:
					continue
				candidatos.append(referencia + Vector2i(dx, dz) - Vector2i(largura / 2, profundidade / 2))
		# embaralha para variar
		for i in range(candidatos.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: Vector2i = candidatos[i]
			candidatos[i] = candidatos[j]
			candidatos[j] = tmp
		for canto in candidatos:
			if _retangulo_livre(tab, ocupadas, canto, largura, profundidade):
				return canto
	return tab.CELULA_INVALIDA


static func _retangulo_livre(tab: Node, ocupadas: Dictionary, canto: Vector2i, largura: int, profundidade: int) -> bool:
	if not tab.celula_valida(canto) or not tab.celula_valida(canto + Vector2i(largura - 1, profundidade - 1)):
		return false
	for x in range(canto.x - 1, canto.x + largura + 1):
		for z in range(canto.y - 1, canto.y + profundidade + 1):
			if ocupadas.has(Vector2i(x, z)):
				return false
	return true


# A frente da construção fica virada para a referência (como uma porta que dá para a rua/praça)
static func _lado_virado_para(canto: Vector2i, largura: int, profundidade: int, referencia: Vector2i) -> String:
	var centro := Vector2(float(canto.x) + float(largura - 1) / 2.0, float(canto.y) + float(profundidade - 1) / 2.0)
	var dx: float = float(referencia.x) - centro.x
	var dz: float = float(referencia.y) - centro.y
	if absf(dx) > absf(dz):
		return "leste" if dx > 0.0 else "oeste"
	return "sul" if dz > 0.0 else "norte"


# ---------------------------------------------------------------
# AJUDAS DE INTERIOR
# ---------------------------------------------------------------
static func _vetor_para(lado: String) -> Vector2i:
	match lado:
		"norte":
			return Vector2i(0, -1)
		"sul":
			return Vector2i(0, 1)
		"leste":
			return Vector2i(1, 0)
	return Vector2i(-1, 0)


static func _interior(predio: Dictionary) -> Array:
	var lista: Array = []
	for x in range(int(predio["x0"]) + 1, int(predio["x1"])):
		for z in range(int(predio["z0"]) + 1, int(predio["z1"])):
			lista.append(Vector2i(x, z))
	return lista


# Células que precisam ficar LIVRES: o corredor de 2 células para dentro de cada porta
static func _reservadas(predio: Dictionary) -> Dictionary:
	var r: Dictionary = {}
	for porta in predio["portas"]:
		var dentro: Vector2i = porta["dentro"]
		var para_dentro: Vector2i = dentro - porta["celula"]
		r[dentro] = true
		r[dentro + para_dentro] = true
		r[dentro + para_dentro * 2] = true
	return r


static func _celula_livre(tab: Node, c: Vector2i) -> bool:
	return tab.celula_valida(c) and not tab.eh_obstaculo(c) and not tab.celula_ocupada(c) and tab._objetos_na_celula(c).is_empty()


# Cria um objeto da construção (se a célula for válida e livre). Devolve o nome criado ou "".
static func _por(tab: Node, predio: Dictionary, nome: String, modelo: String, c: Vector2i, reservadas: Dictionary, ignorar_reserva: bool = false) -> String:
	if not ignorar_reserva and reservadas.has(c):
		return ""
	var dentro: bool = c.x > int(predio["x0"]) and c.x < int(predio["x1"]) and c.y > int(predio["z0"]) and c.y < int(predio["z1"])
	if not dentro or not _celula_livre(tab, c):
		return ""
	if not tab.criar_objeto(nome, modelo, c):
		return ""
	var criado: String = tab._nome_criado_por_ultimo
	tab.objetos[criado]["predio"] = str(predio["nome"])
	return criado


# Células do interior encostadas numa parede (lado), da esquerda para a direita / de cima para baixo
static func _fileira_junto_da_parede(predio: Dictionary, lado: String) -> Array:
	var lista: Array = []
	var x0: int = int(predio["x0"]) + 1
	var x1: int = int(predio["x1"]) - 1
	var z0: int = int(predio["z0"]) + 1
	var z1: int = int(predio["z1"]) - 1
	match lado:
		"norte":
			for x in range(x0, x1 + 1):
				lista.append(Vector2i(x, z0))
		"sul":
			for x in range(x0, x1 + 1):
				lista.append(Vector2i(x, z1))
		"oeste":
			for z in range(z0, z1 + 1):
				lista.append(Vector2i(x0, z))
		_:
			for z in range(z0, z1 + 1):
				lista.append(Vector2i(x1, z))
	return lista


static func _distancia(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func _longe_de(c: Vector2i, outras: Array, minimo: int) -> bool:
	for o in outras:
		if _distancia(c, o) < minimo:
			return false
	return true


# Coloca mesas com espaço em volta (e cadeiras dos lados). Devolve quantas mesas entraram.
static func _espalhar_mesas(tab: Node, predio: Dictionary, quantidade: int, rng: RandomNumberGenerator, reservadas: Dictionary, evitar: Array, prefixo: String, com_cadeiras: bool) -> int:
	var interior: Array = _interior(predio)
	var postas: Array = []
	var total: int = 0
	for tentativa in range(80):
		if total >= quantidade:
			break
		var c: Vector2i = interior[rng.randi_range(0, interior.size() - 1)]
		if reservadas.has(c) or not _longe_de(c, postas, 3) or not _longe_de(c, evitar, 2):
			continue
		var criada: String = _por(tab, predio, "%s %d" % [prefixo, total + 1], "mesa", c, reservadas)
		if criada == "":
			continue
		postas.append(c)
		total += 1
		if com_cadeiras:
			for d in [Vector2i(-1, 0), Vector2i(1, 0)]:
				_por(tab, predio, "Cadeira", "cadeira", c + d, reservadas)
	return total


static func _tochas_na_entrada(tab: Node, predio: Dictionary) -> int:
	var total: int = 0
	var porta: Dictionary = predio["portas"][0]
	var dentro: Vector2i = porta["dentro"]
	var para_dentro: Vector2i = dentro - porta["celula"]
	var lateral: Vector2i = Vector2i(para_dentro.y, para_dentro.x)
	for sinal in [-1, 1]:
		var c: Vector2i = dentro + lateral * sinal
		var nome: String = _por(tab, predio, "Tocha", "tocha", c, {}, true)
		if nome != "":
			tab.mudar_estado(nome, "aceso")
			total += 1
	return total


# ---------------------------------------------------------------
# RECEITAS DE INTERIOR
# ---------------------------------------------------------------
static func _mobiliar_taverna(tab: Node, predio: Dictionary, tamanho: String, extras: Array, rng: RandomNumberGenerator, recursos: Array) -> void:
	var reservadas: Dictionary = _reservadas(predio)
	var frente: String = str(predio["lado_porta"])
	var lados_com_porta: Array = []
	for porta in predio["portas"]:
		lados_com_porta.append(str(porta["lado"]))
	var ocupados_extra: Array = []
	var nome_predio: String = str(predio["nome"])

	# PALCO (terreno elevado num canto longe da entrada)
	if extras.has("palco") or (tamanho != "pequeno" and rng.randf() < 0.35):
		var cantos: Array = []
		var ix0: int = int(predio["x0"]) + 1
		var ix1: int = int(predio["x1"]) - 1
		var iz0: int = int(predio["z0"]) + 1
		var iz1: int = int(predio["z1"]) - 1
		cantos = [Vector2i(ix0, iz0), Vector2i(ix1 - 2, iz0), Vector2i(ix0, iz1 - 1), Vector2i(ix1 - 2, iz1 - 1)]
		var cantos_validos: Array = []
		for c in cantos:
			var ok: bool = true
			for x in range(3):
				for z in range(2):
					var cc: Vector2i = c + Vector2i(x, z)
					if reservadas.has(cc) or not _celula_livre(tab, cc) or cc.x >= int(predio["x1"]) or cc.y >= int(predio["z1"]):
						ok = false
			if ok:
				cantos_validos.append(c)
		if not cantos_validos.is_empty():
			var escolhido: Vector2i = cantos_validos[rng.randi_range(0, cantos_validos.size() - 1)]
			for x in range(3):
				for z in range(2):
					var cc2: Vector2i = escolhido + Vector2i(x, z)
					tab.definir_altura(cc2, 1)
					(predio["alturas"] as Array).append(cc2)
					ocupados_extra.append(cc2)
			recursos.append("palco elevado")

	# BALCÃO junto de uma parede que não seja a da frente (e sem porta)
	var opcoes: Array = []
	var oposto: String = str(tab.LADO_OPOSTO[frente])
	for lado in [oposto, "norte", "sul", "leste", "oeste"]:
		if lado != frente and not lados_com_porta.has(lado) and not opcoes.has(lado):
			opcoes.append(lado)
	var balcao: Array = []
	if not opcoes.is_empty():
		var lado_balcao: String = str(opcoes[0])
		var fileira: Array = _fileira_junto_da_parede(predio, lado_balcao)
		var tamanho_balcao: int = clampi(fileira.size() - 4, 2, 5)
		var inicio: int = rng.randi_range(1, maxi(fileira.size() - tamanho_balcao - 1, 1))
		for i in range(tamanho_balcao):
			var c2: Vector2i = fileira[mini(inicio + i, fileira.size() - 1)]
			if ocupados_extra.has(c2):
				continue
			var nome_b: String = _por(tab, predio, "Balcão" if balcao.is_empty() else "Balcão %d" % (balcao.size() + 1), "balcao", c2, reservadas)
			if nome_b != "":
				balcao.append(c2)
		if balcao.size() >= 1:
			recursos.append("balcão (%d blocos)" % balcao.size())

	# MESAS com cadeiras
	var quantidade: int = {"pequeno": 2, "medio": 4, "grande": 6}.get(tamanho, 3) + rng.randi_range(0, 1)
	var evitar: Array = balcao + ocupados_extra
	var mesas: int = _espalhar_mesas(tab, predio, quantidade, rng, reservadas, evitar, "Mesa", true)
	if mesas > 0:
		recursos.append("%d mesas com cadeiras" % mesas)

	# LAREIRA numa parede lateral
	if rng.randf() < 0.8 or extras.has("lareira"):
		for lado in ["oeste", "leste", "norte", "sul"]:
			if lado == frente or lados_com_porta.has(lado):
				continue
			var fil: Array = _fileira_junto_da_parede(predio, lado)
			var meio: Vector2i = fil[fil.size() / 2]
			if ocupados_extra.has(meio) or balcao.has(meio):
				continue
			var nome_l: String = _por(tab, predio, "Lareira", "fogueira", meio, reservadas)
			if nome_l != "":
				recursos.append("lareira acesa")
				break

	# BARRIS e BAÚ nos cantos
	var cantos_int: Array = [Vector2i(int(predio["x0"]) + 1, int(predio["z0"]) + 1), Vector2i(int(predio["x1"]) - 1, int(predio["z0"]) + 1),
		Vector2i(int(predio["x0"]) + 1, int(predio["z1"]) - 1), Vector2i(int(predio["x1"]) - 1, int(predio["z1"]) - 1)]
	var barris: int = 0
	var baus: int = 0
	for c3 in cantos_int:
		if ocupados_extra.has(c3):
			continue
		if barris < 2 and rng.randf() < 0.6:
			if _por(tab, predio, "Barril de cerveja", "barril", c3, reservadas) != "":
				barris += 1
				continue
		if baus < 1 and rng.randf() < 0.4:
			if _por(tab, predio, "Baú da taverna", "bau", c3, reservadas) != "":
				baus += 1
	if barris > 0:
		recursos.append("%d barris de cerveja" % barris)
	if baus > 0:
		recursos.append("baú")

	# TOCHAS na entrada
	var tochas: int = _tochas_na_entrada(tab, predio)
	if tochas > 0:
		recursos.append("tochas acesas na entrada")

	# ALÇAPÃO para a adega
	if extras.has("alcapao") or rng.randf() < 0.3:
		_por_alcapao(tab, predio, rng, reservadas, balcao, recursos)

	for porta in predio["portas"]:
		recursos.append(str(porta["rotulo"]))


static func _por_alcapao(tab: Node, predio: Dictionary, rng: RandomNumberGenerator, reservadas: Dictionary, evitar: Array, recursos: Array) -> void:
	var interior: Array = _interior(predio)
	for tentativa in range(40):
		var c: Vector2i = interior[rng.randi_range(0, interior.size() - 1)]
		if reservadas.has(c) or not _celula_livre(tab, c) or tab.altura_de(c) > 0:
			continue
		if _por(tab, predio, "Alçapão da adega", "alcapao", c, reservadas) != "":
			recursos.append("alçapão fechado no chão que leva à adega")
			return


static func _mobiliar_casa(tab: Node, predio: Dictionary, extras: Array, rng: RandomNumberGenerator, recursos: Array) -> void:
	var reservadas: Dictionary = _reservadas(predio)
	var frente: String = str(predio["lado_porta"])
	var lados_com_porta: Array = []
	for porta in predio["portas"]:
		lados_com_porta.append(str(porta["lado"]))

	# CAMAS junto da parede dos fundos
	var camas: int = 0
	var oposto: String = str(tab.LADO_OPOSTO[frente])
	var fil: Array = _fileira_junto_da_parede(predio, oposto if not lados_com_porta.has(oposto) else "leste")
	var quer: int = rng.randi_range(1, 2)
	for i in range(fil.size()):
		if camas >= quer:
			break
		if i % 3 == 1:
			if _por(tab, predio, "Cama" if camas == 0 else "Cama %d" % (camas + 1), "cama", fil[i], reservadas) != "":
				camas += 1
	if camas > 0:
		recursos.append("%d cama(s)" % camas)

	var mesas: int = _espalhar_mesas(tab, predio, 1, rng, reservadas, [], "Mesa", true)
	if mesas > 0:
		recursos.append("mesa com cadeiras")

	if rng.randf() < 0.7:
		for lado in ["oeste", "leste", "norte", "sul"]:
			if lado == frente or lados_com_porta.has(lado):
				continue
			var f2: Array = _fileira_junto_da_parede(predio, lado)
			if _por(tab, predio, "Lareira", "fogueira", f2[f2.size() / 2], reservadas) != "":
				recursos.append("lareira acesa")
				break

	var cantos: Array = [Vector2i(int(predio["x0"]) + 1, int(predio["z0"]) + 1), Vector2i(int(predio["x1"]) - 1, int(predio["z1"]) - 1),
		Vector2i(int(predio["x1"]) - 1, int(predio["z0"]) + 1), Vector2i(int(predio["x0"]) + 1, int(predio["z1"]) - 1)]
	for c in cantos:
		if _por(tab, predio, "Baú", "bau", c, reservadas) != "":
			recursos.append("baú")
			break
	if rng.randf() < 0.5:
		for c2 in cantos:
			if _por(tab, predio, "Barril", "barril", c2, reservadas) != "":
				recursos.append("barril")
				break

	if extras.has("alcapao") or rng.randf() < 0.15:
		_por_alcapao(tab, predio, rng, reservadas, [], recursos)
	for porta in predio["portas"]:
		recursos.append(str(porta["rotulo"]))


static func _mobiliar_armazem(tab: Node, predio: Dictionary, extras: Array, rng: RandomNumberGenerator, recursos: Array) -> void:
	var reservadas: Dictionary = _reservadas(predio)
	var interior: Array = _interior(predio)
	var caixotes: int = 0
	var barris: int = 0
	var alvo: int = clampi(interior.size() / 6, 5, 18)
	for tentativa in range(120):
		if caixotes + barris >= alvo:
			break
		var c: Vector2i = interior[rng.randi_range(0, interior.size() - 1)]
		if reservadas.has(c):
			continue
		if rng.randf() < 0.6:
			if _por(tab, predio, "Caixote", "caixote", c, reservadas) != "":
				caixotes += 1
		else:
			if _por(tab, predio, "Barril", "barril", c, reservadas) != "":
				barris += 1
	if caixotes > 0:
		recursos.append("%d caixotes empilhados" % caixotes)
	if barris > 0:
		recursos.append("%d barris" % barris)
	if _tochas_na_entrada(tab, predio) > 0:
		recursos.append("tochas acesas na entrada")
	if extras.has("alcapao") or rng.randf() < 0.25:
		_por_alcapao(tab, predio, rng, reservadas, [], recursos)
	for porta in predio["portas"]:
		recursos.append(str(porta["rotulo"]))


static func _mobiliar_templo(tab: Node, predio: Dictionary, extras: Array, rng: RandomNumberGenerator, recursos: Array) -> void:
	var reservadas: Dictionary = _reservadas(predio)
	var frente: String = str(predio["lado_porta"])
	var oposto: String = str(tab.LADO_OPOSTO[frente])
	var altar_celulas: Array = _fileira_junto_da_parede(predio, oposto)
	var meio: Vector2i = altar_celulas[altar_celulas.size() / 2]
	if _por(tab, predio, "Altar", "altar", meio, reservadas, true) != "":
		recursos.append("altar de pedra")
	# bancos em duas colunas deixando o corredor central livre
	var bancos: int = 0
	var vertical: bool = frente == "norte" or frente == "sul"
	for c in _interior(predio):
		var eixo: int = c.x if vertical else c.y
		var centro: int = (int(predio["x0"]) + int(predio["x1"])) / 2 if vertical else (int(predio["z0"]) + int(predio["z1"])) / 2
		var along: int = c.y if vertical else c.x
		if absi(eixo - centro) < 2 or absi(eixo - centro) > 3:
			continue
		if along % 2 == 0:
			if _por(tab, predio, "Banco", "banco", c, reservadas) != "":
				bancos += 1
	if bancos > 0:
		recursos.append("%d bancos em fileiras" % bancos)
	if _tochas_na_entrada(tab, predio) > 0:
		recursos.append("tochas acesas na entrada")
	if extras.has("alcapao"):
		_por_alcapao(tab, predio, rng, reservadas, [], recursos)
	for porta in predio["portas"]:
		recursos.append(str(porta["rotulo"]))


# ---------------------------------------------------------------
# VERIFICAÇÃO: dá para chegar em todo o interior e em todas as portas?
# ---------------------------------------------------------------
static func _tudo_acessivel(tab: Node, predio: Dictionary) -> bool:
	var porta: Dictionary = predio["portas"][0]
	var alcance: Dictionary = tab.calcular_alcance(porta["fora"], 120, false)
	for c in _interior(predio):
		if tab.eh_obstaculo(c):
			continue
		if not alcance.has(c):
			return false
	for p in predio["portas"]:
		if not alcance.has(p["celula"]) or not alcance.has(p["fora"]):
			return false
	return true
