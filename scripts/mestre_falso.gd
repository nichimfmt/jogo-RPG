extends RefCounted
# ===============================================================
# MESTRE_FALSO.GD - um "Mestre de mentirinha" que responde NA HORA, sem usar a IA.
# Serve para você TESTAR o jogo inteiro rápido: movimento, conversas com NPCs, cenário mudando
# (NPC chegando, construção nova, inimigos se aproximando, combate com motivo).
# Ele usa exatamente os mesmos comandos que a IA usaria, então o que funciona aqui funciona com a IA.
# Liga e desliga no chat com /rapido.
# ===============================================================

var contador: int = 0           # quantas ações o jogador já fez
var proximo_evento: int = 0     # qual evento da história de teste vem agora
var _fala_idx: Dictionary = {}  # npc -> próxima fala a repetir

const EVENTOS: Array[String] = ["npc", "construcao", "ameaca", "combate"]

const CHEGADAS: Array = [
	{"nome": "Mira", "pers": "curiosa e direta",
		"sabe": "Vi luzes estranhas na floresta, ao norte, na noite passada.",
		"segredo": "Carrego um mapa de uma passagem secreta e ainda não o mostrei a ninguém."},
	{"nome": "Tomé", "pers": "cansado e desconfiado",
		"sabe": "Vim da estrada do sul e ela está cheia de pegadas de goblins.",
		"segredo": "Fui assaltado na estrada e perdi um anel que não era meu."},
	{"nome": "Sibila", "pers": "calma e enigmática",
		"sabe": "Estudo sinais no céu e acho que algo ruim se aproxima da vila.",
		"segredo": "Já vi o líder dos invasores em um sonho e sei o nome dele."},
]
const CONSTRUCOES: Array = [
	{"nome": "Casa do Ferreiro", "modelo": "casa"},
	{"nome": "Armazém do Mercador", "modelo": "armazem"},
	{"nome": "Capela Pequena", "modelo": "templo"},
]


func abertura(tab: Node) -> String:
	var base: String = ""
	if tab != null and str(tab.premissa_atual) != "":
		base = str(tab.premissa_atual)
	else:
		base = "A aventura começa."
	return "%s\n(MODO RÁPIDO: respostas instantâneas, sem IA.) O que Kuzin faz? Tente: \"vou até <objeto ou pessoa>\", \"falo com <pessoa>\", \"olho ao redor\", ou /evento para avançar a história." % base


# ---------------------------------------------------------------
# AÇÃO LIVRE
# ---------------------------------------------------------------
func planejar(tab: Node, texto: String, fato: String, forcar_evento: bool = false) -> Dictionary:
	contador += 1
	var plano: Dictionary = {"comandos": [], "tipo": "generico", "texto": texto, "fato": fato, "evento": "", "info": ""}
	if fato != "":
		plano["tipo"] = "mover"
	elif _eh_olhar(texto):
		plano["tipo"] = "olhar"
	var disparar: bool = forcar_evento or (contador >= 2 and contador % 2 == 0)
	if disparar and proximo_evento < EVENTOS.size() and tab != null:
		var ev: String = EVENTOS[proximo_evento]
		proximo_evento += 1
		_montar_evento(ev, tab, plano)
	return plano


func _eh_olhar(texto: String) -> bool:
	var t: String = texto.to_lower()
	for p in ["olho", "examino", "observo", "ao redor", "em volta", "procuro", "inspeciono", "escuto"]:
		if t.contains(p):
			return true
	return false


func _celula_livre_perto_do_jogador(tab: Node, minimo: int, maximo: int) -> Vector2i:
	var jog: Vector2i = tab.celula_jogador
	var melhor: Vector2i = tab.CELULA_INVALIDA
	var melhor_d: int = 999
	for x in range(jog.x - maximo, jog.x + maximo + 1):
		for z in range(jog.y - maximo, jog.y + maximo + 1):
			var c := Vector2i(x, z)
			if not tab.celula_valida(c) or tab.celula_ocupada(c) or tab.eh_obstaculo(c):
				continue
			if tab.predio_em(c) != tab.predio_em(jog):
				continue
			var d: int = tab.distancia(jog, c)
			if d < minimo or d > maximo:
				continue
			var sem_objeto: bool = true
			for n in tab.objetos.keys():
				if tab.objetos[n]["celula"] == c:
					sem_objeto = false
			if sem_objeto and d < melhor_d:
				melhor_d = d
				melhor = c
	return melhor


