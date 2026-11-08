extends Node
# ---------------------------------------------------------------
# MESTRE_IA.GD  (Autoload com o nome EXATO: MestreIA)
# O Mestre é a IA de TEXTO (llama-server local). Ele:
#   - narra o que o jogador faz e o que os NPCs fizeram;
#   - manda comandos de MUNDO (criar objeto, dar item, abrir porta, mudar intenção de NPC);
#   - NÃO rola dados e NÃO decide o combate (isso é do código: regras.gd e ia_tatica.gd).
# ---------------------------------------------------------------

signal status_mudou(texto: String)
signal mestre_pronto()
signal ocupado_mudou(ocupado: bool)
signal mestre_falou(texto: String)

const SERVIDOR_WINDOWS: String = "llama_bin/llama/llama-server.exe"
const SERVIDOR_LINUX: String = "llama_bin/llama/llama-server"
const MODELO: String = "models/llama-3.2-3b-instruct-q4_k_m.gguf"
const PORTA: int = 8765
const CONTEXTO: int = 8192
const MAX_TOKENS_RESPOSTA: int = 700
const TEMPERATURA: float = 0.8
const MENSAGENS_NO_HISTORICO: int = 10
const MAX_FATOS: int = 25
const ARQUIVO_CAMPANHA: String = "user://campanha.json"
const MAX_COMANDOS: int = 6

const PREMISSA: String = "Kuzin, meio-elfo ladino de nível 3, está dentro da grande Taverna Javali Dourado, na vila de Vale Sereno, na véspera da Feira da Colheita. O taberneiro Barnaby está atrás do balcão e a Guarda Elara perto das mesas. Na praça lá fora estão o meio-orc Tharok, o Chefe Goblin e um Goblin Arqueiro em cima de um morro, ameaçando a vila. Do outro lado da praça fica a casa do padeiro Joaquim."

