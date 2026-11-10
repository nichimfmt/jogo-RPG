extends Node
const AcoesPadrao = preload("res://scripts/acoes_padrao.gd")
const EnsaioTaverna = preload("res://scripts/ensaio_taverna.gd")
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
signal npc_falou(nome: String, texto: String)      # um NPC respondeu numa conversa
signal conversa_mudou(nome: String)                # "" = ninguém (conversa acabou)

const SERVIDOR_WINDOWS: String = "llama_bin/llama/llama-server.exe"
const SERVIDOR_LINUX: String = "llama_bin/llama/llama-server"
const MODELO: String = "models/llama-3.2-3b-instruct-q4_k_m.gguf"
const MestreFalso = preload("res://scripts/mestre_falso.gd")
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
- Números em nomes de objetos e níveis de ficha são referências do sistema. No relato, diga “um barril” ou “alguns barris” e use descrições como “um arqueiro goblin”. Evite revelar a identidade de inimigos desconhecidos.
- Nunca decida falas, ações ou pensamentos de Kuzin. Termine abrindo espaço para a próxima ação dele.
- Kuzin SÓ se move de verdade quando o jogo informa um "FATO DO JOGO". NUNCA narre Kuzin andando sem um desses dois.
- Respeite as DISTÂNCIAS da seção PROXIMIDADE DE KUZIN: só quem está "ao lado" pode sussurrar ou tocar em Kuzin; quem está "longe" não pode. Não coloque Kuzin ao lado de alguém que o estado mostra distante. Se um NPC precisa chegar perto, mova-o antes com o comando mover.
- Quando um personagem fala, escreva a FALA entre aspas. Nunca escreva "sussurrou algo" ou "disse alguma coisa" sem dizer o quê.
- Não comece luta sem motivo claro. Só use iniciar_combate se um inimigo realmente atacar ou ameaçar Kuzin de perto, ou se Kuzin atacar; preencha o campo "texto" com o MOTIVO (quem fez o quê) e explique isso na narração.
- Você NÃO rola dados nem calcula dano: o jogo faz isso. Ao narrar combate, descreva os golpes sem citar números de dado.
MODOS:
- EXPLORAÇÃO (sem turnos): o jogo interpreta e executa o movimento de Kuzin e decide quando começa o combate. Use mover apenas para NPCs.
- COMBATE: o jogo cuida dos turnos. Você só narra e pode mudar a intenção de NPCs.
COMANDOS (campo "acao"; use "comandos":[] se nada muda no mundo):
- mover (alvo, x, z) | colocar (alvo=nome novo, modelo, papel, x, z; para papel aliado/neutro SEMPRE preencha também "personalidade" (como ele é), "sabe" (uma coisa que ele pode contar) e "segredo" (algo que só conta a quem confia nele)) | remover (alvo)
- intencao (alvo, estado: padrao|fugir|parado|agressivo) | atividade (alvo, texto curto do que faz agora)
- criar_objeto (alvo=nome novo, modelo, x, z) | mover_objeto (alvo, para=personagem OU x e z) | dar_item (alvo=objeto, para=personagem, objeto a 1 célula ou menos) | soltar_item (alvo) | mudar_estado (alvo, estado) | remover_objeto (alvo)
- gerar_construcao (alvo=nome da construção, modelo=taverna|casa|armazem|templo, tamanho=pequeno|medio|grande, para=personagem ou lugar de referência, extras=[porta_dos_fundos, porta_lateral, palco, alcapao, lareira]): o JOGO desenha a planta (cada vez diferente) e depois te informa o que ela contém. Use extras só se a história pedir (ex.: alguém entra pela porta dos fundos -> extras ["porta_dos_fundos"]).
- iniciar_combate (alvo="combate", texto=motivo da luta; só se um inimigo avistar Kuzin a até 8 passos) | encerrar_combate (alvo="combate")
EXEMPLO (o padeiro manda um pão): "comandos":[{"acao":"criar_objeto","alvo":"Pão quente","modelo":"pao","x":2,"z":6},{"acao":"mover_objeto","alvo":"Pão quente","para":"Kuzin"},{"acao":"dar_item","alvo":"Pão quente","para":"Kuzin"}]
Quando o jogo apresentar os resultados dos comandos, narre apenas o que deu certo e explique as falhas sem inventar efeitos.
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
var modo_rapido: bool = false       # true = Mestre de mentirinha (instantâneo, sem IA) só para testar o jogo
var _falso = MestreFalso.new()
var _npc_conversa: String = ""      # nome do NPC com quem Kuzin conversa agora ("" = falando com o Mestre)
var _semente_campanha: int = 0      # cenário a que esta memória pertence


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 35.0
	add_child(_http)
	if OS.get_cmdline_user_args().has(EnsaioTaverna.ARGUMENTO):
		modo_rapido = true
	else:
		_carregar_campanha()
	if not modo_rapido:
		iniciar_servidor()
	else:
		_status("Modo RÁPIDO ligado (sem IA). Digite /rapido para voltar à IA.")
		mestre_pronto.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		parar_servidor()


