extends RefCounted

const ARGUMENTO: String = "--teste-taverna"
const TAVERNA: String = "Taverna da Lanterna"
const DEPOSITO: String = "Depósito"
const MIRA: String = "Mira"
const INES: String = "Inês"
const TROCA_DE_POSTO: int = 17 * 60
const OBJETIVO: String = "Descobrir quem deixou o bilhete."
const PISTA: String = "O remetente foi o barqueiro. Ele deixou o bilhete e espera na ponte."

var caminho_encontrado: String = ""


func montar(tab: Node) -> String:
	tab.minutos_do_mundo = 16 * 60 + 55
	for x in range(28, 55):
		for z in range(28, 52):
			tab.definir_zona(Vector2i(x, z), "vila")
	for x in range(35, 44):
		for z in range(38, 44):
			tab.definir_zona(Vector2i(x, z), "praça")
	tab.pintar_chao()

	tab.construir_predio(TAVERNA, "taverna", Vector2i(30, 30), 10, 8, "sul")
	tab.construir_predio(DEPOSITO, "casa", Vector2i(36, 46), 7, 6, "norte")
	tab.criar_objeto("Balcão", "balcao", Vector2i(32, 32))
	tab.criar_objeto("Barril 1", "barril", Vector2i(32, 36))
	tab.criar_objeto("Barril 2", "barril", Vector2i(33, 36))
	tab.criar_objeto("Caixote do depósito", "caixote", Vector2i(40, 49))

	tab.colocar_personagem(Vector2i(34, 35), "Kuzin", "kuzin", "jogador")
	tab.colocar_personagem(Vector2i(33, 33), MIRA, "aldeao", "neutro", "Taberneira")
	var posto_antigo := Vector2i(36, 40)
	tab.colocar_personagem(posto_antigo, INES, "guarda", "aliado", "Guarda da vila")
	tab.definir_agenda(posto_antigo, [[0, posto_antigo, "vigia a praça"], [TROCA_DE_POSTO, Vector2i(40, 41), "confere os recados da ponte"]])

	for z in range(33, 39):
		tab.criar_objeto("Muro do vigia %d" % z, "muro", Vector2i(46, z))
	tab.colocar_personagem(Vector2i(49, 36), "Risco", "goblin_arqueiro", "inimigo")
	return "O sino da praça está para tocar. Na Taverna da Lanterna, Mira, a taberneira, separa os papéis do dia. Você traz um bilhete anônimo que diz: “Na ponte, ao cair da tarde”. No verso, ainda dá para ver um pedaço de carimbo.\n\nObjetivo: " + OBJETIVO


func objetivo_texto() -> String:
	if caminho_encontrado == "":
		return "Objetivo: " + OBJETIVO
	return "Objetivo concluído: você descobriu quem deixou o bilhete."


func normalizar_acao(tab: Node, texto: String) -> String:
	var acao: String = " ".join(tab._normalizar(texto).strip_edges().rstrip(".!?").split(" ", false)).trim_prefix("eu ")
	if acao.begins_with("motro o bilhete"):
		return "mostro" + acao.substr(5)
	return acao


func responder_pergunta(tab: Node, texto: String) -> String:
	var pedido: String = normalizar_acao(tab, texto)
	match pedido:
		"qual e o objetivo", "qual o objetivo", "o que eu tenho que fazer", "o que tenho que fazer", "o que faco agora":
			if caminho_encontrado != "":
				return "Você identificou o remetente. O encontro na ponte é o gancho para a próxima cena. A investigação da taverna terminou."
			return objetivo_texto() + " Mira está separando papéis perto do balcão, e o verso do bilhete tem parte de um carimbo."
		"onde esta a guarda", "onde esta o guarda", "onde esta ines", "tem algum guarda", "tem alguma guarda", "vejo algum guarda", "procuro um guarda", "procuro uma guarda", "procuro a guarda":
			var celula: Vector2i = tab._achar_exato(INES)
			if celula == tab.CELULA_INVALIDA or not tab.alvo_visivel(celula):
				return "Você não vê nenhum guarda daqui. Está procurando alguém em particular ou quer pedir ajuda?"
			var onde: String = "Você vê Inês %s. Ela %s." % [tab.lugar_texto(celula), tab.ficha_em(celula)["atividade"]]
			return onde + " Você quer pedir ajuda ou acompanhar o que ela faz?" if pedido.begins_with("procuro") else onde
	return ""