const REGRAS_DO_MESTRE: String = """Você é o Mestre de um RPG de mesa, em português do Brasil. Fale como um mestre de verdade numa mesa: natural, vivo e direto, em 2 a 4 frases.
COMO NARRAR:
- Nunca diga coordenadas, números de célula nem distâncias em números. Descreva em linguagem natural ("junto ao balcão", "perto da porta", "do outro lado da rua"). As coordenadas do estado servem só para você escolher os comandos.
- Se o jogador FAZ uma pergunta (onde estou? quem está aqui? o que vejo?), responda como um mestre responderia a uma dúvida: direto, dizendo o que Kuzin percebe, com detalhes úteis (onde ele está, quem está por perto e o que está fazendo). Sem comandos.
- Use SOMENTE lugares, objetos e personagens que existem no estado. Não invente lugares novos.
- Nunca decida falas, ações ou pensamentos de Kuzin. Termine abrindo espaço para a próxima ação dele.
- Respeite as DISTÂNCIAS da seção PROXIMIDADE DE KUZIN: só quem está "ao lado" pode sussurrar ou tocar em Kuzin; quem está "longe" não pode. Não coloque Kuzin ao lado de alguém que o estado mostra distante. Se um NPC precisa chegar perto, mova-o antes com o comando mover.
- Quando um personagem fala, escreva a FALA entre aspas. Nunca escreva "sussurrou algo" ou "disse alguma coisa" sem dizer o quê.
- Não comece luta sem motivo claro. Só use iniciar_combate se um inimigo realmente atacar ou ameaçar Kuzin de perto, ou se Kuzin atacar; preencha o campo "texto" com o MOTIVO (quem fez o quê) e explique isso na narração.
- Você NÃO rola dados nem calcula dano: o jogo faz isso. Ao narrar combate, descreva os golpes sem citar números de dado.
MODOS:
- EXPLORAÇÃO (sem turnos): se Kuzin quer ir a algum lugar, use mover com alvo Kuzin para uma célula LIVRE perto do destino (ao lado do objeto/pessoa; para sair de um prédio passe pela porta). Se uma luta começa ou Kuzin ataca, use iniciar_combate.
- COMBATE: o jogo cuida dos turnos. Você só narra e pode mudar a intenção de NPCs.
COMANDOS (campo "acao"; use "comandos":[] se nada muda no mundo):
- mover (alvo, x, z) | colocar (alvo=nome novo, modelo, papel, x, z) | remover (alvo)
- intencao (alvo, estado: padrao|fugir|parado|agressivo) | atividade (alvo, texto curto do que faz agora)
- criar_objeto (alvo=nome novo, modelo, x, z) | mover_objeto (alvo, para=personagem OU x e z) | dar_item (alvo=objeto, para=personagem, objeto a 1 célula ou menos) | soltar_item (alvo) | mudar_estado (alvo, estado) | remover_objeto (alvo)
- gerar_construcao (alvo=nome da construção, modelo=taverna|casa|armazem|templo, tamanho=pequeno|medio|grande, para=personagem ou lugar de referência, extras=[porta_dos_fundos, porta_lateral, palco, alcapao, lareira]): o JOGO desenha a planta (cada vez diferente) e depois te informa o que ela contém. Use extras só se a história pedir (ex.: alguém entra pela porta dos fundos -> extras ["porta_dos_fundos"]).
- iniciar_combate (alvo="combate", texto=motivo da luta; só se algum inimigo estiver a menos de 8 passos de Kuzin) | encerrar_combate (alvo="combate")
EXEMPLO (Kuzin quer ir ao balcão): "comandos":[{"acao":"mover","alvo":"Kuzin","x":2,"z":3}]
EXEMPLO (o padeiro manda um pão): "comandos":[{"acao":"criar_objeto","alvo":"Pão quente","modelo":"pao","x":2,"z":6},{"acao":"mover_objeto","alvo":"Pão quente","para":"Kuzin"},{"acao":"dar_item","alvo":"Pão quente","para":"Kuzin"}]
Se um comando FALHAR, o resultado aparece no próximo turno: corrija ou tente outro.
REGRA DE OURO: só existe o que está no estado do tabuleiro (objetos, construções e a lista "contém"). Se algo consta em "NÃO possui" (alçapão, escada, janelas...), NÃO existe: não cite. Se quiser algo novo, crie com um comando; não invente só na narração.
Responda SEMPRE em JSON: {"narracao": "...", "comandos": [...], "novos_fatos": ["fato curto importante"]}."""

const TEXTO_ABERTURA: String = "Comece a aventura: em 3 frases, descreva a cena como um mestre faria, a partir de ONDE KUZIN ESTÁ (veja PROXIMIDADE DE KUZIN): o que ele vê e ouve, quem está perto e quem está longe, sem inventar falas nem aproximações. Não comece nenhuma luta. Pergunte o que Kuzin faz. Use comandos:[]."
const TEXTO_TURNO_NPCS: String = "Narre em 2 a 3 frases, de forma dramática e SEM citar números de dado, apenas estes acontecimentos (não invente dano nem mortes):"

var _pid: int = -1
var _pronto: bool = false
var _ocupado: bool = false
var _historico: Array = []          # [{role, content}]
var _fatos: Array = []
var _feedback_pendente: String = ""
var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 180.0
	add_child(_http)
	_carregar_campanha()
	iniciar_servidor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		parar_servidor()


func esta_pronto() -> bool:
	return _pronto


func esta_ocupado() -> bool:
	return _ocupado


func _definir_ocupado(valor: bool) -> void:
	_ocupado = valor
	ocupado_mudou.emit(valor)


func _status(texto: String) -> void:
	print("[MestreIA] ", texto)
	status_mudou.emit(texto)


# ---------------------------------------------------------------
# SERVIDOR
# ---------------------------------------------------------------
func _caminho_real(relativo: String) -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + relativo)
	return OS.get_executable_path().get_base_dir().path_join(relativo)


