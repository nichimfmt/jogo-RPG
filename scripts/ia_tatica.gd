extends RefCounted
# ---------------------------------------------------------------
# IA_TATICA.GD - o "cérebro de combate" dos NPCs (estilo Baldur's Gate 3).
#
# COMO FUNCIONA (sistema de PONTUAÇÃO, "utility AI"):
#   1. Lista TODAS as células aonde o NPC consegue chegar neste turno.
#   2. Em cada célula, imagina cada ataque possível contra cada alvo possível.
#   3. Dá uma NOTA para cada combinação (dano esperado, chance de matar, risco,
#      altura, cobertura, distância ideal do arquétipo, etc.).
#   4. Escolhe a combinação com a MAIOR nota.
#
# Para mudar o COMPORTAMENTO de um tipo de NPC, é só mexer nos números de ARQUETIPOS.
# Não precisa ser Autoload: o Tabuleiros.gd carrega este arquivo com preload.
# ---------------------------------------------------------------

const Regras = preload("res://scripts/regras.gd")

# Significado de cada peso:
#   dano      -> quanto vale causar dano esperado
#   abate     -> bônus por ter chance de matar o alvo
#   fraco     -> prefere alvos já feridos
#   jogador   -> bônus por mirar no personagem do jogador
#   baixa_ca  -> prefere alvos com CA baixa (fáceis de acertar)
#   ideal     -> distância (em células) em que o NPC gosta de ficar do inimigo mais próximo
#   dist      -> quanto ele se incomoda de estar longe/perto da distância ideal
#   risco     -> quanto ele tem medo de ficar onde pode ser atacado no próximo turno
#   altura    -> quanto gosta de terreno alto (vantagem)
#   cobertura -> quanto gosta de ter obstáculo entre ele e o inimigo
#   cerco     -> bônus por atacar um alvo que já está cercado por aliados
#   area      -> quanto gosta de acertar vários alvos de uma vez
#   amigo     -> castigo por ferir aliados com magia em área
#   fuga      -> abaixo desta fração de PV (0 a 1) ele foge
const ARQUETIPOS: Dictionary = {
	"brutamontes": {"dano": 1.0, "abate": 8.0, "fraco": 1.0, "jogador": 1.0, "baixa_ca": 0.0, "ideal": 1,
		"dist": 1.2, "risco": 0.12, "altura": 0.3, "cobertura": 0.0, "cerco": 0.8, "area": 1.0, "amigo": 1.5, "fuga": 0.15},
	"arqueiro": {"dano": 1.0, "abate": 8.0, "fraco": 2.0, "jogador": 0.5, "baixa_ca": 0.3, "ideal": 5,
		"dist": 0.9, "risco": 0.9, "altura": 1.5, "cobertura": 1.2, "cerco": 0.0, "area": 1.0, "amigo": 1.5, "fuga": 0.3},
	"mago": {"dano": 1.0, "abate": 8.0, "fraco": 1.5, "jogador": 0.5, "baixa_ca": 0.0, "ideal": 5,
		"dist": 0.9, "risco": 1.3, "altura": 1.0, "cobertura": 1.0, "cerco": 0.0, "area": 2.0, "amigo": 2.5, "fuga": 0.4},
	"covarde": {"dano": 0.6, "abate": 4.0, "fraco": 2.0, "jogador": 0.0, "baixa_ca": 0.3, "ideal": 7,
		"dist": 0.8, "risco": 1.8, "altura": 0.5, "cobertura": 1.0, "cerco": 0.5, "area": 1.0, "amigo": 2.0, "fuga": 1.0},
	"lider": {"dano": 1.0, "abate": 8.0, "fraco": 1.0, "jogador": 1.5, "baixa_ca": 0.0, "ideal": 1,
		"dist": 1.0, "risco": 0.6, "altura": 0.5, "cobertura": 0.3, "cerco": 1.5, "area": 1.0, "amigo": 2.0, "fuga": 0.25},
}

# Peso do "peso morto": quanto o NPC odeia ficar parado à toa ou voltar para células recentes
const CASTIGO_REPETICAO: float = 2.0
const CASTIGO_PARADO: float = 1.0
# Quantas jogadas a mais ele considera na ameaça (um inimigo "alcança" vel + alcance)
const RUIDO: float = 0.25


