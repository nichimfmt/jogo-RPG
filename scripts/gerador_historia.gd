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
	var cx: int = tab.largura_tabuleiro / 2
	var cz: int = tab.profundidade_tabuleiro / 2
	var local_nome: String = str(LUGARES[rng.randi_range(0, LUGARES.size() - 1)])
	var momento: String = str(MOMENTOS[rng.randi_range(0, MOMENTOS.size() - 1)])
	var nomes: Array = NOMES.duplicate()
	_embaralhar(nomes, rng)

	# --- construção principal ---
	var nome_predio: String = str(enredo["nomes_predio"][rng.randi_range(0, (enredo["nomes_predio"] as Array).size() - 1)])
	var tamanho: String = str(enredo["tamanhos"][rng.randi_range(0, (enredo["tamanhos"] as Array).size() - 1)])
	var ref := Vector2i(cx + rng.randi_range(-3, 3), cz + rng.randi_range(-3, 3))
	var r: Dictionary = Gerador.gerar_predio(tab, str(enredo["predio"]), nome_predio, ref, tamanho, [], rng.randi())
	if not bool(r["ok"]):
		push_warning("gerador_historia: falhou o prédio principal: " + str(r["motivo"]))
		return ""
	var principal: String = str(r["nome"])
	var pr: Dictionary = tab.predios[principal]

	# --- uma casa por perto ---
	var casa_nome: String = "Casa de %s" % str(nomes[0])
	var casa_ref := Vector2i(clampi(cx + rng.randi_range(-14, 14), 6, tab.largura_tabuleiro - 7), clampi(cz + rng.randi_range(-14, 14), 6, tab.profundidade_tabuleiro - 7))
	var rc: Dictionary = Gerador.gerar_predio(tab, "casa", casa_nome, casa_ref, "pequeno", [], rng.randi())
	var casa_final: String = str(rc["nome"]) if bool(rc["ok"]) else ""

	# --- cenário ao ar livre ---
	var fora_porta: Vector2i = pr["fora"]
	_pocos_e_fogueira(tab, fora_porta, rng)
	_espalhar(tab, "arvore", "Árvore", rng.randi_range(8, 13), rng)
	_espalhar(tab, "pedra", "Pedra", rng.randi_range(2, 4), rng)
	_espalhar(tab, "barril", "Barril", rng.randi_range(1, 3), rng)

	# --- personagens (dentro ou fora) ---
	var dono_nome: String = str(nomes[1])
	var guarda_nome: String = str(nomes[2])
	var viajante_nome: String = str(nomes[3])
	var cel_kuzin: Vector2i = _celula_livre_dentro(tab, pr, rng) if str(enredo["kuzin"]) == "dentro" else _celula_livre_perto(tab, fora_porta, 3, rng)
	if cel_kuzin == tab.CELULA_INVALIDA:
		cel_kuzin = _celula_livre_perto(tab, fora_porta, 4, rng)
	tab.colocar_personagem(cel_kuzin, "Kuzin", "kuzin", "jogador")

	var gancho: String = str(enredo["gancho"])
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
	var guarda_cel: Vector2i = _celula_livre_dentro(tab, pr, rng) if str(enredo["kuzin"]) == "dentro" else _celula_livre_perto(tab, fora_porta, 4, rng)
	if guarda_cel != tab.CELULA_INVALIDA and tab.colocar_personagem(guarda_cel, "Guarda %s" % guarda_nome, "guarda", "aliado"):
		_dar_conhecimento(tab, guarda_cel, str(PERSONALIDADES_GUARDA[rng.randi_range(0, PERSONALIDADES_GUARDA.size() - 1)]),
			["Estou de guarda em %s." % principal, "Vigio os %s do lado de fora." % ameaca_nome],
			[[2, "Desconfio que %s esconde alguma coisa." % viajante_nome]])
	var viaj_cel: Vector2i = _celula_livre_dentro(tab, pr, rng) if str(enredo["kuzin"]) == "dentro" else _celula_livre_perto(tab, fora_porta, 5, rng)
	if viaj_cel != tab.CELULA_INVALIDA and tab.colocar_personagem(viaj_cel, "Viajante %s" % viajante_nome, "aldeao", "aliado", "Humano Viajante Nível 1"):
		_dar_conhecimento(tab, viaj_cel, str(PERSONALIDADES_VIAJANTE[rng.randi_range(0, PERSONALIDADES_VIAJANTE.size() - 1)]),
			["Vim de longe pela estrada.", "Vi os %s perto do caminho." % ameaca_nome],
			[[1, "Procuro alguém que passou por %s e não quero dizer quem é." % principal]])
	# --- ameaça: longe do Kuzin ---
	var nomes_inim: Array = NOMES_INIMIGOS.duplicate()
	_embaralhar(nomes_inim, rng)
	var ancora: Vector2i = _celula_longe(tab, cel_kuzin, 12, 17, rng)
	var inimigos_txt: Array = []
	var i: int = 0
	for modelo in enredo["ameaca"]:
		var c: Vector2i = ancora if i == 0 else _celula_livre_perto(tab, ancora, 3, rng)
		var nm: String = str(nomes_inim[i % nomes_inim.size()])
		if c != tab.CELULA_INVALIDA and tab.colocar_personagem(c, nm, str(modelo), "inimigo"):
			inimigos_txt.append("%s (%s)" % [nm, tab.MODELOS_CRIATURA[str(modelo)]["classe"]])
		i += 1

	# --- premissa para o Mestre ---
	var onde: String = "está dentro de %s" % principal if str(enredo["kuzin"]) == "dentro" else "está do lado de fora de %s" % principal
	var t: String = "Kuzin, meio-elfo ladino de nível 3, %s, na vila de %s, %s. " % [onde, local_nome, momento]
	t += "Por perto estão %s (%s), o guarda %s e %s, viajante. " % [dono_nome, str(enredo["cargo_dono"]), guarda_nome, viajante_nome]
	if casa_final != "":
		t += "Na vila também fica a %s. " % casa_final
	if not inimigos_txt.is_empty():
		t += "Longe dali, ameaçando a vila: %s. " % ", ".join(inimigos_txt)
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
	for n in tab.objetos.keys():
		if tab.objetos[n]["celula"] == celula:
			return false
	return true


