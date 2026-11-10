extends Control
# Chat com o Mestre IA (usa o Autoload MestreIA)

@onready var chat_historico: RichTextLabel = %HistoricoChat
@onready var input_texto: TextEdit = %EntradaChat
@onready var botao_enviar: Button = %EnviarChat

var _mestre: Node
var _iniciou: bool = false


func _ready() -> void:
	botao_enviar.pressed.connect(_on_enviar)
	input_texto.gui_input.connect(_on_texto_gui_input)
	botao_enviar.disabled = true

	_mestre = get_node_or_null("/root/MestreIA")
	if _mestre == null:
		_msg("Sistema", "O MestreIA não foi encontrado. Confira o Autoload (nome exato: MestreIA).")
		return
	_mestre.status_mudou.connect(func(t: String) -> void: _msg("Sistema", t))
	_mestre.mestre_falou.connect(func(t: String) -> void:
		_msg("Mestre", t))
	_mestre.npc_falou.connect(func(nome: String, fala: String) -> void:
		_msg(nome, fala))
	_mestre.conversa_mudou.connect(_ao_mudar_conversa)
	_mestre.ocupado_mudou.connect(_ao_mudar_ocupado)
	_mestre.mestre_pronto.connect(_ao_ficar_pronto)
	_ao_ficar_pronto()

	# O tabuleiro nasce depois deste painel: espera um quadro para achá-lo
	await get_tree().process_frame
	var tab: Node = get_tree().get_first_node_in_group("tabuleiro")
	if tab != null:
		tab.log_de_combate.connect(func(t: String) -> void: _msg("Jogo", t))
		tab.pedido_de_conversa.connect(func(nome: String) -> void: _mestre.comecar_conversa(nome))


func _ao_ficar_pronto() -> void:
	botao_enviar.disabled = _mestre.esta_ocupado()
	if not _iniciou:
		_iniciou = true
		_mestre.iniciar_aventura()


func _ao_mudar_conversa(nome: String) -> void:
	if nome == "":
		input_texto.placeholder_text = "Fale com o Mestre... (Enter envia)"
		_msg("Sistema", "Conversa encerrada. Você voltou a falar com o Mestre.")
	else:
		input_texto.placeholder_text = "Falando com %s... (digite 'tchau' ou /sair para encerrar)" % nome
		_msg("Sistema", "Você está conversando com %s. O que você escrever agora é a fala de Kuzin. Digite 'tchau' ou /sair para voltar ao Mestre." % nome)


func _ao_mudar_ocupado(ocupado: bool) -> void:
	botao_enviar.disabled = ocupado


func _mostrar_cena() -> void:
	var tab: Node = get_tree().get_first_node_in_group("tabuleiro")
	if tab != null:
		_msg("Sistema", tab.resumo_da_cena())


func _on_texto_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Esc solta o teclado (volta a controlar a câmera)
		if event.keycode == KEY_ESCAPE:
			input_texto.release_focus()
			return
		# Enter envia; Shift+Enter pula linha
		if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and not event.shift_pressed:
			input_texto.accept_event()
			_on_enviar()
			return
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			input_texto.accept_event()
			_on_enviar()


func _on_enviar() -> void:
	var texto: String = input_texto.text.strip_edges()
	if texto == "" or _mestre == null or botao_enviar.disabled:
		return
	input_texto.text = ""

	if texto == "/nova":
		_mestre.nova_campanha()
		var tab_nova: Node = get_tree().get_first_node_in_group("tabuleiro")
		if tab_nova != null:
			tab_nova.apagar_mundo()          # esquece o jogo salvo (o tabuleiro volta ao início ao apertar F9)
		chat_historico.clear()
		_msg("Sistema", "Nova campanha. (Aperte F9 para reiniciar também o tabuleiro.)")
		_mestre.iniciar_aventura()
		return
	if texto == "/rapido":
		_mestre.definir_modo_rapido(not _mestre.modo_rapido)
		return
	if texto == "/evento":
		_msg("Você", "(avançar a história)")
		_mestre.forcar_evento()
		return
	if texto.begins_with("/falar "):
		_mestre.comecar_conversa(texto.substr(7).strip_edges())
		return
	if texto == "/sair":
		_mestre.encerrar_conversa()
		return
	if texto == "/diario":
		var tab_d: Node = get_tree().get_first_node_in_group("tabuleiro")
		if tab_d != null:
			_msg("Diário", tab_d.mundo.diario_completo())
		return
	if texto.begins_with("/npc "):
		var tab_n: Node = get_tree().get_first_node_in_group("tabuleiro")
		if tab_n != null:
			_msg("Ficha", tab_n.descrever_npc(texto.substr(5).strip_edges()))
		return
	if texto == "/onde":
		_mostrar_cena()
		return
	if texto == "/ajuda":
		_msg("Sistema", "Comandos: /explorar (libera o clique na cena), /rapido (liga/desliga o Mestre instantâneo de teste), /evento (avança a história no modo rápido), /falar Nome e /sair (conversa com NPC), /onde (resumo da cena), /diario (o que já aconteceu), /npc Nome (ficha), /notas (notas da IA), /nova (nova campanha). Enter envia, Shift+Enter pula linha. Esc ou clicar fora solta o chat.")
		return
	if texto == "/notas":
		var tab: Node = get_tree().get_first_node_in_group("tabuleiro")
		if tab != null:
			tab.debug_ativo = not tab.debug_ativo
			_msg("Sistema", "Notas da IA: " + ("ligadas" if tab.debug_ativo else "desligadas"))
		return

	_msg("Você", texto)
	_mestre.jogador_agiu(texto)


func _msg(remetente: String, mensagem: String) -> void:
	if chat_historico.get_total_character_count() > 0:
		chat_historico.add_text("\n\n")
	var cor: Color = Color("#c0c8d4")
	match remetente:
		"Você":
			cor = Color("#91d3ff")
		"Mestre":
			cor = Color("#ffd18a")
		"Jogo", "Sistema":
			cor = Color("#abb5c2")
	chat_historico.push_color(cor)
	chat_historico.push_bold()
	chat_historico.add_text(remetente + ": ")
	chat_historico.pop()
	chat_historico.pop()
	chat_historico.add_text(mensagem)