# Devolve o plano do NPC que está em "origem":
# {
#   "destino": Vector2i, "ataque": Dictionary ({} se não for atacar), "alvo_celula": Vector2i,
#   "pontos": float, "texto": String (explicação), "fugindo": bool,
#   "top": Array (as melhores jogadas, para depuração),
#   "por_celula": Dictionary {célula: melhor nota naquela célula}
# }
static func decidir(tab: Node, origem: Vector2i) -> Dictionary:
	var ficha: Dictionary = tab.ficha_em(origem)
	var arq: Dictionary = ARQUETIPOS.get(str(ficha.get("arquetipo", "brutamontes")), ARQUETIPOS["brutamontes"])
	var intencao: String = str(ficha.get("intencao", "padrao"))
	var plano: Dictionary = {"destino": origem, "ataque": {}, "alvo_celula": tab.CELULA_INVALIDA,
		"pontos": 0.0, "texto": "sem inimigos à vista", "fugindo": false, "top": [], "por_celula": {}}

	# ----- 1. Quem é inimigo e quem é amigo? -----
	var inimigos: Array = []
	var amigos: Array = []
	for c in tab.pecas.keys():
		if c == origem:
			continue
		var f: Dictionary = tab.ficha_em(c)
		if tab.sao_hostis(ficha, f):
			inimigos.append(c)
		elif tab.equipe_de(ficha) != "" and tab.equipe_de(ficha) == tab.equipe_de(f):
			amigos.append(c)
	if inimigos.is_empty():
		return plano

	# ----- 2. Onde ele consegue chegar? -----
	var velocidade: int = int(ficha.get("velocidade", 6))
	var alcance: Dictionary = {origem: 0}
	if intencao != "parado":
		alcance = tab.calcular_alcance(origem, velocidade, true)

	# Mapas de distância (andando, contornando obstáculos) a partir de cada inimigo
	var mapas: Dictionary = {}
	for c in inimigos:
		mapas[c] = tab.mapa_distancias(c)

	var pv: int = int(ficha.get("pv", 1))
	var pv_max: int = maxi(int(ficha.get("pv_max", 1)), 1)
	var fracao_pv: float = float(pv) / float(pv_max)
	var fugindo: bool = intencao == "fugir" or (intencao != "agressivo" and fracao_pv <= float(arq["fuga"]))
	plano["fugindo"] = fugindo

	var ataques: Array = ficha.get("ataques", [])
	var historico: Array = ficha.get("historico", [])

	# ----- 3. Dá nota para cada célula + ataque + alvo -----
	var melhores: Array = []                # todas as jogadas avaliadas (depois ordenamos)
	var por_celula: Dictionary = {}
	for celula in alcance.keys():
		# Quem é o inimigo mais próximo (andando) desta célula?
		var perto_dist: int = 999
		var perto_cel: Vector2i = inimigos[0]
		for ci in inimigos:
			var d: int = int(mapas[ci].get(celula, 999))
			if d < perto_dist:
				perto_dist = d
				perto_cel = ci

		var partes: Dictionary = {}

		# --- distância ideal / fuga ---
		if fugindo:
			partes["fuga"] = float(mini(perto_dist, 30)) * 1.5
		else:
			partes["distancia"] = -float(arq["dist"]) * absf(float(mini(perto_dist, 40)) - float(arq["ideal"]))

		# --- risco: quanto dano ele espera receber se ficar aqui ---
		var perigo: float = _perigo_na_celula(tab, ficha, celula, inimigos, mapas)
		partes["risco"] = -float(arq["risco"]) * perigo * (1.0 + (1.0 - fracao_pv))

		# --- altura e cobertura (contra o inimigo mais próximo) ---
		var dh: int = tab.altura_de(celula) - tab.altura_de(perto_cel)
		partes["altura"] = float(arq["altura"]) * float(clampi(dh, -2, 2)) * 0.8
		if tab.eh_obstaculo(celula + Vector2i(signi(perto_cel.x - celula.x), signi(perto_cel.y - celula.y))) and perto_dist > 1:
			partes["cobertura"] = float(arq["cobertura"]) * 1.0

		# --- repetição / ficar parado ---
		if celula != origem and historico.has(celula):
			partes["repeticao"] = -CASTIGO_REPETICAO
		if celula == origem and intencao != "parado" and not fugindo:
			partes["parado"] = -CASTIGO_PARADO

		partes["ruido"] = randf() * RUIDO

		var base: float = 0.0
		for k in partes.keys():
			base += float(partes[k])

		# Jogada "só andar" (sem atacar)
		var jogada_andar: Dictionary = {"celula": celula, "ataque": {}, "alvo": tab.CELULA_INVALIDA, "pontos": base, "partes": partes}
		melhores.append(jogada_andar)
		por_celula[celula] = maxf(float(por_celula.get(celula, -9999.0)), base)

		# --- ataques a partir desta célula ---
		for ataque in ataques:
			if ataque.has("usos") and int(ataque["usos"]) <= 0:
				continue
			var alvos_possiveis: Array = inimigos
			for alvo_cel in alvos_possiveis:
				var valor: Dictionary = _avaliar_ataque(tab, ficha, arq, celula, ataque, alvo_cel, amigos, inimigos)
				if valor.is_empty():
					continue
				var partes2: Dictionary = partes.duplicate()
				var peso_ataque: float = 0.3 if fugindo else 1.0
				for k in valor.keys():
					partes2[k] = float(valor[k]) * peso_ataque
				var total: float = 0.0
				for k in partes2.keys():
					total += float(partes2[k])
				melhores.append({"celula": celula, "ataque": ataque, "alvo": alvo_cel, "pontos": total, "partes": partes2})
				por_celula[celula] = maxf(float(por_celula.get(celula, -9999.0)), total)

	# ----- 4. Escolhe a melhor jogada -----
	melhores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["pontos"]) > float(b["pontos"]))
	var escolha: Dictionary = melhores[0]
	plano["destino"] = escolha["celula"]
	plano["ataque"] = escolha["ataque"]
	plano["alvo_celula"] = escolha["alvo"]
	plano["pontos"] = escolha["pontos"]
	plano["texto"] = _explicar(ficha, origem, escolha, fugindo)
	plano["top"] = melhores.slice(0, 5)
	plano["por_celula"] = por_celula
	return plano


