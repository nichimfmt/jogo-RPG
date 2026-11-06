extends Control
# Chat com o Mestre IA (usa o Autoload MestreIA)

@onready var chat_historico: RichTextLabel = $VBoxContainer/RichTextLabel
@onready var input_texto: TextEdit = $VBoxContainer/HBoxContainer/TextEdit
@onready var botao_enviar: Button = $VBoxContainer/HBoxContainer/Button

var _mestre: Node
var _iniciou: bool = false
var _cena_pendente: bool = false


func _ready() -> void:
	chat_historico.bbcode_enabled = true
	# Layout: o chat ocupa o espaço todo; a caixa de digitação fica baixa e o botão Enviar visível
	chat_historico.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_historico.scroll_following = true
	input_texto.custom_minimum_size = Vector2(0.0, 90.0)
	input_texto.size_flags_vertical = Control.SIZE_SHRINK_END
	input_texto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_texto.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	botao_enviar.size_flags_vertical = Control.SIZE_SHRINK_END
	botao_enviar.focus_mode = Control.FOCUS_NONE
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
	_mestre.ocupado_mudou.connect(_ao_mudar_ocupado)
	_mestre.mestre_pronto.connect(_ao_ficar_pronto)
	if _mestre.esta_pronto():
		_ao_ficar_pronto()

	# O tabuleiro nasce depois deste painel: espera um quadro para achá-lo
	await get_tree().process_frame
	var tab: Node = get_tree().get_first_node_in_group("tabuleiro")
	if tab != null:
		tab.log_de_combate.connect(func(t: String) -> void: _msg("Jogo", t))


func _ao_ficar_pronto() -> void:
	botao_enviar.disabled = false
	if not _iniciou:
		_iniciou = true
		_mestre.iniciar_aventura()


func _ao_mudar_ocupado(ocupado: bool) -> void:
	botao_enviar.disabled = ocupado or not _mestre.esta_pronto()


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
	if texto == "" or _mestre == null:
		return
	input_texto.text = ""

	if texto == "/nova":
		_mestre.nova_campanha()
		chat_historico.clear()
		_msg("Sistema", "Nova campanha. (Aperte F9 para reiniciar também o tabuleiro.)")
		_mestre.iniciar_aventura()
		return
	if texto == "/onde":
		_mostrar_cena()
		return
	if texto == "/ajuda":
		_msg("Sistema", "Comandos: /onde (resumo da cena), /notas (notas da IA), /nova (nova campanha). Enter envia, Shift+Enter pula linha. Esc ou clicar fora solta o chat.")
		return
	if texto == "/notas":
		var tab: Node = get_tree().get_first_node_in_group("tabuleiro")
		if tab != null:
			tab.debug_ativo = not tab.debug_ativo
			_msg("Sistema", "Notas da IA: " + ("ligadas" if tab.debug_ativo else "desligadas"))
		return

	if not _mestre.esta_pronto() or _mestre.esta_ocupado():
		return
	_msg("Você", texto)
	_mestre.jogador_agiu(texto)


func _msg(remetente: String, mensagem: String) -> void:
	var segura: String = mensagem.replace("[", "[lb]")
	chat_historico.append_text("\n[b]%s:[/b] %s" % [remetente, segura])