func esta_pronto() -> bool:
	return _pronto or modo_rapido


func definir_modo_rapido(valor: bool) -> void:
	if OS.get_cmdline_user_args().has(EnsaioTaverna.ARGUMENTO):
		_status("O teste da taverna usa resultados fixos.")
		return
	modo_rapido = valor
	_salvar_campanha()
	if valor:
		_status("Modo RÁPIDO ligado: respostas instantâneas, SEM IA (só para testar o jogo).")
		mestre_pronto.emit()
	elif _pronto:
		_status("Modo IA ligado.")
		mestre_pronto.emit()
	else:
		_status("Modo IA ligado. Carregando a IA local...")
		if _pid <= 0:
			iniciar_servidor()


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
	if t.ends_with("?") and not (t.contains(" e ") or t.contains(":") or t.contains("\"")):
		return true
	for prefixo in PREFIXOS_DE_PERGUNTA:
		if t == prefixo or t.begins_with(prefixo + " "):
			return true
	return false


func jogador_agiu(texto: String) -> void:
	if _ocupado:
		return
	_sincronizar_com_mundo()
	if _npc_conversa != "":
		await _conversar(texto)
		return
	var tab: Node = _tabuleiro()
	if tab == null:
		return
	var exploracao: String = tab.liberar_exploracao(texto)
	if exploracao != "":
		_responder_resultado(texto, exploracao)
		return
	if tab._normalizar(texto.strip_edges()).rstrip(".!?") in ["olho ao redor", "olho em volta", "observo o lugar"]:
		_responder_resultado(texto, tab.resumo_da_cena())
		return
	if tab.ensaio_taverna != null:
		var resposta: String = tab.ensaio_taverna.responder_pergunta(tab, texto)
		if resposta != "":
			_responder_resultado(texto, resposta)
			return
	if _eh_pergunta(texto):
		if modo_rapido or not esta_pronto():
			await _responder_pergunta_rapido(texto)
			return
		var pedido: String = "Responda à pergunta de Kuzin com o que ele pode perceber. Sem ações nem comandos. Pergunta: " + texto
		await _consultar(pedido, texto, "pergunta")
		return
	if tab.modo == "combate":
		mestre_falou.emit("Em combate, use o tabuleiro para mover, atacar e encerrar o turno.")
		return
	if tab._em_movimento(tab.celula_jogador):
		mestre_falou.emit("Aguarde Kuzin terminar de andar.")
		return

	var resultados: Array[String] = []
	for parte in AcoesPadrao.separar(texto):
		var acao: String = parte
		if tab.ensaio_taverna != null:
			var normalizada: String = tab.ensaio_taverna.normalizar_acao(tab, parte)
			if normalizada.begins_with("vvou "):
				acao = normalizada.substr(1)
			var ensaio: Dictionary = tab.ensaio_taverna.resolver(tab, parte)
			if not ensaio.is_empty():
				resultados.append(ensaio["texto"])
				if not bool(ensaio["ok"]):
					break
				continue
		var espera: String = tab.esperar_na_cena(parte)
		if espera != "":
			resultados.append(espera)
			continue
		var origem: Vector2i = tab.celula_jogador
		var fato: String = tab.interpretar_movimento(acao).trim_prefix("FATO DO JOGO: ")
		if fato != "":
			resultados.append(fato)
			if origem != tab.celula_jogador:
				_definir_ocupado(true)
				while is_instance_valid(tab) and tab._em_movimento(tab.celula_jogador):
					await get_tree().process_frame
				_definir_ocupado(false)
				if not is_instance_valid(tab):
					return
			if tab.modo == "combate" or fato.begins_with("Kuzin não") or fato.begins_with("não encontrei"):
				break

		if _quer_falar(parte):
			var npc: String = tab.npc_citado_no_texto(parte)
			var erro: String = "Diga com quem você quer falar." if npc == "" else tab.pode_conversar_com(npc)
			if not resultados.is_empty():
				_responder_resultado(texto, " ".join(resultados))
			if erro != "":
				mestre_falou.emit(erro)
				return
			_entrar_na_conversa(npc)
			var inicio_da_fala: int = texto.find(parte)
			await _conversar(texto.substr(inicio_da_fala) if inicio_da_fala >= 0 else parte)
			return

		if fato != "":
			continue
		var padrao: Dictionary = AcoesPadrao.tentar(tab, parte)
		if not bool(padrao["entendeu"]):
			continue
		resultados.append_array(padrao["linhas"])
		if not bool(padrao["algum_ok"]) or tab.modo == "combate":
			break

	if not resultados.is_empty():
		_responder_resultado(texto, " ".join(resultados))
	elif tab.ensaio_taverna != null:
		mestre_falou.emit("Fiquei em dúvida sobre o que Kuzin quer fazer. Você pode dizer para onde quer ir, com quem quer falar ou o que quer examinar. Se perdeu o fio, pergunte “qual é o objetivo?”.")
	elif modo_rapido or not esta_pronto():
		mestre_falou.emit("Não entendi a ação. Tente dizer o que você faz e qual é o alvo.")
	else:
		await _consultar("JOGADOR (Kuzin) diz/faz: " + texto, texto)


