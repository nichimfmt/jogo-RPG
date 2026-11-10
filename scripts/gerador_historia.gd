extends RefCounted
# ===============================================================
# GERADOR_HISTORIA.GD - monta um CENÁRIO INICIAL NOVO a cada partida.
# Escolhe um enredo (estalagem, armazém ou templo), gera a construção principal e uma casa,
# espalha árvores/pedras/barris, cria os personagens com fichas de conhecimento próprias
# e escreve a PREMISSA que o Mestre lê. A mesma "semente" sempre gera o MESMO cenário
# (é assim que o jogo salvo consegue reconstruir tudo).
# Não é Autoload: o Tabuleiros.gd carrega com preload.
# ===============================================================

const Gerador = preload("res://scripts/gerador_cenas.gd")
const Mundo3 = preload("res://scripts/gerador_mundo.gd")

const NOMES: Array[String] = ["Barnaby", "Mirela", "Teodoro", "Isadora", "Gaspar", "Olívia", "Rurik", "Helena", "Dagoberto", "Nara",
	"Ludo", "Selene", "Anselmo", "Berta", "Cassiano", "Vera", "Orlando", "Tânia", "Fausto", "Lívia"]
const NOMES_INIMIGOS: Array[String] = ["Grok", "Zarg", "Vesk", "Mord", "Skarn", "Brug", "Narg", "Tuk"]
const LUGARES: Array[String] = ["Vale Sereno", "Pedra Alta", "Rio Manso", "Campo Verde", "Fonte Antiga", "Bosque Claro"]
const MOMENTOS: Array[String] = ["na véspera da Feira da Colheita", "numa noite fria de outono", "ao fim de uma tarde de chuva fina",
	"logo depois do amanhecer", "numa noite sem lua"]

const ENREDOS: Array = [
	{
		"id": "estalagem", "predio": "taverna", "tamanhos": ["medio", "grande"], "kuzin": "dentro",
		"nomes_predio": ["Taverna do Javali Dourado", "Estalagem do Corvo Cinzento", "O Cervo Cansado", "Taverna da Lua Torta", "Pouso do Viajante"],
		"cargo_dono": "responsável pela estalagem", "classe_dono": "Humano Estalajadeiro Nível 1",
		"ameaca": ["bandido", "bandido", "lobo"], "ameaca_nome": "bandidos e lobos",
		"gancho": "Nas últimas noites, bandidos têm saqueado quem anda pela estrada.",
	},
	{
		"id": "armazem", "predio": "armazem", "tamanhos": ["medio", "grande"], "kuzin": "fora",
		"nomes_predio": ["Armazém do Rio Manso", "Depósito dos Mercadores", "Armazém Velho"],
		"cargo_dono": "responsável pelo armazém", "classe_dono": "Humano Mercador Nível 1",
		"ameaca": ["goblin", "goblin_arqueiro", "chefe_goblin"], "ameaca_nome": "goblins",
		"gancho": "Goblins têm roubado mercadorias das carroças que passam pela vila.",
	},
	{
		"id": "templo", "predio": "templo", "tamanhos": ["pequeno", "medio"], "kuzin": "fora",
		"nomes_predio": ["Templo da Luz Pálida", "Capela do Vale", "Santuário das Cinzas"],
		"cargo_dono": "responsável pelo templo", "classe_dono": "Humano Sacerdote Nível 2",
		"ameaca": ["esqueleto", "esqueleto", "esqueleto"], "ameaca_nome": "mortos-vivos",
		"gancho": "À noite, esqueletos vêm do cemitério velho e rondam o templo.",
	},
]

const PERSONALIDADES: Array[String] = [
	"simpático(a), falante e um pouco medroso(a)",
	"sério(a), reservado(a) e desconfiado(a) de estranhos",
	"bem-humorado(a), curioso(a) e gosta de boas histórias",
	"cansado(a), direto(a) e sem paciência para rodeios",
]
const PERSONALIDADES_GUARDA: Array[String] = ["séria, leal e desconfiada", "calada, observadora e firme", "irritadiça, mas corajosa"]
const PERSONALIDADES_VIAJANTE: Array[String] = ["misterioso(a) e educado(a)", "tagarela e distraído(a)", "nervoso(a) e sempre olhando para a porta"]