func _url(rota: String) -> String:
	return "http://127.0.0.1:%d%s" % [PORTA, rota]


func iniciar_servidor() -> void:
	_pronto = false
	if await _consultar_saude():
		_status("Servidor da IA já estava rodando.")
		_marcar_pronto()
		return

	var programa: String = _caminho_real(SERVIDOR_WINDOWS if OS.get_name() == "Windows" else SERVIDOR_LINUX)
	var modelo: String = _caminho_real(MODELO)
	if not FileAccess.file_exists(programa):
		_status("ERRO: não achei o servidor: " + programa)
		return
	if not FileAccess.file_exists(modelo):
		_status("ERRO: não achei o modelo: " + modelo)
		return

	var args: PackedStringArray = PackedStringArray(["-m", modelo, "--host", "127.0.0.1", "--port", str(PORTA),
		"-c", str(CONTEXTO), "-ngl", "99"])
	_pid = OS.create_process(programa, args)
	if _pid <= 0:
		_status("ERRO: não consegui iniciar o llama-server.")
		return
	_status("Carregando a IA local (pode demorar um pouco)...")
	await _esperar_servidor()


func _consultar_saude() -> bool:
	var req := HTTPRequest.new()
	req.timeout = 3.0
	add_child(req)
	var erro: int = req.request(_url("/health"))
	if erro != OK:
		req.queue_free()
		return false
	var r: Array = await req.request_completed
	req.queue_free()
	return int(r[0]) == HTTPRequest.RESULT_SUCCESS and int(r[1]) == 200


func _esperar_servidor() -> void:
	for i in range(240):
		await get_tree().create_timer(1.0).timeout
		if await _consultar_saude():
			_marcar_pronto()
			return
	_status("ERRO: o servidor da IA não respondeu a tempo.")


func _marcar_pronto() -> void:
	_pronto = true
	_status("IA local pronta.")
	mestre_pronto.emit()


func parar_servidor() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1


# ---------------------------------------------------------------
# CONVERSA
# ---------------------------------------------------------------
func _tabuleiro() -> Node:
	return get_tree().get_first_node_in_group("tabuleiro")


const PREFIXOS_DE_PERGUNTA: Array[String] = ["onde", "quem", "qual", "quais", "quando", "como", "quanto", "quantos", "quantas",
	"por que", "porque", "o que", "oque", "que", "tem", "tem algum", "tem alguma", "ha", "há", "existe", "existem", "posso", "consigo",
	"sera", "será", "descreva", "explique", "me explica", "me diz", "me fala", "me descreva", "me conta", "pode", "dá para", "da para", "vejo"]


# Pergunta = o jogador quer ENTENDER (tirar dúvida), não agir
func _eh_pergunta(texto: String) -> bool:
	var t: String = texto.strip_edges().to_lower()
	if t.contains("?"):
		return true
	for prefixo in PREFIXOS_DE_PERGUNTA:
		if t == prefixo or t.begins_with(prefixo + " "):
			return true
	return false


func jogador_agiu(texto: String) -> void:
	if _ocupado or not _pronto:
		return
	if _eh_pergunta(texto):
		var pedido: String = "O JOGADOR FEZ UMA PERGUNTA (ele quer entender melhor, NÃO está agindo): \"" + texto + "\"\nResponda DIRETAMENTE à pergunta, como um mestre tirando uma dúvida na mesa, usando só o que existe no estado do tabuleiro. NÃO continue a história, NÃO faça ninguém agir ou falar, NÃO narre ações de Kuzin. Se não houver nada assim, diga isso. comandos: []."
		await _consultar(pedido, texto, "pergunta")
	else:
		await _consultar("JOGADOR (Kuzin) diz/faz: " + texto, texto, "acao")


func narrar_turno(eventos: Array) -> void:
	if _ocupado or not _pronto:
		return
	var lista: String = "\n".join(eventos.map(func(e): return "- " + str(e)))
	await _consultar(TEXTO_TURNO_NPCS + "\n" + lista, "(turno dos NPCs)")


