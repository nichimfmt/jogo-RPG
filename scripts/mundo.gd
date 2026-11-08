extends RefCounted
# ===============================================================
# MUNDO: a "memória do jogo" (quem o jogo sabe, a IA só lê)
#   1) PROPRIEDADES dos itens (o que cada coisa PODE fazer) -> daí saem os verbos do menu de clique
#   2) FICHA DE CONHECIMENTO dos NPCs (o que sabem, o que escondem, como se sentem)
#   3) DIÁRIO da campanha (eventos importantes escritos pelo JOGO)
# Este arquivo NÃO é autoload. O Tabuleiros.gd cria uma instância dele.
# ===============================================================

const ARQUIVO_MUNDO: String = "user://mundo.sav"
const MAX_DIARIO: int = 200
const DIARIO_PARA_IA: int = 12

# ---------------------------------------------------------------
# 1) PROPRIEDADES EXTRAS DOS ITENS (além do que já está em CATALOGO_OBJETOS)
#    dc = dificuldade do teste de dado (usado nas etapas 4 em diante)
# ---------------------------------------------------------------
const PROPRIEDADES_EXTRAS: Dictionary = {
	"porta": {"pode_trancar": true, "arrombar_dc": 15, "quebrar_dc": 20},
	"bau": {"pode_trancar": true, "arrombar_dc": 15, "pode_esconder": true},
	"alcapao": {"pode_trancar": true, "arrombar_dc": 14},
	"barril": {"quebrar_dc": 10, "pode_esconder": true},
	"caixote": {"quebrar_dc": 10, "pode_esconder": true},
	"mesa": {"quebrar_dc": 12},
	"balcao": {"quebrar_dc": 14, "pode_esconder": true},
	"cadeira": {"quebrar_dc": 8},
	"banco": {"quebrar_dc": 8},
	"cama": {"quebrar_dc": 12, "pode_esconder": true},
	"altar": {"quebrar_dc": 18},
	"parede": {"quebrar_dc": 25},
	"muro": {"quebrar_dc": 22},
	"arvore": {"quebrar_dc": 22},
}


func propriedades_de(modelo: String, dados: Dictionary) -> Dictionary:
	var p: Dictionary = {
		"pegavel": bool(dados.get("item", false)),
		"movel": bool(dados.get("movel", false)),
		"bloqueia": bool(dados.get("bloqueia", false)),
		"estados": (dados.get("estados", []) as Array).duplicate(),
		"pode_trancar": false,
		"pode_esconder": false,
		"arrombar_dc": 0,
		"quebrar_dc": 0,
	}
	var extra: Dictionary = PROPRIEDADES_EXTRAS.get(modelo, {})
	for k in extra.keys():
		p[k] = extra[k]
	return p


# Verbos que o MENU DE CLIQUE vai mostrar (etapa 2). Dependem do estado atual do objeto.
func verbos_de(modelo: String, estado: String, trancado: bool, dados: Dictionary) -> Array:
	var p: Dictionary = propriedades_de(modelo, dados)
	var v: Array = ["examinar"]
	var estados: Array = p["estados"]
	if estados.has("aberto") and estados.has("fechado"):
		if estado == "fechado":
			v.append("abrir")
		elif estado == "aberto":
			v.append("fechar")
	if estados.has("aceso") and estados.has("apagado"):
		v.append("apagar" if estado == "aceso" else "acender")
	if bool(p["pegavel"]):
		v.append("pegar")
	elif bool(p["movel"]):
		v.append("empurrar")
	if bool(p["pode_trancar"]):
		if trancado:
			v.append("destrancar")
			v.append("arrombar")
		elif estado == "fechado":
			v.append("trancar")
	if int(p["quebrar_dc"]) > 0 and estado != "quebrado" and estado != "destruido":
		v.append("quebrar")
	if bool(p["pode_esconder"]):
		v.append("vasculhar")
	return v


# ---------------------------------------------------------------
# 2) FICHA DE CONHECIMENTO DOS NPCs
#    sabe: fatos que o NPC pode contar à vontade
#    esconde: fatos que só conta se a atitude em relação a Kuzin for >= "atitude_minima"
#    atitude: de -3 (hostil) a +3 (confia). Começa em 0.
#    (Os textos abaixo são de EXEMPLO: edite à vontade, é o seu roteiro.)
# ---------------------------------------------------------------
const CONHECIMENTO_POR_NOME: Dictionary = {
	"Taberneiro Barnaby": {
		"personalidade": "simpático, falante e um pouco medroso; adora uma boa história",
		"sabe": ["Minha taverna se chama Javali Dourado.",
			"Sirvo cerveja e comida no balcão.",
			"Nos últimos dias goblins foram vistos rondando a vila.",
			"O padeiro Joaquim mora na casa do outro lado da praça."],
		"esconde": [{"fato": "O dinheiro da semana está guardado no Baú da taverna.", "atitude_minima": 2}],
	},
	"Guarda Elara": {
		"personalidade": "séria, desconfiada e leal à vila",
		"sabe": ["Estou de guarda na taverna.",
			"Um orc e goblins estão do lado de fora da vila e eu os considero uma ameaça."],
		"esconde": [{"fato": "Acho que os goblins têm alguém ajudando de dentro da vila.", "atitude_minima": 2}],
	},
	"Padeiro Joaquim": {
		"personalidade": "tímido e trabalhador; assusta fácil",
		"sabe": ["Faço pão na Casa do Padeiro.", "Tenho um saco de farinha e um baú em casa."],
		"esconde": [{"fato": "Estou com muito medo dos goblins e penso em fugir da vila.", "atitude_minima": 1}],
	},
}

