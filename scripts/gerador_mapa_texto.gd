extends RefCounted
# ---------------------------------------------------------------
# GERADOR_MAPA_TEXTO.GD - lê um MAPA FEITO À MÃO (arquivo .txt em res://mapas/) e monta o mundo.
# O formato está explicado dentro de res://mapas/vila_exemplo.txt.
# Devolve a "premissa" (texto para o Mestre) ou "" se algo deu errado.
# ---------------------------------------------------------------

const Gerador = preload("res://scripts/gerador_cenas.gd")

const DENSIDADE_FLORESTA: float = 0.45


# Divide uma linha em palavras, respeitando "textos entre aspas"
static func _palavras(linha: String) -> Array:
	var lista: Array = []
	var atual: String = ""
	var aspas: bool = false
	for ch in linha:
		if ch == '"':
			aspas = not aspas
		elif ch == " " and not aspas:
			if atual != "":
				lista.append(atual)
				atual = ""
		else:
			atual += ch
	if atual != "":
		lista.append(atual)
	return lista


static func carregar(tab: Node, caminho: String, semente: int) -> String:
	if not FileAccess.file_exists(caminho):
		push_warning("Mapa manual não encontrado: " + caminho)
		return ""
	var arq := FileAccess.open(caminho, FileAccess.READ)
	var linhas: PackedStringArray = arq.get_as_text().split("\n")
	arq.close()

	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var premissa: String = "Kuzin chega a um lugar desconhecido."
	var largura: int = 0
	var profundidade: int = 0
	var desenho: Array = []
	var comandos: Array = []
	var lendo_mapa: bool = false
	for bruta in linhas:
		var l: String = bruta.strip_edges(false, true).replace("\r", "")
		if lendo_mapa:
			if l.strip_edges() != "":
				desenho.append(l)
			continue
		var t: String = l.strip_edges()
		if t == "" or t.begins_with("#"):
			continue
		if t == "@mapa":
			lendo_mapa = true
			continue
		if t.begins_with("@premissa"):
			premissa = t.substr(9).strip_edges()
		elif t.begins_with("@tamanho"):
			var p: Array = _palavras(t)
			if p.size() >= 3:
				largura = int(p[1])
				profundidade = int(p[2])
		else:
			comandos.append(t)

	if not desenho.is_empty():
		profundidade = maxi(profundidade, desenho.size())
		for l2 in desenho:
			largura = maxi(largura, (l2 as String).length())
	if largura < 20 or profundidade < 20:
		push_warning("Mapa manual: tamanho inválido (%dx%d). Use @tamanho ou @mapa." % [largura, profundidade])
		return ""
	tab.redimensionar_tabuleiro(largura, profundidade)
	tab.zonas.clear()

	# --- chão desenhado ---
	var arvores_extra: Array = []
	for z in range(desenho.size()):
		var linha: String = desenho[z]
		for x in range(linha.length()):
			var c := Vector2i(x, z)
			match linha[x]:
				"f":
					tab.zonas[c] = "floresta"
					if rng.randf() < DENSIDADE_FLORESTA:
						arvores_extra.append(["arvore", c])
				"v":
					tab.zonas[c] = "vila"
				"p":
					tab.zonas[c] = "praça"
				"=":
					tab.zonas[c] = "estrada"
				"a":
					tab.zonas[c] = "acampamento"
				"T":
					arvores_extra.append(["arvore", c])
				"o":
					arvores_extra.append(["pedra", c])
				"#":
					arvores_extra.append(["muro", c])

	# --- comandos: prédios primeiro (precisam de espaço livre) ---
	for t2 in comandos:
		var p2: Array = _palavras(t2)
		if p2.is_empty() or str(p2[0]) != "@predio" or p2.size() < 6:
			continue
		var ref := Vector2i(int(p2[3]), int(p2[4]))
		if p2.size() >= 9 and str(p2[6]) == "olhando":
			Gerador.virar_para = Vector2i(int(p2[7]), int(p2[8]))
		var r: Dictionary = Gerador.gerar_predio(tab, str(p2[1]), str(p2[2]), ref, str(p2[5]), [], rng.randi())
		Gerador.virar_para = Vector2i(-9999, -9999)
		if not bool(r["ok"]):
			push_warning("Mapa manual: não consegui montar '%s': %s" % [str(p2[2]), str(r["motivo"])])

	# --- objetos soltos, árvores, pedras e muros do desenho ---
	for t3 in comandos:
		var p3: Array = _palavras(t3)
		if p3.size() >= 5 and str(p3[0]) == "@objeto":
			if not tab.criar_objeto(str(p3[2]), str(p3[1]), Vector2i(int(p3[3]), int(p3[4]))):
				push_warning("Mapa manual: objeto '%s' não coube: %s" % [str(p3[2]), str(tab.ultimo_motivo)])
	tab.iniciar_lote()
	var n_arv: int = 0
	var n_ped: int = 0
	var n_muro: int = 0
	for item in arvores_extra:
		var modelo: String = str(item[0])
		var cel: Vector2i = item[1]
		if tab.predio_em(cel) != "" or tab.eh_obstaculo(cel):
			continue
		var nome: String = "Árvore %d" % (n_arv + 1) if modelo == "arvore" else ("Pedra %d" % (n_ped + 1) if modelo == "pedra" else "Muro %d" % (n_muro + 1))
		if tab.criar_objeto(nome, modelo, cel):
			if modelo == "arvore":
				n_arv += 1
			elif modelo == "pedra":
				n_ped += 1
			else:
				n_muro += 1
	tab.finalizar_lote()

	# --- personagens ---
	var cel_kuzin: Vector2i = Vector2i(largura / 2, profundidade / 2)
	for t4 in comandos:
		var p4: Array = _palavras(t4)
		if p4.size() >= 3 and str(p4[0]) == "@kuzin":
			cel_kuzin = Vector2i(int(p4[1]), int(p4[2]))
	if not tab.colocar_personagem(cel_kuzin, "Kuzin", "kuzin", "jogador"):
		push_warning("Mapa manual: não deu para colocar o Kuzin em %s (ocupado?)" % str(cel_kuzin))
	for t5 in comandos:
		var p5: Array = _palavras(t5)
		if p5.size() >= 6 and str(p5[0]) == "@npc":
			var classe: String = str(p5[6]) if p5.size() >= 7 else ""
			if not tab.colocar_personagem(Vector2i(int(p5[4]), int(p5[5])), str(p5[3]), str(p5[1]), str(p5[2]), classe):
				push_warning("Mapa manual: NPC '%s' não coube: %s" % [str(p5[3]), str(tab.ultimo_motivo)])

	# --- conhecimento dos NPCs ---
	for t6 in comandos:
		if not t6.begins_with("@conhece"):
			continue
		var dois: PackedStringArray = t6.split(":", true, 1)
		if dois.size() < 2:
			continue
		var cab: Array = _palavras(dois[0])            # @conhece "Nome" tipo [n]
		var texto: String = dois[1].strip_edges()
		if cab.size() < 3:
			continue
		var cel_npc: Vector2i = tab._achar_por_nome(str(cab[1]))
		if cel_npc == tab.CELULA_INVALIDA:
			push_warning("Mapa manual: @conhece de '%s', mas esse personagem não existe." % str(cab[1]))
			continue
		var con: Dictionary = tab.ficha_em(cel_npc)["conhecimento"]
		match str(cab[2]):
			"personalidade":
				con["personalidade"] = texto
			"sabe":
				(con["sabe"] as Array).append(texto)
			"segredo":
				var minimo: int = int(cab[3]) if cab.size() >= 4 else 2
				(con["esconde"] as Array).append({"fato": texto, "atitude_minima": maxi(minimo, 1)})

	print("Mapa manual '", caminho, "': ", largura, "x", profundidade, ", ", n_arv, " árvores, ", tab.predios.size(), " construções.")
	return premissa