func _responder_resultado(pedido: String, resultado: String) -> void:
	mestre_falou.emit(resultado)
	_registrar_no_historico(pedido, resultado)


const VERBOS_DE_FALAR: Array[String] = ["falo", "falar", "fala com", "converso", "conversar", "pergunto", "perguntar", "cumprimento", "saudo", "digo", "dirijo a palavra", "chamo"]


func _quer_falar(texto: String) -> bool:
	var tab: Node = _tabuleiro()
	var t: String = " " + (tab._normalizar(texto) if tab != null else texto.to_lower()) + " "
	for sinal in [",", ".", ":", ";", "!", "?"]:
		t = t.replace(sinal, " ")
	if t.contains(" nao "):
		return false
	for v in VERBOS_DE_FALAR:
		if t.contains(" " + v + " "):
			return true
	return false


func forcar_evento() -> void:
	if OS.get_cmdline_user_args().has(EnsaioTaverna.ARGUMENTO):
		_status("O teste da taverna avança pelas ações de Kuzin.")
		return
	if not modo_rapido:
		_status("O comando /evento só funciona no modo rápido (/rapido).")
		return
	if _ocupado:
		return
	await _agir_rapido("(evento forçado)", "", true)


# ---------------------------------------------------------------
# CONVERSA COM NPC
# ---------------------------------------------------------------
func conversa_atual() -> String:
	return _npc_conversa


func comecar_conversa(nome_digitado: String) -> void:
	var tab: Node = _tabuleiro()
	if tab == null:
		return
	var nome: String = tab.nome_exato_do_npc(nome_digitado)
	if nome == "":
		_status("Não existe ninguém chamado '%s'." % nome_digitado)
		return
	var erro: String = tab.pode_conversar_com(nome)
	if erro != "":
		mestre_falou.emit(erro)
		return
	_entrar_na_conversa(nome)