func iniciar_aventura() -> void:
	if _ocupado or not _pronto:
		return
	await _consultar(TEXTO_ABERTURA, "(início)", "abertura")


func nova_campanha() -> void:
	_historico.clear()
	_fatos.clear()
	_feedback_pendente = ""
	_salvar_campanha()


func _consultar(pedido: String, resumo_para_historico: String, modo: String = "acao") -> void:
	_definir_ocupado(true)
	_status("O Mestre está pensando...")

	var tab: Node = _tabuleiro()
	var estado: String = tab.descrever_tabuleiro() if tab != null else ""
	var schema: Dictionary = _schema_da_resposta(tab)
	var temperatura: float = 0.4 if modo == "pergunta" else TEMPERATURA
	var resposta: Dictionary = await _pedir_com_coerencia(_montar_mensagens(pedido, estado), schema, temperatura, tab)

	if resposta.is_empty():
		_status("ERRO: a IA não respondeu.")
		mestre_falou.emit("(O Mestre ficou em silêncio. Tente de novo.)")
		_definir_ocupado(false)
		return

	var comandos: Array = resposta.get("comandos", [])
	if modo == "pergunta" or modo == "abertura":
		comandos = []                      # pergunta e abertura não mudam o mundo

	# Comandos que mudam o mundo ANTES da narração (gerar construção, iniciar combate):
	# o jogo executa primeiro e o Mestre narra depois, sabendo o resultado (2 passadas).
	if _tem_pre_comando(comandos) and tab != null:
		await _executar_comandos(comandos)
		var estado2: String = tab.descrever_tabuleiro()
		var pedido2: String = pedido + "\n(O jogo JÁ EXECUTOU seus comandos; veja o resultado em RESULTADO DOS SEUS ÚLTIMOS COMANDOS. Narre agora usando SÓ o que existe no estado. Se um combate COMEÇOU, explique com clareza o que o desencadeou (quem fez o quê e por quê). Se o combate FALHOU em começar, NÃO o mencione: apenas continue a cena. Não repita gerar_construcao nem iniciar_combate.)"
		var resposta2: Dictionary = await _pedir_com_coerencia(_montar_mensagens(pedido2, estado2), schema, temperatura, tab)
		if not resposta2.is_empty():
			resposta = resposta2
		comandos = []
		for c in resposta.get("comandos", []):
			if c is Dictionary and str(c.get("acao", "")) != "gerar_construcao" and str(c.get("acao", "")) != "iniciar_combate":
				comandos.append(c)

		await _finalizar(resposta, comandos, resumo_para_historico, false)
	else:
		await _finalizar(resposta, comandos, resumo_para_historico, true)


func _finalizar(resposta: Dictionary, comandos: Array, resumo_para_historico: String, executar: bool) -> void:
	var narracao: String = str(resposta.get("narracao", "")).strip_edges()
	if narracao != "":
		mestre_falou.emit(narracao)

	_historico.append({"role": "user", "content": resumo_para_historico})
	_historico.append({"role": "assistant", "content": narracao})
	while _historico.size() > MENSAGENS_NO_HISTORICO:
		_historico.pop_front()

	for fato in resposta.get("novos_fatos", []):
		var f: String = str(fato).strip_edges()
		if f != "" and not _fatos.has(f):
			_fatos.append(f)
	while _fatos.size() > MAX_FATOS:
		_fatos.pop_front()

	if executar or not comandos.is_empty():
		var feedback_antes: String = _feedback_pendente
		await _executar_comandos(comandos)
		if feedback_antes != "" and _feedback_pendente == "":
			_feedback_pendente = feedback_antes
	_salvar_campanha()
	_status("Pronto.")
	_definir_ocupado(false)