const CONHECIMENTO_PADRAO_POR_LADO: Dictionary = {
	"aliado": {"personalidade": "comum", "sabe": ["Rumores comuns da vila."], "esconde": []},
	"neutro": {"personalidade": "reservado", "sabe": [], "esconde": []},
	"inimigo": {"personalidade": "hostil", "sabe": [], "esconde": []},
	"jogador": {"personalidade": "", "sabe": [], "esconde": []},
}


# Devolve a ficha de conhecimento inicial (uma cópia nova) para um personagem
func conhecimento_inicial(nome: String, lado: String) -> Dictionary:
	var base: Dictionary = CONHECIMENTO_POR_NOME.get(nome, CONHECIMENTO_PADRAO_POR_LADO.get(lado, CONHECIMENTO_PADRAO_POR_LADO["neutro"]))
	var c: Dictionary = (base as Dictionary).duplicate(true)
	c["atitude"] = -2 if lado == "inimigo" else 0
	c["revelado"] = []           # segredos que o NPC já contou (etapa 3)
	return c


func descricao_da_atitude(atitude: int) -> String:
	if atitude <= -2:
		return "hostil"
	if atitude == -1:
		return "desconfiado"
	if atitude == 0:
		return "neutro"
	if atitude == 1:
		return "simpático"
	return "confia em Kuzin"


# Texto sobre UM npc para o Mestre (será usado quando Kuzin conversar com ele)
func descrever_npc(nome: String, ficha: Dictionary) -> String:
	var c: Dictionary = ficha.get("conhecimento", {})
	if c.is_empty():
		return "%s: sem informações." % nome
	var t: String = "%s (%s). Personalidade: %s. Atitude em relação a Kuzin: %s.\n" % [nome, str(ficha.get("classe", "")), str(c.get("personalidade", "")), descricao_da_atitude(int(c.get("atitude", 0)))]
	var sabe: Array = c.get("sabe", [])
	t += "  Sabe e pode contar: " + (" | ".join(sabe) if not sabe.is_empty() else "nada de especial.") + "\n"
	var esconde: Array = c.get("esconde", [])
	for e in esconde:
		var contado: bool = (c.get("revelado", []) as Array).has(str(e["fato"]))
		t += "  Segredo (%s): %s [só conta se a atitude for %d ou mais]\n" % ["JÁ CONTOU" if contado else "ainda guardado", str(e["fato"]), int(e["atitude_minima"])]
	return t


# Ficha para a IA falar COMO o NPC. Segredos que ainda não foram liberados NÃO aparecem aqui:
# a IA não pode vazar o que não sabe.
func ficha_para_conversa(nome: String, ficha: Dictionary) -> String:
	var c: Dictionary = ficha.get("conhecimento", {})
	var atitude: int = int(c.get("atitude", 0))
	var t: String = "VOCÊ É %s (%s). Personalidade: %s. Sua atitude em relação a Kuzin: %s.\n" % [nome, str(ficha.get("classe", "")), str(c.get("personalidade", "")), descricao_da_atitude(atitude)]
	var sabe: Array = c.get("sabe", [])
	t += "O QUE VOCÊ SABE: " + (" | ".join(sabe) if not sabe.is_empty() else "nada de especial; só conversa comum.") + "\n"
	for e in c.get("esconde", []):
		if atitude >= int(e["atitude_minima"]):
			t += "SEGREDO QUE VOCÊ PODE CONTAR AGORA (se fizer sentido na conversa): %s\n" % str(e["fato"])
	return t


# ---------------------------------------------------------------
# 3) DIÁRIO DA CAMPANHA
# ---------------------------------------------------------------
var diario: Array = []          # [{n, tipo, texto}]
var _contador: int = 0


func registrar(tipo: String, texto: String) -> void:
	_contador += 1
	diario.append({"n": _contador, "tipo": tipo, "texto": texto})
	while diario.size() > MAX_DIARIO:
		diario.pop_front()


func ultimos(quantos: int) -> Array:
	var inicio: int = maxi(diario.size() - quantos, 0)
	return diario.slice(inicio)


# Texto que vai junto em TODO pedido ao Mestre
func diario_para_ia() -> String:
	if diario.is_empty():
		return ""
	var t: String = "DIÁRIO DA CAMPANHA (o que JÁ ACONTECEU, do mais antigo ao mais novo; é a verdade sobre o passado, não contradiga):\n"
	for e in ultimos(DIARIO_PARA_IA):
		t += "- #%d [%s] %s\n" % [int(e["n"]), str(e["tipo"]), str(e["texto"])]
	return t


func diario_completo() -> String:
	if diario.is_empty():
		return "O diário está vazio."
	var linhas: Array = []
	for e in diario:
		linhas.append("#%d [%s] %s" % [int(e["n"]), str(e["tipo"]), str(e["texto"])])
	return "\n".join(linhas)


func para_salvar() -> Dictionary:
	return {"diario": diario, "contador": _contador}


func carregar_de(dados: Dictionary) -> void:
	diario = (dados.get("diario", []) as Array).duplicate(true)
	_contador = int(dados.get("contador", diario.size()))