func _entrar_na_conversa(nome: String) -> void:
	_npc_conversa = nome
	var tab: Node = _tabuleiro()
	if tab != null:
		tab.registrar_evento("conversa", "Kuzin começou a conversar com %s." % nome)
	conversa_mudou.emit(nome)


func encerrar_conversa() -> void:
	if _npc_conversa == "":
		return
	var nome: String = _npc_conversa
	_npc_conversa = ""
	conversa_mudou.emit("")
	mestre_falou.emit("Kuzin encerra a conversa com %s." % nome)


func _conversar(texto: String) -> void:
	var tab: Node = _tabuleiro()
	var nome: String = _npc_conversa
	var t: String = texto.strip_edges().to_lower()
	for adeus in ["tchau", "adeus", "ate logo", "até logo", "encerro a conversa", "/sair", "sair"]:
		if t == adeus or t.begins_with(adeus + " "):
			encerrar_conversa()
			return
	if tab == null:
		return
	var erro: String = tab.pode_conversar_com(nome)
	if erro != "":
		_npc_conversa = ""
		conversa_mudou.emit("")
		mestre_falou.emit(erro + " A conversa terminou.")
		return
	if tab.ensaio_taverna != null and nome == EnsaioTaverna.MIRA:
		var acao: String = tab.ensaio_taverna.normalizar_acao(tab, texto)
		if acao in ["mostro o bilhete", "mostro o bilhete a voce", "mostro meu bilhete"]:
			acao = "mostro o bilhete a mira"
		if acao.begins_with("mostro ") and acao.contains("bilhete"):
			var resultado: Dictionary = tab.ensaio_taverna.resolver(tab, acao)
			if not resultado.is_empty():
				_responder_resultado(texto, resultado["texto"])
				return
	_definir_ocupado(true)
	_status("%s está respondendo..." % nome)
	var info: Dictionary = tab.processar_fala_para_npc(nome, texto)
	tab.avancar_relogio(5)
	var fala: String = tab.ensaio_taverna.resposta_npc(tab, nome, texto) if tab.ensaio_taverna != null else ""
	if fala == "" and not modo_rapido and esta_pronto():
		fala = await _fala_do_npc_ia(tab, nome, texto)
		for seg in info.get("liberados", []):
			if _fala_contem(fala, str(seg)):
				tab.marcar_segredo_contado(nome, str(seg))
	if fala == "":
		fala = _falso.responder_npc(tab, nome, texto, info)
	npc_falou.emit(nome, fala)
	_historico.append({"role": "user", "content": "Kuzin diz a %s: %s" % [nome, texto]})
	_historico.append({"role": "assistant", "content": "%s responde: %s" % [nome, fala]})
	while _historico.size() > MENSAGENS_NO_HISTORICO:
		_historico.pop_front()
	_salvar_campanha()
	_status("Pronto.")
	_definir_ocupado(false)


func _fala_contem(fala: String, fato: String) -> bool:
	var tab: Node = _tabuleiro()
	var f: String = tab._normalizar(fala)
	var acertos: int = 0
	for tok in tab._normalizar(fato).split(" "):
		if tok.length() >= 5 and f.contains(tok):
			acertos += 1
	return acertos >= 2


const REGRAS_DO_NPC: String = """Você interpreta UM personagem num RPG de mesa, em português do Brasil. Responda SÓ com a fala dele, em 1 a 3 frases, em primeira pessoa, com o jeito (personalidade) dele. Pode incluir um gesto curto entre asteriscos.
- Use apenas o que está em "O QUE VOCÊ SABE" e os segredos liberados. Se perguntarem algo que você não sabe, diga que não sabe, do seu jeito.
- NÃO invente fatos novos sobre o mundo, lugares, objetos ou pessoas. NÃO conte segredos que não estão listados como liberados.
- NÃO fale nem aja por Kuzin. NÃO narre a cena; só fale como o personagem.
- Responda em JSON: {"narracao": "a fala do personagem"}."""


