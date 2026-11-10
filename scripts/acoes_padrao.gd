extends RefCounted
# ---------------------------------------------------------------
# ACOES_PADRAO.GD - o "juiz de mesa" do JOGO (funciona SEM IA).
#
# O jogador escreve, por exemplo: "empurro a mesa e abro a porta".
# Este arquivo faz, para cada pedaço do texto:
#   1) IDENTIFICAR a ação (palavras-chave) e o alvo (nomes que existem no tabuleiro);
#   2) VALIDAR: o alvo existe? está ao lado? a ação é possível nesse objeto?
#   3) ROLAR o d20 quando o resultado é incerto (arrombar, quebrar, procurar, persuadir...);
#   4) APLICAR no tabuleiro e devolver o resultado como frase pronta.
# Se algum passo falha, NADA acontece e o jogo diz o porquê (como um mestre de mesa).
# A IA (se estiver ligada) só recebe o resultado para NARRAR; ela nunca decide o fato.
#
# Para ensinar uma palavra nova ao jogo, basta incluí-la na lista VERBOS abaixo
# (sem acento, em minúsculas).
# ---------------------------------------------------------------

const VERBOS: Dictionary = {
	"abrir": ["abro", "abrir", "abre", "abrindo"],
	"fechar": ["fecho", "fechar", "fecha"],
	"acender": ["acendo", "acender"],
	"apagar": ["apago", "apagar"],
	"pegar": ["pego", "pegar", "apanho", "apanhar", "recolho", "recolher"],
	"soltar": ["solto", "soltar", "largo", "largar"],
	"empurrar": ["empurro", "empurrar", "arrasto", "arrastar"],
	"trancar": ["tranco", "trancar"],
	"destrancar": ["destranco", "destrancar"],
	"arrombar": ["arrombo", "arrombar", "forco"],
	"quebrar": ["quebro", "quebrar", "destruo", "destruir", "derrubo"],
	"vasculhar": ["procuro", "procurar", "vasculho", "vasculhar", "reviro", "investigo", "investigar"],
	"examinar": ["examino", "examinar", "olho", "observo", "inspeciono", "analiso"],
	"persuadir": ["persuado", "persuadir", "convenco", "convencer"],
	"intimidar": ["intimido", "intimidar", "ameaco", "ameacar"],
	"enganar": ["engano", "enganar", "minto", "blefo"],
	"esconder": ["escondo", "esconder"],
	"atacar": ["ataco", "atacar", "golpeio", "golpear", "esfaqueio"],
}
const VERBOS_SOCIAIS: Array[String] = ["persuadir", "intimidar", "enganar"]
const VOZ_MAXIMA: int = 3                 # distância máxima para persuadir/intimidar/enganar


# Devolve {"entendeu": bool, "linhas": [frases para o jogador], "fato": "FATO DO JOGO: ...", "algum_ok": bool}
static func separar(texto: String) -> PackedStringArray:
	if texto.contains("\"") or texto.contains("“"):
		return PackedStringArray([texto])
	for separador in [",", ";", " depois ", " então ", " entao ", " e "]:
		texto = texto.replace(separador, "|")
	return texto.split("|", false)


static func tentar(tab: Node, texto: String) -> Dictionary:
	var vazio: Dictionary = {"entendeu": false, "linhas": [], "fato": "", "algum_ok": false}
	if tab == null or tab.celula_jogador == tab.CELULA_INVALIDA or tab.modo == "combate":
		return vazio
	if texto.contains("\"") or texto.contains("“"):
		return vazio                                  # entre aspas = fala, não ação
	var linhas: Array = []
	var fatos: Array = []
	var algum_ok: bool = false
	var entendeu: bool = false
	for pedaco in separar(texto):
		var clausula: String = " " + tab._normalizar(pedaco.strip_edges().rstrip(".!?")) + " "
		if clausula.contains(" nao ") or clausula.contains(" nunca ") or clausula.contains(" sem "):
			continue
		var verbo: String = _achar_verbo(clausula)
		if verbo == "":
			continue
		var r: Dictionary = _executar(tab, verbo, clausula)
		if r.is_empty():
			r = {"ok": false, "texto": "Não encontrei um alvo para %s. Diga o nome do alvo." % verbo}
		if bool(r["ok"]) or bool(r.get("rolou", false)):
			tab.avancar_relogio(5 if verbo in VERBOS_SOCIAIS or verbo == "vasculhar" else 1)
		entendeu = true
		linhas.append(str(r["texto"]))
		fatos.append(str(r["texto"]).replace("Você ", "Kuzin ").replace("você ", "Kuzin ") + ("" if bool(r["ok"]) else " (NADA ACONTECEU)"))
		if bool(r["ok"]):
			algum_ok = true
			if tab.modo == "combate":
				break
		else:
			break                                     # a ação falhou: o que viria depois não acontece
	if not entendeu:
		return vazio
	return {"entendeu": true, "linhas": linhas, "fato": "FATO DO JOGO: " + " ".join(fatos), "algum_ok": algum_ok}


