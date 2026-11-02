extends Node

@onready var lista_personagens = %ListasPersonagens
@onready var ficha_detalhada = %FichaDetalhada
@onready var card_kaelen = %CardKaelen
@onready var botao_voltar = %BotaoVoltar

func _ready():
	print("O botão voltar foi encontrado? ", botao_voltar)
	
	if lista_personagens:
		lista_personagens.show()
	if ficha_detalhada:
		ficha_detalhada.hide()
	
	if card_kaelen:
		card_kaelen.pressed.connect(_on_card_kaelen_pressed)
		
	if botao_voltar:
		botao_voltar.pressed.connect(_on_botao_voltar_pressed)

func _on_card_kaelen_pressed():
	lista_personagens.hide()
	ficha_detalhada.show()

func _on_botao_voltar_pressed() -> void:
	print("CLICOU NO BOTÃO VOLTAR!")
	ficha_detalhada.hide()
	lista_personagens.show()