func _tem_pre_comando(comandos: Array) -> bool:
	for c in comandos:
		if c is Dictionary and (str(c.get("acao", "")) == "gerar_construcao" or str(c.get("acao", "")) == "iniciar_combate"):
			return true
	return false


# Pede ao servidor; confere a narração (coisas inexistentes, falas vagas, distâncias impossíveis).
# Se tiver problema, manda reescrever (1 vez); se ainda tiver, remove as frases problemáticas.
func _pedir_com_coerencia(mensagens: Array, schema: Dictionary, temperatura: float, tab: Node) -> Dictionary:
	var resposta: Dictionary = await _chamar_servidor(mensagens, schema, temperatura)
	if resposta.is_empty() or tab == null:
		return resposta
	var problemas: Array = tab.problemas_de_narracao(str(resposta.get("narracao", "")))
	if problemas.is_empty():
		return resposta
	print("[MestreIA] narração com problemas: ", problemas)
	var nova: Array = mensagens.duplicate()
	nova.append({"role": "assistant", "content": JSON.stringify(resposta)})
	nova.append({"role": "user", "content": "ERRO DE COERÊNCIA na sua narração. Corrija: " + " | ".join(problemas) + "\nReescreva a resposta inteira usando só o que está no estado do tabuleiro (respeite a seção PROXIMIDADE DE KUZIN)."})
	var segunda: Dictionary = await _chamar_servidor(nova, schema, temperatura)
	if segunda.is_empty():
		segunda = resposta
	var restantes: Array = tab.problemas_de_narracao(str(segunda.get("narracao", "")))
	if not restantes.is_empty():
		segunda["narracao"] = tab.limpar_narracao(str(segunda.get("narracao", "")))
	return segunda


func _montar_mensagens(pedido: String, estado: String) -> Array:
	var sistema: String = REGRAS_DO_MESTRE + "\nPREMISSA: " + PREMISSA
	if not _fatos.is_empty():
		sistema += "\nFATOS JÁ OCORRIDOS:\n- " + "\n- ".join(_fatos)
	var mensagens: Array = [{"role": "system", "content": sistema}]
	mensagens.append_array(_historico)
	var ultimo: String = ""
	if estado != "":
		ultimo += "ESTADO ATUAL DO TABULEIRO:\n" + estado + "\n"
	if _feedback_pendente != "":
		ultimo += "RESULTADO DOS SEUS ÚLTIMOS COMANDOS:\n" + _feedback_pendente + "\n"
		_feedback_pendente = ""
	ultimo += pedido
	mensagens.append({"role": "user", "content": ultimo})
	return mensagens


# O schema força a IA a responder JSON válido, e limita x/z ao tamanho real do tabuleiro.
func _schema_da_resposta(tab: Node) -> Dictionary:
	var max_x: int = 9
	var max_z: int = 9
	var modelos: Array = []
	var estados: Array = ["padrao", "fugir", "parado", "agressivo", "aberto", "fechado", "aceso", "apagado", "quebrado", "normal", "destruido"]
	if tab != null:
		max_x = tab.largura_tabuleiro - 1
		max_z = tab.profundidade_tabuleiro - 1
		modelos.append_array(tab.MODELOS_CRIATURA.keys())
		modelos.append_array(tab.CATALOGO_OBJETOS.keys())
		modelos.append_array(tab.CATALOGO_PREDIOS.keys())
	else:
		modelos = ["goblin", "pao"]
	var comando: Dictionary = {
		"type": "object",
		"properties": {
			"acao": {"type": "string", "enum": ["mover", "colocar", "remover", "intencao", "atividade", "criar_objeto", "mover_objeto", "dar_item", "soltar_item", "mudar_estado", "remover_objeto", "gerar_construcao", "iniciar_combate", "encerrar_combate"]},
			"texto": {"type": "string"},
			"alvo": {"type": "string"},
			"para": {"type": "string"},
			"modelo": {"type": "string", "enum": modelos},
			"papel": {"type": "string", "enum": ["aliado", "inimigo", "neutro"]},
			"estado": {"type": "string", "enum": estados},
			"tamanho": {"type": "string", "enum": ["pequeno", "medio", "grande"]},
			"extras": {"type": "array", "items": {"type": "string", "enum": ["porta_dos_fundos", "porta_lateral", "palco", "alcapao", "lareira"]}, "maxItems": 3},
			"x": {"type": "integer", "minimum": 0, "maximum": max_x},
			"z": {"type": "integer", "minimum": 0, "maximum": max_z},
		},
		"required": ["acao", "alvo"],
	}
	return {
		"type": "object",
		"properties": {
			"narracao": {"type": "string"},
			"comandos": {"type": "array", "items": comando, "maxItems": MAX_COMANDOS},
			"novos_fatos": {"type": "array", "items": {"type": "string"}, "maxItems": 3},
		},
		"required": ["narracao", "comandos", "novos_fatos"],
	}


