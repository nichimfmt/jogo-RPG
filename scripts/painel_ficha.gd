extends Panel

@onready var botao_voltar = $BotaoVoltar

func _ready() -> void:
	# O painel começa invisível ao arrancar
	visible = false
	
	if botao_voltar:
		# Força o botão a capturar o clique do rato
		botao_voltar.mouse_filter = Control.MOUSE_FILTER_STOP
		
		# Limpa conexões antigas e reconecta o sinal pressed
		if botao_voltar.pressed.is_connected(_on_voltar_pressed):
			botao_voltar.pressed.disconnect(_on_voltar_pressed)
		botao_voltar.pressed.connect(_on_voltar_pressed)

func _on_voltar_pressed() -> void:
	voltar_para_lista()

func voltar_para_lista() -> void:
	# 1. Oculta a ficha detalhada
	visible = false
	
	# 2. Reativa o PainelEsquerdo na raiz da árvore de cena
	var painel_esquerdo = get_tree().root.find_child("PainelEsquerdo", true, false)
	if painel_esquerdo:
		painel_esquerdo.visible = true
	else:
		print("ERRO: PainelEsquerdo não foi encontrado na árvore!")