func _fala_do_npc_ia(tab: Node, nome: String, texto: String) -> String:
	var sistema: String = REGRAS_DO_NPC + "\n" + tab.ficha_para_conversa(nome)
	var cel: Vector2i = tab._achar_exato(nome)
	if cel != tab.CELULA_INVALIDA:
		sistema += "CENA: " + tab.lugar_texto(cel) + ". Kuzin (meio-elfo ladino) conversa com você.\n"
	var mensagens: Array = [{"role": "system", "content": sistema}]
	mensagens.append_array(_historico.slice(maxi(_historico.size() - 6, 0)))
	mensagens.append({"role": "user", "content": "Kuzin diz a você: " + texto})
	var schema: Dictionary = {"type": "object", "properties": {"narracao": {"type": "string"}}, "required": ["narracao"]}
	var resposta: Dictionary = await _pedir_com_coerencia(mensagens, schema, 0.8, tab)
	return str(resposta.get("narracao", "")).strip_edges()


# ---------------------------------------------------------------
# MODO RÁPIDO (Mestre de mentirinha)
# ---------------------------------------------------------------
func _responder_pergunta_rapido(texto: String) -> void:
	_definir_ocupado(true)
	await get_tree().create_timer(0.2).timeout
	var narr: String = _falso.responder_pergunta(_tabuleiro(), texto)
	mestre_falou.emit(narr)
	_registrar_no_historico(texto, narr)
	_definir_ocupado(false)


func _agir_rapido(texto: String, fato: String, forcar: bool) -> void:
	_definir_ocupado(true)
	var tab: Node = _tabuleiro()
	var plano: Dictionary = _falso.planejar(tab, texto, fato, forcar)
	if not (plano["comandos"] as Array).is_empty():
		await _executar_comandos(plano["comandos"])
	var feedback: String = _feedback_pendente
	var narr: String = _falso.narrar(tab, plano, feedback)
	_feedback_pendente = ""
	mestre_falou.emit(narr)
	_registrar_no_historico(texto, narr)
	_definir_ocupado(false)


func _registrar_no_historico(pedido: String, narracao: String) -> void:
	_historico.append({"role": "user", "content": pedido})
	_historico.append({"role": "assistant", "content": narracao})
	while _historico.size() > MENSAGENS_NO_HISTORICO:
		_historico.pop_front()
	_salvar_campanha()


# Se o cenário mudou (partida nova), a memória do Mestre é de outra história: esquece
func _sincronizar_com_mundo() -> void:
	var tab: Node = _tabuleiro()
	if tab == null:
		return
	if int(tab.semente_cenario) != _semente_campanha:
		_historico.clear()
		_fatos.clear()
		_feedback_pendente = ""
		_npc_conversa = ""
		_falso = MestreFalso.new()
		_semente_campanha = int(tab.semente_cenario)
		_salvar_campanha()


func narrar_turno(eventos: Array) -> void:
	if _ocupado or modo_rapido or not esta_pronto():
		mestre_falou.emit(" ".join(eventos.map(func(e): return str(e))))
		return
	var lista: String = "\n".join(eventos.map(func(e): return "- " + str(e)))
	await _consultar(TEXTO_TURNO_NPCS + "\n" + lista, "(turno dos NPCs)", "turno", lista)


func iniciar_aventura() -> void:
	if _ocupado:
		return
	for i in range(30):                     # espera o tabuleiro existir
		if _tabuleiro() != null:
			break
		await get_tree().process_frame
	_sincronizar_com_mundo()
	if modo_rapido or not esta_pronto():
		mestre_falou.emit(_falso.abertura(_tabuleiro()))
		return
	await _consultar(TEXTO_ABERTURA, "(início)", "abertura", _falso.abertura(_tabuleiro()))


func nova_campanha() -> void:
	_npc_conversa = ""
	conversa_mudou.emit("")
	_falso = MestreFalso.new()
	_historico.clear()
	_fatos.clear()
	_feedback_pendente = ""
	_salvar_campanha()


