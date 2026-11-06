extends VBoxContainer
# Lista da esquerda: mostra os personagens da CENA ATUAL, divididos em GRUPO / INIMIGOS / NPCS.
# Os dados vêm do Tabuleiros.gd (grupo "tabuleiro"): ele avisa pelo sinal "personagens_mudaram"
# sempre que alguém entra, sai ou muda de vida, e os cards são refeitos.
#   jogador -> GRUPO | inimigo -> INIMIGOS | aliado e neutro -> NPCS

const CARD_SCENE = preload("res://cenas/card_personagem.tscn")

@onready var container_grupo = $ContainerGrupo
@onready var container_inimigos = $ContainerInimigos
@onready var container_npcs = $ContainerNpcs

var fila_imagens: Array = []
var imagem_por_nome: Dictionary = {}       # cada personagem mantém sempre a mesma imagem
var proxima_imagem: int = 0
var tabuleiro: Node = null


func _ready() -> void:
	var caminhos = [
		"res://kuzin.png",
		"res://elvis_ovo.png",
		"res://borba.jpg",
		"res://3c7e4487-5bbc-4e60-811a-ebdc67901841.png",
		"res://c426dbac-f2e8-456a-898f-65680105445c.png",
		"res://e115440b-e27c-4662-b9d3-b769def6240.png",
		"res://Captura_de_tela_2025-06-06_222312.png",
		"res://Captura_de_tela_2025-12-12_221657.png",
		"res://Captura_de_tela_20260515_000336.png",
		"res://Gemini_Generated_Image_8mkrdu8mkrdu8mkr.png",
		"res://Gemini_Generated_Image_79oh3g79oh3g79oh-removebg-preview.png",
		"res://Gemini_Generated_Image_r7dafyrdafyr7da.png"
	]
	for caminho in caminhos:
		if ResourceLoader.exists(caminho):
			fila_imagens.append(load(caminho))

	# O tabuleiro é criado junto com esta tela: espera um quadro para achá-lo
	await get_tree().process_frame
	tabuleiro = get_tree().get_first_node_in_group("tabuleiro")
	if tabuleiro != null:
		tabuleiro.personagens_mudaram.connect(reconstruir)
		reconstruir()
	else:
		print("conteudo_lista: o tabuleiro não foi encontrado.")


func _imagem_do(nome: String) -> Texture2D:
	if imagem_por_nome.has(nome):
		return imagem_por_nome[nome]
	var textura: Texture2D
	if proxima_imagem < fila_imagens.size():
		textura = fila_imagens[proxima_imagem]
		proxima_imagem += 1
	else:
		textura = preload("res://texturas/icon.svg")
	imagem_por_nome[nome] = textura
	return textura


# Apaga os cards e cria de novo, de acordo com o que existe no tabuleiro agora
func reconstruir() -> void:
	if tabuleiro == null:
		return
	for container in [container_grupo, container_inimigos, container_npcs]:
		for filho in container.get_children():
			filho.queue_free()

	for dados in tabuleiro.lista_para_painel():
		gerar_personagem(str(dados["categoria"]), dados)


func gerar_personagem(categoria: String, dados: Dictionary) -> void:
	dados["imagem_texture"] = _imagem_do(str(dados["nome"]))

	var novo_card = CARD_SCENE.instantiate()
	if novo_card.has_method("inicializar"):
		novo_card.inicializar(dados, self)

	match categoria.to_lower():
		"grupo": container_grupo.add_child(novo_card)
		"inimigos": container_inimigos.add_child(novo_card)
		_: container_npcs.add_child(novo_card)


func abrir_ficha_detalhada() -> void:
	# 1. Esconde o PainelEsquerdo por completo
	var painel_esquerdo = get_tree().root.find_child("PainelEsquerdo", true, false)
	if painel_esquerdo:
		painel_esquerdo.visible = false

	# 2. Torna visível o PainelFicha
	var painel_ficha = get_tree().root.find_child("PainelFicha", true, false)
	if painel_ficha:
		painel_ficha.visible = true