func _montar_evento(ev: String, tab: Node, plano: Dictionary) -> void:
	plano["evento"] = ev
	var jog: Vector2i = tab.celula_jogador
	match ev:
		"npc":
			var escolhida: Dictionary = {}
			for ch in CHEGADAS:
				if tab._achar_exato(str(ch["nome"])) == tab.CELULA_INVALIDA:
					escolhida = ch
					break
			var c: Vector2i = _celula_livre_perto_do_jogador(tab, 3, 6)
			if escolhida.is_empty() or c == tab.CELULA_INVALIDA:
				return
			plano["info"] = str(escolhida["nome"])
			plano["comandos"] = [{"acao": "colocar", "alvo": escolhida["nome"], "modelo": "aldeao", "papel": "aliado",
				"x": c.x, "z": c.y, "personalidade": escolhida["pers"], "sabe": escolhida["sabe"], "segredo": escolhida["segredo"]}]
		"construcao":
			var cons: Dictionary = CONSTRUCOES[randi() % CONSTRUCOES.size()]
			plano["info"] = str(cons["nome"])
			plano["comandos"] = [{"acao": "gerar_construcao", "alvo": cons["nome"], "modelo": cons["modelo"], "tamanho": "pequeno",
				"para": "Kuzin", "extras": ["porta_dos_fundos"]}]
		"ameaca":
			var cmds: Array = []
			var nomes: Array = []
			var usadas: Dictionary = {}
			for c in tab.pecas.keys():
				var f: Dictionary = tab.ficha_em(c)
				if str(f["lado"]) != "inimigo" or cmds.size() >= 2:
					continue
				# procura uma célula livre a 5-7 de Kuzin
				for raio in [5, 6, 7]:
					var achou: bool = false
					for dx in range(-raio, raio + 1):
						for dz in range(-raio, raio + 1):
							var d := Vector2i(jog.x + dx, jog.y + dz)
							if achou or tab.distancia(jog, d) != raio or not tab.celula_valida(d):
								continue
							if tab.celula_ocupada(d) or tab.eh_obstaculo(d) or tab.predio_em(d) != "" or usadas.has(d):
								continue
							usadas[d] = true
							cmds.append({"acao": "mover", "alvo": str(f["nome"]), "x": d.x, "z": d.y})
							nomes.append(str(f["nome"]))
							achou = true
					if achou:
						break
			plano["info"] = ", ".join(nomes)
			plano["comandos"] = cmds
		"combate":
			var alvo_nome: String = ""
			var menor: int = 999
			for c in tab.pecas.keys():
				var f2: Dictionary = tab.ficha_em(c)
				if str(f2["lado"]) == "inimigo" and tab.distancia(jog, c) < menor:
					menor = tab.distancia(jog, c)
					alvo_nome = str(f2["nome"])
			plano["info"] = alvo_nome
			if alvo_nome != "":
				plano["comandos"] = [{"acao": "iniciar_combate", "alvo": "combate", "texto": "%s avançou contra Kuzin de arma em punho" % alvo_nome}]


# Narra DEPOIS de os comandos serem executados (feedback = resultado de cada comando)
func narrar(tab: Node, plano: Dictionary, feedback: String) -> String:
	var partes: Array = []
	match str(plano["tipo"]):
		"mover":
			partes.append(str(plano["fato"]).replace("FATO DO JOGO: ", ""))
		"olhar":
			partes.append(_descrever_ao_redor(tab))
		_:
			if str(plano["evento"]) == "" or str(plano["texto"]) != "(evento forçado)":
				partes.append("Você faz isso: \"%s\". Nada muda de imediato ao redor." % str(plano["texto"]))
	var ev: String = str(plano["evento"])
	if ev != "":
		var falhou: bool = feedback.contains("FALHOU")
		match ev:
			"npc":
				if falhou:
					partes.append("[teste] a chegada de um NPC falhou: " + feedback)
				else:
					partes.append("Alguém chega por perto: %s, com ar %s, aparece e olha em volta." % [str(plano["info"]), _pers_de(tab, str(plano["info"]))])
			"construcao":
				if falhou:
					partes.append("[teste] a construção falhou: " + feedback)
				else:
					partes.append("Enquanto isso, uma nova construção aparece na vila: %s. Seus detalhes: %s" % [str(plano["info"]), feedback.replace("gerar_construcao ", "").left(260)])
			"ameaca":
				if falhou or str(plano["info"]) == "":
					partes.append("[teste] a ameaça não se aproximou: " + feedback)
				else:
					partes.append("Ao longe, passos pesados: %s %s, de olho em Kuzin." % [str(plano["info"]), "se aproximam" if str(plano["info"]).contains(",") else "se aproxima"])
			"combate":
				if falhou:
					partes.append("[teste] o combate não começou (os inimigos ainda estão longe). " + feedback)
				else:
					partes.append("%s perde a paciência e avança contra Kuzin de arma em punho. O combate começa!" % str(plano["info"]))
	return " ".join(partes)