func resposta_npc(tab: Node, nome: String, texto: String) -> String:
	var pedido: String = normalizar_acao(tab, texto)
	match nome:
		MIRA:
			if pedido.contains("deposito") or pedido.contains("carimbo"):
				return "O depósito fica ao sul da praça. Os papéis de frete ficam entre os caixotes."
			if pedido.contains("ronda") or pedido.contains("guarda") or pedido.contains("ines"):
				return "Inês muda de posto quando o sino bate às 17h. Ela confere os recados da ponte perto do depósito."
			if pedido.contains("bilhete"):
				if caminho_encontrado != "":
					return "É do barqueiro. Ele desenha um remo nos papéis que deixa por aqui."
				return "Posso tentar reconhecer a letra se você me mostrar o bilhete. Inês confere os recados da ponte depois do sino das 17h. Se o verso tiver um carimbo de frete, pode ter vindo do depósito."
			return "Boa tarde. Estou separando as contas dos fregueses. Posso ajudar com alguma coisa?"
		INES:
			if pedido.contains("ronda") or pedido.contains("recado") or pedido.contains("bilhete"):
				if int(tab.agendas[INES]["passo"]) == 0:
					return "Confiro os recados da ponte quando troco de posto, às 17h. Por enquanto fico aqui na praça."
				return "Acabei de conferir os recados da ponte. Estão aqui junto ao meu posto."
			return "Boa tarde. Precisa de ajuda na praça?"
	return ""


func resolver(tab: Node, texto: String) -> Dictionary:
	var acao: String = normalizar_acao(tab, texto)
	match acao:
		"leio o bilhete", "examino o bilhete", "olho o bilhete", "olho o verso do bilhete", "examino o verso do bilhete", "leio o verso do bilhete":
			return {"ok": true, "texto": "Na frente, lê-se “Na ponte, ao cair da tarde”. No verso há um carimbo cortado. As palavras “depósito” e “frete” ainda estão legíveis."}
		"mostro o bilhete a mira", "mostro o bilhete para mira", "mostro o bilhete pra mira", "mostro o bilhete a taberneira", "mostro meu bilhete a mira":
			var impedimento: String = tab.pode_conversar_com(MIRA)
			if impedimento != "":
				return _falha(impedimento + " Você pode clicar perto dela ou escrever “vou até Mira”.")
			return _revelar(tab, "Mira", 5, "Mira olha o papel. “Conheço essa letra. É do barqueiro. Ele sempre desenha um remo nas contas.”")
		"observo a guarda", "observo o guarda", "observo ines", "observo a guarda ines", "vejo o que ines faz":
			var celula: Vector2i = tab._achar_exato(INES)
			if celula == tab.CELULA_INVALIDA or not tab.alvo_visivel(celula):
				return _falha("Você não vê nenhum guarda daqui. Está procurando alguém em particular ou quer pedir ajuda?")
			if tab.distancia(tab.celula_jogador, celula) > 3:
				return _falha("Você vê Inês, mas está longe demais para acompanhar o que ela faz. Pode escrever “vou até Inês”.")
			if int(tab.agendas[INES]["passo"]) != 1:
				return _falha("Inês ainda vigia o posto antigo na praça. Ela olha para o sino, que toca na troca de turno, às 17h.")
			return _revelar(tab, "ronda", 1, "No novo posto, Inês confere uma marca de remo. Ao lado dela, há um recado assinado pelo barqueiro com o mesmo convite para a ponte.")
		"vasculho o deposito", "procuro no deposito", "procuro uma pista no deposito", "procuro o rascunho no deposito":
			if tab.predio_em(tab.celula_jogador) != DEPOSITO:
				return _falha("Entre no depósito antes de vasculhá-lo.")
			return _revelar(tab, "depósito", 10, "Entre os caixotes, você encontra o rascunho do bilhete com a assinatura do barqueiro.")
	return {}


func _revelar(tab: Node, caminho: String, minutos: int, achado: String) -> Dictionary:
	if caminho_encontrado != "":
		return _falha("Você já identificou o remetente. Digite /diario para rever a pista.")
	caminho_encontrado = caminho
	tab.avancar_relogio(minutos)
	tab.registrar_evento("pista", PISTA + " Caminho: " + caminho + ".")
	return {"ok": true, "texto": achado + "\n\n" + PISTA + "\n\n" + objetivo_texto() + " A investigação da taverna terminou. Digite /diario para rever a pista."}


func _falha(frase: String) -> Dictionary:
	return {"ok": false, "texto": frase}
