extends VBoxContainer

const CARD_SCENE = preload("res://cenas/card_personagem.tscn")

@onready var container_grupo = $ContainerGrupo
@onready var container_inimigos = $ContainerInimigos
@onready var container_npcs = $ContainerNpcs

var fila_imagens = []
var indice_imagem = 0

var lista_dados_exemplo = [
	{"nome": "Kuzin", "classe": "Meio-Elfo Ladino Nível 3", "progresso": 80},
	{"nome": "Tharok", "classe": "Meio-Orc Bárbara Nível 5", "progresso": 100},
	{"nome": "Chefe Goblin", "classe": "Goblin Guerreiro Nível 2", "progresso": 45},
	{"nome": "Taberneiro Barnaby", "classe": "Humano Comerciante Nível 1", "progresso": 60},
	{"nome": "Lyra", "classe": "Elfa Mago Nível 4", "progresso": 90},
	{"nome": "Grimm", "classe": "Anão Clérigo Nível 4", "progresso": 75},
	{"nome": "Vex", "classe": "Tiefling Bruxo Nível 3", "progresso": 30},
	{"nome": "Serafina", "classe": "Humana Paladina Nível 6", "progresso": 100},
	{"nome": "Zul", "classe": "Orc Xamã Nível 5", "progresso": 55},
	{"nome": "Nyx", "classe": "Gnomo Artífice Nível 2", "progresso": 65}
]
var indice_dado = 0

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

	gerar_proximo("grupo")

func gerar_personagem(categoria: String, dados: Dictionary) -> void:
	if indice_imagem < fila_imagens.size():
		dados["imagem_texture"] = fila_imagens[indice_imagem]
		indice_imagem += 1
	else:
		dados["imagem_texture"] = preload("res://texturas/icon.svg")

	var novo_card = CARD_SCENE.instantiate()
	if novo_card.has_method("inicializar"):
		novo_card.inicializar(dados, self)
		
	match categoria.to_lower():
		"grupo": container_grupo.add_child(novo_card)
		"inimigos": container_inimigos.add_child(novo_card)
		"npc", "npcs": container_npcs.add_child(novo_card)

func gerar_proximo(categoria: String) -> void:
	if indice_dado < lista_dados_exemplo.size():
		var dados = lista_dados_exemplo[indice_dado]
		gerar_personagem(categoria, dados)
		indice_dado += 1
	else:
		gerar_personagem(categoria, {"nome": "Aventureiro " + str(indice_dado), "classe": "Desconhecido Nível 1", "progresso": 50})

func abrir_ficha_detalhada() -> void:
	# 1. Esconde o PainelEsquerdo por completo
	var painel_esquerdo = get_tree().root.find_child("PainelEsquerdo", true, false)
	if painel_esquerdo:
		painel_esquerdo.visible = false
	
	# 2. Torna visível o PainelFicha
	var painel_ficha = get_tree().root.find_child("PainelFicha", true, false)
	if painel_ficha:
		painel_ficha.visible = true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			gerar_proximo("grupo")
		elif event.keycode == KEY_2:
			gerar_proximo("inimigos")
		elif event.keycode == KEY_3:
			gerar_proximo("npcs")