static func _espalhar(tab: Node, modelo: String, base: String, quantos: int, rng: RandomNumberGenerator) -> void:
	var feitos: int = 0
	var tentativas: int = 0
	while feitos < quantos and tentativas < 200:
		tentativas += 1
		var c := Vector2i(rng.randi_range(1, tab.largura_tabuleiro - 2), rng.randi_range(1, tab.profundidade_tabuleiro - 2))
		if _dentro_de_predio_com_folga(tab, c, 2) or _perto_de_porta(tab, c, 2) or not _livre(tab, c):
			continue
		if tab.criar_objeto(base if feitos == 0 else "%s %d" % [base, feitos + 1], modelo, c):
			feitos += 1


# Perto de alguma porta? (não pode pôr nada ali, para não trancar a entrada)
static func _perto_de_porta(tab: Node, celula: Vector2i, raio: int) -> bool:
	for n in tab.predios.keys():
		for porta in tab.predios[n]["portas"]:
			if tab.distancia(celula, porta["fora"]) <= raio:
				return true
	return false


static func _pocos_e_fogueira(tab: Node, fora_porta: Vector2i, rng: RandomNumberGenerator) -> void:
	for tentativa in range(10):
		var c: Vector2i = _celula_livre_perto(tab, fora_porta + Vector2i(rng.randi_range(-4, 4), rng.randi_range(2, 5)), 2, rng)
		if c != tab.CELULA_INVALIDA and not _perto_de_porta(tab, c, 2):
			tab.criar_objeto("Poço", "pedra", c)
			break
	for tentativa in range(10):
		var f: Vector2i = _celula_livre_perto(tab, fora_porta + Vector2i(rng.randi_range(-5, 5), rng.randi_range(-5, 5)), 3, rng)
		if f != tab.CELULA_INVALIDA and not _dentro_de_predio_com_folga(tab, f, 1) and not _perto_de_porta(tab, f, 2):
			tab.criar_objeto("Fogueira", "fogueira", f)
			break


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