func _consultar(pedido: String, resumo_para_historico: String, modo: String = "acao", reserva: String = "") -> void:
	_definir_ocupado(true)
	_status("O Mestre está pensando...")
	var tab: Node = _tabuleiro()
	var estado: String = tab.descrever_tabuleiro() if tab != null else ""
	var schema: Dictionary = _schema_da_resposta(tab)
	var temperatura: float = 0.4 if modo == "pergunta" else TEMPERATURA
	var mensagens: Array = _montar_mensagens(pedido, estado)
	var resposta: Dictionary
	if modo == "acao":
		resposta = await _chamar_servidor(mensagens, schema, temperatura)
		var comandos: Array = resposta.get("comandos", [])
		if not comandos.is_empty() and is_instance_valid(tab) and tab.modo != "combate":
			await _executar_comandos(comandos)
			reserva = _feedback_pendente
			if not is_instance_valid(tab):
				_definir_ocupado(false)
				return
			var pedido_final: String = pedido + "\nO jogo já aplicou os comandos possíveis. Narre somente os resultados abaixo. Não invente efeitos, não execute comandos nem prossiga a história.\n" + reserva
			if reserva.contains("-> FALHOU:"):
				resposta = {}
			else:
				resposta = await _pedir_com_coerencia(_montar_mensagens(pedido_final, tab.descrever_tabuleiro()), schema, temperatura, tab)
		elif not resposta.is_empty():
			resposta = await _validar_narracao(resposta, mensagens, schema, temperatura, tab)
	else:
		resposta = await _pedir_com_coerencia(mensagens, schema, temperatura, tab)

	var narracao: String = str(resposta.get("narracao", "")).strip_edges()
	if narracao == "":
		narracao = reserva if reserva != "" else "O Mestre não conseguiu responder. Reformule a ação ou tente novamente."
	_responder_resultado(resumo_para_historico, narracao)
	_feedback_pendente = ""
	_status("Pronto.")
	_definir_ocupado(false)


func _pedir_com_coerencia(mensagens: Array, schema: Dictionary, temperatura: float, tab: Node) -> Dictionary:
	var resposta: Dictionary = await _chamar_servidor(mensagens, schema, temperatura)
	return await _validar_narracao(resposta, mensagens, schema, temperatura, tab)


func _validar_narracao(resposta: Dictionary, mensagens: Array, schema: Dictionary, temperatura: float, tab: Node) -> Dictionary:
	if resposta.is_empty() or not is_instance_valid(tab):
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
	var tab_p: Node = _tabuleiro()
	var premissa: String = PREMISSA
	if tab_p != null and str(tab_p.premissa_atual) != "":
		premissa = str(tab_p.premissa_atual)
	var sistema: String = REGRAS_DO_MESTRE + "\nPREMISSA: " + premissa
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
			"personalidade": {"type": "string"},
			"sabe": {"type": "string"},
			"segredo": {"type": "string"},
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
		if not is_instance_valid(tab):
			break
		var r: String = tab.executar_comando_mestre(comando)
		resultados.append("%s %s -> %s" % [comando.get("acao", "?"), comando.get("alvo", ""), r])
	_feedback_pendente = "\n".join(resultados)
	print("[MestreIA] comandos: ", _feedback_pendente)


# ---------------------------------------------------------------
# SALVAR / CARREGAR
# ---------------------------------------------------------------
func _salvar_campanha() -> void:
	if OS.get_cmdline_user_args().has(EnsaioTaverna.ARGUMENTO):
		return
	var f := FileAccess.open(ARQUIVO_CAMPANHA, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"historico": _historico, "fatos": _fatos, "semente": _semente_campanha, "rapido": modo_rapido}))


func _carregar_campanha() -> void:
	if not FileAccess.file_exists(ARQUIVO_CAMPANHA):
		return
	var dados: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO_CAMPANHA))
	if dados is Dictionary:
		_historico = dados.get("historico", [])
		_fatos = dados.get("fatos", [])
		_semente_campanha = int(dados.get("semente", 0))
		modo_rapido = bool(dados.get("rapido", false))
