extends Button

var meus_dados = {}
var gestor_referencia = null # Guarda a referência direta do gestor

func inicializar(dados: Dictionary, gestor) -> void:
	meus_dados = dados
	gestor_referencia = gestor # Recebe o gestor diretamente
	
	var lbl_nome = _procura_label(self, 0)
	var lbl_classe = _procura_label(self, 1)
	var avatar = _procura_texture(self)
	var barra = _procura_barra(self)

	if lbl_nome and dados.has("nome"): lbl_nome.text = dados["nome"]
	if lbl_classe and dados.has("classe"): lbl_classe.text = dados["classe"]
	if barra and dados.has("progresso"): barra.value = dados["progresso"]
		
	if avatar:
		avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if dados.has("imagem_texture") and dados["imagem_texture"]:
			avatar.texture = dados["imagem_texture"]
		else:
			avatar.texture = preload("res://texturas/icon.svg")

func _pressed() -> void:
	# Clica no cartão e avisa diretamente o gestor guardado
	if gestor_referencia and gestor_referencia.has_method("abrir_ficha_detalhada"):
		gestor_referencia.abrir_ficha_detalhada()

# --- Funções auxiliares ---
func _procura_label(no: Node, indice: int) -> Label:
	var labels = []
	_recolher_labels(no, labels)
	if labels.size() > indice: return labels[indice]
	return null

func _recolher_labels(no: Node, lista: Array) -> void:
	for filho in no.get_children():
		if filho is Label: lista.append(filho)
		_recolher_labels(filho, lista)

func _procura_texture(no: Node) -> TextureRect:
	for filho in no.get_children():
		if filho is TextureRect: return filho
		var res = _procura_texture(filho)
		if res: return res
	return null

func _procura_barra(no: Node) -> ProgressBar:
	for filho in no.get_children():
		if filho is ProgressBar: return filho
		var res = _procura_barra(filho)
		if res: return res
	return null