# Dano esperado que os inimigos conseguiriam causar a este NPC se ele ficasse em "celula".
static func _perigo_na_celula(tab: Node, ficha: Dictionary, celula: Vector2i, inimigos: Array, mapas: Dictionary) -> float:
	var perigo: float = 0.0
	var minha_ca: int = int(ficha.get("ca", 10))
	for ci in inimigos:
		var f: Dictionary = tab.ficha_em(ci)
		var vel: int = int(f.get("velocidade", 6))
		var melhor: float = 0.0
		for atq in f.get("ataques", []):
			if atq.has("usos") and int(atq["usos"]) <= 0:
				continue
			var alc: int = int(atq.get("alcance", 1))
			var d: int = int(mapas[ci].get(celula, 999))
			# Consegue chegar e atacar? (anda "vel" células e depois alcança "alc")
			if d <= vel + alc:
				var chance: float = 1.0 if atq.get("automatico", false) else Regras.chance_de_acerto(int(atq.get("bonus", 0)), minha_ca)
				melhor = maxf(melhor, chance * Regras.media(str(atq.get("dado", "1d4"))))
		perigo += melhor
	return perigo


# Nota de UM ataque, feito da célula "de", contra o alvo em "alvo_cel".
# Devolve {} se o ataque é impossível (fora de alcance, sem linha de visão...).
static func _avaliar_ataque(tab: Node, ficha: Dictionary, arq: Dictionary, de: Vector2i, ataque: Dictionary,
		alvo_cel: Vector2i, amigos: Array, inimigos: Array) -> Dictionary:
	var alcance: int = int(ataque.get("alcance", 1))
	if tab.distancia(de, alvo_cel) > alcance:
		return {}
	if alcance > 1 and not tab.linha_de_visao(de, alvo_cel):
		return {}

	var area: int = int(ataque.get("area", 0))
	var automatico: bool = bool(ataque.get("automatico", false))
	var dado: String = str(ataque.get("dado", "1d4"))
	var dano_medio: float = Regras.media(dado)
	var dano_max: int = Regras.maximo(dado)

	# Bônus de altura (só para ataques à distância)
	var bonus: int = int(ataque.get("bonus", 0))
	if alcance > 1 and tab.altura_de(de) > tab.altura_de(alvo_cel):
		bonus += 1

	var partes: Dictionary = {}
	var afetados: Array = [alvo_cel]
	if area > 0:
		afetados = []
		for c in tab.pecas.keys():
			if c != de and tab.distancia(c, alvo_cel) <= area:
				afetados.append(c)
		# a própria origem também pode ser atingida se estiver perto demais
		if tab.distancia(de, alvo_cel) <= area:
			afetados.append(de)

	var dano_total: float = 0.0
	var abate: float = 0.0
	var prioridade: float = 0.0
	var cerco: float = 0.0
	var acertos: int = 0
	for c in afetados:
		var f: Dictionary
		if c == de:
			f = ficha
		else:
			f = tab.ficha_em(c)
		var hostil: bool = c != de and tab.sao_hostis(ficha, f)
		var chance: float = 1.0 if automatico else Regras.chance_de_acerto(bonus, int(f.get("ca", 10)))
		var esperado: float = chance * dano_medio
		if hostil:
			dano_total += esperado
			acertos += 1
			var pv_alvo: int = int(f.get("pv", 1))
			if dano_medio >= float(pv_alvo):
				abate += chance
			elif float(dano_max) >= float(pv_alvo):
				abate += chance * 0.3
			var fracao_ferida: float = 1.0 - float(pv_alvo) / float(maxi(int(f.get("pv_max", 1)), 1))
			prioridade += float(arq["fraco"]) * fracao_ferida * 4.0
			if str(f.get("lado", "")) == "jogador":
				prioridade += float(arq["jogador"]) * 2.0
			prioridade += float(arq["baixa_ca"]) * float(15 - int(f.get("ca", 10)))
			# cerco: aliados meus colados no alvo (só para ataque corpo a corpo)
			if alcance <= 1:
				for amigo in amigos:
					if tab.distancia(amigo, c) <= 1:
						cerco += float(arq["cerco"])
		else:
			# Magia em área acertando aliado (ou a si mesmo): castigo
			if tab.equipe_de(ficha) != "" and tab.equipe_de(ficha) == tab.equipe_de(f):
				dano_total -= esperado * float(arq["amigo"])

	if acertos == 0:
		return {}
	partes["dano"] = dano_total * float(arq["dano"])
	if area > 0 and acertos >= 2:
		partes["area"] = float(arq["area"]) * float(acertos - 1) * 2.0
	if abate > 0.0:
		partes["abate"] = abate * float(arq["abate"])
	if prioridade != 0.0:
		partes["prioridade"] = prioridade
	if cerco > 0.0:
		partes["cerco"] = minf(cerco, 3.0)
	# Magias com poucos usos custam um pouquinho (guardar para quando valer a pena)
	if ataque.has("usos"):
		partes["gasto"] = -1.5
	return partes


# Texto curto explicando a decisão (aparece no modo de depuração)
static func _explicar(ficha: Dictionary, origem: Vector2i, escolha: Dictionary, fugindo: bool) -> String:
	var nome: String = str(ficha.get("nome", "?"))
	var texto: String = nome
	if fugindo:
		texto += " (FUGINDO)"
	var destino: Vector2i = escolha["celula"]
	if destino == origem:
		texto += " fica em " + str(destino)
	else:
		texto += " vai de " + str(origem) + " para " + str(destino)
	var ataque: Dictionary = escolha["ataque"]
	if ataque.is_empty():
		texto += " sem atacar"
	else:
		texto += " e usa " + str(ataque.get("nome", "ataque")) + " em " + str(escolha["alvo"])
	texto += "  | NOTA %.1f  [" % float(escolha["pontos"])
	var partes: Dictionary = escolha["partes"]
	var itens: Array = []
	for k in partes.keys():
		if k == "ruido":
			continue
		var v: float = float(partes[k])
		if absf(v) >= 0.05:
			itens.append("%s %+.1f" % [k, v])
	texto += ", ".join(itens) + "]"
	return texto