static func montar(tab: Node, semente: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var enredo: Dictionary = ENREDOS[rng.randi_range(0, ENREDOS.size() - 1)]
	var local_nome: String = str(LUGARES[rng.randi_range(0, LUGARES.size() - 1)])
	var indice_momento: int = rng.randi_range(0, MOMENTOS.size() - 1)
	var momento: String = MOMENTOS[indice_momento]
	var horas_iniciais: Array[int] = [8, 21, 17, 6, 22]
	tab.minutos_do_mundo = 60 * horas_iniciais[indice_momento]
	var nomes: Array = NOMES.duplicate()
	_embaralhar(nomes, rng)

	# --- 1) planta da vila: praça, estradas e acampamento (zonas) ---
	var plano: Dictionary = Mundo3.planejar(tab, rng)
	var centro: Vector2i = plano["centro"]

	# --- 2) prédios em ANEL em volta da praça, com folga e portas viradas para a praça ---
	var nome_predio: String = str(enredo["nomes_predio"][rng.randi_range(0, (enredo["nomes_predio"] as Array).size() - 1)])
	var tamanho: String = str(enredo["tamanhos"][rng.randi_range(0, (enredo["tamanhos"] as Array).size() - 1)])
	var qtd_casas: int = rng.randi_range(2, 4)
	var angulo0: float = rng.randf_range(0.0, TAU)
	var total_slots: int = 1 + qtd_casas
	Gerador.folga = Mundo3.FOLGA_ENTRE_PREDIOS
	Gerador.virar_para = centro
	Gerador.raio_maximo = 20
	var principal: String = ""
	var casas: Array = []
	for i in range(total_slots):
		var ang: float = angulo0 + TAU * float(i) / float(total_slots) + rng.randf_range(-0.2, 0.2)
		var ref := centro + Vector2i(int(round(cos(ang) * Mundo3.DISTANCIA_DOS_PREDIOS)), int(round(sin(ang) * Mundo3.DISTANCIA_DOS_PREDIOS)))
		ref = Vector2i(clampi(ref.x, 8, tab.largura_tabuleiro - 9), clampi(ref.y, 8, tab.profundidade_tabuleiro - 9))
		if i == 0:
			var r: Dictionary = Gerador.gerar_predio(tab, str(enredo["predio"]), nome_predio, ref, tamanho, [], rng.randi())
			if not bool(r["ok"]):
				Gerador.folga = 1
				Gerador.virar_para = Vector2i(-9999, -9999)
				Gerador.raio_maximo = 36
				push_warning("gerador_historia: falhou o prédio principal: " + str(r["motivo"]))
				return ""
			principal = str(r["nome"])
		else:
			var rc: Dictionary = Gerador.gerar_predio(tab, "casa", "Casa de %s" % str(nomes[i - 1]), ref, "pequeno", [], rng.randi())
			if bool(rc["ok"]):
				casas.append(str(rc["nome"]))
	Gerador.folga = 1
	Gerador.virar_para = Vector2i(-9999, -9999)
	Gerador.raio_maximo = 36
	var pr: Dictionary = tab.predios[principal]
	var casa_final: String = ", ".join(casas)

	# --- 3) zonas pintadas (floresta, vila, estrada...) e cenário ao ar livre ---
	Mundo3.pintar_zonas(tab, plano, rng)
	var fora_porta: Vector2i = pr["fora"]
	_poco_e_fogueira_na_praca(tab, centro, rng)
	_acampamento(tab, plano["acampamento"], rng)
	_barris_na_vila(tab, rng)
	var arvores: int = Mundo3.plantar(tab, plano, rng)
	print("gerador_historia: ", arvores, " árvores, ", casas.size(), " casas, acampamento a ", plano["direcao_acampamento"])

	# --- personagens (dentro ou fora) ---
	var dono_nome: String = str(nomes[10])
	var guarda_nome: String = str(nomes[11])
	var viajante_nome: String = str(nomes[12])
	var cel_kuzin: Vector2i = _celula_livre_dentro(tab, pr, rng) if str(enredo["kuzin"]) == "dentro" else _celula_livre_perto(tab, fora_porta, 3, rng)
	if cel_kuzin == tab.CELULA_INVALIDA:
		cel_kuzin = _celula_livre_perto(tab, fora_porta, 4, rng)
	tab.colocar_personagem(cel_kuzin, "Kuzin", "kuzin", "jogador")

	var gancho: String = str(enredo["gancho"])
	tab.boato_inicial = gancho
	var ameaca_nome: String = str(enredo["ameaca_nome"])
	var dono_cel: Vector2i = _celula_livre_dentro(tab, pr, rng)
	var segredos_dono: Array = ["Recebi um recado exigindo pagamento dos %s e ainda não contei a ninguém." % ameaca_nome,
		"Estou pensando em abandonar %s antes que seja tarde." % principal,
		"Reconheci um dos %s: já morou aqui na vila." % ameaca_nome]
	if dono_cel != tab.CELULA_INVALIDA and tab.colocar_personagem(dono_cel, "%s" % dono_nome, "aldeao", "aliado", str(enredo["classe_dono"])):
		_dar_conhecimento(tab, dono_cel, str(PERSONALIDADES[rng.randi_range(0, PERSONALIDADES.size() - 1)]),
			["Este lugar se chama %s e eu cuido dele." % principal, gancho,
				"O guarda %s protege este lugar." % guarda_nome,
				"%s chegou há pouco tempo e fala pouco." % viajante_nome],
			[[2, str(segredos_dono[rng.randi_range(0, segredos_dono.size() - 1)])]])
		var rng_agenda := RandomNumberGenerator.new()
		rng_agenda.seed = rng.state
		var posto: Vector2i = _celula_livre_dentro(tab, pr, rng_agenda)
		if posto != tab.CELULA_INVALIDA:
			tab.definir_agenda(dono_cel, [[0, dono_cel, "organiza o salão"], [540, posto, "atende o público"], [1080, dono_cel, "fecha o salão"]])
	var guarda_cel: Vector2i = _celula_livre_dentro(tab, pr, rng) if str(enredo["kuzin"]) == "dentro" else _celula_livre_perto(tab, fora_porta, 4, rng)
	if guarda_cel != tab.CELULA_INVALIDA and tab.colocar_personagem(guarda_cel, "Guarda %s" % guarda_nome, "guarda", "aliado"):
		_dar_conhecimento(tab, guarda_cel, str(PERSONALIDADES_GUARDA[rng.randi_range(0, PERSONALIDADES_GUARDA.size() - 1)]),
			["Estou de guarda em %s." % principal, "Vigio os %s do lado de fora." % ameaca_nome],
			[[2, "Desconfio que %s esconde alguma coisa." % viajante_nome]])
		if fora_porta != tab.CELULA_INVALIDA and fora_porta != guarda_cel:
			tab.definir_agenda(guarda_cel, [[0, guarda_cel, "vigia seu posto"], [510, fora_porta, "vigia a entrada"], [1020, guarda_cel, "vigia seu posto"]])
	var viaj_cel: Vector2i = _celula_livre_dentro(tab, pr, rng) if str(enredo["kuzin"]) == "dentro" else _celula_livre_perto(tab, fora_porta, 5, rng)
	if viaj_cel != tab.CELULA_INVALIDA and tab.colocar_personagem(viaj_cel, "Viajante %s" % viajante_nome, "aldeao", "aliado", "Humano Viajante Nível 1"):
		_dar_conhecimento(tab, viaj_cel, str(PERSONALIDADES_VIAJANTE[rng.randi_range(0, PERSONALIDADES_VIAJANTE.size() - 1)]),
			["Vim de longe pela estrada.", "Vi os %s perto do caminho." % ameaca_nome],
			[[1, "Procuro alguém que passou por %s e não quero dizer quem é." % principal]])
	# --- ameaça: longe do Kuzin ---
	var nomes_inim: Array = NOMES_INIMIGOS.duplicate()
	_embaralhar(nomes_inim, rng)
	var ancora: Vector2i = _celula_livre_perto(tab, plano["acampamento"], 2, rng)
	if ancora == tab.CELULA_INVALIDA:
		ancora = _celula_longe(tab, cel_kuzin, 12, 30, rng)
	var i: int = 0
	for modelo in enredo["ameaca"]:
		var c: Vector2i = ancora if i == 0 else _celula_livre_perto(tab, ancora, 3, rng)
		var nm: String = str(nomes_inim[i % nomes_inim.size()])
		if c != tab.CELULA_INVALIDA:
			tab.colocar_personagem(c, nm, str(modelo), "inimigo")
		i += 1

	# --- premissa para o Mestre ---
	var onde: String = "está dentro de %s" % principal if str(enredo["kuzin"]) == "dentro" else "está do lado de fora de %s" % principal
	var t: String = "Kuzin, um ladino meio-elfo, %s, na vila de %s, %s. " % [onde, local_nome, momento]
	t += "Por perto estão %s (%s), o guarda %s e %s, viajante. " % [dono_nome, str(enredo["cargo_dono"]), guarda_nome, viajante_nome]
	t += "A vila fica numa clareira cercada de floresta, com uma praça no meio. "
	if casa_final != "":
		t += "Na vila também ficam: %s. " % casa_final
	t += gancho
	return t


# ---------------------------------------------------------------
# AJUDANTES
# ---------------------------------------------------------------
static func _embaralhar(lista: Array, rng: RandomNumberGenerator) -> void:
	for i in range(lista.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = lista[i]
		lista[i] = lista[j]
		lista[j] = tmp


static func _dar_conhecimento(tab: Node, celula: Vector2i, personalidade: String, sabe: Array, segredos: Array) -> void:
	var ficha: Dictionary = tab.ficha_em(celula)
	var c: Dictionary = ficha["conhecimento"]
	c["personalidade"] = personalidade
	c["sabe"] = sabe
	var esconde: Array = []
	for seg in segredos:
		# seg = [atitude_minima, "frase do segredo"]
		esconde.append({"fato": str(seg[1]), "atitude_minima": maxi(int(seg[0]), 1)})
	c["esconde"] = esconde


# Retângulos das construções (com folga) para não espalhar coisas em cima delas
static func _dentro_de_predio_com_folga(tab: Node, celula: Vector2i, folga: int) -> bool:
	for n in tab.predios.keys():
		var p: Dictionary = tab.predios[n]
		if celula.x >= int(p["x0"]) - folga and celula.x <= int(p["x1"]) + folga and celula.y >= int(p["z0"]) - folga and celula.y <= int(p["z1"]) + folga:
			return true
	return false


static func _livre(tab: Node, celula: Vector2i) -> bool:
	if not tab.celula_valida(celula) or tab.celula_ocupada(celula) or tab.eh_obstaculo(celula):
		return false
	var zona: String = tab.zona_em(celula)
	if zona == "floresta" or zona == "campo" or zona == "estrada":
		return true                  # ao ar livre só árvores/pedras existem, e elas já são obstáculos
	for n in tab.objetos.keys():
		if tab.objetos[n]["celula"] == celula:
			return false
	return true


# Poço e fogueira no meio da praça
static func _poco_e_fogueira_na_praca(tab: Node, centro: Vector2i, rng: RandomNumberGenerator) -> void:
	if _livre(tab, centro):
		tab.criar_objeto("Poço", "pedra", centro)
	var f: Vector2i = _celula_livre_perto(tab, centro + Vector2i(rng.randi_range(-2, 2), rng.randi_range(2, 3)), 1, rng)
	if f != tab.CELULA_INVALIDA:
		tab.criar_objeto("Fogueira da Praça", "fogueira", f)


# Fogueira e algumas caixas no acampamento dos inimigos
static func _acampamento(tab: Node, camp: Vector2i, rng: RandomNumberGenerator) -> void:
	if _livre(tab, camp):
		tab.criar_objeto("Fogueira do Acampamento", "fogueira", camp)
	var n: int = 0
	for tentativa in range(12):
		if n >= 3:
			break
		var c := camp + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
		if c != camp and tab.distancia(c, camp) >= 2 and _livre(tab, c):
			if tab.criar_objeto("Caixote do Acampamento" if n == 0 else "Barril do Acampamento %d" % n, "caixote" if n == 0 else "barril", c):
				n += 1


# Alguns barris espalhados pela vila (longe das portas)
static func _barris_na_vila(tab: Node, rng: RandomNumberGenerator) -> void:
	var quer: int = rng.randi_range(2, 4)
	var feitos: int = 0
	var celulas: Array = []
	for c in tab.zonas.keys():
		if str(tab.zonas[c]) == "vila":
			celulas.append(c)
	celulas.sort()
	for tentativa in range(80):
		if feitos >= quer or celulas.is_empty():
			break
		var c: Vector2i = celulas[rng.randi_range(0, celulas.size() - 1)]
		if _dentro_de_predio_com_folga(tab, c, 1) or _perto_de_porta(tab, c, 3) or not _livre(tab, c):
			continue
		if tab.criar_objeto("Barril da Vila %d" % (feitos + 1), "barril", c):
			feitos += 1


# Perto de alguma porta? (não pode pôr nada ali, para não trancar a entrada)
static func _perto_de_porta(tab: Node, celula: Vector2i, raio: int) -> bool:
	for n in tab.predios.keys():
		for porta in tab.predios[n]["portas"]:
			if tab.distancia(celula, porta["fora"]) <= raio:
				return true
	return false


static func _celula_livre_dentro(tab: Node, pr: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var opcoes: Array = []
	var alcancaveis: Dictionary = tab._dijkstra(pr["fora"], 90, false)   # só células que dá para alcançar pela porta
	for x in range(int(pr["x0"]) + 1, int(pr["x1"])):
		for z in range(int(pr["z0"]) + 1, int(pr["z1"])):
			var c := Vector2i(x, z)
			if not _livre(tab, c) or not alcancaveis.has(c):
				continue
			var perto_da_porta: bool = false
			for porta in pr["portas"]:
				if tab.distancia(c, porta["dentro"]) <= 1:
					perto_da_porta = true
			if not perto_da_porta:
				opcoes.append(c)
	if opcoes.is_empty():
		return tab.CELULA_INVALIDA
	return opcoes[rng.randi_range(0, opcoes.size() - 1)]


static func _celula_livre_perto(tab: Node, centro: Vector2i, raio: int, rng: RandomNumberGenerator) -> Vector2i:
	var opcoes: Array = []
	for x in range(centro.x - raio, centro.x + raio + 1):
		for z in range(centro.y - raio, centro.y + raio + 1):
			var c := Vector2i(x, z)
			if _livre(tab, c) and not _dentro_de_predio_com_folga(tab, c, 0) and not _perto_de_porta(tab, c, 1):
				opcoes.append(c)
	if opcoes.is_empty():
		return tab.CELULA_INVALIDA
	return opcoes[rng.randi_range(0, opcoes.size() - 1)]


static func _celula_longe(tab: Node, de: Vector2i, minimo: int, maximo: int, rng: RandomNumberGenerator) -> Vector2i:
	var opcoes: Array = []
	for x in range(1, tab.largura_tabuleiro - 1):
		for z in range(1, tab.profundidade_tabuleiro - 1):
			var c := Vector2i(x, z)
			var d: int = tab.distancia(de, c)
			if d >= minimo and d <= maximo and _livre(tab, c) and not _dentro_de_predio_com_folga(tab, c, 1):
				opcoes.append(c)
	if opcoes.is_empty():
		return tab.CELULA_INVALIDA
	return opcoes[rng.randi_range(0, opcoes.size() - 1)]