func _pers_de(tab: Node, nome: String) -> String:
	var c: Vector2i = tab._achar_exato(nome)
	if c == tab.CELULA_INVALIDA:
		return "misterioso"
	return str(tab.ficha_em(c)["conhecimento"].get("personalidade", "misterioso"))


func _descrever_ao_redor(tab: Node) -> String:
	if tab == null or tab.celula_jogador == tab.CELULA_INVALIDA:
		return "Você olha em volta."
	var jog: Vector2i = tab.celula_jogador
	var t: String = "Kuzin está %s." % tab.lugar_texto(jog)
	var perto: Array = []
	for c in tab.pecas.keys():
		if c == jog:
			continue
		perto.append("%s, %s" % [str(tab.ficha_em(c)["nome"]), str(tab._palavra_de_distancia(tab.distancia(jog, c))).split(" (")[0]])
	if not perto.is_empty():
		t += " Pessoas: " + "; ".join(perto) + "."
	var objs: Array = []
	for n in tab.objetos.keys():
		var m: String = str(tab.objetos[n]["modelo"])
		if m == "parede" or m == "muro" or m == "porta":
			continue
		if tab.distancia(jog, tab.objetos[n]["celula"]) <= 5:
			objs.append(str(n))
	if not objs.is_empty():
		t += " Por perto há: " + ", ".join(objs.slice(0, 8)) + "."
	return t


# ---------------------------------------------------------------
# PERGUNTA
# ---------------------------------------------------------------
func responder_pergunta(tab: Node, texto: String) -> String:
	if tab == null:
		return "Não sei responder agora."
	var t: String = tab._normalizar(texto)
	if t.contains("saida") or t.contains("porta") or t.contains("sair"):
		var pr: String = tab.predio_em(tab.celula_jogador)
		if pr == "":
			return "Kuzin está ao ar livre; não há paredes em volta dele."
		var portas: Array = []
		for p in tab.predios[pr]["portas"]:
			portas.append("%s (lado %s)" % [p["rotulo"], p["lado"]])
		return "Em %s as saídas são: %s." % [pr, ", ".join(portas)]
	if t.contains("quem"):
		var nomes: Array = []
		for c in tab.pecas.keys():
			if c != tab.celula_jogador:
				nomes.append("%s (%s)" % [str(tab.ficha_em(c)["nome"]), tab._palavra_de_distancia(tab.distancia(tab.celula_jogador, c))])
		return "Pessoas na cena: " + "; ".join(nomes) + "."
	return _descrever_ao_redor(tab)


# ---------------------------------------------------------------
# CONVERSA COM NPC
# ---------------------------------------------------------------
func responder_npc(tab: Node, nome: String, texto: String, info: Dictionary) -> String:
	var cel: Vector2i = tab._achar_por_nome(nome)
	if cel == tab.CELULA_INVALIDA:
		return "..."
	var c: Dictionary = tab.ficha_em(cel)["conhecimento"]
	var atitude: int = int(info.get("atitude", 0))
	var n: String = tab._normalizar(texto)
	if atitude <= -2:
		return "\"Não tenho nada a dizer a você.\""
	var liberados: Array = info.get("liberados", [])
	if not liberados.is_empty():
		var seg: String = str(liberados[0])
		tab.marcar_segredo_contado(nome, seg)
		return "*olha em volta e baixa a voz* \"Já que confio em você... %s\"" % seg
	for s in ["ola", "oi ", "bom dia", "boa tarde", "boa noite", "saudac"]:
		if (" " + n + " ").contains(s):
			return "\"Olá, viajante. Em que posso ajudar?\" (%s)" % _tom(atitude)
	var sabe: Array = c.get("sabe", [])
	if sabe.is_empty():
		return "\"Hm. Não sei de nada que ajude, forasteiro.\""
	# procura a fala que combina com as palavras da pergunta
	var melhor: String = ""
	var melhor_pontos: int = 0
	for fala in sabe:
		var pontos: int = 0
		for tok in tab._normalizar(str(fala)).split(" "):
			if tok.length() >= 5 and n.contains(tok):
				pontos += 1
		if pontos > melhor_pontos:
			melhor_pontos = pontos
			melhor = str(fala)
	if melhor == "":
		var i: int = int(_fala_idx.get(nome, 0))
		melhor = str(sabe[i % sabe.size()])
		_fala_idx[nome] = i + 1
	return "\"%s\"" % melhor


func _tom(atitude: int) -> String:
	return "simpático" if atitude >= 1 else ("desconfiado" if atitude < 0 else "neutro")