func _chamar_servidor(mensagens: Array, schema: Dictionary, temperatura: float = TEMPERATURA) -> Dictionary:
	var corpo: Dictionary = {
		"messages": mensagens,
		"temperature": temperatura,
		"max_tokens": MAX_TOKENS_RESPOSTA,
		"response_format": {"type": "json_schema", "json_schema": {"name": "resposta", "strict": true, "schema": schema}},
	}
	var erro: int = _http.request(_url("/v1/chat/completions"), PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(corpo))
	if erro != OK:
		return {}
	var r: Array = await _http.request_completed
	if int(r[0]) != HTTPRequest.RESULT_SUCCESS or int(r[1]) != 200:
		print("[MestreIA] HTTP ", r[1], " ", (r[3] as PackedByteArray).get_string_from_utf8().left(300))
		return {}
	var json: Variant = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if not (json is Dictionary):
		return {}
	var escolhas: Array = json.get("choices", [])
	if escolhas.is_empty():
		return {}
	var conteudo: String = str(escolhas[0].get("message", {}).get("content", ""))
	return _interpretar_resposta(conteudo)


func _interpretar_resposta(texto: String) -> Dictionary:
	var dados: Variant = JSON.parse_string(texto)
	if dados is Dictionary:
		return dados
	return _resgatar_narracao(texto)


# Se o JSON veio quebrado, pelo menos aproveita a narração
func _resgatar_narracao(texto: String) -> Dictionary:
	var rx := RegEx.new()
	rx.compile("\"narracao\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)")
	var m: RegExMatch = rx.search(texto)
	var narracao: String = texto.strip_edges()
	if m != null:
		narracao = m.get_string(1).replace("\\n", "\n").replace("\\\"", "\"")
	if narracao == "":
		return {}
	return {"narracao": narracao, "comandos": [], "novos_fatos": []}


func _executar_comandos(comandos: Array) -> void:
	var tab: Node = _tabuleiro()
	if tab == null or comandos.is_empty():
		return
	var resultados: Array = []
	for comando in comandos.slice(0, MAX_COMANDOS):
		if not (comando is Dictionary):
			continue
		await get_tree().create_timer(0.5).timeout
		var r: String = tab.executar_comando_mestre(comando)
		resultados.append("%s %s -> %s" % [comando.get("acao", "?"), comando.get("alvo", ""), r])
	_feedback_pendente = "\n".join(resultados)
	print("[MestreIA] comandos: ", _feedback_pendente)


# ---------------------------------------------------------------
# SALVAR / CARREGAR
# ---------------------------------------------------------------
func _salvar_campanha() -> void:
	var f := FileAccess.open(ARQUIVO_CAMPANHA, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"historico": _historico, "fatos": _fatos}))


func _carregar_campanha() -> void:
	if not FileAccess.file_exists(ARQUIVO_CAMPANHA):
		return
	var dados: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO_CAMPANHA))
	if dados is Dictionary:
		_historico = dados.get("historico", [])
		_fatos = dados.get("fatos", [])