static func _achar_verbo(clausula: String) -> String:
	var palavras: PackedStringArray = clausula.split(" ", false)
	for p in palavras:
		for v in VERBOS.keys():
			if (VERBOS[v] as Array).has(p):
				return str(v)
	return ""


static func _executar(tab: Node, verbo: String, clausula: String) -> Dictionary:
	var eu: String = str(tab.ficha_em(tab.celula_jogador)["nome"])
	# ---- ações que dependem de uma PESSOA ----
	if VERBOS_SOCIAIS.has(verbo) or verbo == "atacar":
		var npc: String = tab.npc_citado_no_texto(clausula, verbo == "atacar")
		if npc == "":
			return {}
		return _acao_com_pessoa(tab, verbo, npc)
	if verbo == "examinar":
		var npc2: String = tab.npc_citado_no_texto(clausula, true)
		if npc2 != "":
			var cel: Vector2i = tab._achar_por_nome(npc2)
			if not tab.alvo_visivel(cel):
				return {"ok": false, "texto": "Você não consegue ver %s daqui." % npc2}
			return {"ok": true, "texto": "Você observa %s (%s)." % [npc2, tab.titulo_publico(tab.ficha_em(cel))]}
	# ---- ações da própria pessoa ----
	if verbo == "esconder":
		return _esconder(tab)
	# ---- ações com OBJETO ----
	var alvo: String = _achar_objeto(tab, clausula, verbo, eu)
	if alvo == "":
		if verbo == "vasculhar":
			var dado: Dictionary = tab._rolar_d20(2, 12)
			tab.log_de_combate.emit("🎲 " + str(dado["texto"]))
			return {"ok": true, "texto": "🎲 %s: %s" % [dado["texto"], "você olha em volta com atenção e não percebe nada fora do comum." if bool(dado["ok"]) else "você não percebe nada de especial."]}
		return {}
	if verbo != "examinar" and verbo != "soltar" and not (tab.verbos_do_objeto(alvo) as Array).has(verbo):
		return {"ok": false, "texto": "Você não consegue %s %s (%s)." % [verbo, alvo, str(tab.objetos[alvo]["estado"])]}
	var r: Dictionary = tab.executar_verbo_objeto(alvo, verbo)
	if bool(r["rolou"]):
		tab.log_de_combate.emit(str(r["texto"]))
	return r


# Qual objeto o jogador citou? (o mais perto dele, entre os que combinam com o texto)
static func _achar_objeto(tab: Node, clausula: String, verbo: String, eu: String) -> String:
	var melhor_pos: int = 9999
	var melhor_var: String = ""
	var candidatos: Array = []
	for n in tab.objetos.keys():
		var o: Dictionary = tab.objetos[n]
		var m: String = str(o["modelo"])
		if m == "parede" or m == "muro" or m == "arvore":
			continue
		var dono: String = str(o["dono"])
		if dono != "" and not (dono == eu and (verbo == "soltar" or verbo == "examinar")):
			continue
		if dono == "" and verbo == "soltar":
			continue
		var busca: String = str(n)
		for pn in tab.predios.keys():
			busca = busca.replace(" de " + str(pn), "")
		candidatos.append([str(n), tab._variantes_do_nome(busca)])
	for c in candidatos:
		for v in c[1]:
			var pos: int = clausula.find(" " + str(v))
			if pos >= 0 and (pos < melhor_pos or (pos == melhor_pos and str(v).length() > melhor_var.length())):
				melhor_pos = pos
				melhor_var = str(v)
	if melhor_var == "":
		return ""
	var escolhido: String = ""
	var melhor_d: int = 9999
	for c in candidatos:
		if not (c[1] as Array).has(melhor_var):
			continue
		var d: int = tab.distancia(tab.celula_jogador, tab.objetos[c[0]]["celula"])
		if str(tab.objetos[c[0]]["dono"]) == eu:
			d = 0
		if d < melhor_d:
			melhor_d = d
			escolhido = str(c[0])
	return escolhido


static func _acao_com_pessoa(tab: Node, verbo: String, npc: String) -> Dictionary:
	var cel: Vector2i = tab._achar_por_nome(npc)
	if cel == tab.CELULA_INVALIDA:
		return {}
	var f: Dictionary = tab.ficha_em(cel)
	if verbo == "atacar":
		if not tab.sao_hostis(tab.ficha_em(tab.celula_jogador), f):
			return {"ok": false, "texto": "%s não é um inimigo." % npc}
		if tab.melhor_ataque(tab.celula_jogador, cel).is_empty():
			return {"ok": false, "texto": "%s está fora do alcance ou da linha de visão do seu ataque." % npc}
		if not tab.iniciar_combate("Kuzin atacou %s" % npc, "jogo"):
			return {"ok": false, "texto": "Você não pode atacar %s agora (%s)." % [npc, str(tab.ultimo_motivo)]}
		return {"ok": true, "texto": "Você parte para cima de %s. O combate começou!" % npc}
	var dist: int = tab.distancia(tab.celula_jogador, cel)
	if dist > VOZ_MAXIMA or not tab.linha_de_visao(tab.celula_jogador, cel):
		return {"ok": false, "texto": "%s está longe demais (a %d células). Aproxime-se primeiro; nada aconteceu." % [npc, dist]}
	var con: Dictionary = f["conhecimento"]
	var atitude: int = int(con.get("atitude", 0))
	var cd: int = 15 - 2 * atitude if verbo == "persuadir" else (14 if verbo == "intimidar" else 14 - atitude)
	var r: Dictionary = tab._rolar_d20(2, clampi(cd, 6, 22))
	var ok: bool = bool(r["ok"])
	var delta: int = 0
	var frase: String = ""
	match verbo:
		"persuadir":
			delta = 1 if ok else 0
			frase = "%s se deixa convencer um pouco." % npc if ok else "%s não se convence." % npc
		"intimidar":
			delta = -1
			frase = "%s se assusta, mas fica ressentido(a)." % npc if ok else "%s não se intimida e fica irritado(a)." % npc
		"enganar":
			delta = 0 if ok else -1
			frase = "%s acredita no que você disse." % npc if ok else "%s percebe a mentira e desconfia de você." % npc
	con["atitude"] = clampi(atitude + delta, -3, 3)
	tab.registrar_evento("conversa", "Kuzin tentou %s %s (%s). Atitude: %d." % [verbo, npc, "conseguiu" if ok else "falhou", int(con["atitude"])])
	var txt: String = "🎲 %s: %s %s" % [r["texto"], "sucesso!" if ok else "falhou.", frase]
	tab.log_de_combate.emit(txt)
	return {"ok": ok, "texto": txt, "rolou": true}


static func _esconder(tab: Node) -> Dictionary:
	var jog: Vector2i = tab.celula_jogador
	var cobertura: String = ""
	if tab.predio_em(jog) != "":
		cobertura = "as sombras de dentro do lugar"
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var c: Vector2i = jog + Vector2i(dx, dz)
			if c != jog and tab.eh_obstaculo(c):
				cobertura = "os obstáculos ao redor"
	if cobertura == "":
		return {"ok": false, "texto": "Não há cobertura por perto para você se esconder; nada aconteceu."}
	var r: Dictionary = tab._rolar_d20(2, 12)
	var ok: bool = bool(r["ok"])
	var txt: String = "🎲 %s: %s" % [r["texto"], ("sucesso! Você se esconde usando %s." % cobertura) if ok else "falhou. Alguém poderia te ver."]
	tab.log_de_combate.emit(txt)
	return {"ok": ok, "texto": txt, "rolou": true}
